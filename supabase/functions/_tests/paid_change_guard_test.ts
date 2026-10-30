// ===== _tests/paid_change_guard_test.ts =====
// Oprava 2026-10-16 (fix:backend): kdy smí server zapsat zaplacenou změnu (stará / vrácená /
// vyhodnocená platba ne), dorovnání až po zaplacení (webhook CAS), ověření zbytku rezervace
// před odpuštěním / dorovnáním, serverové přecenění app změny.
import { paidChangeEligibility, PREVIOUS_MAX_AGE_H, QUEUE_MAX_AGE_H } from '../_shared/paid-change-guard.ts'
import { applyChargeRounding } from '../_shared/charge-rounding.ts'
import { verifiedBookingFloor } from '../process-payment/due-verify.ts'
import { appChangeParams } from '../process-payment/app-change-price.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
const NOW = Date.UTC(2026, 9, 16, 12, 0, 0)
const pi = (o: Row = {}) => ({ id: 'pi_1', created: NOW / 1000 - 3600, metadata: { type: 'extension', booking_id: 'b1', chg_hash: 'abc' },
  latest_charge: { amount_refunded: 0 }, ...o }) as never
const db = (hist: Row[] = [], log: Row[] = []) => new FakeDb({ bookings: [{ id: 'b1', modification_history: hist }], debug_log: log })
const E = (d: FakeDb, p: unknown, o: Row = {}) =>
  paidChangeEligibility(d, p as never, { bookingId: 'b1', requireNewCode: true, maxAgeH: PREVIOUS_MAX_AGE_H, nowMs: NOW, ...o } as never)

Deno.test('eligibility: nová nevyřízená platba → ok', async () => {
  eq(await E(db(), pi()), { ok: true })
})
Deno.test('eligibility: značka applied_at / payment_ref v historii → applied (nikdy znovu nezapsat)', async () => {
  eq((await E(db(), pi({ metadata: { type: 'extension', booking_id: 'b1', chg_hash: 'a', applied_at: 'x' } }))).ok, false)
  const r = await E(db([{ payment_ref: 'pi_1' }]), pi())
  eq(r, { ok: false, kind: 'applied' })
})
Deno.test('eligibility: už vyhodnocené selhání (paid_change_failed) → failed s výsledkem vratky', async () => {
  const d = db([], [{ id: 'l1', action: 'paid_change_failed', created_at: '2026-10-16T11:00:00Z',
    request_data: { payment_ref: 'pi_1', reason: 'new_moto_unavailable' }, response_data: { refund: 'auto' } }])
  eq(await E(d, pi()), { ok: false, kind: 'failed', reason: 'new_moto_unavailable', refund: 'auto' })
})
Deno.test('eligibility: z platby se vracelo → refunded (i přes stripe.charges, když latest_charge je id)', async () => {
  eq(await E(db(), pi({ latest_charge: { amount_refunded: 1500 } })), { ok: false, kind: 'refunded' })
  const stripe = { charges: { retrieve: () => Promise.resolve({ amount_refunded: 100 }) } }
  eq(await E(db(), pi({ latest_charge: 'ch_1' }), { stripe }), { ok: false, kind: 'refunded' })
})
Deno.test('eligibility: platba z doby před nasazením / mimo lhůtu → stale; webhook (bez požadavku) ji zapisuje', async () => {
  const legacy = pi({ metadata: { type: 'extension', booking_id: 'b1' } })
  eq(await E(db(), legacy), { ok: false, kind: 'stale', why: 'legacy' })
  eq(await E(db(), legacy, { requireNewCode: false, maxAgeH: null }), { ok: true })
  eq(await E(db(), pi({ created: NOW / 1000 - 80 * 3600 })), { ok: false, kind: 'stale', why: 'too_old' })
  eq(await E(db(), pi({ created: NOW / 1000 - 80 * 3600 }), { maxAgeH: QUEUE_MAX_AGE_H }), { ok: true })
})

// ── dorovnání až po zaplacení (webhook) ─────────────────────────────────────
const md = { due: '7', card_rounding: '8' }
Deno.test('charge rounding: CAS due → due + r jednou; opakovaná událost → already', async () => {
  const d = new FakeDb({ bookings: [{ id: 'b1', total_price: 7, card_rounding: 0, payment_status: 'unpaid' }], debug_log: [] })
  eq(await applyChargeRounding(d, { table: 'bookings', id: 'b1', md, payRef: 'pi_1' }), 'applied')
  eq(d.rows('bookings')[0].total_price, 15); eq(d.rows('bookings')[0].card_rounding, 8)
  eq(await applyChargeRounding(d, { table: 'bookings', id: 'b1', md, payRef: 'pi_1' }), 'already')
  eq(d.rows('bookings')[0].card_rounding, 8)
})
Deno.test('charge rounding: cena se mezitím změnila (upsell, přecenění) → mismatch, nic se nepřičte', async () => {
  const d = new FakeDb({ bookings: [{ id: 'b1', total_price: 305, card_rounding: 0, payment_status: 'unpaid' }], debug_log: [] })
  eq(await applyChargeRounding(d, { table: 'bookings', id: 'b1', md, payRef: 'pi_1' }), 'mismatch')
  eq(d.rows('bookings')[0].total_price, 305)
  eq(d.rows('debug_log').some((r) => r.action === 'card_rounding_mismatch'), true)
})
Deno.test('charge rounding: bez metadat → none; e-shop; nenasazené SQL → unavailable', async () => {
  const d = new FakeDb({ shop_orders: [{ id: 'o1', total: 9, card_rounding: 0, payment_status: 'pending' }], debug_log: [] })
  eq(await applyChargeRounding(d, { table: 'shop_orders', id: 'o1', md: {}, payRef: 'pi_1' }), 'none')
  eq(await applyChargeRounding(d, { table: 'shop_orders', id: 'o1', md: { due: '9', card_rounding: '6' }, payRef: 'pi_1' }), 'applied')
  eq(d.rows('shop_orders')[0].total, 15)
  const d2 = new FakeDb({ bookings: [{ id: 'b1', total_price: 15.4, payment_status: 'unpaid' }], debug_log: [] })
  d2.missingCols.add('card_rounding')
  eq(await applyChargeRounding(d2, { table: 'bookings', id: 'b1', md: { due: '15.4', card_rounding: '-0.4' }, payRef: 'pi_1' }), 'unavailable')
})

