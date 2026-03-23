// ===== MotoGo24 – Edge Function: Webhook Receiver (Stripe LIVE) =====
// Receives Stripe webhook events and processes payment confirmations server-side.
// Endpoint: POST /functions/v1/webhook-receiver
// Stripe sends: checkout.session.completed, payment_intent.succeeded, charge.refunded, payout.paid

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
})

const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET') || ''

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  try {
    const body = await req.text()
    const signature = req.headers.get('stripe-signature')

    let event: Stripe.Event

    // Verify Stripe signature — REQUIRED in production
    if (!STRIPE_WEBHOOK_SECRET) {
      console.error('STRIPE_WEBHOOK_SECRET not configured')
      return new Response(
        JSON.stringify({ error: 'Webhook secret not configured' }),
        { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }
    if (!signature) {
      return new Response(
        JSON.stringify({ error: 'Missing stripe-signature header' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }
    try {
      event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        STRIPE_WEBHOOK_SECRET
      )
    } catch (err) {
      console.error('Webhook signature verification failed:', (err as Error).message)
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'signature_verification_failed',
        component: 'stripe',
        status: 'error',
        error_message: (err as Error).message,
      }).catch(() => {})
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Log incoming webhook
    await supabase.from('debug_log').insert({
      source: 'webhook-receiver',
      action: 'webhook_received',
      component: 'stripe',
      status: 'ok',
      request_data: { event_type: event.type, event_id: event.id },
    }).catch(() => {})

    // Handle events
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session
      const metadata = session.metadata || {}
      const paymentType = metadata.type || 'booking'

      if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        await confirmBookingPayment(supabase, metadata.booking_id, session.id)
      } else if (paymentType === 'shop' && metadata.order_id) {
        await confirmShopPayment(supabase, metadata.order_id, session.id)
      } else if (paymentType === 'sos' && metadata.booking_id) {
        await confirmSosPayment(supabase, metadata.booking_id, metadata.incident_id, session.id)
      }
    } else if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object as Stripe.PaymentIntent
      const metadata = paymentIntent.metadata || {}
      const paymentType = metadata.type || 'booking'

      if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        await confirmBookingPayment(supabase, metadata.booking_id, paymentIntent.id)
      } else if (paymentType === 'shop' && metadata.order_id) {
        await confirmShopPayment(supabase, metadata.order_id, paymentIntent.id)
      } else if (paymentType === 'sos' && metadata.booking_id) {
        await confirmSosPayment(supabase, metadata.booking_id, metadata.incident_id, paymentIntent.id)
      }

      // ── Financial event: revenue from Stripe payment ──
      await ingestFinancialEvent(supabase, {
        event_type: 'revenue',
        source: 'stripe',
        amount_czk: paymentIntent.amount / 100,
        vat_rate: 0, // firma není plátce DPH
        duzp: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10),
        linked_entity_type: paymentType || 'booking',
        linked_entity_id: metadata.booking_id || metadata.order_id || null,
        confidence_score: 1.0,
        status: 'validated',
        metadata: {
          stripe_payment_intent_id: paymentIntent.id,
          stripe_customer: paymentIntent.customer,
          payment_type: paymentType,
        },
      })
    } else if (event.type === 'charge.refunded') {
      const charge = event.data.object as Stripe.Charge
      const refundReason = charge.refunds?.data?.[0]?.reason || null

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue',
        source: 'stripe',
        amount_czk: -(charge.amount_refunded / 100), // záporná hodnota
        vat_rate: 0, // firma není plátce DPH
        duzp: new Date().toISOString().slice(0, 10),
        linked_entity_type: null,
        linked_entity_id: null,
        confidence_score: 1.0,
        status: 'validated',
        metadata: {
          refund_reason: refundReason,
          original_payment_intent: charge.payment_intent,
          stripe_charge_id: charge.id,
        },
      })
    } else if (event.type === 'payout.paid') {
      const payout = event.data.object as Stripe.Payout

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue',
        source: 'stripe',
        amount_czk: payout.amount / 100,
        vat_rate: 0, // firma není plátce DPH
        duzp: new Date((payout as any).arrival_date * 1000).toISOString().slice(0, 10),
        linked_entity_type: null,
        linked_entity_id: null,
        confidence_score: 1.0,
        status: 'validated',
        metadata: {
          stripe_payout_id: payout.id,
          arrival_date: (payout as any).arrival_date,
        },
      })
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Webhook error:', err)
    await supabase.from('debug_log').insert({
      source: 'webhook-receiver',
      action: 'webhook_error',
      component: 'stripe',
      status: 'error',
      error_message: (err as Error).message,
    }).catch(() => {})

    return new Response(
      JSON.stringify({ error: 'Webhook processing failed' }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})

