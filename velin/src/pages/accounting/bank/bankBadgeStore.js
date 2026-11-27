// Odznak „K vyřešení“ (počet bankovních pohybů čekajících na obsluhu) — záložka Banka ve Financích a položka
// menu Finance. Jeden sdílený výpočet pro všechny odběratele (vzor lib/ratingAlerts.js).
// Dokud databázová část neexistuje, zeptá se JEDNOU a dalších 30 minut se neptá vůbec (žádné opakované
// chyby v konzoli ani dotazy na neexistující tabulky); jakmile ji otevřená záložka Banka najde, odznak ožije.
import { supabase } from '../../../lib/supabase'
import { loadOverview } from './bankApi'

const SKIP_KEY = 'velin_bank_missing_at'
const SKIP_MS = 30 * 60000
const listeners = new Set()
let state = { count: 0, alert: false }
let available = null
let channel = null
let poll = null
let timer = null
let running = false
let reportedAt = 0

const emit = () => listeners.forEach(fn => fn(state))

function fromOverview(o) {
  const days = o.token_days_left
  return { count: Number(o.todo_count) || 0, alert: o.sync === 'failing' || o.sync === 'stale' || o.account_match === false || (days !== null && days !== undefined && days < 7) }
}
function skipUntil() {
  try { return Number(sessionStorage.getItem(SKIP_KEY) || 0) + SKIP_MS } catch { return 0 }
}
function remember(missing) {
  try { if (missing) sessionStorage.setItem(SKIP_KEY, String(Date.now())); else sessionStorage.removeItem(SKIP_KEY) } catch { /* soukromý režim */ }
}

function startLive() {
  if (channel || !listeners.size) return
  channel = supabase.channel('velin-bank-badge')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'fio_transactions' }, () => schedule())
    .subscribe()
  poll = setInterval(() => { if (!document.hidden && Date.now() - reportedAt > 100000) recompute() }, 120000)
}
function stopLive() {
  clearTimeout(timer); clearInterval(poll)
  if (channel) supabase.removeChannel(channel)
  channel = null; poll = null
}

async function recompute() {
  if (running) return
  running = true
  try {
    const r = await loadOverview()
    if (r.ok) { available = true; remember(false); state = fromOverview(r.overview); startLive(); emit() }
    else if (r.missing) { available = false; remember(true); state = { count: 0, alert: false }; stopLive(); emit() }
    // jiná chyba (výpadek sítě) → ponech poslední stav
  } catch { /* odznak nesmí shodit menu */ } finally { running = false }
}
function schedule(delay = 1500) {
  clearTimeout(timer)
  timer = setTimeout(recompute, delay)
}

/** Odběr { count, alert }; vrací funkci pro odhlášení. */
export function subscribeBankBadge(fn) {
  listeners.add(fn)
  fn(state)
  if (available === true) startLive()
  else if (Date.now() > skipUntil()) recompute()
  return () => {
    listeners.delete(fn)
    if (!listeners.size) stopLive()
  }
}

/** Záložka Banka právě načetla přehled — odznak ho převezme (bez dalšího dotazu). */
export function reportBankOverview(overview) {
  if (!overview) return
  available = true
  reportedAt = Date.now()
  remember(false)
  state = fromOverview(overview)
  startLive()
  emit()
}
