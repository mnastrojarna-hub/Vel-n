// MotoGo24 — dekódování trasy z Mapy.com odkazu
//
// Mapy.cz/.com kódují body trasy v URL parametru `rc` proprietárním
// delta-kódováním (custom base64, řetězec se čte odzadu, přesnost 2^28).
// Algoritmus ověřen proti reálnému odkazu (první bod = pobočka Mezná).
//
// Použití:
//   - plná URL s `rc=...` → decodeRouteCoords(getRcFromUrl(url))
//   - zkrácený odkaz mapy.com/s/... → musí rozbalit edge fn resolve-mapy-route
//     (prohlížeč kvůli CORS redirect nepřečte), pak decodeRouteCoords.

const ALPHABET = '0ABCD2EFGH4IJKLMN6OPQRST8UVWXYZ-1abcd3efgh5ijklmn7opqrst9uvwxyz.'

const r6 = (v) => Math.round(Number(v) * 1e6) / 1e6

function parseNumber(arr, count) {
  let result = 0
  let i = count
  while (i) {
    if (!arr.length) throw new Error('Neplatná data trasy (rc)')
    const ch = arr.pop()
    const index = ALPHABET.indexOf(ch)
    if (index === -1) continue
    result = (result << 6) + index
    i--
  }
  return result
}

/** Dekóduje `rc` parametr → pole bodů [{lat,lng}] v pořadí trasy. */
export function decodeRouteCoords(rc) {
  if (!rc) return []
  const FIVE = (1 + 2) << 4 // 48
  const THREE = 1 << 5      // 32
  const results = []
  const coords = [0, 0]     // [lonInt, latInt] akumulátory (delta)
  let ci = 0
  const arr = String(rc).trim().split('').reverse()
  while (arr.length) {
    let num = parseNumber(arr, 1)
    if ((num & FIVE) === FIVE) {
      num -= FIVE
      num = ((num & 15) << 24) + parseNumber(arr, 4)
      coords[ci] = num
    } else if ((num & THREE) === THREE) {
      num = ((num & 15) << 12) + parseNumber(arr, 2)
      num -= 1 << 15
      coords[ci] += num
    } else {
      num = ((num & 31) << 6) + parseNumber(arr, 1)
      num -= 1 << 10
      coords[ci] += num
    }
    if (ci) {
      const lng = (coords[0] * 360) / (1 << 28) - 180
      const lat = (coords[1] * 180) / (1 << 28) - 90
      results.push({ lat: Math.round(lat * 1e6) / 1e6, lng: Math.round(lng * 1e6) / 1e6 })
    }
    ci = (ci + 1) % 2
  }
  return results
}

