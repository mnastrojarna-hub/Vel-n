// ===== MotoGo24 – Edge Function: Manage Payment Methods (Stripe) =====
// List, delete, and set default saved payment methods via Stripe Customer.
// POST /functions/v1/manage-payment-methods
// Body: { action: 'list' | 'delete' | 'set_default' | 'setup', payment_method_id? }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
})

// Decode JWT payload without verification (gateway already verified)
function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')))
    return payload
  } catch { return null }
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
    // Authenticate user — JWT already verified by Supabase gateway
    const authHeader = req.headers.get('authorization') || ''
    const token = authHeader.replace('Bearer ', '')
    if (!token) {
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { status: 401, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // Decode JWT directly (gateway already verified signature)
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

    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid token' }),
        { status: 401, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    const user = { id: userId, email: userEmail }

    // Get stripe_customer_id from profile
    const { data: profile } = await supabase
      .from('profiles')
      .select('stripe_customer_id, full_name, email, phone')
      .eq('id', user.id)
      .single()

    const customerId = profile?.stripe_customer_id

    const body = await req.json()
    const { action, payment_method_id } = body

    // SETUP — create a Stripe Checkout Session in setup mode to save a new card
    if (action === 'setup') {
      let custId = customerId
      if (!custId) {
        const customer = await stripe.customers.create({
          email: user.email || (profile as any)?.email || undefined,
          name: (profile as any)?.full_name || undefined,
          phone: (profile as any)?.phone || undefined,
          metadata: { supabase_user_id: user.id },
        })
        custId = customer.id
        await supabase
          .from('profiles')
          .update({ stripe_customer_id: custId })
          .eq('id', user.id)
      }

      const session = await stripe.checkout.sessions.create({
        customer: custId,
        mode: 'setup',
        payment_method_types: ['card'],
        success_url: SITE_URL + '/card-setup-success',
        cancel_url: SITE_URL + '/card-setup-cancel',
        locale: 'cs',
        metadata: { source: 'motogo24', action: 'add_card', user_id: user.id },
      } as Stripe.Checkout.SessionCreateParams)

      return new Response(
        JSON.stringify({ success: true, action: 'setup', checkout_url: session.url }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // For list/delete/set_default — need existing customer
    if (!customerId) {
      return new Response(
        JSON.stringify({ success: true, action: action || 'list', methods: [] }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // LIST saved payment methods
    if (action === 'list' || !action) {
      const customer = await stripe.customers.retrieve(customerId) as Stripe.Customer
      const methods = await stripe.paymentMethods.list({
        customer: customerId,
        type: 'card',
      })

      const defaultPmId = (customer.invoice_settings?.default_payment_method as string) || null

      const cards = methods.data.map((pm) => ({
        id: pm.id,
        brand: pm.card?.brand || 'unknown',
        last4: pm.card?.last4 || '****',
        exp_month: pm.card?.exp_month,
        exp_year: pm.card?.exp_year,
        holder_name: pm.billing_details?.name || null,
        is_default: pm.id === defaultPmId,
      }))

      return new Response(
        JSON.stringify({ success: true, action: 'list', methods: cards }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // DELETE a payment method
    if (action === 'delete') {
      if (!payment_method_id) {
        return new Response(
          JSON.stringify({ success: false, error: 'Missing payment_method_id' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      // Verify the PM belongs to this customer
      const pm = await stripe.paymentMethods.retrieve(payment_method_id)
      if (pm.customer !== customerId) {
        return new Response(
          JSON.stringify({ success: false, error: 'Payment method does not belong to this customer' }),
          { status: 403, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      await stripe.paymentMethods.detach(payment_method_id)
      return new Response(
        JSON.stringify({ success: true, action: 'delete' }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    // SET DEFAULT payment method
    if (action === 'set_default') {
      if (!payment_method_id) {
        return new Response(
          JSON.stringify({ success: false, error: 'Missing payment_method_id' }),
          { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
        )
      }
      await stripe.customers.update(customerId, {
        invoice_settings: { default_payment_method: payment_method_id },
      })
      return new Response(
        JSON.stringify({ success: true, action: 'set_default' }),
        { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ success: false, error: 'Unknown action: ' + action }),
      { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('manage-payment-methods error:', err)
    return new Response(
      JSON.stringify({ success: false, error: (err as Error).message }),
      { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } }
    )
  }
})
