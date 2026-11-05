// ===== _tests/storno_multi_test.ts =====
// Sloučení hotfixu storna s vratkou z více plateb (2026-11-05): jednotkové testy cancel-once.ts (hlavní
// vratka vs. zbytek, mg_target, vráceno k stornu celkem), cancel-once-pool.ts (vratky všech plateb) a
// webhook-receiver/cancel-mail-amount.ts (částka pojistného mailu, „jen část větší vratky").
import { cancelTargetHaleru, cancellationRefundedHaleru, duplicateAdminRefunds, logicalRefundHaleru, priorCancellationRefunds, type StripeRefundLike } from '../process-refund/cancel-once.ts'
import { cancellationRefundPool } from '../process-refund/cancel-once-pool.ts'
import { cancellationMailRefundCzk, partOfLargerRefund } from '../webhook-receiver/cancel-mail-amount.ts'
import { Db } from './storno-fake-db.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
const BID = '11111111-2222-4333-8444-555555555555'
const TOK = '2026-11-05T10:00:00.123456+00:00'
const ref = (o: Partial<StripeRefundLike> & { md?: Record<string, string> }): StripeRefundLike => ({
  id: o.id || 're_x', amount: o.amount ?? 11500, status: o.status || 'succeeded', created: o.created ?? 1_800_000_000,
  payment_intent: o.payment_intent ?? 'pi_ext1',
  metadata: { mg_source: 'process-refund', mg_reason: 'cancellation', mg_booking_id: BID, mg_cancel_at: TOK, ...(o.md || {}) },
})
const main = ref({ id: 're_m', amount: 11500, md: { mg_target: '155800', mg_cancel_total: '155800' } })
const rest = ref({ id: 're_r', amount: 144300, payment_intent: 'pi_orig', created: 1_800_000_001, md: { mg_part: 'remainder', mg_main_refund: 're_m' } })

Deno.test('cancel-once (více plateb): vratka TOHOTO storna = jen HLAVNÍ vratka; zbytek k ní patří přes mg_main_refund', () => {
  eq(priorCancellationRefunds([rest, main], BID, TOK).map((r) => r.id), ['re_m'], 'zbytek není „vratka storna“')
  eq(logicalRefundHaleru(main, [rest, main]), 155800)
  eq(logicalRefundHaleru(main, [ref({ id: 'f', amount: 144300, status: 'failed', md: { mg_part: 'remainder', mg_main_refund: 're_m' } })]), 11500, 'failed zbytek se nepočítá')
  eq([cancelTargetHaleru(main), cancelTargetHaleru(rest), cancelTargetHaleru(ref({ md: { mg_target: 'x' } }))], [155800, null, null])
  // vráceno k stornu celkem: 50 % (115 + 1443) + dorovnání 100 % (1557 z původní platby)
  const top = ref({ id: 're_t', amount: 155700, payment_intent: 'pi_orig', created: 1_800_001_000, md: { mg_target: '155700', mg_cancel_total: '311500' } })
  eq(cancellationRefundedHaleru([top, rest, main], BID, TOK), 311500)
  eq(cancellationRefundedHaleru([top, rest, main], BID, '2026-01-01T00:00:00+00:00'), 0, 'jiné storno')
})

Deno.test('cancel-once (více plateb): obsluha — duplicita téhož požadavku i podle cíle storna (hlavní vratka 115 ≠ požadavek 1558)', () => {
  const now = 1_800_000_060
  const ids = (amt: number | null) => duplicateAdminRefunds([rest, main], BID, { amountHaleru: amt, nowS: now, lock: null }).map((r) => r.id)
  eq(ids(155800), ['re_m'], 'stejný požadavek (mg_target)')
  eq(ids(11500), ['re_m'], 'stejná částka hlavní vratky')
  eq(ids(144300), [], 'částka zbytku není požadavek obsluhy')
  eq(ids(200000), [], 'jiný požadavek = vědomá další vratka')
})

Deno.test('cancel-once-pool: vratky všech plateb rezervace (uložená + search + historie), chyba → jen uložená', async () => {
  const sb = new Db({ bookings: [{ id: BID, modification_history: [{ type: 'edit', payment_ref: 'pi_hist' }] }] })
  const lists: Record<string, StripeRefundLike[]> = { pi_ext1: [main], pi_orig: [rest], pi_hist: [ref({ id: 're_h', amount: 100, payment_intent: 'pi_hist' })] }
  const stripe = {
    paymentIntents: {
      search: () => Promise.resolve({ data: [{ id: 'pi_orig', status: 'succeeded', amount_received: 300000, created: 1, metadata: { booking_id: BID, type: 'booking' } },
        { id: 'pi_shop', status: 'succeeded', amount_received: 5000, created: 2, metadata: { booking_id: BID, type: 'shop' } }] }),
      retrieve: (id: string) => Promise.resolve({ id, status: 'succeeded', amount_received: 100, created: 3, metadata: {} }),
    },
    refunds: { list: (p: { payment_intent: string }) => Promise.resolve({ data: lists[p.payment_intent] || [] }), create: () => Promise.reject(new Error('no')) },
  }
  const pool = await cancellationRefundPool(stripe as never, sb, { bookingId: BID, storedPiId: 'pi_ext1', storedRefunds: [main] })
  eq([pool.complete, pool.refunds.map((r) => r.id)], [true, ['re_r', 're_m', 're_h']], 'nejnovější první, bez e-shopu, i z historie')
  const broken = { ...stripe, paymentIntents: { ...stripe.paymentIntents, search: () => Promise.reject(new Error('search down')) } }
  const p2 = await cancellationRefundPool(broken as never, sb, { bookingId: BID, storedPiId: 'pi_ext1', storedRefunds: [main] })
  eq([p2.complete, p2.error, p2.refunds.map((r) => r.id)], [false, 'search down', ['re_m']])
})

Deno.test('cancel-mail-amount: částka pojistného mailu = celé storno (mg_cancel_total), u zbytku přes hlavní vratku; jinak částka z charge', async () => {
  const stripe = { refunds: { retrieve: (id: string) => id === 're_m' ? Promise.resolve(main) : Promise.reject(new Error('no')) } }
  eq(await cancellationMailRefundCzk(stripe, main), 1558)
  eq(await cancellationMailRefundCzk(stripe, rest), 1558, 'zbytek → hlavní vratka')
  eq(await cancellationMailRefundCzk(stripe, ref({ md: { mg_part: 'remainder', mg_main_refund: 're_gone' } })), null, 'hlavní vratka nedohledána')
  eq(await cancellationMailRefundCzk(stripe, ref({ md: { mg_cancel_total: '' } })), null, 'starší vratka bez mg_cancel_total')
  eq(await cancellationMailRefundCzk(stripe, { metadata: {} }), null, 'ruční vratka v dashboardu')
  eq(await cancellationMailRefundCzk(stripe, ref({ md: { mg_reason: 'edit_shortening', mg_cancel_total: '50000' } })), null, 'jen storno')
  eq([partOfLargerRefund(main), partOfLargerRefund(rest), partOfLargerRefund(ref({ amount: 150000, md: { mg_target: '150000' } })),
    partOfLargerRefund(ref({ md: {} })), partOfLargerRefund({ amount: 100, metadata: { mg_target: '200' } }), partOfLargerRefund(null)],
  [true, true, false, false, false, false])
})
