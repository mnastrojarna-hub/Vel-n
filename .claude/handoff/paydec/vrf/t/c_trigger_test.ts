// verify:refunds — DB trigger trg_notify_booking_cancelled_email (live schema): every status → cancelled
// posts send-cancellation-email WITHOUT refund_amount / refund_percent. send-cancellation-email then
// computes the refund from the storno table (≥7 days 100 %, 2–7 days 50 %, <48 h 0 %) and calls
// process-refund for real — racing the cancel path that knows the right amount (Velín modal,
// cancel_booking_tracked incl. _storno_cap_after_move). claim_email_send lets only the FIRST
// send-cancellation-email through, so whichever wins decides the money.
import { boot, setup, velinCancelWithTrigger, triggerCancelMail, deliver, dump, eq, priceRefundedH, bk, call, BID } from '../harness.ts'
await boot()

Deno.test('T1 Velín storno 50 % (admin) + DB trigger souběžně, start za 20 dní → vráceno má být 1500, ne 3000', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  await velinCancelWithTrigger({ refundAmount: 1500 })
  await deliver()
  eq(priceRefundedH(), 150000, 'admin zvolil 50 % ' + JSON.stringify(dump()))
})

Deno.test('T1b Velín storno 50 % — trigger doběhne až po vratce z Velínu → stále jen 1500', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  const b = bk()
  Object.assign(b, { status: 'cancelled', cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)', payment_status: 'refund_pending' })
  await call('process-refund', { booking_id: BID, reason: 'cancellation', amount: 1500 })
  await triggerCancelMail()
  await deliver()
  eq(priceRefundedH(), 150000, 'admin zvolil 50 % ' + JSON.stringify(dump()))
})

Deno.test('T2 Velín storno BEZ vratky (0 Kč) + DB trigger → nic se nevrací', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  await velinCancelWithTrigger({ refundAmount: 0 })
  await deliver()
  eq(priceRefundedH(), 0, 'admin zvolil storno bez vratky ' + JSON.stringify(dump()))
  eq(bk().payment_status, 'paid', 'stav')
})

Deno.test('T3 zákaznické storno cancel_booking_tracked se stropem po přesunu (_storno_cap_after_move → 50 %) + trigger dřív → jen 50 %', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  // cancel_booking_tracked: UPDATE status (trigger → pg_net T, zařazen první), INSERT booking_cancellations, pg_net R s částkou
  Object.assign(bk(), { status: 'cancelled', cancelled_by_source: 'customer', cancellation_reason: 'Stornováno zákazníkem' })
  const t = triggerCancelMail()
  const r = call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', cancellation_reason: 'Stornováno zákazníkem',
    cancelled_by_source: 'customer', refund_amount: 1500, refund_percent: 50, source: 'app' })
  await Promise.all([t, r])
  await deliver()
  eq(priceRefundedH(), 150000, 'RPC spočítala 50 % (strop po přesunu) ' + JSON.stringify(dump()))
})
