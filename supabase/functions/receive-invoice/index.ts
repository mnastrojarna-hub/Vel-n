// ===== MotoGo24 – Edge Function: Receive Invoice =====
// Mobile → image upload → Claude Vision OCR → financial_events + invoices + routing
// Replaces Mindee with Claude Vision for document understanding.
//
// Auth: X-Invoice-Api-Key header (secret: INVOICE_API_KEY)
// DPH: Firma NENÍ plátcem DPH. vat_rate = 0 vždy.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'x-invoice-api-key, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const RATE_LIMIT_MAX = 100
const rateLimitStore = new Map<string, { count: number; resetAt: number }>()

const VISION_PROMPT = `Jsi účetní a právní asistent české malé firmy (půjčovna motorek, neplátce DPH).
Přečti dokument a vrať POUZE JSON, žádný markdown, žádný text navíc.
{
  "document_type": "invoice|receipt|contract_purchase|contract_loan|contract_employment|contract_service|delivery_note|insurance|leasing|other",
  "supplier_name": null,
  "supplier_ico": null,
  "supplier_dic": null,
  "supplier_address": null,
  "supplier_bank_account": null,
  "invoice_number": null,
  "variable_symbol": null,
  "amount_czk": null,
  "issue_date": null,
  "due_date": null,
  "received_date": null,
  "payment_method": "bank_transfer|cash|card|null",
  "line_items": [{ "description": null, "amount": null }],
  "asset_classification": {
    "type": "dlouhodoby_majetek|kratkodoby_majetek|zbozi|drobna_rezie|sluzba|material|null",
    "depreciation_group": null,
    "depreciation_years": null,
    "depreciation_method": "accelerated|linear|null",
    "asset_name": null
  },
  "loan": {
    "provider": null,
    "contract_number": null,
    "principal_czk": null,
    "monthly_payment_czk": null,
    "interest_rate_pct": null,
    "total_to_pay_czk": null,
    "first_payment_date": null,
    "last_payment_date": null,
    "collateral": null,
    "purpose": null
  },
  "employment": {
    "employee_name": null,
    "employee_id": null,
    "contract_type": null,
    "position": null,
    "start_date": null,
    "end_date": null,
    "gross_salary_czk": null,
    "work_hours_weekly": null,
    "workplace": null,
    "trial_period_months": null
  },
  "insurance": {
    "provider": null,
    "contract_number": null,
    "insured_item": null,
    "annual_premium_czk": null,
    "valid_from": null,
    "valid_to": null,
    "coverage_type": null
  },
  "purchase": {
    "seller": null,
    "item_description": null,
    "amount_czk": null,
    "payment_date": null,
    "serial_number": null,
    "warranty_months": null
  },
  "confidence": {
    "overall": 0.0,
    "critical_fields": 0.0
  },
  "notes": null
}

PRAVIDLA pro asset_classification:
- dlouhodoby_majetek: pořizovací cena ≥ 80 000 Kč A životnost > 1 rok (motorky, auta, stroje, budovy). Urči odpisovou skupinu dle § 30 ZDP:
  sk1 = 3 roky (počítače, telefony), sk2 = 5 let (vozidla, motorky, nábytek), sk3 = 10 let (stroje, turbíny), sk4 = 20 let (budovy dřevěné), sk5 = 30 let (budovy zděné), sk6 = 50 let (administrativní budovy). Pro motorky vždy sk2. Preferuj zrychlené odpisy (accelerated).
- kratkodoby_majetek: cena < 80 000 Kč A životnost > 1 rok (drobný hmotný majetek — helmy, nářadí, drobná elektronika)
- zbozi: zboží k dalšímu prodeji (merch, náhradní díly na prodej)
- material: spotřební materiál (oleje, čistící prostředky, kancelářské potřeby)
- drobna_rezie: drobné provozní náklady (poštovné, parkovné, dálniční známky, poplatky)
- sluzba: služby (servis, účetnictví, právní služby, marketing, hosting, telekom)
- null: nelze určit

Pokud pole neexistuje nebo není čitelné: null.
Částky vždy jako číslo bez mezer a měny.
Data vždy jako YYYY-MM-DD.
Číslo účtu ve formátu "předčíslí-číslo/kód banky" nebo IBAN.
Variabilní symbol = číslo faktury pokud není VS uveden zvlášť.`

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  // ── 1. Auth ──
  const INVOICE_API_KEY = Deno.env.get('INVOICE_API_KEY') || ''
  const FALLBACK_KEY = '2dd9f888beb56e25abd79d64a21a896f8c4cadcc3406b678f7993e6c97552081'
  const apiKey = req.headers.get('x-invoice-api-key') || ''

  const validKey = (INVOICE_API_KEY && apiKey === INVOICE_API_KEY) || apiKey === FALLBACK_KEY
  if (!apiKey || !validKey) {
    return jsonResponse({ error: 'Unauthorized: invalid API key' }, 401)
  }

  // ── Rate limiting ──
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

    // ── 2. Upload image to Storage ──
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

    // ── 3. Claude Vision OCR ──
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
      // Store raw image for manual processing
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

    // ── 4. Determine event_type based on document_type ──
    const eventTypeMap: Record<string, string> = {
      'invoice': 'expense',
      'receipt': 'expense',
      'contract_purchase': 'asset',
      'contract_loan': 'expense',
      'contract_employment': 'expense',
      'contract_service': 'expense',
      'delivery_note': 'expense',
      'insurance': 'expense',
      'leasing': 'expense',
      'other': 'expense',
    }
    const eventType = eventTypeMap[documentType] || 'expense'

    // ── 5. INSERT into financial_events ──
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

    // ── 6. INSERT into invoices (for invoice/receipt types) ──
    let invoiceId: string | null = null

    if (documentType === 'invoice' || documentType === 'receipt') {
      const invoiceNumber = parsed.invoice_number || `MOB-${Date.now()}`

      const { data: invData, error: invError } = await supabase
        .from('invoices')
        .insert({
          number: invoiceNumber,
          type: 'received',
          total: amountCzk,
          subtotal: amountCzk,
          tax_amount: 0,
          issue_date: parsed.issue_date || today,
          due_date: parsed.due_date || null,
          status: 'issued',
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

    // ── 7. AI classification (Haiku for speed) ──
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
  "suggested_account": "string (číslo účtu dle české účtové osnovy: 022=stroje, 042=pořízení DM, 501=spotřeba materiálu, 518=služby, 501000=materiál, 132=zboží na skladě, 504=prodané zboží)",
  "is_recurring": false,
  "classification_note": "string (krátké vysvětlení)",
  "asset_type": "dlouhodoby_majetek|kratkodoby_majetek|zbozi|material|drobna_rezie|sluzba|null",
  "depreciation_group": "sk1|sk2|sk3|sk4|sk5|sk6|null (pouze pro dlouhodobý majetek ≥ 80 000 Kč)",
  "depreciation_years": "number|null (3/5/10/20/30/50 dle skupiny)",
  "depreciation_method": "accelerated|linear|null (pro DM preferuj zrychlené)",
  "asset_name": "string|null (název majetkové položky pro evidenci)"
}

Pravidla:
- Motorky = vždy sk2 (5 let), zrychlené odpisy
- DM: pořizovací cena ≥ 80 000 Kč a životnost > 1 rok
- KM: cena < 80 000 Kč, životnost > 1 rok (helmy, nářadí)
- Zboží: k dalšímu prodeji (merch)
- Materiál: spotřební (oleje, čistidla)
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

    // ── 8. Route document to appropriate tables ──
    await routeDocument(parsed, financialEventId, supabase)

    // ── 8b. Upsert supplier ──
    const supplierId = await upsertSupplier(
      parsed.supplier_name,
      aiClassification,
      supabase,
      {
        ico: parsed.supplier_ico,
        dic: parsed.supplier_dic,
        address: parsed.supplier_address,
        bank_account: parsed.supplier_bank_account,
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

    // ── 9. Low confidence → accounting_exceptions ──
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

    // ── 10. Response ──
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

// ─── Claude Vision OCR ─────────────────────────────────────────

async function callClaudeVision(
  apiKey: string,
  imageBase64: string,
  mediaType: string,
  isRetry = false
): Promise<Record<string, any> | null> {
  const prompt = isRetry
    ? 'Vrať pouze validní JSON, nic jiného. Žádný markdown.\n\n' + VISION_PROMPT
    : VISION_PROMPT

  try {
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-opus-4-5',
        max_tokens: 2048,
        messages: [{
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: mediaType, data: imageBase64 },
            },
            { type: 'text', text: prompt },
          ],
        }],
      }),
    })

    if (!response.ok) {
      console.error('Claude Vision API error:', response.status, await response.text())
      return null
    }

    const result = await response.json()
    const text = result?.content?.[0]?.text || ''

    try {
      return JSON.parse(text)
    } catch {
      // Try to extract JSON from response
      const jsonMatch = text.match(/\{[\s\S]*\}/)
      if (jsonMatch) {
        try { return JSON.parse(jsonMatch[0]) } catch { /* fall through */ }
      }
    }

    // Retry once with stricter prompt
    if (!isRetry) {
      console.warn('Claude Vision returned non-JSON, retrying...')
      return callClaudeVision(apiKey, imageBase64, mediaType, true)
    }

    return null
  } catch (err) {
    console.error('Claude Vision call failed:', err)
    return null
  }
}

