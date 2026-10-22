// ===== _tests/f3_refund_test.ts =====
// fix f3 (2026-10-22):
//  1) webhook charge.refunded → process-refund jen RECOVERY (důvod webhook_refund_retry); rezervace
//     ve stavu 'refund_pending' už nedostane druhou plnou vratku,
//  2) Velín plné storno (process-refund BEZ částky) = celý zůstatek plateb v ceně rezervace
//     (dřív jen uložený doplatek → 115 Kč místo 3115 Kč; po nezapsané výměně 0 Kč),
//  3) dobropis k vratce rozdělené mezi více plateb se dorovná na skutečně vrácenou částku,
//  4) webhook zapisuje stav vratky z process-refund compare-and-set (jen ze 'paid').
// Kroky process-refund/index.ts (Stripe větev) se tu opakují ve stejném pořadí jako v f2 testu.
import { mainSource, refundRemainder, refundedStatus, staffFullBalanceHaleru } from '../process-refund/other-intents.ts'
import { reconcileCreditNote, remainderForMainHaleru } from '../process-refund/credit-note-sync.ts'
import { isRecoveryOnlyReason, syncRefundBooking, webhookRecoveryBody, WEBHOOK_REFUND_RECOVERY_REASON } from '../_shared/refund-recovery.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
type Row = Record<string, unknown>
const BID = '11111111-2222-4333-8444-555555555555'
const NOW = Date.UTC(2026, 9, 22, 12, 0, 0)
type Pi = { id: string; status: string; amount_received: number; created: number; metadata: Record<string, string> }
const pi = (id: string, h: number, created: number, md: Record<string, string> = { booking_id: BID, type: 'booking' }): Pi =>
  ({ id, status: 'succeeded', amount_received: h, created, metadata: md })
const ext = (id: string, h: number, created: number, more: Record<string, string> = {}) =>
  pi(id, h, created, { booking_id: BID, type: 'extension', ...more })

function fakeStripe(intents: Pi[]) {
  const refunds: Record<string, Array<{ id: string; amount: number; status: string; metadata: Record<string, string> }>> = {}
  const byKey = new Map<string, { id: string; amount: number; status: string }>()
  let n = 0
  const left = (id: string) => (intents.find((x) => x.id === id)?.amount_received || 0) - (refunds[id] || []).reduce((s, r) => s + r.amount, 0)
  const stripe = {
    paymentIntents: {
      search: () => Promise.resolve({ data: intents.filter((x) => x.metadata.booking_id === BID && x.status === 'succeeded') }),
      retrieve: (id: string) => { const x = intents.find((p) => p.id === id); return x ? Promise.resolve(x) : Promise.reject(new Error('missing')) },
    },
    refunds: {
      list: (p: Row) => Promise.resolve({ data: refunds[String(p.payment_intent)] || [] }),
      create: (p: Row, o: Row = {}) => {
        const key = String(o.idempotencyKey || '')
        if (key && byKey.has(key)) return Promise.resolve(byKey.get(key)!)
        const id = String(p.payment_intent)
        const amt = p.amount != null ? Number(p.amount) : left(id)
        if (amt <= 0 || amt > left(id)) return Promise.reject(new Error('charge_already_refunded'))
        const r = { id: `re_${++n}`, amount: amt, status: 'succeeded', metadata: (p.metadata || {}) as Record<string, string> }
        ;(refunds[id] ||= []).push(r); if (key) byKey.set(key, r)
        return Promise.resolve(r)
      },
    },
  }
  return { stripe, refunds, left, count: () => n }
}
const db = (o: Row = {}, more: Record<string, Row[]> = {}) => new FakeDb({
  bookings: [{ id: BID, status: 'cancelled', payment_status: 'refund_pending', total_price: 3115, modification_history: [],
    stripe_payment_intent_id: 'pi_ext', stripe_refund_id: null, ...o }],
  debug_log: [], ...more,
})

/** Vratka obsluhy / služby (Velín), kroky jako process-refund/index.ts Stripe větev po opravě f3. */
async function staffRefund(f: ReturnType<typeof fakeStripe>, d: FakeDb, storedId: string, amount?: number) {
  const s = f.stripe as never
  const storedPi = await f.stripe.paymentIntents.retrieve(storedId).catch(() => null)
  const storedRefunds = (await f.stripe.refunds.list({ payment_intent: storedId })).data
  let charged = storedPi?.amount_received || 0
  let refundable = Math.max(0, charged - storedRefunds.reduce((t, r) => t + r.amount, 0))
  let reqAmount = amount
  let fullBalance = false
  if (!(Number(amount) > 0)) {
    const bal = await staffFullBalanceHaleru(s, d, { bookingId: BID, storedPi, storedRefunds, nowMs: NOW })
    if (bal != null && bal > 0) { reqAmount = bal / 100; fullBalance = true }
  }
  let mainPi = storedId
  const src = await mainSource(s, d, { bookingId: BID, storedPiId: storedId, storedPi, storedRefunds, chargedHaleru: charged,
    refundableHaleru: refundable, isCustomer: false, amount: reqAmount, nowMs: NOW })
  if (src.kind === 'manual') return { kind: 'manual' as const }
  if (src.kind === 'retarget') { mainPi = src.piId; charged = refundable = src.refundableHaleru }
  if (charged === 0) return { kind: 'manual' as const }
  const eff = reqAmount && reqAmount > 0 ? Math.min(Math.round(reqAmount * 100), refundable) : refundable
  if (eff === 0) return { kind: 'no_op' as const, status: 'refunded', total: 0 }
  const main = await f.stripe.refunds.create({ payment_intent: mainPi, ...(eff < refundable ? { amount: eff } : {}),
    metadata: { mg_source: 'process-refund', mg_reason: 'cancellation' } }, { idempotencyKey: `refund:${BID}:${eff}:${refundable}` })
  const req = reqAmount && reqAmount > 0 ? Math.round(reqAmount * 100) : null
  const extra = req != null && req > eff
    ? await refundRemainder(s, d, { bookingId: BID, mainPi, mainRefundId: main.id, remainingHaleru: req - eff, reason: 'cancellation' })
    : { refunds: [], refundedHaleru: 0, leftHaleru: 0 }
  return { kind: src.kind, mainPi, mainRefundId: main.id, main: main.amount, extra: extra.refundedHaleru, total: main.amount + extra.refundedHaleru,
    status: refundedStatus({ refundStatus: 'succeeded', isCustomer: false, bookingTotalPrice: 3115, amount: reqAmount, refundableHaleru: refundable,
      effectiveAmountHaleru: eff, leftHaleru: extra.leftHaleru, fullBalance }) }
}

