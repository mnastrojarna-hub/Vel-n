// End-to-end harness (verify:refunds): loads the REAL edge handlers process-refund/index.ts,
// webhook-receiver/index.ts and send-cancellation-email/index.ts with a fake Stripe World and an
// in-memory DB (import map → fakes/), routes their internal fetch() calls to each other and lets a
// test order Stripe webhooks (before / after the process-refund response, duplicates, replays).
// Run: deno test --no-check -A --import-map=<vref>/import_map.json <vref>/t/
// deno-lint-ignore-file no-explicit-any
import { World, setWorld, world, type Refund } from './fakes/world.ts'
import { Db } from './fakes/db.ts'

export const FN = Deno.env.get('FN_DIR') || '/home/user/Vel-n/supabase/functions'
export const SB = 'http://sb.local'
export const SVC = 'svc-key-test'
Deno.env.set('SUPABASE_URL', SB)
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
Deno.env.set('SUPABASE_ANON_KEY', 'anon-key-test')
Deno.env.set('STRIPE_SECRET_KEY', 'sk_test_x')
Deno.env.set('STRIPE_WEBHOOK_SECRET', 'whsec_test')
for (const k of ['PDFSHIFT_API_KEY', 'FIO_PAYMENT_TOKEN', 'FIO_API_TOKEN', 'RESEND_API_KEY']) Deno.env.delete(k)

export const BID = '11111111-2222-4333-8444-555555555555'
export const UID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
export const CUST_TOKEN = 'cust.jwt.token'

type Handler = (req: Request) => Promise<Response>
const handlers: Record<string, Handler> = {}
async function load(name: string, path: string) {
  let h: Handler | null = null
  ;(globalThis as any).__CAPTURE = (x: Handler) => { h = x }
  const orig = Deno.serve
  ;(Deno as any).serve = (x: any) => { h = typeof x === 'function' ? x : x?.handler; return { finished: Promise.resolve(), shutdown() {} } }
  await import(path)
  ;(Deno as any).serve = orig
  if (!h) throw new Error('handler not captured: ' + name)
  handlers[name] = h
}

export type Mail = { fn: string; to?: string; subject?: string; body: any }
export const log = { calls: [] as Array<{ fn: string; body: any; status?: number; resp?: any }>, mails: [] as Mail[] }

const realFetch = globalThis.fetch
globalThis.fetch = (async (input: any, init?: any) => {
  const url = typeof input === 'string' ? input : input.url
  if (url.startsWith(SB + '/functions/v1/')) {
    const fn = url.slice((SB + '/functions/v1/').length).split('?')[0]
    let body: any = null
    try { body = init?.body ? JSON.parse(String(init.body)) : null } catch { body = init?.body }
    if (fn === 'send-email') { log.mails.push({ fn, to: body?.to, subject: body?.subject, body }); return new Response('{"ok":true}', { status: 200 }) }
    const h = handlers[fn]
    if (!h) { log.calls.push({ fn, body }); return new Response('{"ok":true}', { status: 200 }) }
    const res = await h(new Request(url, init))
    const txt = await res.text()
    let j: any = null; try { j = JSON.parse(txt) } catch { j = txt }
    log.calls.push({ fn, body, status: res.status, resp: j })
    return new Response(txt, { status: res.status, headers: res.headers })
  }
  if (url.startsWith('https://api.resend.com')) { log.mails.push({ fn: 'resend', body: init?.body }); return new Response('{"id":"em_1"}', { status: 200 }) }
  return new Response('{}', { status: 200 })
}) as typeof fetch
void realFetch

let loaded = false
export async function boot() {
  if (loaded) return
  setWorld(new World())
  ;(globalThis as any).__DB = new Db({})
  // mixed versions (deploy window): PR_DIR / WH_DIR / SCE_DIR override FN per function
  await load('process-refund', `${Deno.env.get('PR_DIR') || FN}/process-refund/index.ts`)
  await load('webhook-receiver', `${Deno.env.get('WH_DIR') || FN}/webhook-receiver/index.ts`)
  await load('send-cancellation-email', `${Deno.env.get('SCE_DIR') || FN}/send-cancellation-email/index.ts`)
  loaded = true
}

