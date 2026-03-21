// ===== MotoGo24 – Edge Function: Receive Invoice =====
// Public API for external mobile mini-app.
// Workflow: Mobile → OCR → POST structured data here → financial_events + invoices
// Admin reviews in Velín dashboard.
//
// Auth: X-Invoice-Api-Key header (secret: INVOICE_API_KEY)
// DPH: Firma NENÍ plátcem DPH. vat_rate = 0 vždy.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*', // TODO: omezit na doménu mobilní appky v produkci
  'Access-Control-Allow-Headers': 'x-invoice-api-key, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const RATE_LIMIT_MAX = 100 // max requests per hour per API key
const rateLimitStore = new Map<string, { count: number; resetAt: number }>()

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  // ── 1. Auth: validate API key ──
  const INVOICE_API_KEY = Deno.env.get('INVOICE_API_KEY') || ''
  const apiKey = req.headers.get('x-invoice-api-key') || ''

  if (!INVOICE_API_KEY || apiKey !== INVOICE_API_KEY) {
    return jsonResponse({ error: 'Unauthorized: invalid API key' }, 401)
  }

  // ── Rate limiting ──
  const now = Date.now()
  const rl = rateLimitStore.get(apiKey) || { count: 0, resetAt: now + 3600_000 }
  if (now > rl.resetAt) {
    rl.count = 0
    rl.resetAt = now + 3600_000
  }
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
      supplier_name: string
      invoice_number: string
      amount_czk: number
      issue_date: string
      due_date?: string
      line_items?: Array<{ description: string; amount: number }>
      confidence_score: number
      image_base64?: string
      file_name?: string
    }

    // Basic validation
    if (!payload.amount_czk || payload.amount_czk <= 0) {
      return jsonResponse({ error: 'amount_czk must be positive' }, 400)
    }
    if (typeof payload.confidence_score !== 'number' || payload.confidence_score < 0 || payload.confidence_score > 1) {
      return jsonResponse({ error: 'confidence_score must be 0.0-1.0' }, 400)
    }

    // ── 2. Upload image to Storage (if provided) ──
    let storagePath: string | null = null

    if (payload.image_base64) {
      const imageDate = new Date()
      const yyyy = imageDate.getFullYear()
      const mm = String(imageDate.getMonth() + 1).padStart(2, '0')
      const fileId = crypto.randomUUID()
      storagePath = `${yyyy}/${mm}/${fileId}.jpg`

      // Decode base64 (strip data URI prefix if present)
      const base64Clean = payload.image_base64.replace(/^data:image\/\w+;base64,/, '')
      const binaryStr = atob(base64Clean)
      const bytes = new Uint8Array(binaryStr.length)
      for (let i = 0; i < binaryStr.length; i++) {
        bytes[i] = binaryStr.charCodeAt(i)
      }

      const { error: uploadErr } = await supabase.storage
        .from('invoices-received')
        .upload(storagePath, bytes, {
          contentType: 'image/jpeg',
          upsert: false,
        })

      if (uploadErr) {
        console.error('Image upload failed:', uploadErr.message)
        storagePath = null // continue without image
      }
    }

    // ── 3. INSERT into financial_events ──
    const today = new Date().toISOString().slice(0, 10)
    const eventStatus = payload.confidence_score >= 0.80 ? 'enriched' : 'pending'

    const { data: feData, error: feError } = await supabase
      .from('financial_events')
      .insert({
        event_type: 'expense',
        source: 'ocr',
        amount_czk: payload.amount_czk,
        vat_rate: 0, // firma není plátce DPH
        duzp: payload.issue_date || today,
        confidence_score: payload.confidence_score,
        status: eventStatus,
        metadata: {
          supplier_name: payload.supplier_name || null,
          invoice_number: payload.invoice_number || null,
          due_date: payload.due_date || null,
          line_items: payload.line_items || null,
          storage_path: storagePath,
          source_app: 'mobile',
        },
      })
      .select('id')
      .single()

    if (feError) {
      console.error('financial_events insert failed:', feError.message)
      return jsonResponse({ error: 'Failed to create financial event: ' + feError.message }, 500)
    }

    const financialEventId = feData.id

    // ── 4. INSERT into invoices (type='received') ──
    const invoiceNumber = payload.invoice_number || `MOB-${Date.now()}`

    const { data: invData, error: invError } = await supabase
      .from('invoices')
      .insert({
        number: invoiceNumber,
        type: 'received',
        total: payload.amount_czk,
        subtotal: payload.amount_czk,
        tax_amount: 0,
        issue_date: payload.issue_date || today,
        due_date: payload.due_date || null,
        status: 'issued',
        notes: payload.supplier_name || null,
        metadata: {
          financial_event_id: financialEventId,
          source_app: 'mobile',
          ocr_confidence: payload.confidence_score,
        },
      })
      .select('id')
      .single()

    if (invError) {
      console.error('invoices insert failed:', invError.message)
      // Don't fail the whole request — financial_event was created
    }

    const invoiceId = invData?.id || null

    // Link invoice back to financial_event
    if (invoiceId) {
      await supabase.from('financial_events').update({
        linked_entity_type: 'invoice',
        linked_entity_id: invoiceId,
      }).eq('id', financialEventId)
    }

    // ── 5. AI classification via Claude API ──
    let aiClassification: Record<string, unknown> | null = null
    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

    if (ANTHROPIC_API_KEY) {
      try {
        const lineItemsText = (payload.line_items || [])
          .map(li => `${li.description}: ${li.amount} Kč`)
          .join(', ') || 'neuvedeno'

        const aiResponse = await fetch('https://api.anthropic.com/v1/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ANTHROPIC_API_KEY,
            'anthropic-version': '2023-06-01',
          },
          body: JSON.stringify({
            model: 'claude-haiku-4-5-20251001',
            max_tokens: 300,
            messages: [{
              role: 'user',
              content: `Klasifikuj tento náklad pro malou českou firmu (neplátce DPH).
Dodavatel: ${payload.supplier_name || 'neuvedeno'}
Částka: ${payload.amount_czk} Kč
Položky: ${lineItemsText}

Vrať POUZE JSON bez markdown:
{
  "category": "string (phm/pojisteni/servis_opravy/najem/energie/telekomunikace/marketing/kancelar/mzdy/dane_odvody/ostatni_naklady)",
  "suggested_account": "string (číslo účtu dle české účtové osnovy, např. 501000)",
  "is_recurring": false,
  "classification_note": "string (krátké vysvětlení)"
}`,
            }],
          }),
        })

        if (aiResponse.ok) {
          const aiResult = await aiResponse.json()
          const aiText = aiResult?.content?.[0]?.text || ''
          try {
            aiClassification = JSON.parse(aiText)
          } catch {
            // Try to extract JSON from response
            const jsonMatch = aiText.match(/\{[\s\S]*\}/)
            if (jsonMatch) {
              aiClassification = JSON.parse(jsonMatch[0])
            }
          }
        }
      } catch (aiErr) {
        console.error('AI classification failed:', aiErr)
        // Non-fatal — continue without AI classification
      }

      // Save AI classification to financial_event metadata
      if (aiClassification) {
        const { data: currentEvent } = await supabase
          .from('financial_events')
          .select('metadata')
          .eq('id', financialEventId)
          .single()

        await supabase.from('financial_events').update({
          metadata: {
            ...(currentEvent?.metadata || {}),
            ai_classification: aiClassification,
          },
        }).eq('id', financialEventId)
      }
    }

    // ── 6. Low confidence → accounting_exceptions ──
    const needsReview = payload.confidence_score < 0.80

    if (needsReview) {
      await supabase.from('accounting_exceptions').insert({
        financial_event_id: financialEventId,
        reason: `Nízká přesnost OCR z mobilní appky: ${(payload.confidence_score * 100).toFixed(0)}%`,
        suggested_fix: {
          fields_to_check: ['amount_czk', 'supplier_name', 'invoice_number'],
          hint: 'Zkontrolujte data ručně ve Velínu a potvrďte nebo opravte.',
        },
        assigned_to: 'admin',
      }).catch(err => {
        console.error('Failed to create exception:', err)
      })
    }

    // ── 7. Response ──
    return jsonResponse({
      success: true,
      financial_event_id: financialEventId,
      invoice_id: invoiceId,
      status: eventStatus,
      ai_classification: aiClassification,
      needs_review: needsReview,
    })
  } catch (err) {
    console.error('receive-invoice error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
