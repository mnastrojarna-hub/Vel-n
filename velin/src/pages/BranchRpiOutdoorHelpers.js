import { ZONE_REFS, channelKey, audioMode, audioOutputNames } from './BranchRpiHardwareDefaults'

// ─── Venek (zóna bez dveří) — `hardware.outdoor` (kanonický) + legacy alias `audio.channels.outdoor` ───
// Kanonický tvar (rozhodnutí 2026-09-11; jednotka: config_outdoor.py):
//   outdoor: { zone: 9, light: { dev, coil }, audio: { out, dev?, coil? }, light_after_close_s? }
// Legacy alias `audio.channels.outdoor { out, trigger: any, dev?, coil? }` jednotka stále čte (když `outdoor.audio.out`
// chybí, doplní ho z kanálu). Velín ho při uložení bloku Venek ODSTRANÍ (migrace na kanonický tvar), ostatní
// `audio.channels` zachová. Texty chyb jsou 1:1 s validate_outdoor() / validate_audio() v jednotce.

// Počet relé modulů (1:1 s CHANNEL_LIMITS v config.py; index 0-based)
export const COIL_LIMITS = { wav645: 16, wav617: 8 }
const WAVESHARE = ['wav645', 'wav617']

// Role kanálů venku pro detekci duplicit (channelKey / findDuplicateChannels — `extraRefs`)
export const OUTDOOR_LIGHT_ROLE = { key: 'light', label: 'Světlo venku', idx: 'coil', kind: 'coil', types: WAVESHARE }
export const OUTDOOR_RELAY_ROLE = { key: 'audio', label: 'Enable relé venku', idx: 'coil', kind: 'coil', types: WAVESHARE }

const obj = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : null)
const intOrNull = v => { if (v == null || v === '') return null; const n = parseInt(v, 10); return Number.isFinite(n) ? n : null }
// Odkaz {dev, coil} z JSON (akceptuje i `idx` jako jednotka); null bez zařízení
const refOf = r => { const o = obj(r); return o && o.dev ? { dev: String(o.dev), coil: o.coil ?? o.idx ?? '' } : null }
// Úplný odkaz {dev, coil:int} | null; `partial` = vyplněno jen jedno z obou
function fullRef(r) {
  const dev = String(r?.dev ?? '').trim(), raw = String(r?.coil ?? '').trim()
  const coil = parseInt(raw, 10)
  if (!dev && raw === '') return { ref: null, partial: false }
  if (!dev || !Number.isFinite(coil)) return { ref: null, partial: true }
  return { ref: { dev, coil }, partial: false }
}

// Legacy kanál `audio.channels.outdoor` (objekt) nebo null
export function legacyOutdoorChannel(audio) {
  return obj(obj(obj(audio)?.channels)?.outdoor)
}

// Normalizovaný venek z `hardware.outdoor`: { present, configured, zone, light, audio: { out, dev, coil }, light_after_close_s }.
// `present` = klíč `outdoor` existuje. Audio se bere z legacy kanálu, když kanonický `outdoor.audio.out` chybí (jako jednotka).
// `configured` jako v jednotce (OutdoorCfg.configured): světlo se počítá jen ÚPLNÉ (dev + číselný coil — HwRef.from_dict
// neúplný odkaz zahodí); v `light` zůstává i neúplný odkaz, aby ho editor ukázal a uložení zachytilo (`fullRef.partial`).
export function outdoorOf(hardware) {
  const hw = obj(hardware)
  const raw = obj(hw?.outdoor)
  const canon = obj(raw?.audio)
  const src = canon && canon.out != null && String(canon.out).trim() ? canon : (legacyOutdoorChannel(hw?.audio) || canon)
  const out = src && src.out != null ? String(src.out).trim() : ''
  const relay = refOf(src)
  const light = refOf(raw?.light)
  return {
    present: !!raw, configured: !!fullRef(light).ref || !!out,
    zone: intOrNull(raw?.zone), light,
    audio: { out, dev: relay?.dev ?? '', coil: relay?.coil ?? '' },
    light_after_close_s: intOrNull(raw?.light_after_close_s),
  }
}

// Výstup venku ('' = žádný): kanonický `outdoor.audio.out`, pak legacy `audio.channels.outdoor.out`
export function outdoorOutOf(hardware) { return outdoorOf(hardware).audio.out }

