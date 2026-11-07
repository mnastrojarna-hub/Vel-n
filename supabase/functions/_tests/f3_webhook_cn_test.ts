// ===== _tests/f3_webhook_cn_test.ts =====
// fix f3 (2026-10-22):
//  1) webhook charge.refunded → process-refund jen RECOVERY (důvod webhook_refund_retry); rezervace
//     ve stavu 'refund_pending' už nedostane druhou plnou vratku,
//  3) dobropis k vratce rozdělené mezi více plateb se dorovná na skutečně vrácenou částku,
//  4) webhook zapisuje stav vratky z process-refund compare-and-set (jen ze 'paid').
import { refundRemainder } from '../process-refund/other-intents.ts'
import { reconcileCreditNote, remainderForMainHaleru } from '../process-refund/credit-note-sync.ts'
import { isRecoveryOnlyReason, syncRefundBooking, webhookRecoveryBody, WEBHOOK_REFUND_RECOVERY_REASON } from '../_shared/refund-recovery.ts'
import { BID, NOW, db, eq, ext, fakeStripe, gate, ok, pi, type Row } from './f3-helpers.ts'

// ── 1) webhook recovery ──────────────────────────────────────────────────────
Deno.test('f3/1: webhook → process-refund jen recovery: refund_pending + vratka z process-refund = žádná druhá vratka', async () => {
  const d = db({ stripe_payment_intent_id: 'pi_orig' })
  const f = fakeStripe([pi('pi_orig', 300000, 100)])
  // storno 50 % z Velínu (rezervace už 'refund_pending') — vratka proběhla, process-refund ještě nezapsal stav
  await f.stripe.refunds.create({ payment_intent: 'pi_orig', amount: 150000, metadata: { mg_source: 'process-refund', mg_reason: 'cancellation' } })
  const bk = d.rows('bookings')[0]
  const w = await syncRefundBooking(d, { bookingId: BID, currentStatus: String(bk.payment_status), currentRefundId: null,
    fromProcessRefund: true, fullyRefunded: false, refundId: 're_1' })
  eq(bk.payment_status, 'refund_pending', 'refund_pending se nepřepisuje'); eq(w.statusWritten, false)
  eq(bk.stripe_refund_id, 're_1', 'prázdné stripe_refund_id doplněno')
  const body = webhookRecoveryBody(BID, 're_1')
  eq(body.reason, WEBHOOK_REFUND_RECOVERY_REASON); ok(!('amount' in body), 'bez částky')
  eq(gate(body, 'refund_pending'), 'recovery', 'recovery-only větev')
  eq(f.count(), 1, 'žádná další Stripe vratka'); eq(f.left('pi_orig'), 150000)
  // dřív: tělo jen {booking_id} → u 'refund_pending' nová vratka celého zbytku
  eq(gate({ booking_id: BID }, 'refund_pending'), 'refund')
  // čekající vratka zkrácení (process-refund zapsal 'refund_pending') — totéž
  eq(gate(body, 'refund_pending'), 'recovery')
})

Deno.test('f3/1: zdroj — recovery větev je v process-refund před bránou stavu i před refunds.create; webhook posílá recovery tělo', async () => {
  const pr = await Deno.readTextFile(new URL('../process-refund/index.ts', import.meta.url))
  const iRec = pr.indexOf('if (isRecoveryOnlyReason(reason))')
  ok(iRec > 0, 'recovery větev chybí')
  ok(iRec < pr.indexOf("data.payment_status !== 'paid' && data.payment_status !== 'refund_pending'"), 'recovery až za bránou stavu')
  ok(iRec < pr.indexOf('stripe.refunds.create(refundParams'), 'recovery až za vratkou')
  const wr = await Deno.readTextFile(new URL('../webhook-receiver/index.ts', import.meta.url))
  ok(wr.includes('body: JSON.stringify(webhookRecoveryBody(linkedBooking.id'), 'webhook neposílá recovery tělo')
  ok(!wr.includes('body: JSON.stringify({ booking_id: linkedBooking.id })'), 'staré tělo bez důvodu')
  eq([isRecoveryOnlyReason('cancellation_retry'), isRecoveryOnlyReason('booking_modified_retry'), isRecoveryOnlyReason('cancellation'),
    isRecoveryOnlyReason(undefined)], [true, true, false, false])
})

