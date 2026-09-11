import { useState, useEffect, useMemo } from 'react'
import { Btn, Chip, Input, Select, Label } from './BranchRpiUi'
import { audioMode, audioOutputNames } from './BranchRpiHardwareDefaults'
import {
  outdoorOf, outdoorToDraft, draftToOutdoor, doorCoils, legacyOutdoorChannel, audioWithoutOutdoorChannel,
  outdoorLightError, outdoorRelayError, outdoorShareError, outdoorOutError, outdoorZoneError,
} from './BranchRpiOutdoorHelpers'

// ─── Venek (zóna bez dveří) — editor `hardware.outdoor` ──────────────────────
// Venek NENÍ řádek branch_doors: bez zámku, kontaktu, signalizace a dlaždice na displeji. Světlo = relé Waveshare
// (svítí od zadání kódu do doběhu po poslední relaci), hudba venku = výstup z audio.outputs (jen režim multi,
// hraje při jakémkoli kódu) + volitelné enable relé zesilovače. Stejná pravidla a texty jako validate_outdoor()
// / validate_audio() v jednotce (BranchRpiOutdoorHelpers.js). Uložení → onSave({ outdoor, audio }): `outdoor`
// kanonický tvar (null = smazat klíč), `audio` = hardware.audio bez legacy kanálu `channels.outdoor`.

const HINT = 'Zóna 9 v šabloně Brno: prostor před displejem. Světlo svítí od zadání kódu do doběhu po poslední relaci, '
  + 'hudba venku hraje při jakémkoli kódu (jen režim multi). Bez zámku, kontaktu a signalizace — na displeji se neukazuje.'
const MSG_COLOR = { red: '#dc2626', amber: '#b45309', green: '#1a8a18' }
// V režimu selector jsou audio pole vypnutá (`disabled` — ani klávesnicí; jednotka: kanál venek v selectoru = upozornění,
// hudba venku nehraje). Výstup venku pak nejde v bloku Venek změnit — editor audia proto v selectoru venek neblokuje.
const SELECTOR_TITLE = 'Hudba venku hraje jen v režimu multi (Audio → režim)'