// Kanály venku pro findDuplicateChannels(drafts, outdoorRefs(outdoorOf(hardware), multi)).
// Světlo se počítá vždy (validate_outdoor blokuje v obou režimech). Enable relé jen v režimu multi — v selectoru ho
// jednotka nevaliduje ani nepoužívá (validate_audio končí upozorněním; venek v selectoru nehraje), takže dveře smí v
// selectoru cívku obsadit; kolizi při přepnutí na multi hlídá AudioOutputsEditor (save) — stejně přísně jako jednotka.
export function outdoorRefs(o, multi = true) {
  const refs = []
  if (o?.light) refs.push({ ref: o.light, role: OUTDOOR_LIGHT_ROLE })
  if (multi && o?.audio?.dev) refs.push({ ref: { dev: o.audio.dev, coil: o.audio.coil }, role: OUTDOOR_RELAY_ROLE })
  return refs
}

// Dveře, jejichž uložená mapa koliduje s venkem `outdoor` (tvar `hardware.outdoor`): stejné číslo zóny, nebo cívka
// zámku/světla/audia = světlo či enable relé venku (validate_outdoor: „koliduje s dveřmi“ / „už používá zóna N“ — blokuje).
// Použití: načtení šablony Brno — dveře mimo šablonu s mapou ze staré 9zónové šablony (zóna 9 = wav617b R1).
export function doorsCollidingWithOutdoor(doors, outdoor) {
  const o = outdoorOf({ outdoor })
  const keys = new Set(outdoorRefs(o, true).map(x => channelKey(x.ref, x.role)).filter(Boolean))
  return (doors || []).filter(d => {
    const hw = obj(d?.hw)
    if (!hw) return false
    if (o.zone != null && intOrNull(hw.zone) === o.zone) return true
    return ZONE_REFS.filter(r => r.kind === 'coil').some(role => { const k = channelKey(hw[role.key], role); return !!k && keys.has(k) })
  })
}

// Cívky relé obsazené uloženými dveřmi: klíč channelKey → { zone, role } (jako `seen` ve validate_hardware)
export function doorCoils(doors) {
  const used = new Map()
  ;(doors || []).forEach(d => {
    const hw = obj(d?.hw)
    ZONE_REFS.filter(r => r.kind === 'coil').forEach(role => {
      const k = channelKey(hw?.[role.key], role)
      if (k && !used.has(k)) used.set(k, { zone: intOrNull(hw?.zone) ?? '?', role: role.key })
    })
  })
  return used
}

// Relé venku (světlo / enable relé) — texty 1:1 s jednotkou; `who` = 'Venek: light' | 'Kanál outdoor: relé'; null = OK / nevyplněno
function relayError(who, ref, devices, coils) {
  const dev = String(ref?.dev ?? '').trim(), idx = parseInt(ref?.coil, 10)
  if (!dev || !Number.isFinite(idx)) return null
  const d = devices?.[dev]
  if (!d) return `${who} odkazuje na neznámé zařízení '${dev}'.`
  if (!WAVESHARE.includes(d.type)) return who === 'Venek: light' ? `${who} musí být relé Waveshare (je ${d.type}).` : `${who} musí být Waveshare (je ${d.type}).`
  const limit = COIL_LIMITS[d.type]
  if (idx < 0 || (limit != null && idx >= limit)) return `${who} ${dev}[${idx}] je mimo rozsah modulu ${d.type} (0–${(limit || 1) - 1}).`
  const used = coils?.get(`${dev}:coil:${idx}`)
  if (used) return `${who} ${dev}[${idx}] už používá zóna ${used.zone} (${used.role}).`
  return null
}
// Chyba světla venku (validate_outdoor) / enable relé venku (validate_audio, kanál outdoor); null = OK
export function outdoorLightError(ref, devices, coils) { return relayError('Venek: light', ref, devices, coils) }
export function outdoorRelayError(ref, devices, coils) { return relayError('Kanál outdoor: relé', ref, devices, coils) }
// Světlo a enable relé venku na téže cívce — jednotka (validate_outdoor) blokuje v OBOU režimech (v selectoru si
// `outdoor.audio` doplní i z legacy kanálu); null = OK / některý odkaz neúplný
export function outdoorShareError(light, audio) {
  const l = fullRef(light).ref, a = fullRef(audio).ref
  return l && a && l.dev === a.dev && l.coil === a.coil ? `Venek: light a audio sdílí ${l.dev}[${l.coil}].` : null
}

// Výstup venku v režimu multi — texty 1:1 s validate_audio() (kanál outdoor); v selectoru se nekontroluje (jednotka jen upozorní)
export function outdoorOutError(out, audio, doors) {
  const o = String(out ?? '').trim()
  if (!o || audioMode(audio) !== 'multi') return null
  if (!audioOutputNames(audio).includes(o)) return `Kanál outdoor: audio výstup '${o}' není v audio.outputs.`
  const door = (doors || []).find(d => String(obj(obj(d?.hw)?.audio)?.out ?? '').trim() === o)
  return door ? `Kanál outdoor: audio výstup '${o}' už používá zóna ${intOrNull(obj(door.hw)?.zone) ?? '?'}.` : null
}

