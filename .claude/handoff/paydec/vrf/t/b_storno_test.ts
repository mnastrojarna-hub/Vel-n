// verify:refunds — Velín / customer storno end to end (real process-refund, webhook-receiver,
// send-cancellation-email handlers; fake Stripe + DB). Invariants: never more than due, never less
// than due without a staff mail, exactly once under retries/replays, credit notes == refunded money.
import { boot, setup, velinCancel, deliver, dump, eq, ok, priceRefundedH, cnSumH, bk, webhookDuringRefund, call, BID, opsMails } from '../harness.ts'
import { world } from '../fakes/world.ts'
await boot()

const appliedExt = (id: string) => ({ booking_id: BID, type: 'extension', attempt_id: 'att-' + id, applied_at: '2026-10-01T10:00:00Z' })

// ── 1) PENDING Stripe refund (low balance) + Velín partial storno ─────────────────────────────
Deno.test('P1 pending vratka: Velín storno 50 % (1 platba) → druhý dispatch send-cancellation-email nesmí vrátit podruhé', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  world().refundStatus = () => 'pending'
  await velinCancel({ refundAmount: 1500 })
  await deliver()
  const d = dump()
  eq(priceRefundedH(), 150000, '50 % storno: vráceno ' + JSON.stringify(d))
  eq(cnSumH(), 150000, 'dobropisy = vráceno ' + JSON.stringify(d))
})

Deno.test('P2 pending vratka + webhook během process-refund: Velín storno 50 % → jen 50 %', async () => {
  setup({ total: 3000, payments: [{ id: 'pi_orig', czk: 3000 }] })
  world().refundStatus = () => 'pending'
  webhookDuringRefund()
  await velinCancel({ refundAmount: 1500 })
  const d = dump()
  eq(priceRefundedH(), 150000, '50 % storno: vráceno ' + JSON.stringify(d))
})

Deno.test('P3 pending vratka: Velín plné storno 3 platby kartou → přesně 100 %, žádná druhá vratka', async () => {
  setup({ total: 3130, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }, { id: 'pi_e2', czk: 15, md: appliedExt('e2') }] })
  world().refundStatus = () => 'pending'
  await velinCancel()
  await deliver()
  const d = dump()
  eq(priceRefundedH(), 313000, 'vráceno ' + JSON.stringify(d))
  eq(cnSumH(), 313000, 'dobropisy ' + JSON.stringify(d))
})

// ── 2) multi-payment storno, webhook ordering ────────────────────────────────────────────────
for (const mode of ['after', 'during', 'during+replay'] as const) {
  Deno.test(`M1 Velín plné storno 3 platby (uložen doplatek 15 Kč), webhook ${mode} → 3130, dobropis 3130, refunded`, async () => {
    setup({ total: 3130, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }, { id: 'pi_e2', czk: 15, md: appliedExt('e2') }] })
    if (mode !== 'after') webhookDuringRefund()
    await velinCancel()
    if (mode === 'after') await deliver()
    if (mode === 'during+replay') { webhookDuringRefund(false); for (const r of world().refunds) await deliver([{ id: 'evt_r' + r.id, type: 'charge.refunded', created: r.created, data: { object: world().chargeSnapshot(r.charge) } }], 2) }
    const d = dump()
    eq(priceRefundedH(), 313000, 'vráceno ' + JSON.stringify(d))
    eq(cnSumH(), 313000, 'dobropisy ' + JSON.stringify(d))
    eq(bk().payment_status, 'refunded', 'stav ' + JSON.stringify(d))
    eq(opsMails().filter((m) => /nevrátila|dořešte/.test(String(m.subject))).length, 0, 'žádný falešný mail obsluze ' + JSON.stringify(d))
  })
  Deno.test(`M2 Velín storno 50 % 3 platby, webhook ${mode} → 1565, dobropis 1565, partial_refund`, async () => {
    setup({ total: 3130, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }, { id: 'pi_e2', czk: 15, md: appliedExt('e2') }] })
    if (mode !== 'after') webhookDuringRefund()
    await velinCancel({ refundAmount: 1565 })
    if (mode === 'after') await deliver()
    if (mode === 'during+replay') { webhookDuringRefund(false); for (const r of world().refunds) await deliver([{ id: 'evt_r' + r.id, type: 'charge.refunded', created: r.created, data: { object: world().chargeSnapshot(r.charge) } }], 2) }
    const d = dump()
    eq(priceRefundedH(), 156500, 'vráceno ' + JSON.stringify(d))
    eq(cnSumH(), 156500, 'dobropisy ' + JSON.stringify(d))
    eq(bk().payment_status, 'partial_refund', 'stav ' + JSON.stringify(d))
  })
}

