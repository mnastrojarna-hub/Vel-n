// Statistiky a stav nahrávky projeté jízdy zákazníka ve Velíně — STEJNÁ
// pravidla jako server (`_ride_stats_v2`, `close_stale_user_rides`) a appka
// (RideStatsGrid, RideStage). Velín se nasazuje nezávisle na SQL: bez nových
// sloupců (`pause_sec`, `pause_aware`, `stages`, …) vše funguje postaru.

import { fmtGap } from './rideTrack'

/** Poslední bod mladší než 15 min = živě (shodné s `admin_booking_live_ride`). */
export const LIVE_SEC = 900
const H = 3600

/** Má řádek sloupce z SQL „pauzy jízd"? (Klíč chybí = DB ještě bez nich.) */
export const hasPauseColumns = (ride) => ride != null && ride.pause_aware !== undefined

/**
 * Čísla jízdy spočítal NOVÝ výpočet (pauzy zvlášť, „na cestě" bez pauz)?
 * Stará uzavřená jízda (`stats_state` null) má čísla ze starého výpočtu,
 * kde noci a dlouhá stání sedí v „čase stání" — popisky pak zůstávají staré.
 */
export function rideStatsV2(ride) {
  if (!hasPauseColumns(ride)) return false
  return !(ride.stats_state === null && !ride.is_recording)
}

/** Výpůjčka nové appky, když stav rezervace neznáme (seznam jízd): „visí" až po týdnu bez bodu. */
export const RENTAL_STUCK_SEC = 7 * 24 * H

/**
 * Drží server nahrávku výpůjčky ještě otevřenou? Zrcadlí `close_stale_user_rides`:
 * výpůjčku uzavře jen její konec (vrácení — cron běží po 15 min, proto rezerva
 * 30 min —, dokončení/zrušení, 2 dny po konci bez vrácení), nikdy ticho přes noc.
 * @param b rezervace (`status` nebo `booking_status`, `returned_at`, `end_date`)
 * @returns true (běží) | false (server ji už měl uzavřít) | null (stav neznáme)
 */
export function rentalHoldsRide(b, now = Date.now()) {
  if (!b) return null
  const ret = b.returned_at ? new Date(b.returned_at).getTime() : NaN
  if (Number.isFinite(ret)) return now - ret < 1800e3
  const st = b.booking_status ?? b.status
  if (st === 'completed' || st === 'cancelled') return false
  const end = b.end_date ? String(b.end_date).slice(0, 10) : null
  if (end && end < pragueDay(new Date(now - 24 * H * 1000))) return false
  return st ? true : null
}

/**
 * Po jak dlouhé době bez bodu už nahrávka „visí" (s).
 * `rental` = rentalHoldsRide(rezervace) tam, kde ji známe (Mapa a poloha).
 */
export function rideStuckSec(ride, rental = null) {
  if (!hasPauseColumns(ride)) return 3 * H // server bez pauz uklízí po 3 h
  if (ride.booking_id && rental === false) return 0 // výpůjčka skončila, záznam měl být uzavřen
  if (ride.pause_aware && ride.booking_id) {
    // Výpůjčku server tichem neuzavře, jen jejím koncem — stojící motorka nevisí.
    return rental === true ? Infinity : RENTAL_STUCK_SEC
  }
  if (ride.pause_aware) return 72 * H // vlastní cesta nové appky (při stání nic neposílá)
  return ride.booking_id ? 24 * H : 3 * H // stará appka: výpůjčka / vlastní
}

/**
 * Stav běžící nahrávky: null (neběží) | 'live' | 'standing' | 'stuck'.
 * Stáří bodu bere ze serveru (`age_sec`), jinak z `last_fix_at`.
 * `rental` = rentalHoldsRide(rezervace), pokud ji volající zná.
 */
export function rideRecState(ride, now = Date.now(), rental = null) {
  if (!ride?.is_recording) return null
  let age = Number(ride.age_sec)
  if (ride.age_sec == null || !Number.isFinite(age)) {
    const t = new Date(ride.last_fix_at || ride.updated_at || ride.started_at).getTime()
    age = Number.isFinite(t) ? Math.max(0, (now - t) / 1000) : Infinity
  }
  if (age < LIVE_SEC) return 'live'
  return age >= rideStuckSec(ride, rental) ? 'stuck' : 'standing'
}

/** Kdy zaseknutou / stojící nahrávku uzavře server sám (do věty). */
export function rideAutoCloseHint(ride, rental = null) {
  if (!hasPauseColumns(ride)) return 'do tří hodin od posledního bodu'
  if (ride.booking_id && rental === false) return 'při dalším úklidu (výpůjčka už skončila, úklid běží každých 15 min)'
  if (ride.booking_id) return 'po skončení výpůjčky (vrácení motorky)'
  if (ride.pause_aware) return 'po 72 h bez jízdy (nejpozději 30 dní od startu)'
  return 'do tří hodin od posledního bodu'
}

/** „14:32" dnes, „včera 21:14", jinak „12. 10. 21:14". */
export function fmtSince(v) {
  if (!v) return '—'
  const d = new Date(v)
  if (!Number.isFinite(d.getTime())) return '—'
  const time = d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' })
  const day = (x) => x.toDateString()
  const now = new Date()
  if (day(d) === day(now)) return time
  if (day(d) === day(new Date(now.getTime() - 86400000))) return `včera ${time}`
  return `${d.getDate()}. ${d.getMonth() + 1}. ${time}`
}

