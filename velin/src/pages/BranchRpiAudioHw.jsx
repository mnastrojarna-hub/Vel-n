import { useState, useEffect, useMemo } from 'react'
import { Btn, Chip, Input, Select, Checkbox, HintedCell, FIT_SELECT } from './BranchRpiUi'
import { AUDIO_MODES, BRNO_AUDIO_OUTPUTS_EXAMPLE, audioMode, audioOutputNames, roleTypeError, toPhysical, fromPhysical, ZONE_REFS } from './BranchRpiHardwareDefaults'
import { outdoorOf, outdoorOutOf, outdoorRelayError, doorCoils } from './BranchRpiOutdoorHelpers'
import { HintList } from './BranchRpiTouchHint'

// ─── Audio: režim, výstupy (`hardware.audio.{mode,outputs}`) ─────────────────
// Kontrakt (music_contract §2): selector = jeden zesilovač + relé (výchozí, beze změny chování),
// multi = pojmenované výstupy (název → ALSA zařízení dle `aplay -L`), každá zóna má `audio.out`,
// venek (zóna bez dveří) hraje při jakémkoli kódu — jeho výstup se nastavuje v bloku Venek (`outdoor.audio.out`;
// legacy `audio.channels.outdoor` tento editor nemění, jen ho čte přes outdoorOutOf). Stejná pravidla jako
// validate_audio() v jednotce: výstup musí existovat, dva cíle nesmí sdílet výstup, venek vyžaduje multi.
// V režimu selector jednotka výstup venku nevaliduje (validate_audio končí upozorněním) a blok Venek je jen ke čtení —
// proto venek v selectoru NEBLOKUJE smazání/přejmenování výstupu (jinak by šel odstranit jen přes „Vymazat venek“).

const NAME_RE = /^[a-z0-9_-]+$/
const AUDIO_ROLE = ZONE_REFS.find(r => r.key === 'audio')
const CUSTOM = '__custom'
// Zařízení výstupu (2026-09-28): „auto“ = jediná USB zvuková karta, „usb:<port>“ = karta na konkrétním USB portu (pro 9 stejných
// adaptérů), jinak ALSA řetězec. Jednotka to sama přeloží (bez terminálu) a karty hlásí ve status.audio.cards.
const isKnownDevice = d => d === '' || d === 'auto' || d.startsWith('usb:')

function deviceOptions(cards, value) {
  const opts = [{ value: 'auto', label: 'Automaticky — jediná USB zvuková karta' }]
  for (const c of cards || []) if (c?.usb_path) opts.push({ value: `usb:${c.usb_path}`, label: `USB port ${c.usb_path} — ${c.name || c.id}` })
  if (value.startsWith('usb:') && !opts.some(o => o.value === value)) opts.push({ value, label: `USB port ${value.slice(4)} (nenalezeno)` })
  opts.push({ value: '', label: '— výchozí výstup (HDMI) —' }, { value: CUSTOM, label: 'vlastní ALSA zařízení…' })
  return opts
}

function outputsToRows(audio) {
  const outs = audio?.outputs && typeof audio.outputs === 'object' ? audio.outputs : {}
  return Object.entries(outs).map(([name, o], i) => {
    const device = o && typeof o === 'object' ? String(o.device ?? '') : String(o ?? '')
    return { _k: `${name}-${i}`, name: String(name), device, mono: !!(o && typeof o === 'object' && o.mono), custom: !isKnownDevice(device) }
  })
}

// Stav karty výstupu dle jednotky; `hint` = text pro „i“ na dotyku (u NENALEZENA je problém už v textu čipu)
function presenceOf(player) {
  if (!player) return { tone: 'gray', title: 'Jednotka o výstupu zatím nehlásí stav (uložte a počkejte na synchronizaci).', text: 'stav neznámý', hint: true }
  if (player.present === false) return { tone: 'red', title: player.problem || '', text: `karta NENALEZENA${player.problem ? ` — ${player.problem}` : ''}`, hint: false }
  return { tone: player.alive ? 'green' : 'amber', title: `mpv: ${player.device || 'výchozí'}`, text: player.alive ? 'karta nalezena' : 'karta nalezena, mpv neběží', hint: true }
}
function PresenceChip({ player }) {
  const p = presenceOf(player)
  return <Chip tone={p.tone} title={p.title}>{p.text}</Chip>
}
const USAGE_TITLE = 'Kdo výstup používá (dle uložené mapy)'
const LOCKER_ONLY_TITLE = 'Dnešní zapojení: 1 USB→jack adaptér → zesilovač → reproduktor v šatně'
const EXAMPLE_TITLE = 'Vyplní out1–out9 (venek = out9 nastavíte v bloku Venek); režim nepřepíná'

