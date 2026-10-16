// ===== _tests/extension_apply_test.ts =====
// D6 (2026-10-16): dokončení zaplacené změny (webhook i complete_extension) —
// idempotence, F1 (žádný dvojí doplatek), dorovnání D1, souběh, třídění chyb, výměna.
import { applyPaidExtension, placeFingerprint } from '../_shared/extension-apply.ts'
import { handlePaidChangeFailure } from '../_shared/paid-change-failure.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}

type Row = Record<string, unknown>
function booking(over: Row = {}): Row {
  return {
    id: 'b1', user_id: 'u1', status: 'reserved', payment_status: 'paid', moto_id: 'm1',
    start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', pickup_time: '10:00:00',
    total_price: 3000, card_rounding: 0, delivery_fee: 0, pickup_method: 'branch', pickup_address: null,
    return_method: 'branch', return_address: null, late_pickup_discount_amount: 0, modification_history: [],
    original_start_date: null, updated_at: '2026-10-16T11:00:00.000Z', ...over,
  }
}
function db(over: Row = {}) {
  const d = new FakeDb({ bookings: [booking(over)], debug_log: [] })
  d.rpcs._late_pickup_discount = () => ({ data: 0, error: null })
  return d
}
// prodloužení o 1 den (app formát) naceněné proti stavu 3000
function extend(total: number) {
  const b = booking()
  return JSON.stringify({ start_date: '2026-11-10', end_date: '2026-11-13', total_price: total,
    _base: { s: '2026-11-10', e: '2026-11-12', t: '10:00', p: 3000 } }) + '|' + JSON.stringify({ f: placeFingerprint(b) })
}
const args = (chgSrv: string, o: Row = {}) => {
  const [chg, srv] = chgSrv.split('|')
  return { bookingId: 'b1', chg, srv, paidCzk: 1000, payRef: 'pi_1', rounding: 0, ...o } as never
}
const row = (d: FakeDb) => d.rows('bookings')[0]
const hist = (d: FakeDb) => row(d).modification_history as Row[]

