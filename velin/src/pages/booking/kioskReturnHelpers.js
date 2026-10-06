import { supabase } from '../../lib/supabase'
import { pragueDateStr } from '../../lib/latePickup'

// Vrácení na kiosku samoobslužné pobočky + krátkodobé kódy (2026-10-06) — sdílené pomůcky Velína.
// Tabulky `booking_kiosk_returns` a `branch_temp_codes` zapisuje JEN server (trigger na branch_door_events,
// cron kiosk_process_returns, RPC admin_issue/revoke_temp_door_code); Velín čte přes RLS (is_admin).

// Tabulka / funkce ještě neexistuje (migrace zatím nenasazena) → funkce Velína se tiše skryje, detail nepadá
export function isMissingRelation(e) {
  if (!e) return false
  const msg = String(e.message || '')
  return ['PGRST205', 'PGRST202', '42P01', '42883'].includes(e.code) || msg.includes('schema cache') || msg.includes('does not exist')
}

const PRAGUE_TZ = 'Europe/Prague'
// Čas v pražské zóně (stejně jako počítá server konec termínu): dnes „16:42“, jindy „6. 10. 16:42“
export function fmtPragueWhen(v) {
  if (!v) return '—'
  const d = new Date(v)
  if (isNaN(d)) return '—'
  const hm = d.toLocaleTimeString('cs-CZ', { timeZone: PRAGUE_TZ, hour: '2-digit', minute: '2-digit' })
  if (pragueDateStr(d.toISOString()) === pragueDateStr(new Date().toISOString())) return hm
  return `${d.toLocaleDateString('cs-CZ', { timeZone: PRAGUE_TZ, day: 'numeric', month: 'numeric' })} ${hm}`
}

// V3 „Přijmout zpět“: motorka už stojí v kóji (vráceno na kiosku, automatika nedokončila — parked/skipped)
// → returned_at = reálný čas zavření kóje podle hodin jednotky místo „teď“. 'completed' = zastaralé potvrzení
// „Přijmout zpět“ po automatickém dokončení (dialog otevřený, než cron dokončil) → týž čas zavření, jinak by
// kliknutí přepsalo čas z kiosku (D3); NE když obsluha automatické dokončení vrátila zpět (detail.reverted nebo
// rezervace teď není dokončená) — closed_at je pak starý. Cokoli podezřelého (motorka po zavření znovu vyjeta =
// 'out', čas v budoucnosti, tabulka nenasazena, chyba) → null = volající dá now().
export async function kioskReturnedAt(bookingId) {
  if (!bookingId) return null
  try {
    const { data, error } = await supabase.from('booking_kiosk_returns')
      .select('state, closed_at, out_at, detail').eq('booking_id', bookingId).maybeSingle()
    if (error || !data?.closed_at) return null
    if (data.state === 'completed') {
      if (data.detail?.reverted === true) return null
      const { data: bk, error: e2 } = await supabase.from('bookings').select('status').eq('id', bookingId).maybeSingle()
      if (e2 || bk?.status !== 'completed') return null
    } else if (!['parked', 'skipped'].includes(data.state)) return null
    const ms = Date.parse(data.closed_at)
    if (!Number.isFinite(ms) || ms > Date.now()) return null
    if (data.out_at && Date.parse(data.out_at) > ms) return null
    return new Date(ms).toISOString()
  } catch { return null }
}

// Původ časů řádku (grant_at / closed_at / out_at / locker_closed_at): jednotka ≥ 1.2.8 posílá `ts` z vlastních
// hodin (detail.unit_ts = true); starší jednotka ne → server vezme čas doručení (po výpadku LTE i hodiny pozdě)
export const kioskUnitClock = row => row?.detail?.unit_ts === true
export function kioskClockNote(row) {
  return kioskUnitClock(row) ? ' (čas jednotky)' : ' (čas doručení na server — starší jednotka)'
}

// Důvody, proč server rezervaci po vrácení automaticky nedokončil (booking_kiosk_returns.reason)
export const KIOSK_RETURN_REASONS = {
  not_active: 'rezervace není ve stavu Aktivní',
  unpaid: 'rezervace není zaplacená',
  sos_replacement: 'jde o SOS náhradní motorku',
  trailer: 'rezervace s vozíkem',
  test: 'testovací rezervace',
  cancelled: 'rezervace je zrušená',
  error: 'opakovaná chyba při automatickém dokončení (viz debug_log)',
}

const TONES = {
  blue: { bg: '#eff6ff', border: '#bfdbfe', color: '#1d4ed8' },
  amber: { bg: '#fffbeb', border: '#fde68a', color: '#b45309' },
  green: { bg: '#dcfce7', border: '#86efac', color: '#1a8a18' },
  red: { bg: '#fef2f2', border: '#fecaca', color: '#dc2626' },
  gray: { bg: '#f1faf7', border: '#d4e8e0', color: '#1a2e22' },
}

