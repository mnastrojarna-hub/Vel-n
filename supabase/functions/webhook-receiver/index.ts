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
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver',
          action: 'signature_verification_failed',
          component: 'stripe',
          status: 'error',
          error_message: (err as Error).message,
        })
      } catch (_) { /* ignore */ }
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Log incoming webhook
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'webhook_received',
        component: 'stripe',
        status: 'ok',
        request_data: { event_type: event.type, event_id: event.id },
      })
    } catch (_) { /* ignore */ }

    // Handle events
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session
      const metadata = session.metadata || {}
      const paymentType = metadata.type || 'booking'
      const stripePaymentIntentId = typeof session.payment_intent === 'string'
        ? session.payment_intent
        : (session.payment_intent as any)?.id || null

      // Handle setup mode sessions (add card without payment)
      if (session.mode === 'setup' && metadata.action === 'add_card') {
        await syncCardFromSetupSession(supabase, session)
      } else if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        await confirmBookingPayment(supabase, metadata.booking_id, session.id, stripePaymentIntentId)
        // Sync cards after payment (card was saved via setup_future_usage)
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if (paymentType === 'shop' && metadata.order_id) {
        await confirmShopPayment(supabase, metadata.order_id, session.id, stripePaymentIntentId)
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if (paymentType === 'sos' && metadata.booking_id) {
        await confirmSosPayment(supabase, metadata.booking_id, metadata.incident_id, session.id, stripePaymentIntentId)
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
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
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'webhook_error',
        component: 'stripe',
        status: 'error',
        error_message: (err as Error).message,
      })
    } catch (_) { /* ignore */ }

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
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    const { data, error } = await supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: 'card',
    })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_booking_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { booking_id: bookingId, transaction_id: transactionId },
        response_data: data,
        error_message: error?.message || null,
      })
    } catch (_) { /* ignore */ }

    if (error) {
      console.error('confirm_payment RPC failed:', error.message)
      // Fallback: direct update — replicate confirm_payment RPC logic
      // start_date <= today → active (+picked_up_at), start_date > today → reserved (+confirmed_at)
      const { data: bk } = await supabase.from('bookings')
        .select('start_date')
        .eq('id', bookingId)
        .single()
      const today = new Date().toISOString().slice(0, 10)
      const startDate = bk?.start_date || today
      const isToday = startDate <= today
      await supabase.from('bookings')
        .update({
          payment_status: 'paid',
          payment_method: 'card',
          status: isToday ? 'active' : 'reserved',
          ...(isToday
            ? { picked_up_at: new Date().toISOString() }
            : { confirmed_at: new Date().toISOString() }),
        })
        .eq('id', bookingId)
    }

    // Save Stripe IDs for future refunds
    if (stripePaymentIntentId) {
      try {
        await supabase.from('bookings')
          .update({
            stripe_payment_intent_id: stripePaymentIntentId,
            stripe_session_id: transactionId,
          })
          .eq('id', bookingId)
      } catch (_) { /* ignore */ }
    }

    // Auto-generate documents (non-blocking, best-effort)
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

      // Generate advance invoice (ZF) — skip if one already exists
      const { data: existingZf } = await supabase.from('invoices')
        .select('id').eq('booking_id', bookingId)
        .in('type', ['advance', 'proforma']).limit(1)
      if (!existingZf?.length) {
        try {
          await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
            method: 'POST', headers,
            body: JSON.stringify({ type: 'advance', booking_id: bookingId }),
          })
        } catch (_) { /* ignore */ }
      }

      // Generate payment receipt (DP)
      try {
        await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id: bookingId }),
        })
      } catch (_) { /* ignore */ }

      // Generate contract + VOP
      try {
        await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'rental_contract', booking_id: bookingId }),
        })
      } catch (_) { /* ignore */ }
      try {
        await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'vop', booking_id: bookingId }),
        })
      } catch (_) { /* ignore */ }

      // Send confirmation email (with source detection for web-specific template)
      const { data: booking } = await supabase.from('bookings')
        .select('booking_source, user_id, moto_id, start_date, end_date, total_price, motorcycles(model, manual_url), profiles(full_name, email)')
        .eq('id', bookingId).single()

      if (booking?.profiles?.email) {
        const source = booking.booking_source || 'app'
        const moto = booking.motorcycles as { model?: string; manual_url?: string } | null
        const profile = booking.profiles as { full_name?: string; email?: string }

        try {
          await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
            method: 'POST', headers,
            body: JSON.stringify({
              type: 'booking_reserved',
              booking_id: bookingId,
              customer_email: profile.email,
              customer_name: profile.full_name || '',
              motorcycle: moto?.model || '',
              start_date: booking.start_date,
              end_date: booking.end_date,
              total_price: booking.total_price,
              source: source,
              manual_url: moto?.manual_url || '',
            }),
          })
        } catch (_) { /* ignore */ }
      }
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
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    // Mark SOS replacement booking as paid + active
    const updateData: Record<string, any> = {
      payment_status: 'paid',
      payment_method: 'card',
      status: 'active',
      confirmed_at: new Date().toISOString(),
      picked_up_at: new Date().toISOString(),
    }
    if (stripePaymentIntentId) {
      updateData.stripe_payment_intent_id = stripePaymentIntentId
      updateData.stripe_session_id = transactionId
    }
    const { error } = await supabase.from('bookings')
      .update(updateData)
      .eq('id', bookingId)

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_sos_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { booking_id: bookingId, incident_id: incidentId, transaction_id: transactionId },
        error_message: error?.message || null,
      })
    } catch (_) { /* ignore */ }

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
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver',
          action: 'financial_event_insert_failed',
          component: 'stripe',
          status: 'error',
          request_data: eventData,
          error_message: error.message,
        })
      } catch (_) { /* ignore */ }
    }
  } catch (err) {
    console.error('ingestFinancialEvent error:', err)
  }
}

