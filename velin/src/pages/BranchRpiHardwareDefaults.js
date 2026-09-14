// ─── Výchozí hardwarová mapa (šablona Brno: 8 zón (7 kójí + šatna) + venek) + popisy polí editoru ───
// Program v jednotce je univerzální — každá pobočka má vlastní mapu v DB; tato šablona je jen start.
// Konstanty jsou 1:1 s raspberry/motogo-box/config/brno-9zone.yaml (bez `network`).
// `branch_kiosk_config.hardware` = BRNO_DEFAULT_HARDWARE (bez `zones`, včetně `outdoor` = venek),
// `branch_doors.hw` = jedna položka BRNO_DEFAULT_ZONES (zóna = box_number).
// Venek (zóna 9, bez dveří): sekce `hardware.outdoor` — helpery v BranchRpiOutdoorHelpers.js.

export const DEVICE_TYPES = [
  { value: 'wav645', label: 'WAV645 (16 relé)' },
  { value: 'wav617', label: 'WAV617 (8 relé + 8 vstupů)' },
  { value: 'shelly_rgbww', label: 'Shelly Pro RGBWW PM' },
]

// Venek = zóna 9 šablony: venkovní osvětlení WAV617-B R1 (coil 0); audio venku jen v režimu multi (blok Venek)
export const BRNO_DEFAULT_OUTDOOR = { zone: 9, light: { dev: 'wav617b', coil: 0 } }

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
  outdoor: BRNO_DEFAULT_OUTDOOR,
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
]
// rezerva: shelly4 light 1–4; wav645 coil 8 (R9), coil 10–15 (R11–R16); wav617b input 0 (DI1)

// Režim audia (`hardware.audio.mode`): chybí = selector (stávající instalace beze změny chování).
export const AUDIO_MODES = [
  { value: 'selector', label: 'selector — 1 zesilovač + relé (hraje vždy jen jedna zóna, venek nelze)' },
  { value: 'multi', label: 'multi — každá místnost vlastní zvukový výstup + mpv (hrají současně, venek)' },
]

