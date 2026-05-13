/**
 * MotoGo24 — Edge Function: translate-document
 *
 * Překlad celých dokumentů (Velín → Dokumenty) do 6 cizích jazyků přes
 * Anthropic Claude API. Na rozdíl od `translate-content` (krátká CMS pole)
 * umí i:
 *   - vlastní dokumenty `custom_documents` typu `pdf` — PDF se pošle Claude
 *     přímo (document content block), výstupem je přeložený obsah jako HTML
 *     (na webu se cizojazyčná verze zobrazí jako HTML stránka, český originál
 *     PDF zůstává beze změny na české verzi);
 *   - vlastní dokumenty `custom_documents` typu `html` (RTE obsah);
 *   - smluvní šablony `document_templates` (VOP, smlouva, GDPR, protokoly) —
 *     `{placeholder}` proměnné zůstávají nepřeložené.
 *
 * Výsledek se uloží do JSONB sloupců cílové tabulky:
 *   custom_documents.translations          = { en: { title, description, content_html }, de: {...}, ... }
 *   document_templates.content_translations = { en: "<html>", de: "<html>", ... }   (čte ho RPC get_document_translation)
 *   document_templates.name_translations    = { en: "<název>", de: "<název>", ... }  (nadpis dokumentu na webu)
 *
 * POST /functions/v1/translate-document
 * Body: { table: 'custom_documents' | 'document_templates', id: string, target_langs?: string[] }
 * Odpověď: { success: true, translations: {...}, errors?: {...} }
 *
 * Bezpečnost: vyžaduje JWT (admin z Velínu) nebo service_role klíč.
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
// Pro kvalitu i délku výstupu (legal dokumenty mohou být desítky KB HTML)
// používáme Sonnet pro vše — haiku má nižší cap na max_tokens a horší
// instrukční stabilitu u dlouhého strukturovaného JSON.
const MODEL_TEXT = 'claude-sonnet-4-6'
const MODEL_PDF = 'claude-sonnet-4-6'
const MAX_TOKENS = 32000

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function uint8ToBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

function classifyAnthropicError(status: number, errText: string): { code: string, msg: string } {
  const lower = errText.toLowerCase()
  if (lower.includes('credit balance') && lower.includes('too low')) {
    return { code: 'insufficient_credits', msg: 'Anthropic API: kredit vyčerpán. Doplň na console.anthropic.com → Plans & Billing.' }
  }
  if (status === 401 || lower.includes('invalid x-api-key')) {
    return { code: 'invalid_api_key', msg: 'Anthropic API: neplatný API klíč (sekret ANTHROPIC_API_KEY).' }
  }
  if (status === 429) return { code: 'rate_limit', msg: 'Anthropic API: rate limit, zkus za chvíli.' }
  return { code: 'anthropic_error', msg: `Anthropic API ${status}: ${errText.slice(0, 300)}` }
}

function systemPrompt(langName: string, langCode: string, hasPlaceholders: boolean): string {
  return [
    `You are a professional Czech-to-${langName} legal/business document translator for MotoGo24 — a Czech motorcycle rental company.`,
    'You receive a document (as text and/or an attached PDF). Translate its full content into the target language.',
    'Output STRICTLY a single valid JSON object. No markdown fences, no commentary.',
    '',
    'OUTPUT JSON SHAPE:',
    '  { "title": "<translated document title, short>", "description": "<translated one-line description or empty string>", "content_html": "<full translated document body as clean semantic HTML>" }',
    '  (If the input does not contain a separate title/description, derive a sensible short title from the heading and leave description as "".)',
    '',
    'CONTENT_HTML RULES:',
    `- Language: ${langName} (${langCode}). Natural, native, fluent, faithful to the legal meaning.`,
    '- Produce clean HTML: <h1>/<h2>/<h3> for headings, <p> for paragraphs, <ul>/<ol>/<li> for lists, <strong>/<em> for emphasis, <table>/<tr>/<td> for tables. No inline style attributes unless essential. No <script>, no <iframe>, no event handlers.',
    '- Preserve the document structure, numbering of clauses, and order exactly.',
    '- DO NOT translate or change: URLs, email addresses, phone numbers, prices in Kč/EUR, IČO, DIČ, license plates (SPZ), VIN, brand names (Honda, Yamaha, BMW, Suzuki, Kawasaki, Ducati...), postal codes, GPS coordinates, dates in numeric form.',
    '- Keep the company name "MotoGo24" and Czech proper nouns / place names (Mezná, Pelhřimov, Vysočina, Praha) unchanged.',
    '- Keep currency "Kč" as is (not "CZK", not converted).',
    hasPlaceholders
      ? '- IMPORTANT: keep ALL template placeholders like {customer_name}, {today}, {{var}}, %s exactly as they are — do NOT translate, do NOT remove, do NOT change the braces.'
      : '- Keep any {placeholder} / {{var}} tokens unchanged if present.',
    '- Keep emoji unchanged.',
  ].join('\n')
}

interface SourceDoc {
  textFields: Record<string, string>   // CZ text fields shown to the model
  pdf?: { mediaType: string, dataB64: string }
  hasPlaceholders: boolean
}

async function buildSource(
  supabaseAdmin: ReturnType<typeof createClient>,
  table: string,
  row: Record<string, unknown>,
): Promise<SourceDoc> {
  if (table === 'custom_documents') {
    const kind = String(row.kind || 'html')
    if (kind === 'pdf') {
      const pdfPath = String(row.pdf_path || '')
      // pdf_path je veřejná URL .../storage/v1/object/public/media/<path> → vytáhneme <path>
      const m = pdfPath.match(/\/object\/public\/media\/(.+)$/)
      if (!m) throw new Error('PDF path není v bucketu media nebo má neočekávaný formát: ' + pdfPath)
      const storagePath = decodeURIComponent(m[1])
      const { data: blob, error: dlErr } = await supabaseAdmin.storage.from('media').download(storagePath)
      if (dlErr || !blob) throw new Error('Stažení PDF z storage selhalo: ' + (dlErr?.message || 'no data'))
      const bytes = new Uint8Array(await blob.arrayBuffer())
      if (bytes.length > 20 * 1024 * 1024) throw new Error('PDF je příliš velké pro překlad (max 20 MB).')
      return {
        textFields: {
          title: String(row.title || ''),
          description: String(row.description || ''),
        },
        pdf: { mediaType: 'application/pdf', dataB64: uint8ToBase64(bytes) },
        hasPlaceholders: false,
      }
    }
    return {
      textFields: {
        title: String(row.title || ''),
        description: String(row.description || ''),
        content_html: String(row.content_html || ''),
      },
      hasPlaceholders: /\{\{?\s*[a-z_]+\s*\}?\}/i.test(String(row.content_html || '')),
    }
  }
  // document_templates — překládá se obsah i název (název se ukládá do name_translations,
  // obsah do content_translations; web bere podle jazyka, jinak fallback na i18n).
  return {
    textFields: { name: String(row.name || ''), content_html: String(row.content_html || '') },
    hasPlaceholders: true,
  }
}

async function translateToLang(src: SourceDoc, langCode: string): Promise<Record<string, string>> {
  const langName = LANG_NAMES[langCode] || langCode
  const userContent: unknown[] = []
  if (src.pdf) {
    userContent.push({ type: 'document', source: { type: 'base64', media_type: src.pdf.mediaType, data: src.pdf.dataB64 } })
  }
  userContent.push({
    type: 'text',
    text: src.pdf
      ? `Translate the attached PDF document into ${langName}. Source metadata (Czech): ${JSON.stringify(src.textFields)}. Output the JSON object as specified.`
      : `Translate this Czech document into ${langName}. Input JSON: ${JSON.stringify(src.textFields)}. Output the JSON object as specified.`,
  })

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: src.pdf ? MODEL_PDF : MODEL_TEXT,
      max_tokens: MAX_TOKENS,
      system: systemPrompt(langName, langCode, src.hasPlaceholders),
      messages: [{ role: 'user', content: userContent }],
    }),
  })

  if (!response.ok) {
    const errText = await response.text()
    const { code, msg } = classifyAnthropicError(response.status, errText)
    const err = new Error(msg) as Error & { code?: string }
    err.code = code
    throw err
  }

  const data = await response.json()
  const stopReason = data?.stop_reason || ''
  let text = (data?.content?.[0]?.text || '').trim()
  // Odstraň markdown fence pokud je obalený (```json ... ``` nebo ``` ... ```).
  const fence = text.match(/^```(?:json)?\s*\n?([\s\S]*?)\n?```\s*$/)
  if (fence) text = fence[1].trim()
  let parsed: Record<string, unknown>
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    // Fallback: zkus vytáhnout JSON ze začátku/konce textu.
    const start = text.indexOf('{')
    const end = text.lastIndexOf('}')
    if (start === -1 || end === -1 || end <= start) {
      throw new Error(`Model nevrátil JSON (${langCode}, stop=${stopReason}, ${text.length} znaků): ${text.slice(0, 300)}`)
    }
    try {
      parsed = JSON.parse(text.slice(start, end + 1))
    } catch (e2) {
      const trunc = stopReason === 'max_tokens' ? ' [VÝSTUP USEKNUTÝ — max_tokens]' : ''
      throw new Error(`JSON parse failed (${langCode}, stop=${stopReason}${trunc}): ${(e2 as Error).message}; první 200 zn: ${text.slice(0, 200)}; posledních 200: ${text.slice(-200)}`)
    }
  }
  if (stopReason === 'max_tokens') {
    console.warn(`translate-document ${langCode}: model usekl výstup na max_tokens=${MAX_TOKENS} — překlad nemusí být kompletní`)
  }

  const out: Record<string, string> = {}
  for (const k of Object.keys(src.textFields)) {
    out[k] = typeof parsed[k] === 'string' ? parsed[k] as string : src.textFields[k]
  }
  // content_html může chybět ve zdroji u PDF (zdroj měl jen title/description) — vrať ho přesto
  if (!('content_html' in out) && typeof parsed.content_html === 'string') {
    out.content_html = parsed.content_html as string
  }
  return out
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    if (!ANTHROPIC_API_KEY) return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
    if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return jsonResponse({ error: 'Supabase env not configured' }, 500)

    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader.startsWith('Bearer ')) return jsonResponse({ error: 'Unauthorized' }, 401)
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const token = authHeader.replace('Bearer ', '')
    if (token !== SUPABASE_SERVICE_KEY) {
      const { data: { user }, error: userErr } = await supabaseAdmin.auth.getUser(token)
      if (userErr || !user) return jsonResponse({ error: 'Unauthorized: invalid token' }, 401)
    }

    const body = await req.json().catch(() => null)
    if (!body) return jsonResponse({ error: 'Invalid JSON body' }, 400)
    const table = String(body.table || '').trim()
    const id = String(body.id || '').trim()
    const targetLangs: string[] = Array.isArray(body.target_langs) && body.target_langs.length > 0
      ? body.target_langs.filter((l: unknown) => typeof l === 'string' && LANG_NAMES[l as string])
      : DEFAULT_LANGS
    if (table !== 'custom_documents' && table !== 'document_templates') return jsonResponse({ error: `Table not allowed: ${table}` }, 400)
    if (!id) return jsonResponse({ error: 'Missing id' }, 400)

    const { data: row, error: readErr } = await supabaseAdmin.from(table).select('*').eq('id', id).maybeSingle()
    if (readErr) return jsonResponse({ error: 'DB read failed: ' + readErr.message }, 500)
    if (!row) return jsonResponse({ error: 'Row not found' }, 404)

    let src: SourceDoc
    try {
      src = await buildSource(supabaseAdmin, table, row as Record<string, unknown>)
    } catch (e) {
      return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 400)
    }
    const hasContent = Object.values(src.textFields).some(v => v.trim().length > 0) || !!src.pdf
    if (!hasContent) return jsonResponse({ success: true, translations: {}, skipped: 'no_content' })

    // Sekvenčně (PDF requesty jsou velké — vyhneme se rate-limitu); textové bychom mohli paralelně, ale držíme to jednotně.
    const translations: Record<string, Record<string, string>> = {}
    const errors: Record<string, string> = {}
    for (const lang of targetLangs) {
      try {
        translations[lang] = await translateToLang(src, lang)
      } catch (e) {
        errors[lang] = e instanceof Error ? e.message : String(e)
        console.error(`translate-document ${table}/${id} ${lang} failed:`, errors[lang])
      }
    }
    if (Object.keys(translations).length === 0) return jsonResponse({ error: 'All translations failed', details: errors }, 502)

    // Uložení:
    //  - custom_documents → JSONB `translations` = { lang: { title, description, content_html } }
    //  - document_templates → `content_translations` = { lang: "<html>" } (RPC get_document_translation)
    //                       + `name_translations`    = { lang: "<přeložený název>" }
    const mergeJsonb = (col: string, valueFor: (t: Record<string, string>) => unknown) => {
      const existing = (row as Record<string, unknown>)[col]
      const m: Record<string, unknown> = (existing && typeof existing === 'object') ? { ...existing as Record<string, unknown> } : {}
      for (const [lang, t] of Object.entries(translations)) m[lang] = valueFor(t)
      return m
    }
    let updatePayload: Record<string, unknown>
    if (table === 'document_templates') {
      updatePayload = {
        content_translations: mergeJsonb('content_translations', t => t.content_html || ''),
        name_translations: mergeJsonb('name_translations', t => t.name || ''),
      }
    } else {
      updatePayload = { translations: mergeJsonb('translations', t => t) }
    }
    const { error: updErr } = await supabaseAdmin.from(table).update(updatePayload).eq('id', id)
    if (updErr) return jsonResponse({ error: 'DB update failed: ' + updErr.message }, 500)

    return jsonResponse({ success: true, translations, ...(Object.keys(errors).length ? { errors } : {}) })
  } catch (e) {
    console.error('translate-document fatal:', e)
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})
