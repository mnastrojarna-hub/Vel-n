// verify:refunds — other refund paths: duplicate payment, failed paid change + storno, bundled e-shop,
// customer shortening from the app (multi-payment, webhook orderings), replays after the dedupe windows.
import { boot, setup, velinCancel, deliver, dump, eq, ok, priceRefundedH, allRefundedH, cnSumH, bk, call, BID, creditNotes, opsMails, webhookDuringRefund } from '../harness.ts'
import { world } from '../fakes/world.ts'
await boot()
const db = () => (globalThis as any).__DB
const appliedExt = (id: string) => ({ booking_id: BID, type: 'extension', attempt_id: 'att-' + id, applied_at: '2026-10-01T10:00:00Z' })

Deno.test('G1 e-shop přibalený k platbě rezervace (3000 + 500 e-shop): plné storno z Velínu vrátí 3000, e-shop zůstane', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3500, md: { booking_id: BID, type: 'booking', shop_order_id: 'so-1' } }] })
  db().rows('shop_orders').push({ id: 'so-1', total: 500, payment_status: 'paid' })
  db().rows('invoices')[0].total = 3000
  await velinCancel()
  await deliver()
  eq(priceRefundedH(), 300000, JSON.stringify(dump()))
  eq(bk().payment_status, 'refunded', 'stav')
})

Deno.test('G2 přibalený e-shop + storno 50 % od zákazníka (send-cancellation-email 1500) → 1500', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3500, md: { booking_id: BID, type: 'booking', shop_order_id: 'so-1' } }] })
  db().rows('shop_orders').push({ id: 'so-1', total: 500, payment_status: 'paid' })
  bk().status = 'cancelled'
  await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', refund_amount: 1500, refund_percent: 50, cancelled_by_source: 'customer' })
  await deliver()
  eq(priceRefundedH(), 150000, JSON.stringify(dump()))
})

Deno.test('G3 dvojí platba rezervace vrácená automaticky (mg_source duplicate_payment), pak plné storno → vrátí jen jednu cenu', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_a', czk: 3000, md: { booking_id: BID, type: 'booking' } }, { id: 'pi_b', czk: 3000, md: { booking_id: BID, type: 'booking', duplicate_of: 'pi_a' } }], stored: 'pi_a' })
  // duplicitní platbu webhook vrátil (duplicate-payment.ts): refund mg-dup + debug_log duplicate_payment
  await world().api().refunds.create({ payment_intent: 'pi_b', reason: 'duplicate', metadata: { mg_source: 'duplicate_payment', booking_id: BID } }, { idempotencyKey: 'mg-dup-pi_b' })
  db().rows('debug_log').push({ id: crypto.randomUUID(), action: 'duplicate_payment', request_data: { payment_ref: 'pi_b' }, created_at: new Date().toISOString() })
  await deliver()
  await velinCancel()
  await deliver()
  eq(priceRefundedH(), 300000, 'cena ' + JSON.stringify(dump()))
  eq(allRefundedH(), 600000, 'vše ' + JSON.stringify(dump()))
  eq(cnSumH(), 300000, 'dobropisy jen k ceně')
})

Deno.test('G4 nezapsaná výměna: doplatek 15 Kč vrácen (unapplied_change), uložená platba = doplatek (obnova selhala), storno 50 % → 1500 z původní', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_sw', czk: 15, md: { booking_id: BID, type: 'extension', attempt_id: 'att-sw', chg_hash: 'h' }, receipt: false }], stored: 'pi_sw' })
  await world().api().refunds.create({ payment_intent: 'pi_sw', amount: 1500, metadata: { mg_source: 'unapplied_change', booking_id: BID } }, { idempotencyKey: 'mg-pcf-pi_sw' })
  db().rows('debug_log').push({ id: crypto.randomUUID(), action: 'paid_change_failed', request_data: { payment_ref: 'pi_sw', booking_id: BID }, created_at: new Date().toISOString() })
  await deliver()
  eq(bk().payment_status, 'paid', 'nezapsaný doplatek stav nemění')
  await velinCancel({ refundAmount: 1500 })
  await deliver()
  eq(priceRefundedH(), 150000, JSON.stringify(dump()))
  eq(cnSumH(), 150000)
  eq(bk().payment_status, 'partial_refund')
})

Deno.test('G5 appka: zkrácení o 500 (2 platby, uložen doplatek 115), webhook během vratky → vráceno 500, stav partial_refund, dobropis 500', async () => {
  setup({ total: 3115, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }] })
  bk().total_price = 2615
  webhookDuringRefund()
  const r = await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' }, 'customer')
  ok(r.success && !r.partial, 'odpověď ' + JSON.stringify(r))
  const d = dump()
  eq(priceRefundedH(), 50000, JSON.stringify(d))
  eq(cnSumH(), 50000, JSON.stringify(d))
  eq(bk().payment_status, 'partial_refund', JSON.stringify(d))
  // opakování téhož volání (síť, dvojklik) → nic navíc
  const r2 = await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening' }, 'customer')
  eq(priceRefundedH(), 50000, 'opakování ' + JSON.stringify(r2))
})

Deno.test('G6 replay charge.refunded po 31 min (Stripe opakuje po 5xx / ruční „Resend") u stornované rezervace 50 % → žádná další vratka', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  await velinCancel({ refundAmount: 1500 })
  const ev = await deliver()
  // posun času: zámek mailu (30 min) a 15min dedup dobropisu vypršely
  const claimsReset = db().rpcs['claim_email_send']; const seen = new Set<string>()
  db().rpcs['claim_email_send'] = (a: any) => { const k = a.p_booking_id + a.p_slug; if (seen.has(k)) return { data: false, error: null }; seen.add(k); return { data: true, error: null } }
  void claimsReset
  for (const c of db().rows('invoices')) c.created_at = new Date(Date.now() - 40 * 60_000).toISOString()
  await deliver(ev)
  eq(priceRefundedH(), 150000, 'replay ' + JSON.stringify(dump()))
})
