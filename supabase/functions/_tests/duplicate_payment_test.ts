// ===== _tests/duplicate_payment_test.ts =====
// fix:backend 2 (2026-10-16): druhá platba za totéž (webhook ji vrátí), zámek výměny
// (complete_extension bez rev.12 nezapisuje), zrušená rezervace se doplatkem neoživí.
import { applyPaidExtension, chgDigest } from '../_shared/extension-apply.ts'
import { findDuplicateCharges, refundDuplicatePayment } from '../_shared/duplicate-payment.ts'
import { paidChangeEligibility } from '../_shared/paid-change-guard.ts'
import { handlePaidChangeFailure } from '../_shared/paid-change-failure.ts'
import { prepareExtensionPayment } from '../webhook-receiver/extension-payment.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
const bk = (o: Row = {}): Row => ({ id: 'b1', user_id: 'u1', status: 'reserved', payment_status: 'paid', moto_id: 'm1',
  start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', pickup_time: '10:00:00', total_price: 3000,
  card_rounding: 0, delivery_fee: 0, pickup_method: 'branch', pickup_address: null, return_method: 'branch', return_address: null,
  late_pickup_discount_amount: 0, modification_history: [], updated_at: '2026-10-16T11:00:00.000Z', stripe_payment_intent_id: null, ...o })
const db = (o: Row = {}) => {
  const d = new FakeDb({ bookings: [bk(o)], debug_log: [] })
  d.rpcs._late_pickup_discount = () => ({ data: 0, error: null })
  return d
}
const row = (d: FakeDb) => d.rows('bookings')[0]
const SINCE = '2026-10-16T10:00:00.000Z'
const SWAP = JSON.stringify({ _swap: { m: 'm2', d: '2026-11-11', t: null } })
const missing6 = (a: Row) => ('p_paid' in a || 'p_payment_ref' in a)
  ? { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } } : { data: { success: true }, error: null }

Deno.test('BLOCKER: rev.12 nenasazená — complete_extension výměnu NEzapisuje 6parametrově (retry), webhook ano', async () => {
  const d = db(); let six = 0
  d.rpcs.split_booking_moto_swap = (a) => { if (!missing6(a).error) six++; return missing6(a) }
  const a = { bookingId: 'b1', chg: SWAP, paidCzk: 1000, payRef: 'pi_s', rounding: 0, since: SINCE }
  const r = await applyPaidExtension(d, { ...a, via: 'complete_extension' } as never)
  eq(r.state, 'retry'); eq((r as { code: string }).code, 'swap_webhook_only'); eq(six, 0)
  eq((await applyPaidExtension(d, { ...a, via: 'process-payment' } as never)).state, 'retry'); eq(six, 0)
  eq((await applyPaidExtension(d, { ...a, via: 'webhook' } as never)).state, 'applied'); eq(six, 1)
})
Deno.test('výměna: tutéž výměnu od vytvoření platby zapsala JINÁ platba → duplicate, dorovnání se nepřičte', async () => {
  const d = db({ moto_id: 'm2', total_price: 3015, card_rounding: 6, modification_history: [
    { at: '2026-10-16T10:02:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2', payment_ref: 'pi_first', card_rounding: 6 }] })
  let called = 0
  d.rpcs.split_booking_moto_swap = () => { called++; return { data: null, error: null } }
  const r = await applyPaidExtension(d, { bookingId: 'b1', chg: SWAP, paidCzk: 15, payRef: 'pi_second', rounding: 6, since: SINCE } as never)
  eq(r.state, 'duplicate'); eq((r as { otherRef: string }).otherRef, 'pi_first'); eq(called, 0)
  eq(row(d).total_price, 3015); eq(row(d).card_rounding, 6)
})
Deno.test('výměna: RPC selže, protože ji souběžně zapsal klient bez značky → dorovnání této platby jednou', async () => {
  const d = db()
  d.rpcs.split_booking_moto_swap = () => {
    Object.assign(row(d), { moto_id: 'm2', total_price: 3009, modification_history: [{ at: '2026-10-16T10:03:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2' }] })
    return { data: { success: false, error: 'invalid_new_moto' }, error: null }
  }
  const r = await applyPaidExtension(d, { bookingId: 'b1', chg: SWAP, paidCzk: 15, payRef: 'pi_s', rounding: 6, since: SINCE, via: 'webhook' } as never)
  eq(r.state, 'already_applied'); eq(row(d).total_price, 3015); eq(row(d).card_rounding, 6)
})

