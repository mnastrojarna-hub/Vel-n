// ===== _tests/f2_customer_refund_test.ts =====
// fix f2 (2026-10-22): zákaznická vratka z appky (zkrácení / levnější motorka) šla jen z uložené
// platby — typicky posledního doplatku úpravy — a oříznutá na jeho zbytek; zbytek se tiše ztratil
// (odpověď success). Teď zdroj jako u obsluhy (mainSource), zbytek do ověřeného přeplatku
// (customerCapHaleru — jen platby v ceně rezervace) z ostatních plateb, co nejde → obsluha + partial.
// Scénáře níže opakují pořadí kroků process-refund/index.ts (mainSource → strop → hlavní vratka →
// refundRemainder → short).
import { mainSource, customerCapHaleru, refundRemainder, refundedStatus, CUSTOMER_SHORT_TOLERANCE_HALERU } from '../process-refund/other-intents.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
const BID = '11111111-2222-4333-8444-555555555555'
const NOW = Date.UTC(2026, 9, 22, 12, 0, 0)
type Pi = { id: string; status: string; amount_received: number; created: number; metadata: Record<string, string> }
const pi = (id: string, h: number, created: number, md: Record<string, string> = { booking_id: BID, type: 'booking' }): Pi =>
  ({ id, status: 'succeeded', amount_received: h, created, metadata: md })
const ext = (id: string, h: number, created: number, more: Record<string, string> = {}) =>
  pi(id, h, created, { booking_id: BID, type: 'extension', ...more })

function fakeStripe(intents: Pi[]) {
  const refunds: Record<string, Array<{ id: string; amount: number; status: string; metadata: Record<string, string> }>> = {}
  const byKey = new Map<string, { id: string; amount: number; status: string }>()
  let n = 0
  const left = (id: string) => (intents.find((x) => x.id === id)?.amount_received || 0) - (refunds[id] || []).reduce((s, r) => s + r.amount, 0)
  const stripe = {
    paymentIntents: {
      search: () => Promise.resolve({ data: intents.filter((x) => x.metadata.booking_id === BID && x.status === 'succeeded') }),
      retrieve: (id: string) => { const x = intents.find((p) => p.id === id); return x ? Promise.resolve(x) : Promise.reject(new Error('missing')) },
    },
    refunds: {
      list: (p: Row) => Promise.resolve({ data: refunds[String(p.payment_intent)] || [] }),
      create: (p: Row, o: Row = {}) => {
        const key = String(o.idempotencyKey || '')
        if (key && byKey.has(key)) return Promise.resolve(byKey.get(key)!)
        const id = String(p.payment_intent)
        const amt = p.amount != null ? Number(p.amount) : left(id)
        if (amt <= 0 || amt > left(id)) return Promise.reject(new Error('charge_already_refunded'))
        const r = { id: `re_${++n}`, amount: amt, status: 'succeeded', metadata: (p.metadata || {}) as Record<string, string> }
        ;(refunds[id] ||= []).push(r); if (key) byKey.set(key, r)
        return Promise.resolve(r)
      },
    },
  }
  return { stripe, refunds, left }
}
const bk = (o: Row = {}): Row => ({ id: BID, user_id: 'u1', status: 'reserved', payment_status: 'paid', total_price: 2615,
  modification_history: [], stripe_payment_intent_id: 'pi_ext', ...o })

/** Zákaznická vratka tak, jak ji provede process-refund/index.ts (Stripe větev). */
async function customerRefund(f: ReturnType<typeof fakeStripe>, d: FakeDb, storedId: string, amountCzk: number, totalPrice: number) {
  const s = f.stripe as never
  const storedPi = await f.stripe.paymentIntents.retrieve(storedId).catch(() => null)
  const storedRefunds = (await f.stripe.refunds.list({ payment_intent: storedId })).data
  const charged = storedPi?.amount_received || 0
  let refundable = Math.max(0, charged - storedRefunds.reduce((t, r) => t + r.amount, 0))
  let mainPi = storedId
  const src = await mainSource(s, d, { bookingId: BID, storedPiId: storedId, storedPi, storedRefunds, chargedHaleru: charged,
    refundableHaleru: refundable, isCustomer: true, amount: amountCzk, nowMs: NOW })
  if (src.kind === 'manual') return { kind: 'manual' as const }
  if (src.kind === 'retarget') { mainPi = src.piId; refundable = src.refundableHaleru }
  if (refundable === 0 && src.kind === 'stored' && charged === 0) return { kind: 'manual' as const }
  const req = Math.round(amountCzk * 100)
  let eff = Math.min(req, refundable)
  const cap = await customerCapHaleru(s, d, { bookingId: BID, storedPi, storedRefunds, totalPrice, nowMs: NOW })
  if (cap == null || Math.min(eff, cap) <= 0) return { kind: 'staff' as const, cap }
  eff = Math.min(eff, cap)
  const main = await f.stripe.refunds.create({ payment_intent: mainPi, amount: eff, metadata: { mg_source: 'process-refund' } },
    { idempotencyKey: `refund:${BID}:${eff}:${refundable}` })
  const target = Math.min(req, cap)
  const extra = target > eff
    ? await refundRemainder(s, d, { bookingId: BID, mainPi, mainRefundId: main.id, remainingHaleru: target - eff })
    : { refunds: [], refundedHaleru: 0, leftHaleru: 0 }
  const shortRaw = Math.max(0, req - eff - extra.refundedHaleru)
  const short = shortRaw <= CUSTOMER_SHORT_TOLERANCE_HALERU ? 0 : shortRaw
  return { kind: 'stripe' as const, mainPi, main: eff, extra: extra.refundedHaleru, short, cap,
    status: refundedStatus({ refundStatus: 'succeeded', isCustomer: true, bookingTotalPrice: totalPrice, amount: amountCzk,
      refundableHaleru: refundable, effectiveAmountHaleru: eff, leftHaleru: extra.leftHaleru, shortHaleru: short }) }
}

