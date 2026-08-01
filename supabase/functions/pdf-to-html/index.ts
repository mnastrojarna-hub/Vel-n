// pdf-to-html — převod nahraného PDF na čisté sémantické HTML přes Claude
// (document content block, stejný mechanismus jako translate-document u PDF).
//
// Slouží Velín → Dokumenty → Smluvní texty: admin nahraje PDF s novým zněním
// (VOP, nájemní smlouva, protokoly, GDPR), funkce vrátí obsah jako HTML,
// který se předvyplní do editačního modalu a uloží STÁVAJÍCÍ cestou do
// document_templates.content_html. Veškerá navazující funkčnost (překlady,
// generování dokumentů k rezervacím, mailové přílohy) tak zůstává beze změny.
//
// JEN převod — žádný zápis do DB. Vlastní ověření admina → verify_jwt=false.
//
// POST body: { pdf_base64: string }
// Odpověď:  { success: true, html: string } | { success: false, error: string }
import { corsResponse, jsonResponse } from '../_shared/cors.ts'
import { requireAdminOrService } from '../_shared/auth.ts'

const MODEL = 'claude-sonnet-4-6'
const MAX_TOKENS = 32000
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

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        tools: [{
          name: 'submit_html',
          description: 'Submit the converted document as a clean semantic HTML fragment.',
          input_schema: {
            type: 'object',
            properties: { html: { type: 'string', description: 'Full document body as clean semantic HTML, Czech text preserved verbatim.' } },
            required: ['html'],
          },
        }],
        tool_choice: { type: 'tool', name: 'submit_html' },
        messages: [{
          role: 'user',
          content: [
            { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: pdf } },
            { type: 'text', text: 'Convert the attached PDF to HTML per the rules. Call submit_html with the result.' },
          ],
        }],
      }),
    })
    if (!response.ok) {
      const errText = await response.text()
      console.error('pdf-to-html Anthropic error:', response.status, errText)
      if (response.status === 429) return jsonResponse({ success: false, error: 'Anthropic API: rate limit, zkuste za chvíli.' }, 502)
      return jsonResponse({ success: false, error: `Anthropic API ${response.status}: ${errText.slice(0, 300)}` }, 502)
    }
    const data = await response.json()
    if (data?.stop_reason === 'max_tokens') {
      return jsonResponse({ success: false, error: 'PDF je příliš dlouhé — výstup se nevešel do limitu. Rozdělte dokument nebo vložte text ručně.' }, 400)
    }
    const toolUse = Array.isArray(data?.content)
      ? data.content.find((c: { type?: string, name?: string }) => c?.type === 'tool_use' && c?.name === 'submit_html')
      : null
    const html = typeof toolUse?.input?.html === 'string' ? toolUse.input.html.trim() : ''
    if (!html) return jsonResponse({ success: false, error: 'Převod selhal — model nevrátil HTML.' }, 502)
    return jsonResponse({ success: true, html })
  } catch (err) {
    console.error('pdf-to-html fatal:', err)
    return jsonResponse({ success: false, error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