const EXT = JSON.stringify({ start_date: '2026-11-10', end_date: '2026-11-13', total_price: 4000, _base: { s: '2026-11-10', e: '2026-11-12', t: '10:00', p: 3000 } })
Deno.test('úprava: tutéž změnu (chg_hash) zapsala jiná platba → duplicate; jiná změna se stejným výsledkem → applied', async () => {
  const h = await chgDigest(EXT)
  const written = { end_date: '2026-11-13T00:00:00+00:00', total_price: 4000 }
  const d = db({ ...written, modification_history: [{ at: '2026-10-16T10:05:00+00:00', to_end: '2026-11-13', payment_ref: 'pi_first', chg_hash: h }] })
  const r = await applyPaidExtension(d, { bookingId: 'b1', chg: EXT, paidCzk: 1000, payRef: 'pi_second', since: SINCE } as never)
  eq(r.state, 'duplicate'); eq((r as { otherRef: string }).otherRef, 'pi_first'); eq(row(d).total_price, 4000)
  const d2 = db({ ...written, modification_history: [{ at: '2026-10-16T10:05:00+00:00', payment_ref: 'pi_other', chg_hash: 'ffff' }] })
  eq((await applyPaidExtension(d2, { bookingId: 'b1', chg: EXT, paidCzk: 1000, payRef: 'pi_second', since: SINCE } as never)).state, 'applied')
  const fresh = db()
  await applyPaidExtension(fresh, { bookingId: 'b1', chg: EXT, paidCzk: 1000, payRef: 'pi_1', since: SINCE } as never)
  eq((row(fresh).modification_history as Row[])[0].chg_hash, h, 'historie nese chg_hash')
})
Deno.test('úprava: zrušená / ukončená rezervace se zaplacenou změnou nemění → failed (vratka)', async () => {
  for (const status of ['cancelled', 'completed']) {
    const d = db({ status })
    const r = await applyPaidExtension(d, { bookingId: 'b1', chg: EXT, paidCzk: 1000, payRef: 'pi_1', since: SINCE } as never)
    eq(r.state, 'failed', status); eq((r as { reason: string }).reason, status === 'cancelled' ? 'booking_cancelled' : 'booking_completed')
    eq(String(row(d).end_date).slice(0, 10), '2026-11-12')
  }
})
Deno.test('výbava: RPC nic nezměnila a stejnou změnu zaplatila jiná platba → duplicate (dorovnání ne podruhé)', async () => {
  const chg = JSON.stringify({ _gear: { sizes: { helmet: 'L' } } })
  const d = db({ total_price: 3015, card_rounding: 8, modification_history: [
    { at: '2026-10-16T10:05:00+00:00', type: 'card_rounding', card_rounding: 8, payment_ref: 'pi_g1', chg_hash: await chgDigest(chg) }] })
  d.rpcs.apply_paid_gear_change = () => ({ data: { success: true, net_diff: 0 }, error: null })
  const r = await applyPaidExtension(d, { bookingId: 'b1', chg, paidCzk: 15, payRef: 'pi_g2', rounding: 8, since: SINCE } as never)
  eq(r.state, 'duplicate'); eq(row(d).total_price, 3015); eq(row(d).card_rounding, 8)
})
Deno.test('eligibility: duplicitní platba (značka duplicate_of / záznam) → duplicate', async () => {
  const d = new FakeDb({ bookings: [{ id: 'b1', modification_history: [] }], debug_log: [{ id: 'x', action: 'duplicate_payment', request_data: { payment_ref: 'pi_2' } }] })
  const pi = { id: 'pi_2', created: 1, metadata: { type: 'extension', booking_id: 'b1', chg_hash: 'a' }, latest_charge: { amount_refunded: 1500 } }
  eq(await paidChangeEligibility(d, pi as never, { bookingId: 'b1', requireNewCode: true, maxAgeH: null }), { ok: false, kind: 'duplicate' })
})

// ── rezervace / objednávka: druhá úspěšná platba ─────────────────────────────
const P = (id: string, at: number, o: Row = {}) => ({ id, status: 'succeeded', amount: 1500, metadata: { booking_id: '11111111-1111-1111-1111-111111111111', type: 'booking' },
  latest_charge: { amount: 1500, amount_refunded: 0, created: at }, ...o })
