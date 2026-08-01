// pdf-to-html — převod nahraného PDF na čisté sémantické HTML přes Claude
// (document content block, stejný mechanismus jako translate-document u PDF).
//
// Slouží Velín → Dokumenty → Smluvní texty: admin nahraje PDF s novým zněním
// (VOP, nájemní smlouva, protokoly, GDPR), funkce vrátí obsah jako HTML,
// který se předvyplní do editačního modalu a uloží STÁVAJÍCÍ cestou do
// document_templates.content_html. Veškerá navazující funkčnost (překlady,
// generování dokumentů k rezervacím, mailové přílohy) tak zůstává beze změny.
//
// Dlouhá PDF (> CHUNK_PAGES stran) se dělí přes pdf-lib na části po stránkách
// a převádí PARALELNĚ — jeden celokusový request na dlouhém dokumentu generuje
// i několik minut a narazí na wall-clock limit edge funkce. Přechodné chyby
// (429/5xx/síť) se opakují s backoffem. Selhání i úspěch se zapisují do
// `debug_log` (component 'pdf-to-html') pro diagnostiku z Velína.
//
// JEN převod — žádný zápis do document_templates. Vlastní ověření admina →
// verify_jwt=false.
//
// POST body: { pdf_base64: string }
// Odpověď:  { success: true, html, pages?, chunks? } | { success: false, error }
import { corsResponse, jsonResponse } from '../_shared/cors.ts'
import { requireAdminOrService } from '../_shared/auth.ts'
import { PDFDocument } from 'npm:pdf-lib@1.17.1'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const MODEL = 'claude-sonnet-4-6'
const MAX_TOKENS_PER_CALL = 20000
const CHUNK_PAGES = 8        // ≤ tolik stran = jeden request; víc = dělení po CHUNK_PAGES
const CHUNK_CONCURRENCY = 3
const MAX_PAGES = 60
// 10 MB PDF ≈ 13,7 M znaků base64
const MAX_BASE64_CHARS = 14_000_000

const SYSTEM_PROMPT = [
  'You convert a Czech legal/business PDF document (rental terms, contract, handover/damage protocol, GDPR consent) into clean semantic HTML for a WYSIWYG editor.',
  '',
  'TEXT RULES — ABSOLUTE:',
  '- Preserve 100% of the document text VERBATIM, in the original Czech. Every sentence, clause, clause number, definition, list item, table cell and footnote must appear in the output exactly as written.',
  '- Do NOT translate, summarize, paraphrase, reorder, omit or add ANY text.',
  '- Keep all numbers, prices, dates, IČO/DIČ, e-mails, URLs, phone numbers exactly as printed.',
  '- Keep any template placeholders like {{customer_name}} or {today} exactly as they are, including the braces.',
  '- The ONLY text you may drop: repeated running page headers/footers and bare page numbers (e.g. "Strana 2/8") that merely repeat on every page.',
  '',
  'HTML RULES:',
  '- Output clean semantic HTML fragment (no <html>/<head>/<body> wrapper): <h1>/<h2>/<h3> for headings by visual hierarchy, <p> for paragraphs, <ul>/<ol>/<li> for lists, <table>/<tr>/<th>/<td> for tables, <strong>/<em>/<u> for visible emphasis.',
  '- Numbered clauses that are part of the text (e.g. "1.1 Nájemce se zavazuje…") keep their numbers in the text — do not convert them to <ol> numbering that would drop the literal numbers.',
  '- No inline style attributes unless essential (e.g. text-align for a centered title). No <script>, no <iframe>, no event handlers, no images.',
  '- Merge lines broken only by PDF line-wrapping into full paragraphs; keep genuine paragraph breaks.',
].join('\n')

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes
}

