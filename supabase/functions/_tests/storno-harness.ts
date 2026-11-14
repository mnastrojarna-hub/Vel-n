// ===== _tests/storno-harness.ts =====
// Flow harness storna (HOTFIX 2026-10-29): SKUTEČNÉ handlery process-refund, webhook-receiver
// a send-cancellation-email nad falešným Stripe + in-memory DB (import mapa storno-flow-map.json).
// Volání mezi edge funkcemi (fetch …/functions/v1/…) jdou přímo do handlerů; Resend se zachytí.
// Dispečeři kopírují přesná těla volajících: Velín cancelBookingFromVelin (admin JWT), RPC
// cancel_booking_tracked (UPDATE + booking_cancellations v jedné transakci + pg_net), DB trigger
// trg_notify_booking_cancelled_email (pg_net bez e-mailu a bez vratky), webhook charge.refunded.
// STORNO_FN_DIR=<…/supabase/functions> spustí tytéž testy proti jinému stromu (např. main).
// deno-lint-ignore-file no-explicit-any
import { World, setWorld, world } from './storno-fake-stripe.ts'
import { Db } from './storno-fake-db.ts'

const dir = Deno.env.get('STORNO_FN_DIR')
export const FN = dir ? `file://${dir.replace(/\/$/, '')}/` : new URL('../', import.meta.url).href
const SB = 'https://fake.supabase.test'
const SVC = 'svc-storno-test'
Deno.env.set('SUPABASE_URL', SB)
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
Deno.env.set('SUPABASE_ANON_KEY', 'anon-storno-test')
Deno.env.set('STRIPE_SECRET_KEY', 'sk_test_storno')
Deno.env.set('STRIPE_WEBHOOK_SECRET', 'whsec_storno')
Deno.env.set('RESEND_API_KEY', 're_storno_test')
for (const k of ['PDFSHIFT_API_KEY', 'FIO_PAYMENT_TOKEN', 'FIO_API_TOKEN']) Deno.env.delete(k)

export const BID = '11111111-2222-4333-8444-555555555555'
const UID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
export const ADMIN_ID = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff'
const ADMIN = 'adm.jwt.token'
/** přihlášený ZÁKAZNÍK (vlastník rezervace) — appka po zkrácení (i2) */
const CUST = 'cus.jwt.token'
export const EMAIL = 'zakaznik@example.com'
export const TOTAL = 3000
const g = globalThis as any
type Handler = (req: Request) => Promise<Response>
const handlers: Record<string, Handler> = {}
export const mails: Array<{ to: string; html: string; attachments?: string[] }> = []
/** interní maily obsluze (process-refund sendOpsMail → send-email; i1) */
export const opsMails: Array<{ to: string; subject: string; html: string }> = []
/** HTTP stavy odpovědí webhook-receiver z deliver() (i1: 500 = Stripe doručí znovu) */
export const webhookStatuses: number[] = []

g.fetch = async (input: any, init?: any) => {
  const url = typeof input === 'string' ? input : input.url
  if (url.startsWith(SB + '/functions/v1/')) {
    const name = url.slice((SB + '/functions/v1/').length).split('?')[0]
    const h = handlers[name]
    if (!h && name === 'send-email') {
      try { const b = JSON.parse(String(init?.body || '{}')); opsMails.push({ to: String(b.to), subject: String(b.subject || ''), html: String(b.raw_html || '') }) } catch { /* ignore */ }
      return new Response('{"ok":true}', { status: 200 })
    }
    if (!h) return new Response('{"ok":true}', { status: 200 })
    const res = await h(new Request(url, init)); const txt = await res.text()
    return new Response(txt, { status: res.status })
  }
  if (url.startsWith('https://api.resend.com')) {
    const b = JSON.parse(String(init?.body || '{}'))
    mails.push({ to: String(b.to), html: String(b.html || ''), attachments: (Array.isArray(b.attachments) ? b.attachments : []).map((a: any) => String(a?.filename || '')) })
    return new Response('{"id":"em_1"}', { status: 200 })
  }
  return new Response('{}', { status: 200 })
}
async function load(name: string) {
  let h: Handler | null = null
  g.__STORNO_CAPTURE = (x: Handler) => { h = x }
  const orig = Deno.serve
  ;(Deno as any).serve = (x: any) => { h = typeof x === 'function' ? x : x?.handler; return { finished: Promise.resolve(), shutdown() {} } }
  try { await import(`${FN}${name}/index.ts`) } finally { (Deno as any).serve = orig }
  if (!h) throw new Error('handler se nezaregistroval: ' + name)
  handlers[name] = h
}
const tier = await import(`${FN}send-cancellation-email/refund-tier.ts`)
export async function boot() { if (!handlers['process-refund']) for (const n of ['process-refund', 'webhook-receiver', 'send-cancellation-email']) await load(n) }
/** i3: další handler do téhož světa (např. send-booking-email — mail úpravy s vratkou) */
export async function loadFn(name: string) { if (!handlers[name]) await load(name) }

