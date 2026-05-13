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
      let paymentType = metadata.type || 'booking'
      let resolvedOrderId: string | null = metadata.order_id || null
      let resolvedBookingId: string | null = metadata.booking_id || null
      const stripePaymentIntentId = typeof session.payment_intent === 'string'
        ? session.payment_intent
        : (session.payment_intent as any)?.id || null

      // Fallback: pokud Stripe metadata chybí (Apple Pay, Link, edge cases),
      // použij client_reference_id (process-payment ho nastavuje na booking_id/order_id).
      const clientRef = (session as any).client_reference_id as string | null
      if (!resolvedOrderId && !resolvedBookingId && clientRef) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders')
            .select('id').eq('id', clientRef).maybeSingle()
          if (shopMatch?.id) { resolvedOrderId = shopMatch.id; paymentType = 'shop' }
          else {
            const { data: bkMatch } = await supabase.from('bookings')
              .select('id').eq('id', clientRef).maybeSingle()
            if (bkMatch?.id) { resolvedBookingId = bkMatch.id; paymentType = 'booking' }
          }
        } catch (e) { console.warn('[webhook] client_reference_id lookup failed:', e) }
      }

      // Druhý fallback: dohledej podle stripe_session_id (process-payment ho ukládá do shop_orders/bookings)
      if (!resolvedOrderId && !resolvedBookingId) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders')
            .select('id').eq('stripe_session_id', session.id).maybeSingle()
          if (shopMatch?.id) { resolvedOrderId = shopMatch.id; paymentType = 'shop' }
          else {
            const { data: bkMatch } = await supabase.from('bookings')
              .select('id').eq('stripe_session_id', session.id).maybeSingle()
            if (bkMatch?.id) { resolvedBookingId = bkMatch.id; paymentType = 'booking' }
          }
        } catch (e) { console.warn('[webhook] session_id lookup failed:', e) }
      }

      if (session.mode === 'setup' && metadata.action === 'add_card') {
        await syncCardFromSetupSession(supabase, session)
      } else if (session.mode === 'setup' && metadata.action === 'verify_free_booking' && resolvedBookingId) {
        // 0 Kč rezervace přes Stripe Checkout setup — karta ověřena, žádný charge.
        // Spustíme stejný flow jako u placené rezervace: confirm_payment + booking_reserved mail
        // + door codes (trigger) + KF generace. Bez tohoto by zákazník nedostal mail ani doklady.
        try {
          await confirmBookingPayment(supabase, resolvedBookingId, session.id, stripePaymentIntentId)
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'free_verify_confirmed',
            component: 'stripe', status: 'ok',
            request_data: { session_id: session.id, booking_id: resolvedBookingId },
          }).catch(() => {})
        } catch (e) {
          console.error('[webhook] free verify exception:', (e as Error).message)
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'free_verify_confirm_failed',
            component: 'stripe', status: 'error',
            error_message: (e as Error).message,
            request_data: { session_id: session.id, booking_id: resolvedBookingId },
          }).catch(() => {})
        }
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if ((paymentType === 'booking' || paymentType === 'extension') && resolvedBookingId) {
        await confirmBookingPayment(supabase, resolvedBookingId, session.id, stripePaymentIntentId)
        // Bundled e-shop upsell paid in the same session — confirm shop side too (separate invoice + email)
        if (metadata.shop_order_id) {
          try {
            await confirmShopPayment(supabase, metadata.shop_order_id, session.id, stripePaymentIntentId)
          } catch (e) { console.warn('[webhook] bundled shop confirm failed:', e) }
        }
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if (paymentType === 'shop' && resolvedOrderId) {
        await confirmShopPayment(supabase, resolvedOrderId, session.id, stripePaymentIntentId)
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else if (paymentType === 'sos' && resolvedBookingId) {
        await confirmSosPayment(supabase, resolvedBookingId, metadata.incident_id, session.id, stripePaymentIntentId)
        if (session.customer) {
          await syncCardsForCustomer(supabase, session.customer as string)
        }
      } else {
        try {
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'unmatched_session_completed',
            component: 'stripe', status: 'warning',
            request_data: { session_id: session.id, metadata, client_reference_id: clientRef },
          })
        } catch { /* ignore */ }
      }
    } else if (event.type === 'payment_intent.succeeded') {
      const paymentIntent = event.data.object as Stripe.PaymentIntent
      const metadata = paymentIntent.metadata || {}
      let paymentType = metadata.type || 'booking'
      let resolvedOrderId: string | null = metadata.order_id || null
      let resolvedBookingId: string | null = metadata.booking_id || null

      // Fallback: pokud Stripe Checkout Session metadata neproteklo do PaymentIntent,
      // dohledej order/booking podle stripe_payment_intent_id v DB.
      if (!resolvedOrderId && !resolvedBookingId) {
        try {
          const { data: shopMatch } = await supabase.from('shop_orders')
            .select('id').eq('stripe_payment_intent_id', paymentIntent.id).maybeSingle()
          if (shopMatch?.id) { resolvedOrderId = shopMatch.id; paymentType = 'shop' }
          else {
            const { data: bkMatch } = await supabase.from('bookings')
              .select('id').eq('stripe_payment_intent_id', paymentIntent.id).maybeSingle()
            if (bkMatch?.id) { resolvedBookingId = bkMatch.id; paymentType = 'booking' }
          }
        } catch (e) { console.warn('[webhook] PI fallback lookup failed:', e) }
      }

      if ((paymentType === 'booking' || paymentType === 'extension') && resolvedBookingId) {
        await confirmBookingPayment(supabase, resolvedBookingId, paymentIntent.id)
        if (metadata.shop_order_id) {
          try { await confirmShopPayment(supabase, metadata.shop_order_id, paymentIntent.id) }
          catch (e) { console.warn('[webhook] bundled shop confirm (intent) failed:', e) }
        }
      } else if (paymentType === 'shop' && resolvedOrderId) {
        await confirmShopPayment(supabase, resolvedOrderId, paymentIntent.id)
      } else if (paymentType === 'sos' && resolvedBookingId) {
        await confirmSosPayment(supabase, resolvedBookingId, metadata.incident_id, paymentIntent.id)
      }

      // Capture card brand + last4 from the underlying Charge so Velín booking detail
      // can show "Visa **** 4242" without an on-demand Stripe call.
      if (resolvedBookingId) {
        try {
          const chargeId = typeof (paymentIntent as any).latest_charge === 'string'
            ? (paymentIntent as any).latest_charge
            : (paymentIntent as any).latest_charge?.id || null
          if (chargeId) {
            const ch = await stripe.charges.retrieve(chargeId)
            const brand = ch?.payment_method_details?.card?.brand || null
            const last4 = ch?.payment_method_details?.card?.last4 || null
            if (brand || last4) {
              await supabase.from('bookings')
                .update({ card_brand: brand, card_last4: last4 })
                .eq('id', resolvedBookingId)
            }
          }
        } catch (e) { console.warn('[webhook] card brand/last4 capture failed:', (e as Error).message) }
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
      let linkedBooking: any = null
      if (charge.payment_intent) {
        try {
          const piId = typeof charge.payment_intent === 'string' ? charge.payment_intent : (charge.payment_intent as any)?.id
          if (piId) {
            const { data: bk } = await supabase.from('bookings')
              .select('id, status, payment_status, total_price, start_date, end_date, booking_source, cancelled_by_source, motorcycles(model), profiles:user_id(full_name, email)')
              .eq('stripe_payment_intent_id', piId).single()
            if (bk) {
              linkedBooking = bk
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

      // Refund handling — 2 scénáře:
      // 1) Stripe portál refund (booking ještě není cancelled): zacancelovat + mail
      // 2) Safety-net (booking už je cancelled, ale credit_note nebo mail chybí):
      //    proces-refund spadl po refunds.create() → DB neví, ale Stripe ano.
      //    Zde dohraje payment_status='refunded', stripe_refund_id, vystavění
      //    credit_note přes process-refund.alreadyRefunded recovery + odešleme mail.
      //    send-cancellation-email má vlastní idempotency check (sent_emails 30 min).
      if (linkedBooking) {
        try {
          const refund = charge.refunds?.data?.[0] || null
          const refundCzk = charge.amount_refunded / 100
          const total = Number(linkedBooking.total_price || 0)
          const refundPct = total > 0 ? Math.round((refundCzk / total) * 100) : 0
          const newPaymentStatus = refundPct >= 100 ? 'refunded' : 'partial_refund'
          const isFreshCancel = linkedBooking.status !== 'cancelled'

          // 1) UPDATE booking. Pokud nebyl cancelled, doplň cancellation pole.
          //    Pokud už byl cancelled (proces-refund flow), update jen payment_status+stripe_refund_id.
          const bkPatch: Record<string, any> = {
            payment_status: newPaymentStatus,
          }
          if (refund?.id) bkPatch.stripe_refund_id = refund.id
          if (isFreshCancel) {
            bkPatch.status = 'cancelled'
            bkPatch.cancelled_at = new Date().toISOString()
            bkPatch.cancelled_by_source = 'stripe_portal'
            bkPatch.cancellation_reason = refundReason
              ? `Refund přes Stripe portál (${refundReason})`
              : 'Refund přes Stripe portál'
          }
          await supabase.from('bookings').update(bkPatch).eq('id', linkedBooking.id)

          // 2) Vystavit credit_note (idempotentní). process-refund.alreadyRefunded
          //    branch teď s upraveným payment_status='refunded' + stripe_refund_id
          //    spustí createCreditNoteForExistingRefund (pokud row chybí) nebo
          //    ensureCreditNotePdf (pokud row je ale PDF chybí).
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'charge_refunded_safety_net',
            component: 'stripe', status: 'info',
            request_data: {
              booking_id: linkedBooking.id, refund_id: refund?.id || null,
              fresh_cancel: isFreshCancel, refund_pct: refundPct,
            },
          }).then(() => {}, () => {})
          await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/process-refund`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
            },
            body: JSON.stringify({
              booking_id: linkedBooking.id,
              amount: refundCzk,
              reason: 'cancellation',
            }),
          }).catch(e => console.warn('Webhook process-refund recovery failed:', e?.message))

          // 3) Mail s dobropisem. send-cancellation-email má idempotency (sent_emails
          //    30 min) — pokud cancel_booking_tracked / proces-refund už mail poslal,
          //    bude no-op. Pokud ne (proces-refund spadl), pošleme teď s přílohou.
          if (linkedBooking.profiles?.email) {
            await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-cancellation-email`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
              },
              body: JSON.stringify({
                booking_id: linkedBooking.id,
                customer_email: linkedBooking.profiles.email,
                customer_name: linkedBooking.profiles.full_name || '',
                motorcycle: linkedBooking.motorcycles?.model || '',
                start_date: linkedBooking.start_date,
                end_date: linkedBooking.end_date,
                cancellation_reason: refundReason
                  ? `Refund přes Stripe portál (${refundReason})`
                  : 'Refund přes Stripe portál',
                cancelled_by_source: isFreshCancel ? 'stripe_portal' : (linkedBooking.cancelled_by_source || 'customer'),
                refund_amount: refundCzk,
                refund_percent: refundPct,
                source: linkedBooking.booking_source || 'app',
              }),
            }).catch(e => console.warn('Webhook safety-net mail failed:', e?.message))
          }
        } catch (e) {
          console.warn('charge.refunded safety-net failed:', (e as Error).message)
        }
      }
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
