// Flotila pobočky V ČASE („moto-dny“) — kde motorka v daný den reálně stála.
//
// Výkon poboček nesmí dělit tržby rezervací pobočky (bookings.branch_id, lib/bookingBranch.js)
// AKTUÁLNÍ flotilou: po přesunu motorek Mezná → Velké Němčice by Mezná měla historické tržby
// na 0 motorek a Němčice by nesly fixní náklady motorek, které tam stojí teprve od dneška.
// Proto se každý den každé motorky přiřadí jedné pobočce:
//  1) dny pronájmu → pobočka REZERVACE (kde zákazník převzal);
//  2) zalogované přesuny (admin_audit_log 'motorcycle_migrated', moto_odometer_readings 'transfer');
//  3) dnešek → aktuální pobočka motorky (motorcycles.branch_id);
//  4) mezi dvěma body se shodnou pobočkou = ta pobočka; při neshodě (nezalogovaný přesun) motorka
//     zůstává na předchozí pobočce, ale od MOVES_LOGGED_SINCE už je na té další — od té doby jde každý
//     přesun přes RPC admin_move_motorcycle(s) a je zalogovaný (strážce 20260929g/h). Nezalogovaný
//     přesun před tímto datem se tak projeví nejpozději k tomuto datu (přibližné, víc dat neexistuje).
// Přesun dnes = nečinné dny na nové pobočce až od dneška (ne zpětně za celé období).
// Vozíky (is_trailer) se do flotily nepočítají; vyřazená motorka (retired) jen do posledního záznamu.
import { supabase } from './supabase'
import { effBranchId } from './bookingBranch'
import { isRealizedBooking } from './revenueUtils'
import { FLEET_CALC, calcBikeEconomicsIdle } from './fleetCalc'

const DAY = 86400000
export const MOVES_LOGGED_SINCE = '2026-09-30'
// Roční projekce zisku z méně než ~1 motoměsíce dat je jen šum (1 výpůjčka × 365 / pár dní).
export const MIN_EXPOSURE_DAYS = 30

/** Kalendářní den (lokální datum, jako lib/rentalDays) jako celé číslo; 'YYYY-MM-DD' = lokální půlnoc. */
export function dayNum(x) {
  if (x == null || x === '') return null
  const dt = x instanceof Date ? x : new Date(typeof x === 'string' && x.length <= 10 ? x + 'T00:00:00' : x)
  if (isNaN(dt)) return null
  return Math.round(Date.UTC(dt.getFullYear(), dt.getMonth(), dt.getDate()) / DAY)
}
/** Měsíc (1–12) dne z dayNum. */
export const dayMonth = n => new Date(n * DAY).getUTCMonth() + 1

/** Načte VŠECHNY řádky (PostgREST vrací max. 1000 na dotaz). makeQuery = () => nový builder s .order(). */
export async function fetchAllRows(makeQuery, pageSize = 1000) {
  const out = []
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await makeQuery().range(from, from + pageSize - 1)
    if (error) throw error
    for (const r of data || []) out.push(r)
    if (!data || data.length < pageSize) return out
  }
}

/** fetchAllRows ve tvaru odpovědi supabase-js ({ data, error }) — náhrada dotazu v Promise.all bez dalších úprav. */
export async function fetchAllResult(makeQuery, pageSize = 1000) {
  try { return { data: await fetchAllRows(makeQuery, pageSize), error: null } } catch (error) { return { data: null, error } }
}

/** Zalogované přesuny motorek [{ moto_id, at, from, to }]. Selhání čtení → [] (časová osa jen z rezervací). */
export async function loadMotoMoves() {
  try {
    const [audit, odo] = await Promise.all([
      fetchAllRows(() => supabase.from('admin_audit_log').select('entity_id, created_at, old_data, new_data')
        .eq('action', 'motorcycle_migrated').order('created_at').order('id')),
      fetchAllRows(() => supabase.from('moto_odometer_readings').select('moto_id, recorded_at, branch_id, to_branch_id')
        .eq('kind', 'transfer').order('recorded_at').order('id')),
    ])
    const seen = new Set(), out = []
    const add = (moto_id, at, from, to) => {
      const k = `${moto_id}|${dayNum(at)}|${from}|${to}`
      if (!moto_id || !at || from === to || seen.has(k)) return
      seen.add(k); out.push({ moto_id, at, from: from || null, to: to || null })
    }
    for (const a of audit) if (a.new_data && 'branch_id' in a.new_data) add(a.entity_id, a.created_at, a.old_data?.branch_id, a.new_data.branch_id)
    for (const r of odo) add(r.moto_id, r.recorded_at, r.branch_id, r.to_branch_id)
    return out
  } catch (e) {
    console.warn('loadMotoMoves:', e?.message || e)
    return []
  }
}