/** Brána process-refund/index.ts pro rezervaci (bez zákaznických kontrol): co se s voláním stane. */
function gate(body: Row, paymentStatus: string): 'recovery' | 'idempotent' | 'refund' | 'not_paid' {
  if (isRecoveryOnlyReason(body.reason)) return 'recovery'
  const wantsNewPartial = paymentStatus === 'partial_refund' && Number(body.amount) > 0
  if (paymentStatus === 'refunded' || (paymentStatus === 'partial_refund' && !wantsNewPartial)) return 'idempotent'
  if (paymentStatus !== 'paid' && paymentStatus !== 'refund_pending' && !wantsNewPartial) return 'not_paid'
  return 'refund'
}

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

// ── 2) Velín plné storno bez částky ─────────────────────────────────────────
Deno.test('f3/2: Velín plné storno bez částky po zaplacené úpravě → vrátí 3000 + 115 Kč, refunded', async () => {
  const d = db()
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  const r = await staffRefund(f, d, 'pi_ext')
  eq([r.kind, r.total, r.status], ['stored', 311500, 'refunded'])
  eq([f.left('pi_ext'), f.left('pi_orig')], [0, 0])
  // navazující send-cancellation-email (amount = celá cena) → 'refunded' = idempotentní větev
  eq(gate({ booking_id: BID, amount: 3115, reason: 'cancellation' }, 'refunded'), 'idempotent')
})

Deno.test('f3/2: Velín plné storno po nezapsané výměně (uložený vrácený doplatek) → vrátí původní platbu', async () => {
  const d = db({ stripe_payment_intent_id: 'pi_swap', total_price: 3000 }, {})
  d.rows('debug_log').push({ id: 'l1', action: 'paid_change_failed', request_data: { payment_ref: 'pi_swap' } })
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_swap', 50000, NOW / 1000 - 600, { chg_hash: 'h' })])
  await f.stripe.refunds.create({ payment_intent: 'pi_swap', metadata: { mg_source: 'unapplied_change' } })
  const r = await staffRefund(f, d, 'pi_swap')
  eq([r.kind, r.mainPi, r.total, r.status], ['retarget', 'pi_orig', 300000, 'refunded'])
  eq(f.left('pi_orig'), 0)
})

Deno.test('f3/2: dorovnaný doplatek 15 Kč (D1) se při plném stornu vrací celý; doplatek, který webhook ještě nezapsal, ne', async () => {
  const d = db()
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 1500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  eq((await staffRefund(f, d, 'pi_ext')).total, 301500)
  const d2 = db({ stripe_payment_intent_id: 'pi_new' })
  const f2 = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_new', 11500, NOW / 1000 - 60, { attempt_id: 'a1' })])
  const r = await staffRefund(f2, d2, 'pi_new')
  eq([r.kind, r.mainPi, r.total, r.status], ['retarget', 'pi_orig', 300000, 'refunded'])
  eq(f2.left('pi_new'), 11500, 'nezapsaný doplatek nedotčen (vyřeší webhook / fronta)')
})

Deno.test('f3/2: uložená platba s přibaleným e-shopem → vrátí jen část v ceně rezervace, stav refunded', async () => {
  const d = db({ stripe_payment_intent_id: 'pi_orig', total_price: 3000 }, { shop_orders: [{ id: 'so1', total: 500 }] })
  const f = fakeStripe([pi('pi_orig', 350000, 100, { booking_id: BID, type: 'booking', shop_order_id: 'so1' })])
  const r = await staffRefund(f, d, 'pi_orig')
  eq([r.total, r.status], [300000, 'refunded']); eq(f.left('pi_orig'), 50000)
})

Deno.test('f3/2: s částkou beze změny; refundedStatus fullBalance', async () => {
  const d = db()
  const f = fakeStripe([pi('pi_orig', 300000, 100), ext('pi_ext', 11500, NOW / 1000 - 3600, { chg_hash: 'h', applied_at: 'x' })])
  const r = await staffRefund(f, d, 'pi_ext', 1557.5)
  eq([r.main, r.extra, r.status], [11500, 144250, 'partial_refund'])
  const base = { isCustomer: false, bookingTotalPrice: 3115, amount: 3000, refundableHaleru: 350000, effectiveAmountHaleru: 300000 }
  eq([refundedStatus({ ...base, refundStatus: 'succeeded', leftHaleru: 0, fullBalance: true }),
    refundedStatus({ ...base, refundStatus: 'succeeded', leftHaleru: 0 }),
    refundedStatus({ ...base, refundStatus: 'pending', leftHaleru: 0, fullBalance: true }),
    refundedStatus({ ...base, refundStatus: 'succeeded', leftHaleru: 100, fullBalance: true })],
  ['refunded', 'partial_refund', 'refund_pending', 'partial_refund'])
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