Deno.test('apply: čerstvá změna → applied, cena absolutně, historie s payment_ref', async () => {
  const d = db()
  const r = await applyPaidExtension(d, args(extend(4000)))
  eq(r.state, 'applied'); eq(row(d).total_price, 4000); eq(String(row(d).end_date).slice(0, 10), '2026-11-13')
  eq(hist(d).length, 1); eq(hist(d)[0].payment_ref, 'pi_1'); eq(hist(d)[0].price_diff, 1000)
})
Deno.test('apply: opakované doručení téže platby → already_applied, nic se nepřičte', async () => {
  const d = db()
  await applyPaidExtension(d, args(extend(4000)))
  const r = await applyPaidExtension(d, args(extend(4000)))
  eq(r.state, 'already_applied'); eq(row(d).total_price, 4000); eq(hist(d).length, 1)
})
Deno.test('apply F1: změnu už zapsal klient (appka ≤ 4.1.3) → žádný dvojí doplatek', async () => {
  const d = db({ end_date: '2026-11-13T00:00:00+00:00', total_price: 4000 })
  const r = await applyPaidExtension(d, args(extend(4000)))
  eq(r.state, 'applied'); eq(row(d).total_price, 4000, 'dřív 5000 (zastaralý základ + doplatek)')
  eq(hist(d).length, 1); eq(hist(d)[0].stale_baseline, undefined)
})
Deno.test('apply: skutečně zastaralý základ (jiná změna mezitím) → cena + zaplaceno', async () => {
  const d = db({ total_price: 3200 }) // mezitím jiná úprava (+200), termín beze změny
  const r = await applyPaidExtension(d, args(extend(4000)))
  eq(r.state, 'applied'); eq(row(d).total_price, 4200); eq(hist(d)[0].stale_baseline, true)
})
Deno.test('apply D1: doplatek 7 Kč zaplacený 15 Kč → cena +15, card_rounding +8, historie', async () => {
  const d = db()
  const r = await applyPaidExtension(d, args(extend(3007), { paidCzk: 15, rounding: 8 }))
  eq(r.state, 'applied'); eq(row(d).total_price, 3015); eq(row(d).card_rounding, 8)
  eq(hist(d)[0].price_diff, 15); eq(hist(d)[0].card_rounding, 8)
})
Deno.test('apply D1: odpuštěný doplatek 0,60 Kč → cena beze změny, card_rounding −0,6', async () => {
  const d = db()
  const r = await applyPaidExtension(d, args(extend(3000.6), { paidCzk: 0, rounding: -0.6, payRef: 'waive:x' }))
  eq(r.state, 'applied'); eq(row(d).total_price, 3000); eq(row(d).card_rounding, -0.6); eq(hist(d)[0].price_diff, 0)
})
Deno.test('apply D1: dorovnání bez sloupce card_rounding (SQL nenasazené) → retry rounding_unavailable', async () => {
  const d = db(); d.missingCols.add('card_rounding')
  const r = await applyPaidExtension(d, args(extend(3007), { paidCzk: 15, rounding: 8 }))
  eq(r.state, 'retry'); eq((r as { code: string }).code, 'rounding_unavailable'); eq(row(d).total_price, 3000)
})
Deno.test('apply: souběh (webhook ↔ complete_extension) — prohraný zámek → načíst znovu → already_applied', async () => {
  const d = db()
  let first = true
  d.beforeUpdate = () => {
    if (!first) return
    first = false
    // druhý dokončovatel stihl zapsat tutéž platbu dřív
    Object.assign(row(d), { end_date: '2026-11-13T00:00:00+00:00', total_price: 4000, updated_at: '2026-10-16T11:59:59.000Z',
      modification_history: [{ payment_ref: 'pi_1', price_diff: 1000 }] })
  }
  const r = await applyPaidExtension(d, args(extend(4000)))
  eq(r.state, 'already_applied'); eq(row(d).total_price, 4000); eq(hist(d).length, 1)
})
Deno.test('apply: odmítnutí triggerem (P0001 překryv) → failed; výpadek → retry', async () => {
  const d1 = db(); d1.failUpdate = () => ({ code: 'P0001', message: 'Překrývající se rezervace' })
  eq((await applyPaidExtension(d1, args(extend(4000)))).state, 'failed')
  const d2 = db(); d2.failUpdate = () => ({ message: 'fetch failed' })
  eq((await applyPaidExtension(d2, args(extend(4000)))).state, 'retry')
})
Deno.test('apply: bez payloadu / nečitelný payload → no_payload', async () => {
  eq((await applyPaidExtension(db(), { bookingId: 'b1', chg: null, paidCzk: 1, payRef: 'x' })).state, 'no_payload')
  eq((await applyPaidExtension(db(), { bookingId: 'b1', chg: '{oops', paidCzk: 1, payRef: 'x' })).state, 'no_payload')
})

// ── výměna motorky ─────────────────────────────────────────────────────────
const SWAP = JSON.stringify({ _swap: { m: 'm2', d: '2026-11-11', t: null } })
const SINCE = '2026-10-16T10:00:00.000Z'
const swapArgs = (o: Row = {}) => ({ bookingId: 'b1', chg: SWAP, paidCzk: 15, payRef: 'pi_s', rounding: 0, since: SINCE, ...o }) as never
const rpcArgs = (d: FakeDb) => d.calls.find((c) => c.fn === 'split_booking_moto_swap')?.data as Row | undefined

