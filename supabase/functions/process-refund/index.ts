// ===== MotoGo24 – Edge Function: Process Refund (Stripe LIVE) =====
// Handles partial and full refunds for bookings and shop orders.
// Endpoint: POST /functions/v1/process-refund
// Body: { booking_id?, order_id?, amount?, reason? }
// If amount is omitted, full refund is issued.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
})

const PDFSHIFT_API_KEY = Deno.env.get('PDFSHIFT_API_KEY') || ''

async function htmlToPdf(html: string): Promise<Uint8Array | null> {
  if (!PDFSHIFT_API_KEY) return null
  try {
    const res = await fetch('https://api.pdfshift.io/v3/convert/pdf', {
      method: 'POST',
      headers: { 'X-API-Key': PDFSHIFT_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: html, format: 'A4', margin: '12mm', sandbox: false, use_print: false }),
    })
    if (!res.ok) return null
    return new Uint8Array(await res.arrayBuffer())
  } catch { return null }
}

const fmtPrice = (n: number) => Math.abs(n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })
const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'

function renderCreditNoteHtml(opts: {
  number: string; issueDate: string; reasonText: string; motoModel: string;
  refundAmount: number; refundPercent: number; bookingDates: string;
  customer: { full_name?: string; email?: string; phone?: string; street?: string; city?: string; zip?: string; ico?: string; dic?: string };
  originalInvoiceNumber?: string | null; stripeRefundId: string;
  cardBrand?: string | null; cardLast4?: string | null;
}): string {
  const c = opts.customer || {}
  const cardLine = opts.cardLast4
    ? `Refund proběhl na kartu ${(opts.cardBrand || 'CARD').toUpperCase()} **** ${opts.cardLast4}.`
    : 'Refund proběhl na původní platební kartu.'
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"><title>Dobropis ${opts.number}</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;margin:0;padding:24px;font-size:13px}
.hdr{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid #dc2626;padding-bottom:12px;margin-bottom:18px}
.hdr h1{margin:0;font-size:22px;color:#dc2626;letter-spacing:1px}
.hdr .num{font-size:14px;color:#4a5a52;margin-top:4px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px;margin-bottom:18px}
.box{border:1px solid #d4e8e0;border-radius:6px;padding:12px;background:#f8fbfa}
.box h3{margin:0 0 8px;font-size:12px;color:#4a5a52;text-transform:uppercase;letter-spacing:1px}
.box p{margin:2px 0;font-size:13px}
table{width:100%;border-collapse:collapse;margin:12px 0}
th{text-align:left;padding:8px;background:#1a2e22;color:#fff;font-size:12px;text-transform:uppercase;letter-spacing:1px}
td{padding:10px 8px;border-bottom:1px solid #eef4f0;font-size:13px}
tr.total td{background:#fef2f2;font-weight:800;font-size:15px;color:#dc2626;border-bottom:none}
.note{margin-top:18px;padding:12px;background:#fef2f2;border-left:4px solid #dc2626;border-radius:4px;font-size:12px;line-height:1.6}
.foot{margin-top:24px;padding-top:12px;border-top:1px solid #d4e8e0;font-size:11px;color:#4a5a52;text-align:center}
</style></head><body>
<div class="hdr">
  <div>
    <h1>DOBROPIS</h1>
    <div class="num">Číslo: <strong>${opts.number}</strong></div>
    <div class="num">Datum vystavení: ${opts.issueDate}</div>
    ${opts.originalInvoiceNumber ? `<div class="num">K dokladu: ${opts.originalInvoiceNumber}</div>` : ''}
  </div>
  <div style="text-align:right">
    <div style="font-size:18px;font-weight:800">MotoGo24</div>
    <div style="color:#4a5a52">Bc. Petra Semorádová</div>
    <div style="color:#4a5a52">Mezná 9, 393 01 Mezná</div>
    <div style="color:#4a5a52">IČO: 21874263</div>
  </div>
</div>
<div class="grid">
  <div class="box"><h3>Odběratel</h3>
    <p><strong>${c.full_name || '—'}</strong></p>
    ${c.street ? `<p>${c.street}</p>` : ''}
    ${(c.city || c.zip) ? `<p>${c.zip || ''} ${c.city || ''}</p>` : ''}
    ${c.ico ? `<p>IČO: ${c.ico}</p>` : ''}
    ${c.dic ? `<p>DIČ: ${c.dic}</p>` : ''}
    ${c.email ? `<p>${c.email}</p>` : ''}
    ${c.phone ? `<p>${c.phone}</p>` : ''}
  </div>
  <div class="box"><h3>Detaily refundu</h3>
    <p>Důvod: <strong>${opts.reasonText}</strong></p>
    <p>Rezervace: ${opts.motoModel}</p>
    <p>Termín: ${opts.bookingDates}</p>
    <p>Procento vrácení: <strong>${opts.refundPercent} %</strong></p>
    <p style="font-size:11px;color:#4a5a52;word-break:break-all">Stripe refund: ${opts.stripeRefundId}</p>
  </div>
</div>
<table>
  <thead><tr><th>Popis</th><th style="text-align:right">Částka</th></tr></thead>
  <tbody>
    <tr><td>Dobropis – ${opts.reasonText} (${opts.motoModel})</td><td style="text-align:right">−${fmtPrice(opts.refundAmount)} Kč</td></tr>
    <tr class="total"><td>K vrácení celkem</td><td style="text-align:right">−${fmtPrice(opts.refundAmount)} Kč</td></tr>
  </tbody>
</table>
<div class="note">
  <strong>${cardLine}</strong> Peníze obvykle dorazí do 5–7 pracovních dnů.<br>
  Tento dobropis slouží jako daňový doklad o vrácení platby.
</div>
<div class="foot">www.motogo24.cz · info@motogo24.cz · +420 774 256 271</div>
</body></html>`
}

interface RefundRequest {
  booking_id?: string
  order_id?: string
  amount?: number      // partial refund in CZK (omit for full refund)
  reason?: string      // 'cancellation' | 'shortening' | 'duplicate' | 'requested_by_customer'
}

// Idempotent helper: for an already-refunded booking, locate the credit note,
// regenerate its PDF if the storage file is missing or pdf_path is empty.
// Returns { creditNoteId, pdfPath, refundId } so the caller can return success.
async function ensureCreditNotePdf(
  supabase: any,
  bookingId: string,
  bk: { stripe_refund_id?: string | null; card_brand?: string | null; card_last4?: string | null },
): Promise<{ creditNoteId: string | null; pdfPath: string | null; refundId: string | null }> {
  try {
    const { data: cnRows } = await supabase.from('invoices')
      .select('id, number, pdf_path, stripe_refund_id, total, original_invoice_id, notes, created_at')
      .eq('booking_id', bookingId)
      .eq('type', 'credit_note')
      .neq('status', 'cancelled')
      .order('created_at', { ascending: false })
      .limit(1)
    if (!cnRows?.length) return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id || null }

    const cn = cnRows[0]
    const refundId = cn.stripe_refund_id || bk.stripe_refund_id || null
    if (cn.pdf_path) {
      // Verify file actually exists in storage; if missing, regenerate.
      try {
        const { data: blob } = await supabase.storage.from('documents').download(cn.pdf_path)
        if (blob && blob.size > 0) return { creditNoteId: cn.id, pdfPath: cn.pdf_path, refundId }
      } catch { /* file missing — fall through to regenerate */ }
    }

    // Regenerate PDF — load booking + customer for the template
    const { data: bk2 } = await supabase.from('bookings')
      .select('start_date, end_date, motorcycles(model), profiles:user_id(full_name, email, phone, street, city, zip, ico, dic)')
      .eq('id', bookingId).single()
    const refundedAmount = Math.abs(Number(cn.total || 0))
    const refundPercent = 100 // unknown without booking.total_price comparison; default 100%
    const reasonText = (cn.notes || '').includes('Storno') ? 'Storno rezervace'
      : (cn.notes || '').includes('Zkrácení') ? 'Zkrácení rezervace'
      : 'Vrácení platby zákazníkovi'

    let originalNumber: string | null = null
    if (cn.original_invoice_id) {
      const { data: orig } = await supabase.from('invoices')
        .select('number').eq('id', cn.original_invoice_id).single()
      originalNumber = orig?.number || null
    }

    const html = renderCreditNoteHtml({
      number: cn.number,
      issueDate: fmtDate(new Date().toISOString().slice(0, 10)),
      reasonText,
      motoModel: (bk2 as any)?.motorcycles?.model || 'motorky',
      refundAmount: refundedAmount,
      refundPercent,
      bookingDates: `${fmtDate(bk2?.start_date)} – ${fmtDate(bk2?.end_date)}`,
      customer: (bk2 as any)?.profiles || {},
      originalInvoiceNumber: originalNumber,
      stripeRefundId: refundId || '',
      cardBrand: bk.card_brand,
      cardLast4: bk.card_last4,
    })

    const pdfBytes = await htmlToPdf(html)
    let path: string
    if (pdfBytes) {
      path = `invoices/${cn.id}.pdf`
      await supabase.storage.from('documents').upload(
        path, new Blob([pdfBytes], { type: 'application/pdf' }),
        { upsert: true, contentType: 'application/pdf' },
      )
    } else {
      path = `invoices/${cn.id}.html`
      await supabase.storage.from('documents').upload(
        path, new Blob([html], { type: 'text/html' }),
        { upsert: true, contentType: 'text/html' },
      )
    }
    await supabase.from('invoices').update({ pdf_path: path }).eq('id', cn.id)
    return { creditNoteId: cn.id, pdfPath: path, refundId }
  } catch (e) {
    console.warn('[ensureCreditNotePdf] failed:', (e as Error).message)
    return { creditNoteId: null, pdfPath: null, refundId: bk.stripe_refund_id || null }
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    const body: RefundRequest = await req.json()
    const { booking_id, order_id, amount, reason } = body

    if (!booking_id && !order_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing booking_id or order_id', code: 'missing_identifier' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the Stripe payment_intent_id
    let stripePaymentIntentId: string | null = null
    let entityType = 'booking'
    let entityId = booking_id || order_id || ''
    let alreadyRefunded = false

    if (booking_id) {
      const { data } = await supabase.from('bookings')
        .select('stripe_payment_intent_id, total_price, payment_status, stripe_refund_id, card_brand, card_last4')
        .eq('id', booking_id)
        .single()

      if (!data) {
        return new Response(
          JSON.stringify({ success: false, error: 'Booking not found', code: 'not_found' }),
          { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      // Idempotency: if booking is already refunded, ensure the credit note has pdf_path
      // (regenerate if missing) and return success — DON'T call Stripe again.
      // This handles the scenario where a previous refund attempt partially succeeded
      // (Stripe refund went through, status updated, but PDF/email step failed).
      if (data.payment_status === 'refunded' || data.payment_status === 'partial_refund') {
        alreadyRefunded = true
        const result = await ensureCreditNotePdf(supabase, booking_id, data)
        return new Response(
          JSON.stringify({
            success: true,
            already_refunded: true,
            refund_id: data.stripe_refund_id || result.refundId,
            credit_note_id: result.creditNoteId,
            credit_note_pdf_path: result.pdfPath,
            card_brand: data.card_brand,
            card_last4: data.card_last4,
          }),
          { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      if (data.payment_status !== 'paid') {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Booking is not paid (current: ${data.payment_status}) — cannot refund`,
            code: 'not_paid',
            current_status: data.payment_status,
          }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      stripePaymentIntentId = data.stripe_payment_intent_id
    } else if (order_id) {
      entityType = 'shop'
      const { data } = await supabase.from('shop_orders')
        .select('stripe_payment_intent_id, total_amount, payment_status')
        .eq('id', order_id)
        .single()

      if (!data) {
        return new Response(
          JSON.stringify({ success: false, error: 'Order not found', code: 'not_found' }),
          { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      if (data.payment_status !== 'paid') {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Order is not paid (current: ${data.payment_status}) — cannot refund`,
            code: 'not_paid',
            current_status: data.payment_status,
          }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      stripePaymentIntentId = data.stripe_payment_intent_id
    }

    if (!stripePaymentIntentId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `No Stripe payment found for this ${entityType}. Refund must be processed manually.`,
          code: 'no_stripe_payment',
        }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Cap refund at the amount actually charged on Stripe.
    // Without this, edge cases (100% promo code → tiny payment, but DB-side
    // refund_amount computed from gross per-day pricing) make us request a
    // refund larger than the captured charge — Stripe then errors with
    // "Refund amount ... is greater than charge amount ..." and the user
    // sees "Něco se pokazilo. Zkus to prosím znovu."
    let refundableHaleru: number | null = null
    let refundableCZK: number | null = null
    try {
      const pi = await stripe.paymentIntents.retrieve(stripePaymentIntentId)
      const charged = pi.amount_received || pi.amount || 0
      // Subtract refunds already issued on this PI
      let alreadyRefunded = 0
      try {
        const refundsList = await stripe.refunds.list({ payment_intent: stripePaymentIntentId, limit: 100 })
        for (const r of refundsList.data) {
          if (r.status === 'succeeded' || r.status === 'pending') alreadyRefunded += r.amount
        }
      } catch { /* non-fatal */ }
      refundableHaleru = Math.max(0, charged - alreadyRefunded)
      refundableCZK = refundableHaleru / 100
    } catch (e) {
      console.warn('[process-refund] PI lookup failed:', (e as Error).message)
    }

    // Decide effective amount (in haléře). Null = full refund.
    let effectiveAmountHaleru: number | null = null
    if (amount && amount > 0) {
      effectiveAmountHaleru = Math.round(amount * 100)
      if (refundableHaleru != null && effectiveAmountHaleru > refundableHaleru) {
        console.warn(`[process-refund] requested ${effectiveAmountHaleru/100} CZK > refundable ${refundableHaleru/100} CZK — clamping`)
        effectiveAmountHaleru = refundableHaleru
      }
    } else if (refundableHaleru != null) {
      effectiveAmountHaleru = refundableHaleru
    }

    // Nothing left to refund (e.g. fully discounted booking that paid 0 Kč,
    // or already-refunded PI) — short-circuit with success so the caller
    // (web "Zkrátit a vrátit peníze" / change-bike flow) doesn't error out.
    if (effectiveAmountHaleru === 0) {
      if (booking_id) {
        await supabase.from('bookings').update({ payment_status: 'refunded' }).eq('id', booking_id)
      } else if (order_id) {
        await supabase.from('shop_orders').update({ payment_status: 'refunded' }).eq('id', order_id)
      }
      return new Response(
        JSON.stringify({
          success: true,
          refund_id: null,
          status: 'no_op',
          amount_refunded: 0,
          currency: 'czk',
          credit_note_id: null,
          card_brand: null,
          card_last4: null,
          note: 'Nothing left to refund (already refunded or amount paid was 0)',
        }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Create Stripe refund
    const refundParams: Stripe.RefundCreateParams = {
      payment_intent: stripePaymentIntentId,
      reason: reason === 'duplicate' ? 'duplicate' : 'requested_by_customer',
    }
    if (effectiveAmountHaleru != null && (refundableHaleru == null || effectiveAmountHaleru < refundableHaleru)) {
      refundParams.amount = effectiveAmountHaleru
    }

    const refund = await stripe.refunds.create(refundParams)

    // Look up card brand/last4 from the underlying Charge (used both on credit note and bookings).
    let cardBrand: string | null = null
    let cardLast4: string | null = null
    try {
      const chargeId = typeof refund.charge === 'string' ? refund.charge : (refund.charge as any)?.id
      if (chargeId) {
        const ch = await stripe.charges.retrieve(chargeId)
        cardBrand = ch?.payment_method_details?.card?.brand || null
        cardLast4 = ch?.payment_method_details?.card?.last4 || null
      }
    } catch (e) { console.warn('[process-refund] charge retrieve failed:', (e as Error).message) }

    // Update payment_status in DB
    const refundedAmountCZK = refund.amount / 100
    if (booking_id) {
      const newStatus = (!amount || refund.status === 'succeeded') ? 'refunded' : 'partial_refund'
      const bkPatch: Record<string, any> = { payment_status: newStatus, stripe_refund_id: refund.id }
      if (cardBrand) bkPatch.card_brand = cardBrand
      if (cardLast4) bkPatch.card_last4 = cardLast4
      await supabase.from('bookings').update(bkPatch).eq('id', booking_id)
    } else if (order_id) {
      await supabase.from('shop_orders')
        .update({ payment_status: 'refunded' })
        .eq('id', order_id)
    }

    // Auto-generate credit note (dobropis) for booking refunds
    let creditNoteId: string | null = null
    if (booking_id) {
      try {
        // Fetch booking data for the credit note
        const { data: bk } = await supabase.from('bookings')
          .select('user_id, total_price, start_date, end_date, motorcycles(model), profiles:user_id(full_name, email, phone, street, city, zip, ico, dic)')
          .eq('id', booking_id).single()
        if (bk) {
          const refundPercent = amount ? Math.round((amount / Number(bk.total_price || 1)) * 100) : 100
          const reasonText = reason === 'cancellation' ? 'Storno rezervace'
            : reason === 'shortening' ? 'Zkrácení rezervace'
            : reason === 'duplicate' ? 'Duplicitní platba'
            : 'Vrácení platby zákazníkovi'

          // Find original invoice to reference
          const { data: origInvs } = await supabase.from('invoices')
            .select('id, type, number')
            .eq('booking_id', booking_id)
            .neq('status', 'cancelled')
            .in('type', ['final', 'payment_receipt', 'advance', 'proforma'])
            .order('issue_date', { ascending: false })
            .limit(1)
          const originalInvoiceId = origInvs?.[0]?.id || null
          const originalInvoiceNumber = origInvs?.[0]?.number || null

          // Idempotency: if a credit_note already exists for this booking + refund, reuse it
          const { data: existingCn } = await supabase.from('invoices')
            .select('id, number, pdf_path')
            .eq('booking_id', booking_id)
            .eq('type', 'credit_note')
            .eq('stripe_refund_id', refund.id)
            .limit(1)
          let cnNumber: string
          let cnId: string | null = null

          if (existingCn?.length) {
            cnId = existingCn[0].id
            cnNumber = existingCn[0].number
          } else {
            // Generate credit note number (DB-YYYY-NNNN)
            const year = new Date().getFullYear()
            const { data: lastCN } = await supabase.from('invoices')
              .select('number')
              .like('number', `DB-${year}-%`)
              .order('number', { ascending: false })
              .limit(1)
            let seq = 1
            if (lastCN?.length) {
              const m = lastCN[0].number.match(/-(\d+)$/)
              if (m) seq = parseInt(m[1], 10) + 1
            }
            cnNumber = `DB-${year}-${String(seq).padStart(4, '0')}`

            const issueDate = new Date().toISOString().slice(0, 10)
            const motoModel = (bk as any).motorcycles?.model || 'motorky'
            const { data: cnInv } = await supabase.from('invoices').insert({
              number: cnNumber,
              type: 'credit_note',
              customer_id: bk.user_id,
              booking_id,
              items: [{
                description: `Dobropis – ${reasonText} (${motoModel})`,
                qty: 1,
                unit_price: -refundedAmountCZK,
              }],
              subtotal: -refundedAmountCZK,
              tax_amount: 0,
              total: -refundedAmountCZK,
              notes: `Dobropis k rezervaci. ${refundPercent < 100 ? `Částečný refund ${refundPercent}%.` : 'Plný refund.'} ${reasonText}`,
              issue_date: issueDate,
              due_date: issueDate,
              status: 'issued',
              source: 'refund',
              variable_symbol: cnNumber,
              original_invoice_id: originalInvoiceId,
              stripe_refund_id: refund.id,
            }).select('id').single()

            cnId = cnInv?.id || null

            // Create negative accounting entry only on first creation
            await supabase.from('accounting_entries').insert({
              type: 'expense',
              amount: -refundedAmountCZK,
              description: `Dobropis ${cnNumber} – ${reasonText}`,
              category: 'refund',
              date: issueDate,
              booking_id,
            })
          }

          creditNoteId = cnId

          // Render and upload dobropis PDF/HTML so it can be attached to the cancellation email.
          if (cnId) {
            try {
              const motoModel2 = (bk as any).motorcycles?.model || 'motorky'
              const html = renderCreditNoteHtml({
                number: cnNumber,
                issueDate: fmtDate(new Date().toISOString().slice(0, 10)),
                reasonText,
                motoModel: motoModel2,
                refundAmount: refundedAmountCZK,
                refundPercent,
                bookingDates: `${fmtDate(bk.start_date)} – ${fmtDate(bk.end_date)}`,
                customer: (bk as any).profiles || {},
                originalInvoiceNumber,
                stripeRefundId: refund.id,
                cardBrand,
                cardLast4,
              })
              const pdfBytes = await htmlToPdf(html)
              let path: string
              if (pdfBytes) {
                path = `invoices/${cnId}.pdf`
                await supabase.storage.from('documents').upload(
                  path, new Blob([pdfBytes], { type: 'application/pdf' }),
                  { upsert: true, contentType: 'application/pdf' },
                )
              } else {
                path = `invoices/${cnId}.html`
                await supabase.storage.from('documents').upload(
                  path, new Blob([html], { type: 'text/html' }),
                  { upsert: true, contentType: 'text/html' },
                )
              }
              await supabase.from('invoices').update({ pdf_path: path }).eq('id', cnId)
            } catch (pdfErr) {
              console.warn('[process-refund] credit note PDF render failed:', (pdfErr as Error).message)
            }
          }
        }
      } catch (cnErr) {
        console.error('Credit note generation failed:', (cnErr as Error).message)
        // Non-blocking — refund was already processed
      }
    }

    // Log to debug_log
    try {
      await supabase.from('debug_log').insert({
        source: 'process-refund',
        action: 'stripe_refund_created',
        component: entityType,
        status: 'ok',
        request_data: { booking_id, order_id, amount, reason },
        response_data: { refund_id: refund.id, status: refund.status, amount_refunded: refundedAmountCZK, credit_note_id: creditNoteId },
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({
        success: true,
        refund_id: refund.id,
        status: refund.status,
        amount_refunded: refundedAmountCZK,
        currency: refund.currency,
        credit_note_id: creditNoteId,
        card_brand: cardBrand,
        card_last4: cardLast4,
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Refund error:', err)

    try {
      await supabase.from('debug_log').insert({
        source: 'process-refund',
        action: 'stripe_refund_error',
        component: 'stripe',
        status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({ success: false, error: 'Refund failed: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
