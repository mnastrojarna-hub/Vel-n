import { useState, useEffect, useMemo } from 'react'
import { Btn, Chip, Input, Select, Label } from './BranchRpiUi'
import { AUDIO_MODES, BRNO_AUDIO_OUTPUTS_EXAMPLE, audioMode, audioOutputNames, roleTypeError, ZONE_REFS } from './BranchRpiHardwareDefaults'
import { outdoorOutOf } from './BranchRpiOutdoorHelpers'

// ─── Audio: režim, výstupy (`hardware.audio.{mode,outputs}`) ─────────────────
// Kontrakt (music_contract §2): selector = jeden zesilovač + relé (výchozí, beze změny chování),
// multi = pojmenované výstupy (název → ALSA zařízení dle `aplay -L`), každá zóna má `audio.out`,
// venek (zóna bez dveří) hraje při jakémkoli kódu — jeho výstup se nastavuje v bloku Venek (`outdoor.audio.out`;
// legacy `audio.channels.outdoor` tento editor nemění, jen ho čte přes outdoorOutOf). Stejná pravidla jako
// validate_audio() v jednotce: výstup musí existovat, dva cíle nesmí sdílet výstup, venek vyžaduje multi.

const NAME_RE = /^[a-z0-9_-]+$/
const AUDIO_ROLE = ZONE_REFS.find(r => r.key === 'audio')

function outputsToRows(audio) {
  const outs = audio?.outputs && typeof audio.outputs === 'object' ? audio.outputs : {}
  return Object.entries(outs).map(([name, o], i) => ({
    _k: `${name}-${i}`, name: String(name), device: o && typeof o === 'object' ? String(o.device ?? '') : String(o ?? ''),
  }))
}

// Kdo výstup používá (dveře dle uloženého hw + venek) — pro chip u řádku a blokaci smazání
function outputUsage(doors, outdoor) {
  const use = {}
  const add = (o, who) => { const n = String(o ?? '').trim(); if (n) (use[n] = use[n] || []).push(who) }
  ;(doors || []).forEach(d => add(d?.hw?.audio?.out, d.door_kind === 'accessories' ? 'oblečení' : `kóje #${d.box_number}`))
  add(outdoor, 'venek')
  return use
}

