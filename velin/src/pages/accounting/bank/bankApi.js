// Finance → Banka: veškerá komunikace s backendem (kontrakt Fio / QR plateb).
// ČTENÍ: tabulky fio_transactions, fio_sync_state, bank_payment_requests, fio_payment_orders (admin SELECT).
// ZÁPIS: výhradně auditované RPC admin_fio_* a akce edge funkce fio-sync — nikdy přímo do tabulek.
// Dokud není databázová část nasazená (chybí tabulka / RPC / akce), vrací volání { ok:false, missing:true }
// a obrazovka ukáže jen klidné upozornění — žádné opakované pokusy.
import { supabase } from '../../../lib/supabase'
import { debugAction } from '../../../lib/debugLog'
import { loadCompanyInfo } from '../../../lib/company'
import { TODO_STATUSES, MATCHED_STATUSES, daysUntil, sameIban } from './bankFormat'

const MISSING_RE = /PGRST20[245]|42P01|42703|42883|could not find the|does not exist|schema cache/i
const EDGE_MISSING = ['bank_unavailable', 'unknown_action', 'bad_action', 'invalid_action', 'not_found_action']

export function isMissing(error, status) {
  if (status === 404) return true
  return !!error && MISSING_RE.test(`${error.code || ''} ${error.message || ''}`)
}

function fromPostgrest({ data, error, status, count }) {
  if (error) {
    if (isMissing(error, status)) return { ok: false, missing: true, code: error.code || 'missing' }
    if (!status) return { ok: false, lost: true, code: 'network' }
    return { ok: false, code: status === 401 || status === 403 ? 'forbidden' : (error.code || 'error'), message: error.message }
  }
  if (data && typeof data === 'object' && data.success === false) return { ok: false, code: data.error || 'error', data }
  return { ok: true, data, count }
}

async function safe(fn) {
  try { return fromPostgrest(await fn()) } catch { return { ok: false, lost: true, code: 'network' } }
}
const rpc = (name, args) => safe(() => supabase.rpc(name, args))
// akce obsluhy se logují stejně jako jinde ve Velíně (debugAction → DebugPanel / debug_log při chybě)
const rpcAction = (label, name, args) => safe(() => debugAction('bank.' + label, 'Banka', () => supabase.rpc(name, args), args))

/**
 * Volání edge funkce fio-sync. `need` = klíč, který úspěšná odpověď MUSÍ mít (starší nasazená verze akci
 * nezná a jen by spustila synchronizaci — taková odpověď se NIKDY nesmí vyložit jako „spárováno“).
 * `log` = akce obsluhy (zapisuje se přes debugAction); čtení (návrhy, čekající platby) se neloguje.
 */
async function edge(body, need, log = false) {
  let data = null
  let status = 200
  try {
    const call = () => supabase.functions.invoke('fio-sync', { body })
    const res = log ? await debugAction('bank.' + body.action, 'Banka', call, body) : await call()
    data = res?.data ?? null
    if (res?.error) {
      const ctx = res.error.context
      status = Number(ctx?.status) || 0
      if (!status) return { ok: false, lost: true, code: 'network' }
      try { data = await ctx.json() } catch { data = null }
    }
  } catch { return { ok: false, lost: true, code: 'network' } }
  const code = (data && (data.error || data.code)) || null
  if (status === 404 || EDGE_MISSING.includes(code) || (status === 400 && !code)) return { ok: false, missing: true, code: code || 'missing' }
  if (status === 401 || status === 403) return { ok: false, code: 'forbidden' }
  if (data && data.success === false) return { ok: false, code: code || 'error', data }
  if (status >= 400 || !data || typeof data !== 'object') return { ok: false, code: code || `http_${status}`, data }
  if (need && !(need in data)) return { ok: false, missing: true, code: 'old_edge' }
  return { ok: true, data }
}

// ── Stav synchronizace ──
const TODO_OR = `status.in.(${TODO_STATUSES.join(',')}),and(followup.not.is.null,followup_done_at.is.null)`

function syncVerdict(s) {
  if (!s.last_ok_at && !s.last_run_at) return 'never'
  if (s.last_error && (Number(s.consecutive_failures) > 0 || !s.last_ok_at)) return 'failing'
  if (!s.last_ok_at || Date.now() - Date.parse(s.last_ok_at) > 20 * 60000) return 'stale'
  return 'ok'
}

