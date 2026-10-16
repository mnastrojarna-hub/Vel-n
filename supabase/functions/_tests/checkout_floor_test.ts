// ===== _tests/checkout_floor_test.ts =====
// fix:backend 2 (2026-10-16): jedna zaplatitelná Checkout Session (web), spodní mez ceny
// (price_outdated místo jiné částky, log-only u běžné platby), zdarma jen doložené.
import { settleStoredSession, settleMatchingSessions } from '../process-payment/checkout-guard.ts'
import { floorCheck, freeVerifiedByFloor } from '../process-payment/floor-check.ts'
import { refuse } from '../process-payment/refusals.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
const NOW = Date.UTC(2026, 9, 16, 12, 0, 0)
const S = (id: string, o: Row = {}) => ({ id, status: 'open', created: NOW / 1000 - 600, metadata: { booking_id: 'b1', type: 'extension' }, ...o })

function fake(sessions: Row[], o: { expireFails?: boolean; completeOnRetrieve?: boolean } = {}) {
  const expired: string[] = []
  const stripe = { checkout: { sessions: {
    retrieve: (id: string) => {
      const s = sessions.find((x) => x.id === id)
      if (!s) return Promise.reject(new Error('missing'))
      return Promise.resolve(o.completeOnRetrieve && expired.length === 0 && o.expireFails ? { ...s, status: 'complete' } : s)
    },
    expire: (id: string) => { if (o.expireFails) return Promise.reject(new Error('not open')); expired.push(id); return Promise.resolve({ id }) },
    list: (p: Row) => Promise.resolve({ data: sessions.filter((s) => s.status === p.status) }),
  } } }
  return { stripe: stripe as never, expired }
}

Deno.test('checkout guard: otevřenou předchozí session zruší, čerstvě zaplacenou odmítne', async () => {
  const a = fake([S('cs_1')])
  eq(await settleStoredSession(a.stripe, 'cs_1', NOW), { action: 'proceed', expired: ['cs_1'] }); eq(a.expired, ['cs_1'])
  const paid = fake([S('cs_2', { status: 'complete', payment_intent: { id: 'pi', latest_charge: { amount_refunded: 0, created: NOW / 1000 - 120 } } })])
  eq((await settleStoredSession(paid.stripe, 'cs_2', NOW)).action, 'refuse')
})
Deno.test('checkout guard: vrácená / stará (>60 min) / prošlá session → nová platba smí; žádné id → proceed', async () => {
  const refunded = fake([S('cs_r', { status: 'complete', payment_intent: { latest_charge: { amount_refunded: 1500, created: NOW / 1000 - 60 } } })])
  eq((await settleStoredSession(refunded.stripe, 'cs_r', NOW)).action, 'proceed')
  const old = fake([S('cs_o', { status: 'complete', payment_intent: { latest_charge: { amount_refunded: 0, created: NOW / 1000 - 7200 } } })])
  eq((await settleStoredSession(old.stripe, 'cs_o', NOW)).action, 'proceed')
  eq((await settleStoredSession(fake([S('cs_e', { status: 'expired' })]).stripe, 'cs_e', NOW)), { action: 'proceed', expired: [] })
  eq((await settleStoredSession(fake([]).stripe, null, NOW)).action, 'proceed')
  eq((await settleStoredSession(fake([]).stripe, 'pi_x', NOW)).action, 'proceed')
})
Deno.test('checkout guard: zrušení selže, protože ji zákazník právě dokončil → odmítnout', async () => {
  const f = fake([S('cs_1')], { expireFails: true, completeOnRetrieve: true })
  // první retrieve vrátí open (settleStoredSession), druhý po neúspěšném expire complete
  let n = 0
  const st = f.stripe as unknown as { checkout: { sessions: { retrieve: (id: string) => Promise<Row> } } }
  st.checkout.sessions.retrieve = () => Promise.resolve(n++ === 0 ? S('cs_1') : S('cs_1', { status: 'complete', created: NOW / 1000 - 30 }))
  eq((await settleStoredSession(f.stripe, 'cs_1', NOW)).action, 'refuse')
})
Deno.test('checkout guard (doplatek bez uloženého id): jen session téže rezervace a typu', async () => {
  const f = fake([S('cs_a'), S('cs_b', { metadata: { booking_id: 'b2', type: 'extension' } }), S('cs_c', { metadata: { booking_id: 'b1', type: 'booking' } })])
  eq(await settleMatchingSessions(f.stripe, { customerId: 'cus', refKey: 'booking_id', refId: 'b1', type: 'extension', nowMs: NOW }),
    { action: 'proceed', expired: ['cs_a'] })
  const done = fake([S('cs_d', { status: 'complete', created: NOW / 1000 - 300 })])
  eq((await settleMatchingSessions(done.stripe, { customerId: null, refKey: 'booking_id', refId: 'b1', type: 'extension', nowMs: NOW })).action, 'refuse')
})

