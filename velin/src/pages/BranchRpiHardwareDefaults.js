// ─── Výchozí hardwarová mapa (šablona: Brno, 9 zón) + popisy polí editoru ───
// Program v jednotce je univerzální — každá pobočka má vlastní mapu v DB; tato šablona je jen start.
// Konstanty jsou 1:1 s raspberry/motogo-box/config/brno-9zone.yaml (bez `network`).
// `branch_kiosk_config.hardware` = BRNO_DEFAULT_HARDWARE (bez `zones`),
// `branch_doors.hw` = jedna položka BRNO_DEFAULT_ZONES (zóna = box_number).

export const DEVICE_TYPES = [
  { value: 'wav645', label: 'WAV645 (16 relé)' },
  { value: 'wav617', label: 'WAV617 (8 relé + 8 vstupů)' },
  { value: 'shelly_rgbww', label: 'Shelly Pro RGBWW PM' },
]

export const BRNO_DEFAULT_HARDWARE = {
  version: 1,
  devices: {
    wav645: { type: 'wav645', host: '192.168.50.20', port: 502, unit_id: 1 },
    wav617a: { type: 'wav617', host: '192.168.50.21', port: 502, unit_id: 1 },
    wav617b: { type: 'wav617', host: '192.168.50.22', port: 502, unit_id: 1 },
    shelly1: { type: 'shelly_rgbww', host: '192.168.50.31' },
    shelly2: { type: 'shelly_rgbww', host: '192.168.50.32' },
    shelly3: { type: 'shelly_rgbww', host: '192.168.50.33' },
    shelly4: { type: 'shelly_rgbww', host: '192.168.50.34' },
  },
  timings: {
    lock_pulse_ms: 800,
    door_open_timeout_s: 30,
    door_close_debounce_ms: 1000,
    light_after_close_s: 30,
    music_after_close_s: 10,
    maximum_session_s: 600,
    forced_open_debounce_ms: 500,
    pin_entry_timeout_s: 20,
    overtime_alert_minutes: [10, 20, 30],
  },
  polling: {
    door_input_poll_ms: 100,
    software_debounce_ms: 300,
    modbus_timeout_ms: 500,
    retry_delays_ms: [100, 250, 500],
    device_offline_after_failures: 3,
  },
  contacts: { closed_level: 1 },
  security: {
    maximum_failed_attempts: 5,
    attempt_window_minutes: 5,
    lockout_minutes: 15,
    pin_length: 6,
    mask_pin_on_screen: true,
    service_token_minutes: 10,
  },
  audio: {
    volume: 70,
    fade_in_ms: 1500,
    fade_out_ms: 500,
    selector_settle_ms: 200,
    selector_on_ms: 100,
    device: null,
    shuffle: true,
  },
  signal: { brightness: 100, blink_ms: 500, pulse_ms: 1500, transition_s: 0.2 },
}

const z = (zone, lock, cDev, contact, lDev, light, aDev, audio, rDev, red, gDev, green) => ({
  zone,
  lock: { dev: 'wav645', coil: lock },
  contact: { dev: cDev, input: contact },
  light: { dev: lDev, coil: light },
  audio: { dev: aDev, coil: audio },
  red: { dev: rDev, light: red },
  green: { dev: gDev, light: green },
})

export const BRNO_DEFAULT_ZONES = [
  z(1, 0, 'wav617a', 0, 'wav617a', 0, 'wav617b', 1, 'shelly1', 0, 'shelly1', 1),
  z(2, 1, 'wav617a', 1, 'wav617a', 1, 'wav617b', 2, 'shelly1', 2, 'shelly1', 3),
  z(3, 2, 'wav617a', 2, 'wav617a', 2, 'wav617b', 3, 'shelly1', 4, 'shelly2', 0),
  z(4, 3, 'wav617a', 3, 'wav617a', 3, 'wav617b', 4, 'shelly2', 1, 'shelly2', 2),
  z(5, 4, 'wav617a', 4, 'wav617a', 4, 'wav617b', 5, 'shelly2', 3, 'shelly2', 4),
  z(6, 5, 'wav617a', 5, 'wav617a', 5, 'wav617b', 6, 'shelly3', 0, 'shelly3', 1),
  z(7, 6, 'wav617a', 6, 'wav617a', 6, 'wav617b', 7, 'shelly3', 2, 'shelly3', 3),
  z(8, 7, 'wav617a', 7, 'wav617a', 7, 'wav645', 9, 'shelly3', 4, 'shelly4', 0),
  z(9, 8, 'wav617b', 0, 'wav617b', 0, 'wav645', 10, 'shelly4', 1, 'shelly4', 2),
]

