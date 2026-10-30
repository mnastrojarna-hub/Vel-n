// verify:refunds — L1 money consequence: a service/admin refund that drains the stored surcharge PI marks a
// LIVE booking 'refunded'; a later storno (customer ≥ 7 days → 100 %) then returns nothing.
import { boot, setup, deliver, dump, eq, priceRefundedH, bk, call, BID, opsMails, triggerCancelMail } from '../harness.ts'
await boot()
const appliedExt = (id: string) => ({ booking_id: BID, type: 'extension', attempt_id: 'att-' + id, applied_at: '2026-10-01T10:00:00Z' })

Deno.test('L2 prodloužení o den kartou (+500), pak web zkrácení o den (−500), pak zákaznické storno 100 % → vráceno celkem 3500', async () => {
  setup({ total: 3500, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_ext', czk: 500, md: appliedExt('ext') }] })
  bk().total_price = 3000
  await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening', source: 'edit' }) // web RPC → pg_net (service)
  await deliver()
  const st = bk().payment_status
  // cancel_booking_tracked: počítá vratku jen u zaplacené rezervace — tady pošle částku dle stavu; obě varianty:
  Object.assign(bk(), { status: 'cancelled', cancelled_by_source: 'customer', cancellation_reason: 'Stornováno zákazníkem' })
  await Promise.all([triggerCancelMail(), call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', cancelled_by_source: 'customer',
    refund_amount: 3000, refund_percent: 100, source: 'app' })])
  await deliver()
  eq(priceRefundedH(), 350000, `stav po zkrácení ${st}; ` + JSON.stringify(dump()) + ' mails ' + opsMails().length)
})