/** Dlouhé časy po dnech: „45 min", „3 h 20 min", „2 d 5 h". */
export function fmtLongSec(sec) {
  const min = Math.round(Math.max(0, Number(sec) || 0) / 60)
  if (min < 60) return `${min} min`
  if (min < 1440) return `${Math.floor(min / 60)} h ${min % 60} min`
  const d = Math.floor(min / 1440)
  const h = Math.floor((min % 1440) / 60)
  return h ? `${d} d ${h} h` : `${d} d`
}

const fmtMin = (min) => min == null ? '—' : fmtLongSec(Number(min) * 60)
const fmtSec = (sec) => !sec ? '—' : fmtLongSec(sec)
const fmtSpeed = (v) => v == null || Number(v) <= 0 ? '—' : `${Math.round(Number(v))} km/h`

/** Česky: 1 jízda, 2 jízdy, 5 jízd. */
export function cz(n, one, few, many) {
  return `${n} ${n === 1 ? one : (n >= 2 && n <= 4 ? few : many)}`
}

/** Pražské datum (YYYY-MM-DD) z epoch sekund / ISO — dny počítá server v Praze. */
export function pragueDay(v) {
  const d = typeof v === 'number' ? new Date(v * 1000) : new Date(v)
  if (!Number.isFinite(d.getTime())) return null
  return d.toLocaleDateString('sv-SE', { timeZone: 'Europe/Prague' })
}

/** Etapy (`user_rides.stages`) → [{from,to,km,mv,gap,ps,gain,max,idle,avg}]. */
export function normStages(stages) {
  if (!Array.isArray(stages)) return []
  const out = []
  for (const s of stages) {
    const f = Number(s?.f), t = Number(s?.t)
    if (!s || typeof s !== 'object' || !Number.isFinite(f) || !Number.isFinite(t)) continue
    const n = (k) => Math.max(0, Number(s[k]) || 0)
    const to = Math.max(f, t)
    const km = n('km'), mv = n('mv'), gap = n('gap'), ps = n('ps')
    const avg = mv >= 60 && km > 0 ? km / (mv / 3600) : null
    out.push({
      from: f, to, km, mv, gap, ps, gain: n('gain'),
      max: Number(s.max) > 0 ? Number(s.max) : null,
      idle: Math.max(0, (to - f) - mv - gap - ps),
      avg: avg != null && avg < 200 ? avg : null,
    })
  }
  return out
}

/** Dny na cestě: z etap (dny s ≥ 5 min jízdy), jinak kalendářní dny jízdy. */
export function rideDays(ride, stages = ride?.stages) {
  const st = normStages(stages)
  const set = new Set()
  if (st.length) {
    for (const s of st) {
      if (s.mv < 300) continue
      set.add(pragueDay(s.from)); set.add(pragueDay(s.to))
    }
    return Math.max(1, set.size)
  }
  if (Number(ride?.moving_sec || 0) < 300) return 1
  const a = new Date(ride.started_at).getTime()
  const b = new Date(ride.ended_at || ride.last_fix_at || ride.started_at).getTime()
  if (!Number.isFinite(a) || !Number.isFinite(b)) return 1
  for (let t = a; t <= b + 1; t += 6 * H * 1000) set.add(pragueDay(new Date(t).toISOString()))
  set.add(pragueDay(new Date(b).toISOString()))
  return Math.max(1, set.size)
}

/**
 * Hlavní dlaždice statistik — sdílí je detail jízdy i „Mapa a poloha".
 * @returns {[emoji, label, value, title][]}
 */
export function rideCoreStats(ride, { pauseCount = 0 } = {}) {
  const v2 = rideStatsV2(ride)
  const pause = Number(ride?.pause_sec || 0)
  return [
    ['📏', 'Ujeto', `${Number(ride?.distance_km || 0).toFixed(1)} km`,
      v2 ? 'Ověřené km (bez úseků bez signálu, chůze a přesunů během pauzy)' : 'Ujeto podle stopy (bez úseků bez signálu)'],
    ['🏍️', 'Čas jízdy (v sedle)', fmtSec(ride?.moving_sec), 'Čas, kdy se motorka opravdu pohybovala'],
    ['⏱️', v2 ? 'Na cestě (bez pauz)' : 'Celkový čas', fmtMin(ride?.duration_min),
      v2 ? 'Od startu do konce bez pauz (noci, delší přestávky)' : 'Od startu do konce (spočítáno postaru, včetně nocí)'],
    ['⏸️', v2 ? 'Zastávky (čas)' : 'Čas stání', fmtSec(ride?.idle_sec),
      v2 ? 'Krátká stání během jízdy (křižovatky, tankování, focení) — zbytek času na cestě'
        : 'Stání včetně pauz a nocí (jízda spočítaná postaru)'],
    ...(v2 ? [['🛌', 'Pauzy', pause >= 60 ? (pauseCount > 0 ? `${pauseCount}× · ${fmtLongSec(pause)}` : fmtLongSec(pause)) : '—',
      'Delší přestávky a noci — appka je pozná sama (stání, chůze) nebo je jezdec zapnul ručně; do času na cestě se nepočítají']] : []),
    ['📵', 'Bez signálu', ride?.gap_sec ? fmtGap(ride.gap_sec) : '—',
      'Úseky projeté bez GPS bodů — trasu neznáme a do km se nepočítají'],
    ['📊', 'Ø rychlost', fmtSpeed(ride?.avg_speed_kmh), 'Průměr z času v sedle'],
    ['🚀', 'Max. rychlost', fmtSpeed(ride?.max_speed_kmh),
      v2 ? 'Z rychlosti GPS (Doppler) s kontrolou věrohodnosti' : 'Nejvyšší rychlost z GPS'],
  ]
}