/** Fresh Stripe world + DB with one booking. payments: card PaymentIntents (first = stored unless `stored` given). */
export function setup(o: {
  total: number; status?: string; payment_status?: string; payments: Array<{ id: string; czk: number; md?: Record<string, string>; receipt?: boolean; ageDays?: number }>
  stored?: string | null; history?: any[]; booking?: Record<string, any>; receipts?: boolean
}) {
  const w = new World(); setWorld(w)
  const pays = o.payments
  pays.forEach((p, i) => w.addPi(p.id, p.czk, p.md ?? { booking_id: BID, type: i === 0 ? 'booking' : 'extension', ...(i ? { applied_at: '2026-10-01T10:00:00Z' } : {}) },
    { createdAgoS: 86400 * (p.ageDays ?? (30 - i * 5)) }))
  const startIn = new Date(Date.now() + 20 * 86400_000).toISOString().slice(0, 10)
  const endIn = new Date(Date.now() + 23 * 86400_000).toISOString().slice(0, 10)
  const db = new Db({
    bookings: [{ id: BID, user_id: UID, status: o.status ?? 'reserved', payment_status: o.payment_status ?? 'paid', total_price: o.total,
      stripe_payment_intent_id: o.stored === undefined ? (pays[pays.length - 1]?.id ?? null) : o.stored, stripe_session_id: null, stripe_refund_id: null,
      payment_method: 'card', pay_channel: 'card', card_brand: null, card_last4: null, start_date: startIn, end_date: endIn,
      booking_source: 'app', moto_id: 'moto-1', language: 'cs', modification_history: o.history ?? [], cancellation_reason: null, cancelled_by_source: null,
      ...(o.booking || {}) }],
    profiles: [{ id: UID, full_name: 'Test Zákazník', email: 'zakaznik@example.com' }],
    invoices: (o.receipts !== false ? pays.filter((p) => p.receipt !== false) : []).map((p, i) => ({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt',
      status: 'issued', total: p.czk, number: `DP-2026-${1000 + i}`, issue_date: '2026-10-01', created_at: new Date(Date.now() - 86400_000).toISOString() })),
    accounting_entries: [], debug_log: [], financial_events: [], sent_emails: [], email_templates: [], admin_users: [], app_settings: [],
    motorcycles: [{ id: 'moto-1', model: 'Test Moto', price_mon: 1000, price_tue: 1000, price_wed: 1000, price_thu: 1000, price_fri: 1000, price_sat: 1000, price_sun: 1000 }],
    booking_discounts: [], booking_cancellations: [], fio_transactions: [], shop_orders: [],
  })
  db.users.set(CUST_TOKEN, { id: UID })
  // claim_email_send: INSERT … ON CONFLICT DO UPDATE WHERE locked_at < now()-30 min → první vyhrává (jako živá RPC)
  const claims = new Set<string>()
  db.rpcs['claim_email_send'] = (a: any) => { const k = `${a.p_booking_id}|${a.p_slug}`; if (claims.has(k)) return { data: false, error: null }; claims.add(k); return { data: true, error: null } }
  db.rpcs['_moto_dayprice_sum'] = () => ({ data: 3000, error: null })
  db.rpcs['next_document_number'] = (() => { let n = 0; return () => ({ data: `DB-2026-${String(++n).padStart(4, '0')}`, error: null }) })()
  // _cap_refund_to_paid (BEFORE INSERT on invoices)
  db.beforeInsert = (t, r) => {
    if (t !== 'invoices' || r.type !== 'credit_note' || !r.booking_id) return
    const inv = db.rows('invoices')
    const paid = inv.filter((x) => x.booking_id === r.booking_id && x.type === 'payment_receipt' && x.status !== 'cancelled').reduce((s, x) => s + Number(x.total || 0), 0)
    const refunded = inv.filter((x) => x.booking_id === r.booking_id && x.type === 'credit_note' && x.status !== 'cancelled' && x.id !== r.id).reduce((s, x) => s + Math.abs(Number(x.total || 0)), 0)
    if (paid > 0) { const cap = Math.max(0, paid - refunded); if (Math.abs(Number(r.total)) > cap) { r.total = -cap; r.subtotal = -cap } }
  }
  ;(globalThis as any).__DB = db
  log.calls.length = 0; log.mails.length = 0
  return { w, db }
}

export const bk = () => ((globalThis as any).__DB as Db).rows('bookings')[0]
export const creditNotes = () => ((globalThis as any).__DB as Db).rows('invoices').filter((x) => x.type === 'credit_note' && x.status !== 'cancelled')
export const cnSumH = () => creditNotes().reduce((s, x) => s + Math.round(Math.abs(Number(x.total || 0)) * 100), 0)
/** refunds that return booking price money (process-refund) — haléře */
export const priceRefundedH = () => world().refundedTotal((r: Refund) => r.metadata.mg_source === 'process-refund')
export const allRefundedH = () => world().refundedTotal()
export const opsMails = () => log.mails.filter((m) => m.to === 'info@motogo24.cz')

/** POST to an edge handler as service role (default), admin-like staff, or customer. */
export async function call(fn: string, body: any, as: 'service' | 'customer' = 'service'): Promise<any> {
  const token = as === 'customer' ? CUST_TOKEN : SVC
  const res = await handlers[fn](new Request(`${SB}/functions/v1/${fn}`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: JSON.stringify(body) }))
  const t = await res.text(); try { return JSON.parse(t) } catch { return t }
}

