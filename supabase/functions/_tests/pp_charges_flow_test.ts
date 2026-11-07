// ===== _tests/pp_charges_flow_test.ts =====
// verify:charges (2026-11-05) — adversariální flow testy CELÉHO handleru process-payment (mode intent,
// appka): strhne se VŽDY jen částka z požadavku (nikdy víc, než appka ukázala), dorovnání / odpuštění
// jen s card_min, měna jen CZK, staré appky pod 15 Kč = below_minimum bez stržení, cena 0 jen doložená.
// Import mapa gear-flow-map.json (supabase-js = LooseDb); spouští gear_flow_runner_test.ts v podprocesu.
import { LooseDb, stubFetch } from './gear-fake.ts'
import { stripe } from '../process-payment/stripe-customer.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
type Handler = (req: Request) => Response | Promise<Response>
const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
const SVC = 'svc-test-key'
if (MAPPED) { Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC) }
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown }
const BID = '11111111-2222-3333-4444-5555666677cc'
const OID = '22222222-3333-4444-5555-6666777788dd'
let handler: Handler | null = null
async function pp(): Promise<Handler> {
  if (handler) return handler
  const d = Deno as unknown as { serve: unknown }
  const orig = d.serve
  let captured: Handler | null = null
  const before = (g.__gearHandlers || []).length
  d.serve = (h: Handler) => { captured = h; return { finished: Promise.resolve(), shutdown: () => Promise.resolve() } }
  try { await import('../process-payment/index.ts') } finally { d.serve = orig }
  handler = captured || (g.__gearHandlers || [])[before]
  if (!handler) throw new Error('process-payment handler se nezaregistroval')
  return handler
}

type Pi = Row & { id: string; status: string }
type StripeMock = { paymentIntents: { create: (p: Row, o?: Row) => Promise<Row>; retrieve: (id: string) => Promise<Row>; cancel: (id: string) => Promise<Row>; search?: unknown } }
function patchStripe(stored: Pi[] = []) {
  const st = stripe as unknown as StripeMock
  const orig = { create: st.paymentIntents.create, retrieve: st.paymentIntents.retrieve, cancel: st.paymentIntents.cancel, search: st.paymentIntents.search }
  const intents: Row[] = []
  st.paymentIntents.create = (p: Row) => { intents.push(p); return Promise.resolve({ id: `pi_new_${intents.length}`, client_secret: 'cs', status: 'requires_payment_method', amount: p.amount, currency: p.currency, metadata: p.metadata }) }
  st.paymentIntents.retrieve = (id: string) => { const p = stored.find((x) => x.id === id); return p ? Promise.resolve({ ...p }) : Promise.reject(Object.assign(new Error('no pi'), { code: 'resource_missing' })) }
  st.paymentIntents.cancel = (id: string) => { const p = stored.find((x) => x.id === id)!; p.status = 'canceled'; return Promise.resolve({ ...p }) }
  st.paymentIntents.search = undefined
  return { intents, restore: () => Object.assign(st.paymentIntents, orig) }
}

