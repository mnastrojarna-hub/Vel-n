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

  // 100% sleva pro web — potvrdit bez Stripe, ALE POUZE pokud je sleva opravdu 100%
  if (amount < 1) {
    let isTrue100 = false

    // Ověření promo kódu — musí být type=percent, value=100
    if (booking.promo_code_id) {
      const { data: promo } = await supabaseAdmin.from('promo_codes')
        .select('type, value')
        .eq('id', booking.promo_code_id)
        .single()
      if (promo && promo.type === 'percent' && promo.value >= 100) {
        isTrue100 = true
      }
    }

    // Ověření voucheru — musí pokrýt celou původní cenu
    if (!isTrue100 && booking.voucher_id) {
      const { data: voucher } = await supabaseAdmin.from('vouchers')
        .select('amount')
        .eq('id', booking.voucher_id)
        .single()
      const originalPrice = (booking.total_price || 0) + (booking.discount_amount || 0)
      if (voucher && voucher.amount >= originalPrice && originalPrice > 0) {
        isTrue100 = true
      }
    }

    if (!isTrue100) {
      console.error('Free booking rejected — discount is not truly 100%:', {
        booking_id: body.booking_id, total_price: booking.total_price,
        discount_amount: booking.discount_amount, promo_code_id: booking.promo_code_id
      })
      return new Response(JSON.stringify({
        error: 'Chyba kalkulace ceny. Sleva není 100%. Obnovte stránku a zkuste znovu.'
      }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' }
      })
    }

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

  // automatic_payment_methods povolí Apple Pay / Google Pay na podporovaných zařízeních
  // (Stripe Checkout automaticky verifikuje doménu pro Apple Pay)
  const session = await stripe.checkout.sessions.create({
    customer: customerId,
    mode: 'payment',
    automatic_payment_methods: { enabled: true },
    line_items: [{
      price_data: {
        currency,
        unit_amount: amount,
        product_data: { name: PRODUCT_NAMES.booking, description: `Rezervace #${body.booking_id!.slice(-8).toUpperCase()}` }
      },
      quantity: 1
    }],
    metadata: { booking_id: body.booking_id!, type: 'booking', source: 'web' },
    success_url: `${SITE_URL}/#/potvrzeni?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${SITE_URL}/#/rezervace?resume=${body.booking_id}`,
    locale: 'cs',
  })

  await supabaseAdmin.from('bookings').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string
  }).eq('id', body.booking_id!)

  return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id }), {
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}

