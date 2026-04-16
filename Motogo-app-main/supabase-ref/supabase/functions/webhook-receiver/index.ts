// ===== MotoGo24 – Edge Function: Webhook Receiver (Stripe LIVE) =====
// Receives Stripe webhook events and processes payment confirmations server-side.
// Endpoint: POST /functions/v1/webhook-receiver
// Stripe sends: checkout.session.completed, payment_intent.succeeded, charge.refunded, payout.paid

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { confirmBookingPayment, confirmSosPayment, confirmShopPayment, ingestFinancialEvent } from './payment-confirmers.ts'
import { syncCardFromSetupSession, syncCardsForCustomer } from './stripe-card-sync.ts'

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
        body, signature, STRIPE_WEBHOOK_SECRET
      )
    } catch (err) {
      console.error('Webhook signature verification failed:', (err as Error).message)
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'signature_verification_failed',
          component: 'stripe', status: 'error',
          error_message: (err as Error).message,
        })
      } catch (e) { /* ignore */ }
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Log incoming webhook
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver', action: 'webhook_received',
        component: 'stripe', status: 'ok',
        request_data: { event_type: event.type, event_id: event.id },
      })
    } catch (e) { /* ignore */ }

    // Handle events
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as Stripe.Checkout.Session
      const metadata = session.metadata || {}
      const paymentType = metadata.type || 'booking'
      const stripePaymentIntentId = typeof session.payment_intent === 'string'
        ? session.payment_intent
        : (session.payment_intent as any)?.id || null

      if (session.mode === 'setup' && metadata.action === 'add_card') {
        await syncCardFromSetupSession(supabase, session)
      } else if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        await confirmBookingPayment(supabase, metadata.booking_id, session.id, stripePaymentIntentId)
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

      // Auto-save card: attach PM to customer and sync to Supabase
      if (paymentIntent.customer && paymentIntent.payment_method) {
        const custId = typeof paymentIntent.customer === 'string'
          ? paymentIntent.customer : (paymentIntent.customer as any)?.id
        const pmId = typeof paymentIntent.payment_method === 'string'
          ? paymentIntent.payment_method : (paymentIntent.payment_method as any)?.id
        if (custId && pmId) {
          try {
            await stripe.paymentMethods.attach(pmId, { customer: custId })
          } catch (e) {
            // Already attached — ignore
          }
          await syncCardsForCustomer(supabase, custId)
        }
      }

      // Enrich financial event with booking/order details
      const feMetadata: Record<string, any> = {
        stripe_payment_intent_id: paymentIntent.id,
        stripe_customer: paymentIntent.customer,
        payment_type: paymentType,
        payment_method: 'card',
        received_date: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10),
      }

      // Auto-fill supplier (= our company) and document details
      feMetadata.supplier_name = 'Bc. Petra Semorádová'
      feMetadata.supplier_ico = '21874263'
      feMetadata.supplier_bank_account = '670100-2225851630/6210'

      if ((paymentType === 'booking' || paymentType === 'extension') && metadata.booking_id) {
        try {
          const { data: bk } = await supabase.from('bookings')
            .select('id, start_date, end_date, total_price, user_id, motorcycles(model, spz), profiles:user_id(full_name, email)')
            .eq('id', metadata.booking_id).single()
          if (bk) {
            const { data: inv } = await supabase.from('invoices')
              .select('number, variable_symbol')
              .eq('booking_id', metadata.booking_id)
              .in('type', ['payment_receipt', 'advance', 'proforma'])
              .order('issue_date', { ascending: false })
              .limit(1)
            feMetadata.invoice_number = inv?.[0]?.number || `RES-${metadata.booking_id.slice(-8).toUpperCase()}`
            feMetadata.variable_symbol = inv?.[0]?.variable_symbol || inv?.[0]?.number || ''
            feMetadata.customer_name = (bk as any).profiles?.full_name || ''
            feMetadata.customer_email = (bk as any).profiles?.email || ''
            feMetadata.booking_model = (bk as any).motorcycles?.model || ''
            feMetadata.booking_spz = (bk as any).motorcycles?.spz || ''
            feMetadata.booking_dates = `${bk.start_date} – ${bk.end_date}`
            feMetadata.due_date = new Date(paymentIntent.created * 1000).toISOString().slice(0, 10)
          }
        } catch (e) { /* ignore enrichment errors */ }
      } else if (paymentType === 'shop' && metadata.order_id) {
        try {
          const { data: ord } = await supabase.from('shop_orders')
            .select('order_number, total_amount, profiles:customer_id(full_name, email)')
            .eq('id', metadata.order_id).single()
          if (ord) {
            feMetadata.invoice_number = ord.order_number || `OBJ-${metadata.order_id.slice(-8).toUpperCase()}`
            feMetadata.variable_symbol = ord.order_number || ''
            feMetadata.customer_name = (ord as any).profiles?.full_name || ''
            feMetadata.due_date = new Date(paymentIntent.created * 1000).toISOString().slice(0, 10)
          }
        } catch (e) { /* ignore */ }
      }

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue', source: 'stripe',
        amount_czk: paymentIntent.amount / 100, vat_rate: 0,
        duzp: new Date(paymentIntent.created * 1000).toISOString().slice(0, 10),
        linked_entity_type: paymentType || 'booking',
        linked_entity_id: metadata.booking_id || metadata.order_id || null,
        confidence_score: 1.0, status: 'validated',
        metadata: feMetadata,
      })
    } else if (event.type === 'charge.refunded') {
      const charge = event.data.object as Stripe.Charge
      const refundReason = charge.refunds?.data?.[0]?.reason || null
      const chargeMeta = charge.metadata || {}

      // Enrich refund with booking details
      const refundFeMeta: Record<string, any> = {
        refund_reason: refundReason,
        original_payment_intent: charge.payment_intent,
        stripe_charge_id: charge.id,
        payment_method: 'card',
        supplier_name: 'Bc. Petra Semorádová',
        supplier_ico: '21874263',
        received_date: new Date().toISOString().slice(0, 10),
      }
      let linkedId: string | null = null
      let linkedType: string | null = null

      // Try to find linked booking via payment_intent
      if (charge.payment_intent) {
        try {
          const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : (charge.payment_intent as any)?.id
          if (piId) {
            const { data: bk } = await supabase.from('bookings')
              .select('id, motorcycles(model), profiles:user_id(full_name)')
              .eq('stripe_payment_intent_id', piId).single()
            if (bk) {
              linkedId = bk.id
              linkedType = 'booking'
              refundFeMeta.customer_name = (bk as any).profiles?.full_name || ''
              refundFeMeta.booking_model = (bk as any).motorcycles?.model || ''
              refundFeMeta.invoice_number = `Refund RES-${bk.id.slice(-8).toUpperCase()}`
            }
          }
        } catch (e) { /* ignore */ }
      }

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue', source: 'stripe',
        amount_czk: -(charge.amount_refunded / 100), vat_rate: 0,
        duzp: new Date().toISOString().slice(0, 10),
        linked_entity_type: linkedType, linked_entity_id: linkedId,
        confidence_score: 1.0, status: 'validated',
        metadata: refundFeMeta,
      })
    } else if (event.type === 'payout.paid') {
      const payout = event.data.object as Stripe.Payout

      await ingestFinancialEvent(supabase, {
        event_type: 'revenue', source: 'stripe',
        amount_czk: payout.amount / 100, vat_rate: 0,
        duzp: new Date((payout as any).arrival_date * 1000).toISOString().slice(0, 10),
        linked_entity_type: null, linked_entity_id: null,
        confidence_score: 1.0, status: 'validated',
        metadata: {
          stripe_payout_id: payout.id,
          arrival_date: (payout as any).arrival_date,
        },
      })
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Webhook error:', err)
    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver', action: 'webhook_error',
        component: 'stripe', status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({ error: 'Webhook processing failed' }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
