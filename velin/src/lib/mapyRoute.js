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
