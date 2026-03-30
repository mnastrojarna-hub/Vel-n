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

interface RefundRequest {
  booking_id?: string
  order_id?: string
  amount?: number      // partial refund in CZK (omit for full refund)
  reason?: string      // 'cancellation' | 'shortening' | 'duplicate' | 'requested_by_customer'
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
        JSON.stringify({ success: false, error: 'Missing booking_id or order_id' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the Stripe payment_intent_id
    let stripePaymentIntentId: string | null = null
    let entityType = 'booking'
    let entityId = booking_id || order_id || ''

    if (booking_id) {
      const { data } = await supabase.from('bookings')
        .select('stripe_payment_intent_id, total_price, payment_status')
        .eq('id', booking_id)
        .single()

      if (!data) {
        return new Response(
          JSON.stringify({ success: false, error: 'Booking not found' }),
          { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      if (data.payment_status !== 'paid') {
        return new Response(
          JSON.stringify({ success: false, error: 'Booking is not paid — cannot refund' }),
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
          JSON.stringify({ success: false, error: 'Order not found' }),
          { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      if (data.payment_status !== 'paid') {
        return new Response(
          JSON.stringify({ success: false, error: 'Order is not paid — cannot refund' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      stripePaymentIntentId = data.stripe_payment_intent_id
    }

    if (!stripePaymentIntentId) {
      return new Response(
        JSON.stringify({ success: false, error: 'No Stripe payment found for this ' + entityType + '. Refund must be processed manually.' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Create Stripe refund
    const refundParams: Stripe.RefundCreateParams = {
      payment_intent: stripePaymentIntentId,
      reason: reason === 'duplicate' ? 'duplicate' : 'requested_by_customer',
    }
    if (amount && amount > 0) {
      refundParams.amount = Math.round(amount * 100) // CZK → haléře
    }

    const refund = await stripe.refunds.create(refundParams)

    // Update payment_status in DB
    const refundedAmountCZK = refund.amount / 100
    if (booking_id) {
      const newStatus = (!amount || refund.status === 'succeeded') ? 'refunded' : 'partial_refund'
      await supabase.from('bookings')
        .update({ payment_status: newStatus })
        .eq('id', booking_id)
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
          .select('user_id, total_price, start_date, end_date, motorcycles(model)')
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
          const cnNumber = `DB-${year}-${String(seq).padStart(4, '0')}`

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

          creditNoteId = cnInv?.id || null

          // Create negative accounting entry
          await supabase.from('accounting_entries').insert({
            type: 'expense',
            amount: -refundedAmountCZK,
            description: `Dobropis ${cnNumber} – ${reasonText}`,
            category: 'refund',
            date: issueDate,
            booking_id,
          })
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
