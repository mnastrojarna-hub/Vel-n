// ===== _tests/paid_change_refund_test.ts =====
// fix 2026-10-16 (odpověď majitele 1 + 3): nezapsaná zaplacená výměna se vrátí jednou
// a rezervace zůstane beze změny; pozdější storno / vratka obsluhy pak vrací z PŮVODNÍ
// platby (uložená platba = vrácený doplatek → jiná platba téže rezervace), zbytek z dalších
// plateb (vč. webových doplatků z historie) idempotentně podle hlavní vratky.
import { handlePaidChangeFailure } from '../_shared/paid-change-failure.ts'
import { failureRow } from '../_shared/paid-change-guard.ts'
import { otherRefundableIntents } from '../_shared/booking-intents.ts'
import { pickMainIntent, refundRemainder, refundedStatus } from '../process-refund/other-intents.ts'
import { failedText } from '../process-payment/complete-extension.ts'
import { CS } from '../process-payment/refusals.ts'
import { roundingLabel, editLineLabel } from '../process-payment/checkout-labels.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
const BID = '11111111-2222-4333-8444-555555555555'
const bk = (o: Row = {}): Row => ({ id: BID, user_id: 'u1', status: 'reserved', payment_status: 'paid', total_price: 3015,
  modification_history: [], stripe_payment_intent_id: 'pi_orig', ...o })
type Pi = { id: string; status: string; amount_received: number; created: number; metadata: Record<string, string> }
const pi = (id: string, h: number, created: number, md: Record<string, string> = { booking_id: BID, type: 'booking' }): Pi =>
  ({ id, status: 'succeeded', amount_received: h, created, metadata: md })

/** Stripe: vratky drží zbývající částku na PI, stejný idempotency klíč = stejná vratka. */
function fakeStripe(intents: Pi[], sessions: Record<string, Row> = {}) {
  const refunds: Record<string, Array<{ id: string; amount: number; status: string; metadata: Row }>> = {}
  const created: Array<{ p: Row; key: string }> = []
  const byKey = new Map<string, { id: string; amount: number; status: string }>()
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
        const r = { id: `re_${created.length + 1}`, amount: amt, status: 'succeeded', metadata: (p.metadata || {}) as Row }
        ;(refunds[id] ||= []).push(r); created.push({ p, key }); if (key) byKey.set(key, r)
        return Promise.resolve(r)
      },
    },
    checkout: { sessions: { retrieve: (id: string) => sessions[id] ? Promise.resolve(sessions[id]) : Promise.reject(new Error('missing')) } },
  }
  return { stripe, created, refunds, left }
}
async function withFetch<T>(fn: () => Promise<T>): Promise<T> {
  const orig = globalThis.fetch
  globalThis.fetch = (() => Promise.resolve(new Response('{}'))) as typeof fetch
  try { return await fn() } finally { globalThis.fetch = orig }
}