/** Confirm booking payment via existing RPC */
async function confirmBookingPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  transactionId: string
) {
  try {
    const { data, error } = await supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: 'card',
    })

    await supabase.from('debug_log').insert({
      source: 'webhook-receiver',
      action: 'confirm_booking_payment',
      component: 'stripe',
      status: error ? 'error' : 'ok',
      request_data: { booking_id: bookingId, transaction_id: transactionId },
      response_data: data,
      error_message: error?.message || null,
    }).catch(() => {})

    if (error) {
      console.error('confirm_payment RPC failed:', error.message)
      // Fallback: direct update
      await supabase.from('bookings')
        .update({ payment_status: 'paid', payment_method: 'card' })
        .eq('id', bookingId)
    }

    // Auto-generate documents (non-blocking, best-effort)
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
      // Generate advance invoice (ZF)
      await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SUPABASE_ANON_KEY}`, 'apikey': SUPABASE_ANON_KEY },
        body: JSON.stringify({ type: 'advance', booking_id: bookingId }),
      }).catch(() => {})
      // Generate contract + VOP
      await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SUPABASE_ANON_KEY}`, 'apikey': SUPABASE_ANON_KEY },
        body: JSON.stringify({ type: 'rental_contract', booking_id: bookingId }),
      }).catch(() => {})
    } catch (_) { /* doc gen is best-effort */ }
  } catch (err) {
    console.error('confirmBookingPayment error:', err)
  }
}

/** Confirm SOS replacement booking payment (mark paid + active) */
async function confirmSosPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  incidentId: string | undefined,
  transactionId: string
) {
  try {
    // Mark SOS replacement booking as paid + active
    const { error } = await supabase.from('bookings')
      .update({
        payment_status: 'paid',
        payment_method: 'card',
        status: 'active',
        confirmed_at: new Date().toISOString(),
        picked_up_at: new Date().toISOString(),
      })
      .eq('id', bookingId)

    await supabase.from('debug_log').insert({
      source: 'webhook-receiver',
      action: 'confirm_sos_payment',
      component: 'stripe',
      status: error ? 'error' : 'ok',
      request_data: { booking_id: bookingId, incident_id: incidentId, transaction_id: transactionId },
      error_message: error?.message || null,
    }).catch(() => {})

    if (error) {
      console.error('SOS booking update failed:', error.message)
    }
  } catch (err) {
    console.error('confirmSosPayment error:', err)
  }
}

/** Idempotent insert into financial_events (skips duplicates by stripe ID in metadata) */
async function ingestFinancialEvent(
  supabase: ReturnType<typeof createClient>,
  eventData: {
    event_type: string
    source: string
    amount_czk: number
    vat_rate: number
    duzp: string
    linked_entity_type: string | null
    linked_entity_id: string | null
    confidence_score: number
    status: string
    metadata: Record<string, any>
  }
) {
  try {
    // Idempotence: check if this Stripe event was already ingested
    const stripeId = eventData.metadata.stripe_payment_intent_id
      || eventData.metadata.stripe_charge_id
      || eventData.metadata.stripe_payout_id

    if (stripeId) {
      const idempotencyKey = eventData.metadata.stripe_payment_intent_id
        ? 'stripe_payment_intent_id'
        : eventData.metadata.stripe_charge_id
          ? 'stripe_charge_id'
          : 'stripe_payout_id'

      const { data: existing } = await supabase
        .from('financial_events')
        .select('id')
        .eq(`metadata->>${idempotencyKey}`, stripeId)
        .maybeSingle()

      if (existing) {
        console.log(`Financial event already exists for ${idempotencyKey}=${stripeId}, skipping`)
        return
      }
    }

    const { error } = await supabase.from('financial_events').insert(eventData)

    if (error) {
      console.error('Failed to insert financial_event:', error.message)
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'financial_event_insert_failed',
        component: 'stripe',
        status: 'error',
        request_data: eventData,
        error_message: error.message,
      }).catch(() => {})
    }
  } catch (err) {
    console.error('ingestFinancialEvent error:', err)
  }
}

/** Confirm shop payment via existing RPC */
async function confirmShopPayment(
  supabase: ReturnType<typeof createClient>,
  orderId: string,
  transactionId: string
) {
  try {
    const { data, error } = await supabase.rpc('confirm_shop_payment', {
      p_order_id: orderId,
      p_method: 'card',
    })

    await supabase.from('debug_log').insert({
      source: 'webhook-receiver',
      action: 'confirm_shop_payment',
      component: 'stripe',
      status: error ? 'error' : 'ok',
      request_data: { order_id: orderId, transaction_id: transactionId },
      response_data: data,
      error_message: error?.message || null,
    }).catch(() => {})

    if (error) {
      console.error('confirm_shop_payment RPC failed:', error.message)
      // Fallback: direct update
      await supabase.from('shop_orders')
        .update({ payment_status: 'paid', payment_method: 'card' })
        .eq('id', orderId)
    }
  } catch (err) {
    console.error('confirmShopPayment error:', err)
  }
}
