// ===== _tests/f3_refund_test.ts =====
// fix f3 (2026-10-22), bod 2: Velín plné storno (process-refund BEZ částky) = celý zůstatek plateb v ceně
// rezervace (dřív jen uložený doplatek → 115 Kč místo 3115 Kč; po nezapsané výměně 0 Kč). Kroky
// process-refund/index.ts (Stripe větev) se tu opakují ve stejném pořadí jako v f2 testu.
// Body 1, 3, 4 (webhook recovery, dobropis z více plateb, compare-and-set) → f3_webhook_cn_test.ts.
import { mainSource, refundRemainder, refundedStatus, staffFullBalanceHaleru } from '../process-refund/other-intents.ts'
import { FakeDb } from './fake-supabase.ts'
import { BID, NOW, db, eq, ext, fakeStripe, gate, pi } from './f3-helpers.ts'

/** Vratka obsluhy / služby (Velín), kroky jako process-refund/index.ts Stripe větev po opravě f3. */
async function staffRefund(f: ReturnType<typeof fakeStripe>, d: FakeDb, storedId: string, amount?: number) {
  const s = f.stripe as never
  const storedPi = await f.stripe.paymentIntents.retrieve(storedId).catch(() => null)
  const storedRefunds = (await f.stripe.refunds.list({ payment_intent: storedId })).data
  let charged = storedPi?.amount_received || 0
  let refundable = Math.max(0, charged - storedRefunds.reduce((t, r) => t + r.amount, 0))
  let reqAmount = amount
  let fullBalance = false
  if (!(Number(amount) > 0)) {
    const bal = await staffFullBalanceHaleru(s, d, { bookingId: BID, storedPi, storedRefunds, nowMs: NOW })
    if (bal != null && bal > 0) { reqAmount = bal / 100; fullBalance = true }
  }
  let mainPi = storedId
  const src = await mainSource(s, d, { bookingId: BID, storedPiId: storedId, storedPi, storedRefunds, chargedHaleru: charged,
    refundableHaleru: refundable, isCustomer: false, amount: reqAmount, nowMs: NOW })
  if (src.kind === 'manual') return { kind: 'manual' as const }
  if (src.kind === 'retarget') { mainPi = src.piId; charged = refundable = src.refundableHaleru }
  if (charged === 0) return { kind: 'manual' as const }
  const eff = reqAmount && reqAmount > 0 ? Math.min(Math.round(reqAmount * 100), refundable) : refundable
  if (eff === 0) return { kind: 'no_op' as const, status: 'refunded', total: 0 }
  const main = await f.stripe.refunds.create({ payment_intent: mainPi, ...(eff < refundable ? { amount: eff } : {}),
    metadata: { mg_source: 'process-refund', mg_reason: 'cancellation' } }, { idempotencyKey: `refund:${BID}:${eff}:${refundable}` })
  const req = reqAmount && reqAmount > 0 ? Math.round(reqAmount * 100) : null
  const extra = req != null && req > eff
    ? await refundRemainder(s, d, { bookingId: BID, mainPi, mainRefundId: main.id, remainingHaleru: req - eff, reason: 'cancellation' })
    : { refunds: [], refundedHaleru: 0, leftHaleru: 0 }
  return { kind: src.kind, mainPi, mainRefundId: main.id, main: main.amount, extra: extra.refundedHaleru, total: main.amount + extra.refundedHaleru,
    status: refundedStatus({ refundStatus: 'succeeded', isCustomer: false, bookingTotalPrice: 3115, amount: reqAmount, refundableHaleru: refundable,
      effectiveAmountHaleru: eff, leftHaleru: extra.leftHaleru, fullBalance }) }
}

// ── 2) Velín plné storno bez částky ─────────────────────────────────────────
Deno.test('f3/2: Velín plné storno bez částky po zaplacené úpravě → vrátí 3000 + 115 Kč, refunded', async () => {
  const d = db()
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  const r = await staffRefund(f, d, 'pi_ext')
  eq([r.kind, r.total, r.status], ['stored', 311500, 'refunded'])
  eq([f.left('pi_ext'), f.left('pi_orig')], [0, 0])
  // navazující send-cancellation-email (amount = celá cena) → 'refunded' = idempotentní větev
  eq(gate({ booking_id: BID, amount: 3115, reason: 'cancellation' }, 'refunded'), 'idempotent')
})

Deno.test('f3/2: Velín plné storno po nezapsané výměně (uložený vrácený doplatek) → vrátí původní platbu', async () => {
  const d = db({ stripe_payment_intent_id: 'pi_swap', total_price: 3000 }, {})
  d.rows('debug_log').push({ id: 'l1', action: 'paid_change_failed', request_data: { payment_ref: 'pi_swap' } })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_swap', 50000, NOW / 1000 - 600, { chg_hash: 'h' })])
  await f.stripe.refunds.create({ payment_intent: 'pi_swap', metadata: { mg_source: 'unapplied_change' } })
  const r = await staffRefund(f, d, 'pi_swap')
  eq([r.kind, r.mainPi, r.total, r.status], ['retarget', 'pi_orig', 300000, 'refunded'])
  eq(f.left('pi_orig'), 0)
})

Deno.test('f3/2: dorovnaný doplatek 15 Kč (D1) se při plném stornu vrací celý; doplatek, který webhook ještě nezapsal, ne', async () => {
  const d = db()
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 1500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  eq((await staffRefund(f, d, 'pi_ext')).total, 301500)
  const d2 = db({ stripe_payment_intent_id: 'pi_new' })
  const f2 = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_new', 11500, NOW / 1000 - 60, { attempt_id: 'a1' })])
  const r = await staffRefund(f2, d2, 'pi_new')
  eq([r.kind, r.mainPi, r.total, r.status], ['retarget', 'pi_orig', 300000, 'refunded'])
  eq(f2.left('pi_new'), 11500, 'nezapsaný doplatek nedotčen (vyřeší webhook / fronta)')
})

Deno.test('f3/2: uložená platba s přibaleným e-shopem → vrátí jen část v ceně rezervace, stav refunded', async () => {
  const d = db({ stripe_payment_intent_id: 'pi_orig', total_price: 3000 }, { shop_orders: [{ id: 'so1', total: 500 }] })
  const f = fakeStripe([pi('pi_orig', 350000, 100, { booking_id: BID, type: 'booking', shop_order_id: 'so1' })])
  const r = await staffRefund(f, d, 'pi_orig')
  eq([r.total, r.status], [300000, 'refunded']); eq(f.left('pi_orig'), 50000)
})

Deno.test('f3/2: s částkou beze změny; refundedStatus fullBalance', async () => {
  const d = db()
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  const r = await staffRefund(f, d, 'pi_ext', 1557.5)
  eq([r.main, r.extra, r.status], [11500, 144250, 'partial_refund'])
  const base = { isCustomer: false, bookingTotalPrice: 3115, amount: 3000, refundableHaleru: 350000, effectiveAmountHaleru: 300000 }
  eq([refundedStatus({ ...base, refundStatus: 'succeeded', leftHaleru: 0, fullBalance: true }),
    refundedStatus({ ...base, refundStatus: 'succeeded', leftHaleru: 0 }),
    refundedStatus({ ...base, refundStatus: 'pending', leftHaleru: 0, fullBalance: true }),
    refundedStatus({ ...base, refundStatus: 'succeeded', leftHaleru: 100, fullBalance: true })],
  ['refunded', 'partial_refund', 'refund_pending', 'partial_refund'])
})
