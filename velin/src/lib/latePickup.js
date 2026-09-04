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