Deno.test('swap: úspěch → applied; RPC dostane zaplacenou částku a značku platby (rev.12)', async () => {
  const d = db()
  d.rpcs.split_booking_moto_swap = () => ({ data: { success: true, new_booking_id: 'b2' }, error: null })
  const r = await applyPaidExtension(d, swapArgs())
  eq(r.state, 'applied'); eq((r as { newBookingId: string }).newBookingId, 'b2')
  eq(rpcArgs(d)?.p_paid, 15); eq(rpcArgs(d)?.p_payment_ref, 'pi_s'); eq('p_card_rounding' in (rpcArgs(d) || {}), false)
})
Deno.test('swap: rev.12 vrátí already_applied (značka platby) → already_applied', async () => {
  const d = db()
  d.rpcs.split_booking_moto_swap = () => ({ data: { success: true, already_applied: true, new_booking_id: 'b1' }, error: null })
  eq((await applyPaidExtension(d, swapArgs())).state, 'already_applied')
})
Deno.test('swap: rev.12 nenasazená — bez dorovnání 6parametrové volání, s dorovnáním retry rounding_unavailable', async () => {
  const d = db()
  d.rpcs.split_booking_moto_swap = (a) => ('p_paid' in a || 'p_payment_ref' in a)
    ? { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } }
    : { data: { success: true, new_booking_id: 'b1' }, error: null }
  eq((await applyPaidExtension(d, swapArgs())).state, 'applied')
  const d2 = db() // RPC neexistuje v nové signatuře, platba s dorovnáním
  d2.rpcs.split_booking_moto_swap = d.rpcs.split_booking_moto_swap
  const r2 = await applyPaidExtension(d2, swapArgs({ rounding: 7.5 }))
  eq(r2.state, 'retry'); eq((r2 as { code: string }).code, 'rounding_unavailable')
})
Deno.test('swap BLOCKER: přehrání staré platby po bezplatné výměně zpět → already_applied, RPC se nevolá', async () => {
  // zaplacená výměna m1→m2 (pi_s) proběhla, pak bezplatná výměna zpět m2→m1
  const d = db({ moto_id: 'm1', modification_history: [
    { at: '2026-10-16T10:05:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2', payment_ref: 'pi_s', price_diff: 15 },
    { at: '2026-10-16T10:30:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm1', price_diff: 0 },
  ] })
  let called = 0
  d.rpcs.split_booking_moto_swap = () => { called++; return { data: { success: true, new_booking_id: 'b1' }, error: null } }
  eq((await applyPaidExtension(d, swapArgs())).state, 'already_applied'); eq(called, 0); eq(row(d).moto_id, 'm1')
})
Deno.test('swap: replace provedený od vytvoření platby (klientský commit, bez značky) → already_applied bez RPC', async () => {
  const d = db({ moto_id: 'm2', modification_history: [{ at: '2026-10-16T10:01:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2' }] })
  let called = 0
  d.rpcs.split_booking_moto_swap = () => { called++; return { data: { success: false, error: 'invalid_new_moto' }, error: null } }
  eq((await applyPaidExtension(d, swapArgs())).state, 'already_applied'); eq(called, 0)
})
Deno.test('swap D1: web po návratu výměnu provedl sám (bez dorovnání) → webhook dopíše dorovnání jednou', async () => {
  const d = db({ moto_id: 'm2', total_price: 3007, modification_history: [{ at: '2026-10-16T10:01:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2', price_diff: 7 }] })
  let called = 0
  d.rpcs.split_booking_moto_swap = () => { called++; return { data: null, error: null } }
  eq((await applyPaidExtension(d, swapArgs({ rounding: 8 }))).state, 'already_applied'); eq(called, 0)
  eq(row(d).total_price, 3015); eq(row(d).card_rounding, 8); eq(hist(d).at(-1)?.payment_ref, 'pi_s')
  eq((await applyPaidExtension(d, swapArgs({ rounding: 8 }))).state, 'already_applied'); eq(row(d).total_price, 3015)
})
Deno.test('swap D1: split zapsaný touto platbou (rev.12, B už má dorovnání) → opakování nic nepřičte', async () => {
  const d = db({ modification_history: [{ at: '2026-10-16T10:05:00+00:00', type: 'moto_swap_shorten', new_moto_id: 'm2', payment_ref: 'pi_s' }] })
  d.rows('bookings').push(booking({ id: 'b2', moto_id: 'm2', start_date: '2026-11-11T00:00:00+00:00', continues_booking_id: 'b1',
    total_price: 2015, card_rounding: 9, created_at: '2026-10-16T10:05:00+00:00' }))
  const r = await applyPaidExtension(d, swapArgs({ rounding: 9 }))
  eq(r.state, 'already_applied'); eq((r as { newBookingId: string }).newBookingId, 'b2')
  eq(d.rows('bookings')[1].total_price, 2015); eq(d.rows('bookings')[1].card_rounding, 9)
})
Deno.test('swap: rezervace už na nové motorce BEZ důkazu z této platby → failed manual (obsluha, žádná automatická vratka)', async () => {
  const d = db({ moto_id: 'm2', modification_history: [{ at: '2026-10-15T09:00:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2' }] })
  d.rpcs.split_booking_moto_swap = () => ({ data: { success: false, error: 'invalid_new_moto' }, error: null })
  const r = await applyPaidExtension(d, swapArgs())
  eq(r.state, 'failed'); eq((r as { manual?: boolean }).manual, true)
})
Deno.test('swap: split hotový (B od platby, i když B je mezitím ZRUŠENÁ) → already_applied, žádná vratka', async () => {
  for (const status of ['reserved', 'cancelled']) {
    const d = db()
    d.rows('bookings').push(booking({ id: 'b2', moto_id: 'm2', start_date: '2026-11-11T00:00:00+00:00', continues_booking_id: 'b1',
      status, created_at: '2026-10-16T10:02:00.000000+00:00' }))
    d.rpcs.split_booking_moto_swap = () => ({ data: { success: false, error: 'swap_date_out_of_range' }, error: null })
    const r = await applyPaidExtension(d, swapArgs())
    eq(r.state, 'already_applied', status); eq((r as { newBookingId: string }).newBookingId, 'b2')
  }
})
Deno.test('swap: navazující B starší než platba není důkaz → RPC rozhodne', async () => {
  const d = db()
  d.rows('bookings').push(booking({ id: 'b2', moto_id: 'm2', start_date: '2026-11-11T00:00:00+00:00', continues_booking_id: 'b1',
    created_at: '2026-10-01T10:00:00+00:00' }))
  d.rpcs.split_booking_moto_swap = () => ({ data: { success: false, error: 'already_split' }, error: null })
  const r = await applyPaidExtension(d, swapArgs())
  eq(r.state, 'failed'); eq((r as { manual?: boolean }).manual, true)
})
Deno.test('swap: motorku mezitím obsadil jiný zákazník → failed; chyba RPC → retry', async () => {
  const d = db()
  d.rpcs.split_booking_moto_swap = () => ({ data: { success: false, error: 'new_moto_unavailable' }, error: null })
  const r = await applyPaidExtension(d, swapArgs())
  eq(r.state, 'failed'); eq((r as { reason: string }).reason, 'new_moto_unavailable'); eq((r as { manual?: boolean }).manual, undefined)
  const d2 = db()
  d2.rpcs.split_booking_moto_swap = () => ({ data: null, error: { code: '57014', message: 'statement timeout' } })
  eq((await applyPaidExtension(d2, swapArgs())).state, 'retry')
})
Deno.test('swap odpuštění: stejné klepnutí (značka waive:) → already_applied; jiné klepnutí stejné výměny → RPC', async () => {
  const d = db({ modification_history: [{ at: '2026-10-16T10:05:00+00:00', type: 'moto_swap_replace', new_moto_id: 'm2', payment_ref: 'waive:att-1:x' }] })
  let called = 0
  d.rpcs.split_booking_moto_swap = () => { called++; return { data: { success: true, new_booking_id: 'b1' }, error: null } }
  eq((await applyPaidExtension(d, swapArgs({ payRef: 'waive:att-1:x', paidCzk: 0, rounding: -0.6, since: null }))).state, 'already_applied')
  eq(called, 0)
  eq((await applyPaidExtension(d, swapArgs({ payRef: 'waive:att-2:x', paidCzk: 0, rounding: -0.6, since: null }))).state, 'applied')
  eq(called, 1)
})