function booking(over: Row = {}): Row {
  return { id: BID, user_id: 'u1', status: 'pending', payment_status: 'unpaid', booking_source: 'app', booking_kind: 'moto', moto_id: 'm1',
    trailer_moto_id: null, total_price: 1000, card_rounding: 0, discount_amount: 0, extras_price: 0, delivery_fee: 0, loyalty_discount_amount: 0,
    late_pickup_discount_amount: 0, start_date: '2026-12-10', end_date: '2026-12-11', pickup_time: '10:00:00', pickup_method: 'branch',
    pickup_address: null, return_method: 'branch', return_address: null, sos_replacement: false, stripe_payment_intent_id: null, promo_code_id: null,
    voucher_id: null, modification_history: [], motorcycles: { model: 'M', manual_url: '', is_trailer: false }, profiles: { full_name: 'J', email: 'j@x.cz' }, ...over }
}
function dbFor(bk: Row, extra: Record<string, Row[]> = {}): LooseDb {
  const db = new LooseDb({ bookings: [bk], booking_discounts: [], vouchers: [], promo_codes: [], feature_flags: [], debug_log: [], profiles: [], shop_orders: [], ...extra })
  db.rpcs._moto_dayprice_sum = () => ({ data: Number(bk.total_price) || 0, error: null }) // ceník = uložená cena
  db.rpcs.confirm_payment = () => { bk.payment_status = 'paid'; return { data: { success: true, was_already_paid: false }, error: null } }
  db.rpcs.confirm_shop_payment = () => ({ data: { success: true, was_already_paid: false }, error: null })
  db.rpcs.check_moto_availability = () => ({ data: true, error: null })
  return db
}
async function pay(db: LooseDb, body: Row, stored: Pi[] = []) {
  g.__gearFakeDb = db
  const h = await pp()
  const st = patchStripe(stored)
  const f = stubFetch(() => new Response('{}', { status: 200 }))
  try {
    const res = await h(new Request('http://x/pp', { method: 'POST', headers: { Authorization: `Bearer ${SVC}` }, body: JSON.stringify(body) }))
    const json = await res.json()
    return { status: res.status, json, intents: st.intents, code: json.code, amount: st.intents[0]?.amount, md: (st.intents[0]?.metadata || {}) as Row, fetches: f.calls }
  } finally { st.restore(); f.restore() }
}
const bookPay = (total: number, amount: number, cardMin = true, over: Row = {}, extra: Row = {}) =>
  pay(dbFor(booking({ total_price: total, ...over })), { type: 'booking', booking_id: BID, amount, mode: 'intent', ...(cardMin ? { card_min: true } : {}), ...extra })

Deno.test({ name: 'charges rezervace (appka, card_min): strženo = částka z požadavku; dorovnání jen do metadat; cena beze změny do webhooku', ignore: !MAPPED, fn: async () => {
  for (const [total, want] of [[1.01, '13.99'], [7.5, '7.5'], [14.99, '0.01']] as Array<[number, string]>) {
    const r = await bookPay(total, 15)
    eq([r.status, r.amount, r.md.due, r.md.card_rounding, r.json.charge, r.json.card_rounding], [200, 1500, String(total), want, 15, Number(want)], `due ${total}`)
    eq(r.intents[0].currency, 'czk')
  }
  const a = await bookPay(15, 15); eq([a.status, a.amount, a.md.card_rounding ?? null], [200, 1500, null], 'přesně 15')
  const b = await bookPay(15.4, 15); eq([b.status, b.amount, b.md.card_rounding], [200, 1500, '-0.4'], '15,40 → 15')
  const c = await bookPay(16, 15); eq([c.status, c.amount, c.md.card_rounding], [200, 1500, '-1'], 'doklad 16, strženo 15 (i1)')
  const d = await bookPay(100, 100); eq([d.status, d.amount, d.md.card_rounding ?? null], [200, 10000, null])
} })

Deno.test({ name: 'charges rezervace: odpuštění do 1 Kč = bez Stripe, confirm_payment free, cena 0 a card_rounding −due', ignore: !MAPPED, fn: async () => {
  for (const total of [0.5, 1]) {
    const db = dbFor(booking({ total_price: total }))
    const r = await pay(db, { type: 'booking', booking_id: BID, amount: 0, mode: 'intent', card_min: true })
    eq([r.status, r.json.success, r.json.waived, r.json.charge, r.intents.length], [200, true, true, 0, 0], `due ${total}`)
    const bk = db.rows('bookings')[0]
    eq([bk.total_price, bk.card_rounding, db.callsOf('rpc', 'confirm_payment')[0]?.data], [0, -total, { p_booking_id: BID, p_method: 'free' }])
  }
} })

Deno.test({ name: 'charges rezervace: nesoulad částky = odmítnutí bez PaymentIntentu (méně, víc bez doprodeje, 15 za 7 bez card_min, stará appka pod 15)', ignore: !MAPPED, fn: async () => {
  const cases: Array<[number, number, boolean, number, string]> = [
    [100, 50, true, 409, 'amount_mismatch'], [100, 200, true, 409, 'amount_mismatch'], [100, 200, false, 409, 'amount_mismatch'],
    [7, 15, false, 409, 'amount_mismatch'], [7, 7, false, 400, 'below_minimum'], [0.5, 1, false, 400, 'below_minimum'], [7, 7, true, 400, 'below_minimum'],
    [100, 0, true, 400, 'free_mismatch'], [100, -5, true, 400, 'free_mismatch'],
  ]
  for (const [total, amount, cm, status, code] of cases) {
    const r = await bookPay(total, amount, cm)
    eq([r.status, r.code, r.intents.length], [status, code, 0], `due ${total} amount ${amount} card_min ${cm}`)
    if (!/@|\+420/.test(String(r.json.error)) === false) throw new Error('kontakt v textu')
  }
} })

