// ===== MotoGo24 – Edge Function: Process Payment (Stripe LIVE) =====
// Supports booking, shop, extension, and SOS payments via Stripe Checkout.
// Endpoint: POST /functions/v1/process-payment
// Body: { booking_id?, order_id?, amount, currency?, type: 'booking'|'shop'|'extension'|'sos' }

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
    const { booking_id, order_id, incident_id, amount, currency, method, type } = body
    const paymentType: PaymentType = type || 'booking'

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

    // Build reference ID and URLs based on payment type
    const referenceId = paymentType === 'shop' ? order_id! : booking_id!
    const productName = PRODUCT_NAMES[paymentType]

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

    // Build metadata
    const metadata: Record<string, string> = {
      type: paymentType,
      source: 'motogo24',
    }
    if (booking_id) metadata.booking_id = booking_id
    if (order_id) metadata.order_id = order_id
    if (incident_id) metadata.incident_id = incident_id

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
    } catch (_) { /* ignore logging errors */ }

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
    } catch (_) { /* ignore logging errors */ }

    return new Response(
      JSON.stringify({ success: false, error: 'Payment processing failed: ' + (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