export let skew = 0 // virtuální posun hodin (okna claimů a 15min dedup dobropisů)
const db = (): Db => g.__STORNO_DB
const pragueDay = (ms: number) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Prague' }).format(new Date(ms))
/** timestamptz jak ho vrací PostgREST (mikrosekundy, +00:00) */
export const pgNow = () => new Date(Date.now()).toISOString().replace('Z', `${String(Math.floor(Math.random() * 1000)).padStart(3, '0')}+00:00`)
/** DB now() při INSERTu z PostgRESTu (Velín): vždy jiný okamžik než milisekundový čas z prohlížeče */
export const dbNow = () => new Date(Date.now()).toISOString().replace('Z', `${String(1 + Math.floor(Math.random() * 999)).padStart(3, '0')}+00:00`)

/** Zaplacený doplatek úpravy (další PaymentIntent téže rezervace — vratka z více plateb, dev f1–f3). */
export type ExtraPi = { id: string; czk: number; type?: string }
export function fresh(days: number, o: { gear?: boolean; booking?: Record<string, any>; extra?: ExtraPi[] } = {}) {
  const w = new World(); setWorld(w); w.addPi('pi_orig', TOTAL, { booking_id: BID, type: 'booking' })
  // doplatky: mladší než původní platba, zapsané (payment_ref v historii), process-payment ukládá POSLEDNÍ do stripe_payment_intent_id
  const extra = o.extra || []
  extra.forEach((e, i) => w.addPi(e.id, e.czk, { booking_id: BID, type: e.type || 'extension', chg_hash: 'h_' + e.id }, -86400 * (10 - i)))
  const total = TOTAL + extra.reduce((s, e) => s + e.czk, 0)
  const start = `${pragueDay(Date.now() + days * 86400_000)}T00:00:00+00:00`
  const dp = (amount: number, n: number) => ({ id: crypto.randomUUID(), booking_id: BID, type: 'payment_receipt', status: 'issued', total: amount,
    number: `DP-2026-${1000 + n}`, issue_date: '2026-10-01', created_at: new Date(Date.now() - 86400_000 + n).toISOString() })
  const d = new Db({
    bookings: [{ id: BID, user_id: UID, status: 'reserved', payment_status: 'paid', total_price: total,
      stripe_payment_intent_id: extra.length ? extra[extra.length - 1].id : 'pi_orig',
      stripe_session_id: null, stripe_refund_id: null, payment_method: 'card', pay_channel: 'card', card_brand: null, card_last4: null,
      start_date: start, end_date: `${pragueDay(Date.now() + (days + 2) * 86400_000)}T00:00:00+00:00`, pickup_time: '09:00:00', refund_pickup_time: '09:00:00',
      booking_source: 'app', moto_id: 'moto-1', booking_kind: 'moto', language: 'cs', cancelled_at: null,
      modification_history: extra.map((e) => ({ type: 'edit', payment_ref: e.id, price_diff: e.czk })),
      ...(o.gear ? { booking_kind: 'gear', moto_id: null, gear_per_day: 1000, gear_lines: [{ key: 'helmet', size: 'L', price_per_day: 1000 }], helmet_size: 'L' } : {}),
      ...(o.booking || {}) }],
    profiles: [{ id: UID, full_name: 'Test Zákazník', email: EMAIL }],
    admin_users: [{ id: ADMIN_ID, role: 'admin', active: true }],
    motorcycles: [{ id: 'moto-1', model: 'Test Moto' }],
    invoices: [dp(TOTAL, 0), ...extra.map((e, i) => dp(e.czk, i + 1))],
  })
  d.users.set(ADMIN, { id: ADMIN_ID })
  d.users.set(CUST, { id: UID })
  d.rpcs.claim_email_send = (a) => { // živá RPC: INSERT … ON CONFLICT DO UPDATE … WHERE locked_at < now() - okno
    const now = Date.now() + skew, rows = d.rows('email_send_locks')
    const r = rows.find((x) => x.booking_id === a.p_booking_id && x.template_slug === a.p_slug)
    if (!r) { rows.push({ booking_id: a.p_booking_id, template_slug: a.p_slug, locked_at: now }); return { data: true, error: null } }
    if (now - r.locked_at > Math.max(1, a.p_window_minutes ?? 30) * 60_000) { r.locked_at = now; return { data: true, error: null } }
    return { data: false, error: null }
  }
  let n = 0
  d.rpcs.next_document_number = () => ({ data: `DB-2026-${String(++n).padStart(4, '0')}`, error: null })
  d.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  d.beforeInsert = (t, r) => { // _cap_refund_to_paid (BEFORE INSERT invoices) + i1: unikátní index dobropisů (volitelně)
    if (t !== 'invoices' || r.type !== 'credit_note') return
    const inv = d.rows('invoices'), live = (x: any) => x.booking_id === r.booking_id && x.status !== 'cancelled'
    if (uniqueCnIndex && r.stripe_refund_id && inv.some((x) => x.type === 'credit_note' && x.status !== 'cancelled' && x.stripe_refund_id === r.stripe_refund_id)) {
      return { code: '23505', message: 'duplicate key value violates unique constraint "uq_invoices_credit_note_refund"' }
    }
    const paid = inv.filter((x) => live(x) && x.type === 'payment_receipt').reduce((s, x) => s + Number(x.total || 0), 0)
    const back = inv.filter((x) => live(x) && x.type === 'credit_note').reduce((s, x) => s + Math.abs(Number(x.total || 0)), 0)
    if (paid > 0 && Math.abs(Number(r.total)) > paid - back) { r.total = -(paid - back); r.subtotal = r.total }
  }
  g.__STORNO_DB = d; skew = 0; mails.length = 0; opsMails.length = 0; webhookStatuses.length = 0; uniqueCnIndex = false
}
/** i1: simulace unikátního indexu uq_invoices_credit_note_refund (SQL návrh 20261105a) v falešné DB */
export let uniqueCnIndex = false
export function setUniqueCnIndex(on: boolean) { uniqueCnIndex = on }
export const bk = () => db().rows('bookings')[0]
/** čas plyne: vyprší claim mailu (30 min) i 15min okna čerstvých dobropisů */
export function advance(min: number) {
  skew += min * 60_000
  for (const t of ['invoices', 'debug_log', 'sent_emails', 'message_log']) for (const r of db().rows(t)) r.created_at = new Date(Date.parse(r.created_at) - min * 60_000).toISOString()
  for (const r of world().refunds) r.created -= min * 60 // Stripe: dřívější vratky jsou o `min` starší
  for (const v of world().byKey.values()) v.refund.created -= min * 60 // i5r2: i přehraná odpověď (idempotency) nese původní čas vzniku
  for (const e of world().events) e.created -= min * 60
  // i6r1: i okamžik storna (dobropisy storna vznikly PO něm — okno „dobropisy tohoto storna“ od cancelled_at − 2 min) a jeho
  // značky (booking_cancellations.created_at, mg_cancel_at vratek) — o celé minuty, formát (µs, +00:00) beze změny
  for (const b of db().rows('bookings')) b.cancelled_at = shiftTs(b.cancelled_at, min)
  for (const c of db().rows('booking_cancellations')) c.created_at = shiftTs(c.created_at, min)
  for (const md of [...world().refunds.map((r) => r.metadata), ...[...world().byKey.values()].map((v) => v.refund.metadata)]) {
    if (md?.mg_cancel_at) md.mg_cancel_at = shiftTs(md.mg_cancel_at, min)
  }
}
/** timestamptz o `min` minut dřív se stejným zlomkem sekundy i zónou (Z / +00:00); jiný tvar beze změny */
function shiftTs(v: any, min: number): any {
  const m = typeof v === 'string' ? /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?(Z|\+00:00)$/.exec(v) : null
  if (!m) return v
  return new Date(Date.parse(m[1] + 'Z') - min * 60_000).toISOString().slice(0, 19) + (m[2] || '') + m[3]
}
export async function later<T>(ms: number, fn: () => Promise<T>): Promise<T> {
  const orig = Date.now; Date.now = () => orig() + ms
  try { return await fn() } finally { Date.now = orig }
}
export async function call(fn: string, body: any, as: 'service' | 'admin' | 'customer' = 'service'): Promise<any> {
  const token = as === 'admin' ? ADMIN : as === 'customer' ? CUST : SVC
  const res = await handlers[fn](new Request(`${SB}/functions/v1/${fn}`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: JSON.stringify(body) }))
  const t = await res.text(); try { return JSON.parse(t) } catch { return t }
}
/** Stripe → webhook-receiver (všechny čekající události, `times` = opakované doručení) */
export async function deliver(events = world().takeEvents(), times = 1) {
  for (const e of events) for (let i = 0; i < times; i++) {
    const res = await handlers['webhook-receiver'](new Request(`${SB}/functions/v1/webhook-receiver`, { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'stripe-signature': 't=1,v1=x' }, body: JSON.stringify(e) }))
    webhookStatuses.push(res.status)
  }
  return events
}

// ── výsledky ──
export const refundedKc = () => world().refundedTotal() / 100
export const creditNotes = () => db().rows('invoices').filter((x) => x.type === 'credit_note' && x.status !== 'cancelled')
export const cnKc = () => creditNotes().reduce((s, x) => s + Math.abs(Number(x.total || 0)), 0)
/** storno maily zákazníkovi: částka a % z textu (null = mail bez vratky) */
export function customerMails() {
  return mails.filter((m) => m.to === EMAIL).map((m) => {
    const x = /<strong>([\d\s ]+) Kč<\/strong> \((\d+) %\)/.exec(m.html)
    return x ? { amount: Number(x[1].replace(/[\s ]/g, '')), pct: Number(x[2]) } : { amount: null, pct: null }
  })
}

export { tier }
export { world }
export const rows = (t: string) => db().rows(t)
/** INSERT přes PostgREST (created_at = čas DB) */
export const insert = (t: string, row: Record<string, any>) => db().from(t).insert(row)