// ── ověření zbytku rezervace před odpuštěním / dorovnáním ──────────────────
function priced(over: Row = {}, vouchers: Row[] = [], promos: Row[] = [], bd: Row[] = []) {
  const d = new FakeDb({
    bookings: [{ id: 'b1', moto_id: 'm1', start_date: '2026-11-10', end_date: '2026-11-14', total_price: 0.4, extras_price: 0,
      delivery_fee: 0, loyalty_discount_amount: 0, late_pickup_discount_amount: 0, pickup_time: '10:00', discount_code: null, ...over }],
    vouchers, promo_codes: promos, booking_discounts: bd,
  })
  d.rpcs._moto_dayprice_sum = () => ({ data: 5000, error: null }) // 5 dní × 1000
  d.rpcs._late_pickup_discount = () => ({ data: 500, error: null })
  return d
}
Deno.test('due-verify: podvržená cena 0,40 Kč za 5 dní bez slev → spodní mez 5000 (odpuštění odmítnuto)', async () => {
  const d = priced()
  eq(await verifiedBookingFloor(d, d.rows('bookings')[0]), 5000)
})
Deno.test('due-verify: poukaz 4999,60 pokrývá skoro vše → zbytek 0,40 doložitelný', async () => {
  const d = priced({}, [{ id: 'v1', code: 'V1', amount: 4999.6, status: 'active', valid_until: '2027-01-01' }], [],
    [{ booking_id: 'b1', kind: 'voucher', voucher_id: 'v1' }])
  eq(await verifiedBookingFloor(d, d.rows('bookings')[0]), 0.4)
})
Deno.test('due-verify: poukaz použitý jinde se nepočítá; % kód z ceny; věrnost max 20 %; late max dle pravidla', async () => {
  const used = priced({}, [{ id: 'v1', amount: 4999.6, status: 'redeemed', booking_id: 'other', valid_until: '2027-01-01' }], [],
    [{ booking_id: 'b1', kind: 'voucher', voucher_id: 'v1' }])
  eq(await verifiedBookingFloor(used, used.rows('bookings')[0]), 5000)
  const pct = priced({ promo_code_id: 'p1' }, [], [{ id: 'p1', type: 'percent', value: 100, active: true }])
  eq(await verifiedBookingFloor(pct, pct.rows('bookings')[0]), 0)
  const loy = priced({ loyalty_discount_amount: 4000, late_pickup_discount_amount: 900 })
  eq(await verifiedBookingFloor(loy, loy.rows('bookings')[0]), 5000 - 1000 - 500)
})
Deno.test('due-verify: výpadek ceníku → null (ověření neproběhlo, nic neodpouštět)', async () => {
  const d = priced()
  d.rpcs._moto_dayprice_sum = () => ({ data: null, error: { message: 'timeout' } })
  eq(await verifiedBookingFloor(d, d.rows('bookings')[0]), null)
})

// ── app formát → dry-run apply_booking_changes ─────────────────────────────
Deno.test('app změna: termín / motorka / čas → parametry dry-runu; místo, výbava, slevy beze změny jen', () => {
  const cur = { start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', moto_id: 'm1', pickup_time: '10:00:00',
    delivery_fee: 0, extras_price: 300, discount_amount: 0, loyalty_discount_amount: 0, pickup_method: 'branch', return_method: 'branch' }
  eq(appChangeParams({ start_date: '2026-11-10', end_date: '2026-11-13', total_price: 4000, extras_price: 300, delivery_fee: 0,
    _base: { p: 3000 }, return_time: '18:00', late_pickup_discount_amount: 0 }, cur), { p_new_end: '2026-11-13' })
  eq(appChangeParams({ moto_id: 'm2', pickup_time: '13:00' }, cur), { p_new_moto_id: 'm2', p_new_pickup_time: '13:00' })
  eq(appChangeParams({ end_date: '2026-11-13', extras_price: 500 }, cur), null) // výbava se mění → nejde ocenit
  eq(appChangeParams({ end_date: '2026-11-13', pickup_method: 'delivery' }, cur), null)
  eq(appChangeParams({ end_date: '2026-11-13', something_new: 1 }, cur), null) // neznámý klíč → neodpouštět
  eq(appChangeParams({ end_date: '2026-11-12', return_time: '17:00' }, cur), null) // nic oceněného se nemění
})