Deno.test({ name: 'charges rezervace: měna jen CZK, zaplacená = already_paid, dorovnání bez SQL = rounding_unavailable (ok cesta beze změny jako main)', ignore: !MAPPED, fn: async () => {
  const cur = await bookPay(100, 100, true, {}, { currency: 'eur' }); eq([cur.status, cur.code, cur.intents.length], [400, 'invalid_currency', 0])
  const paid = await bookPay(100, 100, true, { payment_status: 'paid' }); eq([paid.status, paid.code, paid.json.already_paid], [409, 'already_paid', true])
  const bkNoCol = booking({ total_price: 7 }); delete bkNoCol.card_rounding
  const nc = await pay(dbFor(bkNoCol), { type: 'booking', booking_id: BID, amount: 15, mode: 'intent', card_min: true })
  eq([nc.status, nc.code, nc.intents.length], [409, 'rounding_unavailable', 0])
  const bk16 = booking({ total_price: 16 }); delete bk16.card_rounding
  const ok16 = await pay(dbFor(bk16), { type: 'booking', booking_id: BID, amount: 15, mode: 'intent', card_min: true })
  eq([ok16.status, ok16.amount, ok16.md.card_rounding ?? null], [200, 1500, null], 'bez sloupce: 15 za 16 jako dnes na main (bez záznamu)')
} })

Deno.test({ name: 'charges rezervace zdarma: cena 0 jen s doloženou slevou (poukaz na celou cenu), jinak free_mismatch', ignore: !MAPPED, fn: async () => {
  const bare = dbFor(booking({ total_price: 0 })); bare.rpcs._moto_dayprice_sum = () => ({ data: 1000, error: null })
  const no = await pay(bare, { type: 'booking', booking_id: BID, amount: 0, mode: 'intent', card_min: true })
  eq([no.status, no.code, no.intents.length], [400, 'free_mismatch', 0])
  const withV = dbFor(booking({ total_price: 0, discount_amount: 1000, voucher_id: 'v1' }), { vouchers: [{ id: 'v1', code: 'ABC', amount: 1000, status: 'active', booking_id: null, valid_until: null }] })
  withV.rpcs._moto_dayprice_sum = () => ({ data: 1000, error: null })
  const yes = await pay(withV, { type: 'booking', booking_id: BID, amount: 0, mode: 'intent', card_min: true })
  eq([yes.status, yes.json.free, withV.callsOf('rpc', 'confirm_payment').length], [200, true, 1])
} })

Deno.test({ name: 'charges rezervace: uložený zaplacený PaymentIntent blokuje druhou platbu; celý vrácený ne', ignore: !MAPPED, fn: async () => {
  const live: Pi = { id: 'pi_s', status: 'succeeded', amount: 100000, currency: 'czk', amount_received: 100000, metadata: { booking_id: BID, type: 'booking' }, latest_charge: { amount: 100000, amount_refunded: 0 } }
  const r = await pay(dbFor(booking({ total_price: 1000, stripe_payment_intent_id: 'pi_s' })), { type: 'booking', booking_id: BID, amount: 1000, mode: 'intent', card_min: true }, [live])
  eq([r.status, r.code, r.intents.length], [409, 'payment_in_progress', 0])
  const back: Pi = { ...live, latest_charge: { amount: 100000, amount_refunded: 100000 } }
  const r2 = await pay(dbFor(booking({ total_price: 1000, stripe_payment_intent_id: 'pi_s' })), { type: 'booking', booking_id: BID, amount: 1000, mode: 'intent', card_min: true }, [back])
  eq([r2.status, r2.amount], [200, 100000], 'storno + obnovení → nová platba smí')
} })

