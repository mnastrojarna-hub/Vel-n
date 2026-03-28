// ===== process-payment/payment-flows.ts =====
// Web checkout flows: booking checkout + shop (voucher) checkout

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14'
import { stripe, SITE_URL, PRODUCT_NAMES, CORS, PaymentRequest } from './stripe-customer.ts'

/** Handle web anonymous booking checkout (no auth required) */
export async function handleWebBookingCheckout(
  body: PaymentRequest,
  supabaseAdmin: ReturnType<typeof createClient>
): Promise<Response> {
  const { data: booking, error: bErr } = await supabaseAdmin
    .from('bookings')
    .select('*, profiles:user_id(full_name, email, phone, stripe_customer_id)')
    .eq('id', body.booking_id!)
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

  let customerId = profile?.stripe_customer_id || null
  if (!customerId && customerEmail) {
    const customers = await stripe.customers.list({ email: customerEmail, limit: 1 })
    customerId = customers.data.length > 0 ? customers.data[0].id : null
  }
  if (!customerId) {
    const newCust = await stripe.customers.create({
      email: customerEmail || undefined,
      name: customerName || undefined,
      metadata: { source: 'web', booking_id: body.booking_id! }
    })
    customerId = newCust.id
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
        product_data: { name: PRODUCT_NAMES.booking, description: `Rezervace #${body.booking_id!.slice(0,8)}` }
      },
      quantity: 1
    }],
    metadata: { booking_id: body.booking_id!, type: 'booking', source: 'web' },
    success_url: `${SITE_URL}/#/potvrzeni?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${SITE_URL}/#/rezervace`,
  })

  await supabaseAdmin.from('bookings').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string
  }).eq('id', body.booking_id!)

  return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id }), {
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}

/** Handle web anonymous SHOP checkout (voucher purchase, no auth required) */
export async function handleWebShopCheckout(
  body: PaymentRequest
): Promise<Response> {
  const webBody = body as Record<string, unknown>
  const customerEmail = webBody.customer_email as string
  const customerName = (webBody.customer_name as string) || ''
  const amountCzk = body.amount
  const amountCents = Math.round(amountCzk * 100)
  const currency = body.currency || 'czk'

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
