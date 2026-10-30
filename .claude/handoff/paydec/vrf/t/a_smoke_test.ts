import { boot, setup, velinCancel, deliver, dump, eq, ok, priceRefundedH, cnSumH, bk, webhookDuringRefund } from '../harness.ts'
await boot()

Deno.test('smoke: Velín plné storno, 1 platba kartou, webhook až po odpovědi → 100 %, 1 dobropis, refunded', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  await velinCancel()
  await deliver(undefined, 2) // + replay
  const d = dump()
  eq(priceRefundedH(), 300000, 'vráceno ' + JSON.stringify(d))
  eq(cnSumH(), 300000, 'dobropisy ' + JSON.stringify(d))
  eq(bk().payment_status, 'refunded', 'stav')
})

Deno.test('smoke: Velín plné storno, webhook během process-refund → 100 %, 1 dobropis', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  webhookDuringRefund()
  await velinCancel()
  const d = dump()
  eq(priceRefundedH(), 300000, 'vráceno ' + JSON.stringify(d))
  eq(cnSumH(), 300000, 'dobropisy ' + JSON.stringify(d))
  ok(d.cns.length === 1, 'jeden dobropis ' + JSON.stringify(d))
  eq(bk().payment_status, 'refunded', 'stav')
})
