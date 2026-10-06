import { supabase } from '../lib/supabase'

// ─── Hudba pobočky — čistá logika (bez JSX) ──────────────────────────────────
// Tabulka branch_music_tracks + bucket branch-music (public read, cesta <branch_id>/<track_id>.<ext>).
// Cíle: 'all' (společná), 'outdoor' (venek), 'door:<uuid>' (kóje / šatna). Kontrakt: scratchpad music_contract.md §0/§5.

export const BUCKET = 'branch-music'
export const MAX_SIZE_BYTES = 200 * 1024 * 1024
export const ALLOWED_EXT = ['mp3', 'wav', 'flac', 'ogg', 'oga', 'opus', 'm4a', 'aac', 'wma', 'aiff', 'aif', 'webm', 'mkv', 'mp4a']
export const ACCEPT = ['audio/*', ...ALLOWED_EXT.map(e => `.${e}`)].join(',')

const MIME_BY_EXT = {
  mp3: 'audio/mpeg', wav: 'audio/wav', flac: 'audio/flac', ogg: 'audio/ogg', oga: 'audio/ogg', opus: 'audio/opus',
  m4a: 'audio/mp4', mp4a: 'audio/mp4', aac: 'audio/aac', wma: 'audio/x-ms-wma', aiff: 'audio/aiff', aif: 'audio/aiff',
  webm: 'audio/webm', mkv: 'audio/x-matroska',
}

export function extOf(name) {
  const m = /\.([a-z0-9]+)$/i.exec(String(name || ''))
  return m ? m[1].toLowerCase() : ''
}
export function titleOf(name) { return String(name || '').replace(/\.[^.]+$/, '').trim() || 'Skladba' }
export function isAllowedFile(file) {
  if (!file) return false
  const ext = extOf(file.name)
  return ALLOWED_EXT.includes(ext) || String(file.type || '').startsWith('audio/')
}
export function mimeFor(file) { return (file?.type && String(file.type)) || MIME_BY_EXT[extOf(file?.name)] || 'application/octet-stream' }
export function formatBytes(n) {
  const v = Number(n)
  if (!Number.isFinite(v) || v <= 0) return '—'
  if (v < 1024 * 1024) return `${Math.round(v / 1024)} kB`
  return `${(v / (1024 * 1024)).toFixed(1)} MB`
}
export function publicUrl(filePath) {
  if (!filePath) return ''
  return supabase.storage.from(BUCKET).getPublicUrl(filePath).data?.publicUrl || ''
}
// URL vynucující stažení (Content-Disposition: attachment) — atribut `download` prohlížeč u cizí domény ignoruje.
// Název bez znaků, které encodeURI nechává (& # ? / + …) a rozbily by query string.
export function downloadUrl(filePath, name) {
  if (!filePath) return ''
  const safe = String(name || 'skladba').replace(/[\\/?#&%+;=]/g, '-').replace(/[\u0000-\u001f]/g, '').trim() || 'skladba'
  return supabase.storage.from(BUCKET).getPublicUrl(filePath, { download: safe }).data?.publicUrl || ''
}
function newId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
  })
}