// Kdo výstup používá (dveře dle uloženého hw + venek) — pro chip u řádku a blokaci smazání
function outputUsage(doors, outdoor) {
  const use = {}
  const add = (o, who) => { const n = String(o ?? '').trim(); if (n) (use[n] = use[n] || []).push(who) }
  ;(doors || []).forEach(d => add(d?.hw?.audio?.out, d.door_kind === 'accessories' ? 'šatna' : `kóje ${d.box_number}`))
  add(outdoor, 'venek')
  return use
}

function AudioOutputsEditor({ hardware, doors, disabled, onSave, onSaveDoor, status, onCommand }) {
  const rawAudio = hardware?.audio
  const audio = useMemo(() => (rawAudio && typeof rawAudio === 'object' ? rawAudio : {}), [rawAudio])   // stabilní ref pro efekt
  const [mode, setMode] = useState(() => audioMode(audio))
  // Hlavní vypínač hudby pobočky (`audio.music_enabled`; chybí = zapnuto). Vypnuto = po zadání kódu
  // se hudba nespustí nikde — zesilovače jsou napájené trvale, takže jinak hudbu nešlo vypnout.
  const [musicOn, setMusicOn] = useState(() => audio.music_enabled !== false)
  const [rows, setRows] = useState(() => outputsToRows(audio))
  const [dirty, setDirty] = useState(false)
  const [err, setErr] = useState(null)
  const [msg, setMsg] = useState(null)
  const [lockerPreset, setLockerPreset] = useState(false)
  const cards = Array.isArray(status?.cards) ? status.cards : []
  const players = status?.players && typeof status.players === 'object' ? status.players : {}
  const accDoor = (doors || []).find(d => d.door_kind === 'accessories')
  useEffect(() => {
    if (dirty) return
    setMode(audioMode(audio)); setRows(outputsToRows(audio)); setMusicOn(audio.music_enabled !== false)
  }, [audio, dirty])
  const multi = mode === 'multi'

  const nameCounts = useMemo(() => rows.reduce((m, r) => { m[r.name.trim()] = (m[r.name.trim()] || 0) + 1; return m }, {}), [rows])
  const usage = useMemo(() => outputUsage(doors, outdoorOutOf(hardware)), [doors, hardware])
  // Kdo smazání/přejmenování výstupu blokuje: dveře vždy, venek jen v multi (viz hlavička). Při přepínání selector → multi
  // je blok Venek (řídí se ULOŽENÝM režimem) ještě ke čtení — nápověda, jak z toho ven.
  const blockers = who => (who || []).filter(w => multi || w !== 'venek')
  const usedMsg = (name, who) => `Výstup „${name}“ používá ${who.join(', ')} — nejdřív změňte výstup v mapování dveří / bloku Venek`
    + (who.includes('venek') && audioMode(audio) !== 'multi' ? ' (blok Venek je v selectoru jen ke čtení: uložte režim multi s tímto výstupem, pak výstup venku změňte, nebo venek vymažte)' : '') + '.'

  function edit(i, patch) { setRows(rs => rs.map((r, j) => j === i ? { ...r, ...patch } : r)); setDirty(true) }
  function add() {
    const n = rows.length + 1
    setRows(rs => [...rs, { _k: `new-${Date.now()}`, name: `out${n}`, device: 'auto', mono: true, custom: false }]); setDirty(true)
  }
  function remove(i) {
    const who = blockers(usage[rows[i]?.name?.trim()])
    if (who.length) { setErr(usedMsg(rows[i].name, who)); return }
    setRows(rs => rs.filter((_, j) => j !== i)); setDirty(true)
  }
  // Dnešní zapojení (2026-09-28): 1 USB→jack adaptér → zesilovač → reproduktor v šatně. Kóje bez výstupu = bez reproduktoru.
  function fillLockerOnly() {
    if (!window.confirm('Nastavit „Jen šatna“: režim multi, jeden výstup out8 = USB zvuková karta (automaticky), mono; šatna hraje přes out8, kóje bez reproduktoru. Po uložení tlačítkem „Test výstupu“ ověřte pípnutí ze šatny.')) return
    setMode('multi')
    setRows([{ _k: `out8-${Date.now()}`, name: 'out8', device: 'auto', mono: true, custom: false }])
    setLockerPreset(true); setDirty(true); setErr(null)
  }
  async function testOutput(name) {
    if (!onCommand) return
    setMsg(null)
    if (await onCommand('audio_test', { out: name, seconds: 3 })) setMsg(`Test výstupu ${name} odeslán — z reproduktoru má ~3 s pípat (i bez nahrané hudby). Výsledek: Hlášení a chyby.`)
  }
  function fillExample() {
    if (rows.length && !window.confirm('Nahradit seznam výstupů vzorem out1–out9 (7 kójí, šatna, venek)? Režim se NEpřepne — u každého výstupu zvolte USB port adaptéru a uložte. Výstup venku (out9) pak nastavte v bloku Venek.')) return
    setRows(outputsToRows({ outputs: BRNO_AUDIO_OUTPUTS_EXAMPLE }))
    setLockerPreset(false)
    setDirty(true)
    setErr(null)
  }

  async function save() {
    const outputs = {}
    for (const r of rows) {
      const name = r.name.trim()
      if (!NAME_RE.test(name)) { setErr(`Název výstupu „${r.name}“ musí být malá písmena, číslice, - nebo _.`); return }
      if (outputs[name]) { setErr(`Duplicitní název výstupu „${name}“.`); return }
      const prev = audio.outputs?.[name]
      outputs[name] = { ...(prev && typeof prev === 'object' ? prev : {}), device: r.device.trim() || null }
      if (r.mono) outputs[name].mono = true; else delete outputs[name].mono
    }
    if (mode === 'multi' && !Object.keys(outputs).length) { setErr('Režim multi vyžaduje aspoň jeden výstup (název + ALSA zařízení dle aplay -L).'); return }
    // Přejmenování/smazání výstupu, na který se odkazují uložené dveře nebo venek (stejně jako remove()) — v multi
    // jednotka celou mapu odmítne (validate_audio: „Zóna N: audio výstup 'x' není v audio.outputs.“ / „Kanál outdoor: …“).
    // V selectoru blokujeme jen nově vzniklou díru (dříve stale `out` jednotka ignoruje a editor dveří ho v selectoru neukazuje).
    const before = audio.outputs && typeof audio.outputs === 'object' ? audio.outputs : {}
    const lockerUse = lockerPreset && accDoor ? { ...usage } : usage
    if (lockerPreset && accDoor) {                     // šatna se přepne na out8 v témže uložení — její starý výstup neblokuje
      for (const k of Object.keys(lockerUse)) lockerUse[k] = (lockerUse[k] || []).filter(w => w !== 'šatna')
    }
    const orphan = Object.entries(lockerUse).map(([n, who]) => [n, blockers(who)]).find(([n, who]) => !outputs[n] && who.length && (multi || n in before))
    if (orphan) { setErr(usedMsg(orphan[0], orphan[1])); return }
    if (multi) {
      // Přepnutí na multi: enable relé venku se v selectoru nehlídá (jednotka ho tam ignoruje), dveře mezitím mohly cívku
      // obsadit — validate_audio by v multi celou mapu odmítl („Kanál outdoor: relé … už používá zóna N“).
      const relayErr = outdoorRelayError(outdoorOf(hardware).audio, hardware?.devices, doorCoils(doors))
      if (relayErr) { setErr(`${relayErr} Změňte cívku v mapování dveří, nebo venek vymažte a po uložení režimu multi nastavte znovu.`); return }
    }
    const next = { ...audio, mode }   // `channels` (vč. legacy venku) se zde nemění — venek spravuje blok Venek
    if (musicOn) delete next.music_enabled; else next.music_enabled = false   // výchozí (zapnuto) se do mapy nepíše
    if (Object.keys(outputs).length) next.outputs = outputs; else delete next.outputs
    if (next.device === null || next.device === '') delete next.device   // null by přebil USB kartu z instalace (selector)
    setErr(null)
    if ((await onSave(next)) === false) return
    if (lockerPreset && accDoor && onSaveDoor) {
      const hw = accDoor.hw && typeof accDoor.hw === 'object' ? accDoor.hw : {}
      await onSaveDoor(accDoor.id, { hw: { ...hw, audio: { ...(hw.audio && typeof hw.audio === 'object' ? hw.audio : {}), out: 'out8' } } })
    }
    setLockerPreset(false)
    setDirty(false)
  }

  return (
    <div className="p-3 rounded-card" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
      <div className="flex items-center justify-between gap-2 mb-2 flex-wrap">
        <div>
          <div className="text-[12px] font-extrabold uppercase" style={{ color: '#1a2e22' }}>Audio — režim, výstupy</div>
          <div className="text-[11px]" style={{ color: '#6b8c7a' }}>
            multi = každá místnost s reproduktorem má vlastní výstup (USB→jack adaptér + zesilovač) a hraje po kódu svých dveří. Dnes stačí „Jen šatna (1 výstup)“; další výstupy (kóje, venek) přidáte, až budou zapojené — dveře bez výstupu jsou „bez reproduktoru“ (po kódu nehrají, není to chyba). Zařízení: „Automaticky“ = jediná USB karta, u více adaptérů zvolte USB port (jednotka karty hlásí sama, bez terminálu). selector = 1 zesilovač + přepínací relé.
          </div>
        </div>
        <div className="flex gap-2 max-lg:flex-wrap">
          <Btn tone="blue" onClick={add} disabled={disabled}>Přidat výstup</Btn>
          <Btn tone="green" onClick={fillLockerOnly} disabled={disabled} title={LOCKER_ONLY_TITLE}>Jen šatna (1 výstup)</Btn>
          <Btn tone="gray" onClick={fillExample} disabled={disabled} title={EXAMPLE_TITLE}>Vzor 9 výstupů (7 kójí, šatna, venek)</Btn>
          <Btn tone="dark" onClick={save} disabled={disabled || !dirty}>{dirty ? 'Uložit audio' : 'Uloženo'}</Btn>
          {/* Dotyk: co vyplní tlačítka vzorů (na PC bublina) */}
          <HintList items={[['Jen šatna', LOCKER_ONLY_TITLE], ['Vzor 9 výstupů', EXAMPLE_TITLE]]} />
        </div>
      </div>
      <div className="flex gap-2 flex-wrap items-end mb-2">
        <div className="p-2 rounded-lg self-center" style={{ background: musicOn ? '#f1faf7' : '#fef3c7', border: `1px solid ${musicOn ? '#d4e8e0' : '#fde68a'}` }}>
          <Checkbox label={musicOn ? 'Hudba na pobočce zapnutá' : 'Hudba na pobočce VYPNUTÁ'} checked={musicOn}
            title="Hlavní vypínač hudby pro celou pobočku. Zapnuto = po zadání kódu se v dané kóji (šatně) spustí hudba. Vypnuto = nehraje nikde, ani venku — dveře se otevírají normálně. Jednotlivé kóje a šatna si to můžou přepsat v mapování dveří níže („Hudba“)."
            onChange={v => { setMusicOn(v); setDirty(true) }} />
        </div>
        <Select label="Režim" width={460} value={mode} options={AUDIO_MODES}
          title="Jak je pobočka ozvučená. „selector“ = jeden zesilovač a přepínací relé: hraje vždy jen JEDNA kóje a venku nehraje nic. „multi“ = každá kóje, šatna i venek má vlastní zvukovou kartu a vlastní přehrávač, takže hrají současně a každá své skladby. Pro vlastní hudbu v každé kóji (blok „Hudba pobočky“) je potřeba „multi“."
          onChange={v => { setMode(v); setDirty(true) }} />
      </div>
      {rows.length === 0 ? (
        <div className="text-[12px]" style={{ color: '#6b8c7a' }}>{multi ? 'Žádné výstupy — režim multi bez výstupů jednotka odmítne.' : 'Žádné výstupy (v režimu selector nejsou potřeba).'}</div>
      ) : (
        <div className="space-y-1">
          {rows.map((r, i) => {
            const name = r.name.trim()
            const badName = !NAME_RE.test(name) || nameCounts[name] > 1
            const who = usage[name]
            const pres = presenceOf(players[name])
            const testTitle = dirty ? 'Nejdřív uložte audio.' : !players[name] ? 'Jednotka výstup zatím nemá (uložte a počkejte na synchronizaci).' : 'Pípne 3 s z reproduktoru tohoto výstupu (i bez hudby).'
            return (
              <div key={r._k} className="flex items-end gap-2 flex-wrap p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                <Input label="Název" width={100} value={r.name} placeholder="out1" invalid={badName}
                  title={badName ? 'Název musí být unikátní, malá písmena/číslice/-/_' : 'Odkaz z mapování dveří (audio.out)'}
                  onChange={v => edit(i, { name: v })} />
                <Select label="Zvuková karta" width={280} value={r.custom ? CUSTOM : r.device} options={deviceOptions(cards, r.device)}
                  warn={!r.device.trim()}
                  title={!r.device.trim() ? 'Výchozí výstup systému = HDMI — z reproduktoru v místnosti nic nehraje. Zvolte USB kartu.'
                    : 'Automaticky = jediná připojená USB zvuková karta. Při více adaptérech zvolte USB port (seznam hlásí jednotka).'}
                  onChange={v => edit(i, v === CUSTOM ? { custom: true } : { device: v, custom: false })} />
                {r.custom && <Input label="ALSA zařízení" width={220} value={r.device} placeholder="alsa/plughw:CARD=Device"
                  onChange={v => edit(i, { device: v })} />}
                <div className="self-center"><Checkbox label="Mono" checked={!!r.mono}
                  title="Reproduktor je na jednom kanálu zesilovače → mono hraje celý mix do obou kanálů (doporučeno)."
                  onChange={v => edit(i, { mono: v })} /></div>
                <PresenceChip player={players[name]} />
                <Chip tone={who?.length ? 'green' : 'gray'} title={USAGE_TITLE}>{who?.length ? who.join(', ') : 'volný'}</Chip>
                {onCommand && <Btn tone="blue" small onClick={() => testOutput(name)} disabled={disabled || dirty || !players[name]}
                  title={testTitle}
                  style={{ alignSelf: 'center' }}>Test výstupu</Btn>}
                {/* Dotyk: bubliny čipů stavu/použití a „Test výstupu“ pod jedním „i“ (na PC beze změny) */}
                <HintList items={[pres.hint && [pres.text, pres.title], [who?.length ? who.join(', ') : 'volný', USAGE_TITLE], onCommand && ['Test výstupu', testTitle]]} />
                <Btn tone="red" small onClick={() => remove(i)} disabled={disabled} style={{ alignSelf: 'center', marginLeft: 'auto' }}>Smazat</Btn>
              </div>
            )
          })}
        </div>
      )}
      {cards.length > 0 && <div className="text-[11px] mt-2" style={{ color: '#6b8c7a' }}>
        Jednotka vidí karty: {cards.map(c => `${c.index}: ${c.name || c.id}${c.usb_path ? ` (USB ${c.usb_path})` : ''}`).join(' · ')}</div>}
      {msg && <div className="text-[12px] font-bold mt-2" style={{ color: '#1a8a18' }}>{msg}</div>}
      {err && <div className="text-[12px] font-bold mt-2" style={{ color: '#dc2626' }}>{err}</div>}
    </div>
  )
}