const REF = '11111111-1111-1111-1111-111111111111'
function fakeStripe(pis: Row[], refundFails = false) {
  const refunds: Array<{ p: Row; o: Row }> = []
  return { refunds, stripe: {
    refunds: { create: (p: Row, o: Row) => { if (refundFails) return Promise.reject(new Error('x')); refunds.push({ p, o }); return Promise.resolve({ id: 're_1' }) } },
    paymentIntents: { list: () => Promise.resolve({ data: pis }), retrieve: (id: string) => Promise.resolve(pis.find((p) => p.id === id)),
      update: () => Promise.resolve({}) },
  } as never }
}
Deno.test('findDuplicateCharges: ponechá nejdřív strženou, vrátí ostatní; vrácené / jiné / 1 platba / >24 h → nic', async () => {
  const two = fakeStripe([P('pi_b', 2000), P('pi_a', 1000), P('pi_x', 900, { metadata: { booking_id: REF, type: 'extension' } })])
  eq(await findDuplicateCharges(two.stripe, { piId: 'pi_b', customer: 'cus', refKey: 'booking_id', refId: REF, type: 'booking' }),
    { keep: 'pi_a', refund: [{ id: 'pi_b', amountCzk: 15 }] })
  // obrácené pořadí událostí: přišla událost PONECHANÉ platby → vrátí se ta druhá
  eq((await findDuplicateCharges(two.stripe, { piId: 'pi_a', customer: 'cus', refKey: 'booking_id', refId: REF, type: 'booking' }))?.refund[0].id, 'pi_b')
  const one = fakeStripe([P('pi_a', 1000), P('pi_b', 2000, { latest_charge: { amount: 1500, amount_refunded: 1500, created: 2000 } })])
  eq(await findDuplicateCharges(one.stripe, { piId: 'pi_a', customer: 'cus', refKey: 'booking_id', refId: REF, type: 'booking' }), null)
  const far = fakeStripe([P('pi_a', 1000), P('pi_b', 1000 + 25 * 3600)])
  eq(await findDuplicateCharges(far.stripe, { piId: 'pi_b', customer: 'cus', refKey: 'booking_id', refId: REF, type: 'booking' }), null)
})
Deno.test('refundDuplicatePayment: celá vratka jednou (klíč mg-dup), uložený PI = ponechaná platba; selhání → obsluha', async () => {
  const orig = globalThis.fetch
  globalThis.fetch = (() => Promise.resolve(new Response('{}'))) as typeof fetch
  try {
    const d = new FakeDb({ bookings: [{ id: REF, stripe_payment_intent_id: 'pi_b' }], debug_log: [] })
    const f = fakeStripe([P('pi_b', 2000)])
    const a = { piId: 'pi_b', table: 'bookings' as const, refId: REF, keepRef: 'pi_a', amountCzk: 15, via: 'test' }
    eq(await refundDuplicatePayment(d, f.stripe, a), 'refunded')
    eq(await refundDuplicatePayment(d, f.stripe, a), 'refunded')
    eq(f.refunds.length, 1); eq(f.refunds[0].o.idempotencyKey, 'mg-dup-pi_b'); eq((f.refunds[0].p.metadata as Row).mg_source, 'duplicate_payment')
    eq(d.rows('bookings')[0].stripe_payment_intent_id, 'pi_a')
    const bad = fakeStripe([P('pi_c', 2000)], true)
    eq(await refundDuplicatePayment(new FakeDb({ bookings: [], debug_log: [] }), bad.stripe, { ...a, piId: 'pi_c' }), 'staff')
  } finally { globalThis.fetch = orig }
})

// ── doplatek u zrušené rezervace: žádné oživení, vratka přímo ze Stripe ───────
Deno.test('prepareExtensionPayment: zrušená → closed beze změny; živá po vratce → paid; PI jen když chybí', async () => {
  const c = db({ status: 'cancelled', payment_status: 'refunded' })
  eq(await prepareExtensionPayment(c, 'b1', 'pi_e', null), 'closed')
  eq(row(c).status, 'cancelled'); eq(row(c).payment_status, 'refunded'); eq(row(c).stripe_payment_intent_id, null)
  const l = db({ payment_status: 'partial_refund', stripe_payment_intent_id: 'pi_orig' })
  eq(await prepareExtensionPayment(l, 'b1', 'pi_e', 'cs_1'), 'ok')
  eq(row(l).payment_status, 'paid'); eq(row(l).stripe_payment_intent_id, 'pi_orig')
})
Deno.test('handlePaidChangeFailure: zrušená rezervace → vratka přímo ze Stripe (mg-pcf), ne přes process-refund', async () => {
  const sent: string[] = []
  const orig = globalThis.fetch
  globalThis.fetch = ((u: string) => { sent.push(String(u).split('/functions/v1/')[1]); return Promise.resolve(new Response('{"success":true}')) }) as typeof fetch
  try {
    const f = fakeStripe([])
    const mode = await handlePaidChangeFailure(db({ status: 'cancelled' }), { bookingId: 'b1', payRef: 'pi_e', paidCzk: 300, code: 'change_failed',
      reason: 'booking_cancelled', via: 'test', stripe: (f.stripe as unknown as { refunds: never }) } as never)
    eq(mode, 'auto'); eq(f.refunds.length, 1); eq(f.refunds[0].o.idempotencyKey, 'mg-pcf-pi_e'); eq(f.refunds[0].p.amount, 30000)
    eq((f.refunds[0].p.metadata as Row).mg_source, 'unapplied_change'); eq(sent.includes('process-refund'), false)
  } finally { globalThis.fetch = orig }
})
