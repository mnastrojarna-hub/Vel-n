// ===== _tests/bank-helpers.ts =====
// Pomůcky testů bankovních plateb (Fio synchronizace, požadavky na platbu, QR): in-memory DB
// (LooseDb + primární klíč fio_transactions), falešné hodiny, náhrada fetch (Fio API + volání mezi
// edge funkcemi) a emulace RPC z návrhů SQL 20261130a1/a2/b (zámek běhu, claim pohybu, požadavky).
// Fungují pod oběma import mapami (storno-flow-map.json i gear-flow-map.json): createClient z mapy
// vrací aktuální DB z globalThis. Bez mapy se flow testy přeskočí (MAPPED = false).
// deno-lint-ignore-file no-explicit-any
import { LooseDb, stubFetch } from './gear-fake.ts'

export type Row = Record<string, any>
export const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
export const FN = new URL('../', import.meta.url).href
export const SB = 'https://fake.supabase.test'
export const SVC = 'svc-bank-test'
if (MAPPED) {
  Deno.env.set('SUPABASE_URL', SB)
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
  Deno.env.set('SUPABASE_ANON_KEY', 'anon-bank-test')
  if (!Deno.env.get('STRIPE_SECRET_KEY')) Deno.env.set('STRIPE_SECRET_KEY', 'sk_test_bank')
}

