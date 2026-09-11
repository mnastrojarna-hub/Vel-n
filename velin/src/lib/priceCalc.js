/**
 * Kalkulace ceny motorky — přepis excelu „Moto ceny.xlsx“ (horní tabulka)
 * do Velína (Analýza → Kalkulace cen). ANALYTICKÝ nástroj: NEMĚNÍ reálný ceník.
 *
 * Excel:  Náklady/rok Q = servis×četnost + pojištění+čistírna
 *         Náklady na návratnost S = cena_moto×R + Q×R
 *         Základ bez marže T = S / (půjčené_dny×R),  Zákl. cena U = T×1,25
 *         Po = U, Út = St = U×0,8, Čt = U×0,9, Pá = U, So = U×1,2, Ne = U×1,1
 *
 * Změny proti excelu (zadání 2026-09-11):
 *  - servis = ROČNÍ NÁJEZD × Kč/km (2 Kč) místo „cena servisu × četnost“,
 *  - roční nájezd i půjčené dny se dopočítávají z REÁLNÝCH dat motorky:
 *    km z předávacích protokolů (jen za období, kdy se protokoly zapisují),
 *    půjčené dny z realizovaných rezervací za dobu vlastnění; z obou se
 *    odečtou dny v servisu a přepočte se na SEZÓNU (7 měsíců = duben–říjen),
 *  - cena moto = reálná pořizovací cena (`purchase_price`),
 *  - pojištění+čistírna 13 000, návratnost 2 roky, marže 25 % beze změny,
 *  - úterý = středa (×0,8).
 */

export const DEFAULT_PARAMS = {
  kcPerKm: 2,            // servis: Kč za 1 km ročního nájezdu
  insuranceYear: 13000,  // pojištění + čistírna / rok
  paybackYears: 2,       // doba cílené návratnosti
  margin: 0.25,          // marže nad základ bez marže
  seasonFrom: 4,         // sezóna od měsíce (1–12)
  seasonTo: 10,          // sezóna do měsíce (včetně)
  fallbackRentedDays: 60,// průměr půjčených dní: bez dat NEBO když dopočet vyjde mimo <rentedMin, rentedMax>
  rentedMin: 40,         // dopočtené půjčené dny pod tímto → použije se průměr (původní v závorce)
  rentedMax: 80,         // dopočtené půjčené dny nad tímto → použije se průměr (původní v závorce)
  minObsDays: 14,        // min. efektivních dní pozorování, aby odhad platil
}

// Denní koeficienty z excelu (Út = St dle zadání).
export const DAY_COEF = { mon: 1, tue: 0.8, wed: 0.8, thu: 0.9, fri: 1, sat: 1.2, sun: 1.1 }
export const DAY_LABELS = { mon: 'Po', tue: 'Út', wed: 'St', thu: 'Čt', fri: 'Pá', sat: 'So', sun: 'Ne' }

const DAY_MS = 86400000
const midnight = d => { if (!d) return null; const x = new Date(typeof d === 'string' && d.length <= 10 ? d + 'T00:00:00' : d); if (isNaN(x)) return null; x.setHours(0, 0, 0, 0); return x }

/** Je měsíc (1–12) v sezóně? Zvládá i sezónu přes Nový rok (např. 11–3). */
export function inSeason(month, p) {
  return p.seasonFrom <= p.seasonTo ? (month >= p.seasonFrom && month <= p.seasonTo) : (month >= p.seasonFrom || month <= p.seasonTo)
}

/** Počet sezónních dní v jednom (nepřestupném) roce — základ ročního přepočtu. */
export function seasonDaysPerYear(p) {
  let n = 0
  for (let m = 1; m <= 12; m++) if (inSeason(m, p)) n += new Date(2025, m, 0).getDate()
  return n
}