const order = (total: number, over: Row = {}): Row => ({ id: OID, customer_id: 'u1', payment_status: 'pending', total, card_rounding: 0, stripe_payment_intent_id: null, ...over })
const shopPay = (total: number, amount: number, cardMin = true) => {
  const db = dbFor(booking(), { shop_orders: [order(total)] })
  return pay(db, { type: 'shop', order_id: OID, amount, mode: 'intent', ...(cardMin ? { card_min: true } : {}) }).then((r) => ({ ...r, db }))
}
Deno.test({ name: 'charges e-shop (appka): částka přesně dle serveru; 1–15 Kč → 15 s dorovnáním; do 1 Kč zdarma; stará appka pod 15 = below_minimum', ignore: !MAPPED, fn: async () => {
  const a = await shopPay(7, 15); eq([a.status, a.amount, a.md.due, a.md.card_rounding], [200, 1500, '7', '8'])
  const b = await shopPay(99.5, 100); eq([b.status, b.amount, b.md.card_rounding], [200, 10000, '0.5'])
  const c = await shopPay(100, 50); eq([c.status, c.code, c.intents.length], [409, 'amount_mismatch', 0])
  const d = await shopPay(7, 7, false); eq([d.status, d.code, d.intents.length], [400, 'below_minimum', 0])
  const e = await shopPay(7, 15, false); eq([e.status, e.code, e.intents.length], [409, 'amount_mismatch', 0], '15 za 7 bez card_min se nestrhne')
  const w = await shopPay(0.8, 0); eq([w.status, w.json.waived, w.intents.length], [200, true, 0])
  eq([w.db.rows('shop_orders')[0].total, w.db.rows('shop_orders')[0].card_rounding, w.db.callsOf('rpc', 'confirm_shop_payment')[0]?.data], [0, -0.8, { p_order_id: OID, p_method: 'free' }])
  const z = await shopPay(0, 0); eq([z.status, z.code], [409, 'no_payment_needed'])
} })

const extPay = (newTotal: number, amount: number, cardMin = true) =>
  pay(dbFor(booking({ status: 'reserved', payment_status: 'paid', total_price: 1000 })),
    { type: 'extension', booking_id: BID, amount, mode: 'intent', ...(cardMin ? { card_min: true } : {}), change: { total_price: newTotal, end_date: '2026-12-12', _base: { s: '2026-12-10', e: '2026-12-11', t: '10:00', p: 1000 } } })
Deno.test({ name: 'charges doplatek (app formát): ±1 Kč dle serveru, 1–15 Kč jen s card_min = 15 + dorovnání, 0 = nic', ignore: !MAPPED, fn: async () => {
  const a = await extPay(1007, 15); eq([a.status, a.amount, a.md.due, a.md.card_rounding], [200, 1500, '7', '8'])
  const b = await extPay(1007, 7, false); eq([b.status, b.code, b.intents.length], [400, 'below_minimum', 0])
  const c = await extPay(1100, 1); eq([c.status, c.code, c.intents.length], [400, 'amount_mismatch', 0])
  const d = await extPay(1016, 16); eq([d.status, d.amount, d.md.card_rounding ?? null], [200, 1600, null])
  const e = await extPay(1016, 15); eq([e.status, e.amount, e.md.card_rounding], [200, 1500, '-1'])
  const f = await extPay(1100, 0); eq([f.status, f.code, f.intents.length], [400, 'amount_mismatch', 0], '0 za doplatek 100 = nesoulad, nic se nestrhne')
  const z = await extPay(1000, 0); eq([z.status, z.code, z.intents.length], [400, 'invalid_amount', 0], 'doplatek 0 se neplatí')
  const h = await extPay(1100, 115); eq([h.status, h.code, h.intents.length], [400, 'amount_mismatch', 0], 'víc než doplatek se nestrhne')
} })