function OutdoorHwEditor({ hardware, doors, disabled, onSave }) {
  const hw = useMemo(() => (hardware && typeof hardware === 'object' ? hardware : {}), [hardware])
  const [draft, setDraft] = useState(() => outdoorToDraft(hw))
  const [dirty, setDirty] = useState(false)
  const [msg, setMsg] = useState(null)   // { text, tone }
  useEffect(() => { if (!dirty) setDraft(outdoorToDraft(hw)) }, [hw, dirty])

  const devices = hw.devices && typeof hw.devices === 'object' ? hw.devices : {}
  const audio = hw.audio && typeof hw.audio === 'object' ? hw.audio : {}
  const multi = audioMode(audio) === 'multi'
  const saved = useMemo(() => outdoorOf(hw), [hw])
  const legacy = !!legacyOutdoorChannel(audio)
  const coils = useMemo(() => doorCoils(doors), [doors])

  const wsOptions = [{ value: '', label: '—' }, ...Object.entries(devices)
    .filter(([, d]) => d?.type === 'wav645' || d?.type === 'wav617').map(([n]) => ({ value: n, label: n }))]
  const devOpts = dev => (dev && !wsOptions.some(o => o.value === dev) ? [...wsOptions, { value: dev, label: `${dev} (?)` }] : wsOptions)
  const names = audioOutputNames(audio)
  const out = String(draft.audio.out ?? '').trim()
  const outOptions = [{ value: '', label: '— (venek nehraje)' }, ...names.map(n => ({ value: n, label: n }))]
  if (out && !names.includes(out)) outOptions.push({ value: out, label: `${out} (?)` })

  const zoneErr = draft.zone === '' ? null : outdoorZoneError(draft.zone, doors)
  const shareErr = outdoorShareError(draft.light, draft.audio)   // světlo × enable relé na téže cívce: blokuje v obou režimech
  const lightErr = outdoorLightError(draft.light, devices, coils) || shareErr
  // Enable relé vs. dveře jen v multi (v selectoru ho jednotka nevaliduje — viz outdoorRefs v helperech)
  const relayErr = (multi ? outdoorRelayError(draft.audio, devices, coils) : null) || shareErr
  const outErr = outdoorOutError(out, audio, doors)
  const afterBad = draft.light_after_close_s !== '' && !(parseInt(draft.light_after_close_s, 10) >= 0)

  function patch(fn) { setDraft(d => fn(d)); setDirty(true); setMsg(null) }
  const setRef = (key, part) => v => patch(d => ({ ...d, [key]: { ...d[key], [part]: v } }))

  async function save() {
    const { outdoor, error } = draftToOutdoor(draft, { devices, audio, doors })
    if (error) { setMsg({ text: error, tone: 'red' }); return }
    const ok = await onSave({ outdoor, audio: audioWithoutOutdoorChannel(hw.audio) })
    if (ok === false) { setMsg({ text: 'Uložení selhalo (viz chyba nahoře).', tone: 'red' }); return }
    setDirty(false)
    setMsg({ text: 'Uloženo — jednotka si mapu stáhne při dalším syncu.', tone: 'green' })
  }
  async function clear() {
    if (!window.confirm('Vymazat venek? Sekce outdoor (i starší kanál audio.channels.outdoor) se z HW mapy odstraní — venkovní světlo a hudba venku přestanou fungovat.')) return
    const ok = await onSave({ outdoor: null, audio: audioWithoutOutdoorChannel(hw.audio) })
    if (ok === false) { setMsg({ text: 'Uložení selhalo (viz chyba nahoře).', tone: 'red' }); return }
    setDraft(outdoorToDraft({})); setDirty(false)
    setMsg({ text: 'Vymazáno', tone: 'amber' })
  }

  const stateChip = saved.configured ? <Chip tone="green">nastaven</Chip>
    : saved.present ? <Chip tone="amber" title="Klíč outdoor existuje, ale nemá světlo ani audio výstup (jednotka hlásí upozornění)">bez světla i audia</Chip>
      : <Chip tone="gray">nenastaven</Chip>
  return (
    <div className="p-3 rounded-card" style={{ background: '#f8fcfa', border: `1px solid ${dirty ? '#f59e0b' : '#d4e8e0'}` }}>
      <div className="flex items-center justify-between gap-2 mb-2 flex-wrap">
        <div>
          <div className="text-[12px] font-extrabold uppercase" style={{ color: '#1a2e22' }}>Venek (zóna bez dveří) — venkovní osvětlení + hudba venku</div>
          <div className="text-[11px]" style={{ color: '#6b8c7a' }}>{HINT}</div>
        </div>
        <div className="flex gap-2">
          <Btn tone="red" onClick={clear} disabled={disabled || !(saved.present || legacy)} title="Odstraní sekci outdoor z HW mapy">Vymazat venek</Btn>
          <Btn tone="dark" onClick={save} disabled={disabled || !dirty}>{dirty ? 'Uložit venek' : 'Uloženo'}</Btn>
        </div>
      </div>
      <div className="flex items-end gap-2 flex-wrap p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <div className="flex flex-col gap-1 self-center" style={{ minWidth: 76 }}>
          <Chip tone="blue">Venek</Chip>
          {stateChip}
        </div>
        <Input label="Zóna" type="number" min={1} width={64} value={draft.zone} invalid={!!zoneErr || (draft.zone !== '' && !(parseInt(draft.zone, 10) >= 1))}
          title={zoneErr || 'Popisné číslo venku pro Velín, diagnostiku a příkazy — nesmí kolidovat s číslem zóny dveří'}
          onChange={v => patch(d => ({ ...d, zone: v }))} />
        <div className="flex flex-col gap-0.5" title={lightErr || 'Venkovní osvětlení: relé Waveshare (zařízení + coil; coil 0 = R1)'}>
          <Label>Světlo (relé)</Label>
          <div className="flex gap-1">
            <Select width={96} value={draft.light.dev} options={devOpts(draft.light.dev)} invalid={!!lightErr} onChange={setRef('light', 'dev')} />
            <Input width={54} type="number" min={0} value={draft.light.coil} placeholder="coil" invalid={!!lightErr} onChange={setRef('light', 'coil')} />
          </div>
        </div>
        <Select label="Audio výstup" width={150} value={out} options={outOptions} invalid={!!outErr} warn={multi && !out} disabled={!multi}
          title={outErr || (!multi ? SELECTOR_TITLE : out ? `Výstup ${out} (outdoor.audio.out) — hraje při jakémkoli kódu` : 'Bez výstupu hudba venku nehraje')}
          onChange={setRef('audio', 'out')} />
        <div className="flex flex-col gap-0.5" title={relayErr || (!multi ? SELECTOR_TITLE : 'Volitelné enable relé zesilovače venku (zařízení + coil)')}>
          <Label>Enable relé (volit.)</Label>
          <div className="flex gap-1">
            <Select width={96} value={draft.audio.dev} options={devOpts(draft.audio.dev)} invalid={!!relayErr} disabled={!multi} onChange={setRef('audio', 'dev')} />
            <Input width={54} type="number" min={0} value={draft.audio.coil} placeholder="coil" invalid={!!relayErr} disabled={!multi} onChange={setRef('audio', 'coil')} />
          </div>
        </div>
        {!multi && <Chip tone="amber" title="Přepněte Audio → režim na multi a nastavte výstup venku">hudba venku jen v multi</Chip>}
        <Input label="Doběh světla (s)" type="number" min={0} width={110} value={draft.light_after_close_s} placeholder="glob." invalid={afterBad}
          title="Za kolik sekund po poslední relaci zhasne venkovní světlo (prázdné = globální „Světlo po zavření“ v časování)"
          onChange={v => patch(d => ({ ...d, light_after_close_s: v }))} />
      </div>
      {legacy && (
        <div className="text-[11px] font-bold mt-1" style={{ color: '#b45309' }}>
          Výstup venku je uložen starším tvarem (audio.channels.outdoor) — uložením bloku Venek se převede na outdoor.audio.
        </div>
      )}
      {msg && <div className="text-[11px] font-bold mt-1" style={{ color: MSG_COLOR[msg.tone] || MSG_COLOR.green }}>{msg.text}</div>}
    </div>
  )
}

export { OutdoorHwEditor }
