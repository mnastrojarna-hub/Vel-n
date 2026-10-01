// Sleva 50 % na 1. den při pozdním vyzvednutí — zrcadlí SQL helper
// _late_pickup_discount(): vyzvednutí >= 12:00 A rezervace na 2 a více
// kalendářních dní (start i end včetně) => sleva = round(50 % ceny 1. dne).
// Cenu 1. dne předává volající (každé místo Velína má vlastní zdroj ceníku:
// moto_day_prices override / motorcycles.price_*), aby rozpis seděl na jeho
// vlastní součet; autoritativní strop drží DB trigger validate_late_pickup.
export const LATE_PICKUP_LABEL = 'Sleva 50 % na 1. den (pozdní vyzvednutí)'
export const LATE_PICKUP_HINT = 'Vyzvednutí od 12:00 = 1. den za polovinu (u rezervací na 2 a více dní).'

export function isLatePickup(pickupTime) {
  if (!pickupTime) return false
  const h = parseInt(String(pickupTime).split(':')[0], 10)
  return Number.isFinite(h) && h >= 12
}

export function bookingDaysInclusive(startDate, endDate) {
  if (!startDate || !endDate) return 0
  const a = new Date(startDate); a.setHours(0, 0, 0, 0)
  const b = new Date(endDate); b.setHours(0, 0, 0, 0)
  return Math.round((b - a) / 86400000) + 1
}

export function latePickupDiscount(startDate, endDate, pickupTime, firstDayPrice) {
  if (!isLatePickup(pickupTime)) return 0
  if (bookingDaysInclusive(startDate, endDate) < 2) return 0
  return Math.round((Number(firstDayPrice) || 0) * 0.5)
}

// ── Hradlo kiosku samoobslužné pobočky (zadání 2026-10-01 večer) ────────────
// Zrcadlí SQL `_kiosk_release_at()` (migrace 20261001h): rezervaci se slevou za
// vyzvednutí od 12:00 vydá kiosk (šatna i motorka) až od 12:00 Europe/Prague
// v den začátku. Hradlo = samoobslužná pobočka motorky + převzetí NA pobočce
// (ne přistavení, bez adresy) + late_pickup_discount_amount > 0 (skutečně
// přiznaná sleva) + ještě nevyzvednuto + reserved/active + ne SOS náhrada.
export const SELF_SERVICE_BRANCH_TYPE = 'samoobslužná'
export const LATE_PICKUP_KIOSK_HINT = 'Samoobslužná pobočka: kiosk motorku vydá až od 12:00 v den vyzvednutí.'
export const LATE_PICKUP_KIOSK_CHIP = '🌗 Kiosk vydá od 12:00 (sleva za pozdní vyzvednutí)'
// '00:01' = stará hodnota „bez času" (samoobsluha 2026-10-01 dopoledne) — bez slevy i hradla
export const isLegacyNoPickupTime = t => String(t || '').startsWith('00:01')

const PRAGUE_TZ = 'Europe/Prague'
let _pragueFmt = null
function pragueParts(ms) {
  if (!_pragueFmt) _pragueFmt = new Intl.DateTimeFormat('en-GB', { timeZone: PRAGUE_TZ, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
  const p = {}
  for (const x of _pragueFmt.formatToParts(new Date(ms))) p[x.type] = x.value
  return p
}

// Pražské kalendářní datum 'YYYY-MM-DD'. 'YYYY-MM-DD' i objekt Date (datum
// zvolené v kalendáři Velína = lokální půlnoc) se berou jako kalendářní den;
// plný ISO timestamp (bookings.start_date timestamptz) se převede do Prahy.
export function pragueDateStr(v) {
  if (!v) return ''
  if (v instanceof Date) {
    if (isNaN(v)) return ''
    return `${v.getFullYear()}-${String(v.getMonth() + 1).padStart(2, '0')}-${String(v.getDate()).padStart(2, '0')}`
  }
  const s = String(v)
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s
  const ms = Date.parse(s)
  if (!Number.isFinite(ms)) return ''
  const p = pragueParts(ms)
  return `${p.year}-${p.month}-${p.day}`
}

// Okamžik 12:00 Europe/Prague daného kalendářního dne (nezávisle na zóně zařízení).
export function pragueNoon(dateStr) {
  const [y, m, d] = String(dateStr).split('-').map(Number)
  if (!y || !m || !d) return null
  const guess = Date.UTC(y, m - 1, d, 12, 0, 0)
  const p = pragueParts(guess)
  const offset = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - guess
  return new Date(guess - offset)
}

// Vrací Date (okamžik vydání) nebo null (bez hradla). branchType = branches.type
// pobočky MOTORKY rezervace.
export function kioskReleaseGate(booking, branchType) {
  const b = booking || {}
  if (branchType !== SELF_SERVICE_BRANCH_TYPE) return null
  if (!(Number(b.late_pickup_discount_amount) > 0)) return null
  if (b.pickup_method === 'delivery' || String(b.pickup_address || '').trim()) return null
  if (b.picked_up_at || b.sos_replacement) return null
  if (!['reserved', 'active'].includes(b.status)) return null
  const ds = pragueDateStr(b.start_date)
  return ds ? pragueNoon(ds) : null
}

// „1. 10. 2026 12:00" v pražském čase (pro tooltipy / hlášky Velína)
export function fmtPragueDateTime(d) {
  if (!d) return ''
  return new Date(d).toLocaleString('cs-CZ', { timeZone: PRAGUE_TZ, day: 'numeric', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}