/** Počet sezónních dní v intervalu <from, to> (inkluzivně, po dnech). */
export function seasonDaysBetween(from, to, p) {
  const a = midnight(from), b = midnight(to)
  if (!a || !b || b < a) return 0
  let n = 0
  for (let t = a.getTime(); t <= b.getTime(); t += DAY_MS) if (inSeason(new Date(t).getMonth() + 1, p)) n++
  return n
}

/** Dny v servisu (sezónní) uvnitř okna <from, to> — servisní intervaly se ořežou na okno a sloučí (bez dvojího počítání). */
export function serviceDaysInWindow(intervals, from, to, p) {
  const a = midnight(from), b = midnight(to)
  if (!a || !b) return 0
  const cut = intervals
    .map(i => ({ s: midnight(i.start), e: midnight(i.end || i.start) }))
    .filter(i => i.s && i.e)
    .map(i => ({ s: Math.max(i.s.getTime(), a.getTime()), e: Math.min(i.e.getTime(), b.getTime()) }))
    .filter(i => i.e >= i.s)
    .sort((x, y) => x.s - y.s)
  let days = 0, curS = null, curE = null
  const flush = () => { if (curS != null) days += seasonDaysBetween(new Date(curS), new Date(curE), p) }
  for (const i of cut) {
    if (curS == null || i.s > curE + DAY_MS) { flush(); curS = i.s; curE = i.e }
    else if (i.e > curE) curE = i.e
  }
  flush()
  return days
}

/**
 * Servisní intervaly motorky z `maintenance_log` (service_date → completed_date,
 * nedokončený = dodnes) a `service_orders` (created_at → completed_at). Testovací se vynechají.
 */
export function serviceIntervals(logs, orders, today) {
  const out = []
  for (const l of logs || []) {
    if (l.is_test || !l.service_date) continue
    const end = l.completed_date || (l.status === 'completed' ? l.service_date : today)
    out.push({ start: l.service_date, end })
  }
  for (const o of orders || []) {
    if (o.is_test || o.status === 'cancelled' || !o.created_at) continue
    out.push({ start: o.created_at, end: o.completed_at || (o.status === 'completed' ? o.created_at : today) })
  }
  return out
}

/** Roční přepočet: hodnota za efektivní (sezónní − servis) dny → jedna sezóna. */
function annualize(value, effDays, p) {
  if (effDays < p.minObsDays || effDays <= 0) return null
  return value / effDays * seasonDaysPerYear(p)
}

/**
 * Kompletní kalkulace jedné motorky.
 * @param moto      řádek motorcycles (purchase_price, acquired_at, price_*)
 * @param segments  uzavřené segmenty z RPC analytics_moto_rental_km (start_date, reading, next_reading)
 * @param kmRow     řádek RPC analytics_moto_km (purchase_km, total_driven)
 * @param bookings  realizované rezervace motorky (start_date, end_date)
 * @param svc       servisní intervaly (serviceIntervals)
 * @param p         parametry (DEFAULT_PARAMS)
 * @param today     Date
 */