// ── Konec přehrávání skladby (branch_music_tracks.end_s, 2026-10-06; DB CHECK 0 < end_s ≤ 7200, NULL = celá) ──
export const END_MAX_S = 7200
export const END_MIN_S = 5   // pojistka Velína (DB bere > 0): kratší konec je skoro jistě překlep („4“ místo „4:00“)
const pad2 = n => String(n).padStart(2, '0')
// Sekundy → 'm:ss' / 'h:mm:ss' (desetiny zachová: 242.5 → '4:02.5'); null/neplatné → ''
export function formatEndTime(sec) {
  const v = sec == null || sec === '' ? NaN : Number(sec)
  if (!Number.isFinite(v) || v <= 0) return ''
  const whole = Math.floor(v)
  const frac = Math.round((v - whole) * 1000) / 1000
  const s = whole % 60, m = Math.floor(whole / 60) % 60, h = Math.floor(whole / 3600)
  const ss = pad2(s) + (frac > 0 ? String(frac).slice(1) : '')
  return h > 0 ? `${h}:${pad2(m)}:${ss}` : `${Math.floor(whole / 60)}:${ss}`
}
// Text z políčka → { value: sekundy | null (prázdné = celá skladba) } nebo { error }.
// Přijímá 'm:ss' / 'h:mm:ss' (desetiny jen za sekundami: '4:02.5', čárka i tečka) a CELÉ sekundy ('242').
// Desetinné číslo bez dvojtečky ('4.02', '4,02') odmítne — česky se tak píše čas („10.30“) a uložilo by se 4,02 s.
export function parseEndTime(text) {
  const t = String(text ?? '').trim().replace(',', '.')
  if (t === '') return { value: null }
  const dec = /^(\d+)\.(\d+)$/.exec(t)
  if (dec) {
    const guess = dec[2].length === 2 && Number(dec[2]) < 60 ? `Myslíte ${Number(dec[1])}:${dec[2]}? ` : ''
    return { error: `${guess}Čas zadejte s dvojtečkou jako m:ss (např. 4:02) nebo v celých sekundách (242).` }
  }
  const m = /^(?:(\d+):)?(?:(\d+):)?(\d+(?:\.\d+)?)$/.exec(t)
  const bad = { error: 'Konec zadejte jako m:ss (např. 4:02) nebo v celých sekundách; prázdné = celá skladba.' }
  if (!m) return bad
  const parts = [m[1], m[2], m[3]].filter(x => x != null).map(Number)
  if (parts.length > 1 && parts[parts.length - 1] >= 60) return bad
  if (parts.length === 3 && parts[1] >= 60) return bad
  // Zaokrouhlit PŘED kontrolou rozsahu — '0.0004' by jinak prošlo a do DB šla 0 (porušení CHECK end_s > 0)
  const v = Math.round(parts.reduce((acc, x) => acc * 60 + x, 0) * 1000) / 1000
  if (!(v >= END_MIN_S) || v > END_MAX_S) {
    return { error: `Konec musí být mezi ${formatEndTime(END_MIN_S)} a ${formatEndTime(END_MAX_S)} (m:ss, např. 4:02); prázdné = celá skladba.` }
  }
  return { value: v }
}

// ── Cíle ──
const isDoorObj = d => d && typeof d === 'object'
export function doorTargetOf(door) { return `door:${door.id}` }
export function doorShortLabel(door) {
  if (!isDoorObj(door)) return 'Dveře'
  return door.door_kind === 'accessories' ? 'Šatna' : `Kóje ${door.box_number ?? '?'}`
}
// Řazení dveří pro cíle: šatna první, pak kóje podle čísla boxu
export function sortedDoors(doors) {
  return (Array.isArray(doors) ? doors : []).filter(isDoorObj).slice().sort((a, b) => {
    const ka = a.door_kind === 'accessories' ? -1 : (Number(a.box_number) || 0)
    const kb = b.door_kind === 'accessories' ? -1 : (Number(b.box_number) || 0)
    return ka - kb
  })
}
// Pořadí skupin v seznamu: Venek, Šatna, Kóje 1–N, Společná
export function targetOrder(doors) {
  return ['outdoor', ...sortedDoors(doors).map(doorTargetOf), 'all']
}
export function targetLabel(target, doors) {
  if (target === 'all') return 'Společná (všechny kóje)'
  if (target === 'outdoor') return 'Venek'
  const id = String(target || '').startsWith('door:') ? target.slice(5) : null
  const door = id ? (Array.isArray(doors) ? doors : []).find(d => d?.id === id) : null
  return door ? doorShortLabel(door) : 'Smazané dveře'
}
// Volby pro select cíle (upload / přesun) — popis dveří jako doplněk
export function targetOptions(doors) {
  return [
    { value: 'all', label: 'Všechny kóje (společná hudba)' },
    ...sortedDoors(doors).map(d => ({ value: doorTargetOf(d), label: d.label ? `${doorShortLabel(d)} — ${d.label}` : doorShortLabel(d) })),
    { value: 'outdoor', label: 'Venek' },
  ]
}

// Seskupení skladeb podle cíle v pořadí targetOrder; neznámé cíle (smazané dveře) na konec
export function groupTracks(tracks, doors) {
  const order = targetOrder(doors)
  const by = new Map(order.map(t => [t, []]))
  const list = (Array.isArray(tracks) ? tracks : []).slice().sort((a, b) =>
    (a.sort_order - b.sort_order) || String(a.created_at || '').localeCompare(String(b.created_at || '')))
  for (const t of list) {
    if (!by.has(t.target)) by.set(t.target, [])
    by.get(t.target).push(t)
  }
  return [...by.entries()].map(([target, items]) => ({ target, items }))
}