// ── 4) compare-and-set stavu ve webhooku ─────────────────────────────────────
Deno.test('f3/4: process-refund zapíše partial_refund mezi čtením a zápisem webhooku → zůstane partial_refund', async () => {
  const d = db({ status: 'reserved', payment_status: 'paid' })
  let once = true
  d.beforeUpdate = (t) => {
    if (t === 'bookings' && once) { once = false; Object.assign(d.rows('bookings')[0], { payment_status: 'partial_refund', stripe_refund_id: 're_main' }) }
  }
  const w = await syncRefundBooking(d, { bookingId: BID, currentStatus: 'paid', currentRefundId: null,
    fromProcessRefund: true, fullyRefunded: true, refundId: 're_main' })
  const bk = d.rows('bookings')[0]
  eq([bk.payment_status, bk.stripe_refund_id, w.statusWritten, w.refundIdWritten], ['partial_refund', 're_main', false, false])
})

Deno.test('f3/4: stále paid → zástupný stav; stripe_refund_id jen do prázdného; externí (portál) vratka beze změny', async () => {
  const d = db({ status: 'reserved', payment_status: 'paid', stripe_refund_id: 're_old' })
  await syncRefundBooking(d, { bookingId: BID, currentStatus: 'paid', currentRefundId: 're_old', fromProcessRefund: true, fullyRefunded: true, refundId: 're_new' })
  eq([d.rows('bookings')[0].payment_status, d.rows('bookings')[0].stripe_refund_id], ['refunded', 're_old'])
  const e = db({ status: 'reserved', payment_status: 'partial_refund', stripe_refund_id: 're_old' })
  await syncRefundBooking(e, { bookingId: BID, currentStatus: 'partial_refund', currentRefundId: 're_old', fromProcessRefund: false, fullyRefunded: true,
    refundId: 're_portal', cancelPatch: { status: 'cancelled', cancelled_by_source: 'stripe_portal' } })
  const b = e.rows('bookings')[0]
  eq([b.payment_status, b.stripe_refund_id, b.status, b.cancelled_by_source], ['refunded', 're_portal', 'cancelled', 'stripe_portal'])
})

// ── 3) dobropis vratky z více plateb ─────────────────────────────────────────
Deno.test('f3/3: recovery dobropis jen z hlavní vratky (−115) → process-refund ho dorovná na −500 vč. účetního záznamu', async () => {
  const d = db({ status: 'reserved', payment_status: 'paid' }, {
    invoices: [
      { id: 'dp1', booking_id: BID, type: 'payment_receipt', status: 'issued', total: 3000 },
      { id: 'dp2', booking_id: BID, type: 'payment_receipt', status: 'issued', total: 115 },
      { id: 'cn1', booking_id: BID, type: 'credit_note', status: 'issued', number: 'DB-2026-0007', total: -115, subtotal: -115,
        items: [{ description: 'Dobropis – Storno rezervace (X)', qty: 1, unit_price: -115 }], stripe_refund_id: 're_1' },
    ],
    accounting_entries: [{ id: 'ae1', booking_id: BID, invoice_id: 'cn1', category: 'refund', amount: -115, description: 'Dobropis DB-2026-0007 - Storno rezervace' }],
  })
  const czk = await reconcileCreditNote(d, { cnId: 'cn1', cnNumber: 'DB-2026-0007', bookingId: BID, currentTotal: -115, targetCzk: 500,
    description: 'Dobropis – Zkrácení rezervace (X)', reasonText: 'Zkrácení rezervace', notes: 'Vráceno z více plateb: re_1 + re_2.', issueDate: '2026-10-22' })
  eq(czk, 500)
  const cn = d.rows('invoices').find((r) => r.id === 'cn1')!
  eq([cn.total, cn.subtotal, (cn.items as Row[])[0].unit_price, (cn.items as Row[])[0].description, cn.notes],
    [-500, -500, -500, 'Dobropis – Zkrácení rezervace (X)', 'Vráceno z více plateb: re_1 + re_2.'])
  eq(d.rows('accounting_entries').map((r) => r.amount), [-500])
  // znovu (duplicitní dispatch) / nižší cíl → beze změny
  eq(await reconcileCreditNote(d, { cnId: 'cn1', cnNumber: 'DB-2026-0007', bookingId: BID, currentTotal: -500, targetCzk: 500,
    description: '', reasonText: '', notes: '', issueDate: '2026-10-22' }), null)
  eq(await reconcileCreditNote(d, { cnId: 'cn1', cnNumber: 'DB-2026-0007', bookingId: BID, currentTotal: -500, targetCzk: 115,
    description: '', reasonText: '', notes: '', issueDate: '2026-10-22' }), null)
  eq(cn.total, -500)
})

