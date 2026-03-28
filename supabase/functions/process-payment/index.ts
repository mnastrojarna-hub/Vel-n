// ===== MotoGo24 – Edge Function: Process Payment (Stripe LIVE) =====
// Supports booking, shop, extension, and SOS payments via Stripe Checkout or inline PaymentIntent.
// Endpoint: POST /functions/v1/process-payment
// Body: { booking_id?, order_id?, amount, currency?, type, mode?: 'intent'|'checkout' }

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

const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

type PaymentType = 'booking' | 'shop' | 'extension' | 'sos'

interface PaymentRequest {
  booking_id?: string
  order_id?: string
  incident_id?: string
  amount: number
  currency?: string
  method?: string
  type?: PaymentType
  mode?: 'intent' | 'checkout'
  source?: string
}

const PRODUCT_NAMES: Record<PaymentType, string> = {
  booking: 'MotoGo24 — Pronájem motorky',
  shop: 'MotoGo24 — E-shop objednávka',
  extension: 'MotoGo24 — Prodloužení rezervace',
  sos: 'MotoGo24 — SOS náhradní motorka',
}

// Decode JWT payload without verification (gateway already verified)
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')))
    return payload
  } catch { return null }
}

// Get or create Stripe Customer for the authenticated user
async function getOrCreateStripeCustomer(
  supabase: ReturnType<typeof createClient>,
  req: Request
): Promise<string | null> {
  try {
    // Get user from JWT — decode directly (gateway already verified)
    const authHeader = req.headers.get('authorization') || ''
    const token = authHeader.replace('Bearer ', '')
    if (!token) return null

    const jwtPayload = decodeJwtPayload(token)
    let userId = jwtPayload?.sub as string | null
    let userEmail = (jwtPayload?.email as string) || null

    // Fallback: try getUser if JWT decode fails
    if (!userId) {
      try {
        const { data: { user: authUser } } = await supabase.auth.getUser(token)
        if (authUser) {
          userId = authUser.id
          userEmail = authUser.email || null
        }
      } catch (e) {
        console.warn('getUser fallback failed:', e)
      }
    }

    if (!userId) return null

    // Check if profile already has stripe_customer_id
    const { data: profile } = await supabase
      .from('profiles')
      .select('stripe_customer_id, full_name, email, phone')
      .eq('id', userId)
      .single()

    if (profile?.stripe_customer_id) {
      return profile.stripe_customer_id
    }

    // Create new Stripe Customer
    const customer = await stripe.customers.create({
      email: userEmail || profile?.email || undefined,
      name: profile?.full_name || undefined,
      phone: profile?.phone || undefined,
      metadata: { supabase_user_id: userId },
    })

    // Save stripe_customer_id to profile
    await supabase
      .from('profiles')
      .update({ stripe_customer_id: customer.id })
      .eq('id', userId)

    return customer.id
  } catch (e) {
    console.warn('getOrCreateStripeCustomer error:', e)
    return null
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  try {
    const body: PaymentRequest = await req.json()

    // --- Web anonymous checkout (no auth required) ---
    if (body.source === 'web' && body.booking_id) {
      // Use service role client for DB access
      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )

      const { data: booking, error: bErr } = await supabaseAdmin
        .from('bookings')
        .select('*, profiles:user_id(full_name, email, phone, stripe_customer_id)')
        .eq('id', body.booking_id)
        .eq('booking_source', 'web')
        .eq('payment_status', 'unpaid')
        .single()

      if (bErr || !booking) {
        console.error('Web booking lookup failed:', bErr?.message, 'booking_id:', body.booking_id)
        return new Response(JSON.stringify({ error: 'Booking not found or already paid' }), {
          status: 400, headers: { ...CORS, 'Content-Type': 'application/json' }
        })
      }

      const amountCzk = booking.total_price || body.amount || 0
      const amount = Math.round(amountCzk * 100)
      const currency = body.currency || 'czk'

      // 100% sleva pro web — potvrdit bez Stripe
      if (amount < 1) {
        const { error: rpcErr } = await supabaseAdmin.rpc('confirm_payment', { p_booking_id: body.booking_id, p_method: 'free' })
        if (rpcErr) {
          console.error('confirm_payment RPC failed for free web booking:', rpcErr.message)
          return new Response(JSON.stringify({ error: 'Potvrzení rezervace selhalo.' }), {
            status: 500, headers: { ...CORS, 'Content-Type': 'application/json' }
          })
        }
        return new Response(JSON.stringify({ success: true, free: true, booking_id: body.booking_id }), {
          headers: { ...CORS, 'Content-Type': 'application/json' }
        })
      }

      const profile = booking.profiles as { full_name?: string; email?: string; phone?: string; stripe_customer_id?: string } | null
      const customerEmail = profile?.email || ''
      const customerName = profile?.full_name || ''

      // Create or get Stripe customer by email
      let customerId = profile?.stripe_customer_id || null
      if (!customerId && customerEmail) {
        const customers = await stripe.customers.list({ email: customerEmail, limit: 1 })
        customerId = customers.data.length > 0 ? customers.data[0].id : null
      }
      if (!customerId) {
        const newCust = await stripe.customers.create({
          email: customerEmail || undefined,
          name: customerName || undefined,
          metadata: { source: 'web', booking_id: body.booking_id }
        })
        customerId = newCust.id
        // Save stripe_customer_id to profile
        if (booking.user_id) {
          await supabaseAdmin.from('profiles').update({ stripe_customer_id: customerId }).eq('id', booking.user_id)
        }
      }

      const session = await stripe.checkout.sessions.create({
        customer: customerId,
        mode: 'payment',
        payment_method_types: ['card'],
        line_items: [{
          price_data: {
            currency,
            unit_amount: amount,
            product_data: { name: PRODUCT_NAMES.booking, description: `Rezervace #${body.booking_id.slice(0,8)}` }
          },
          quantity: 1
        }],
        metadata: { booking_id: body.booking_id, type: 'booking', source: 'web' },
        success_url: `${SITE_URL}/#/potvrzeni?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${SITE_URL}/#/rezervace`,
      })

      // Store session ID
      await supabaseAdmin.from('bookings').update({
        stripe_session_id: session.id,
        stripe_payment_intent_id: session.payment_intent as string
      }).eq('id', body.booking_id)

      return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id }), {
        headers: { ...CORS, 'Content-Type': 'application/json' }
      })
    }

    // --- Web anonymous SHOP checkout (voucher purchase, no auth required) ---
    if (body.source === 'web' && (body as Record<string, unknown>).customer_email && body.type === 'shop') {
      const webBody = body as Record<string, unknown>
      const customerEmail = webBody.customer_email as string
      const customerName = (webBody.customer_name as string) || ''
      const amountCzk = body.amount
      const amountCents = Math.round(amountCzk * 100)
      const currency = body.currency || 'czk'

      // Create or get Stripe customer by email
      const customers = await stripe.customers.list({ email: customerEmail, limit: 1 })
      let custId = customers.data.length > 0 ? customers.data[0].id : null
      if (!custId) {
        const newCust = await stripe.customers.create({
          email: customerEmail,
          name: customerName,
          metadata: { source: 'web_shop' }
        })
        custId = newCust.id
      }

      const supabaseAdmin = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      )

      // Create shop_order directly via service role (bypass RLS)
      const orderId = body.order_id || crypto.randomUUID()
      if (!body.order_id) {
        await supabaseAdmin.from('shop_orders').insert({
          id: orderId,
          customer_name: customerName,
          customer_email: customerEmail,
          status: 'new',
          payment_status: 'unpaid',
          payment_method: 'stripe',
          total: amountCzk,
          subtotal: amountCzk,
          shipping_cost: 0,
          discount: 0,
          currency: 'CZK',
        })
        await supabaseAdmin.from('shop_order_items').insert({
          order_id: orderId,
          product_name: 'Dárkový poukaz',
          quantity: 1,
          unit_price: amountCzk,
          total_price: amountCzk,
        })
      }

      const session = await stripe.checkout.sessions.create({
        customer: custId,
        mode: 'payment',
        payment_method_types: ['card'],
        line_items: [{
          price_data: {
            currency,
            unit_amount: amountCents,
            product_data: { name: 'MotoGo24 — Dárkový poukaz' }
          },
          quantity: 1
        }],
        metadata: { order_id: orderId, type: 'shop', source: 'web' },
        success_url: `${SITE_URL}/#/potvrzeni?order_id=${orderId}&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${SITE_URL}/#/poukazy`,
        locale: 'cs',
      })

      await supabaseAdmin.from('shop_orders').update({
        stripe_session_id: session.id,
        stripe_payment_intent_id: session.payment_intent as string,
      }).eq('id', orderId)

      return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id, order_id: orderId }), {
        headers: { ...CORS, 'Content-Type': 'application/json' }
      })
    }

    const { booking_id, order_id, incident_id, amount, currency, method, type, mode } = body
    const paymentType: PaymentType = type || 'booking'
    const paymentMode = mode || 'intent' // Default to inline PaymentIntent

    // Validate required fields
    if ((paymentType === 'booking' || paymentType === 'extension' || paymentType === 'sos') && !booking_id) {
      return new Response(
        JSON.stringify({ success: false, error: `Missing booking_id for ${paymentType} payment` }),
        { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // ── Duplicate payment guard: refuse if booking is already paid ──
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

    // Get or create Stripe Customer (enables saved cards + card prefill)
    const customerId = await getOrCreateStripeCustomer(supabase, req)

    // Build reference ID based on payment type
    const referenceId = paymentType === 'shop' ? order_id! : booking_id!
    const productName = PRODUCT_NAMES[paymentType]

    // Build metadata
    const metadata: Record<string, string> = {
      type: paymentType,
      source: 'motogo24',
    }
    if (booking_id) metadata.booking_id = booking_id
    if (order_id) metadata.order_id = order_id
    if (incident_id) metadata.incident_id = incident_id

    // ── FREE BOOKING (100% discount, amount = 0) — confirm directly without Stripe ──
    // Safety: verify that booking's total_price in DB is actually 0 before confirming for free
    if (amount <= 0 && booking_id) {
      const { data: dbBooking } = await supabase.from('bookings')
        .select('total_price, payment_status')
        .eq('id', booking_id)
        .single()

      if (dbBooking?.payment_status === 'paid') {
        return new Response(
          JSON.stringify({ success: false, error: 'Tato rezervace je již zaplacena.' }),
          { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      // Only allow free confirmation if DB total_price is also 0
      if (dbBooking && dbBooking.total_price > 0) {
        return new Response(
          JSON.stringify({ success: false, error: 'Částka neodpovídá ceně rezervace (' + dbBooking.total_price + ' Kč). Obnovte stránku a zkuste znovu.' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      const { error: rpcError } = await supabase.rpc('confirm_payment', {
        p_booking_id: booking_id,
        p_method: 'free'
      })

      if (rpcError) {
        console.error('confirm_payment RPC failed for free booking:', rpcError.message)
        // Do NOT fallback to direct update — if RPC fails, payment is NOT confirmed
        return new Response(
          JSON.stringify({ success: false, error: 'Potvrzení rezervace selhalo. Zkuste to znovu.' }),
          { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }

      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment',
          action: 'free_booking_confirmed',
          component: paymentType,
          status: 'ok',
          request_data: { booking_id, amount, type: paymentType },
        })
      } catch { /* ignore */ }

      return new Response(
        JSON.stringify({ success: true, free: true, booking_id }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // ── MODE: INTENT — Create PaymentIntent for in-app Stripe Elements (no redirect) ──
    if (paymentMode === 'intent') {
      const amountCents = Math.round(amount * 100)
      const intentParams: Record<string, unknown> = {
        amount: amountCents,
        currency: currency || 'czk',
        metadata,
        payment_method_types: ['card'],
        setup_future_usage: 'off_session',
        description: productName,
      }
      if (customerId) {
        intentParams.customer = customerId
      }
      const intent = await stripe.paymentIntents.create(intentParams as Stripe.PaymentIntentCreateParams)

      // Store stripe_payment_intent_id on the booking/order
      try {
        if (booking_id) {
          await supabase.from('bookings').update({
            stripe_payment_intent_id: intent.id,
          }).eq('id', booking_id)
        }
        if (order_id) {
          await supabase.from('shop_orders').update({
            stripe_payment_intent_id: intent.id,
          }).eq('id', order_id)
        }
      } catch (e) { /* non-blocking */ }

      // Log to debug_log
      try {
        await supabase.from('debug_log').insert({
          source: 'process-payment',
          action: 'stripe_intent_created',
          component: paymentType,
          status: 'ok',
          request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType, mode: 'intent' },
          response_data: { payment_intent_id: intent.id },
        })
      } catch (e) { /* ignore */ }

      return new Response(
        JSON.stringify({
          success: true,
          client_secret: intent.client_secret,
          payment_intent_id: intent.id,
          amount,
          currency: currency || 'czk',
        }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // ── MODE: CHECKOUT — Legacy Stripe Checkout Session (redirect) ──
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

    // Stripe Checkout Session with Customer (saves cards, prefills cardholder name)
    const sessionParams: Record<string, unknown> = {
      payment_method_types: ['card'],
      line_items: [{
        price_data: {
          currency: currency || 'czk',
          product_data: { name: productName },
          unit_amount: Math.round(amount * 100),
        },
        quantity: 1,
      }],
      mode: 'payment',
      success_url: SITE_URL + successPath,
      cancel_url: SITE_URL + cancelPath,
      metadata,
      locale: 'cs',
      // Save card for future use
      payment_intent_data: {
        setup_future_usage: 'off_session',
      },
    }

    // Attach customer — enables saved card selection in Stripe Checkout
    if (customerId) {
      sessionParams.customer = customerId
    }

    const session = await stripe.checkout.sessions.create(sessionParams as Stripe.Checkout.SessionCreateParams)

    // Log to debug_log
    try {
      await supabase.from('debug_log').insert({
        source: 'process-payment',
        action: 'stripe_session_created',
        component: paymentType,
        status: 'ok',
        request_data: { booking_id, order_id, incident_id, amount, currency, type: paymentType },
        response_data: { session_id: session.id, checkout_url: session.url },
      })
    } catch (e) { /* ignore logging errors */ }

    return new Response(
      JSON.stringify({
        success: true,
        checkout_url: session.url,
        session_id: session.id,
        amount,
        currency: currency || 'czk',
      }),
      { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('Stripe payment error:', err)

    // Log error to debug_log
    try {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      await supabase.from('debug_log').insert({
        source: 'process-payment',
        action: 'stripe_error',
        component: 'stripe',
        status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore logging errors */ }

    return new Response(
      JSON.stringify({ success: false, error: 'Payment processing failed: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