Deno.test('BLOCKER: výměna nezapsaná (motorka obsazená) → doplatek vrácen jednou, uložená platba zpět na původní; storno pak vrací z původní', async () => {
  // appka: process-payment uložil doplatek pi_x jako platbu rezervace
  const d = new FakeDb({ bookings: [bk({ total_price: 3000, stripe_payment_intent_id: 'pi_x' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), pi('pi_x', 1500, 200, { booking_id: BID, type: 'extension' })])
  const a = { bookingId: BID, payRef: 'pi_x', paidCzk: 15, code: 'change_failed', reason: 'new_moto_unavailable', via: 'test', stripe: f.stripe }
  eq(await withFetch(() => handlePaidChangeFailure(d, a as never)), 'auto')
  eq(await withFetch(() => handlePaidChangeFailure(d, a as never)), 'auto')
  eq(f.created.length, 1); eq(f.left('pi_x'), 0)
  const b = d.rows('bookings')[0]
  eq(b.stripe_payment_intent_id, 'pi_orig'); eq(b.payment_status, 'paid'); eq(b.total_price, 3000)

  // storno 100 % (obsluha / cancel_booking_tracked) — i kdyby uložená platba zůstala pi_x:
  b.stripe_payment_intent_id = 'pi_x'
  const main = await pickMainIntent(f.stripe as never, d, { bookingId: BID, storedPi: 'pi_x', chargedHaleru: 1500, refundableHaleru: 0,
    isCustomer: false, amount: 3000 })
  eq(main, { piId: 'pi_orig', refundableHaleru: 300000 }) // dřív: no_op → 'refunded' bez vrácení peněz
  // storno 50 % z původní platby → částečně vráceno
  eq(refundedStatus({ refundStatus: 'succeeded', isCustomer: false, bookingTotalPrice: 3000, amount: 1500,
    refundableHaleru: 300000, effectiveAmountHaleru: 150000, leftHaleru: 0 }), 'partial_refund')
  eq(refundedStatus({ refundStatus: 'succeeded', isCustomer: false, bookingTotalPrice: 3000, amount: 3000,
    refundableHaleru: 300000, effectiveAmountHaleru: 300000, leftHaleru: 0 }), 'refunded')
  // zákaznická vratka ani vratka bez částky se nepřesměrovává
  eq(await pickMainIntent(f.stripe as never, d, { bookingId: BID, storedPi: 'pi_x', chargedHaleru: 1500, refundableHaleru: 0, isCustomer: true, amount: 100 }), null)
  eq(await pickMainIntent(f.stripe as never, d, { bookingId: BID, storedPi: 'pi_x', chargedHaleru: 1500, refundableHaleru: 0, isCustomer: false, amount: 0 }), null)
})

Deno.test('storno: uložený PI opuštěného doplatku (nikdy nezaplacený) → vratka kartou z původní platby, ne převodem', async () => {
  const d = new FakeDb({ bookings: [bk({ stripe_payment_intent_id: 'pi_open' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100)])
  eq(await pickMainIntent(f.stripe as never, d, { bookingId: BID, storedPi: 'pi_open', chargedHaleru: 0, refundableHaleru: 0, isCustomer: false, amount: 3000 }),
    { piId: 'pi_orig', refundableHaleru: 300000 })
  // rezervace placená QR (žádná platba kartou) → null → ruční vratka jako dosud
  const q = fakeStripe([])
  eq(await pickMainIntent(q.stripe as never, d, { bookingId: BID, storedPi: 'pi_open', chargedHaleru: 0, refundableHaleru: 0, isCustomer: false, amount: 3000 }), null)
})

Deno.test('storno 50 % po zaplacené úpravě: hlavní = malý doplatek celý, zbytek z původní platby → partial_refund', async () => {
  const d = new FakeDb({ bookings: [bk({ stripe_payment_intent_id: 'pi_ext' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), pi('pi_ext', 1500, 200, { booking_id: BID, type: 'extension' })])
  // hlavní vratka (process-refund) z pi_ext: 15 Kč celých
  const main = await f.stripe.refunds.create({ payment_intent: 'pi_ext', metadata: { mg_source: 'process-refund' } }, { idempotencyKey: 'refund:main' })
  const ex = await refundRemainder(f.stripe as never, d, { bookingId: BID, mainPi: 'pi_ext', mainRefundId: main.id, remainingHaleru: 150750 - 1500 })
  eq(ex.refundedHaleru, 149250); eq(ex.leftHaleru, 150750); eq(ex.refunds.map((r) => r.piId), ['pi_orig'])
  eq(refundedStatus({ refundStatus: 'succeeded', isCustomer: false, bookingTotalPrice: 3015, amount: 1507.5,
    refundableHaleru: 1500, effectiveAmountHaleru: 1500, leftHaleru: ex.leftHaleru }), 'partial_refund')
})

Deno.test('zbytek vratky: duplicitní dispatch (přehraná hlavní vratka) nevrací zbytek podruhé; nová hlavní vratka = nový klíč', async () => {
  const d = new FakeDb({ bookings: [bk()], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), pi('pi_e1', 1000, 150, { booking_id: BID, type: 'extension' }),
    pi('pi_e2', 50000, 200, { booking_id: BID, type: 'extension' })])
  const a = { bookingId: BID, mainPi: 'pi_orig', mainRefundId: 're_main1', remainingHaleru: 20000 }
  const one = await refundRemainder(f.stripe as never, d, a)
  eq(one.refundedHaleru, 20000); eq(f.created.length, 2) // pi_e1 celý (1000) + pi_e2 19000
  const two = await refundRemainder(f.stripe as never, d, a) // druhý dispatch po dokončení prvního
  eq(f.created.length, 2); eq(two.refundedHaleru, 20000); eq(two.refunds.length, 0)
  eq(f.left('pi_e2'), 31000)
  const later = await refundRemainder(f.stripe as never, d, { ...a, mainRefundId: 're_main2', remainingHaleru: 5000 })
  eq(later.refundedHaleru, 5000); eq(f.created.length, 3); eq(f.left('pi_e2'), 26000)
})

Deno.test('ostatní platby: webový doplatek z historie (cs_ i pi_ bez metadat) ano; nezapsaná změna, duplicita, e-shop, cizí ne', async () => {
  const d = new FakeDb({ bookings: [bk({ modification_history: [
    { type: 'moto_swap_replace', payment_ref: 'cs_web1' }, { type: 'edit', payment_ref: 'pi_web2' }, { type: 'edit', payment_ref: 'waive:a:b' },
    { type: 'edit', payment_ref: 'pi_foreign' }] })], debug_log: [{ id: 'l1', action: 'paid_change_failed', request_data: { payment_ref: 'pi_failed' } }] })
  const f = fakeStripe([
    pi('pi_orig', 300000, 100),
    pi('pi_web1', 2000, 150, {}), pi('pi_web2', 900, 160, {}),
    pi('pi_failed', 1500, 170, { booking_id: BID, type: 'extension' }),
    pi('pi_dup', 300000, 180, { booking_id: BID, type: 'booking', duplicate_of: 'pi_orig' }),
    pi('pi_shop', 50000, 190, { booking_id: BID, type: 'shop' }),
    pi('pi_foreign', 700, 195, { booking_id: 'aaaaaaaa-2222-4333-8444-555555555555', type: 'extension' }),
  ], { cs_web1: { payment_intent: 'pi_web1', metadata: { booking_id: BID, type: 'extension' } } })
  const c = await otherRefundableIntents(f.stripe as never, d, BID, 'pi_orig')
  eq(c.map((x) => x.id), ['pi_web1', 'pi_web2'])
  eq(c.map((x) => x.refundableHaleru), [2000, 900])
})

Deno.test('failureRow: první dokončovatel ještě vrací (< 2 min) → očekávaný výsledek, ne „obsluha"; pořadí created_at, id', async () => {
  const now = Date.parse('2026-10-16T12:00:30.000Z')
  const d = new FakeDb({ bookings: [], debug_log: [
    { id: 'b', action: 'paid_change_failed', created_at: '2026-10-16T12:00:00.000Z', request_data: { payment_ref: 'pi_1', reason: 'new_moto_unavailable', expect_refund: 'staff' }, response_data: null },
    { id: 'a', action: 'paid_change_failed', created_at: '2026-10-16T12:00:00.000Z', request_data: { payment_ref: 'pi_1', reason: 'new_moto_unavailable', expect_refund: 'auto' }, response_data: null },
  ] })
  eq(await failureRow(d, 'pi_1', now), { reason: 'new_moto_unavailable', refund: 'auto' }) // 'a' < 'b'
  eq(await failureRow(d, 'pi_1', now + 5 * 60_000), { reason: 'new_moto_unavailable', refund: 'staff' }) // starý bez výsledku
  d.rows('debug_log')[1].response_data = { refund: 'staff' }
  eq(await failureRow(d, 'pi_1', now), { reason: 'new_moto_unavailable', refund: 'staff' })
})

Deno.test('complete_extension: obsazená motorka zůstane obsazenou i když doplatek vrací obsluha', () => {
  eq(failedText('new_moto_unavailable', true), CS.change_failed_taken_staff)
  eq(failedText('moto_unavailable', false), CS.change_failed_taken)
  eq(failedText('booking_cancelled', true), CS.change_failed_staff)
  eq(failedText('db_refused', false), CS.change_failed)
  if (/@|\+420|774\s?256|kontaktuj|zavolej|info@/i.test(CS.change_failed_taken_staff)) throw new Error('kontakt v textu')
})

Deno.test('Stripe Checkout: dorovnání a doplatek úpravy v jazyce webu, druh změny v názvu', () => {
  eq(roundingLabel('cs'), 'Dorovnání na minimální platbu kartou (15 Kč)')
  eq(roundingLabel('en'), 'Top-up to the minimum card payment (CZK 15)')
  eq(roundingLabel('uk'), 'Доплата до мінімального платежу карткою (15 CZK)')
  eq(roundingLabel('xx'), roundingLabel('cs'))
  eq(editLineLabel({ _swap: { m: 'x' } }, 'cs'), 'MotoGo24 — Doplatek za výměnu motorky')
  eq(editLineLabel({ _gear: {} }, 'de'), 'MotoGo24 — Aufpreis für die Ausrüstung')
  eq(editLineLabel({ p_new_end: '2026-11-13' }, 'pl'), 'MotoGo24 — Dopłata za zmianę rezerwacji')
  for (const l of ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
    if (!roundingLabel(l).includes('15')) throw new Error(`${l}: chybí 15`)
  }
})
