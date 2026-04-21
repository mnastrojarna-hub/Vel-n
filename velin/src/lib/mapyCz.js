// ===== Mapy.cz API klient =====
// Centralizovana integrace Mapy.cz API pro Velin.
// Pouzivame ve vsech map-relevantnich flow: SOS incidenty, uprava rezervaci,
// tvorba rezervaci, hledani adres, reverse geocode, vypocet vzdalenosti, mapy.
//
// Dokumentace: https://api.mapy.cz/v1/docs/

export const MAPY_CZ_API_KEY = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0'
export const MAPY_CZ_BASE = 'https://api.mapy.cz/v1'

const HEADERS = { 'X-Mapy-Api-Key': MAPY_CZ_API_KEY }

function qs(params) {
  const u = new URLSearchParams()
  Object.entries(params || {}).forEach(([k, v]) => {
    if (v === undefined || v === null || v === '') return
    u.append(k, String(v))
  })
  return u.toString()
}

async function request(path, params) {
  const url = `${MAPY_CZ_BASE}${path}?${qs({ ...params, apikey: MAPY_CZ_API_KEY, lang: 'cs' })}`
  const res = await fetch(url, { headers: HEADERS })
  if (!res.ok) throw new Error(`Mapy.cz ${path} HTTP ${res.status}`)
  return res.json()
}

// ===== Suggest (autocomplete) =====
// Vrati navrhy pro dany query (regionalni i adresni).
export async function suggest(query, { limit = 8, type } = {}) {
  if (!query || query.trim().length < 2) return []
  try {
    const data = await request('/suggest', {
      query: query.trim(),
      limit,
      lang: 'cs',
      ...(type ? { type } : {}),
    })
    return (data.items || []).map(normalizeSuggest)
  } catch (e) {
    console.warn('[mapyCz] suggest failed', e)
    return []
  }
}

function normalizeSuggest(item) {
  const pos = item.position || {}
  return {
    label: item.name || item.label || '',
    description: item.location || '',
    name: item.name || '',
    zip: item.zip || '',
    lat: pos.lat ?? null,
    lng: pos.lon ?? null,
    type: item.type,
    full: [item.name, item.location].filter(Boolean).join(', '),
    raw: item,
  }
}

// ===== Geocode (forward) =====
// Text -> souradnice + standardizovana adresa.
export async function geocode(address) {
  if (!address) return null
  try {
    const data = await request('/geocode', { query: address, limit: 1 })
    const it = (data.items || [])[0]
    if (!it) return null
    return normalizeSuggest(it)
  } catch (e) {
    console.warn('[mapyCz] geocode failed', e)
    return null
  }
}

// ===== Reverse geocode =====
// Souradnice -> nejblizsi adresa.
export async function rgeocode(lat, lng) {
  try {
    const data = await request('/rgeocode', { lat, lon: lng })
    const it = (data.items || [])[0]
    if (!it) return null
    const addr = it.regionalStructure || []
    const byType = (t) => addr.find(x => x.type === t)?.name || ''
    const street = byType('regional.street') || byType('regional.address') || ''
    const houseNumber = it.name && /\d/.test(it.name) ? it.name.match(/\d+[a-zA-Z]?(?:\/\d+[a-zA-Z]?)?/)?.[0] || '' : ''
    const city = byType('regional.municipality') || byType('regional.municipality_part') || byType('regional.region') || ''
    const zip = it.zip || ''
    const streetLine = [street, houseNumber].filter(Boolean).join(' ').trim() || it.name || ''
    const full = [streetLine, [zip, city].filter(Boolean).join(' ').trim()].filter(Boolean).join(', ')
    return {
      full,
      streetLine,
      street,
      houseNumber,
      city,
      zip,
      label: it.label || it.name || '',
      lat,
      lng,
      raw: it,
    }
  } catch (e) {
    console.warn('[mapyCz] rgeocode failed', e)
    return null
  }
}

// ===== Routing (vzdalenost v km) =====
// Vraci { distanceKm, durationSec } pro autovou trasu mezi dvema GPS body.
export async function routeKm({ startLat, startLng, endLat, endLng, routeType = 'car_fast' } = {}) {
  if ([startLat, startLng, endLat, endLng].some(v => v === undefined || v === null || Number.isNaN(Number(v)))) {
    return null
  }
  try {
    const data = await request('/routing/route', {
      start: `${startLng},${startLat}`,
      end: `${endLng},${endLat}`,
      routeType,
    })
    const lengthM = Number(data?.length ?? data?.summary?.length ?? 0)
    const durationS = Number(data?.duration ?? data?.summary?.duration ?? 0)
    if (!lengthM) return null
    return { distanceKm: lengthM / 1000, durationSec: durationS }
  } catch (e) {
    console.warn('[mapyCz] routeKm failed', e)
    return null
  }
}

// ===== Static tile URL pro Leaflet =====
// Pouzivame pri vestavenych mapach (booking map picker, SOS detail apod.).
export function mapyTileUrl() {
  return `${MAPY_CZ_BASE}/maptiles/basic/256/{z}/{x}/{y}?apikey=${MAPY_CZ_API_KEY}`
}

export function mapyTileAttribution() {
  return '<a href="https://mapy.cz" target="_blank">Mapy.cz</a>, <a href="https://api.mapy.cz/copyright" target="_blank">Seznam.cz a.s.</a>'
}

// ===== Embed URL pro iframe (fallback) =====
// Vygeneruje URL pro vlozeni mapy do iframe (Frame API).
export function mapyEmbedUrl(lat, lng, zoom = 15) {
  if (lat === undefined || lng === undefined) return ''
  return `https://frame.mapy.cz/s/?x=${lng}&y=${lat}&z=${zoom}&source=coor&id=${lng},${lat}`
}

// ===== Prima URL na Mapy.cz pro zobrazeni mista =====
export function mapyLinkUrl(lat, lng, zoom = 15) {
  if (lat === undefined || lng === undefined) return ''
  return `https://mapy.cz/zakladni?x=${lng}&y=${lat}&z=${zoom}&source=coor&id=${lng}%2C${lat}`
}

// ===== Navigovat na dane souradnice =====
export function mapyNavigateUrl(lat, lng) {
  if (lat === undefined || lng === undefined) return ''
  return `https://mapy.cz/fnc/v1/route?waypoints=${lng},${lat}&mode=car_fast`
}

// ===== Vypocet vzdalenosti od pobocky (Mezna) =====
// Fallback na Haversine kdyz routing selze.
export const BRANCH_DEFAULT = { lat: 49.4147, lng: 15.2953 }

export async function routeKmFromBranch(lat, lng, branch = BRANCH_DEFAULT) {
  const r = await routeKm({
    startLat: branch.lat, startLng: branch.lng,
    endLat: lat, endLng: lng,
  })
  if (r?.distanceKm) return r.distanceKm
  return haversineKm(branch.lat, branch.lng, lat, lng)
}

export function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371
  const toRad = x => x * Math.PI / 180
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(a))
}
