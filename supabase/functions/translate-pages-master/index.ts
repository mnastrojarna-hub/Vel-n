/**
 * MotoGo24 — Edge Function: translate-pages-master
 *
 * Auto-překlad CS masteru velkých CMS stránek (jak_pujcit_*, home, pujcovna, …)
 * do 6 jazyků a uložení do `app_settings` pod klíče `pages_overlay.<page>.<lang>`.
 *
 * Master CS strom se načte z public PHP endpointu motogo-web-php
 * `https://motogo24.cz/api/master.php?token=<cms_admin_token>` — buď celý naráz
 * nebo per-page přes `&page=<slug>`.
 *
 * Klient (Velín tlačítko) volá:
 *   POST /functions/v1/translate-pages-master
 *   Body: {
 *     pages?: string[],          // konkrétní slugy; default: všechny vrácené /api/master.php
 *     target_langs?: string[],   // default ['en','de','es','fr','nl','pl']
 *     master_url?: string,       // override (default: https://motogo24.cz/api/master.php)
 *   }
 *
 * Odpověď:
 *   { success: true, processed: [{page, lang, status, error?}], total }
 *
 * Bezpečnost: vyžaduje JWT (admin volá z Velínu). cms_admin_token autorizuje
 * fetch masteru z PHP endpointu.
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

const DEFAULT_MASTER_URL = 'https://motogo24.cz/api/master.php'
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
    if (!ANTHROPIC_API_KEY) return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // JWT auth — vyžaduje admina ve Velíně
    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : ''
    if (!token) return jsonResponse({ error: 'unauthorized' }, 401)
    const { data: { user } } = await sb.auth.getUser(token)
    if (!user) return jsonResponse({ error: 'unauthorized' }, 401)

    const body = await req.json().catch(() => ({}))
    const targetLangs: string[] = Array.isArray(body.target_langs) && body.target_langs.length
      ? body.target_langs.filter((l: string) => LANG_NAMES[l])
      : DEFAULT_LANGS
    const masterUrl = body.master_url || DEFAULT_MASTER_URL
    const wantPages: string[] | null = Array.isArray(body.pages) && body.pages.length ? body.pages : null

    // Načti cms_admin_token z app_settings → autorizuje fetch /api/master.php
    const { data: tokRow } = await sb.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
    const cmsAdminToken = typeof tokRow?.value === 'string' ? tokRow.value : (tokRow?.value ?? '')
    if (!cmsAdminToken) return jsonResponse({ error: 'cms_admin_token missing in app_settings' }, 500)

    // Fetch master
    const masterRes = await fetch(`${masterUrl}?token=${encodeURIComponent(String(cmsAdminToken))}`)
    if (!masterRes.ok) {
      return jsonResponse({ error: `master fetch failed: HTTP ${masterRes.status}` }, 502)
    }
    const masterJson = await masterRes.json()
    const allPages: Record<string, unknown> = masterJson?.pages || {}
    const pageKeys = wantPages ? wantPages.filter(p => allPages[p]) : Object.keys(allPages)

    const processed: Array<{ page: string, lang: string, status: 'ok' | 'error', error?: string }> = []
    for (const page of pageKeys) {
      const masterTree = allPages[page]
      for (const lang of targetLangs) {
        try {
          const translated = await translateTree(masterTree, lang)
          // Upsert do app_settings
          const settingKey = `pages_overlay.${page}.${lang}`
          const { error: upErr } = await sb
            .from('app_settings')
            .upsert({ key: settingKey, value: translated, updated_at: new Date().toISOString() }, { onConflict: 'key' })
          if (upErr) throw new Error(upErr.message)
          processed.push({ page, lang, status: 'ok' })
        } catch (e) {
          processed.push({ page, lang, status: 'error', error: (e as Error).message })
        }
      }
    }

    return jsonResponse({
      success: true,
      total: processed.length,
      ok: processed.filter(p => p.status === 'ok').length,
      errors: processed.filter(p => p.status === 'error').length,
      processed,
    })
  } catch (e) {
    return jsonResponse({ error: (e as Error).message }, 500)
  }
})
