// ===== MotoGo24 – Edge Function: Process Payment (Stripe LIVE) =====
// Supports booking, shop, extension, and SOS payments via Stripe Checkout or inline PaymentIntent.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { stripe, SITE_URL, PRODUCT_NAMES, CORS, PaymentType, PaymentRequest, getOrCreateStripeCustomer } from './stripe-customer.ts'
import { handleWebBookingCheckout, handleWebShopCheckout } from './payment-flows.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  try {
    const body: PaymentRequest = await req.json()

    // --- Web anonymous checkout (no auth required) ---
    if (body.source === 'web' && body.booking_id) {
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )
      return await handleWebBookingCheckout(body, supabaseAdmin)
    }

    // --- Web anonymous SHOP checkout (voucher purchase, no auth required) ---
    if (body.source === 'web' && (body as Record<string, unknown>).customer_email && body.type === 'shop') {
      return await handleWebShopCheckout(body)
    }

    const { booking_id, order_id, incident_id, amount, currency, method, type, mode } = body
    const paymentType: PaymentType = type || 'booking'
    const paymentMode = mode || 'intent'

    // Validate required fields
    if ((paymentType === 'booking' || paymentType === 'extension' || paymentType === 'sos') && !booking_id) {
      return new Response(
        JSON.stringify({ success: false, error: `Missing booking_id for ${paymentType} payment` }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // -- Duplicate payment guard --
    if (paymentType === 'booking' && booking_id) {
      const tmpSupabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      const { data: bk } = await tmpSupabase.from('bookings')
        .select('payment_status, status')
        .eq('id', booking_id)
        .single()
      if (bk?.payment_status === 'paid') {
        return new Response(
          JSON.stringify({ success: false, error: 'Tato rezervace je již zaplacena.' }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
    }
    if (paymentType === 'shop' && !order_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing order_id for shop payment' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }
    if (amount == null) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing amount' }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const customerId = await getOrCreateStripeCustomer(supabase, req)

    const referenceId = paymentType === 'shop' ? order_id! : booking_id!
    const productName = PRODUCT_NAMES[paymentType]

    const metadata: Record<string, string> = {
      type: paymentType,
      source: 'motogo24',
    }
    if (booking_id) metadata.booking_id = booking_id
    if (order_id) metadata.order_id = order_id
    if (incident_id) metadata.incident_id = incident_id

    // -- FREE BOOKING (100% discount) — POUZE pokud je sleva skutečně 100% --
    if (amount <= 0 && booking_id) {
      const { data: dbBooking } = await supabase.from('bookings')
        .select('total_price, payment_status, promo_code_id, voucher_id, discount_amount')
        .eq('id', booking_id)
        .single()

      if (dbBooking?.payment_status === 'paid') {
        return new Response(
          JSON.stringify({ success: false, error: 'Tato rezervace je již zaplacena.' }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      if (dbBooking && dbBooking.total_price > 0) {
        return new Response(
          JSON.stringify({ success: false, error: 'Částka neodpovídá ceně rezervace (' + dbBooking.total_price + ' Kč). Obnovte stránku a zkuste znovu.' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      // Ověření, že sleva je skutečně 100%
      let isTrue100 = false
      if (dbBooking?.promo_code_id) {
        const { data: promo } = await supabase.from('promo_codes')
          .select('type, value')
          .eq('id', dbBooking.promo_code_id)
          .single()
        if (promo && promo.type === 'percent' && promo.value >= 100) {
          isTrue100 = true
        }
      }
      if (!isTrue100 && dbBooking?.voucher_id) {
        const { data: voucher } = await supabase.from('vouchers')
          .select('amount')
          .eq('id', dbBooking.voucher_id)
          .single()
        const originalPrice = (dbBooking.total_price || 0) + (dbBooking.discount_amount || 0)
        if (voucher && voucher.amount >= originalPrice && originalPrice > 0) {
          isTrue100 = true
        }
      }

      if (!isTrue100) {
        console.error('Free booking rejected — discount is not truly 100%:', {
          booking_id, total_price: dbBooking?.total_price,
          discount_amount: dbBooking?.discount_amount, promo_code_id: dbBooking?.promo_code_id
        })
        return new Response(
          JSON.stringify({ success: false, error: 'Chyba kalkulace ceny. Sleva není 100%. Obnovte stránku a zkuste znovu.' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      const { error: rpcError } = await supabase.rpc('confirm_payment', {
        p_booking_id: booking_id,
        p_method: 'free'
      })

      if (rpcError) {
        console.error('confirm_payment RPC failed for free booking:', rpcError.message)
        return new Response(
          JSON.stringify({ success: false, error: 'Potvrzení rezervace selhalo. Zkuste to znovu.' }),
          { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment', action: 'free_booking_confirmed',
          component: paymentType, status: 'ok',
          request_data: { booking_id, amount, type: paymentType },
        })
      } catch { /* ignore */ }

      return new Response(
        JSON.stringify({ success: true, free: true, booking_id }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // -- MODE: INTENT --
    if (paymentMode === 'intent') {
      const amountCents = Math.round(amount * 100)
      const intentParams: Record<string, unknown> = {
        amount: amountCents,
        currency: currency || 'czk',
        metadata,
        automatic_payment_methods: { enabled: true },
        description: productName,
      }
      if (customerId) {
        intentParams.customer = customerId
      }
      const intent = await stripe.paymentIntents.create(intentParams as Stripe.PaymentIntentCreateParams)

      // Create ephemeral key for Payment Sheet (saved cards support)
      let ephemeralKey: string | null = null
      if (customerId) {
        try {
          const ek = await stripe.ephemeralKeys.create(
            { customer: customerId },
            { apiVersion: '2024-04-10' }
          )
          ephemeralKey = ek.secret ?? null
        } catch (e) { /* non-blocking — Payment Sheet works without it */ }
      }

      try {
        if (booking_id) {
          await supabase.from('bookings').update({ stripe_payment_intent_id: intent.id }).eq('id', booking_id)
        }
        if (order_id) {
          await supabase.from('shop_orders').update({ stripe_payment_intent_id: intent.id }).eq('id', order_id)
        }
      } catch (e) { /* non-blocking */ }

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment', action: 'stripe_intent_created',
          component: paymentType, status: 'ok',
          request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType, mode: 'intent' },
          response_data: { payment_intent_id: intent.id },
        })
      } catch (e) { /* ignore */ }

      return new Response(
        JSON.stringify({
          success: true, client_secret: intent.client_secret,
          payment_intent_id: intent.id, amount, currency: currency || 'czk',
          // Payment Sheet support — Flutter uses these for saved cards
          customer_id: customerId || null,
          ephemeral_key: ephemeralKey,
        }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // -- MODE: CHECKOUT --
    let successPath: string
    let cancelPath: string

    if (paymentType === 'shop') {
      successPath = `/payment-success?order_id=${referenceId}`
      cancelPath = `/payment-cancel?order_id=${referenceId}`
    } else if (paymentType === 'sos') {
      successPath = `/payment-success?booking_id=${referenceId}&type=sos` + (incident_id ? `&incident_id=${incident_id}` : '')
      cancelPath = `/payment-cancel?booking_id=${referenceId}&type=sos`
    } else if (paymentType === 'extension') {
      successPath = `/payment-success?booking_id=${referenceId}&type=extension`
      cancelPath = `/payment-cancel?booking_id=${referenceId}&type=extension`
    } else {
      successPath = `/payment-success?booking_id=${referenceId}`
      cancelPath = `/payment-cancel?booking_id=${referenceId}`
    }

    const sessionParams: Record<string, unknown> = {
      line_items: [{
        price_data: {
          currency: currency || 'czk',
          product_data: { name: productName },
          unit_amount: Math.round(amount * 100),
        },
        quantity: 1,
      }],
      mode: 'payment',
      payment_method_types: ['card', 'link'],
      success_url: SITE_URL + successPath,
      cancel_url: SITE_URL + cancelPath,
      metadata,
      locale: 'cs',
    }

    if (customerId) {
      sessionParams.customer = customerId
    }

    const session = await stripe.checkout.sessions.create(sessionParams as Stripe.Checkout.SessionCreateParams)

    try {
      await supabase.from('debug_log').insert({
        source: 'process-payment', action: 'stripe_session_created',
        component: paymentType, status: 'ok',
        request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType },
        response_data: { session_id: session.id, checkout_url: session.url },
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({
        success: true, checkout_url: session.url, session_id: session.id,
        amount, currency: currency || 'czk',
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Stripe payment error:', err)

    try {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      await supabase.from('debug_log').insert({
        source: 'process-payment', action: 'stripe_error',
        component: 'stripe', status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return new Response(
      JSON.stringify({ success: false, error: 'Payment processing failed: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
