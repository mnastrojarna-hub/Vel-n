// extract-document — OCR faktury / dodacího listu přes Claude Vision.
// JEN extrakce (žádný zápis do DB) — pro Velín → Logistika → Naskladnění,
// kde admin z výstupu naskladní položky (finance řeší samostatně receive-invoice).
import { corsHeaders, corsResponse, jsonResponse } from '../_shared/cors.ts'
import { requireAdminOrService } from '../_shared/auth.ts'

const VISION_PROMPT = `Jsi účetní asistent české firmy (půjčovna motorek). Přečti naskenovaný doklad
(faktura nebo dodací list) a vrať POUZE JSON, žádný markdown, žádný text navíc:
{
  "document_type": "invoice|delivery_note|receipt|other",
  "supplier_name": null,
  "supplier_ico": null,
  "invoice_number": null,
  "issue_date": null,
  "amount_czk": null,
  "line_items": [{ "description": null, "quantity": null, "unit_price": null, "amount": null }]
}
Pro KAŽDOU položku dokladu vyplň description (název), quantity (počet kusů, default 1),
unit_price (cena za kus bez měny) a amount (celkem za řádek). Když cena za kus chybí,
dopočítej ji z amount/quantity. Částky jako čísla bez mezer a měny. Data jako YYYY-MM-DD.
Pole, které nejde přečíst: null.`

async function callClaudeVision(apiKey: string, imageBase64: string, mediaType: string, isRetry = false): Promise<Record<string, unknown> | null> {
  const prompt = isRetry ? 'Vrať pouze validní JSON, nic jiného.\n\n' + VISION_PROMPT : VISION_PROMPT
  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({
        model: 'claude-opus-4-5',
        max_tokens: 2048,
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
            { type: 'text', text: prompt },
          ],
        }],
      }),
    })
    if (!response.ok) { console.error('Claude Vision error:', response.status, await response.text()); return null }
    const result = await response.json()
    const text = result?.content?.[0]?.text || ''
    try { return JSON.parse(text) } catch { /* try extract */ }
    const m = text.match(/\{[\s\S]*\}/)
    if (m) { try { return JSON.parse(m[0]) } catch { /* fall through */ } }
    if (!isRetry) return callClaudeVision(apiKey, imageBase64, mediaType, true)
    return null
  } catch (err) { console.error('Vision call failed:', err); return null }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return corsResponse()
  if (req.method !== 'POST') return jsonResponse({ success: false, error: 'method_not_allowed' }, 405)

  const auth = await requireAdminOrService(req)
  if (!auth.ok) return jsonResponse({ success: false, error: 'unauthorized', reason: auth.reason }, 401)

  let body: { image_base64?: string; mime?: string }
  try { body = await req.json() } catch { return jsonResponse({ success: false, error: 'bad_json' }, 400) }
  const image = (body.image_base64 || '').replace(/^data:[^;]+;base64,/, '')
  const mime = body.mime || 'image/jpeg'
  if (!image) return jsonResponse({ success: false, error: 'missing_image' }, 400)
  if (image.length > 12_000_000) return jsonResponse({ success: false, error: 'image_too_large' }, 400)

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY') || ''
  if (!apiKey) return jsonResponse({ success: false, error: 'missing_api_key' }, 500)

  const parsed = await callClaudeVision(apiKey, image, mime)
  if (!parsed) return jsonResponse({ success: false, error: 'ocr_failed' }, 502)

  const items = Array.isArray(parsed.line_items) ? parsed.line_items : []
  return jsonResponse({
    success: true,
    document_type: parsed.document_type ?? null,
    supplier_name: parsed.supplier_name ?? null,
    supplier_ico: parsed.supplier_ico ?? null,
    invoice_number: parsed.invoice_number ?? null,
    issue_date: parsed.issue_date ?? null,
    amount_czk: parsed.amount_czk ?? null,
    items,
  })
})