// Číslo zóny venku: povinné (příkazy light_on/music_on/zone_test i stav se adresují číslem) a nesmí kolidovat s dveřmi
export function outdoorZoneError(zone, doors) {
  const n = parseInt(zone, 10)
  if (!Number.isFinite(n) || n < 1) return 'Venek: zóna musí být kladné číslo (příkazy a stav venku se adresují číslem zóny).'
  return (doors || []).some(d => intOrNull(obj(d?.hw)?.zone) === n) ? `Venek: číslo zóny ${n} koliduje s dveřmi (zóna ${n}).` : null
}

// `hardware` → draft editoru (texty; vždy má všechna pole)
export function outdoorToDraft(hardware) {
  const o = outdoorOf(hardware)
  return {
    zone: o.zone == null ? '' : String(o.zone),
    light: { dev: o.light?.dev ?? '', coil: o.light ? String(o.light.coil) : '' },
    audio: { out: o.audio.out, dev: o.audio.dev, coil: o.audio.coil === '' ? '' : String(o.audio.coil) },
    light_after_close_s: o.light_after_close_s == null ? '' : String(o.light_after_close_s),
  }
}

// Draft → kanonický `outdoor` + validace jako jednotka: { outdoor } nebo { error }.
// Audio (výstup + enable relé vs. dveře) se kontroluje jen v režimu multi; v selectoru projde beze změny (jednotka jen
// upozorní). Kolize světla a enable relé venku (`outdoorShareError`) platí v obou režimech jako v jednotce.
export function draftToOutdoor(draft, { devices, audio, doors }) {
  const zoneErr = outdoorZoneError(draft?.zone, doors)
  if (zoneErr) return { error: zoneErr }
  const coils = doorCoils(doors)
  const light = fullRef(draft?.light)
  if (light.partial) return { error: 'Venek: světlo — vyplňte zařízení i coil, nebo obojí vymažte.' }
  const lightErr = outdoorLightError(draft?.light, devices, coils)
  if (lightErr) return { error: lightErr }
  const relay = fullRef(draft?.audio)
  if (relay.partial) return { error: 'Venek: enable relé — vyplňte zařízení i coil, nebo obojí vymažte.' }
  const shareErr = outdoorShareError(draft?.light, draft?.audio)
  if (shareErr) return { error: shareErr }
  const out = String(draft?.audio?.out ?? '').trim()
  if (audioMode(audio) === 'multi') {
    const relayErr = outdoorRelayError(draft?.audio, devices, coils)
    if (relayErr) return { error: relayErr }
    const outErr = outdoorOutError(out, audio, doors)
    if (outErr) return { error: outErr }
    if (relay.ref && !out) return { error: 'Venek: enable relé bez audio výstupu — vyberte výstup venku, nebo relé vymažte.' }
  }
  const outdoor = { zone: parseInt(draft.zone, 10) }
  if (light.ref) outdoor.light = light.ref
  const a = {}
  if (out) a.out = out
  if (relay.ref) { a.dev = relay.ref.dev; a.coil = relay.ref.coil }
  if (Object.keys(a).length) outdoor.audio = a
  const after = String(draft?.light_after_close_s ?? '').trim()
  if (after !== '') {
    const n = parseInt(after, 10)
    if (!Number.isFinite(n) || n < 0) return { error: 'Venek: doběh světla musí být celé nezáporné číslo sekund (prázdné = globální světlo po zavření).' }
    outdoor.light_after_close_s = n
  }
  if (!outdoor.light && !out) return { error: 'Upozornění: venek nemá světlo ani audio výstup. Vyplňte světlo nebo výstup venku, nebo venek vymažte.' }
  return { outdoor }
}

// `hardware.audio` bez legacy kanálu venku (migrace → kanonický `outdoor.audio`); ostatní kanály zachová.
// Vrací původní hodnotu, když není co odstranit (i ne-objekt / undefined — volající pak `audio` nemění).
export function audioWithoutOutdoorChannel(audio) {
  const a = obj(audio)
  if (!legacyOutdoorChannel(a)) return audio
  const channels = { ...a.channels }
  delete channels.outdoor
  const next = { ...a }
  if (Object.keys(channels).length) next.channels = channels; else delete next.channels
  return next
}