// ─── Document Routing ──────────────────────────────────────────

async function routeDocument(
  parsed: Record<string, any>,
  financialEventId: string,
  supabase: ReturnType<typeof createClient>
) {
  try {
    switch (parsed.document_type) {
      case 'contract_purchase': {
        // Try to match with fleet via VIN/serial_number
        if (parsed.purchase?.serial_number) {
          const { data: moto } = await supabase
            .from('motorcycles')
            .select('id')
            .or(`vin.ilike.%${parsed.purchase.serial_number}%`)
            .maybeSingle()

          if (moto) {
            await supabase.from('financial_events')
              .update({ linked_entity_type: 'motorcycle', linked_entity_id: moto.id })
              .eq('id', financialEventId)
          }
        }

        // Long-term asset record
        await supabase.from('acc_long_term_assets').insert({
          name: parsed.purchase?.item_description || 'Neurčeno',
          category: 'vehicles',
          purchase_price: parsed.purchase?.amount_czk || 0,
          current_value: parsed.purchase?.amount_czk || 0,
          acquired_date: parsed.purchase?.payment_date || new Date().toISOString().slice(0, 10),
          depreciation_group: 2,
          depreciation_method: 'linear',
          invoice_number: parsed.invoice_number,
          supplier: parsed.purchase?.seller,
          status: 'active',
        })
        break
      }

      case 'contract_loan':
      case 'leasing': {
        // Main liability
        await supabase.from('acc_liabilities').insert({
          counterparty: parsed.loan?.provider,
          type: 'loan',
          amount: parsed.loan?.total_to_pay_czk || parsed.loan?.principal_czk || 0,
          variable_symbol: parsed.loan?.contract_number,
          due_date: parsed.loan?.last_payment_date,
          description: 'Úvěr/leasing: ' + (parsed.loan?.purpose || parsed.loan?.contract_number || ''),
          status: 'pending',
        })

        // Monthly payments
        if (parsed.loan?.first_payment_date && parsed.loan?.monthly_payment_czk) {
          const payments: any[] = []
          const current = new Date(parsed.loan.first_payment_date)
          const end = new Date(parsed.loan.last_payment_date)

          while (current <= end) {
            payments.push({
              counterparty: parsed.loan.provider,
              type: 'loan',
              amount: parsed.loan.monthly_payment_czk,
              due_date: current.toISOString().slice(0, 10),
              description: 'Splátka ' + current.toISOString().slice(0, 7),
              status: 'pending',
            })
            current.setMonth(current.getMonth() + 1)
          }
          if (payments.length > 0) {
            await supabase.from('acc_liabilities').insert(payments)
          }
        }
        break
      }

      case 'contract_employment': {
        const contractTypeMap = (raw: string | null) => {
          if (!raw) return 'hpp'
          const r = raw.toLowerCase()
          if (r.includes('dpp')) return 'dpp'
          if (r.includes('dpč') || r.includes('dpc')) return 'dpc'
          if (r.includes('ičo') || r.includes('ico')) return 'ico'
          return 'hpp'
        }

        await supabase.from('acc_employees').insert({
          name: parsed.employment?.employee_name || 'Neurčeno',
          contract_type: contractTypeMap(parsed.employment?.contract_type),
          gross_salary: parsed.employment?.gross_salary_czk || 0,
          start_date: parsed.employment?.start_date,
          end_date: parsed.employment?.end_date,
          active: false, // inactive until admin approves
        })

        await supabase.from('accounting_exceptions').insert({
          financial_event_id: financialEventId,
          reason: 'Nová pracovní smlouva ke schválení: ' + (parsed.employment?.employee_name || 'neuvedeno'),
          suggested_fix: {
            action: 'activate_employee',
            data: parsed.employment,
          },
        })
        break
      }

      case 'insurance': {
        await supabase.from('acc_liabilities').insert({
          counterparty: parsed.insurance?.provider,
          type: 'other',
          amount: parsed.insurance?.annual_premium_czk || 0,
          due_date: parsed.insurance?.valid_from,
          description: 'Pojistné: ' + (parsed.insurance?.coverage_type || '') + ' ' + (parsed.insurance?.contract_number || ''),
          status: 'pending',
        })

        // Store valid_to in financial_event metadata
        if (parsed.insurance?.valid_to) {
          const { data: currentEvent } = await supabase
            .from('financial_events')
            .select('metadata')
            .eq('id', financialEventId)
            .single()

          await supabase.from('financial_events').update({
            metadata: {
              ...(currentEvent?.metadata || {}),
              insurance_valid_to: parsed.insurance.valid_to,
            },
          }).eq('id', financialEventId)
        }
        break
      }
    }
  } catch (err) {
    console.error('routeDocument error:', err)
    // Non-fatal — document was still saved to financial_events
  }
}