/** Deliver Stripe events to webhook-receiver (all queued, oldest first; `times` = duplicate deliveries). */
export async function deliver(events = world().takeEvents(), times = 1) {
  for (const e of events) for (let i = 0; i < times; i++) {
    await handlers['webhook-receiver'](new Request(`${SB}/functions/v1/webhook-receiver`, { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'stripe-signature': 't=1,v1=x' }, body: JSON.stringify(e) }))
  }
  return events
}

/** Webhooks delivered while process-refund is still running (right after each refunds.create). */
export function webhookDuringRefund(on = true) {
  world().onRefundCreated = on ? async () => { await deliver() } : null
}

/** Velín cancelBookingFromVelin (velin/src/pages/booking/bookingMessageHelpers.js) — same calls, same order. */
export async function velinCancel(opts: { refundAmount?: number } = {}) {
  const b = bk()
  const wasPaid = b.payment_status === 'paid'
  const total = Math.max(0, Math.round(Number(b.total_price) || 0))
  let refundAmount = wasPaid ? total : 0
  if (wasPaid && opts.refundAmount != null) refundAmount = Math.min(total, Math.max(0, Math.round(Number(opts.refundAmount))))
  const refundPercent = wasPaid && total > 0 ? Math.round(refundAmount / total * 100) : 0
  const isFull = wasPaid && refundAmount >= total
  const noRefund = wasPaid && refundAmount === 0
  Object.assign(b, { status: 'cancelled', cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)', ...(wasPaid && !noRefund ? { payment_status: 'refund_pending' } : {}) })
  const r1 = wasPaid && !noRefund ? await call('process-refund', { booking_id: BID, reason: 'cancellation', ...(isFull ? {} : { amount: refundAmount }) }) : null
  const r2 = await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', customer_name: 'Test', motorcycle: 'Test Moto',
    cancellation_reason: 'Storno (Velín)', cancelled_by_source: 'velin', source: 'app', ...(wasPaid ? { refund_amount: refundAmount, refund_percent: refundPercent } : {}) })
  return { r1, r2, refundAmount }
}

/** DB trigger trg_notify_booking_cancelled_email (živé schéma, notify_booking_cancelled_email): po změně status → cancelled
 *  pg_net POST send-cancellation-email jen s booking_id, cancellation_reason, cancelled_by_source, source — BEZ refund_amount/percent. */
export function triggerCancelMail() {
  const b = bk()
  return call('send-cancellation-email', { booking_id: BID, cancellation_reason: b.cancellation_reason || '', cancelled_by_source: b.cancelled_by_source || '', source: b.booking_source || 'app' })
}

/** Velín storno včetně DB triggeru: UPDATE (commit) → pg_net T běží souběžně s process-refund z Velínu; pak Velínův send-cancellation-email. */
export async function velinCancelWithTrigger(opts: { refundAmount?: number } = {}) {
  const b = bk()
  const wasPaid = b.payment_status === 'paid'
  const total = Math.max(0, Math.round(Number(b.total_price) || 0))
  let refundAmount = wasPaid ? total : 0
  if (wasPaid && opts.refundAmount != null) refundAmount = Math.min(total, Math.max(0, Math.round(Number(opts.refundAmount))))
  const refundPercent = wasPaid && total > 0 ? Math.round(refundAmount / total * 100) : 0
  const isFull = wasPaid && refundAmount >= total
  const noRefund = wasPaid && refundAmount === 0
  Object.assign(b, { status: 'cancelled', cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)', ...(wasPaid && !noRefund ? { payment_status: 'refund_pending' } : {}) })
  const t = triggerCancelMail()
  const a = wasPaid && !noRefund ? call('process-refund', { booking_id: BID, reason: 'cancellation', ...(isFull ? {} : { amount: refundAmount }) }) : Promise.resolve(null)
  const [rt, r1] = await Promise.all([t, a])
  const r2 = await call('send-cancellation-email', { booking_id: BID, customer_email: 'zakaznik@example.com', customer_name: 'Test', motorcycle: 'Test Moto',
    cancellation_reason: 'Storno (Velín)', cancelled_by_source: 'velin', source: 'app', ...(wasPaid ? { refund_amount: refundAmount, refund_percent: refundPercent } : {}) })
  return { rt, r1, r2, refundAmount }
}

export function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} — expected ${B}, got ${A}`)
}
export function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
export function dump() {
  return { refunds: world().refunds.map((r) => ({ id: r.id, pi: r.payment_intent, amount: r.amount, status: r.status, src: r.metadata.mg_source, part: r.metadata.mg_part || '' })),
    cns: creditNotes().map((c) => ({ total: c.total, refund: c.stripe_refund_id })), status: bk().payment_status, stripe_refund_id: bk().stripe_refund_id,
    ops: opsMails().map((m) => m.subject) }
}
