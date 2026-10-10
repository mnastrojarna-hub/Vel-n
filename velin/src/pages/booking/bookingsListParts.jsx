// Sdílené kousky řádku rezervace — tabulka na desktopu (BookingsTable) i karty
// na mobilu/tabletu (BookingsListMobile) vykreslují stejné štítky a výpočty.
// `fs` = velikost písma štítků (desktop beze změny 9 px, karty větší kvůli čitelnosti).
import StatusBadge, { getDisplayStatus } from '../../components/ui/StatusBadge'
import AppInstallBadge from '../../components/AppInstallBadge'
import { paymentStatusInfo } from './bookingConstants'
import { rentalDays } from '../../lib/rentalDays'

/** Počet dní + změna termínu oproti původní rezervaci (štítek +Nd / −Nd). */
export function bookingDaysInfo(b) {
  const toLocalDate = d => d ? new Date(d).toLocaleDateString('sv-SE') : ''
  const days = b.start_date && b.end_date ? rentalDays(b.start_date, b.end_date) : '—'
  const hasDateChange = b.original_start_date && b.original_end_date &&
    (toLocalDate(b.start_date) !== toLocalDate(b.original_start_date) || toLocalDate(b.end_date) !== toLocalDate(b.original_end_date))
  const origDays = hasDateChange ? rentalDays(b.original_start_date, b.original_end_date) : null
  const daysDelta = origDays !== null && typeof days === 'number' ? days - origDays : null
  return { days, hasDateChange, daysDelta }
}

export function DaysDelta({ info, fs = 'text-[9px]' }) {
  const { hasDateChange, daysDelta } = info
  if (!(hasDateChange && daysDelta !== 0)) return null
  const lbl = daysDelta > 0 ? `+${daysDelta}d` : `${daysDelta}d`
  const lbg = daysDelta > 0 ? '#dbeafe' : '#fee2e2'
  const lcol = daysDelta > 0 ? '#2563eb' : '#dc2626'
  return <span className={`ml-1 ${fs} font-extrabold px-1 py-0.5 rounded-btn`} style={{ background: lbg, color: lcol }}>{lbl}</span>
}

/** Štítky zdroje rezervace (WEB / APP / AI) + indikátor nainstalované appky. */
export function SourceTags({ b, install, fs = 'text-[9px]' }) {
  return (
    <>
      {b.booking_source === 'web' ? <span className={`ml-1 ${fs} font-extrabold px-1.5 py-0.5 rounded-btn`} style={{ background: '#dbeafe', color: '#2563eb' }}>WEB</span> : b.booking_source === 'app' ? <span className={`ml-1 ${fs} font-extrabold px-1.5 py-0.5 rounded-btn`} style={{ background: '#dcfce7', color: '#16a34a' }}>APP</span> : null}
      {b.created_via_ai ? <span className={`ml-1 ${fs} font-extrabold px-1.5 py-0.5 rounded-btn`} style={{ background: '#fef3c7', color: '#92400e' }} title="Vytvořeno přes AI asistenta">🤖 AI</span> : null}
      <AppInstallBadge install={install} />
    </>
  )
}

export function PaymentPill({ b }) {
  const pay = paymentStatusInfo(b)
  return (
    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
      style={{ padding: '3px 8px', background: pay.bg, color: pay.color }}>
      {pay.label}
    </span>
  )
}

/** Stav rezervace + doplňkové štítky (prodloužení, test, SOS, reklamace, úpravy). */
export function StatusTags({ b, fs = 'text-[9px]' }) {
  const tag = `ml-1 ${fs} font-extrabold px-1.5 py-0.5 rounded-btn`
  return (
    <>
      <StatusBadge status={getDisplayStatus(b)} />
      {/* Navazující rezervace (stejný zákazník + motorka, termín den po dni) = prezentuje se jako prodloužení, ne nová */}
      {b.extends_booking_id && <span className={tag} title={`Navazuje na rezervaci #${b.extends_booking_id.slice(-8).toUpperCase()} — úprava/prodloužení, ne nová rezervace`} style={{ background: '#e0e7ff', color: '#4338ca' }}>PRODLOUŽENÍ</span>}
      {b.is_test && <span className={tag} title="Testovací rezervace (obsazenost kalendáře) — pro zákazníky viditelná jako obsazeno" style={{ background: '#f3e8ff', color: '#7c3aed' }}>TEST</span>}
      {b.sos_replacement && <span className={tag} style={{ background: '#dcfce7', color: '#1a8a18' }}>SOS</span>}
      {b.ended_by_sos && <span className={tag} style={{ background: '#fee2e2', color: '#b91c1c' }}>SOS</span>}
      {b.complaint_status && <span className={tag} style={{ background: '#fef3c7', color: '#92400e' }}>RKL</span>}
      {/* Upraveno = má historii změn (i změna jen času/výbavy/místa bez posunu termínu) */}
      {Array.isArray(b.modification_history) && b.modification_history.length > 0 &&
        <span className={tag} title={`Historie úprav: ${b.modification_history.length}×`}
          style={{ background: '#fef3c7', color: '#d97706' }}>✏️ {b.modification_history.length}×</span>}
    </>
  )
}