export function calcMotoPrice(moto, segments, kmRow, bookings, svc, p, today = new Date()) {
  const purchase = Number(moto.purchase_price) || 0
  const purchaseKm = Number(kmRow?.purchase_km) || 0
  // Doba vlastnění: od data pořízení, bez něj od první rezervace motorky.
  const firstBooking = (bookings || []).reduce((min, b) => (b.start_date && (!min || b.start_date < min) ? b.start_date : min), null)
  const own = midnight(moto.acquired_at) || midnight(firstBooking) || null

  // ── Roční nájezd ─────────────────────────────────────────────────────────
  // Primárně z protokolů: km jen za okno <první čtení, poslední čtení>, kde se
  // km reálně zapisují. Čtení pod „koupeno s km“ se podlaží (stejně jako Nájezd km).
  const closed = (segments || []).filter(s => s.next_reading != null).sort((a, b) => (a.start_date < b.start_date ? -1 : 1))
  let kmObserved = 0
  for (const s of closed) {
    const a = Number(s.reading) || 0, b = Number(s.next_reading) || 0
    kmObserved += b >= purchaseKm ? Math.max(0, b - Math.max(a, purchaseKm)) : Math.max(0, b - a)
  }
  let kmFrom = closed.length ? closed[0].start_date : null
  let kmTo = closed.length ? ((segments || []).find(s => s.next_reading == null)?.start_date || closed[closed.length - 1].start_date) : null
  let kmSource = 'protokoly'
  const kmWindow = () => {
    const season = kmFrom ? seasonDaysBetween(kmFrom, kmTo, p) : 0
    const service = kmFrom ? serviceDaysInWindow(svc, kmFrom, kmTo, p) : 0
    const eff = Math.max(0, season - service)
    return { service, eff, annual: kmFrom ? annualize(kmObserved, eff, p) : null }
  }
  let kw = kmWindow()
  if (kw.annual == null && Number(kmRow?.total_driven) > 0 && own) {
    // Fallback (žádné/příliš krátké protokoly): celkový nájezd z tachometru
    // (aktuální − koupeno s km) za celou dobu vlastnění.
    kmObserved = Number(kmRow.total_driven); kmFrom = own; kmTo = today; kmSource = 'tachometr'
    kw = kmWindow()
  }
  const kmServiceDays = kw.service, kmEffDays = kw.eff, annualKm = kw.annual

  // ── Půjčené dny / rok ────────────────────────────────────────────────────
  // Rezervace jsou evidované od pořízení → okno = doba vlastnění (do dneška).
  let rentedObserved = 0
  const winEnd = today
  for (const b of bookings || []) {
    const s = midnight(b.start_date), e = midnight(b.end_date)
    if (!s || !e) continue
    const end = e > winEnd ? winEnd : e
    if (end < s) continue
    rentedObserved += seasonDaysBetween(s, end, p)   // jen sezónní dny (konzistentně se jmenovatelem)
  }
  const ownSeasonDays = own ? seasonDaysBetween(own, today, p) : 0
  const ownServiceDays = own ? serviceDaysInWindow(svc, own, today, p) : 0
  const ownEffDays = Math.max(0, ownSeasonDays - ownServiceDays)
  const rentedRaw = own ? annualize(rentedObserved, ownEffDays, p) : null   // dopočet z dat (může být null)
  // Bez dostatečných dat = výchozí průměr; dopočet mimo <rentedMin, rentedMax>
  // (zadání: >80 nebo <40) = také průměr, původní dopočet zůstává v `rentedRaw` (UI v závorce).
  let rentedSource = 'data', rentedDays = rentedRaw
  if (rentedRaw == null) { rentedSource = 'odhad'; rentedDays = p.fallbackRentedDays }
  else if (rentedRaw < p.rentedMin || rentedRaw > p.rentedMax) { rentedSource = 'mimo'; rentedDays = p.fallbackRentedDays }
  rentedDays = Math.min(rentedDays, seasonDaysPerYear(p))

  // ── Cena (excel) ─────────────────────────────────────────────────────────
  const serviceYear = (annualKm || 0) * p.kcPerKm
  const costsYear = serviceYear + p.insuranceYear
  const costsPayback = purchase * p.paybackYears + costsYear * p.paybackYears
  const baseNoMargin = rentedDays > 0 ? costsPayback / (rentedDays * p.paybackYears) : 0
  const base = baseNoMargin * (1 + p.margin)
  const days = Object.fromEntries(Object.keys(DAY_COEF).map(k => [k, Math.round(base * DAY_COEF[k])]))
  const currentMon = Number(moto.price_mon ?? moto.price_weekday) || 0

  return {
    purchase, own, kmSource, kmObserved, kmFrom, kmTo, kmEffDays, kmServiceDays, annualKm,
    rentedObserved, ownEffDays, ownServiceDays, rentedRaw, rentedDays, rentedSource,
    serviceYear, costsYear, costsPayback, baseNoMargin, base, days, currentMon,
    diffPct: currentMon > 0 ? (base - currentMon) / currentMon * 100 : null,
    ok: purchase > 0,
  }
}