// ── spodní mez ceny ───────────────────────────────────────────────────────────
function priced(over: Row = {}, vouchers: Row[] = [], bd: Row[] = []) {
  const d = new FakeDb({
    bookings: [{ id: 'b1', moto_id: 'm1', start_date: '2026-11-10', end_date: '2026-11-14', total_price: 0, card_rounding: 0, extras_price: 0,
      delivery_fee: 0, loyalty_discount_amount: 0, late_pickup_discount_amount: 0, pickup_time: '10:00', discount_code: null, ...over }],
    vouchers, promo_codes: [], booking_discounts: bd, debug_log: [],
  })
  d.rpcs._moto_dayprice_sum = () => ({ data: 5000, error: null })
  d.rpcs._late_pickup_discount = () => ({ data: 0, error: null })
  return d
}
const V = (id: string, amount: number) => ({ id, code: id.toUpperCase(), amount, status: 'active', valid_until: '2027-01-01' })
Deno.test('floorCheck: dorovnání / odpuštění nesedí s ceníkem → outdated (žádná jiná částka); běžná platba jen log', async () => {
  const d = priced({ total_price: 10 })
  eq(await floorCheck(d, d.rows('bookings')[0], { due: 10, kind: 'round', type: 'booking' }), 'outdated')
  eq(await floorCheck(d, d.rows('bookings')[0], { due: 10, kind: 'ok', type: 'booking' }), 'ok')
  eq(d.rows('debug_log').map((r) => r.action), ['card_minimum_price_unverified', 'booking_price_below_floor'])
  eq(await floorCheck(d, d.rows('bookings')[0], { due: 10, kind: 'round', type: 'sos' }), 'ok', 'SOS cenu určuje obsluha — jen log')
  Deno.env.set('PP_FLOOR_ENFORCE', '1')
  try { eq(await floorCheck(d, d.rows('bookings')[0], { due: 10, kind: 'ok', type: 'booking' }), 'outdated') }
  finally { Deno.env.delete('PP_FLOOR_ENFORCE') }
  const ok = priced({ total_price: 10 }, [V('v1', 4990)], [{ booking_id: 'b1', kind: 'voucher', voucher_id: 'v1' }])
  eq(await floorCheck(ok, ok.rows('bookings')[0], { due: 10, kind: 'round', type: 'booking' }), 'ok')
  const down = priced(); down.rpcs._moto_dayprice_sum = () => ({ data: null, error: { message: 'x' } })
  eq(await floorCheck(down, down.rows('bookings')[0], { due: 10, kind: 'round', type: 'booking' }), 'unavailable')
  eq(await floorCheck(down, down.rows('bookings')[0], { due: 3000, kind: 'ok', type: 'booking' }), 'ok')
})
Deno.test('zdarma: víc poukazů pokryje cenu → ano; zastaralé odpuštění po změně motorky / termínu → ne', async () => {
  const two = priced({}, [V('v1', 3000), V('v2', 2000)], [{ booking_id: 'b1', kind: 'voucher', voucher_id: 'v1' }, { booking_id: 'b1', kind: 'voucher', voucher_id: 'v2' }])
  eq(await freeVerifiedByFloor(two, two.rows('bookings')[0]), true)
  const stale = priced({ card_rounding: -0.6 }) // dřív odpuštěno 0,60 Kč, pak jiný termín bez slev
  eq(await freeVerifiedByFloor(stale, stale.rows('bookings')[0]), false)
  const waived = priced({ card_rounding: -0.6 }, [V('v1', 4998.6)], [{ booking_id: 'b1', kind: 'voucher', voucher_id: 'v1' }])
  eq(await freeVerifiedByFloor(waived, waived.rows('bookings')[0]), true, 'odpuštěný zbytek 1,40 s tolerancí 1 Kč')
  eq(await freeVerifiedByFloor(waived, { ...waived.rows('bookings')[0], total_price: 5 }), false)
})
Deno.test('price_outdated: český text bez kontaktu, nic nestrženo, žádná částka k zaplacení', async () => {
  const r = await refuse(409, 'price_outdated', { booking_id: 'b1' }).json()
  eq(r.code, 'price_outdated'); eq('server_total' in r, false)
  if (!/Nic jsme nestrhli/.test(r.error) || /@|\+420|info@|telefon/i.test(r.error)) throw new Error(r.error)
})
Deno.test('checkout guard (doplatek): dokončená session už ZAPSANÉ úpravy další úpravu neblokuje', async () => {
  const done = fake([S('cs_d', { status: 'complete', created: NOW / 1000 - 300, payment_intent: { id: 'pi_d', metadata: {} } })])
  const g = await settleMatchingSessions(done.stripe, { customerId: 'cus', refKey: 'booking_id', refId: 'b1', type: 'extension', nowMs: NOW,
    settled: (piId) => Promise.resolve(piId === 'pi_d') })
  eq(g.action, 'proceed')
  const pending = await settleMatchingSessions(done.stripe, { customerId: 'cus', refKey: 'booking_id', refId: 'b1', type: 'extension', nowMs: NOW,
    settled: () => Promise.resolve(false) })
  eq(pending.action, 'refuse')
})
Deno.test('zdarma: uznané dosavadní kontrolou, ale spodní mez nesedí → uznáno + záznam ke kalibraci', async () => {
  const d = priced()
  eq(await freeVerifiedByFloor(d, d.rows('bookings')[0], true), true)
  eq(d.rows('debug_log').map((r) => r.action), ['free_booking_floor_mismatch'])
})
Deno.test('D3: obnovená rezervace (restored_by_source app) — spodní mez VYNUCENA i u běžné platby', async () => {
  // draft za 3000 Kč z mimosezóny, dnešní ceník 5000 Kč → zaplatit starou cenu nejde
  const r = priced({ total_price: 3000, restored_by_source: 'app' })
  eq(await floorCheck(r, r.rows('bookings')[0], { due: 3000, kind: 'ok', type: 'booking' }), 'outdated')
  eq(r.rows('debug_log').map((x) => x.action), ['restored_price_below_floor'])
  eq((r.rows('debug_log')[0].request_data as Row).enforced, true)
  // aktuální cena (± 1 Kč) projde; neobnovená stará cena jen log (beze změny)
  const fine = priced({ total_price: 4999.5, restored_by_source: 'app' })
  eq(await floorCheck(fine, fine.rows('bookings')[0], { due: 4999.5, kind: 'ok', type: 'booking' }), 'ok')
  const plain = priced({ total_price: 3000, restored_by_source: null })
  eq(await floorCheck(plain, plain.rows('bookings')[0], { due: 3000, kind: 'ok', type: 'booking' }), 'ok')
  // obnovená ve Velínu (NULL) = beze změny; ceník nedostupný u obnovené → unavailable (nic se nestrhne)
  const down = priced({ total_price: 3000, restored_by_source: 'app' })
  down.rpcs._moto_dayprice_sum = () => ({ data: null, error: { message: 'x' } })
  eq(await floorCheck(down, down.rows('bookings')[0], { due: 3000, kind: 'ok', type: 'booking' }), 'unavailable')
})
Deno.test('D3: odmítnuté obnovení kvůli ceníku → booking_cancelled s vlastním textem bez kontaktu', async () => {
  const { cancelledReasonKey, CS } = await import('../process-payment/refusals.ts')
  eq(cancelledReasonKey('price_changed'), 'booking_cancelled_price')
  const r = await refuse(409, 'booking_cancelled', { reason: 'price_changed' }, CS[cancelledReasonKey('price_changed')]).json()
  eq(r.code, 'booking_cancelled')
  if (!/Nic jsme nestrhli/.test(r.error) || !/novou rezervaci/.test(r.error) || /@|\+420|info@|telefon/i.test(r.error)) throw new Error(r.error)
})