// Režim audia (`hardware.audio.mode`): chybí = selector (stávající instalace beze změny chování).
export const AUDIO_MODES = [
  { value: 'selector', label: 'selector — 1 zesilovač + relé (hraje vždy jen jedna zóna, venek nelze)' },
  { value: 'multi', label: 'multi — každá místnost vlastní zvukový výstup + mpv (hrají současně, venek)' },
]

// Vzor 9 výstupů pro Brno (7 kójí, šatna, venek) = KOMENTOVANÝ příklad v brno-9zone.yaml. Není součástí
// BRNO_DEFAULT_HARDWARE (výchozí režim zůstává selector) — vyplní ho jen tlačítko „Vzor 9 výstupů“ v editoru.
export const BRNO_AUDIO_OUTPUTS_EXAMPLE = {
  out1: { device: 'alsa/plughw:CARD=Box1' }, out2: { device: 'alsa/plughw:CARD=Box2' }, out3: { device: 'alsa/plughw:CARD=Box3' },
  out4: { device: 'alsa/plughw:CARD=Box4' }, out5: { device: 'alsa/plughw:CARD=Box5' }, out6: { device: 'alsa/plughw:CARD=Box6' },
  out7: { device: 'alsa/plughw:CARD=Box7' }, out8: { device: 'alsa/plughw:CARD=Satna' }, out9: { device: 'alsa/plughw:CARD=Venek' },
}
export const BRNO_AUDIO_OUTDOOR_EXAMPLE = { out: 'out9', trigger: 'any' }

// Role kanálů v `branch_doors.hw`: klíč indexu + druh kanálu (pro detekci duplicit).
// `types` = povolené typy zařízení 1:1 s validate_hardware() v jednotce (config.py):
// zámek VÝHRADNĚ WAV645 (HW flash-on — nezůstane pod napětím ani při pádu procesu), kontakt jen vstup WAV617.
export const ZONE_REFS = [
  { key: 'lock', label: 'Zámek', idx: 'coil', kind: 'coil', types: ['wav645'] },
  { key: 'contact', label: 'Kontakt', idx: 'input', kind: 'input', types: ['wav617'] },
  { key: 'light', label: 'Světlo', idx: 'coil', kind: 'coil', types: ['wav645', 'wav617'] },
  { key: 'audio', label: 'Audio', idx: 'coil', kind: 'coil', types: ['wav645', 'wav617'] },
  { key: 'red', label: 'Červená', idx: 'light', kind: 'light', types: ['shelly_rgbww'] },
  { key: 'green', label: 'Zelená', idx: 'light', kind: 'light', types: ['shelly_rgbww'] },
]