Deno.test('f3/3: účetní záznam process-refund (bez invoice_id) dle čísla dobropisu; strop jako _cap_refund_to_paid', async () => {
  const d = db({}, {
    invoices: [
      { id: 'dp1', booking_id: BID, type: 'payment_receipt', status: 'issued', total: 3000 },
      { id: 'cn0', booking_id: BID, type: 'credit_note', status: 'issued', total: -2700 },
      { id: 'cn1', booking_id: BID, type: 'credit_note', status: 'issued', number: 'DB-2026-0008', total: -115 },
    ],
    accounting_entries: [
      { id: 'ae0', booking_id: BID, category: 'refund', amount: -2700, description: 'Dobropis DB-2026-0080 – Storno rezervace' },
      { id: 'ae1', booking_id: BID, category: 'refund', amount: -115, description: 'Dobropis DB-2026-0008 – Storno rezervace' },
    ],
  })
  eq(await reconcileCreditNote(d, { cnId: 'cn1', cnNumber: 'DB-2026-0008', bookingId: BID, currentTotal: -115, targetCzk: 500,
    description: 'x', reasonText: 'Storno rezervace', notes: 'n', issueDate: '2026-10-22' }), 300)
  eq(d.rows('accounting_entries').map((r) => r.amount), [-2700, -300])
  // žádný účetní záznam → doplní se
  const e = db({}, { invoices: [{ id: 'cn1', booking_id: BID, type: 'credit_note', status: 'issued', number: 'DB-2026-0009', total: -115 }] })
  eq(await reconcileCreditNote(e, { cnId: 'cn1', cnNumber: 'DB-2026-0009', bookingId: BID, currentTotal: -115, targetCzk: 500,
    description: 'x', reasonText: 'Storno rezervace', notes: 'n', issueDate: '2026-10-22' }), 500)
  eq(e.rows('accounting_entries').map((r) => [r.amount, r.invoice_id, r.description]), [[-500, 'cn1', 'Dobropis DB-2026-0009 – Storno rezervace']])
})

Deno.test('f3/3: recovery dobropisu započte zbytek, který už k téže hlavní vratce proběhl z jiné platby', async () => {
  const d = db({ status: 'reserved', payment_status: 'paid' })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  const s = f.stripe as never
  const main = await f.stripe.refunds.create({ payment_intent: 'pi_ext', metadata: { mg_source: 'process-refund' } })
  eq(await remainderForMainHaleru(s, d, { bookingId: BID, mainPi: 'pi_ext', mainRefundId: main.id }), 0, 'zbytek ještě neproběhl')
  await refundRemainder(s, d, { bookingId: BID, mainPi: 'pi_ext', mainRefundId: main.id, remainingHaleru: 38500, reason: 'edit_shortening' })
  eq(await remainderForMainHaleru(s, d, { bookingId: BID, mainPi: 'pi_ext', mainRefundId: main.id }), 38500)
  eq(await remainderForMainHaleru(s, d, { bookingId: BID, mainPi: 'pi_ext', mainRefundId: 're_other' }), 0, 'jiná hlavní vratka')
})