// ── 3) second dispatch after a SHORT first refund (remainder Stripe error) ───────────────────
Deno.test('S1 Velín storno 50 %: zbytek z původní platby jednou selže → druhý dispatch nesmí vrátit víc než 50 %', async () => {
  setup({ total: 3115, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }] })
  let failed = false
  world().failCreate = (_p, key) => (!failed && key?.startsWith('refund-rest:')) ? (failed = true, new Error('Too many requests')) : null
  await velinCancel({ refundAmount: 1558 })
  await deliver()
  const d = dump()
  ok(priceRefundedH() <= 155800, 'přeplaceno: vráceno ' + priceRefundedH() / 100 + ' Kč při 50 % = 1558 Kč ' + JSON.stringify(d))
})

Deno.test('S2 plné storno 3 platby: zbytek částečně selže → druhý dispatch (send-cancellation-email) bez falešného „zbývá X Kč" obsluze', async () => {
  setup({ total: 3130, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_e1', czk: 115, md: appliedExt('e1') }, { id: 'pi_e2', czk: 15, md: appliedExt('e2') }] })
  let failed = false
  world().failCreate = (p, key) => (!failed && key?.startsWith('refund-rest:') && p.payment_intent === 'pi_e1') ? (failed = true, new Error('api_connection_error')) : null
  await velinCancel()
  await deliver()
  const d = dump()
  eq(priceRefundedH(), 313000, 'vráceno ' + JSON.stringify(d))
  const lastShort = opsMails().filter((m) => /nevrátila|dořešte/.test(String(m.subject)))
  // po 2. dispatchi je vráceno vše — poslední mail obsluze nesmí tvrdit, že zbývá vrátit 3015 Kč
  ok(!lastShort.some((m) => /zbývá <strong>3015/.test(String(m.body?.raw_html))), 'falešný mail „zbývá 3015 Kč" ' + JSON.stringify(d))
})

// ── 4) live booking: a staff/web refund that empties the stored surcharge must not mark it 'refunded'
Deno.test('L1 živá rezervace: web zkrácení vrátí celý uložený doplatek → stav partial_refund; pozdější storno 100 % vrátí zbytek', async () => {
  setup({ total: 3500, payments: [{ id: 'pi_orig', czk: 3000 }, { id: 'pi_ext', czk: 500, md: appliedExt('ext') }] })
  // web zkrácení (RPC _apply_booking_changes_core → pg_net service, částka 500)
  bk().total_price = 3000
  const r = await call('process-refund', { booking_id: BID, amount: 500, reason: 'edit_shortening', source: 'edit' })
  ok(r.success, 'zkrácení ' + JSON.stringify(r))
  await deliver()
  eq(bk().payment_status, 'partial_refund', 'živá rezervace s 3000 Kč zaplacenými ' + JSON.stringify(dump()))
  // zákazník stornuje ≥ 7 dní předem (cancel_booking_tracked → send-cancellation-email, 100 %)
  bk().status = 'cancelled'
  await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', refund_amount: 3000, refund_percent: 100, cancelled_by_source: 'customer' })
  await deliver()
  eq(priceRefundedH(), 350000, 'storno 100 % po zkrácení: vráceno celkem ' + JSON.stringify(dump()))
})

// ── 5) full storno with a part paid by QR/transfer (not on Stripe) ───────────────────────────
Deno.test('Q1 plné storno: 3000 kartou + 1000 doplatek převodem → karta 3000 a obsluha dostane upozornění na 1000 převodem', async () => {
  setup({ total: 4000, payments: [{ id: 'pi_orig', czk: 3000 }], booking: { mod_surcharge_vs: '123456' } })
  await velinCancel()
  await deliver()
  const d = dump()
  eq(priceRefundedH(), 300000, 'karta ' + JSON.stringify(d))
  ok(opsMails().length > 0 || bk().payment_status !== 'refunded', 'o nevrácených 1000 Kč (převod) nikdo neví: ' + JSON.stringify(d))
})