/** Z textu (URL i celý <iframe …> kód) vytáhne mapy.com/.cz URL. */
export function extractMapyUrl(text) {
  if (!text) return null
  const t = String(text).trim()
  const src = t.match(/src=["']([^"']*mapy\.(?:com|cz)[^"']*)["']/i)
  if (src) return src[1]
  const url = t.match(/https?:\/\/[^\s"']*mapy\.(?:com|cz)[^\s"']*/i)
  if (url) return url[0]
  return null
}

/** Je odkaz z Google Maps (plný i zkrácený goo.gl / maps.app.goo.gl)? */
export function isGoogleMapsUrl(url) {
  return /(?:google\.[a-z.]+\/maps|maps\.app\.goo\.gl|goo\.gl\/maps)/i.test(url || '')
}

/** Zkrácený Google odkaz (maps.app.goo.gl/… / goo.gl/maps/…) — nutno rozbalit. */
export function isGoogleShareLink(url) {
  return /(?:maps\.app\.goo\.gl|goo\.gl\/maps)\//i.test(url || '')
}

/**
 * Z textu vytáhne odkaz na Mapy.com NEBO Google Maps (i z <iframe> src).
 * Vrací { url, provider:'mapy'|'google' } nebo null.
 */
export function extractMapUrl(text) {
  if (!text) return null
  const t = String(text).trim()
  const mapy = extractMapyUrl(t)
  if (mapy) return { url: mapy, provider: 'mapy' }
  const gsrc = t.match(/src=["']([^"']*(?:google\.[a-z.]+\/maps|maps\.app\.goo\.gl|goo\.gl\/maps)[^"']*)["']/i)
  if (gsrc) return { url: gsrc[1], provider: 'google' }
  const gurl = t.match(/https?:\/\/[^\s"']*(?:google\.[a-z.]+\/maps|maps\.app\.goo\.gl|goo\.gl\/maps)[^\s"']*/i)
  if (gurl) return { url: gurl[0], provider: 'google' }
  return null
}

/**
 * Dekóduje body trasy z PLNÉ Google Maps URL (google.com/maps/dir/…).
 * Podporuje dva tvary:
 *   1) `data=…!1d<lng>!2d<lat>…` (běžný /dir/ odkaz z prohlížeče) — každá
 *      zastávka je dvojice `!1d<lng>!2d<lat>` v pořadí trasy,
 *   2) `?api=1&origin=lat,lng&waypoints=lat,lng|…&destination=lat,lng`
 *      (oficiální sdílecí/deeplink formát).
 * Fallback: `/@lat,lng` střed → jeden bod. Vrací pole [{lat,lng}] (pořadí trasy).
 * Zkrácený maps.app.goo.gl NEJDE dekódovat v prohlížeči (CORS redirect) —
 * musí ho rozbalit edge fn resolve-mapy-route.
 */
export function decodeGoogleRouteCoords(url) {
  if (!url) return []
  const s = String(url)
  const out = []

  // 1) data param: …!1d<lng>!2d<lat>… (pořadí = pořadí v řetězci)
  const re = /!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)/g
  let m
  while ((m = re.exec(s)) !== null) {
    const lng = Number(m[1]); const lat = Number(m[2])
    if (isFinite(lat) && isFinite(lng)) out.push({ lat: r6(lat), lng: r6(lng) })
  }
  if (out.length) return out

  // 2) api=1 query (origin / waypoints / destination jako "lat,lng")
  try {
    const u = new URL(s)
    const q = u.searchParams
    const pushLL = (val) => {
      if (!val) return
      const parts = String(val).split(',').map(x => Number(x.trim()))
      if (parts.length >= 2 && isFinite(parts[0]) && isFinite(parts[1])) {
        out.push({ lat: r6(parts[0]), lng: r6(parts[1]) })
      }
    }
    pushLL(q.get('origin'))
    const wp = q.get('waypoints')
    if (wp) wp.split('|').forEach(pushLL)
    pushLL(q.get('destination'))
    if (out.length) return out
    // 3) /@lat,lng střed → aspoň jeden bod (POI)
    const at = s.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/)
    if (at) { const lat = Number(at[1]); const lng = Number(at[2]); if (isFinite(lat) && isFinite(lng)) out.push({ lat: r6(lat), lng: r6(lng) }) }
    // 3b) /place/…!3d<lat>!4d<lng> → jeden bod
    const pl = s.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/)
    if (!out.length && pl) { const lat = Number(pl[1]); const lng = Number(pl[2]); if (isFinite(lat) && isFinite(lng)) out.push({ lat: r6(lat), lng: r6(lng) }) }
  } catch { /* neplatná URL */ }
  return out
}

/** Vrátí hodnotu `rc` z URL, nebo null. */
export function getRcFromUrl(url) {
  try {
    return new URL(url).searchParams.get('rc')
  } catch {
    return null
  }
}

/** Je to zkrácený sdílecí odkaz (mapy.com/s/…)? */
export function isShareLink(url) {
  return /mapy\.(?:com|cz)\/s\//i.test(url || '')
}

/**
 * Dekóduje zakódovaný polyline řetězec (standardní Google algoritmus) →
 * pole `[[lng,lat],…]` (GeoJSON pořadí). `factor` = 1e5 (přesnost 5) nebo 1e6.
 * Mapy routing vrací geometrii buď jako GeoJSON, nebo jako tento řetězec.
 */
export function decodePolyline(str, factor = 1e5) {
  if (!str || typeof str !== 'string') return []
  let index = 0, lat = 0, lng = 0
  const coords = []
  while (index < str.length) {
    let b, shift = 0, result = 0
    do { b = str.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
    lat += (result & 1) ? ~(result >> 1) : (result >> 1)
    shift = 0; result = 0
    do { b = str.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
    lng += (result & 1) ? ~(result >> 1) : (result >> 1)
    coords.push([lng / factor, lat / factor])
  }
  return coords
}

/**
 * Vytáhne geometrii trasy z odpovědi Mapy routing API v JAKÉMKOLIV tvaru:
 * GeoJSON (Feature / geometry / FeatureCollection) i zakódovaný polyline string.
 * `refLngLat` = orientační bod [lng,lat] (waypoint) pro výběr správné přesnosti
 * polyline. Vrací `[[lng,lat],…]` nebo null.
 */
export function extractRouteGeometry(data, refLngLat) {
  if (!data) return null
  // 1) GeoJSON varianty
  const g =
    data?.geometry?.geometry?.coordinates ||
    data?.geometry?.coordinates ||
    data?.features?.[0]?.geometry?.coordinates ||
    data?.shape?.coordinates ||
    null
  if (Array.isArray(g) && g.length >= 2 && Array.isArray(g[0])) return g
  // 2) Zakódovaný polyline string (na různých místech)
  const str =
    (typeof data?.geometry === 'string' && data.geometry) ||
    (typeof data?.geometry?.geometry === 'string' && data.geometry.geometry) ||
    (typeof data?.shape === 'string' && data.shape) ||
    (typeof data?.geometry?.points === 'string' && data.geometry.points) ||
    null
  if (str) {
    const ref = Array.isArray(refLngLat) ? refLngLat : null
    for (const f of [1e5, 1e6]) {
      const dec = decodePolyline(str, f)
      if (dec.length < 2) continue
      if (!ref || (Math.abs(dec[0][0] - ref[0]) < 1.5 && Math.abs(dec[0][1] - ref[1]) < 1.5)) {
        return dec
      }
    }
  }
  return null
}