// Vzor 9 výstupů pro Brno (7 kójí, šatna, venek) = KOMENTOVANÝ příklad v brno-9zone.yaml. Není součástí
// BRNO_DEFAULT_HARDWARE (výchozí režim zůstává selector) — vyplní ho jen tlačítko „Vzor 9 výstupů“ v editoru.
// Výstup venku (`outdoor.audio.out`) se nastavuje v bloku Venek — BRNO_AUDIO_OUTDOOR_EXAMPLE je jen nápověda.
export const BRNO_AUDIO_OUTPUTS_EXAMPLE = {
  out1: { device: 'alsa/plughw:CARD=Box1' }, out2: { device: 'alsa/plughw:CARD=Box2' }, out3: { device: 'alsa/plughw:CARD=Box3' },
  out4: { device: 'alsa/plughw:CARD=Box4' }, out5: { device: 'alsa/plughw:CARD=Box5' }, out6: { device: 'alsa/plughw:CARD=Box6' },
  out7: { device: 'alsa/plughw:CARD=Box7' }, out8: { device: 'alsa/plughw:CARD=Satna' }, out9: { device: 'alsa/plughw:CARD=Venek' },
}
export const BRNO_AUDIO_OUTDOOR_EXAMPLE = { out: 'out9' }

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
// `hint` = vysvětlivka pro obsluhu Velína (bublina po najetí myší): CO to znamená, K ČEMU to slouží
// a jaká je typická hodnota. Píše se lidsky, bez žargonu — nastavuje to i netechnický člověk.
// Chování odpovídá jednotce: časování → zone.py / zone_access.py, polling → modbus.py a io_devices.py,
// kontakty → io_devices.py, bezpečnost → controller_codes.py, audio → audio.py / audio_multi.py,
// signalizace → shelly.py. Výchozí hodnoty jsou v BRNO_DEFAULT_HARDWARE výše (šablona Brno).
export const HW_SECTIONS = [
  { key: 'timings', title: 'Časování',
    hint: 'Kdy se co stane od zadání kódu po zavření dveří. Platí pro kóje 1–7 i šatnu; venkovní prostor má vlastní režim v bloku „Venek“ níže.',
    fields: [
    { key: 'lock_pulse_ms', label: 'Pulz zámku', unit: 'ms', type: 'int',
      hint: 'Jak dlouho dostane elektrický zámek proud, aby odjistil dveře. Je to krátký impulz — zámek pak zůstane odjištěný mechanicky, dokud zákazník neotevře. Příliš krátký pulz dveře neotevře, příliš dlouhý zbytečně hřeje cívku. Typicky 800 ms.' },
    { key: 'door_open_timeout_s', label: 'Timeout otevření dveří', unit: 's', type: 'int',
      hint: 'Kolik sekund má zákazník na to, aby po zadání kódu opravdu otevřel dveře. Když je neotevře, relace se zruší, světlo a hudba zhasnou a stejný kód lze použít znovu. Typicky 30 s.' },
    { key: 'door_close_debounce_ms', label: 'Debounce zavření', unit: 'ms', type: 'int',
      hint: 'Jak dlouho musí dveřní kontakt hlásit „zavřeno“ v kuse, aby to jednotka uznala. Brání tomu, aby zadrnčení dveří nebo zákmit kontaktu předčasně ukončily relaci. Typicky 1000 ms.' },
    { key: 'light_after_close_s', label: 'Světlo po zavření', unit: 's', type: 'int',
      hint: 'Za jak dlouho po zavření dveří zhasne světlo v kóji. Zákazník tak neodchází ze tmy. Typicky 30 s.' },
    { key: 'music_after_close_s', label: 'Hudba po zavření', unit: 's', type: 'int',
      hint: 'Za jak dlouho po zavření dveří ztichne hudba v kóji (pozvolna, ne rázem). Typicky 10 s.' },
    { key: 'maximum_session_s', label: 'Max. délka relace', unit: 's', type: 'int',
      hint: 'Jak dlouho smí být kóje otevřená, než to jednotka označí za překročený čas: hudba se vypne, zelená začne blikat, na displeji se objeví výzva k zavření a Velín dostane upozornění. Dveře se NEZAMKNOU. Typicky 600 s (10 min).' },
    { key: 'forced_open_debounce_ms', label: 'Debounce násilného otevření', unit: 'ms', type: 'int',
      hint: 'Jak dlouho musí být dveře otevřené BEZ zadaného kódu, aby jednotka vyhlásila poruchu „násilné otevření“. Krátká prodleva odfiltruje falešné poplachy z otřesů a zákmitů. Typicky 500 ms.' },
    { key: 'pin_entry_timeout_s', label: 'Timeout zadávání PIN', unit: 's', type: 'int',
      hint: 'Za jak dlouho se na displeji smaže rozepsaný kód, když zákazník přestane ťukat. Aby po odchozím zákazníkovi nezůstal na obrazovce půlka kódu. Typicky 20 s.' },
    { key: 'overtime_alert_minutes', label: 'Upozornění při překročení', unit: 'min, čárkami', type: 'list',
      hint: 'Po kolika minutách otevřených dveří se opakuje upozornění do Velína. Zadejte čísla oddělená čárkou, např. 10, 20, 30.' },
  ] },
  { key: 'polling', title: 'Polling (Modbus)',
    hint: 'Jak často a jak trpělivě se jednotka ptá relé modulů Waveshare po síti LAN. Měňte jen při problémech se sítí — výchozí hodnoty jsou ověřené.',
    fields: [
    { key: 'door_input_poll_ms', label: 'Čtení kontaktů', unit: 'ms', type: 'int',
      hint: 'Jak často jednotka čte stav dveřních kontaktů. Nižší číslo = rychlejší reakce na otevření, vyšší zátěž sítě. Typicky 100 ms.' },
    { key: 'software_debounce_ms', label: 'SW debounce', unit: 'ms', type: 'int',
      hint: 'Jak dlouho musí být nová hodnota kontaktu stabilní, než ji jednotka vezme vážně. Filtruje zákmity mechanického kontaktu. Typicky 300 ms.' },
    { key: 'modbus_timeout_ms', label: 'Timeout Modbus', unit: 'ms', type: 'int',
      hint: 'Jak dlouho jednotka čeká na odpověď relé modulu, než pokus prohlásí za neúspěšný. Typicky 500 ms.' },
    { key: 'retry_delays_ms', label: 'Prodlevy opakování', unit: 'ms, čárkami', type: 'list',
      hint: 'Po jakých prodlevách se zopakuje neúspěšný dotaz na relé modul. Počet čísel = počet opakování. Typicky 100, 250, 500.' },
    { key: 'device_offline_after_failures', label: 'Offline po selháních', unit: '×', type: 'int',
      hint: 'Po kolika neúspěšných pokusech za sebou se modul označí za nedostupný. Zóny na něm pak hlásí poruchu „I/O modul nedostupný“ a nejde je otevřít. Typicky 3.' },
  ] },
  { key: 'contacts', title: 'Dveřní kontakty',
    hint: 'Jak jednotka pozná, že jsou dveře zavřené. Závisí na typu čidla (NC / NO) a na zapojení.',
    fields: [
    { key: 'closed_level', label: 'Úroveň vstupu při zavřených dveřích', unit: '0/1', type: 'int',
      hint: 'Jakou hodnotu hlásí vstup modulu, když jsou dveře ZAVŘENÉ. Pro běžný NC kontakt je to 1. Když je to nastavené obráceně, jednotka považuje otevřené dveře za zavřené — ověřte na prázdné kóji (blok Diagnostika → HW test).' },
  ] },
  { key: 'security', title: 'Bezpečnost (PIN)',
    hint: 'Ochrana proti hádání kódů na displeji a platnost servisního přístupu.',
    fields: [
    { key: 'maximum_failed_attempts', label: 'Max. neúspěšných pokusů', unit: '×', type: 'int',
      hint: 'Kolik špatných kódů po sobě smí kdokoli na displeji zadat, než se zadávání dočasně zablokuje. Typicky 5.' },
    { key: 'attempt_window_minutes', label: 'Okno pokusů', unit: 'min', type: 'int',
      hint: 'Za jak dlouhou dobu se neúspěšné pokusy počítají dohromady. Po uplynutí se počítadlo nuluje. Typicky 5 min.' },
    { key: 'lockout_minutes', label: 'Uzamčení po překročení', unit: 'min', type: 'int',
      hint: 'Jak dlouho displej po překročení počtu pokusů odmítá další kódy. Zákazník uvidí, za kolik minut to může zkusit znovu. Typicky 15 min.' },
    { key: 'service_token_minutes', label: 'Platnost servisního přístupu', unit: 'min', type: 'int',
      hint: 'Jak dlouho zůstane po zadání servisního hesla otevřený servisní panel na displeji, než se sám zamkne. Typicky 10 min.' },
  ] },
  { key: 'audio', title: 'Audio',
    hint: 'Hlasitost a chování přehrávání. Skladby se nahrávají v bloku „Hudba pobočky“; výstupy a režim (selector / multi) nastavíte v sekci „Audio — režim, výstupy“ níže.',
    fields: [
    { key: 'volume', label: 'Hlasitost', unit: '%', type: 'int',
      hint: 'Hlasitost přehrávače na jednotce v procentech (0–100). Celkovou hlasitost dolaďte i na zesilovači. Typicky 70 %.' },
    { key: 'fade_in_ms', label: 'Náběh hlasitosti', unit: 'ms', type: 'int',
      hint: 'Jak dlouho hudba po zadání kódu plynule naběhne z ticha na nastavenou hlasitost, aby zákazníka nevylekala. Typicky 1500 ms.' },
    { key: 'fade_out_ms', label: 'Doběh hlasitosti', unit: 'ms', type: 'int',
      hint: 'Jak dlouho hudba na konci plynule ztichne místo rázového vypnutí. Typicky 500 ms.' },
    { key: 'selector_settle_ms', label: 'Prodleva po vypnutí relé', unit: 'ms', type: 'int',
      hint: 'Jen režim „selector“ (jeden zesilovač + přepínací relé): jak dlouho se počká po rozepnutí všech audio relé, než se sepne relé nové kóje. Zabrání lupnutí a sepnutí dvou reproduktorů naráz. Typicky 200 ms.' },
    { key: 'selector_on_ms', label: 'Prodleva po sepnutí relé', unit: 'ms', type: 'int',
      hint: 'Jen režim „selector“: jak dlouho se počká po sepnutí relé kóje, než se spustí přehrávání. Typicky 100 ms.' },
    { key: 'device', label: 'Zvukové zařízení (mpv)', unit: 'prázdné = výchozí', type: 'text',
      hint: 'Jen režim „selector“: jméno zvukové karty pro přehrávač, např. „alsa/plughw:CARD=Box1“. Seznam získáte na jednotce příkazem „aplay -L“. Prázdné = výchozí výstup systému (na Raspberry je to HDMI — pak z reproduktorů nic nehraje). V režimu „multi“ se zařízení nastavuje u každého výstupu zvlášť.' },
    { key: 'shuffle', label: 'Náhodné pořadí skladeb', type: 'bool',
      hint: 'Zapnuto = skladby se přehrávají zamíchaně, takže zákazník neslyší pořád stejnou písničku jako první. Vypnuto = hraje se v pořadí nastaveném v bloku „Hudba pobočky“.' },
  ] },
  { key: 'signal', title: 'Signalizace (Shelly)',
    hint: 'Barevná světla u kójí (Shelly RGBWW): červená = zamčeno, zelená = otevřeno / probíhá relace, blikání = porucha nebo překročený čas.',
    fields: [
    { key: 'brightness', label: 'Jas', unit: '%', type: 'int',
      hint: 'Jas signalizačních světel v procentech (0–100). Ve tmavé hale stačí méně, na přímém světle dejte 100 %.' },
    { key: 'blink_ms', label: 'Perioda blikání', unit: 'ms', type: 'int',
      hint: 'Jak rychle bliká výstražná signalizace (porucha, obě barvy). Nižší číslo = rychlejší blikání. Typicky 500 ms.' },
    { key: 'pulse_ms', label: 'Perioda pulzování', unit: 'ms', type: 'int',
      hint: 'Jak rychle pulzuje zelená při překročeném čase otevření (plynulé zesilování a zeslabování). Typicky 1500 ms.' },
    { key: 'transition_s', label: 'Přechod', unit: 's', type: 'float',
      hint: 'Jak dlouho trvá plynulý přechod mezi barvami, aby světlo neskákalo skokově. Typicky 0,2 s.' },
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

// Vrátí Set klíčů kanálů, které se objevují ve více než jedné roli/dveřích.
// `extraRefs` = [{ ref, role }] kanály mimo dveře (světlo / enable relé venku — outdoorRefs()), počítají se stejně.
export function findDuplicateChannels(hwByDoor, extraRefs = []) {
  const counts = new Map()
  const add = (ref, role) => { const k = channelKey(ref, role); if (k) counts.set(k, (counts.get(k) || 0) + 1) }
  Object.values(hwByDoor || {}).forEach(hw => ZONE_REFS.forEach(role => add(hw?.[role.key], role)))
  ;(extraRefs || []).forEach(x => add(x?.ref, x?.role))
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

// Set názvů výstupů, které sdílí víc cílů (dveře mezi sebou nebo dveře + venek) — jednotka odmítá.
// `outdoor` = výstup venku (outdoorOutOf(hardware) z BranchRpiOutdoorHelpers.js) nebo ''.
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

// Set čísel zón, která má víc než jedny dveře (jednotka odmítá: „Duplicitní čísla zón.“).
// `outdoorZone` (volitelné) = číslo zóny venku — koliduje-li s dveřmi, jednotka mapu odmítne („Venek: číslo zóny N koliduje s dveřmi“).
export function findDuplicateZones(hwByDoor, outdoorZone) {
  const counts = new Map()
  const add = v => { const n = parseInt(v, 10); if (Number.isFinite(n) && n >= 1) counts.set(n, (counts.get(n) || 0) + 1) }
  Object.values(hwByDoor || {}).forEach(hw => add(hw?.zone))
  add(outdoorZone)
  return new Set([...counts.entries()].filter(([, c]) => c > 1).map(([n]) => n))
}

// Šablona: číslo zóny pro dveře šatny = nejvyšší zóna šablony, kterou nezabírá žádná kóje (null = žádná volná)
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
