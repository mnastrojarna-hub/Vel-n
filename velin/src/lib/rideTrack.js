// Práce se stopou projeté jízdy (`user_rides.track`) ve Velíně.
//
// Bod stopy = [lat, lng, čas (epoch s), rychlost km/h, výška m]; povinné jsou
// jen první dva prvky (starý klient posílal jen [lat,lng]).
//
// Proč to tu je: když appka běžela na pozadí bez foreground service, GPS fixy
// nechodily a mezi dvěma sousedními body je klidně hodina a 40 kilometrů.
// Spojit takové body plnou čarou znamená tvrdit, že tudy zákazník jel.
// Mapa i statistiky proto musí takový úsek umět oddělit — stejnou hranicí,
// jakou používá server (`_ride_stats` v 20260921f_user_rides_real_track.sql).

/** Delší pauza mezi fixy už není souvislá jízda (shodné se serverem). */
export const GAP_SEC = 180
/** Posun do 50 m bereme jako „stál na místě", ne jako mezeru v trase. */
export const STILL_KM = 0.05

/** Vzdálenost dvou bodů v km (haversine). */
export function distKm(a, b) {
  const R = 6371
  const rad = (d) => (d * Math.PI) / 180
  const dLat = rad(b[0] - a[0])
  const dLng = rad(b[1] - a[1])
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLng / 2) ** 2
  return R * 2 * Math.asin(Math.sqrt(h))
}

/** „1 h 20 min" / „45 min" / „30 s" — pro popisky mezer. */
export function fmtGap(sec) {
  const s = Math.round(Number(sec) || 0)
  if (s < 60) return `${s} s`
  if (s < 3600) return `${Math.round(s / 60)} min`
  const h = Math.floor(s / 3600)
  const m = Math.round((s % 3600) / 60)
  return m ? `${h} h ${m} min` : `${h} h`
}

/** Bod stopy → [lat, lng] jako čísla, nebo null když je bod rozbitý. */
function coords(p) {
  if (!Array.isArray(p) || p.length < 2) return null
  const lat = Number(p[0]); const lng = Number(p[1])
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null
  return [lat, lng]
}

/**
 * Rozdělí stopu na SOUVISLÉ úseky a mezery mezi nimi.
 *
 * Vrací pole úseků `{ pts: [[lat,lng],…], gapBefore: {from,to,sec,km,label}|null }`.
 * `gapBefore` má jen úsek, před kterým byla mezera — mapa ho pak kreslí
 * přerušovaně a šedě.
 *
 * Stopa bez časových značek (starý klient) se nedělí vůbec — u ní nemáme
 * podle čeho poznat, kde byla díra, a řezat ji podle vzdálenosti by rozbilo
 * legitimní ručně poskládané trasy.
 */
export function splitTrackOnGaps(track, gapSec = GAP_SEC, stillKm = STILL_KM) {
  // Jedním průchodem: souřadnice + čas, rozbité body rovnou pryč.
  const pts = []
  for (const p of (Array.isArray(track) ? track : [])) {
    const ll = coords(p)
    if (!ll) continue
    const ts = Array.isArray(p) && p.length > 2 ? Number(p[2]) : NaN
    pts.push({ ll, ts: Number.isFinite(ts) ? ts : null })
  }
  if (!pts.length) return []

  const segments = []
  let cur = { pts: [pts[0].ll], gapBefore: null }
  // Bod bez času si drží čas předchozího bodu — stejně jako server.
  let prevTs = pts[0].ts

  for (let i = 1; i < pts.length; i++) {
    const { ll, ts } = pts[i]
    const dt = ts != null && prevTs != null ? ts - prevTs : null
    const km = distKm(pts[i - 1].ll, ll)
    const isGap = dt != null && dt > gapSec && dt < 86400 && km > stillKm

    if (isGap) {
      segments.push(cur)
      cur = {
        pts: [ll],
        gapBefore: {
          from: pts[i - 1].ll, to: ll,
          sec: Math.round(dt), km: Math.round(km * 10) / 10,
          label: fmtGap(dt),
        },
      }
    } else {
      cur.pts.push(ll)
    }
    if (ts != null) prevTs = ts
  }
  segments.push(cur)
  return segments
}

/**
 * Posouzení kvality stopy — Velín podle toho pozná, jestli má co zobrazit,
 * nebo jestli jde o „trasu" slepenou z pár náhodných fixů.
 */
export function trackQuality(ride, track) {
  const t = Array.isArray(track) ? track : (Array.isArray(ride?.track) ? ride.track : [])
  const points = t.length
  const km = Number(ride?.distance_km || 0)
  const gapSec = Number(ride?.gap_sec || 0)
  const segments = splitTrackOnGaps(t)
  const gaps = segments.filter(s => s.gapBefore).length
  // Slušná stopa má při 20m filtru desítky bodů na kilometr. Pod 5 už to
  // není trasa, ale spojnice náhodných fixů.
  const perKm = km > 0 ? points / km : null
  const sparse = points < 10 || (perKm != null && perKm < 5)
  return { points, gaps, gapSec, segments, perKm, sparse, hasTimestamps: t.some(p => Array.isArray(p) && p.length > 2) }
}

/** Stáří posledního GPS fixu v sekundách (null = neznámé). */
export function fixAgeSec(lastFixAt, now = Date.now()) {
  if (!lastFixAt) return null
  const t = new Date(lastFixAt).getTime()
  if (!Number.isFinite(t)) return null
  return Math.max(0, Math.round((now - t) / 1000))
}
