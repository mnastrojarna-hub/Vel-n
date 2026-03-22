// Season: April (3) – October (9), 7 months
export const SEASON_MONTHS = 7
export const SEASON_START = 3
export const SEASON_END = 9

// České státní svátky (měsíc 0-indexed, den)
export function getCzechHolidays(year) {
  const fixed = [
    [0, 1], [4, 1], [4, 8], [6, 5], [6, 6],
    [8, 28], [9, 28], [10, 17], [11, 24], [11, 25], [11, 26],
  ]
  const holidays = new Set(fixed.map(([m, d]) => `${year}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`))
  // Velikonoční pondělí (Gauss)
  const a = year % 19, b = Math.floor(year / 100), c = year % 100
  const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25)
  const g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
  const i = Math.floor(c / 4), k = c % 4
  const l = (32 + 2 * e + 2 * i - h - k) % 7
  const m = Math.floor((a + 11 * h + 22 * l) / 451)
  const month = Math.floor((h + l - 7 * m + 114) / 31) - 1
  const day = ((h + l - 7 * m + 114) % 31) + 1
  const easter = new Date(year, month, day)
  const goodFriday = new Date(easter); goodFriday.setDate(easter.getDate() - 2)
  holidays.add(isoDate(goodFriday))
  const easterMonday = new Date(easter); easterMonday.setDate(easter.getDate() + 1)
  holidays.add(isoDate(easterMonday))
  return holidays
}

export function isBlockedDay(date) {
  const m = date.getMonth(), d = date.getDate(), y = date.getFullYear()
  if (m === 11 && d >= 20) return true
  if (m === 0 && d <= 7) return true
  return getCzechHolidays(y).has(isoDate(date))
}

export function isServiceDay(date) {
  const day = date.getDay()
  return day >= 1 && day <= 5 && !isBlockedDay(date)
}

export function isInSeason(date) {
  const m = date.getMonth()
  return m >= SEASON_START && m <= SEASON_END
}

export function seasonDaysBetween(from, to) {
  let count = 0
  const d = new Date(from); d.setHours(0, 0, 0, 0)
  const end = new Date(to); end.setHours(0, 0, 0, 0)
  while (d <= end) { if (isInSeason(d)) count++; d.setDate(d.getDate() + 1) }
  return count
}

export function addSeasonDays(from, seasonDays) {
  const d = new Date(from); d.setHours(0, 0, 0, 0)
  let added = 0
  while (added < seasonDays) { d.setDate(d.getDate() + 1); if (isInSeason(d)) added++ }
  return d
}

export function findWinterServiceDate(year, bookings) {
  for (let month = 0; month <= 1; month++) {
    const d = new Date(year, month, 1); d.setHours(0, 0, 0, 0)
    while (d.getMonth() === month) {
      if (isServiceDay(d)) {
        const ds = isoDate(d)
        if (!bookings.some(b => ds >= (b.start_date || '').split('T')[0] && ds <= (b.end_date || '').split('T')[0]))
          return new Date(d)
      }
      d.setDate(d.getDate() + 1)
    }
  }
  return new Date(year, 0, 15)
}

export function scheduleStkDates(motos, bookings, year) {
  const availableDays = []
  for (let d = new Date(year - 1, 11, 1); d.getMonth() === 11; d.setDate(d.getDate() + 1))
    if (isServiceDay(d)) availableDays.push(new Date(d))
  for (let d = new Date(year, 0, 1); d.getMonth() === 0; d.setDate(d.getDate() + 1))
    if (isServiceDay(d)) availableDays.push(new Date(d))
  for (let d = new Date(year, 1, 1); d.getMonth() === 1; d.setDate(d.getDate() + 1))
    if (isServiceDay(d)) availableDays.push(new Date(d))

  const assignments = {}, dayUsage = {}
  let dayIdx = 0
  for (const moto of motos) {
    const mb = bookings.filter(b => b.moto_id === moto.id)
    let assigned = false
    for (let attempt = 0; attempt < availableDays.length; attempt++) {
      const idx = (dayIdx + attempt) % availableDays.length
      const candidate = availableDays[idx]
      const ds = isoDate(candidate)
      if ((dayUsage[ds] || 0) >= 2) continue
      if (mb.some(b => ds >= (b.start_date || '').split('T')[0] && ds <= (b.end_date || '').split('T')[0])) continue
      assignments[moto.id] = new Date(candidate)
      dayUsage[ds] = (dayUsage[ds] || 0) + 1
      dayIdx = (idx + 1) % availableDays.length
      assigned = true; break
    }
    if (!assigned) assignments[moto.id] = new Date(year, 0, 15)
  }
  return assignments
}

export function isLateOctober(date) {
  return date && date.getMonth() === 9 && date.getDate() >= 17
}

export function isoDate(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function nearestTueWed(date) {
  const d = new Date(date); d.setHours(0, 0, 0, 0)
  for (let i = 0; i < 30; i++) {
    const day = d.getDay()
    if ((day === 2 || day === 3) && !isBlockedDay(d)) return new Date(d)
    d.setDate(d.getDate() + 1)
  }
  return new Date(date)
}

export function findFreeServiceDate(baseDate, bookings) {
  const d = new Date(baseDate); d.setHours(0, 0, 0, 0)
  for (let i = 0; i < 90; i++) {
    const day = d.getDay()
    if ((day === 2 || day === 3) && !isBlockedDay(d)) {
      const ds = isoDate(d)
      if (!bookings.some(b => ds >= (b.start_date || '').split('T')[0] && ds <= (b.end_date || '').split('T')[0]))
        return new Date(d)
    }
    d.setDate(d.getDate() + 1)
  }
  return nearestTueWed(baseDate)
}

export const TYPE_LABELS = {
  oil_change: 'Výměna oleje', tire_change: 'Výměna pneumatik', brake_check: 'Kontrola brzd',
  full_service: 'Kompletní servis', repair: 'Oprava', inspection: 'STK / Inspekce',
  stk: 'STK & Emise', winter_service: 'Velký zimní servis',
}