// Oprava i2 (2026-11-05): důkaz „zdarma“ věří sloupcům, které si zákazník zapisuje sám (total_price 0 + discount_amount 100 +
// vlastní poukaz 100 Kč při ceníku 1 000) → spodní mez ze serveru: kalibrace = potvrzeno + mail obsluze (pokaždé),
// PP_FREE_FLOOR_ENFORCE=1 = odmítnuto (free_mismatch, nic nepotvrzeno); promo 100 % projde v obou režimech.
Deno.test({ name: 'charges rezervace zdarma (i2): vlastní poukaz 100 Kč na cenu 1 000 → kalibrace potvrdí + mail obsluze, PP_FREE_FLOOR_ENFORCE=1 odmítne; promo 100 % projde', ignore: !MAPPED, fn: async () => {
  const mk = () => {
    const db = dbFor(booking({ total_price: 0, discount_amount: 100, voucher_id: 'v1' }), { vouchers: [{ id: 'v1', code: 'ABC', amount: 100, status: 'active', booking_id: null, valid_until: null }] })
    db.rpcs._moto_dayprice_sum = () => ({ data: 1000, error: null }); return db
  }
  const promo = () => {
    const db = dbFor(booking({ total_price: 0, discount_amount: 1000, promo_code_id: 'p1' }), { promo_codes: [{ id: 'p1', type: 'percent', value: 100, active: true }] })
    db.rpcs._moto_dayprice_sum = () => ({ data: 1000, error: null }); return db
  }
  const free = { type: 'booking', booking_id: BID, amount: 0, mode: 'intent', card_min: true }
  const d1 = mk(); const a = await pay(d1, free)
  eq([a.status, a.json.free, d1.callsOf('rpc', 'confirm_payment').length], [200, true, 1], 'kalibrace: potvrzeno')
  eq(a.fetches.some((c) => /send-email/.test(c.url) && /nepokrývají cenu/.test(String(c.body?.subject))), true, 'kalibrace: mail obsluze')
  eq(d1.rows('debug_log').some((r) => r.action === 'free_booking_floor_mismatch'), true)
  Deno.env.set('PP_FREE_FLOOR_ENFORCE', '1')
  try {
    const d2 = mk(); const b = await pay(d2, free)
    eq([b.status, b.code, d2.callsOf('rpc', 'confirm_payment').length, b.intents.length], [400, 'free_mismatch', 0, 0], 'vynucení: odmítnuto')
    eq(b.fetches.some((c) => /send-email/.test(c.url) && /ODMÍTNUTO/.test(String(c.body?.subject))), true, 'vynucení: mail obsluze')
    const d3 = promo(); const c = await pay(d3, free)
    eq([c.status, c.json.free, d3.callsOf('rpc', 'confirm_payment').length], [200, true, 1], 'promo 100 % s vynucením')
  } finally { Deno.env.delete('PP_FREE_FLOOR_ENFORCE') }
  const d4 = promo(); const d = await pay(d4, free)
  eq([d.status, d.json.free, d.fetches.some((c) => /send-email/.test(c.url))], [200, true, false], 'promo 100 % bez vynucení, bez mailu')
} })

// Oprava i2 (2026-11-05): synchronní fallback /potvrzeni (verify_setup_session) potvrzoval 0 Kč rezervaci bez kontroly ceny.
Deno.test({ name: 'charges verify_setup_session (i2): cena změněná na 500 po vzniku setup session → free_mismatch (nic nepotvrzeno); cena 0 → potvrzeno', ignore: !MAPPED, fn: async () => {
  const st = stripe as unknown as { checkout: { sessions: { retrieve: (id: string) => Promise<Row> } } }
  const orig = st.checkout.sessions.retrieve
  st.checkout.sessions.retrieve = () => Promise.resolve({ id: 'cs_s1', status: 'complete', mode: 'setup', metadata: { action: 'verify_free_booking', booking_id: BID }, client_reference_id: BID })
  try {
    const db = dbFor(booking({ total_price: 500 }))
    const r = await pay(db, { action: 'verify_setup_session', session_id: 'cs_s1' })
    eq([r.status, r.code, r.json.server_total, db.callsOf('rpc', 'confirm_payment').length], [409, 'free_mismatch', 500, 0])
    eq(r.fetches.some((c) => /send-email/.test(c.url) && /cena se změnila/.test(String(c.body?.subject))), true, 'mail obsluze')
    const db2 = dbFor(booking({ total_price: 0 }))
    const r2 = await pay(db2, { action: 'verify_setup_session', session_id: 'cs_s1' })
    eq([r2.status, r2.json.success, db2.callsOf('rpc', 'confirm_payment').length], [200, true, 1])
  } finally { st.checkout.sessions.retrieve = orig }
} })
