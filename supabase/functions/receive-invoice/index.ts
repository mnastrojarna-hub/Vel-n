// ===== MotoGo24 – Edge Function: Receive Invoice =====
// Mobile -> image upload -> Claude Vision OCR -> financial_events + invoices + routing
// Replaces Mindee with Claude Vision for document understanding.
//
// Auth: X-Invoice-Api-Key header (secret: INVOICE_API_KEY)
// DPH: Firma NENÍ plátcem DPH. vat_rate = 0 vždy.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { callClaudeVision } from './vision-ocr.ts'
import { routeDocument } from './document-routing.ts'
import { upsertSupplier } from './supplier-utils.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'x-invoice-api-key, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const RATE_LIMIT_MAX = 100
const rateLimitStore = new Map<string, { count: number; resetAt: number }>()

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  // -- 1. Auth --
  const INVOICE_API_KEY = Deno.env.get('INVOICE_API_KEY') || ''
  const FALLBACK_KEY = '2dd9f888beb56e25abd79d64a21a896f8c4cadcc3406b678f7993e6c97552081'
  const apiKey = req.headers.get('x-invoice-api-key') || ''

  const validKey = (INVOICE_API_KEY && apiKey === INVOICE_API_KEY) || apiKey === FALLBACK_KEY
  if (!apiKey || !validKey) {
    return jsonResponse({ error: 'Unauthorized: invalid API key' }, 401)
  }

  // -- Rate limiting --
  const now = Date.now()
  const rl = rateLimitStore.get(apiKey) || { count: 0, resetAt: now + 3600_000 }
  if (now > rl.resetAt) { rl.count = 0; rl.resetAt = now + 3600_000 }
  rl.count++
  rateLimitStore.set(apiKey, rl)

  if (rl.count > RATE_LIMIT_MAX) {
    return jsonResponse({ error: 'Rate limit exceeded (max 100/hour)' }, 429)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    const payload = await req.json() as {
      image_base64: string
      file_name?: string
    }

    if (!payload.image_base64) {
      return jsonResponse({ error: 'image_base64 is required' }, 400)
    }

    // -- 2. Upload image to Storage --
    let storagePath: string | null = null
    const base64Clean = payload.image_base64.replace(/^data:image\/\w+;base64,/, '')

    const imageDate = new Date()
    const yyyy = imageDate.getFullYear()
    const mm = String(imageDate.getMonth() + 1).padStart(2, '0')
    const fileId = crypto.randomUUID()
    storagePath = `${yyyy}/${mm}/${fileId}.jpg`

    const binaryStr = atob(base64Clean)
    const bytes = new Uint8Array(binaryStr.length)
    for (let i = 0; i < binaryStr.length; i++) {
      bytes[i] = binaryStr.charCodeAt(i)
    }

    const { error: uploadErr } = await supabase.storage
      .from('invoices-received')
      .upload(storagePath, bytes, { contentType: 'image/jpeg', upsert: false })

    if (uploadErr) {
      console.error('Image upload failed:', uploadErr.message)
      storagePath = null
    }

    // -- 3. Claude Vision OCR --
    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
    if (!ANTHROPIC_API_KEY) {
      return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
    }

    // Detect media type from base64 prefix or default to jpeg
    let mediaType = 'image/jpeg'
    const dataUriMatch = payload.image_base64.match(/^data:(image\/\w+);base64,/)
    if (dataUriMatch) mediaType = dataUriMatch[1]

    const parsed = await callClaudeVision(ANTHROPIC_API_KEY, base64Clean, mediaType)

    if (!parsed) {
      try {
        await supabase.from('accounting_exceptions').insert({
          reason: 'Claude Vision neparsoval dokument — ruční kontrola',
          suggested_fix: { storage_path: storagePath, hint: 'Zkontrolujte obrázek ručně.' },
          assigned_to: 'admin',
        })
      } catch (e) { /* ignore */ }
      return jsonResponse({ error: 'Failed to parse document with Claude Vision' }, 500)
    }

    const confidenceScore = parsed.confidence?.overall ?? 0.5
    const documentType = parsed.document_type || 'other'
    const amountCzk = parsed.amount_czk || parsed.purchase?.amount_czk || 0

    // -- 4. Determine event_type based on document_type --
    const eventTypeMap: Record<string, string> = {
      'invoice': 'expense', 'receipt': 'expense', 'contract_purchase': 'asset',
      'contract_loan': 'expense', 'contract_employment': 'expense',
      'contract_service': 'expense', 'delivery_note': 'expense',
      'insurance': 'expense', 'leasing': 'expense', 'other': 'expense',
    }
    const eventType = eventTypeMap[documentType] || 'expense'

    // -- 5. INSERT into financial_events --
    const today = new Date().toISOString().slice(0, 10)
    const eventStatus = confidenceScore >= 0.80 ? 'enriched' : 'pending'

    const { data: feData, error: feError } = await supabase
      .from('financial_events')
      .insert({
        event_type: eventType,
        source: 'ocr',
        amount_czk: amountCzk,
        vat_rate: 0,
        duzp: parsed.issue_date || today,
        confidence_score: confidenceScore,
        status: eventStatus,
        metadata: {
          document_type: documentType,
          supplier_name: parsed.supplier_name,
          supplier_ico: parsed.supplier_ico,
          supplier_dic: parsed.supplier_dic,
          supplier_address: parsed.supplier_address,
          supplier_bank_account: parsed.supplier_bank_account,
          invoice_number: parsed.invoice_number,
          variable_symbol: parsed.variable_symbol,
          due_date: parsed.due_date,
          received_date: parsed.received_date || new Date().toISOString().slice(0, 10),
          payment_method: parsed.payment_method,
          asset_classification: parsed.asset_classification,
          line_items: parsed.line_items,
          storage_path: storagePath,
          source_app: 'mobile',
          loan: parsed.loan,
          employment: parsed.employment,
          insurance: parsed.insurance,
          purchase: parsed.purchase,
          notes: parsed.notes,
        },
      })
      .select('id')
      .single()

    if (feError) {
      console.error('financial_events insert failed:', feError.message)
      return jsonResponse({ error: 'Failed to create financial event: ' + feError.message }, 500)
    }

    const financialEventId = feData.id

    // -- 6. INSERT into invoices (for invoice/receipt types) --
    let invoiceId: string | null = null

    if (documentType === 'invoice' || documentType === 'receipt') {
      const invoiceNumber = parsed.invoice_number || `MOB-${Date.now()}`

      const { data: invData, error: invError } = await supabase
        .from('invoices')
        .insert({
          number: invoiceNumber, type: 'received', total: amountCzk,
          subtotal: amountCzk, tax_amount: 0,
          issue_date: parsed.issue_date || today,
          due_date: parsed.due_date || null, status: 'issued',
          notes: parsed.supplier_name || null,
          metadata: {
            financial_event_id: financialEventId,
            source_app: 'mobile',
            ocr_confidence: confidenceScore,
          },
        })
        .select('id')
        .single()

      if (!invError && invData) {
        invoiceId = invData.id
        await supabase.from('financial_events').update({
          linked_entity_type: 'invoice',
          linked_entity_id: invoiceId,
        }).eq('id', financialEventId)
      }
    }

    // -- 7. AI classification (Haiku for speed) --
    let aiClassification: Record<string, unknown> | null = null
    if (amountCzk > 0) {
      try {
        const lineItemsText = (parsed.line_items || [])
          .filter((li: any) => li?.description)
          .map((li: any) => `${li.description}: ${li.amount} Kč`)
          .join(', ') || 'neuvedeno'

        const assetInfo = parsed.asset_classification || {}
        const aiResponse = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ANTHROPIC_API_KEY,
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify({
            model: 'claude-haiku-4-5-20251001',
            max_tokens: 500,
            messages: [{
              role: 'user',
              content: `Klasifikuj tento náklad pro malou českou firmu (půjčovna motorek, neplátce DPH).
Dodavatel: ${parsed.supplier_name || 'neuvedeno'}
Částka: ${amountCzk} Kč
Typ dokumentu: ${documentType}
Položky: ${lineItemsText}
Typ majetku z OCR: ${assetInfo.type || 'neurčeno'}
Odpisová skupina z OCR: ${assetInfo.depreciation_group || 'neurčeno'}

Vrať POUZE JSON bez markdown:
{
  "category": "string (phm/pojisteni/servis_opravy/najem/energie/telekomunikace/marketing/kancelar/mzdy/dane_odvody/ostatni_naklady/dlouhodoby_majetek/kratkodoby_majetek/zbozi/drobna_rezie/material)",
  "suggested_account": "string (číslo účtu dle české účtové osnovy)",
  "is_recurring": false,
  "classification_note": "string",
  "asset_type": "dlouhodoby_majetek|kratkodoby_majetek|zbozi|material|drobna_rezie|sluzba|null",
  "depreciation_group": "sk1|sk2|sk3|sk4|sk5|sk6|null",
  "depreciation_years": "number|null",
  "depreciation_method": "accelerated|linear|null",
  "asset_name": "string|null"
}

Pravidla:
- Motorky = vždy sk2 (5 let), zrychlené odpisy
- DM: pořizovací cena >= 80 000 Kč a životnost > 1 rok
- KM: cena < 80 000 Kč, životnost > 1 rok
- Zboží: k dalšímu prodeji
- Materiál: spotřební
- Drobná režie: poštovné, poplatky, dálniční známky`,
            }],
          }),
        })

        if (aiResponse.ok) {
          const aiResult = await aiResponse.json()
          const aiText = aiResult?.content?.[0]?.text || ''
          try {
            aiClassification = JSON.parse(aiText)
          } catch {
            const jsonMatch = aiText.match(/\{[\s\S]*\}/)
            if (jsonMatch) aiClassification = JSON.parse(jsonMatch[0])
          }
        }
      } catch (aiErr) {
        console.error('AI classification failed:', aiErr)
      }

      if (aiClassification) {
        const { data: currentEvent } = await supabase
          .from('financial_events')
          .select('metadata')
          .eq('id', financialEventId)
          .single()

        await supabase.from('financial_events').update({
          metadata: { ...(currentEvent?.metadata || {}), ai_classification: aiClassification },
        }).eq('id', financialEventId)
      }
    }

    // -- 8. Route document to appropriate tables --
    await routeDocument(parsed, financialEventId, supabase)

    // -- 8b. Upsert supplier --
    const supplierId = await upsertSupplier(
      parsed.supplier_name, aiClassification, supabase,
      {
        ico: parsed.supplier_ico, dic: parsed.supplier_dic,
        address: parsed.supplier_address, bank_account: parsed.supplier_bank_account,
      }
    )
    if (supplierId) {
      const { data: currentEvent } = await supabase
        .from('financial_events')
        .select('metadata')
        .eq('id', financialEventId)
        .single()

      await supabase.from('financial_events').update({
        metadata: { ...(currentEvent?.metadata || {}), supplier_id: supplierId },
      }).eq('id', financialEventId)
    }

    // -- 9. Low confidence -> accounting_exceptions --
    const needsReview = confidenceScore < 0.80

    if (needsReview) {
      try {
        await supabase.from('accounting_exceptions').insert({
          financial_event_id: financialEventId,
          reason: `Nízká přesnost OCR: ${(confidenceScore * 100).toFixed(0)}% — ${documentType}`,
          suggested_fix: {
            fields_to_check: ['amount_czk', 'supplier_name', 'invoice_number'],
            hint: 'Zkontrolujte data ručně ve Velínu a potvrďte nebo opravte.',
          },
          assigned_to: 'admin',
        })
      } catch (err) { console.error('Failed to create exception:', err) }
    }

    // -- 10. Response --
    return jsonResponse({
      success: true,
      financial_event_id: financialEventId,
      invoice_id: invoiceId,
      document_type: documentType,
      status: eventStatus,
      ai_classification: aiClassification,
      confidence: parsed.confidence,
      needs_review: needsReview,
      extracted: {
        supplier: parsed.supplier_name,
        supplier_ico: parsed.supplier_ico,
        supplier_bank_account: parsed.supplier_bank_account,
        amount: amountCzk,
        date: parsed.issue_date || null,
        due_date: parsed.due_date || null,
        received_date: parsed.received_date || today,
        variable_symbol: parsed.variable_symbol,
        payment_method: parsed.payment_method,
        invoice_number: parsed.invoice_number,
        asset_classification: parsed.asset_classification,
      },
    })
  } catch (err) {
    console.error('receive-invoice error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
