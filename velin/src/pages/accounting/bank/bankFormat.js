// Finance → Banka: popisky stavů a důvodů (1:1 s kontraktem fio-sync / fio_transactions) + formátování.
// Formát peněz a dat je shodný se zbytkem Velína (toLocaleString('cs-CZ')), jen částky z banky
// ukazují i haléře, když nejsou celé.

export const TODO_STATUSES = ['no_match', 'amount_mismatch', 'needs_review', 'error']
export const MATCHED_STATUSES = ['confirmed_booking', 'confirmed_surcharge', 'confirmed_order', 'confirmed_change', 'already_paid']

const GREEN = { color: '#1a8a18', bg: '#dcfce7' }
const AMBER = { color: '#b45309', bg: '#fef3c7' }
const RED = { color: '#dc2626', bg: '#fee2e2' }
const GREY = { color: '#1a2e22', bg: '#f3f4f6' }
const BLUE = { color: '#2563eb', bg: '#dbeafe' }

export const STATUS = {
  new: { label: 'Čeká na zpracování', ...BLUE },
  outgoing: { label: 'Odchozí', ...GREY },
  confirmed_booking: { label: 'Spárováno — rezervace', ...GREEN },
  confirmed_surcharge: { label: 'Spárováno — doplatek', ...GREEN },
  confirmed_order: { label: 'Spárováno — objednávka / poukaz', ...GREEN },
  confirmed_change: { label: 'Spárováno — úprava rezervace', ...GREEN },
  already_paid: { label: 'Už bylo potvrzeno ručně', ...GREEN },
  no_match: { label: 'Nespárováno', ...RED },
  amount_mismatch: { label: 'Nižší částka', ...AMBER },
  needs_review: { label: 'Ke kontrole', ...AMBER },
  error: { label: 'Chyba zpracování', ...RED },
  ignored: { label: 'Ignorováno', ...GREY },
}
export const statusOf = (s) => STATUS[s] || { label: s || '—', ...GREY }

// Důvod automatického rozhodnutí → co má obsluha udělat.
export const REASON = {
  no_vs: 'Platba bez variabilního symbolu — spárujte ji ručně.',
  vs_not_found: 'Variabilní symbol neodpovídá žádné čekající platbě — spárujte ji ručně.',
  foreign_currency: 'Platba v cizí měně — spárujte ji ručně.',
  underpaid: 'Přišlo méně, než se čekalo — počkejte na doplatek, nebo přijměte nižší částku.',
  overpaid: 'Přeplatek — rozdíl vraťte zákazníkovi.',
  partial_sum: 'Dřívější částečná platba, kterou dorovnal další pohyb.',
  accepted_lower: 'Obsluha přijala nižší částku.',
  duplicate: 'Duplicitní platba (cíl už je zaplacený) — vraťte ji.',
  late_cancelled: 'Platba přišla po zrušení rezervace a termín už není volný — vraťte ji.',
  late_revived: 'Pozdní platba — rezervace byla automaticky obnovena.',
  target_closed: 'Rezervace nebo objednávka je zrušená / ukončená — vraťte platbu, nebo rozhodněte ručně.',
  booking_closed: 'Rezervace je zrušená / ukončená — vraťte platbu, nebo rozhodněte ručně.',
  request_expired: 'Doplatek úpravy přišel po lhůtě 60 minut — úpravu přesto proveďte, nebo platbu vraťte.',
  request_cancelled: 'Doplatek úpravy, kterou zákazník mezitím zrušil — úpravu proveďte, nebo platbu vraťte.',
  change_failed: 'Zaplacenou úpravu už nešlo provést (termín / motorka obsazena) — rezervace je beze změny, vraťte doplatek.',
  processing_error: 'Zpracování opakovaně selhalo — zkontrolujte platbu a spárujte ji ručně.',
  manual: 'Spárováno ručně obsluhou.',
}
const STATUS_FALLBACK = {
  no_match: 'Platbu se nepodařilo přiřadit — spárujte ji ručně, nebo ignorujte.',
  amount_mismatch: REASON.underpaid,
  needs_review: 'Platbu je potřeba zkontrolovat — nepotvrdila se automaticky.',
  error: 'Zpracování platby selhalo — zkontrolujte ji a spárujte ručně.',
}
/** Česká věta „proč to čeká na obsluhu“ (důvod, jinak podle stavu). */
export function reasonText(tx) {
  if (!tx) return ''
  if (tx.reason_code && REASON[tx.reason_code]) return REASON[tx.reason_code]
  return STATUS_FALLBACK[tx.status] || ''
}

export const followupOpen = (tx) => !!tx?.followup && !tx.followup_done_at
export const needsStaff = (tx) => !!tx && (TODO_STATUSES.includes(tx.status) || followupOpen(tx))
export const FOLLOWUP = { overpaid: 'Přeplatek — vraťte rozdíl zákazníkovi' }