/** Confirm shop payment via existing RPC */
async function confirmShopPayment(
  supabase: ReturnType<typeof createClient>,
  orderId: string,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    const { data, error } = await supabase.rpc('confirm_shop_payment', {
      p_order_id: orderId,
      p_method: 'card',
    })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_shop_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { order_id: orderId, transaction_id: transactionId },
        response_data: data,
        error_message: error?.message || null,
      })
    } catch (_) { /* ignore */ }

    if (error) {
      console.error('confirm_shop_payment RPC failed:', error.message)
      // Fallback: direct update
      await supabase.from('shop_orders')
        .update({ payment_status: 'paid', payment_method: 'card' })
        .eq('id', orderId)
    }

    // Save Stripe IDs for future refunds
    if (stripePaymentIntentId) {
      try {
        await supabase.from('shop_orders')
          .update({
            stripe_payment_intent_id: stripePaymentIntentId,
            stripe_session_id: transactionId,
          })
          .eq('id', orderId)
      } catch (_) { /* ignore */ }
    }
  } catch (err) {
    console.error('confirmShopPayment error:', err)
  }
}

/** Sync card details from a setup session (add card flow) to Supabase */
async function syncCardFromSetupSession(
  supabase: ReturnType<typeof createClient>,
  session: Stripe.Checkout.Session
) {
  try {
    const customerId = session.customer as string
    const userId = session.metadata?.user_id
    if (!customerId || !userId) return

    // Get the SetupIntent to find the payment method
    const setupIntentId = typeof session.setup_intent === 'string'
      ? session.setup_intent
      : (session.setup_intent as any)?.id
    if (!setupIntentId) return

    const setupIntent = await stripe.setupIntents.retrieve(setupIntentId)
    const pmId = typeof setupIntent.payment_method === 'string'
      ? setupIntent.payment_method
      : (setupIntent.payment_method as any)?.id
    if (!pmId) return

    const pm = await stripe.paymentMethods.retrieve(pmId)

    // Upsert card into payment_methods table
    await supabase.from('payment_methods').upsert({
      user_id: userId,
      stripe_payment_method_id: pm.id,
      brand: pm.card?.brand || 'unknown',
      last4: pm.card?.last4 || '****',
      exp_month: pm.card?.exp_month || null,
      exp_year: pm.card?.exp_year || null,
      holder_name: pm.billing_details?.name || null,
      is_default: false,
    }, { onConflict: 'stripe_payment_method_id' })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'card_saved_from_setup',
        component: 'stripe',
        status: 'ok',
        request_data: { user_id: userId, pm_id: pm.id, brand: pm.card?.brand, last4: pm.card?.last4 },
      })
    } catch (_) { /* ignore */ }
  } catch (e) {
    console.error('syncCardFromSetupSession error:', e)
  }
}

/** Sync all cards for a Stripe customer to Supabase payment_methods table */
async function syncCardsForCustomer(
  supabase: ReturnType<typeof createClient>,
  customerId: string
) {
  try {
    // Find user_id from profiles
    const { data: profile } = await supabase
      .from('profiles')
      .select('id')
      .eq('stripe_customer_id', customerId)
      .maybeSingle()
    if (!profile) return

    const customer = await stripe.customers.retrieve(customerId) as Stripe.Customer
    const methods = await stripe.paymentMethods.list({
      customer: customerId,
      type: 'card',
    })

    const defaultPmId = (customer.invoice_settings?.default_payment_method as string) || null

    // Remove old cards and insert fresh
    await supabase.from('payment_methods').delete().eq('user_id', profile.id)

    if (methods.data.length > 0) {
      const cards = methods.data.map((pm) => ({
        user_id: profile.id,
        stripe_payment_method_id: pm.id,
        brand: pm.card?.brand || 'unknown',
        last4: pm.card?.last4 || '****',
        exp_month: pm.card?.exp_month || null,
        exp_year: pm.card?.exp_year || null,
        holder_name: pm.billing_details?.name || null,
        is_default: pm.id === defaultPmId,
      }))
      await supabase.from('payment_methods').insert(cards)
    }
  } catch (e) {
    console.error('syncCardsForCustomer error:', e)
  }
}
