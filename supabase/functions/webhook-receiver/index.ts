// ===== MotoGo24 – Edge Function: Webhook Receiver (Stripe) =====
// Receives Stripe webhook events and processes payment confirmations server-side.
// Endpoint: POST /functions/v1/webhook-receiver
// Stripe sends: checkout.session.completed, payment_intent.succeeded

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

    // Verify Stripe signature if webhook secret is configured
    if (STRIPE_WEBHOOK_SECRET && signature) {
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
    } else {
      // In test mode without webhook secret — parse event directly
      event = JSON.parse(body) as Stripe.Event
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