/** Okno období TimePeriodSelectoru jako dny {fromDay, toDay, days}; konec nejpozději dnes. 'all' = od 1. rezervace. */
export function periodWindow(period, bookings, today = dayNum(new Date())) {
  let f, t
  if (period?.type === 'month') { f = dayNum(new Date(period.year, period.month, 1)); t = dayNum(new Date(period.year, period.month + 1, 0)) }
  else if (period?.type === 'calendar_year') { f = dayNum(new Date(period.year, 0, 1)); t = dayNum(new Date(period.year, 11, 31)) }
  else if (period?.type === 'fiscal_year') { f = dayNum(new Date(period.year - 1, 3, 1)); t = dayNum(new Date(period.year, 2, 31)) }
  else if (period?.type === 'custom') {
    if (!period.from || !period.to) return { fromDay: today, toDay: today - 1, days: 0 } // jako filterByPeriod: nic
    f = dayNum(period.from); t = dayNum(period.to)
  } else {
    f = today
    for (const b of bookings || []) if (isAnchor(b)) { const s = dayNum(b.start_date); if (s != null && s < f) f = s }
    t = today
  }
  t = Math.min(t, today)
  return { fromDay: f, toDay: t, days: Math.max(0, t - f + 1) }
}

function isAnchor(b) {
  return !!b && b.is_test !== true && b.status !== 'cancelled' && (b.status !== 'pending' || isRealizedBooking(b))
}
const upper = (keys, x) => { let lo = 0, hi = keys.length; while (lo < hi) { const m = (lo + hi) >> 1; if (keys[m] <= x) lo = m + 1; else hi = m } return lo }

/**
 * Časová osa flotily v okně [fromDay, toDay]. Vrací { fromDay, toDay, motos: [{ moto, start, loc[], rented[], revByBranch }] }
 * (loc[i] = pobočka dne start+i, rented[i] = den realizovaného pronájmu, revByBranch = tržba rozpuštěná do dnů okna).
 */