export function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
export function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed: ${msg}`) }

/** Falešné hodiny testu (ms). */
export const clock = { t: Date.parse('2026-12-01T10:00:00Z') }
export const now = () => clock.t
export const isoNow = () => new Date(clock.t).toISOString()

const failing = (err: { code?: string; message: string }): any => {
  const res = Promise.resolve({ data: null, error: err })
  const p: any = new Proxy(function () {}, { get: (_t, k) => (k === 'then' ? res.then.bind(res) : () => p) })
  return p
}

/** LooseDb + PK fio_transactions (upsert přeskakuje duplicity) + volitelné chyby zápisu. */
export class BankDb extends LooseDb {
  /** chyba hromadného / jednotlivého zápisu pohybů (simulace selhání INSERT) */
  failUpsert: ((rows: Row[]) => { message: string } | null) | null = null
  /** chyba UPDATE dané tabulky (např. překryv rezervací při zápisu zaplacené změny) */
  failUpdate: ((table: string, patch: Row) => { code?: string; message: string } | null) | null = null
  override from(t: string): any {
    const q: any = super.from(t)
    // deno-lint-ignore no-this-alias
    const db = this
    return new Proxy(q, {
      get(target, prop) {
        if (prop === 'update') {
          return (patch: Row) => { const e = db.failUpdate?.(t, patch); return e ? failing(e) : target.update(patch) }
        }
        if (prop === 'upsert' && t === 'fio_transactions') {
          return (rows: Row | Row[]) => {
            const list = Array.isArray(rows) ? rows : [rows]
            const err = db.failUpsert?.(list)
            if (err) return failing(err)
            const fresh = list.filter((r) => !db.rows(t).some((x) => Number(x.fio_id) === Number(r.fio_id)))
            return target.insert(fresh.map((r) => ({ id: 'tx' + r.fio_id, ...r })))
          }
        }
        const v = target[prop]
        return typeof v === 'function' ? v.bind(target) : v
      },
    })
  }
}

type Handler = (req: Request) => Response | Promise<Response>
/** Načte modul s `serve(handler)` a vrátí zachycený handler (funguje pod oběma import mapami). */
export async function loadHandler(spec: string): Promise<Handler> {
  const g = globalThis as any
  let h: Handler | null = null
  const before = (g.__gearHandlers || []).length
  const prev = g.__STORNO_CAPTURE
  g.__STORNO_CAPTURE = (x: Handler) => { h = x }
  try { await import(spec) } finally { g.__STORNO_CAPTURE = prev }
  h = h || (g.__gearHandlers || [])[before] || null
  if (!h) throw new Error('handler se nezaregistroval: ' + spec)
  return h
}
export const post = async (h: Handler, body: Row, token = SVC) => {
  const res = await h(new Request('http://x/fn', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }))
  const txt = await res.text()
  let json: any = null
  try { json = JSON.parse(txt) } catch { /* text */ }
  return { status: res.status, json, txt }
}

export function useDb(db: LooseDb) {
  const g = globalThis as any
  g.__STORNO_DB = db
  g.__gearFakeDb = db
  return db
}

/** Emulace RPC ze SQL 20261130a1 (stav synchronizace, zámek, claim) nad BankDb. */
export function withState(db: BankDb, state: Row = {}) {
  const s: Row = { id: 1, lease_until: null, consecutive_failures: 0, last_ok_at: null, last_error: null, reconcile_since: null,
    last_reconcile_on: null, reconcile_tries: 0, ends: [] as Row[], ...state }
  db.tables.fio_sync_state = [s]
  db.rpcs.fio_sync_begin = (a: Row) => {
    if (s.lease_until && Date.parse(s.lease_until) > now()) return { data: { acquired: false }, error: null }
    s.lease_until = new Date(now() + (Number(a.p_lease_seconds) || 180) * 1000).toISOString()
    const today = new Date(now()).toISOString().slice(0, 10)
    const due = !!s.reconcile_since || (s.force_daily === true && s.last_reconcile_on !== today)
    return { data: { acquired: true, reconcile_due: due, reconcile_from: '2026-11-26', reconcile_to: today }, error: null }
  }
  db.rpcs.fio_sync_end = (a: Row) => {
    s.ends.push(a)
    s.lease_until = null
    if (a.p_error === 'rate_limited') return { data: { success: true, skipped: 'rate_limited' }, error: null }
    if (a.p_ok === true) {
      s.last_ok_at = isoNow(); s.consecutive_failures = 0; s.last_error = null
      if (a.p_info?.reconciled) { s.reconcile_since = null; s.last_reconcile_on = new Date(now()).toISOString().slice(0, 10) }
    } else {
      s.consecutive_failures++; s.last_error = a.p_error
      if (a.p_info?.recover) s.reconcile_since = s.reconcile_since || isoNow()
    }
    return { data: { success: true }, error: null }
  }
  db.rpcs.fio_claim_transactions = (a: Row) => {
    const row = db.rows('fio_transactions').filter((r) => Number(r.amount) > 0 && (r.status === 'new' || (r.status === 'error' && !(Number(r.attempts) > 0)))
      && (!r.claimed_until || Date.parse(r.claimed_until) <= now()) && (a.p_fio_id == null || Number(r.fio_id) === Number(a.p_fio_id)))
      .sort((x, y) => Number(x.fio_id) - Number(y.fio_id))[0]
    if (!row) return { data: [], error: null }
    row.claimed_until = new Date(now() + 150_000).toISOString()
    return { data: [{ ...row }], error: null }
  }
  return s
}

/** Fio pohyb ve tvaru odpovědi API (column*). */
export function fioTx(id: number, amount: number, o: { vs?: string | null; name?: string; msg?: string; currency?: string; account?: string; date?: string } = {}) {
  const c = (value: unknown) => (value == null ? null : { value, name: 'x', id: 0 })
  return { column22: c(id), column0: c(o.date || '2026-12-01+0100'), column1: c(amount), column14: c(o.currency || 'CZK'), column5: c(o.vs ?? null),
    column2: c(o.account || '123456789'), column3: c('0800'), column10: c(o.name || 'NOVAK JAN'), column16: c(o.msg ?? null), column8: c('Bezhotovostní příjem') }
}
export const statement = (txs: unknown[], info: Row = {}) => JSON.stringify({ accountStatement: {
  info: { accountId: '2303580494', bankId: '2010', currency: 'CZK', iban: 'CZ8320100000002303580494', idFrom: null, idTo: null, idLastDownload: 100, ...info },
  transactionList: { transaction: txs } } })

export type Net = { calls: Array<{ url: string; body: Row | null }>; restore: () => void; fio: Array<() => Response>; edge: Record<string, (b: Row | null) => Row>; mails: Row[] }
/** Náhrada fetch: Fio API (fronta odpovědí `fio`), volání edge funkcí (send-email, generate-invoice…). */
export function net(): Net {
  const n: Net = { calls: [], restore: () => {}, fio: [], edge: {}, mails: [] }
  const st = stubFetch((url, body) => {
    if (url.startsWith('https://fioapi.fio.cz/')) {
      const next = n.fio.shift()
      return next ? next() : new Response(statement([]), { status: 200 })
    }
    if (url.startsWith(SB + '/functions/v1/')) {
      const name = url.slice((SB + '/functions/v1/').length).split('?')[0]
      if (name === 'send-email') n.mails.push(body || {})
      const reply = n.edge[name] ? n.edge[name](body) : { success: true }
      return new Response(JSON.stringify(reply), { status: 200 })
    }
    if (url.startsWith(SB + '/auth/v1/')) return new Response('{}', { status: 401 })
    return new Response('{}', { status: 200 })
  })
  n.calls = st.calls
  n.restore = st.restore
  return n
}
export const edgeCalls = (n: Net, fn: string) => n.calls.filter((c) => c.url === `${SB}/functions/v1/${fn}`)
export const fioCalls = (n: Net) => n.calls.filter((c) => c.url.startsWith('https://fioapi.fio.cz/'))
export const opsSubjects = (n: Net) => n.mails.filter((m) => m.to === 'info@motogo24.cz').map((m) => String(m.subject))

export const UID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
export const BID = '11111111-2222-4333-8444-555555555555'
export const OID = '99999999-2222-4333-8444-555555555555'
export const RID = '77777777-2222-4333-8444-555555555555'

export const booking = (o: Row = {}): Row => ({ id: BID, status: 'pending', payment_status: 'unpaid', payment_method: null, total_price: 3000, booking_source: 'web',
  user_id: UID, moto_id: 'm1', booking_kind: 'moto', start_date: '2026-12-20', end_date: '2026-12-22', docs_completed_at: '2026-11-30T10:00:00Z',
  cancelled_by_source: null, payment_vs: '10000123', pay_channel: 'qr', mod_surcharge_due: 0, mod_surcharge_vs: null, created_at: '2026-12-01T08:00:00Z',
  language: 'cs', modification_history: [], motorcycles: { model: 'BMW R 1250 GS', manual_url: '' }, profiles: { full_name: 'Jan Novák', email: 'jan@example.com' }, ...o })
export const order = (o: Row = {}): Row => ({ id: OID, order_number: 'MG-2026-0042', status: 'new', payment_status: 'pending', payment_method: 'bank_transfer', total: 1000,
  customer_name: 'Petra Malá', customer_email: 'petra@example.com', customer_id: null, notes: 'Elektronický poukaz', language: 'cs', created_at: '2026-12-01T08:00:00Z', ...o })
export const request = (o: Row = {}): Row => ({ id: RID, kind: 'shop_order', vs: '10000200', amount: 1000, booking_id: null, order_id: OID, chg: null, srv: null,
  status: 'pending', expires_at: '2026-12-08T08:00:00Z', created_at: '2026-12-01T08:00:00Z', fio_id: null, result: null, language: 'cs', ...o })
export const txRow = (id: number, amount: number, o: Row = {}): Row => ({ fio_id: id, tx_date: '2026-12-01', amount, currency: 'CZK', vs: null, counter_account: '123456789', counter_bank: '0800',
  counter_name: 'NOVAK JAN', message: null, tx_type: 'Bezhotovostní příjem', status: 'new', booking_id: null, note: null, processed_at: null, ...o })
export const tx = (db: LooseDb, id: number) => db.rows('fio_transactions').find((r) => Number(r.fio_id) === id) as Row
