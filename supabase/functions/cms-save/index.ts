/**
 * MotoGo24 — Edge Function: cms-save
 *
 * Inline ukládání CMS textů přímo z webu motogo24.com (admin overlay).
 * Auth není přes Supabase JWT — uživatel není přihlášen k Supabase. Místo toho
 * posíláme `cms_admin_token` z `app_settings`, který si Velín admin předtím
 * nastavil cookie přes /index.php?cms_admin=<token>. Edge funkce token ověří
 * proti DB (timing-safe), uloží hodnotu do `cms_variables` (přes service_role,
 * obejde RLS) a fire-and-forget zavolá `translate-content` pro auto-překlad
 * do EN/DE/ES/FR/NL/PL.
 *
 * POST /functions/v1/cms-save
 * Body:
 *   {
 *     token: string,    // cms_admin_token z app_settings
 *     key:   string,    // např. "web.home.hero.body" (musí začínat "web." a obsahovat aspoň 2 segmenty)
 *     value: string,    // nová hodnota (textová — JSONB string)
 *   }
 * Odpověď:
 *   { success: true, key, translation: 'queued' | 'skipped' }
 *
 * Bezpečnost:
 *   - Token validace přes timingSafeEqual (proti time-attack na app_settings token).
 *   - Whitelist klíčů: musí začínat `web.` (zamezuje přepsání systémových rows).
 *   - Max délka klíče 200, max délka value 16 KB.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const KEY_RE = /^web\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$/
const MAX_VALUE_BYTES = 16 * 1024

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

/** Timing-safe porovnání 2 stringů (zabráni měření timing pro odhad správného tokenu). */
function timingSafeEqual(a: string, b: string): boolean {
  if (typeof a !== 'string' || typeof b !== 'string') return false
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

async function fetchAdminToken(sb: SupabaseClient): Promise<string | null> {
  const { data, error } = await sb.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
  if (error || !data) return null
  const v = data.value
  // jsonb string se vrací jako primitiva — node-postgrest deserializuje sám
  if (typeof v === 'string') return v
  return null
}

/** Fire-and-forget zavolání translate-content (admin nečeká na překlad). */
async function triggerTranslate(rowId: string, value: string): Promise<'queued' | 'skipped'> {
  if (!value || typeof value !== 'string' || value.trim().length === 0) return 'skipped'
  try {
    // translate-content vyžaduje JWT — service_role je validní JWT.
    fetch(`${SUPABASE_URL}/functions/v1/translate-content`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        table: 'cms_variables',
        id: rowId,
        fields: { value },
      }),
    }).catch(() => { /* fire-and-forget */ })
    return 'queued'
  } catch {
    return 'skipped'
  }
}