// (výbava s dorovnáním → gear_rounding_test.ts)

// ── trvalé selhání: vratka jen jednou ─────────────────────────────────────────
Deno.test('paid change failure: automatická vratka + upozornění jen jednou na platbu', async () => {
  const d = new FakeDb({ bookings: [booking()], debug_log: [] })
  const sent: string[] = []
  const orig = globalThis.fetch
  globalThis.fetch = ((url: string) => {
    sent.push(String(url).split('/functions/v1/')[1])
    return Promise.resolve(new Response(JSON.stringify({ success: true }), { status: 200 }))
  }) as typeof fetch
  try {
    const a = { bookingId: 'b1', payRef: 'pi_x', paidCzk: 15, code: 'change_failed', reason: 'new_moto_unavailable', via: 'test' }
    eq(await handlePaidChangeFailure(d, a), 'auto')
    eq(await handlePaidChangeFailure(d, a), 'auto') // druhý dokončovatel: jen převezme výsledek
    eq(sent.filter((s) => s === 'process-refund').length, 1)
    eq(sent.filter((s) => s === 'send-email').length, 1)
    eq(row(d).stripe_payment_intent_id, 'pi_x') // vratka z TÉTO platby
    eq(d.rows('debug_log').filter((r) => r.action === 'paid_change_failed').length, 1)
  } finally { globalThis.fetch = orig }
})