async function normalizeOverview(o) {
  const state = o.state || {}
  let companyIban = o.company_iban || null
  let company = null
  try { company = await loadCompanyInfo() } catch { /* záložní údaje řeší lib/company */ }
  if (!companyIban) companyIban = company?.bank_iban || null
  const match = typeof o.account_match === 'boolean' ? o.account_match
    : (state.account_iban && companyIban ? sameIban(state.account_iban, companyIban) : null)
  return {
    state,
    sync: o.sync || syncVerdict(state),
    todo_count: Number(o.todo_count) || 0,
    waiting_requests: Number(o.waiting_requests) || 0,
    token_days_left: o.token_days_left ?? daysUntil(state.token_valid_until),
    pay_token_days_left: o.pay_token_days_left ?? daysUntil(state.pay_token_valid_until),
    company_iban: companyIban,
    company_account: company?.bank_account || null,
    account_match: match,
  }
}

/** Brána obrazovky: přehled z RPC admin_fio_overview, jinak přímo z fio_sync_state. missing = databázová část chybí. */
export async function loadOverview() {
  const r = await rpc('admin_fio_overview')
  if (r.ok && r.data && r.data.state) return { ok: true, overview: await normalizeOverview(r.data) }
  if (!r.ok && !r.missing) return r
  const st = await safe(() => supabase.from('fio_sync_state').select('*').eq('id', 1).maybeSingle())
  if (!st.ok || !st.data) return { ok: false, missing: true, code: st.code || 'missing' }
  const cnt = await safe(() => supabase.from('fio_transactions').select('fio_id', { count: 'exact', head: true }).or(TODO_OR))
  if (!cnt.ok) return { ok: false, missing: true, code: cnt.code || 'missing' }
  return { ok: true, overview: await normalizeOverview({ state: st.data, todo_count: cnt.count }) }
}