// Souhrn cíle: co v něm bude hrát (vlastní / společná / nic)
export function summaryFor(target, groups) {
  const own = (groups.find(g => g.target === target)?.items || []).filter(t => t.is_active).length
  const shared = (groups.find(g => g.target === 'all')?.items || []).filter(t => t.is_active).length
  if (target === 'all') return { text: own ? `${own} skladeb — hraje všude, kde není vlastní hudba` : '0 skladeb', warn: false }
  if (own > 0) return { text: `${own} skladeb (vlastní)`, warn: false }
  if (shared > 0) return { text: `společná hudba (${shared})`, warn: false }
  return { text: '0 — nehraje nic', warn: true }
}

// ── Stav knihovny na jednotce: kiosk_devices.status.audio.library (JSON z jednotky — defenzivně) ──
const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : null)
const int = v => { const n = Number(v); return Number.isFinite(n) ? Math.max(0, Math.round(n)) : 0 }
export function libraryStatus(dev) {
  const lib = obj(obj(obj(dev?.status)?.audio)?.library)
  if (!lib) return null
  return {
    tracks: int(lib.tracks), synced: int(lib.synced), pending: int(lib.pending), failed: int(lib.failed),
    last_sync_at: typeof lib.last_sync_at === 'string' ? lib.last_sync_at : null,
    targets: obj(lib.targets) || {},
  }
}
export function audioModeOf(dev) {
  const m = obj(obj(dev?.status)?.audio)?.mode
  return m === 'multi' || m === 'selector' ? m : null
}
export function libraryChip(lib) {
  if (!lib) return { tone: 'gray', text: 'stav knihovny neznámý' }
  if (lib.failed > 0) return { tone: 'red', text: `${lib.failed} selhalo` }
  if (lib.pending > 0) return { tone: 'amber', text: `stahuje ${lib.pending}` }
  return { tone: 'green', text: `${lib.synced}/${lib.tracks} staženo` }
}

// ── Datové operace ──
export async function fetchTracks(branchId) {
  const { data, error } = await supabase.from('branch_music_tracks').select('*')
    .eq('branch_id', branchId).order('target').order('sort_order').order('created_at')
  if (error) throw error
  return data || []
}
export function nextSortOrder(tracks, target) {
  return tracks.filter(t => t.target === target).reduce((m, t) => Math.max(m, Number(t.sort_order) || 0), -1) + 1
}
// Upload do bucketu + INSERT řádku; při chybě insertu objekt smaže. Vrací vložený řádek.
export async function uploadTrack({ branchId, file, target, sortOrder, userId }) {
  if (!isAllowedFile(file)) throw new Error(`„${file.name}“ není podporovaný zvukový soubor`)
  if (file.size > MAX_SIZE_BYTES) throw new Error(`„${file.name}“ je příliš velký (max 200 MB)`)
  const id = newId()
  const ext = extOf(file.name) || 'bin'
  const path = `${branchId}/${id}.${ext}`
  const mime = mimeFor(file)
  const up = await supabase.storage.from(BUCKET).upload(path, file, { cacheControl: '31536000', upsert: false, contentType: mime })
  if (up.error) throw new Error(`Upload „${file.name}“ selhal: ${up.error.message}`)
  const row = { id, branch_id: branchId, target, title: titleOf(file.name), file_path: path, ext, mime, size_bytes: file.size, sort_order: sortOrder, created_by: userId || null }
  const ins = await supabase.from('branch_music_tracks').insert(row).select('*').single()
  if (ins.error) {
    await supabase.storage.from(BUCKET).remove([path]).catch(() => {})
    throw new Error(`Uložení „${file.name}“ selhalo: ${ins.error.message}`)
  }
  return ins.data
}
export async function updateTrack(id, patch) {
  const { error } = await supabase.from('branch_music_tracks').update(patch).eq('id', id)
  if (error) throw error
}
// Smaže objekt v bucketu a pak řádek (chybějící objekt neblokuje)
export async function deleteTrack(track) {
  const rm = await supabase.storage.from(BUCKET).remove([track.file_path])
  if (rm.error && !/not found/i.test(rm.error.message || '')) throw rm.error
  const { error } = await supabase.from('branch_music_tracks').delete().eq('id', track.id)
  if (error) throw error
}