function AudioOutputsEditor({ hardware, doors, disabled, onSave }) {
  const rawAudio = hardware?.audio
  const audio = useMemo(() => (rawAudio && typeof rawAudio === 'object' ? rawAudio : {}), [rawAudio])   // stabilní ref pro efekt
  const [mode, setMode] = useState(() => audioMode(audio))
  const [rows, setRows] = useState(() => outputsToRows(audio))
  const [dirty, setDirty] = useState(false)
  const [err, setErr] = useState(null)
  useEffect(() => {
    if (dirty) return
    setMode(audioMode(audio)); setRows(outputsToRows(audio))
  }, [audio, dirty])

  const nameCounts = useMemo(() => rows.reduce((m, r) => { m[r.name.trim()] = (m[r.name.trim()] || 0) + 1; return m }, {}), [rows])
  const usage = useMemo(() => outputUsage(doors, outdoorOutOf(hardware)), [doors, hardware])

  function edit(i, patch) { setRows(rs => rs.map((r, j) => j === i ? { ...r, ...patch } : r)); setDirty(true) }
  function add() {
    const n = rows.length + 1
    setRows(rs => [...rs, { _k: `new-${Date.now()}`, name: `out${n}`, device: '' }]); setDirty(true)
  }
  function remove(i) {
    const who = usage[rows[i]?.name?.trim()]
    if (who?.length) { setErr(`Výstup „${rows[i].name}“ používá ${who.join(', ')} — nejdřív změňte výstup v mapování dveří / bloku Venek.`); return }
    setRows(rs => rs.filter((_, j) => j !== i)); setDirty(true)
  }
  function fillExample() {
    if (rows.length && !window.confirm('Nahradit seznam výstupů vzorem out1–out9 (7 kójí, šatna, venek)? Režim se NEpřepne — zkontrolujte názvy karet (aplay -L) a uložte. Výstup venku (out9) pak nastavte v bloku Venek.')) return
    setRows(outputsToRows({ outputs: BRNO_AUDIO_OUTPUTS_EXAMPLE }))
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
    }
    if (mode === 'multi' && !Object.keys(outputs).length) { setErr('Režim multi vyžaduje aspoň jeden výstup (název + ALSA zařízení dle aplay -L).'); return }
    // Přejmenování/smazání výstupu, na který se odkazují uložené dveře nebo venek (stejně jako remove()) — v multi
    // jednotka celou mapu odmítne (validate_audio: „Zóna N: audio výstup 'x' není v audio.outputs.“ / „Kanál outdoor: …“).
    // V selectoru blokujeme jen nově vzniklou díru (dříve stale `out` jednotka ignoruje a editor dveří ho v selectoru neukazuje).
    const before = audio.outputs && typeof audio.outputs === 'object' ? audio.outputs : {}
    const orphan = Object.entries(usage).find(([n, who]) => !outputs[n] && who.length && (mode === 'multi' || n in before))
    if (orphan) { setErr(`Výstup „${orphan[0]}“ používá ${orphan[1].join(', ')} — nejdřív změňte výstup v mapování dveří / bloku Venek.`); return }
    const next = { ...audio, mode }   // `channels` (vč. legacy venku) se zde nemění — venek spravuje blok Venek
    if (Object.keys(outputs).length) next.outputs = outputs; else delete next.outputs
    setErr(null)
    await onSave(next)
    setDirty(false)
  }

  const multi = mode === 'multi'
  return (
    <div className="p-3 rounded-card" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
      <div className="flex items-center justify-between gap-2 mb-2 flex-wrap">
        <div>
          <div className="text-[12px] font-extrabold uppercase" style={{ color: '#1a2e22' }}>Audio — režim, výstupy</div>
          <div className="text-[11px]" style={{ color: '#6b8c7a' }}>
            selector = 1 zesilovač + relé (výchozí). multi = každá místnost vlastní zvukový výstup (USB zvukovka / pár vícekanálové karty) a vlastní mpv — hraje současně, venek při jakémkoli kódu (výstup venku nastavíte v bloku Venek). Zařízení = řetězek pro mpv, např. „alsa/plughw:CARD=Box1“ (názvy karet: na jednotce „aplay -L“).
          </div>
        </div>
        <div className="flex gap-2">
          <Btn tone="blue" onClick={add} disabled={disabled}>Přidat výstup</Btn>
          <Btn tone="gray" onClick={fillExample} disabled={disabled} title="Vyplní out1–out9 (venek = out9 nastavíte v bloku Venek); režim nepřepíná">Vzor 9 výstupů (7 kójí, šatna, venek)</Btn>
          <Btn tone="dark" onClick={save} disabled={disabled || !dirty}>{dirty ? 'Uložit audio' : 'Uloženo'}</Btn>
        </div>
      </div>
      <div className="flex gap-2 flex-wrap items-end mb-2">
        <Select label="Režim" width={460} value={mode} options={AUDIO_MODES} onChange={v => { setMode(v); setDirty(true) }} />
      </div>
      {rows.length === 0 ? (
        <div className="text-[12px]" style={{ color: '#6b8c7a' }}>{multi ? 'Žádné výstupy — režim multi bez výstupů jednotka odmítne.' : 'Žádné výstupy (v režimu selector nejsou potřeba).'}</div>
      ) : (
        <div className="space-y-1">
          {rows.map((r, i) => {
            const name = r.name.trim()
            const badName = !NAME_RE.test(name) || nameCounts[name] > 1
            const who = usage[name]
            return (
              <div key={r._k} className="flex items-end gap-2 flex-wrap p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                <Input label="Název" width={100} value={r.name} placeholder="out1" invalid={badName}
                  title={badName ? 'Název musí být unikátní, malá písmena/číslice/-/_' : 'Odkaz z mapování dveří (audio.out)'}
                  onChange={v => edit(i, { name: v })} />
                <Input label="ALSA zařízení (aplay -L)" width={260} value={r.device} placeholder="alsa/plughw:CARD=Box1" warn={!r.device.trim()}
                  title={r.device.trim() ? '' : 'Prázdné = výchozí ALSA výstup (na RPi 5 HDMI → místnost mlčí)'}
                  onChange={v => edit(i, { device: v })} />
                <Chip tone={who?.length ? 'green' : 'gray'} title="Kdo výstup používá (dle uložené mapy)">{who?.length ? who.join(', ') : 'volný'}</Chip>
                <Btn tone="red" small onClick={() => remove(i)} disabled={disabled} style={{ alignSelf: 'center', marginLeft: 'auto' }}>Smazat</Btn>
              </div>
            )
          })}
        </div>
      )}
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
  const relayTitle = dup ? 'Kanál už používá jiná zóna/role' : typeErr ? `${typeErr} Povolené: wav645/wav617.`
    : multi ? 'Volitelné enable relé zesilovače (dev + coil)' : 'Audio selektor: zařízení + coil'
  const relay = (
    <div className="flex gap-1">
      <Select width={96} value={ref.dev} options={unknownDev ? [...devOptions, { value: ref.dev, label: `${ref.dev} (?)` }] : devOptions}
        invalid={dup || !!typeErr} onChange={v => onPatch(p => ({ ...p, audio: { ...p.audio, dev: v } }))} />
      <Input width={54} type="number" min={0} value={ref.coil} placeholder="coil" invalid={dup || !!typeErr}
        onChange={v => onPatch(p => ({ ...p, audio: { ...p.audio, coil: v } }))} />
    </div>
  )
  if (!multi) return <div className="flex flex-col gap-0.5" title={relayTitle}><Label>Audio</Label>{relay}</div>
  const unknownOut = !!(out && !names.includes(out))
  const outOptions = [{ value: '', label: '—' }, ...names.map(n => ({ value: n, label: n }))]
  if (unknownOut) outOptions.push({ value: out, label: `${out} (?)` })
  const outTitle = dupOut ? `Výstup ${out} už používá jiná zóna nebo venek` : unknownOut ? `Výstup '${out}' není v audio.outputs`
    : !out ? 'Bez výstupu v této místnosti hudba nehraje' : `Výstup ${out} (audio.out)`
  return (
    <div className="flex flex-col gap-0.5">
      <Label>Audio výstup / relé (volit.)</Label>
      <div className="flex gap-1">
        <Select width={96} value={out} options={outOptions} invalid={dupOut || unknownOut} warn={!out} title={outTitle}
          onChange={v => onPatch(p => ({ ...p, audio: { ...p.audio, out: v } }))} />
        <span title={relayTitle}>{relay}</span>
      </div>
    </div>
  )
}

export { AudioOutputsEditor, DoorAudioCell }