Deno.test('f2: zkrácení v appce po zaplacené úpravě (uložen doplatek 115 Kč) → vrátí se celých 500 Kč (115 + 385 z původní platby)', async () => {
  const d = new FakeDb({ bookings: [bk()], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: '2026-10-22T11:00:00Z' })])
  const r = await customerRefund(f, d, 'pi_ext', 500, 2615)
  eq(r, { kind: 'stripe', mainPi: 'pi_ext', main: 11500, extra: 38500, short: 0, cap: 50000, status: 'partial_refund' })
  eq(f.left('pi_ext'), 0); eq(f.left('pi_orig'), 261500)
  // tentýž požadavek znovu (duplicitní volání po dokončení) → strop je vyčerpaný → obsluha, nic navíc
  eq((await customerRefund(f, d, 'pi_ext', 500, 2615)).kind, 'staff'); eq(f.left('pi_orig'), 261500)
})

Deno.test('f2: dorovnaný doplatek 15 Kč (D1) uložen → vratka zkrácení 500 Kč = 15 + 485 z původní platby', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 2515 })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 1500, NOW / 1000 - 3600, { applied_at: '2026-10-22T11:00:00Z' })])
  const r = await customerRefund(f, d, 'pi_ext', 500, 2515)
  eq(r, { kind: 'stripe', mainPi: 'pi_ext', main: 1500, extra: 48500, short: 0, cap: 50000, status: 'partial_refund' })
})

Deno.test('f2: uložený PI opuštěného doplatku (nikdy nezaplacený) → vratka kartou z původní platby, ne ruční / obsluha', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 2500, stripe_payment_intent_id: 'pi_open' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), { ...ext('pi_open', 0, NOW / 1000 - 60, { chg_hash: 'o' }), status: 'requires_payment_method' }])
  const r = await customerRefund(f, d, 'pi_open', 500, 2500)
  eq(r, { kind: 'stripe', mainPi: 'pi_orig', main: 50000, extra: 0, short: 0, cap: 50000, status: 'partial_refund' })
})

Deno.test('f2: uložený doplatek vyčerpaný (vrácený) → hlavní vratka z původní platby', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 2700 })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { applied_at: 'x' })])
  await f.stripe.refunds.create({ payment_intent: 'pi_ext', amount: 11500, metadata: { mg_source: 'process-refund' } })
  // zaplaceno 3115 − vráceno 115 = 3000; cena po dalším zkrácení 2700 → přeplatek 300
  const r = await customerRefund(f, d, 'pi_ext', 300, 2700)
  eq(r, { kind: 'stripe', mainPi: 'pi_orig', main: 30000, extra: 0, short: 0, cap: 30000, status: 'partial_refund' })
})

Deno.test('f2: doplatek nezapsané změny, který automatika nevrátila (obsluha) → nepoužije se jako vratka zkrácení ani nenafoukne strop', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 2500, stripe_payment_intent_id: 'pi_fail' })],
    debug_log: [{ id: 'l1', action: 'paid_change_failed', created_at: '2026-10-22T10:00:00Z', request_data: { payment_ref: 'pi_fail' },
      response_data: { refund: 'staff' } }] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_fail', 50000, NOW / 1000 - 7200, { chg_hash: 'f' })])
  const r = await customerRefund(f, d, 'pi_fail', 500, 2500)
  eq(r, { kind: 'stripe', mainPi: 'pi_orig', main: 50000, extra: 0, short: 0, cap: 50000, status: 'partial_refund' })
  eq(f.left('pi_fail'), 50000) // doplatek zůstal celý k vrácení obsluhou
  // přemrštěný požadavek (upravený klient) nedostane navíc ani o doplatek mimo cenu
  const d2 = new FakeDb({ bookings: [bk({ total_price: 2500, stripe_payment_intent_id: 'pi_fail' })], debug_log: d.rows('debug_log') })
  const f2 = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_fail', 50000, NOW / 1000 - 7200, { chg_hash: 'f' })])
  const r2 = await customerRefund(f2, d2, 'pi_fail', 1000, 2500)
  eq(r2, { kind: 'stripe', mainPi: 'pi_orig', main: 50000, extra: 0, short: 50000, cap: 50000, status: 'partial_refund' })
})

