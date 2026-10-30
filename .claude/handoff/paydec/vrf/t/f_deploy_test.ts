// verify:refunds — deploy window (deploy-functions.yml deploys functions one by one; old and new
// versions run side by side for ~a minute). Run with WH_DIR=<main functions> (old webhook-receiver,
// recovery call {booking_id} without reason, unconditional status write) or PR_DIR=<main>.
import { boot, setup, velinCancel, deliver, dump, eq, priceRefundedH, cnSumH, webhookDuringRefund } from '../harness.ts'
import { world } from '../fakes/world.ts'
await boot()

Deno.test('X1 Velín storno 50 % s čekající vratkou, webhook dřív i později', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  world().refundStatus = () => 'pending'
  webhookDuringRefund()
  await velinCancel({ refundAmount: 1500 })
  await deliver(undefined, 2)
  eq(priceRefundedH(), 150000, JSON.stringify(dump()))
})

Deno.test('X2 Velín storno 50 %, webhook dřív než zápis stavu (succeeded)', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  webhookDuringRefund()
  await velinCancel({ refundAmount: 1500 })
  eq(priceRefundedH(), 150000, JSON.stringify(dump()))
  eq(cnSumH(), 150000, JSON.stringify(dump()))
})
