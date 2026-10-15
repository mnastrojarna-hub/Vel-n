// Zprávy → Hodnocení: čisté pomocné funkce (bez Reactu a bez dotazů).
// Hvězdičky = bookings.rating (1–5) + rated_at, zapisuje je zákazník v appce.
// Text „co máme zlepšit“ NENÍ veřejný: appka ho pošle do zákazníkova vlastního chatu
// (message_threads + messages, direction 'customer') do vlákna, jehož předmět obsahuje
// značku rezervace „#XXXXXXXX“ (= posledních 8 znaků ID velkými písmeny, stejně jako shortId
// v appce a #ID ve Velínu). Tabulka `reviews` se NEPOUŽÍVÁ — je veřejně čitelná a web ji zobrazuje.

export const LOW_MAX = 3 // 1–3 ★ = nízké hodnocení → zvýraznit a počítat do odznaku, dokud není vyřízené

export function shortBookingId(id) {
  return id ? String(id).slice(-8).toUpperCase() : ''
}

// Předmět vlákna, které Velín založí sám („Napsat zákazníkovi“, zákazník ještě nepsal).
// Zákazník předmět vidí v appce → v jeho jazyce (profiles.language), značka #ID vždy beze změny.
// Texty = appka `rfThreadSubject` (translations_ext_36_ride_feedback.dart) — appka pak do
// tohoto (neuzavřeného) vlákna pošle i svou zpětnou vazbu (hledá ho podle značky).
const SUBJECT_PREFIX = {
  cs: 'Zpětná vazba k jízdě', en: 'Ride feedback', de: 'Feedback zur Fahrt', es: 'Comentarios sobre el viaje',
  fr: 'Retour sur le trajet', nl: 'Feedback over de rit', pl: 'Opinia o jeździe', uk: 'Відгук про поїздку',
}

// Appka začíná zprávu řádkem „★★☆☆☆ 2/5“ (hodnocení v okamžiku odeslání) → Velín ho
// zobrazí zvlášť a jen když se liší od aktuálních hvězdiček.
export function splitFeedback(content) {
  const m = /^\s*[★☆]{5}\s+([1-5])\/5\s*(?:\r?\n)+/.exec(content || '')
  return m ? { stars: Number(m[1]), text: content.slice(m[0].length) } : { stars: null, text: content || '' }
}

export function feedbackSubject(lang, bookingId) {
  return `${SUBJECT_PREFIX[lang] || SUBJECT_PREFIX.cs} #${shortBookingId(bookingId)}`
}

const ms = v => (v ? new Date(v).getTime() : NaN)
const isAdminDir = d => d === 'admin' || d === 'outbound'

// Ruční „vyřízeno“ platí jen pro hodnocení, které admin viděl: změní-li zákazník hvězdičky
// (nové rated_at), je hodnocení znovu nevyřízené. Porovnává se uložené rated_at, ne čas
// označení — rated_at zapisuje zařízení zákazníka a jeho hodiny se můžou lišit.
export function manualHandledValid(entry, booking) {
  if (!entry) return false
  if (!booking.rated_at || !entry.rated_at_seen) return true
  return ms(entry.rated_at_seen) === ms(booking.rated_at)
}

/**
 * Spojí hodnocené rezervace s vlákny zpětné vazby a stavem „vyřízeno“.
 * threads: message_threads s vnořenými messages (jen vlákna s „#“ v předmětu).
 * handled: { [booking_id]: { handled_at, rated_at_seen, handled_by } }.
 */
