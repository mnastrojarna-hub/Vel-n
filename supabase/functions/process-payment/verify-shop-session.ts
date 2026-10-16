// ===== process-payment/verify-shop-session.ts =====
// Sync fallback: ověř Stripe SHOP session a potvrď voucher/e-shop objednávku
// (action `verify_shop_session`, volá stránka /potvrzeni hned po načtení a znovu
// při 3. a 7. dotazu). Vyčleněno z index.ts (2026-10-16) beze změny chování, navíc:
//  • D2 (oprava 2026-10-16): dorovnání platby kartou z metadat session (`due` /
//    `card_rounding`, web e-shop 1–15 Kč → 15 Kč) se zapíše do objednávky PŘED
//    potvrzením — stejně jako ve webhooku (applyChargeRounding). Dřív tahle cesta
//    často předběhla webhook a potvrdila objednávku s total = due (např. 7 Kč):
//    trigger potvrzení vystavil DP na 7 Kč, webhook pak cenu zvedl na 15 Kč a FV
//    ukázala 8 Kč „k doplacení", i když karta zaplatila 15 Kč.
//    `error` (výpadek DB) → {success:false, retry:true} BEZ potvrzení (stránka se
//    zeptá znovu, objednávku potvrdí i webhook); `mismatch` jen záznam (debug_log).
// Původní popis: potvrzení dřív záviselo VÝHRADNĚ na webhooku — když nedorazil,
// objednávka zůstala `pending`, voucher se nevygeneroval a mail nedorazil.
// Idempotence: confirm_shop_payment je atomic (UPDATE … WHERE payment_status<>'paid'
// RETURNING) a vrací `was_already_paid` — když webhook (nebo dřívější dotaz) potvrdil
// dřív, vrátíme already_paid a NEposíláme druhý mail.
import { respond } from './refusals.ts'
import { applyChargeRounding } from '../_shared/charge-rounding.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
export type StripeSessionsLike = {
  checkout: { sessions: { retrieve(id: string): Promise<Record<string, unknown>> } }
}
export type VerifyShopDeps = {
  sb: Sb
  stripe: StripeSessionsLike
  supabaseUrl: string
  serviceKey: string
  fetchFn?: typeof fetch
}

export async function verifyShopSession(body: Record<string, unknown>, deps: VerifyShopDeps): Promise<Response> {
  const { sb, stripe } = deps
  const doFetch = deps.fetchFn ?? fetch
  const sessionId = body.session_id as string | undefined
  let orderId = (body.order_id as string | undefined) || null
  if (!sessionId && !orderId) return respond(400, { success: false, error: 'Missing session_id or order_id' })
  try {
    // Dohledej stripe_session_id z objednávky, pokud klient session_id neposlal
    // (starší odkaz / přímá navigace na /potvrzeni?order_id=…).
    let sid = sessionId || null
    if (!sid && orderId) {
      const { data: ord } = await sb.from('shop_orders').select('stripe_session_id').eq('id', orderId).maybeSingle()
      sid = (ord?.stripe_session_id as string | null) || null
    }
    if (!sid) return respond(200, { success: false, error: 'No session to verify' })
    const session = await stripe.checkout.sessions.retrieve(sid)
    const md = (session.metadata || {}) as Record<string, string>
    // BEZPEČNOST 2026-09-24: objednávku určuje VÝHRADNĚ zaplacená session
    // (metadata.order_id / client_reference_id), ne order_id z požadavku —
    // jinak by šla jednou zaplacenou session potvrdit libovolná jiná
    // objednávka. order_id z požadavku smí jen souhlasit.
    const sessionOrderId = md.order_id || (session.client_reference_id as string | null) || null
    if (sessionOrderId) {
      if (orderId && orderId !== sessionOrderId) return respond(400, { success: false, error: 'order_mismatch' })
      orderId = sessionOrderId
    } else if (orderId && sessionId) {
      // Session bez vazby na objednávku → přijmi jen, když ji má u sebe
      // uloženou sama objednávka (web ji zapisuje při vytvoření session).
      const { data: ord } = await sb.from('shop_orders').select('stripe_session_id').eq('id', orderId).maybeSingle()
      if ((ord?.stripe_session_id as string | null) !== sid) return respond(400, { success: false, error: 'order_mismatch' })
    }
    if (!orderId) return respond(400, { success: false, error: 'No order_id in session' })
    // Dokud Stripe platbu nepotvrdil, vrátíme pending — klient pollne znovu
    // (webhook může dorazit mezitím). Potvrzujeme JEN reálně zaplacenou
    // session (dřív stačilo status 'complete', které nastane i bez platby).
    const freeSession = session.payment_status === 'no_payment_required' &&
      (Number(session.amount_total ?? 0) === 0) // web objednávka celá pokrytá slevou
    if (session.payment_status !== 'paid' && !freeSession) {
      return respond(200, { success: false, payment_status: session.payment_status, status: session.status })
    }
    const piId = typeof session.payment_intent === 'string'
      ? session.payment_intent
      : ((session.payment_intent as { id?: string } | null)?.id || null)

    // D2: dorovnání na minimální platbu kartou do objednávky PŘED potvrzením (doklady
    // vystavené při potvrzení pak nesou zaplacenou částku i řádek dorovnání).
    if (!freeSession) {
      let cr: string
      try {
        cr = await applyChargeRounding(sb, { table: 'shop_orders', id: orderId, md, payRef: piId || sid })
      } catch { cr = 'error' }
      if (cr === 'error') return respond(200, { success: false, retry: true, order_id: orderId })
    }

    // ATOMIC confirm — stejná RPC jako webhook (confirmShopPayment). was_already_paid=true
    // → webhook nebo dřívější poll už potvrdil; skončíme bez druhého mailu.
    const { data: confirmData, error: rpcErr } = await sb.rpc('confirm_shop_payment', { p_order_id: orderId, p_method: 'card' })
    if (rpcErr) {
      // Fallback přímý UPDATE — BEFORE UPDATE trigger auto_process_voucher_order vygeneruje
      // voucher i tak (OLD.payment_status='pending' → NEW.payment_status='paid').
      await sb.from('shop_orders')
        .update({ payment_status: 'paid', payment_method: 'card', confirmed_at: new Date().toISOString() })
        .eq('id', orderId).neq('payment_status', 'paid')
    }
    const wasAlreadyPaid = !!(confirmData as Record<string, unknown> | null)?.was_already_paid

    if (piId) {
      try {
        await sb.from('shop_orders').update({ stripe_payment_intent_id: piId, stripe_session_id: sid })
          .eq('id', orderId).is('stripe_payment_intent_id', null)
      } catch { /* ignore */ }
    }
    try {
      await sb.from('debug_log').insert({
        source: 'process-payment', action: 'verify_shop_session_confirmed', component: 'voucher_checkout', status: 'ok',
        request_data: { session_id: sid, order_id: orderId, was_already_paid: wasAlreadyPaid },
      })
    } catch { /* ignore */ }
    if (wasAlreadyPaid) return respond(200, { success: true, already_paid: true, order_id: orderId })

    // Vyhráli jsme atomic flip → dogenerujeme voucher (pojistka, kdyby trigger selhal),
    // FV (účetní doklad) a pošleme voucher_purchased mail — zrcadlí confirmShopPayment.
    try {
      await postConfirm(sb, orderId, deps, doFetch)
    } catch (e) {
      try {
        await sb.from('debug_log').insert({
          source: 'process-payment', action: 'verify_shop_session_postprocess_failed', component: 'voucher_checkout',
          status: 'error', error_message: (e as Error).message, request_data: { order_id: orderId },
        })
      } catch { /* ignore */ }
    }
    return respond(200, { success: true, confirmed: true, order_id: orderId })
  } catch (e) {
    return respond(500, { success: false, error: (e as Error).message })
  }
}