// ── Buňka role „Audio“ v řádku dveří ─────────────────────────────────────────
// selector: relé {dev, coil} (jako dosud). multi: výstup {out} ze seznamu + volitelné enable relé zesilovače.
function DoorAudioCell({ zoneNo, audioRef, audio, devices, devOptions, dup, dupOut, onPatch }) {
  const ref = audioRef || { dev: '', coil: '', out: '' }
  const multi = audioMode(audio) === 'multi'
  const names = audioOutputNames(audio)
  const out = String(ref.out ?? '').trim()
  const typeErr = roleTypeError(zoneNo, AUDIO_ROLE, ref.dev, devices)
  const unknownDev = !!(ref.dev && !devices?.[ref.dev])
  const relayTitle = dup ? 'Tenhle kanál už používá jiná zóna nebo venek — každý kanál smí patřit jen jedné zóně.' : typeErr ? `${typeErr} Povolené: wav645/wav617.`
    : multi ? 'Nepovinné: relé, které zapne zesilovač této místnosti, když v ní má hrát hudba (modul + relé). Nechte prázdné, pokud je zesilovač napájený trvale.'
      : 'Relé audio přepínače pro tuto místnost (modul + relé). V režimu „selector“ je jen jedno ozvučení a relé přepíná, do které kóje jde zvuk.'
  const relay = (
    <div className="flex gap-1">
      <Select width={96} className={FIT_SELECT} value={ref.dev} options={unknownDev ? [...devOptions, { value: ref.dev, label: `${ref.dev} (?)` }] : devOptions}
        invalid={dup || !!typeErr} onChange={v => onPatch(p => ({ ...p, audio: { ...p.audio, dev: v } }))} />
      <span className="self-center text-[11px] font-extrabold" style={{ color: '#6b8c7a', minWidth: 14 }}>R</span>
      <Input width={54} type="number" min={1} value={toPhysical(AUDIO_ROLE, ref.coil)} placeholder="R…" invalid={dup || !!typeErr}
        onChange={v => onPatch(p => ({ ...p, audio: { ...p.audio, coil: fromPhysical(AUDIO_ROLE, v) } }))} />
    </div>
  )
  if (!multi) return <HintedCell title={relayTitle} label="Audio">{relay}</HintedCell>
  const unknownOut = !!(out && !names.includes(out))
  const outOptions = [{ value: '', label: '— bez reproduktoru —' }, ...names.map(n => ({ value: n, label: n }))]
  if (unknownOut) outOptions.push({ value: out, label: `${out} (?)` })
  const outTitle = dupOut ? `Výstup ${out} už používá jiná zóna nebo venek — každý zvukový výstup smí patřit jen jedné místnosti.`
    : unknownOut ? `Výstup „${out}“ v seznamu výstupů nahoře neexistuje — jednotka by celou mapu odmítla. Vyberte existující, nebo ho doplňte v sekci Audio.`
      : !out ? 'Bez reproduktoru: po kódu tu hudba nehraje (není to chyba). Až bude reproduktor zapojený, vyberte jeho výstup.'
        : `Hudba této místnosti hraje přes výstup „${out}“ (nastavuje se v sekci Audio výše).`
  // Bubliny jsou na PC u výstupu a u relé zvlášť; na dotyku obě vysvětlivky pod jedním „i“ u popisku
  return (
    <HintedCell label="Audio výstup / relé (volit.)" hint={`${outTitle} Relé: ${relayTitle}`}>
      <div className="flex gap-1 max-sm:flex-wrap">
        <Select width={150} className={FIT_SELECT} value={out} options={outOptions} invalid={dupOut || unknownOut} title={outTitle}
          onChange={v => onPatch(p => ({ ...p, audio: { ...p.audio, out: v } }))} />
        {/* Dotyk: relé nesmí přetéct buňku ani s dlouhým názvem zařízení (výběr se pak zúží na min. 96 px) */}
        <span title={relayTitle} className="max-lg:max-w-full">{relay}</span>
      </div>
    </HintedCell>
  )
}

export { AudioOutputsEditor, DoorAudioCell }
