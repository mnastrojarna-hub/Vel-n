/**
 * MotoGo24 — Edge Function: translate-content
 *
 * Auto-překlad textů zadávaných přes Velín pro veřejný web (motogo24.cz).
 * Volá Anthropic Claude API (claude-haiku-4-5-20251001), překládá zadaná pole
 * z češtiny do 6 cizích jazyků (en, de, es, fr, nl, pl) a UPDATEuje sloupec
 * `translations` v cílové tabulce přes service_role.
 *
 * POST /functions/v1/translate-content
 * Body:
 *   {
 *     table: 'cms_pages' | 'cms_variables' | 'products' | 'motorcycles' | 'branches',
 *     id: string,                        // PK řádku
 *     fields: { [name]: string },        // pole k přeložení (CZ text)
 *     target_langs?: string[],           // default ['en','de','es','fr','nl','pl']
 *     id_column?: string,                // default 'id'
 *   }
 * Odpověď:
 *   { success: true, translations: { en: {...}, de: {...}, ... } }
 *
 * Bezpečnost: vyžaduje JWT (any authenticated user — admin volá z Velínu).
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

const ALLOWED_TABLES = new Set(['cms_pages', 'cms_variables', 'products', 'motorcycles', 'branches'])
const MODEL = 'claude-haiku-4-5-20251001'

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function buildSystemPrompt(targetLang: string, langName: string): string {
  return [
    `You are a professional Czech-to-${langName} translator for MotoGo24 — a Czech motorcycle rental company.`,
    'Translate the provided JSON object of Czech text fields. Output STRICTLY a valid JSON object with the same keys and translated values.',
    '',
    'STRICT RULES:',
    `- Output language: ${langName} (${targetLang}). Natural, native, fluent.`,
    '- Preserve ALL HTML tags, attributes, structure, and inline formatting EXACTLY (e.g. <p>, <h2>, <strong>, <a href="...">, <ul>, <li>, <img>, <br>).',
    '- DO NOT translate or change: URLs, email addresses, phone numbers, prices in Kč/EUR, IČO, DIČ, license plates (SPZ), VIN, brand names (Honda, Yamaha, BMW, Suzuki, Kawasaki, Ducati...), product SKUs, postal codes, GPS coordinates, hashtags, code snippets.',
    '- Keep the company name "MotoGo24" unchanged.',
    '- Keep currency "Kč" as is (not "CZK", not converted).',
    '- Keep Czech proper nouns and place names (Mezná, Vysočina, Praha) unchanged.',
    '- Keep template placeholders like {placeholder}, {{var}}, %s, %d unchanged.',
    '- Keep emoji unchanged.',
    '- For very short fields (single words like "Vyber motorku") translate naturally and concisely.',
    '- Do NOT add commentary, do NOT add markdown fences, do NOT wrap in objects. Output ONLY the raw JSON object.',
    '',
    'Example input:  {"title":"Tipy pro bezpečnou jízdu","content":"<p>Vždy noste přilbu.</p>"}',
    `Example output: {"title":"...","content":"<p>...</p>"}`,
  ].join('\n')
}

async function translateToLang(fields: Record<string, string>, lang: string): Promise<Record<string, string>> {
  const langName = LANG_NAMES[lang] || lang
  const userPayload = JSON.stringify(fields)
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 4096,
      system: buildSystemPrompt(lang, langName),
      messages: [{ role: 'user', content: userPayload }],
    }),
  })

  if (!response.ok) {
    const errText = await response.text()
    throw new Error(`Anthropic API ${response.status}: ${errText.slice(0, 300)}`)
  }

  const data = await response.json()
  const text = (data?.content?.[0]?.text || '').trim()
  // Tolerantní parsování: pokud model přidá fences nebo whitespace, stáhneme JSON blok.
  let parsed: Record<string, string>
  try {
    parsed = JSON.parse(text)
  } catch {
    const start = text.indexOf('{')
    const end = text.lastIndexOf('}')
    if (start === -1 || end === -1 || end <= start) {
      throw new Error(`Invalid JSON from model (${lang}): ${text.slice(0, 200)}`)
    }
    parsed = JSON.parse(text.slice(start, end + 1))
  }

  // Sanity check: výstup musí být objekt se stejnými klíči (povolíme chybějící, doplníme původní hodnotou).
  const out: Record<string, string> = {}
  for (const k of Object.keys(fields)) {
    out[k] = typeof parsed[k] === 'string' ? parsed[k] : fields[k]
  }
  return out
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    if (!ANTHROPIC_API_KEY) return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
    if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return jsonResponse({ error: 'Supabase env not configured' }, 500)

    // JWT ověření — Velín admin volá s anon JWT; service role ale potřebujeme pro update.
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader.startsWith('Bearer ')) return jsonResponse({ error: 'Unauthorized' }, 401)

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userErr } = await supabaseAdmin.auth.getUser(token)
    if (userErr || !user) return jsonResponse({ error: 'Unauthorized: invalid token' }, 401)

    const body = await req.json().catch(() => null)
    if (!body) return jsonResponse({ error: 'Invalid JSON body' }, 400)

    const table = String(body.table || '').trim()
    const id = String(body.id || '').trim()
    const idColumn = String(body.id_column || 'id').trim()
    const rawFields = body.fields && typeof body.fields === 'object' ? body.fields as Record<string, unknown> : null
    const targetLangs: string[] = Array.isArray(body.target_langs) && body.target_langs.length > 0
      ? body.target_langs.filter((l: unknown) => typeof l === 'string')
      : DEFAULT_LANGS

    if (!ALLOWED_TABLES.has(table)) return jsonResponse({ error: `Table not allowed: ${table}` }, 400)
    if (!id) return jsonResponse({ error: 'Missing id' }, 400)
    if (!rawFields) return jsonResponse({ error: 'Missing fields' }, 400)

    // Filtrujeme: jen non-empty stringy. Prázdná pole nepřekládáme (mrhání tokeny).
    const fields: Record<string, string> = {}
    for (const [k, v] of Object.entries(rawFields)) {
      if (typeof v === 'string' && v.trim().length > 0) fields[k] = v
    }
    if (Object.keys(fields).length === 0) {
      return jsonResponse({ success: true, translations: {}, skipped: 'no_text' })
    }

    // Paralelně přeložit do všech jazyků.
    const results = await Promise.allSettled(
      targetLangs.map(async (lang) => ({ lang, translated: await translateToLang(fields, lang) }))
    )

    const translations: Record<string, Record<string, string>> = {}
    const errors: Record<string, string> = {}
    for (const r of results) {
      if (r.status === 'fulfilled') {
        translations[r.value.lang] = r.value.translated
      } else {
        const reason = r.reason instanceof Error ? r.reason.message : String(r.reason)
        // jazyk nepoznáme přesně — zalogujeme jen text
        errors[`unknown_${Object.keys(errors).length}`] = reason
        console.error('translate-content lang failed:', reason)
      }
    }

    if (Object.keys(translations).length === 0) {
      return jsonResponse({ error: 'All translations failed', details: errors }, 502)
    }

    // Načti existující translations a zmerguj (zachová pole, která neaktualizujeme).
    const { data: existingRow, error: readErr } = await supabaseAdmin
      .from(table)
      .select('translations')
      .eq(idColumn, id)
      .maybeSingle()

    if (readErr) {
      return jsonResponse({ error: 'DB read failed: ' + readErr.message }, 500)
    }
    if (!existingRow) {
      return jsonResponse({ error: `Row not found: ${table}.${idColumn}=${id}` }, 404)
    }

    const existing = (existingRow as { translations?: Record<string, Record<string, string>> }).translations || {}
    const merged: Record<string, Record<string, string>> = { ...existing }
    for (const [lang, trans] of Object.entries(translations)) {
      merged[lang] = { ...(existing[lang] || {}), ...trans }
    }

    const { error: updErr } = await supabaseAdmin
      .from(table)
      .update({ translations: merged })
      .eq(idColumn, id)

    if (updErr) {
      return jsonResponse({ error: 'DB update failed: ' + updErr.message }, 500)
    }

    return jsonResponse({
      success: true,
      languages: Object.keys(translations),
      failed: Object.keys(errors).length > 0 ? errors : undefined,
    })
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('translate-content error:', msg)
    return jsonResponse({ error: msg }, 500)
  }
})