// ── Pohyby ──
export function parseAmount(raw) {
  const s = String(raw || '').replace(/[\s\u00a0]/g, '').replace(/kč$/i, '').replace(',', '.')
  return /^-?\d+(\.\d{1,2})?$/.test(s) ? Number(s) : null
}
/** Hledání VS / plátce / zprávy / částky → PostgREST or(); znaky se zvláštním významem se nahrazují mezerou. */
export function searchFilter(raw) {
  const text = String(raw || '').replace(/[,()"\\*%]/g, ' ').replace(/\s+/g, ' ').trim()
  const parts = []
  if (text) for (const col of ['vs', 'counter_name', 'message', 'counter_account']) parts.push(`${col}.ilike.%${text}%`)
  const num = parseAmount(raw)
  if (num !== null && num !== 0) parts.push(`amount.eq.${Math.abs(num)}`, `amount.eq.${-Math.abs(num)}`)
  return parts.length ? parts.join(',') : null
}

export async function loadMovements({ filter = 'todo', search = '', from = '', to = '', page = 1, perPage = 25 } = {}) {
  const r = await safe(() => {
    let q = supabase.from('fio_transactions').select('*', { count: 'exact' })
    if (filter === 'todo') q = q.or(TODO_OR)
    else if (filter === 'matched') q = q.in('status', MATCHED_STATUSES)
    else if (filter === 'ignored') q = q.eq('status', 'ignored')
    else if (filter === 'outgoing') q = q.lt('amount', 0)
    const s = searchFilter(search)
    if (s) q = q.or(s)
    if (from) q = q.gte('tx_date', from)
    if (to) q = q.lte('tx_date', to)
    return q.order('tx_date', { ascending: false }).order('fio_id', { ascending: false }).range((page - 1) * perPage, page * perPage - 1)
  })
  if (!r.ok) return r
  return { ok: true, rows: r.data || [], total: r.count || 0 }
}

export async function loadMovement(fioId) {
  const r = await safe(() => supabase.from('fio_transactions').select('*').eq('fio_id', fioId).maybeSingle())
  return r.ok ? { ok: true, row: r.data || null } : r
}

/** Čísla objednávek k pohybům na stránce (odkaz „Spárováno s“). Chyba = prázdná mapa. */
export async function loadOrderNumbers(orderIds) {
  const ids = [...new Set((orderIds || []).filter(Boolean))]
  if (!ids.length) return {}
  const r = await safe(() => supabase.from('shop_orders').select('id, order_number').in('id', ids))
  return Object.fromEntries(((r.ok && r.data) || []).map(o => [o.id, o.order_number]))
}

/** K čemu je pohyb přiřazený (rezervace / objednávka / požadavek) — jen pro zobrazení v detailu. */
export async function loadTargets(tx) {
  const out = { booking: null, order: null, request: null }
  const jobs = []
  if (tx.booking_id) jobs.push(safe(() => supabase.from('bookings')
    .select('id, status, payment_status, total_price, start_date, end_date, booking_kind, profiles(full_name, email)')
    .eq('id', tx.booking_id).maybeSingle()).then(r => { if (r.ok) out.booking = r.data }))
  if (tx.order_id) jobs.push(safe(() => supabase.from('shop_orders')
    .select('id, order_number, customer_name, customer_email, total, status, payment_status')
    .eq('id', tx.order_id).maybeSingle()).then(r => { if (r.ok) out.order = r.data }))
  if (tx.request_id) jobs.push(safe(() => supabase.from('bank_payment_requests')
    .select('id, kind, vs, amount, status, change_kind, expires_at, booking_id, order_id')
    .eq('id', tx.request_id).maybeSingle()).then(r => { if (r.ok) out.request = r.data }))
  await Promise.all(jobs)
  return out
}

/** Historie zásahů obsluhy (admin_audit_log, zapisují RPC admin_fio_*) + jména účtů. */
export async function loadHistory(fioId) {
  const r = await safe(() => supabase.from('admin_audit_log').select('id, admin_id, action, old_data, new_data, created_at')
    .eq('entity_type', 'fio_transaction').eq('new_data->>fio_id', String(fioId)).order('created_at', { ascending: false }).limit(30))
  const rows = (r.ok && r.data) || []
  const ids = [...new Set(rows.map(x => x.admin_id).filter(Boolean))]
  let names = {}
  if (ids.length) {
    const a = await safe(() => supabase.from('admin_users').select('id, name, email').in('id', ids))
    names = Object.fromEntries(((a.ok && a.data) || []).map(u => [u.id, (u.name || '').trim() || u.email || '']))
  }
  return rows.map(x => ({ ...x, admin_name: names[x.admin_id] || (x.admin_id ? 'obsluha' : 'automat') }))
}

export async function loadAdminName(id) {
  if (!id) return ''
  const a = await safe(() => supabase.from('admin_users').select('id, name, email').eq('id', id).maybeSingle())
  return (a.ok && a.data && ((a.data.name || '').trim() || a.data.email)) || ''
}

// ── Platební příkazy (vratky) ──
export async function loadPaymentOrders() {
  const r = await safe(() => supabase.from('fio_payment_orders').select('*').order('created_at', { ascending: false }).limit(200))
  if (!r.ok) return r
  const rows = r.data || []
  const cnIds = [...new Set(rows.map(o => o.credit_note_id).filter(Boolean))]
  let numbers = {}
  if (cnIds.length) {
    const inv = await safe(() => supabase.from('invoices').select('id, number').in('id', cnIds))
    numbers = Object.fromEntries(((inv.ok && inv.data) || []).map(i => [i.id, i.number]))
  }
  return { ok: true, rows: rows.map(o => ({ ...o, credit_note_number: numbers[o.credit_note_id] || null })) }
}

// ── Akce (RPC s auditem) ──
export const ignoreMovement = (fioId, note) => rpcAction('ignore', 'admin_fio_ignore_transaction', { p_fio_id: fioId, p_note: note })
export const reopenMovement = (fioId) => rpcAction('reopen', 'admin_fio_reopen_transaction', { p_fio_id: fioId })
export const ackFollowup = (fioId, note) => rpcAction('ack_followup', 'admin_fio_ack_followup', { p_fio_id: fioId, p_note: note || null })
export const setTokenExpiry = (validUntil, payValidUntil, autoProlong) => rpcAction('token_expiry', 'admin_fio_set_token_expiry',
  { p_valid_until: validUntil || null, p_pay_valid_until: payValidUntil || null, p_auto_prolong: autoProlong })

// ── Akce edge funkce fio-sync ──
export const syncNow = () => edge({ action: 'sync' }, null, true)
export const pairMovement = ({ fioId, targetType, targetId, acceptAmount = false, note = null }) =>
  edge({ action: 'pair', fio_id: fioId, target_type: targetType, target_id: targetId, accept_amount: !!acceptAmount, note }, 'result', true)
export const processMovement = (fioId) => edge({ action: 'process', fio_id: fioId }, 'result', true)
export const suggestTargets = (fioId, limit = 8) => edge({ action: 'suggest', fio_id: fioId, limit }, 'candidates')
export const loadWaiting = () => edge({ action: 'waiting' }, 'items')