/** Handle web anonymous PRODUCT checkout (e-shop produkty z motogo24.cz). */
async function handleWebProductCheckout(
  body: PaymentRequest,
  webBody: Record<string, unknown>
): Promise<Response> {
  const orderId = body.order_id as string
  const customerEmail = (webBody.customer_email as string) || ''
  const customerName  = (webBody.customer_name as string)  || ''
  const customerPhone = (webBody.customer_phone as string) || ''
  const currency = body.currency || 'czk'

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Načti objednávku + položky (RPC create_web_shop_order je už vytvořilo)
  const { data: order, error: orderErr } = await supabaseAdmin
    .from('shop_orders')
    .select('id, total, subtotal, shipping_cost, discount, currency, customer_email, customer_name, customer_phone, payment_status, shipping_method')
    .eq('id', orderId)
    .single()
  if (orderErr || !order) {
    return new Response(JSON.stringify({ success: false, error: 'Objednávka nenalezena.' }),
      { status: 404, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }
  if (order.payment_status === 'paid') {
    return new Response(JSON.stringify({ success: false, error: 'Tato objednávka je již zaplacena.' }),
      { status: 409, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  const { data: items } = await supabaseAdmin
    .from('shop_order_items')
    .select('product_name, product_sku, size, quantity, unit_price, total_price')
    .eq('order_id', orderId)
  const orderItems = items || []
  if (orderItems.length === 0) {
    return new Response(JSON.stringify({ success: false, error: 'Objednávka neobsahuje žádné položky.' }),
      { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  // Stripe customer (re-use po e-mailu)
  const email = customerEmail || order.customer_email || ''
  const name  = customerName  || order.customer_name  || ''
  const customers = email ? await stripe.customers.list({ email, limit: 1 }) : { data: [] }
  let custId = customers.data.length > 0 ? customers.data[0].id : null
  if (!custId && email) {
    const newCust = await stripe.customers.create({
      email, name, phone: customerPhone || order.customer_phone || undefined,
      metadata: { source: 'web_shop_products' }
    })
    custId = newCust.id
  }

  // Sestavit Stripe line items z DB (cena pochází z DB, ne z klienta)
  const lineItems: Record<string, unknown>[] = orderItems.map((it: Record<string, unknown>) => {
    const baseName = String(it.product_name || 'Produkt')
    const size = it.size ? ` (vel. ${it.size})` : ''
    return {
      price_data: {
        currency,
        unit_amount: Math.round(Number(it.unit_price) * 100),
        product_data: {
          name: baseName + size,
          ...(it.product_sku ? { metadata: { sku: String(it.product_sku) } } : {})
        }
      },
      quantity: Number(it.quantity) || 1
    }
  })

  // Doprava jako samostatný line item (Stripe ji tak ukáže na účtence)
  const shipCost = Number(order.shipping_cost) || 0
  if (shipCost > 0) {
    const shipName = order.shipping_method === 'zasilkovna' ? 'Doprava — Zásilkovna'
                   : order.shipping_method === 'post'       ? 'Doprava — Česká pošta'
                   : 'Doprava'
    lineItems.push({
      price_data: {
        currency,
        unit_amount: Math.round(shipCost * 100),
        product_data: { name: shipName }
      },
      quantity: 1
    })
  }

  // Sleva přes Stripe coupon (jen ad-hoc, neukládáme)
  let discounts: Record<string, unknown>[] | undefined
  const discount = Number(order.discount) || 0
  if (discount > 0) {
    const coupon = await stripe.coupons.create({
      amount_off: Math.round(discount * 100),
      currency,
      duration: 'once',
      name: 'Sleva',
    })
    discounts = [{ coupon: coupon.id }]
  }

  const sessionParams: Record<string, unknown> = {
    mode: 'payment',
    line_items: lineItems as Stripe.Checkout.SessionCreateParams.LineItem[],
    automatic_payment_methods: { enabled: true }, // Apple Pay / Google Pay
    metadata: { order_id: orderId, type: 'shop', source: 'web' },
    success_url: `${SITE_URL}/objednavka/dokoncit?order_id=${orderId}&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url:  `${SITE_URL}/kosik`,
    locale: 'cs',
  }
  if (custId) sessionParams.customer = custId
  if (discounts) sessionParams.discounts = discounts

  const session = await stripe.checkout.sessions.create(sessionParams as Stripe.Checkout.SessionCreateParams)

  await supabaseAdmin.from('shop_orders').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string,
  }).eq('id', orderId)

  // ZF (proforma) — best-effort, neblokuje
  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY },
      body: JSON.stringify({ type: 'shop_proforma', order_id: orderId, send_email: true }),
    })
  } catch (e) { console.warn('[WebProductCheckout] ZF generation failed:', e) }

  return new Response(JSON.stringify({
    success: true,
    url: session.url,           // alias pro web (kompatibilita s checkout.js)
    checkout_url: session.url,
    session_id: session.id,
    order_id: orderId
  }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
}

/** Handle web anonymous SHOP checkout — produkty (kind=products) NEBO voucher (default). */
export async function handleWebShopCheckout(
  body: PaymentRequest
): Promise<Response> {
  const webBody = body as Record<string, unknown>

  // Větvení: produkty z e-shopu (mají order_id z create_web_shop_order, nemají voucher_amount)
  // vs. dárkový poukaz (existující flow).
  if (webBody.kind === 'products' || (body.order_id && webBody.voucher_amount == null)) {
    return await handleWebProductCheckout(body, webBody)
  }

  const customerEmail = webBody.customer_email as string
  const customerName = (webBody.customer_name as string) || ''
  const customerPhone = (webBody.customer_phone as string) || ''
  const isPrint = !!(webBody.is_print)
  const voucherAmount = (webBody.voucher_amount as number) || body.amount
  const printFee = isPrint ? 180 : 0
  const shippingAddress = (webBody.shipping_address as string) || ''
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
      customer_phone: customerPhone,
      shipping_address: shippingAddress || null,
      status: 'new',
      payment_status: 'unpaid',
      payment_method: 'stripe',
      total: amountCzk,
      subtotal: voucherAmount,
      shipping_cost: printFee,
      discount: 0,
      currency: 'CZK',
      notes: isPrint ? 'Fyzický poukaz (tisk + poštovné)' : 'Elektronický poukaz',
    })

    // Hlavní položka: dárkový poukaz
    const orderItems: Record<string, unknown>[] = [{
      order_id: orderId,
      product_name: 'Dárkový poukaz',
      quantity: 1,
      unit_price: voucherAmount,
      total_price: voucherAmount,
    }]

    // Fyzický tisk + poštovné (název BEZ "poukaz" aby trigger negeneroval voucher)
    if (isPrint) {
      orderItems.push({
        order_id: orderId,
        product_name: 'Tisk a poštovné',
        quantity: 1,
        unit_price: printFee,
        total_price: printFee,
      })
    }

    await supabaseAdmin.from('shop_order_items').insert(orderItems)
  }

  // Stripe line items (separate for clarity on Stripe receipt)
  const lineItems: Record<string, unknown>[] = [{
    price_data: {
      currency,
      unit_amount: Math.round(voucherAmount * 100),
      product_data: { name: 'MotoGo24 — Dárkový poukaz' }
    },
    quantity: 1
  }]
  if (isPrint) {
    lineItems.push({
      price_data: {
        currency,
        unit_amount: Math.round(printFee * 100),
        product_data: { name: 'Tisk a poštovné' }
      },
      quantity: 1
    })
  }

  const session = await stripe.checkout.sessions.create({
    customer: custId,
    mode: 'payment',
    payment_method_types: ['card', 'link'],
    line_items: lineItems as Stripe.Checkout.SessionCreateParams.LineItem[],
    metadata: { order_id: orderId, type: 'shop', source: 'web' },
    success_url: `${SITE_URL}/#/potvrzeni?order_id=${orderId}&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${SITE_URL}/#/poukazy`,
    locale: 'cs',
  })

  await supabaseAdmin.from('shop_orders').update({
    stripe_session_id: session.id,
    stripe_payment_intent_id: session.payment_intent as string,
  }).eq('id', orderId)

  // Generate ZF (proforma) + send email with order summary (best-effort, non-blocking)
  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
    const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

    await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
      method: 'POST', headers,
      body: JSON.stringify({ type: 'shop_proforma', order_id: orderId, send_email: true }),
    })
  } catch (e) { console.warn('[WebShopCheckout] ZF generation failed:', e) }

  return new Response(JSON.stringify({ checkout_url: session.url, session_id: session.id, order_id: orderId }), {
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}