Deno.test('f2: doplatek, který webhook ještě nezapsal → vratka z původní platby (dřív celá na obsluhu), strop bez něj', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 2500, stripe_payment_intent_id: 'pi_pend' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_pend', 20000, NOW / 1000 - 30, { chg_hash: 'p' })])
  const r = await customerRefund(f, d, 'pi_pend', 500, 2500)
  eq(r, { kind: 'stripe', mainPi: 'pi_orig', main: 50000, extra: 0, short: 0, cap: 50000, status: 'partial_refund' })
  eq(f.left('pi_pend'), 20000)
})

Deno.test('f2: strop menší než požadavek → vrátí se jen ověřený přeplatek, short > 0 (obsluha + partial)', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 2800 })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { applied_at: 'x' })])
  // zaplaceno 3115, cena 2800 → přeplatek 315; appka žádá 500
  const r = await customerRefund(f, d, 'pi_ext', 500, 2800)
  eq(r, { kind: 'stripe', mainPi: 'pi_ext', main: 11500, extra: 20000, short: 18500, cap: 31500, status: 'partial_refund' })
  eq(f.left('pi_orig'), 280000)
})

Deno.test('f2: strop — e-shop (typ shop i přibalená část), duplicita a cizí platba se nepočítají; chyba čtení ostatních = jen uložená', async () => {
  const d = new FakeDb({ bookings: [bk({ total_price: 3000, stripe_payment_intent_id: 'pi_orig' })], debug_log: [],
    shop_orders: [{ id: 'so1', total: 400 }] })
  const f = fakeStripe([
    pi('pi_orig', 350000, 100, { booking_id: BID, type: 'booking', shop_order_id: 'so1' }), // 3100 pronájem + 400 zboží
    pi('pi_shop', 90000, 150, { booking_id: BID, type: 'shop' }),
    pi('pi_dup', 350000, 160, { booking_id: BID, type: 'booking', duplicate_of: 'pi_orig' }),
    ext('pi_e', 5000, 170, { applied_at: 'x' }),
  ])
  const stored = await f.stripe.paymentIntents.retrieve('pi_orig')
  eq(await customerCapHaleru(f.stripe as never, d, { bookingId: BID, storedPi: stored, storedRefunds: [], totalPrice: 3000, nowMs: NOW }),
    310000 + 5000 - 300000)
  const broken = { ...f.stripe, paymentIntents: { ...f.stripe.paymentIntents, search: () => Promise.reject(new Error('search down')) } }
  eq(await customerCapHaleru(broken as never, d, { bookingId: BID, storedPi: stored, storedRefunds: [], totalPrice: 3000, nowMs: NOW }), 10000)
  // uložená platba cizí rezervace se nepočítá
  const foreign = { ...stored, metadata: { booking_id: 'aaaaaaaa-2222-4333-8444-555555555555', type: 'booking' } }
  eq(await customerCapHaleru(f.stripe as never, d, { bookingId: BID, storedPi: foreign, storedRefunds: [], totalPrice: 3000, nowMs: NOW }), 0)
})

Deno.test('f2: zákaznická vratka s nevráceným zbytkem → partial_refund i při nulové ceně', () => {
  eq(refundedStatus({ refundStatus: 'succeeded', isCustomer: true, bookingTotalPrice: 0, amount: 100, refundableHaleru: 5000,
    effectiveAmountHaleru: 5000, leftHaleru: 0, shortHaleru: 5000 }), 'partial_refund')
  eq(refundedStatus({ refundStatus: 'succeeded', isCustomer: true, bookingTotalPrice: 0, amount: 50, refundableHaleru: 5000,
    effectiveAmountHaleru: 5000, leftHaleru: 0, shortHaleru: 0 }), 'refunded')
  eq(refundedStatus({ refundStatus: 'pending', isCustomer: true, bookingTotalPrice: 100, amount: 50, refundableHaleru: 5000,
    effectiveAmountHaleru: 5000, leftHaleru: 0, shortHaleru: 100 }), 'refund_pending')
})

Deno.test('f2: zbytek do 1 Kč = zaokrouhlení ceny na haléře (numeric(10,2)) → bez obsluhy a bez partial', async () => {
  // appka: nová cena 2666,665 → DB 2666,67; vratka 333,34 (33334 haléřů); ověřený přeplatek 33333
  const d = new FakeDb({ bookings: [bk({ total_price: 2666.67, stripe_payment_intent_id: 'pi_orig' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100)])
  const r = await customerRefund(f, d, 'pi_orig', 333.34, 2666.67)
  eq(r, { kind: 'stripe', mainPi: 'pi_orig', main: 33333, extra: 0, short: 0, cap: 33333, status: 'partial_refund' })
})