// Popisy polí editoru (sekce → pole). type: int | float | bool | list | text
export const HW_SECTIONS = [
  { key: 'timings', title: 'Časování', fields: [
    { key: 'lock_pulse_ms', label: 'Pulz zámku', unit: 'ms', type: 'int' },
    { key: 'door_open_timeout_s', label: 'Timeout otevření dveří', unit: 's', type: 'int' },
    { key: 'door_close_debounce_ms', label: 'Debounce zavření', unit: 'ms', type: 'int' },
    { key: 'light_after_close_s', label: 'Světlo po zavření', unit: 's', type: 'int' },
    { key: 'music_after_close_s', label: 'Hudba po zavření', unit: 's', type: 'int' },
    { key: 'maximum_session_s', label: 'Max. délka relace', unit: 's', type: 'int' },
    { key: 'forced_open_debounce_ms', label: 'Debounce násilného otevření', unit: 'ms', type: 'int' },
    { key: 'pin_entry_timeout_s', label: 'Timeout zadávání PIN', unit: 's', type: 'int' },
    { key: 'overtime_alert_minutes', label: 'Upozornění při překročení', unit: 'min, čárkami', type: 'list' },
  ] },
  { key: 'polling', title: 'Polling (Modbus)', fields: [
    { key: 'door_input_poll_ms', label: 'Čtení kontaktů', unit: 'ms', type: 'int' },
    { key: 'software_debounce_ms', label: 'SW debounce', unit: 'ms', type: 'int' },
    { key: 'modbus_timeout_ms', label: 'Timeout Modbus', unit: 'ms', type: 'int' },
    { key: 'retry_delays_ms', label: 'Prodlevy opakování', unit: 'ms, čárkami', type: 'list' },
    { key: 'device_offline_after_failures', label: 'Offline po selháních', unit: '×', type: 'int' },
  ] },
  { key: 'contacts', title: 'Dveřní kontakty', fields: [
    { key: 'closed_level', label: 'Úroveň vstupu při zavřených dveřích', unit: '0/1', type: 'int' },
  ] },
  { key: 'security', title: 'Bezpečnost (PIN)', fields: [
    { key: 'maximum_failed_attempts', label: 'Max. neúspěšných pokusů', unit: '×', type: 'int' },
    { key: 'attempt_window_minutes', label: 'Okno pokusů', unit: 'min', type: 'int' },
    { key: 'lockout_minutes', label: 'Uzamčení po překročení', unit: 'min', type: 'int' },
    { key: 'pin_length', label: 'Délka PIN', unit: 'číslic', type: 'int' },
    { key: 'service_token_minutes', label: 'Platnost servisního přístupu', unit: 'min', type: 'int' },
    { key: 'mask_pin_on_screen', label: 'Maskovat PIN na displeji', type: 'bool' },
  ] },
  { key: 'audio', title: 'Audio', fields: [
    { key: 'volume', label: 'Hlasitost', unit: '%', type: 'int' },
    { key: 'fade_in_ms', label: 'Náběh hlasitosti', unit: 'ms', type: 'int' },
    { key: 'fade_out_ms', label: 'Doběh hlasitosti', unit: 'ms', type: 'int' },
    { key: 'selector_settle_ms', label: 'Prodleva po vypnutí relé', unit: 'ms', type: 'int' },
    { key: 'selector_on_ms', label: 'Prodleva po sepnutí relé', unit: 'ms', type: 'int' },
    { key: 'device', label: 'Zvukové zařízení (mpv)', unit: 'prázdné = výchozí', type: 'text' },
    { key: 'shuffle', label: 'Náhodné pořadí skladeb', type: 'bool' },
  ] },
  { key: 'signal', title: 'Signalizace (Shelly)', fields: [
    { key: 'brightness', label: 'Jas', unit: '%', type: 'int' },
    { key: 'blink_ms', label: 'Perioda blikání', unit: 'ms', type: 'int' },
    { key: 'pulse_ms', label: 'Perioda pulzování', unit: 'ms', type: 'int' },
    { key: 'transition_s', label: 'Přechod', unit: 's', type: 'float' },
  ] },
]

// Hodnota pole → text pro input
export function fieldToText(field, value) {
  if (value == null) return ''
  if (field.type === 'list') return Array.isArray(value) ? value.join(', ') : String(value)
  return String(value)
}

// Text z inputu → hodnota pro JSON (null = neplatné / prázdné)
export function textToField(field, text) {
  const t = String(text ?? '').trim()
  if (field.type === 'text') return t === '' ? null : t
  if (field.type === 'list') {
    const items = t.split(/[,\s;]+/).filter(Boolean).map(x => parseInt(x, 10))
    return items.length && items.every(Number.isFinite) ? items : null
  }
  if (t === '') return null
  const n = field.type === 'float' ? parseFloat(t.replace(',', '.')) : parseInt(t, 10)
  return Number.isFinite(n) ? n : null
}

