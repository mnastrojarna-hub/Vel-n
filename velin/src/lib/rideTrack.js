// Práce se stopou projeté jízdy (`user_rides.track`) ve Velíně.
//
// Bod stopy = [lat, lng, čas (epoch s), rychlost km/h, výška m]; povinné jsou
// jen první dva prvky (starý klient posílal jen [lat,lng]). Rychlost −1 je
// ZNAČKA PAUZY: nová appka ji dává prvnímu bodu po pauze (ruční i auto-pauza)
// — úsek od předchozího bodu je pauza (noc, oběd, trajekt), ne jízda.
//
// Proč to tu je: když appka běžela na pozadí bez foreground service, GPS fixy
// nechodily a mezi dvěma sousedními body je klidně hodina a 40 kilometrů.
// Spojit takové body plnou čarou znamená tvrdit, že tudy zákazník jel.
// Mapa i statistiky proto musí takový úsek umět oddělit — stejnými pravidly
// jako server (`_ride_stats_v2`) a appka (`_splitOnGaps` v ride_model.dart):
//   značka pauzy → PAUZA; ticho > 3 min projeté ≥ 15 km/h a > 300 m → BEZ
//   SIGNÁLU (mezera); jinak ticho ≥ 5 min → PAUZA (noc, delší stání).

/** Delší pauza mezi fixy už není souvislá jízda (shodné se serverem). */
export const GAP_SEC = 180
/** Posun do 300 m bereme jako „stál na místě", ne jako mezeru v trase.
 *  (Při filtru 20 m + intervalu 5 s je první fix po rozjezdu 40–100 m od
 *  posledního; 50 m dělalo mezeru i z tříminutového tankování.) */
export const STILL_KM = 0.3
/** Ticho od 5 min, kterým se neprojelo, je pauza (noc, delší stání). */
export const PAUSE_SEC = 300
/** Ticho projeté aspoň touhle rychlostí je výpadek signálu, ne pauza. */
export const THROUGH_KMH = 15
/** Větší časový skok = rozbitý čas telefonu, nic se nepočítá (30 dní). */
export const BAD_DT_SEC = 2592000

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
 * Rozdělí stopu na SOUVISLÉ úseky a přerušení mezi nimi.
 *
 * Vrací pole úseků `{ pts: [[lat,lng],…], gapBefore: {…}|null }`, kde
 * `gapBefore` = `{ kind: 'gap'|'pause', from, to, sec, km, moved, label,
 * fromTs, toTs }`. `kind: 'gap'` = bez signálu (mapa šedě přerušovaně),
 * `'pause'` = pauza (spojnice jen při přesunu > 300 m — `moved`).
 *
 * Stopa bez časových značek (starý klient) se nedělí vůbec — u ní nemáme
 * podle čeho poznat, kde byla díra, a řezat ji podle vzdálenosti by rozbilo
 * legitimní ručně poskládané trasy.
 */
export function splitTrackOnGaps(track, gapSec = GAP_SEC, stillKm = STILL_KM) {
  // Jedním průchodem: souřadnice + čas + značka pauzy, rozbité body pryč.
  const pts = []
  for (const p of (Array.isArray(track) ? track : [])) {
    const ll = coords(p)
    if (!ll) continue
    const ts = p.length > 2 && p[2] != null ? Number(p[2]) : NaN
    const kmh = p.length > 3 && p[3] != null ? Number(p[3]) : NaN
    pts.push({ ll, ts: Number.isFinite(ts) ? ts : null, flag: kmh < 0 })
  }
  if (!pts.length) return []

  const segments = []
  let cur = { pts: [pts[0].ll], gapBefore: null }
  // Bod bez času si drží čas předchozího bodu — stejně jako server.
  let prevTs = pts[0].ts

  for (let i = 1; i < pts.length; i++) {
    const { ll, ts, flag } = pts[i]
    const dt = ts != null && prevTs != null ? ts - prevTs : null
    const km = distKm(pts[i - 1].ll, ll)
    let kind = null
    if (dt != null && dt >= 0 && dt < BAD_DT_SEC) {
      const through = dt > 0 && (km / dt) * 3600 >= THROUGH_KMH && km > stillKm
      if (flag) kind = 'pause'
      else if (dt > gapSec) kind = through ? 'gap' : (dt >= PAUSE_SEC ? 'pause' : null)
    }

    if (kind) {
      segments.push(cur)
      cur = {
        pts: [ll],
        gapBefore: {
          kind, from: pts[i - 1].ll, to: ll,
          sec: Math.round(dt), km: Math.round(km * 10) / 10, moved: km > stillKm,
          label: fmtGap(dt), fromTs: prevTs, toTs: ts,
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

/** Pauzy ve stopě (značky appky + ticha ≥ 5 min bez jízdy): počet a čas. */
export function trackPauses(track) {
  let count = 0, sec = 0
  for (const s of splitTrackOnGaps(track)) {
    if (s.gapBefore?.kind !== 'pause') continue
    count++
    sec += s.gapBefore.sec
  }
  return { count, sec }
}

/**
 * Posouzení kvality stopy — Velín podle toho pozná, jestli má co zobrazit,
 * nebo jestli jde o „trasu" slepenou z pár náhodných fixů.
 */
export function trackQuality(ride, track, pointCount) {
  const t = Array.isArray(track) ? track : (Array.isArray(ride?.track) ? ride.track : [])
  // RPC pro živou mapu stopu prořídne na 1200 bodů, ale skutečný počet posílá
  // zvlášť — bez něj by dlouhá jízda (> ~240 km) vypadala jako „řídká".
  const points = Number.isFinite(pointCount) && pointCount > 0 ? pointCount : t.length
  const km = Number(ride?.distance_km || 0)
  const gapSec = Number(ride?.gap_sec || 0)
  const segments = splitTrackOnGaps(t)
  // Výpadky signálu zvlášť od pauz — pauza (noc, oběd) není vada záznamu.
  const gaps = segments.filter(s => s.gapBefore?.kind === 'gap').length
  const pauses = segments.filter(s => s.gapBefore?.kind === 'pause').length
  // Slušná stopa má při 20m filtru desítky bodů na kilometr. Pod 5 už to
  // není trasa, ale spojnice náhodných fixů.
  const perKm = km > 0 ? points / km : null
  // Stopa s tisícem a víc bodů není „pár náhodných fixů" — u dlouhé jízdy
  // ji server prořídne (strop 4000 / 1200) a bodů na km ubude přirozeně.
  const sparse = points < 10 || (perKm != null && perKm < 5 && points < 1000)
  return { points, gaps, pauses, gapSec, segments, perKm, sparse, hasTimestamps: t.some(p => Array.isArray(p) && p.length > 2) }
}

/** Stáří posledního GPS fixu v sekundách (null = neznámé). */
export function fixAgeSec(lastFixAt, now = Date.now()) {
  if (!lastFixAt) return null
  const t = new Date(lastFixAt).getTime()
  if (!Number.isFinite(t)) return null
  return Math.max(0, Math.round((now - t) / 1000))
}
