/**
 * MotoGo24 — Edge Function: translate-pages-master
 *
 * Auto-překlad CS masteru velkých CMS stránek do 6 jazyků a uložení
 * do `app_settings.pages_overlay.<page>.<lang>` (JSONB strom).
 *
 * Dva módy provozu:
 *
 * 1) `{action: 'list'}` — rychle (žádné Anthropic volání): vrací pole
 *    všech kombinací {page, lang}, které je třeba přeložit.
 *    Klient (Velín) z toho udělá frontu a volá `action:'translate-one'`
 *    sekvenčně/paralelně. Tím se vyhneme timeoutu edge fn.
 *
 * 2) `{action: 'translate-one', page, lang}` — přeloží JEDNU dvojici.
 *    Trvá typicky 3-8 s. Vrací uloženou hodnotu.
 *
 * V obou případech se master fetchuje z public PHP endpointu
 * `https://motogo24.cz/api/master.php?token=<cms_admin_token>`
 * (volitelně přepsatelné přes `master_url`).
 *
 * Bezpečnost: vyžaduje JWT (admin volá z Velínu).
 * Sekret: ANTHROPIC_API_KEY.
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DEFAULT_LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl']
const LANG_NAMES: Record<string, string> = {
  en: 'English',
  de: 'German (Deutsch)',
  es: 'Spanish (Español)',
  fr: 'French (Français)',
  nl: 'Dutch (Nederlands)',
  pl: 'Polish (Polski)',
}

const DEFAULT_MASTER_URLS = [
  'https://motogo24.cz/api/master.php',
  'https://motogo24.com/api/master.php',
]
const MODEL = 'claude-haiku-4-5-20251001'

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function buildSystemPrompt(targetLang: string, langName: string): string {
  return [
    `You are a professional Czech-to-${langName} translator for MotoGo24 — a Czech motorcycle rental company.`,
    'Translate the provided JSON tree of Czech text values. Output STRICTLY a valid JSON object with the SAME structure (same keys, same array nesting, same array indices) and translated string values.',
    '',
    'STRICT RULES:',
    `- Output language: ${langName} (${targetLang}). Natural, native, fluent.`,
    '- Preserve ALL HTML tags, attributes, structure, inline formatting EXACTLY (e.g. <p>, <h2>, <strong>, <a href="...">, <ul>, <li>, <img>, <br>).',
    '- DO NOT translate or change: URLs (incl. /jak-pujcit/...), email addresses, phone numbers, prices in Kč/EUR, IČO, DIČ, SPZ, VIN, brand names (Honda, Yamaha, BMW, Suzuki, Kawasaki, Ducati...), product SKUs, postal codes, GPS coordinates, file paths to icons (gfx/...svg), CSS classes (btn, btndark, btngreen, gr2, gr4, pulse, ...).',
    '- ARIA labels (aria, aria-label keys) MUST be translated.',
    '- Keep the company name "MotoGo24" unchanged.',
    '- Keep currency "Kč" as is (not "CZK", not converted).',
    '- Keep Czech proper nouns and place names (Mezná, Vysočina, Praha, Pelhřimov) unchanged.',
    '- Keep template placeholders like {placeholder}, {{var}}, %s, %d unchanged.',
    '- DO NOT translate keys, only values. Keep all booleans, numbers, nulls intact.',
    '- For arrays-of-objects (e.g. process steps, FAQ items), preserve the array order and length.',
    '- Do NOT add commentary, do NOT add markdown fences. Output ONLY the raw JSON object.',
  ].join('\n')
}

async function fetchMaster(masterUrls: string[], sb: ReturnType<typeof createClient>, page?: string): Promise<{
  pages: Record<string, unknown>,
}> {
  const { data: tokRow } = await sb.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
  const cmsAdminToken = typeof tokRow?.value === 'string' ? tokRow.value : (tokRow?.value ?? '')
  if (!cmsAdminToken) throw new Error('cms_admin_token missing in app_settings')
  const errors: string[] = []
  for (const baseUrl of masterUrls) {
    const url = `${baseUrl}?token=${encodeURIComponent(String(cmsAdminToken))}` + (page ? `&page=${encodeURIComponent(page)}` : '')
    try {
      const res = await fetch(url, { redirect: 'follow' })
      if (!res.ok) {
        errors.push(`${baseUrl}: HTTP ${res.status}`)
        continue
      }
      const json = await res.json()
      return { pages: json?.pages || {} }
    } catch (e) {
      errors.push(`${baseUrl}: ${(e as Error).message}`)
    }
  }
  throw new Error(`master fetch failed (tried ${masterUrls.length} URL${masterUrls.length === 1 ? '' : 's'}): ${errors.join(' | ')}`)
}

async function translateTree(tree: unknown, lang: string): Promise<unknown> {
  const langName = LANG_NAMES[lang] || lang
  const userPayload = JSON.stringify(tree)
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8192,
      system: buildSystemPrompt(lang, langName),
      messages: [{ role: 'user', content: userPayload }],
    }),
  })
  if (!response.ok) {
    const errText = await response.text()
    throw new Error(`Anthropic ${response.status}: ${errText.slice(0, 300)}`)
  }
  const data = await response.json()
  const text = (data?.content?.[0]?.text || '').trim()
  try {
    return JSON.parse(text)
  } catch {
    const start = text.indexOf('{')
    const end = text.lastIndexOf('}')
    if (start === -1 || end === -1 || end <= start) {
      throw new Error(`Invalid JSON from model (${lang}): ${text.slice(0, 200)}`)
    }
    return JSON.parse(text.slice(start, end + 1))
  }
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : ''
    if (!token) return jsonResponse({ error: 'unauthorized' }, 401)
    const { data: { user } } = await sb.auth.getUser(token)
    if (!user) return jsonResponse({ error: 'unauthorized' }, 401)

    const body = await req.json().catch(() => ({}))
    const action = body.action || 'list'
    // Override priority: body.master_url > app_settings.master_url > built-in defaults (.cz, .com)
    const { data: urlRow } = await sb.from('app_settings').select('value').eq('key', 'master_url').maybeSingle()
    const settingMasterUrl = typeof urlRow?.value === 'string' ? urlRow.value : (urlRow?.value ?? '')
    const masterUrls: string[] = body.master_url
      ? [String(body.master_url)]
      : (settingMasterUrl ? [String(settingMasterUrl), ...DEFAULT_MASTER_URLS] : DEFAULT_MASTER_URLS)
    const targetLangs: string[] = Array.isArray(body.target_langs) && body.target_langs.length
      ? body.target_langs.filter((l: string) => LANG_NAMES[l])
      : DEFAULT_LANGS

    if (action === 'list') {
      const { pages } = await fetchMaster(masterUrls, sb)
      const wantPages: string[] | null = Array.isArray(body.pages) && body.pages.length ? body.pages : null
      const pageKeys = wantPages ? wantPages.filter(p => pages[p]) : Object.keys(pages)
      const queue: Array<{ page: string, lang: string }> = []
      for (const p of pageKeys) for (const l of targetLangs) queue.push({ page: p, lang: l })
      return jsonResponse({ success: true, queue, pages: pageKeys, langs: targetLangs })
    }

    if (action === 'translate-one') {
      if (!ANTHROPIC_API_KEY) return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
      const page = String(body.page || '')
      const lang = String(body.lang || '')
      if (!page || !LANG_NAMES[lang]) return jsonResponse({ error: 'invalid page or lang' }, 400)

      const { pages } = await fetchMaster(masterUrls, sb, page)
      const masterTree = pages[page]
      if (!masterTree) return jsonResponse({ error: `unknown page: ${page}` }, 404)

      const translated = await translateTree(masterTree, lang)
      const settingKey = `pages_overlay.${page}.${lang}`
      const { error: upErr } = await sb
        .from('app_settings')
        .upsert({ key: settingKey, value: translated, updated_at: new Date().toISOString() }, { onConflict: 'key' })
      if (upErr) return jsonResponse({ error: upErr.message }, 500)

      return jsonResponse({ success: true, page, lang, key: settingKey })
    }

    return jsonResponse({ error: `unknown action: ${action}` }, 400)
  } catch (e) {
    return jsonResponse({ error: (e as Error).message }, 500)
  }
})