function uint8ToBase64(bytes: Uint8Array): string {
  let binary = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

// Best-effort zápis do debug_log — diagnostika viditelná z Velína.
async function logDb(status: string, errorMessage: string | null, data: Record<string, unknown>, durationMs: number) {
  try {
    if (!SUPABASE_URL || !SERVICE_KEY) return
    const admin = createClient(SUPABASE_URL, SERVICE_KEY)
    await admin.from('debug_log').insert({
      source: 'edge',
      component: 'pdf-to-html',
      action: 'convert',
      status,
      error_message: errorMessage,
      request_data: data,
      duration_ms: Math.round(durationMs),
    })
  } catch { /* log nesmí shodit odpověď */ }
}

function partNote(index: number, total: number, fromPage: number, toPage: number): string {
  if (total <= 1) return 'Convert the attached PDF to HTML per the rules. Call submit_html with the result.'
  return [
    `The attached PDF contains pages ${fromPage}–${toPage} of a longer document that has been split into ${total} parts for processing (this is part ${index + 1}).`,
    'Convert ONLY the attached pages to HTML per the rules — the parts will be concatenated in order.',
    index > 0 ? 'Do NOT invent a document title or introduction — the document already started in a previous part. If the first line visibly continues a sentence from the previous page, still include it verbatim.' : '',
    'Do not add any "part X" headings or separators of your own.',
    'Call submit_html with the result.',
  ].filter(Boolean).join(' ')
}

async function claudeConvert(apiKey: string, pdfB64: string, note: string): Promise<string> {
  let lastErr = ''
  for (let attempt = 1; attempt <= 3; attempt++) {
    if (attempt > 1) await new Promise(r => setTimeout(r, attempt === 2 ? 3000 : 8000))
    let response: Response
    try {
      response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
        body: JSON.stringify({
          model: MODEL,
          max_tokens: MAX_TOKENS_PER_CALL,
          system: SYSTEM_PROMPT,
          tools: [{
            name: 'submit_html',
            description: 'Submit the converted document as a clean semantic HTML fragment.',
            input_schema: {
              type: 'object',
              properties: { html: { type: 'string', description: 'Document body as clean semantic HTML, Czech text preserved verbatim.' } },
              required: ['html'],
            },
          }],
          tool_choice: { type: 'tool', name: 'submit_html' },
          messages: [{
            role: 'user',
            content: [
              { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: pdfB64 } },
              { type: 'text', text: note },
            ],
          }],
        }),
      })
    } catch (e) {
      lastErr = 'síťová chyba: ' + (e instanceof Error ? e.message : String(e))
      continue
    }
    if (!response.ok) {
      const errText = await response.text()
      lastErr = `Anthropic API ${response.status}: ${errText.slice(0, 300)}`
      // 429 / 5xx jsou přechodné → retry; 4xx (kredit, klíč, moc velký request) ne.
      if (response.status === 429 || response.status >= 500) continue
      throw new Error(lastErr)
    }
    const data = await response.json()
    if (data?.stop_reason === 'max_tokens') {
      throw new Error('Výstup se nevešel do tokenového limitu části — kontaktujte vývojáře (příliš hustý dokument).')
    }
    const toolUse = Array.isArray(data?.content)
      ? data.content.find((c: { type?: string, name?: string }) => c?.type === 'tool_use' && c?.name === 'submit_html')
      : null
    const html = typeof toolUse?.input?.html === 'string' ? toolUse.input.html.trim() : ''
    if (html) return html
    lastErr = 'model nevrátil HTML (stop=' + (data?.stop_reason || '?') + ')'
  }
  throw new Error(lastErr || 'převod selhal')
}

// Paralelní zpracování s omezenou souběžností (šetří Anthropic rate-limit).
async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T, i: number) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length)
  let next = 0
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++
      results[i] = await fn(items[i], i)
    }
  })
  await Promise.all(workers)
  return results
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') return jsonResponse({ success: false, error: 'method_not_allowed' }, 405)

  const auth = await requireAdminOrService(req)
  if (!auth.ok) return jsonResponse({ success: false, error: 'unauthorized', reason: auth.reason }, 401)

  let body: { pdf_base64?: string }
  try { body = await req.json() } catch { return jsonResponse({ success: false, error: 'bad_json' }, 400) }
  const pdf = (body.pdf_base64 || '').replace(/^data:[^;]+;base64,/, '')
  if (!pdf) return jsonResponse({ success: false, error: 'missing_pdf' }, 400)
  if (pdf.length > MAX_BASE64_CHARS) return jsonResponse({ success: false, error: 'PDF je příliš velké (max 10 MB).' }, 400)

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY') || ''
  if (!apiKey) return jsonResponse({ success: false, error: 'missing_api_key' }, 500)

  const t0 = performance.now()
  try {
    // Kolik má PDF stran? (pdf-lib; když se nepovede načíst, jedeme celokusově)
    let pageCount: number | null = null
    let srcDoc: PDFDocument | null = null
    try {
      srcDoc = await PDFDocument.load(base64ToBytes(pdf), { ignoreEncryption: true })
      pageCount = srcDoc.getPageCount()
    } catch (e) {
      console.warn('pdf-to-html: pdf-lib load failed, falling back to single call:', e)
    }
    if (pageCount !== null && pageCount > MAX_PAGES) {
      await logDb('error', `too_many_pages: ${pageCount}`, { pages: pageCount, b64_len: pdf.length }, performance.now() - t0)
      return jsonResponse({ success: false, error: `PDF má ${pageCount} stran — maximum je ${MAX_PAGES}. Rozdělte dokument.` }, 400)
    }

    let html: string
    let chunks = 1
    if (srcDoc === null || pageCount === null || pageCount <= CHUNK_PAGES) {
      html = await claudeConvert(apiKey, pdf, partNote(0, 1, 1, pageCount || 0))
    } else {
      // Rozdělení po CHUNK_PAGES stranách → paralelní převod → spojení v pořadí.
      const ranges: Array<[number, number]> = []
      for (let start = 0; start < pageCount; start += CHUNK_PAGES) {
        ranges.push([start, Math.min(start + CHUNK_PAGES, pageCount) - 1])
      }
      chunks = ranges.length
      const parts = await mapLimit(ranges, CHUNK_CONCURRENCY, async ([from, to], i) => {
        const part = await PDFDocument.create()
        const indices = Array.from({ length: to - from + 1 }, (_, k) => from + k)
        const pages = await part.copyPages(srcDoc as PDFDocument, indices)
        for (const p of pages) part.addPage(p)
        const partB64 = uint8ToBase64(await part.save())
        return claudeConvert(apiKey, partB64, partNote(i, ranges.length, from + 1, to + 1))
      })
      html = parts.join('\n')
    }

    await logDb('ok', null, { pages: pageCount, chunks, b64_len: pdf.length, html_len: html.length }, performance.now() - t0)
    return jsonResponse({ success: true, html, pages: pageCount, chunks })
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    console.error('pdf-to-html fatal:', msg)
    await logDb('error', msg, { b64_len: pdf.length }, performance.now() - t0)
    return jsonResponse({ success: false, error: msg }, 502)
  }
})