// Sekce hardware sloučená s výchozími hodnotami (aby editor ukazoval všechna pole)
export function sectionWithDefaults(hardware, key) {
  return { ...(BRNO_DEFAULT_HARDWARE[key] || {}), ...((hardware && hardware[key]) || {}) }
}

// Prázdná HW mapa zóny pro editor dveří
export function emptyZoneHw(zone) {
  const out = { zone: zone ?? '' }
  ZONE_REFS.forEach(r => { out[r.key] = { dev: '', [r.idx]: '' } })
  out.audio.out = ''   // režim multi: název výstupu z audio.outputs
  return out
}

// Kanál (dev, druh, index) → klíč pro detekci duplicit; null když neúplný
export function channelKey(ref, role) {
  if (!ref || !ref.dev) return null
  const raw = ref[role.idx] ?? ref.idx
  if (raw === '' || raw == null) return null
  const n = parseInt(raw, 10)
  return Number.isFinite(n) ? `${ref.dev}:${role.kind}:${n}` : null
}

// Vrátí Set klíčů kanálů, které se objevují ve více než jedné roli/dveřích
export function findDuplicateChannels(hwByDoor) {
  const counts = new Map()
  Object.values(hwByDoor || {}).forEach(hw => {
    ZONE_REFS.forEach(role => {
      const k = channelKey(hw?.[role.key], role)
      if (k) counts.set(k, (counts.get(k) || 0) + 1)
    })
  })
  return new Set([...counts.entries()].filter(([, c]) => c > 1).map(([k]) => k))
}

// Chyba typu zařízení pro roli — stejné texty jako validate_hardware() v jednotce (config.py); null = OK
export function roleTypeError(zone, role, dev, devices) {
  if (!dev) return null
  const d = devices?.[dev]
  if (!d) return `Zóna ${zone}: ${role.key} odkazuje na neznámé zařízení '${dev}'.`
  if (role.types.includes(d.type)) return null
  if (role.key === 'lock') return `Zóna ${zone}: lock musí být relé WAV645 s HW flash-on (je ${d.type}).`
  if (role.key === 'contact') return `Zóna ${zone}: contact musí být vstup WAV617 (je ${d.type}).`
  if (role.kind === 'light') return `Zóna ${zone}: ${role.key} musí být na Shelly (je ${d.type}).`
  return `Zóna ${zone}: ${role.key} musí být relé Waveshare (je ${d.type}).`
}

// Názvy výstupů z `hardware.audio.outputs` (JSON z DB — nevěřit tvaru; prázdné názvy se přeskočí)
export function audioOutputNames(audio) {
  const outs = audio && typeof audio === 'object' && audio.outputs && typeof audio.outputs === 'object' ? audio.outputs : {}
  return Object.keys(outs).map(n => String(n).trim()).filter(Boolean)
}

// Normalizovaný režim audia ('selector' | 'multi'); neznámý/chybějící = selector (stejně jako jednotka)
export function audioMode(audio) {
  const m = String(audio?.mode ?? '').trim().toLowerCase()
  return m === 'multi' ? 'multi' : 'selector'
}

// Výstup kanálu venek (`audio.channels.outdoor.out`) nebo ''
export function outdoorOut(audio) {
  const ch = audio?.channels && typeof audio.channels === 'object' ? audio.channels.outdoor : null
  return ch && typeof ch === 'object' && ch.out != null ? String(ch.out).trim() : ''
}

// Set názvů výstupů, které sdílí víc cílů (dveře mezi sebou nebo dveře + kanál venek) — jednotka odmítá
export function findDuplicateOutputs(hwByDoor, outdoor) {
  const counts = new Map()
  const add = o => { const n = String(o ?? '').trim(); if (n) counts.set(n, (counts.get(n) || 0) + 1) }
  Object.values(hwByDoor || {}).forEach(hw => add(hw?.audio?.out))
  add(outdoor)
  return new Set([...counts.entries()].filter(([, c]) => c > 1).map(([n]) => n))
}

