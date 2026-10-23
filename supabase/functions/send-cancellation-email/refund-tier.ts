// Pásmo vratky storna, když volající `refund_percent` neposlal (záchranná cesta — cancel_booking_tracked,
// webhook i Velín ho posílají). Zrcadlí DB `_refund_tier_pct` (20261023e, DESIGN-GEAR §1.11): hodiny od
// TEĎ do začátku rezervace = pražský den `start_date` + `pickup_time` (výchozí 09:00) v Europe/Prague;
// ≥168 h → 100 %, ≥48 h → 50 %, jinak 0 %. (Strop po posunu `_storno_cap_after_move` umí jen DB.)

const PRAGUE = 'Europe/Prague'

function pragueParts(ms: number): { y: number; m: number; d: number; h: number; mi: number } {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: PRAGUE, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(ms)).map((x) => [x.type, x.value]))
  return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour, mi: +p.minute }
}

/** Pražský „nástěnný“ čas (den 'YYYY-MM-DD' + 'HH:MM') → okamžik v ms (střídání času řeší 2 průchody). */
export function pragueWallToMs(day: string, hhmm: string): number {
  const [y, m, d] = day.split('-').map(Number)
  const [h, mi] = hhmm.split(':').map(Number)
  const wall = Date.UTC(y, m - 1, d, h, mi)
  let ms = wall
  for (let i = 0; i < 2; i++) {
    const p = pragueParts(ms)
    ms += wall - Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi)
  }
  return ms
}

/** Okamžik začátku rezervace pro pásmo vratky (NaN = neplatné datum). */
export function refundTierRef(startDate: unknown, pickupTime: unknown): number {
  const s = String(startDate || '')
  let day = /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : ''
  if (!day) {
    const t = Date.parse(s)
    if (Number.isNaN(t)) return NaN
    const p = pragueParts(t)
    day = `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`
  }
  const tm = /^(\d{1,2}):(\d{2})/.exec(String(pickupTime || ''))
  return pragueWallToMs(day, tm ? `${tm[1]}:${tm[2]}` : '09:00')
}

/** Procento vratky storna dle pásma (100 / 50 / 0). */
export function refundTierPercent(startDate: unknown, pickupTime: unknown, now = Date.now()): number {
  const ref = refundTierRef(startDate, pickupTime)
  if (Number.isNaN(ref)) return 0
  const hours = (ref - now) / 3600000
  return hours >= 168 ? 100 : hours >= 48 ? 50 : 0
}