// Kódy chyb RPC (admin_fio_*) a akcí edge fio-sync → česká hláška.
const ERRORS = {
  forbidden: 'K této akci nemáte oprávnění.',
  bad_target: 'Neplatný cíl spárování.',
  not_found: 'Pohyb nebyl nalezen — obnovte seznam.',
  wrong_status: 'Pohyb je mezitím v jiném stavu — obnovte seznam.',
  target_not_found: 'Vybraná rezervace / objednávka už neexistuje.',
  note_required: 'Poznámka je povinná.',
  nothing_to_ack: 'U pohybu není žádný otevřený úkol.',
  not_pending: 'Pohyb už je zpracovaný.',
  busy: 'Pohyb právě zpracovává automatická synchronizace — zkuste to za chvíli.',
  claim_failed: 'Pohyb se nepodařilo převzít ke zpracování — zkuste to za chvíli.',
  rate_limited: 'Banka dovoluje jeden dotaz za 30 s — zkuste to za 30 s.',
  missing_fio_token: 'V nastavení serveru chybí API token banky.',
  bad_response: 'Banka poslala nečitelnou odpověď — zkuste to znovu.',
  insert_failed: 'Pohyby se nepodařilo uložit — zkuste to znovu.',
  account_mismatch: 'Token čte jiný účet, než na který platí zákazníci.',
  exception: 'Neočekávaná chyba synchronizace.',
}
export function errorText(code) {
  const c = String(code || '')
  if (ERRORS[c]) return ERRORS[c]
  const http = c.match(/^fio_http_(\d+)$/)
  if (http) {
    if (http[1] === '500') return 'Banka odpověděla chybou 500 — token je nejspíš neplatný nebo mu skončila platnost.'
    if (http[1] === '409') return ERRORS.rate_limited
    return `Banka odpověděla chybou HTTP ${http[1]}.`
  }
  return c ? `Akce se nezdařila (${c}).` : 'Akce se nezdařila.'
}

// ── Formát ──
export function fmtMoney(n, currency) {
  if (n === null || n === undefined || n === '') return '—'
  const v = Number(n)
  if (!Number.isFinite(v)) return '—'
  const cents = Math.round(Math.abs(v) * 100) % 100 !== 0
  const s = v.toLocaleString('cs-CZ', { minimumFractionDigits: cents ? 2 : 0, maximumFractionDigits: 2 })
  const cur = String(currency || 'CZK').toUpperCase()
  return `${s} ${cur === 'CZK' ? 'Kč' : cur}`
}
const asDate = (d) => (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d) ? new Date(d + 'T00:00:00') : new Date(d))
export const fmtDate = (d) => (d ? asDate(d).toLocaleDateString('cs-CZ') : '—')
export const fmtDateTime = (iso) => (iso
  ? new Date(iso).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  : '—')
export const shortId = (id) => String(id || '').slice(-8).toUpperCase()

export function daysWord(n) { const a = Math.abs(n); return a === 1 ? 'den' : a >= 2 && a <= 4 ? 'dny' : 'dní' }
// „za“ se pojí se 4. pádem (1 den, 2–4 dny, 5+ dní), „před“ se 7. pádem (1 dnem, 2+ dny)
function span(ms, past) {
  const s = Math.max(0, Math.round(ms / 1000))
  if (s < 90) return `${s} s`
  const m = Math.round(s / 60)
  if (m < 90) return `${m} min`
  const h = Math.floor(m / 60)
  if (h < 48) return m % 60 && h < 6 ? `${h} h ${m % 60} min` : `${h} h`
  const d = Math.round(h / 24)
  return `${d} ${past ? (d === 1 ? 'dnem' : 'dny') : daysWord(d)}`
}
/** „před 40 s“ / „před 5 min“ / „před 3 h“ / „před 4 dny“. */
export function fmtAgo(iso, now = Date.now()) {
  const t = Date.parse(iso || '')
  if (!Number.isFinite(t)) return '—'
  return now - t < 5000 ? 'právě teď' : `před ${span(now - t, true)}`
}
/** „za 35 min“ / „za 3 h 20 min“ / „za 6 dní“; po lhůtě „vypršelo před …“. */
export function fmtUntil(iso, now = Date.now()) {
  const t = Date.parse(iso || '')
  if (!Number.isFinite(t)) return '—'
  return t >= now ? `za ${span(t - now, false)}` : `vypršelo před ${span(now - t, true)}`
}
/** Počet dní ode dneška do data (YYYY-MM-DD); záporné = po termínu, null = datum neznámé. */
export function daysUntil(dateStr, now = new Date()) {
  if (!dateStr) return null
  const d = asDate(String(dateStr).slice(0, 10))
  if (!Number.isFinite(d.getTime())) return null
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  return Math.round((d - today) / 86400000)
}
export const isoDate = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
export const sameIban = (a, b) => String(a || '').replace(/\s+/g, '').toUpperCase() === String(b || '').replace(/\s+/g, '').toUpperCase()