// Chyba výstupu zóny — stejný text jako validate_audio() v jednotce; null = OK (bez `audio` se existence nekontroluje)
export function audioOutError(zone, out, audio) {
  const o = String(out ?? '').trim()
  if (!o || !audio) return null
  return audioOutputNames(audio).includes(o) ? null : `Zóna ${zone}: audio výstup '${o}' není v audio.outputs.`
}

// Set čísel zón, která má víc než jedny dveře (jednotka odmítá: „Duplicitní čísla zón.“)
export function findDuplicateZones(hwByDoor) {
  const counts = new Map()
  Object.values(hwByDoor || {}).forEach(hw => {
    const n = parseInt(hw?.zone, 10)
    if (Number.isFinite(n) && n >= 1) counts.set(n, (counts.get(n) || 0) + 1)
  })
  return new Set([...counts.entries()].filter(([, c]) => c > 1).map(([n]) => n))
}

// Šablona: číslo zóny pro dveře oblečení = nejvyšší zóna šablony, kterou nezabírá žádná kóje (null = žádná volná)
export function pickAccessoriesZone(usedZones, template = BRNO_DEFAULT_ZONES) {
  const used = new Set([...usedZones].map(n => parseInt(n, 10)))
  const free = template.map(z => z.zone).filter(n => !used.has(n))
  return free.length ? Math.max(...free) : null
}

// Editorový draft → čisté `hw` pro uložení (neúplné odkazy = null, prázdný zone = chyba).
// `devices` (hardware.devices) → kontrola typů zařízení jako v jednotce; bez něj se typy nekontrolují.
// `audio` (hardware.audio, volitelné) → v režimu multi kontrola, že výstup `audio.out` existuje v audio.outputs
// (v selectoru jednotka `out` ignoruje a editor ho neukazuje — stale hodnota nesmí blokovat uložení; zůstává zachována).
// Draft bez `audio.out` dává stejné `hw` jako dřív (selector: audio = {dev, coil} | null).
export function draftToHw(draft, devices, audio) {
  const zone = parseInt(draft?.zone, 10)
  if (!Number.isFinite(zone) || zone < 1) return { error: 'Zóna musí být kladné číslo.' }
  const hw = { zone }
  for (const role of ZONE_REFS) {
    const ref = draft[role.key]
    const idx = ref ? parseInt(ref[role.idx], 10) : NaN
    const full = !!(ref && ref.dev && Number.isFinite(idx))
    hw[role.key] = full ? { dev: ref.dev, [role.idx]: idx } : null
    if (full && idx < 0) return { error: `Zóna ${zone}: ${role.key} má záporný index ${idx}.`, hw }
    const typeErr = devices && full ? roleTypeError(zone, role, ref.dev, devices) : null
    if (typeErr) return { error: typeErr, hw }
  }
  const out = String(draft.audio?.out ?? '').trim()
  if (out) {
    hw.audio = { ...(hw.audio || {}), out }   // multi: {out} nebo {dev, coil, out} (výstup + enable relé)
    const outErr = audioMode(audio) === 'multi' ? audioOutError(zone, out, audio) : null
    if (outErr) return { error: outErr, hw }
  }
  if (!hw.lock || !hw.contact) return { error: 'Zámek a kontakt jsou povinné.', hw }
  const cl = String(draft.closed_level ?? '').trim()
  if (cl !== '') {
    const n = parseInt(cl, 10)
    if (n !== 0 && n !== 1) return { error: 'Úroveň zavřeno musí být 0 nebo 1.', hw }
    hw.closed_level = n
  }
  return { hw }
}

// `hw` z DB → editorový draft (vždy má všechny role)
export function hwToDraft(hw, fallbackZone) {
  const d = emptyZoneHw(hw?.zone ?? fallbackZone ?? '')
  ZONE_REFS.forEach(role => {
    const ref = hw?.[role.key]
    if (ref && typeof ref === 'object') d[role.key] = { dev: ref.dev || '', [role.idx]: ref[role.idx] ?? ref.idx ?? '' }
  })
  d.audio.out = hw?.audio && typeof hw.audio === 'object' && hw.audio.out != null ? String(hw.audio.out).trim() : ''
  d.closed_level = hw?.closed_level == null ? '' : String(hw.closed_level)
  return d
}