// Stav řádku → { title, hint, tone } pro blok „Vrácení na kiosku“. Konec termínu = pražské datum end_date
// (D1: vrácení v POSLEDNÍ den pronájmu nebo později dokončí rezervaci; dřív = jen zaparkování).
export function kioskReturnView(row, booking) {
  const b = booking || {}
  const endDay = pragueDateStr(b.end_date)
  const endTxt = endDay ? endDay.split('-').reverse().map(Number).join('. ') : 'konci termínu'
  let state = row.state
  // Obsluha / cron dokončili dřív, než server stihl řádek přepnout (completed_elsewhere doběhne do minuty)
  if (b.status === 'completed' && ['parked', 'returning', 'out'].includes(state)) state = 'completed_elsewhere'
  const clock = kioskUnitClock(row) ? 'podle hodin jednotky' : 'podle času doručení na server (starší jednotka)'
  switch (state) {
    case 'returning':
      return { tone: TONES.blue, title: 'Probíhá vrácení', hint: 'Zákazník zadal na displeji kód motorky a stav tachometru — čeká se na zaparkování a zavření kóje.' }
    case 'parked': {
      const final = !!endDay && pragueDateStr(row.closed_at) >= endDay
      const over = !!endDay && pragueDateStr(new Date().toISOString()) > endDay
      if (final) return { tone: TONES.green, title: 'Vráceno v poslední den — dokončuje se', hint: 'Rezervace se dokončí automaticky ~2 min po posledním zavření kóje; kódy pak ještě 15 min dobíhají.' }
      if (over) return { tone: TONES.green, title: 'Zaparkováno do konce termínu — dokončuje se', hint: 'Motorka zůstala v kóji do konce termínu — rezervace se dokončí automaticky s časem vrácení = zavření kóje.' }
      return { tone: TONES.amber, title: 'Zaparkováno před posledním dnem', hint: `Zákazník motorku jen zaparkoval — kódy platí dál. Zůstane-li motorka v kóji, rezervace se dokončí automaticky po konci termínu (${endTxt}) s časem vrácení = zavření kóje.` }
    }
    case 'out':
      // Kóji se zaparkovanou motorkou otevřel kód BEZ rezervace (krátkodobý kód z Velína) — motorka mohla odjet
      if (row.detail?.last_event === 'FOREIGN_GRANT')
        return { tone: TONES.amber, title: 'Kóje otevřena krátkodobým kódem', hint: 'Kóji se zaparkovanou motorkou otevřel krátkodobý kód — automatika rezervaci nedokončí, dokud zákazník motorku znovu nevrátí kódem motorky. Stojí-li motorka v kóji, dokončete ručně tlačítkem „Přijmout zpět“ (čas vrácení = okamžik potvrzení).' }
      // Po zaparkování i po vrácení, které automatika nedokončila (skipped → out, důvod smazán): motorka je venku
      return { tone: TONES.blue, title: 'Motorka znovu vyjeta', hint: 'Po vrácení do kóje si zákazník motorku kódem motorky znovu vyzvedl — pronájem pokračuje. Dokončení se posoudí znovu až při dalším vrácení na kiosku; ručně nedokončujte, dokud motorka není zpět (čas vrácení by byl okamžik potvrzení).' }
    case 'completed': {
      // Obsluha automatické dokončení vrátila zpět (stav řádku zůstává terminální 'completed')
      if (b.status === 'cancelled') return { tone: TONES.gray, title: 'Vráceno na kiosku — rezervace zrušená', hint: 'Automatické dokončení obsluha vrátila zpět a rezervaci zrušila.' }
      if (b.status && b.status !== 'completed')
        return { tone: TONES.amber, title: 'Dokončení vráceno — rezervace opět neukončená', hint: 'Automatika rezervaci po vrácení na kiosku dokončila, obsluha ji pak vrátila zpět. Další vrácení na kiosku se už automaticky nedokončí — dokončete ručně tlačítkem „Přijmout zpět“.' }
      if (row.detail?.reverted === true)
        return { tone: TONES.gray, title: 'Vráceno na kiosku — dokončeno ručně', hint: 'Automatické dokončení obsluha vrátila zpět a rezervaci pak dokončila ručně.' }
      if (row.detail?.completed_after_end === true)
        return { tone: TONES.green, title: 'Dokončeno automaticky po konci termínu', hint: `Motorka zůstala v kóji do konce termínu; čas vrácení = zavření kóje ${clock}. Kódy byly zneplatněny hned při dokončení (bez 15min doběhu).` }
      return { tone: TONES.green, title: 'Dokončeno automaticky', hint: `Rezervace dokončena po vrácení na kiosku; čas vrácení = zavření kóje ${clock}. Znovuotevření tímtéž kódem v 15min okně čas posune.` }
    }
    case 'skipped': {
      if (b.status === 'completed') return { tone: TONES.gray, title: 'Vráceno na kiosku — dokončeno ručně', hint: 'Automatika rezervaci nedokončila, dokončila ji obsluha.' }
      const why = KIOSK_RETURN_REASONS[row.reason] || row.reason || 'neznámý důvod'
      if (b.status === 'cancelled') return { tone: TONES.gray, title: 'Vráceno na kiosku — rezervace zrušená', hint: `Automaticky se nedokončuje (${why}).` }
      return { tone: TONES.red, title: 'Vráceno, ale nedokončeno automaticky', hint: `Důvod: ${why}. → Zkontrolujte a dokončete ručně tlačítkem „Přijmout zpět“ (čas vrácení se převezme z kiosku).` }
    }
    case 'completed_elsewhere':
      return { tone: TONES.gray, title: 'Vráceno na kiosku — dokončeno jinou cestou', hint: 'Rezervaci dokončila obsluha nebo automatika po konci termínu.' }
    default:
      return { tone: TONES.gray, title: `Stav ${row.state || '—'}`, hint: '' }
  }
}
