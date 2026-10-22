// verify:refunds — more orderings: credit-note race (webhook recovery vs process-refund), Velín
// "Potvrdit vrácení" on a partially refunded cancelled booking, pending refund status, recovery for a
// second refund, old webhook during deploy.
import { boot, setup, velinCancel, deliver, dump, eq, ok, priceRefundedH, cnSumH, bk, call, BID, creditNotes, opsMails } from '../harness.ts'
import { world } from '../fakes/world.ts'
await boot()
const db = () => (globalThis as any).__DB

/** BookingDetail.confirmCancelledRefund (velin/src/pages/BookingDetail.jsx:414) — step 1 + 3 + 4 */
async function velinConfirmCancelledRefund(amtIn: number) {
  const total = Math.max(0, Math.round(Number(bk().total_price) || 0))
  const amt = Math.min(total, Math.max(0, Math.round(amtIn)))
  const pct = total > 0 ? Math.round(amt / total * 100) : 0
  let r: any = null
  if (amt > 0 && !creditNotes().find((c) => Math.abs(Number(c.total) || 0) === amt)) {
    r = await call('process-refund', { booking_id: BID, reason: 'cancellation', ...(amt >= total ? {} : { amount: amt }) })
  }
  await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', cancellation_reason: 'Storno (Velín)',
    cancelled_by_source: 'velin', refund_amount: amt, refund_percent: pct, skip_refund: true, force: true, source: 'app' })
  return r
}

Deno.test('CN1 webhook recovery vystaví dobropis mezi kontrolou a zápisem process-refund → jeden dobropis = vráceno', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  // Stripe doručí charge.refunded, když process-refund už prošel kontrolou existingCn a bere si číslo dobropisu
  let n = 0, fired = false
  db().rpcs['next_document_number'] = async () => {
    n++
    if (!fired) { fired = true; await deliver() }
    return { data: `DB-2026-${String(n).padStart(4, '0')}`, error: null }
  }
  await velinCancel({ refundAmount: 1500 })
  const d = dump()
  eq(priceRefundedH(), 150000, 'vráceno ' + JSON.stringify(d))
  eq(creditNotes().length, 1, 'dobropisů k jedné vratce ' + JSON.stringify(d))
  eq(cnSumH(), 150000, 'dobropisy = vráceno ' + JSON.stringify(d))
})

Deno.test('V1 Velín storno 50 %, později „Potvrdit částečné vrácení" na 100 % → vrátí zbývajících 1500 (nebo upozorní obsluhu)', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  await velinCancel({ refundAmount: 1500 })
  await deliver()
  eq(bk().payment_status, 'partial_refund', 'po 50 %')
  const mailsBefore = opsMails().length
  const r = await velinConfirmCancelledRefund(3000)
  await deliver()
  const d = dump()
  ok(priceRefundedH() === 300000 || opsMails().length > mailsBefore || r?.success === false,
    `admin potvrdil 100 % → vráceno ${priceRefundedH() / 100} Kč, odpověď ${JSON.stringify(r)} (úspěch bez vratky, bez upozornění) ` + JSON.stringify(d))
})

Deno.test('PS1 čekající Stripe vratka (pending): po charge.refunded zůstane stav navždy refund_pending (na main se přepsal)', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  world().refundStatus = () => 'pending'
  // jen process-refund z Velínu (bez druhého dispatche) — izolovaně stav
  Object.assign(bk(), { status: 'cancelled', payment_status: 'refund_pending', cancelled_by_source: 'velin' })
  await call('process-refund', { booking_id: BID, reason: 'cancellation', amount: 1500 })
  await deliver()
  // Stripe vratku později dokončí (refund.updated / charge.refund.updated webhook-receiver nezpracovává)
  for (const r of world().refunds) r.status = 'succeeded'
  ok(bk().payment_status !== 'refund_pending', 'stav po charge.refunded: ' + JSON.stringify(dump()))
})

Deno.test('PS2 čekající vratka 50 % + charge.refunded (bezpečnostní storno mail webhooku) + potvrzení téže částky ve Velínu → stále jen 1500', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  world().refundStatus = () => 'pending'
  Object.assign(bk(), { status: 'cancelled', payment_status: 'refund_pending', cancelled_by_source: 'velin' })
  await call('process-refund', { booking_id: BID, reason: 'cancellation', amount: 1500 })
  await deliver()
  for (const r of world().refunds) r.status = 'succeeded'
  world().refundStatus = () => 'succeeded'
  await velinConfirmCancelledRefund(1500) // admin jen potvrzuje proběhlých 50 % → dobropis 1500 existuje → přeskočí
  eq(priceRefundedH(), 150000, 'potvrzení téže částky ' + JSON.stringify(dump()))
})

Deno.test('R1 druhá vratka rezervace: process-refund spadne po refunds.create → webhook recovery dobropis k NOVÉ vratce nevystaví', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  // 1) zkrácení přes web (service, 500) — proběhne celé
  bk().total_price = 2500
  await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' })
  await deliver()
  eq(creditNotes().length, 1, 'první dobropis')
  // 2) další zkrácení 300: Stripe vratka proběhne, ale funkce spadne hned potom (timeout / pád isolate)
  bk().total_price = 2200
  db().beforeUpdate = (t: string, p: any) => { if (t === 'bookings' && p.payment_status && p.stripe_refund_id) throw new Error('isolate killed') }
  await call('process-refund', { booking_id: BID, amount: 300, reason: 'edit_shortening' }).catch(() => null)
  db().beforeUpdate = null
  await deliver() // charge.refunded → webhook → recovery (webhook_refund_retry)
  const d = dump()
  eq(priceRefundedH(), 80000, 'vráceno ' + JSON.stringify(d))
  eq(cnSumH(), 80000, 'dobropisy = vráceno (recovery má vystavit dobropis k re_2) ' + JSON.stringify(d))
})