export function buildRatingRows(bookings, threads, handled) {
  const byCustomer = {}
  for (const t of threads || []) {
    if (!t.customer_id) continue
    ;(byCustomer[t.customer_id] ||= []).push(t)
  }
  return (bookings || []).filter(b => b.rating >= 1).map(b => {
    const short = shortBookingId(b.id)
    const marker = '#' + short
    // Vlákno patří k rezervaci jen když nese její značku A patří témuž zákazníkovi.
    const own = (byCustomer[b.user_id] || []).filter(t => (t.subject || '').toUpperCase().includes(marker))
    // Komentář = zprávy zákazníka od začátku nájmu (starší dotazy z téhož vlákna nejsou zpětná vazba).
    const startMs = ms(b.start_date) || 0
    const msgs = own.flatMap(t => (t.messages || []).map(m => ({ ...m, thread_id: t.id })))
      .sort((a, z) => ms(a.created_at) - ms(z.created_at))
    const comments = msgs.filter(m => m.direction === 'customer' && ms(m.created_at) >= startMs && (m.content || '').trim())
    const unread = comments.filter(m => !m.read_at)
    const ratedMs = ms(b.rated_at)
    const firstCommentMs = comments.length ? ms(comments[0].created_at) : NaN
    const since = Math.min(...[ratedMs, firstCommentMs].filter(Number.isFinite), Infinity)
    const reply = Number.isFinite(since) ? msgs.filter(m => isAdminDir(m.direction) && ms(m.created_at) >= since).pop() : null
    // Uzavřené/vyřešené musí být vlákno s POSLEDNÍ zpětnou vazbou (appka po uzavření zakládá nové).
    const lastThread = comments.length ? own.find(t => t.id === comments[comments.length - 1].thread_id) : null
    const closedThread = !!lastThread && unread.length === 0 && (lastThread.status === 'resolved' || lastThread.status === 'closed')
    const manual = manualHandledValid(handled?.[b.id], b) ? handled[b.id] : null
    let handledBy = null
    if (manual) handledBy = { kind: 'manual', at: manual.handled_at }
    else if (reply) handledBy = { kind: 'reply', at: reply.created_at }
    else if (closedThread) handledBy = { kind: 'closed', at: null }
    const low = b.rating <= LOW_MAX
    // Vlákno pro „Odpovědět“: to s nejnovější zpětnou vazbou, jinak nejnověji aktivní.
    const latestThreadId = comments.length ? comments[comments.length - 1].thread_id : null
    const thread = own.find(t => t.id === latestThreadId)
      || [...own].sort((a, z) => ms(z.last_message_at || z.created_at) - ms(a.last_message_at || a.created_at))[0] || null
    return {
      id: b.id, short, booking: b, rating: b.rating, low,
      comments, unread, thread, threads: own,
      handled: handledBy, manual: !!manual,
      attention: (low && !handledBy) || unread.length > 0,
    }
  }).sort((a, z) => (ms(z.booking.rated_at) || ms(z.booking.end_date) || 0) - (ms(a.booking.rated_at) || ms(a.booking.end_date) || 0))
}

export const RATING_FILTERS = [
  { key: 'all', label: 'Vše' },
  { key: 'low', label: '1–3 ★' },
  { key: 'high', label: '4–5 ★' },
  { key: 'comment', label: 'S komentářem' },
  { key: 'unread', label: 'Nepřečtené' },
  { key: 'open', label: 'Nevyřízené' },
]

const FILTER_FN = {
  all: () => true,
  low: r => r.low,
  high: r => !r.low,
  comment: r => r.comments.length > 0,
  unread: r => r.unread.length > 0,
  open: r => r.attention,
}

export function filterCounts(rows) {
  const out = {}
  for (const f of RATING_FILTERS) out[f.key] = rows.filter(FILTER_FN[f.key]).length
  return out
}

export function filterRows(rows, filter, search) {
  const fn = FILTER_FN[filter] || FILTER_FN.all
  const q = (search || '').trim().toLowerCase().replace(/^#/, '')
  return rows.filter(r => {
    if (!fn(r)) return false
    if (!q) return true
    const b = r.booking
    const hay = [r.short, b.profiles?.full_name, b.profiles?.email, b.profiles?.phone, b.motorcycles?.model,
      b.motorcycles?.spz, branchName(b), ...r.comments.map(m => m.content)].filter(Boolean).join(' ').toLowerCase()
    return hay.includes(q)
  })
}

export function ratingsSummary(rows) {
  const dist = [0, 0, 0, 0, 0, 0]
  let sum = 0
  for (const r of rows) { dist[r.rating] += 1; sum += r.rating }
  const lowOpen = rows.filter(r => r.low && !r.handled).length
  const unread = rows.filter(r => r.unread.length > 0).length
  return {
    total: rows.length, avg: rows.length ? sum / rows.length : 0, dist,
    lowOpen, unread, badge: rows.filter(r => r.attention).length,
  }
}

// Pobočka rezervace: bookings.branch_id (kde zákazník převzal), jinak pobočka motorky (lib/bookingBranch.js).
export function branchName(b) {
  return b?.branch?.name || b?.motorcycles?.branches?.name || ''
}

export function fmtDateTime(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export function fmtRange(start, end) {
  if (!start) return '—'
  const f = d => new Date(d).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' })
  return end && end !== start ? `${f(start)} – ${f(end)}` : f(start)
}

// ── Ruční „vyřízeno“ bez SQL: localStorage tohoto prohlížeče (sdílené přes DB až po migraci) ──
const LOCAL_KEY = 'velin_ratings_handled_v1'
export function readLocalHandled() {
  try { return JSON.parse(localStorage.getItem(LOCAL_KEY) || '{}') || {} } catch { return {} }
}
export function writeLocalHandled(map) {
  try {
    if (map && Object.keys(map).length) localStorage.setItem(LOCAL_KEY, JSON.stringify(map))
    else localStorage.removeItem(LOCAL_KEY)
  } catch { /* plné/blokované úložiště nesmí shodit stránku */ }
}