async function postConfirm(sb: Sb, orderId: string, deps: VerifyShopDeps, doFetch: typeof fetch): Promise<void> {
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${deps.serviceKey}`, 'apikey': deps.serviceKey }
  const { data: order } = await sb.from('shop_orders')
    .select('customer_name, customer_email, order_number, status, total').eq('id', orderId).single()
  const { data: items } = await sb.from('shop_order_items').select('product_name').eq('order_id', orderId)
  const hasVoucherItem = (items || []).some((it: { product_name?: string }) =>
    /voucher|poukaz/i.test(String(it.product_name || '')))
  let { data: vouchers } = await sb.from('vouchers').select('code, amount, valid_until').eq('order_id', orderId)
  if (hasVoucherItem && (!vouchers || vouchers.length === 0)) {
    try { await sb.rpc('regen_voucher_for_order', { p_order_id: orderId }) } catch { /* ignore */ }
    const re = await sb.from('vouchers').select('code, amount, valid_until').eq('order_id', orderId)
    vouchers = re.data
  }
  // FV (shop_final) pro doručený elektronický voucher — jen účetní doklad ve Velínu.
  if (order?.status === 'delivered') {
    try {
      await doFetch(`${deps.supabaseUrl}/functions/v1/generate-invoice`, {
        method: 'POST', headers, body: JSON.stringify({ type: 'shop_final', order_id: orderId, send_email: false }),
      })
    } catch { /* ignore */ }
  }
  if (order?.customer_email && vouchers && vouchers.length > 0) {
    const orderNum = order.order_number || orderId.slice(-8).toUpperCase()
    const firstVoucher = vouchers[0] as { code: string; amount: number; valid_until: string }
    const allCodes = vouchers.map((v: { code: string; amount: number }) => `${v.code} (${v.amount} Kč)`).join(', ')
    await doFetch(`${deps.supabaseUrl}/functions/v1/send-booking-email`, {
      method: 'POST', headers,
      body: JSON.stringify({
        type: 'voucher_purchased', customer_email: order.customer_email, customer_name: order.customer_name || '',
        voucher_code: allCodes, voucher_value: String(firstVoucher.amount), voucher_expiry: firstVoucher.valid_until,
        order_number: orderNum, order_id: orderId, source: 'web',
      }),
    })
  }
}
