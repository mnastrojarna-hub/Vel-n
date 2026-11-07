// verify:refunds — charge.refunded delivered BEFORE process-refund writes the booking status (normal
// Stripe latency 1–3 s vs. remainder refunds / PDF in process-refund). Booking is 'refund_pending'
// (Velín storno) → webhook safety-net send-cancellation-email (alreadyCancelled) → process-refund
// with amount = charge.amount_refunded → passes the 'refund_pending' gate → second real refund.
import { boot, setup, velinCancel, deliver, dump, eq, priceRefundedH, cnSumH, bk, webhookDuringRefund, call, BID } from '../harness.ts'
import { world } from '../fakes/world.ts'
await boot()

Deno.test('W1 Velín storno 50 % (1 platba, vratka succeeded), charge.refunded dorazí dřív než process-refund zapíše stav → jen 1500', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  webhookDuringRefund()
  await velinCancel({ refundAmount: 1500 })
  const d = dump()
  eq(priceRefundedH(), 150000, '50 % storno ' + JSON.stringify(d))
  eq(cnSumH(), 150000, 'dobropisy ' + JSON.stringify(d))
})

Deno.test('W2 zákaznické storno 50 % (cancel_booking_tracked → send-cancellation-email), webhook dřív než zápis stavu → jen 1500', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  Object.assign(bk(), { status: 'cancelled', cancelled_by_source: 'customer' })
  webhookDuringRefund()
  await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', cancelled_by_source: 'customer', refund_amount: 1500, refund_percent: 50 })
  eq(priceRefundedH(), 150000, '50 % storno ' + JSON.stringify(dump()))
})