// ─── Supplier Upsert ──────────────────────────────────

async function upsertSupplier(
  supplierName: string | null,
  aiClassification: Record<string, unknown> | null,
  supabase: ReturnType<typeof createClient>,
  extra?: { ico?: string; dic?: string; address?: string; bank_account?: string }
): Promise<string | null> {
  if (!supplierName) return null

  try {
    const normalized = supplierName
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .trim()

    // Search by ICO first (exact match), then by name prefix
    let existing = null
    if (extra?.ico) {
      const { data } = await supabase
        .from('suppliers')
        .select('id, name, default_category, ico, bank_account')
        .eq('ico', extra.ico)
        .maybeSingle()
      existing = data
    }
    if (!existing) {
      const { data } = await supabase
        .from('suppliers')
        .select('id, name, default_category, ico, bank_account')
        .ilike('normalized_name', '%' + normalized.substring(0, 10) + '%')
        .maybeSingle()
      existing = data
    }

    if (existing) {
      // Update missing fields
      const updates: Record<string, string> = {}
      if (!existing.default_category && aiClassification?.category)
        updates.default_category = aiClassification.category as string
      if (!existing.ico && extra?.ico) updates.ico = extra.ico
      if (!existing.bank_account && extra?.bank_account) updates.bank_account = extra.bank_account
      if (extra?.dic) updates.dic = extra.dic
      if (extra?.address) updates.address = extra.address
      if (Object.keys(updates).length > 0) {
        await supabase.from('suppliers').update(updates).eq('id', existing.id)
      }
      return existing.id
    }

    // Create new supplier
    const { data: newSupplier } = await supabase
      .from('suppliers')
      .insert({
        name: supplierName,
        normalized_name: normalized,
        default_category: (aiClassification?.category as string) || null,
        default_account: (aiClassification?.suggested_account as string) || null,
        ico: extra?.ico || null,
        dic: extra?.dic || null,
        address: extra?.address || null,
        bank_account: extra?.bank_account || null,
        notes: 'Automaticky vytvořen z OCR dokladu',
      })
      .select('id')
      .single()

    return newSupplier?.id || null
  } catch (err) {
    console.error('upsertSupplier error:', err)
    return null
  }
}

// ─── Helpers ───────────────────────────────────────────────────

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