serve(async (req: Request): Promise<Response> => {
  // Diagnostika — viditelné v Supabase Dashboard → Functions → cms-save → Logs.
  // Pomáhá odhalit, jaká metoda/headers/URL skutečně dorazí (např. když proxy
  // přepíše POST na GET nebo když některý prohlížeč pošle před POST nějaký
  // prefetch / SW-intercept).
  console.log('[cms-save] req', {
    method: req.method,
    url: req.url,
    has_auth: !!req.headers.get('authorization'),
    has_apikey: !!req.headers.get('apikey'),
    content_type: req.headers.get('content-type'),
    user_agent: req.headers.get('user-agent'),
  })

  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  // GET/HEAD bez body — vrátíme 200 health stub (některé prohlížeče/proxy
  // dělají prefetch a potřebují non-error odpověď). Save logika běží jen
  // pro POST (níže).
  if (req.method === 'GET' || req.method === 'HEAD') {
    return jsonResponse({ ok: true, fn: 'cms-save', method: req.method })
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed', method: req.method }, 405)
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return jsonResponse({ error: 'env_not_configured' }, 500)
  }

  let body: { token?: string; key?: string; value?: unknown }
  try {
    body = await req.json()
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400)
  }

  const { token, key } = body
  const value = body.value
  if (!token || typeof token !== 'string') return jsonResponse({ error: 'missing_token' }, 400)
  if (!key || typeof key !== 'string') return jsonResponse({ error: 'missing_key' }, 400)
  if (key.length > 200 || !KEY_RE.test(key)) return jsonResponse({ error: 'invalid_key' }, 400)
  if (typeof value !== 'string') return jsonResponse({ error: 'value_must_be_string' }, 400)
  if (new TextEncoder().encode(value).length > MAX_VALUE_BYTES) {
    return jsonResponse({ error: 'value_too_large', max_bytes: MAX_VALUE_BYTES }, 413)
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false } })

  // 1) Ověř token proti app_settings.cms_admin_token
  const expected = await fetchAdminToken(sb)
  if (!expected) return jsonResponse({ error: 'token_not_configured' }, 503)
  if (!timingSafeEqual(expected, token)) return jsonResponse({ error: 'invalid_token' }, 403)

  // 2) Select existing row by key, then UPDATE or INSERT.
  // Důvod: upsert s onConflict='key' selhával na 500 (zřejmě kvůli kombinaci
  // existujícího řádku s jinou category + RLS / select po insertu). Explicitní
  // větvení je transparentnější a chyba z PG se snadno propaguje na klienta.
  // Schema: id (uuid PK, default), key (text NOT NULL UNIQUE), value (jsonb NOT NULL),
  //         category (text NOT NULL), translations (jsonb NOT NULL default '{}'), updated_*.
  // Pozn.: záměrně NE-používáme `.maybeSingle()` — pokud z nějakého důvodu
  // existují duplikáty (nebo `key` ztratil UNIQUE constraint), maybeSingle()
  // vyhodí 406 a uživatel uvidí 500. `limit(1)` zaručí, že vždycky dostaneme
  // max 1 řádek a aktualizujeme ho.
  const { data: existingRows, error: selErr } = await sb
    .from('cms_variables')
    .select('id')
    .eq('key', key)
    .limit(1)

  if (selErr) {
    return jsonResponse({
      error: 'select_failed',
      detail: selErr.message,
      code: (selErr as { code?: string }).code || null,
      hint: (selErr as { hint?: string }).hint || null,
    }, 500)
  }

  const existing = Array.isArray(existingRows) && existingRows.length > 0 ? existingRows[0] : null
  let rowId: string | null = existing?.id ?? null

  if (existing?.id) {
    // UPDATE — neměníme category, abychom nepřemazali ručně nastavenou hodnotu
    // ve Velíně (např. 'general' / 'content'). Pouze hodnotu.
    const { error: updErr } = await sb
      .from('cms_variables')
      .update({ value })
      .eq('id', existing.id)
    if (updErr) {
      return jsonResponse({
        error: 'update_failed',
        detail: updErr.message,
        code: (updErr as { code?: string }).code || null,
        hint: (updErr as { hint?: string }).hint || null,
      }, 500)
    }
  } else {
    // INSERT — `select().single()` po insertu vyžaduje RLS/representation,
    // proto raději děláme nahý insert + samostatný select pro id.
    const { error: insErr } = await sb
      .from('cms_variables')
      .insert({ key, value, category: 'web' })
    if (insErr) {
      return jsonResponse({
        error: 'insert_failed',
        detail: insErr.message,
        code: (insErr as { code?: string }).code || null,
        hint: (insErr as { hint?: string }).hint || null,
      }, 500)
    }
    const { data: insRows } = await sb
      .from('cms_variables')
      .select('id')
      .eq('key', key)
      .limit(1)
    rowId = (Array.isArray(insRows) && insRows.length > 0) ? insRows[0].id : null
  }

  // 3) Fire-and-forget auto-překlad (admin nečeká)
  const translation = rowId ? await triggerTranslate(rowId, value) : 'skipped'

  return jsonResponse({ success: true, key, id: rowId, translation })
})
