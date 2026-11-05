// ===== _tests/currency_test.ts =====
// Měna plateb = vždy CZK a určuje ji server (oprava 2026-11-05, _shared/currency.ts):
// `currency` z požadavku se do Stripe nikdy nepropisuje (dřív `body.currency || 'czk'`).
import { CZK, requestedCurrencyOk, paymentCurrencyOk } from '../_shared/currency.ts'
import { handleWebBookingCheckout, handleSosPaymentLink } from '../process-payment/payment-flows.ts'
import { stripe } from '../process-payment/stripe-customer.ts'
import { CS } from '../process-payment/refusals.ts'
import { LooseDb, stubFetch } from './gear-fake.ts'

type Row = Record<string, unknown>
function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }

Deno.test('currency: požadavek smí CZK nebo nic; cokoli jiného se odmítá', () => {
  for (const v of [undefined, null, '', 'czk', 'CZK', ' Czk ']) ok(requestedCurrencyOk(v), `ok ${JSON.stringify(v)}`)
  for (const v of ['eur', 'EUR', 'huf', 'usd', 'czk ', 0, 1, true, {}, [], 'czk,eur']) {
    if (v === 'czk ') { ok(requestedCurrencyOk(v)); continue } // ořez mezer
    ok(!requestedCurrencyOk(v), `refuse ${JSON.stringify(v)}`)
  }
  eq(CZK, 'czk')
})

Deno.test('currency: zaplacená platba ze Stripe jen v CZK (setup session bez měny = ok)', () => {
  ok(paymentCurrencyOk('czk')); ok(paymentCurrencyOk('CZK')); ok(paymentCurrencyOk(null)); ok(paymentCurrencyOk(undefined)); ok(paymentCurrencyOk(''))
  ok(!paymentCurrencyOk('eur')); ok(!paymentCurrencyOk('huf')); ok(!paymentCurrencyOk('jpy'))
})

Deno.test('currency: text odmítnutí invalid_currency česky, říká CZK, bez kontaktu', () => {
  ok(/CZK/.test(CS.invalid_currency)); ok(/nestrhli/i.test(CS.invalid_currency))
  ok(!/@|\+420|telefon/i.test(CS.invalid_currency))
})

// ── web (hosted Checkout): měna z požadavku se do Stripe nikdy nedostane ──────────────────
type StripeLike = {
  checkout: { sessions: { create: (p: Row) => Promise<Row>; retrieve: (id: string) => Promise<Row> } }
  customers: { list: (p: Row) => Promise<Row>; create: (p: Row) => Promise<Row> }
}
function patchStripe() {
  const st = stripe as unknown as StripeLike
  const orig = { create: st.checkout.sessions.create, list: st.customers.list, ccreate: st.customers.create }
  const sessions: Row[] = []
  st.checkout.sessions.create = (p: Row) => { sessions.push(p); return Promise.resolve({ id: 'cs_cur_1', url: 'https://checkout.stripe.test/cs_cur_1', payment_intent: 'pi_cur_1' }) }
  st.customers.list = () => Promise.resolve({ data: [] })
  st.customers.create = () => Promise.resolve({ id: 'cus_new' })
  return { sessions, restore: () => { st.checkout.sessions.create = orig.create; st.customers.list = orig.list; st.customers.create = orig.ccreate } }
}
const BID = '11111111-2222-3333-4444-5555666677aa'
const booking = (over: Row = {}): Row => ({
  id: BID, booking_source: 'web', payment_status: 'unpaid', status: 'pending', booking_kind: 'moto', moto_id: 'm1',
  total_price: 2000, discount_amount: 0, start_date: '2026-11-10', end_date: '2026-11-12', created_at: new Date().toISOString(),
  language: 'cs', user_id: 'u1', stripe_session_id: null, voucher_id: null, promo_code_id: null, sos_replacement: false,
  profiles: { full_name: 'Jan Novák', email: 'jan@example.com', phone: '+420777000111', stripe_customer_id: 'cus_1' }, ...over,
})
const currencies = (s: Row) => ((s.line_items as Row[]) || []).map((li) => ((li.price_data as Row) || {}).currency)

Deno.test('web rezervace: body.currency "eur" → Checkout položky v CZK, odpověď bez cizí měny', async () => {
  const db = new LooseDb({ bookings: [booking()], booking_discounts: [], vouchers: [], promo_codes: [], debug_log: [], profiles: [] })
  const st = patchStripe()
  const f = stubFetch(() => new Response(JSON.stringify({ success: true }), { status: 200 }))
  try {
    const res = await handleWebBookingCheckout({ booking_id: BID, amount: 2000, currency: 'eur', type: 'booking', source: 'web', mode: 'checkout',
      origin: 'https://www.motogo24.cz', locale: 'cs' } as never, db as never)
    const json = await res.json()
    eq(json.checkout_url, 'https://checkout.stripe.test/cs_cur_1')
    eq(currencies(st.sessions[0]), ['czk'], 'položka v CZK')
    eq(((st.sessions[0].line_items as Row[])[0].price_data as Row).unit_amount, 200000)
  } finally { st.restore(); f.restore() }
})

Deno.test('web rezervace + přibalené zboží: všechny položky v CZK i při body.currency "huf"', async () => {
  const db = new LooseDb({
    bookings: [booking()], booking_discounts: [], vouchers: [], promo_codes: [], debug_log: [], profiles: [],
    shop_orders: [{ id: 'o1', payment_status: 'pending', shipping_cost: 99, shop_order_items: [{ product_name: 'Rukavice', quantity: 1, unit_price: 500, size: 'M' }] }],
  })
  const st = patchStripe()
  const f = stubFetch(() => new Response(JSON.stringify({ success: true }), { status: 200 }))
  try {
    await handleWebBookingCheckout({ booking_id: BID, amount: 2000, currency: 'huf', type: 'booking', source: 'web', mode: 'checkout',
      shop_order_id: 'o1', origin: 'https://www.motogo24.cz', locale: 'cs' } as never, db as never)
    const cur = currencies(st.sessions[0])
    ok(cur.length >= 3, `položky ${cur.length}`)
    ok(cur.every((c) => c === 'czk'), `vše CZK: ${JSON.stringify(cur)}`)
  } finally { st.restore(); f.restore() }
})

Deno.test('Velín SOS odkaz: body.currency "eur" → Checkout položka v CZK', async () => {
  const db = new LooseDb({ bookings: [booking({ sos_replacement: true })], debug_log: [], profiles: [] })
  const st = patchStripe()
  try {
    const res = await handleSosPaymentLink({ booking_id: BID, amount: 1500, currency: 'eur', incident_id: 'inc1' } as never, db as never)
    const json = await res.json()
    eq(json.success, true)
    eq(currencies(st.sessions[0]), ['czk'])
    eq(((st.sessions[0].line_items as Row[])[0].price_data as Row).unit_amount, 150000)
  } finally { st.restore() }
})