export function buildFleetTimeline({ motorcycles, bookings, moves, fromDay, toDay, today = dayNum(new Date()), includeTrailers = false }) {
  const motoBranchMap = Object.fromEntries((motorcycles || []).map(m => [m.id, m.branch_id]))
  const logDay = dayNum(MOVES_LOGGED_SINCE)
  const byMoto = {}
  const push = (id, a) => { if (id) (byMoto[id] ||= { a: [], m: [] }).a.push(a) }
  for (const b of bookings || []) {
    if (!isAnchor(b)) continue
    const s = dayNum(b.start_date), e0 = dayNum(b.end_date)
    if (s == null) continue
    const e = Math.max(s, e0 ?? s), loc = effBranchId(b, motoBranchMap)
    const rented = isRealizedBooking(b)
    push(b.moto_id, { s, e, loc, rented, price: rented ? (Number(b.total_price) || 0) : 0 })
    if (b.trailer_moto_id) push(b.trailer_moto_id, { s, e, loc: b.branch_id || motoBranchMap[b.trailer_moto_id] || null, rented: false, price: 0 })
  }
  for (const mv of moves || []) if (byMoto[mv.moto_id] || motoBranchMap[mv.moto_id] !== undefined) (byMoto[mv.moto_id] ||= { a: [], m: [] }).m.push({ d: dayNum(mv.at), from: mv.from, to: mv.to })

  const out = []
  for (const moto of motorcycles || []) {
    if (moto.is_trailer && !includeTrailers) continue
    const ev = byMoto[moto.id] || { a: [], m: [] }
    const A = ev.a.slice().sort((x, y) => x.s - y.s), M = ev.m.filter(x => x.d != null).sort((x, y) => x.d - y.d)
    const firsts = [...A.map(x => x.s), ...M.map(x => x.d)], lasts = [...A.map(x => x.e), ...M.map(x => x.d)]
    const acq = dayNum(moto.acquired_at) ?? dayNum(moto.created_at)
    let pStart = Math.min(acq ?? Infinity, ...firsts)
    if (!isFinite(pStart)) pStart = fromDay
    const pEnd = moto.status === 'retired' ? (lasts.length ? Math.max(...lasts) : -Infinity) : Infinity
    const a = Math.max(fromDay, pStart), z = Math.min(toDay, pEnd)
    if (!(a <= z)) continue
    const n = z - a + 1, loc = new Array(n).fill(undefined), rented = new Uint8Array(n), revByBranch = {}
    for (const x of A) {
      const len = x.e - x.s + 1
      for (let d = Math.max(x.s, a); d <= Math.min(x.e, z); d++) {
        loc[d - a] = x.loc
        if (x.rented) { rented[d - a] = 1; if (x.loc) revByBranch[x.loc] = (revByBranch[x.loc] || 0) + x.price / len }
      }
    }
    const ends = A.slice().sort((x, y) => x.e - y.e), endK = ends.map(x => x.e), startK = A.map(x => x.s), moveK = M.map(x => x.d)
    const cur = moto.branch_id || null
    for (let i = 0; i < n; i++) {
      if (loc[i] !== undefined) continue
      const d = a + i
      let prev = null, next = null
      const pe = upper(endK, d - 1) - 1; if (pe >= 0) prev = { at: endK[pe], loc: ends[pe].loc, r: 0 }
      const pm = upper(moveK, d) - 1; if (pm >= 0 && (!prev || M[pm].d >= prev.at)) prev = { at: M[pm].d, loc: M[pm].to, r: 2 }
      if (today <= d && (!prev || today > prev.at || (today === prev.at && prev.r < 1))) prev = { at: today, loc: cur, r: 1 }
      const ns = upper(startK, d); if (ns < A.length) next = { at: A[ns].s, loc: A[ns].loc }
      const nm = upper(moveK, d); if (nm < M.length && (!next || M[nm].d <= next.at)) next = { at: M[nm].d, loc: M[nm].from }
      if (today > d && (!next || today < next.at)) next = { at: today, loc: cur }
      loc[i] = !prev ? next?.loc ?? cur : !next ? prev.loc : prev.loc === next.loc ? prev.loc : (d >= logDay ? next.loc : prev.loc)
    }
    out.push({ moto, start: a, loc, rented, revByBranch })
  }
  return { fromDay, toDay, motos: out }
}

/** Souhrn po pobočkách: { [branchId]: { motoDays, rentedDays, revenue, perMoto: {id: dny}, cats: {kat: {motoDays, rentedDays, revenue}} } }. */
export function summarizeByBranch(tl, catOf = m => (m.category || 'naked').toLowerCase()) {
  const out = {}
  const get = b => (out[b] ||= { motoDays: 0, rentedDays: 0, revenue: 0, perMoto: {}, cats: {} })
  const cget = (s, c) => (s.cats[c] ||= { motoDays: 0, rentedDays: 0, revenue: 0 })
  for (const t of tl?.motos || []) {
    const cat = catOf(t.moto)
    for (let i = 0; i < t.loc.length; i++) {
      const b = t.loc[i]
      if (!b) continue
      const s = get(b), c = cget(s, cat)
      s.motoDays++; c.motoDays++
      s.perMoto[t.moto.id] = (s.perMoto[t.moto.id] || 0) + 1
      if (t.rented[i]) { s.rentedDays++; c.rentedDays++ }
    }
    for (const [b, v] of Object.entries(t.revByBranch)) { const s = get(b); s.revenue += v; cget(s, cat).revenue += v }
  }
  return out
}

/** Fixní roční náklady motorky (servis + pojištění/čištění + ostatní) — jako calcBikeEconomicsIdle. */
export const fixedAnnualCost = moto => calcBikeEconomicsIdle(moto || {}).totalCosts

/**
 * Roční projekce zisku na motorku pobočky = (tržba rozpuštěná do dnů okna × (1 − marketing)
 * − fixní náklady motorek poměrně dle dnů na pobočce) × 365 / moto-dny. Pod MIN_EXPOSURE_DAYS → null.
 */
export function profitPerMotoYear(stat, motosById) {
  if (!stat || stat.motoDays < MIN_EXPOSURE_DAYS) return null
  let fixed = 0
  for (const [id, days] of Object.entries(stat.perMoto)) fixed += fixedAnnualCost(motosById[id]) * days / 365
  return (stat.revenue * (1 - FLEET_CALC.marketingPct) - fixed) * 365 / stat.motoDays
}
