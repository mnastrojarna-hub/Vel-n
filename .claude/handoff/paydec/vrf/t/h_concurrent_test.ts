// verify:refunds — Velín A (process-refund) and the second dispatch B (send-cancellation-email →
// process-refund) overlapping: B runs after A's main refund, before A's remainder refunds.
import { boot, setup, deliver, dump, eq, ok, priceRefundedH, cnSumH, bk, call, BID, opsMails } from '../harness.ts'
import { world } from '../fakes/world.ts'
await boot()
const appliedExt = (id: string) => ({ booking_id: BID, type: 'extension', attempt_id: 'att-' + id, applied_at: '2026-10-01T10:00:00Z' })

for (const amt of [null, 1565] as const) {
  Deno.test(`H1 Velín storno ${amt ?? 'plné'} 3 platby: druhý dispatch běží mezi hlavní vratkou a zbytkem`, async () => {
    setup({ total: 3130, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }, { id: 'pi_e2', czk: 15, md: appliedExt('e2') }] })
    Object.assign(bk(), { status: 'cancelled', payment_status: 'refund_pending', cancelled_by_source: 'velin' })
    const due = amt ?? 3130
    let fired = false
    world().onRefundCreated = async () => {
      if (fired) return; fired = true
      await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', cancelled_by_source: 'velin', refund_amount: due, refund_percent: Math.round(due / 3130 * 100) })
    }
    await call('process-refund', { booking_id: BID, reason: 'cancellation', ...(amt ? { amount: amt } : {}) })
    world().onRefundCreated = null
    await deliver()
    const d = dump()
    eq(priceRefundedH(), due * 100, 'vráceno ' + JSON.stringify(d))
    eq(cnSumH(), due * 100, 'dobropisy ' + JSON.stringify(d))
    eq(bk().payment_status, amt ? 'partial_refund' : 'refunded', 'stav ' + JSON.stringify(d))
    eq(opsMails().filter((m) => /nevrátila|dořešte/.test(String(m.subject))).length, 0, 'falešné maily obsluze ' + JSON.stringify(d))
  })
}
