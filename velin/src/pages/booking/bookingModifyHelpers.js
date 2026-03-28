export const DAY_KEYS_JS = { 0: 'price_sunday', 1: 'price_monday', 2: 'price_tuesday', 3: 'price_wednesday', 4: 'price_thursday', 5: 'price_friday', 6: 'price_saturday' }
export const DAY_KEYS_MOTO = { 0: 'price_sun', 1: 'price_mon', 2: 'price_tue', 3: 'price_wed', 4: 'price_thu', 5: 'price_fri', 6: 'price_sat' }
export const DOW_LABELS = ['Ne', 'Po', 'Ut', 'St', 'Ct', 'Pa', 'So']

export function isoDate(d) {
  if (!d) return ''
  if (typeof d === 'string') return d.slice(0, 10)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function toDate(s) { if (!s) return null; const d = new Date(s); d.setHours(0, 0, 0, 0); return d }
export function fmtDate(d) { return d ? (typeof d === 'string' ? new Date(d + 'T00:00:00') : d).toLocaleDateString('cs-CZ') : '\u2014' }
export function fmtCZK(n) { return Number(n || 0).toLocaleString('cs-CZ') }

export function countDays(start, end) {
  if (!start || !end) return 0
  const s = toDate(typeof start === 'string' ? start : isoDate(start))
  const e = toDate(typeof end === 'string' ? end : isoDate(end))
  return Math.max(1, Math.round((e - s) / 86400000) + 1)
}

export function calcDayBreakdown(motoId, start, end, motoPrices, allMotos) {
  if (!motoId || !start || !end) return []
  const dp = motoPrices[motoId]
  const moto = allMotos.find(m => m.id === motoId)
  const days = []
  const cur = new Date(start)
  const endD = new Date(end)
  while (cur <= endD) {
    const dow = cur.getDay()
    const price = (dp && Number(dp[DAY_KEYS_JS[dow]])) || (moto && Number(moto[DAY_KEYS_MOTO[dow]])) || 0
    days.push({ date: new Date(cur), dow, dowLabel: DOW_LABELS[dow], price })
    cur.setDate(cur.getDate() + 1)
  }
  return days
}
