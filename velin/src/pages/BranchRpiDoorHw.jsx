import { useState, useEffect, useMemo } from 'react'
import { Btn, Chip, Input, Select, Label } from './BranchRpiUi'
import { DoorAudioCell } from './BranchRpiAudioHw'
import {
  ZONE_REFS, audioMode, channelKey, findDuplicateChannels, findDuplicateZones, findDuplicateOutputs, outdoorOut, roleTypeError, draftToHw, hwToDraft,
} from './BranchRpiHardwareDefaults'

// ─── Editor `branch_doors.hw` — mapování zóny na kanály hardwaru ────────────
// Lokální drafty per dveře; uložení tlačítkem → onSaveDoor(id, { hw }).
// Stejná pravidla jako validate_hardware() v jednotce: duplicitní kanály mezi dveřmi (i uvnitř jedněch),
// duplicitní čísla zón a špatný typ zařízení pro roli se zvýrazní červeně a BLOKUJÍ uložení
// (jednotka by jinak celou mapu odmítla a Velín by ukazoval „Uloženo“).
// `audio` = hardware.audio: v režimu multi je role Audio výstup `audio.out` (musí existovat v audio.outputs,
// nesmí ho sdílet dvě zóny ani zóna + kanál venek); v režimu selector zůstává relé {dev, coil} beze změny
// a `out` se nekontroluje (jednotka ho v selectoru ignoruje) — zachová se pro připravené multi mapování.

function doorTitle(d) {
  return d.door_kind === 'accessories' ? 'Oblečení' : `Kóje #${d.box_number}`
}

function DoorHwEditor({ doors, devices, audio, busy, onSaveDoor }) {
  const [drafts, setDrafts] = useState({})
  const [msg, setMsg] = useState({})

  // Při změně dveří z DB obnov drafty (jen řádky bez rozpracovaných změn)
  useEffect(() => {
    setDrafts(prev => {
      const next = {}
      doors.forEach(d => { next[d.id] = prev[d.id]?.dirty ? prev[d.id] : { ...hwToDraft(d.hw, d.box_number), dirty: false } })
      return next
    })
  }, [doors])

  const dupes = useMemo(() => findDuplicateChannels(drafts), [drafts])
  const dupZones = useMemo(() => findDuplicateZones(drafts), [drafts])
  const multi = audioMode(audio) === 'multi'
  const dupOuts = useMemo(() => (multi ? findDuplicateOutputs(drafts, outdoorOut(audio)) : new Set()), [drafts, audio, multi])
  const deviceNames = Object.keys(devices || {})
  const devOptions = [{ value: '', label: '—' }, ...deviceNames.map(n => ({ value: n, label: n }))]

  function patch(id, fn) {
    setDrafts(prev => ({ ...prev, [id]: { ...fn(prev[id]), dirty: true } }))
  }

  async function save(d) {
    const draft = drafts[d.id]
    const zoneNo = parseInt(draft?.zone, 10)
    if (dupZones.has(zoneNo)) { setMsg(m => ({ ...m, [d.id]: { text: `Duplicitní čísla zón — zónu ${zoneNo} mají i jiné dveře.`, tone: 'red' } })); return }
    const { hw, error } = draftToHw(draft, devices, audio)
    if (error) { setMsg(m => ({ ...m, [d.id]: { text: error, tone: 'red' } })); return }
    if (hw.audio?.out && dupOuts.has(hw.audio.out)) { setMsg(m => ({ ...m, [d.id]: { text: `Audio výstup ${hw.audio.out} už používá jiná zóna nebo kanál venek.`, tone: 'red' } })); return }
    const usedChannel = ZONE_REFS.map(role => channelKey(draft[role.key], role)).find(k => k && dupes.has(k))
    if (usedChannel) { setMsg(m => ({ ...m, [d.id]: { text: `Kanál ${usedChannel} už používá jiná zóna/role.`, tone: 'red' } })); return }
    const ok = await onSaveDoor(d.id, { hw })
    if (ok === false) { setMsg(m => ({ ...m, [d.id]: { text: 'Uložení selhalo (viz chyba nahoře).', tone: 'red' } })); return }
    setDrafts(prev => ({ ...prev, [d.id]: { ...prev[d.id], dirty: false } }))
    setMsg(m => ({ ...m, [d.id]: { text: 'Uloženo — jednotka si mapu stáhne při dalším syncu.', tone: 'green' } }))
  }

  async function clear(d) {
    if (!window.confirm(`Vymazat hardwarovou mapu pro ${doorTitle(d)}? Řídicí jednotka zónu přestane obsluhovat.`)) return
    await onSaveDoor(d.id, { hw: {} })
    setDrafts(prev => ({ ...prev, [d.id]: { ...hwToDraft({}, d.box_number), dirty: false } }))
    setMsg(m => ({ ...m, [d.id]: { text: 'Vymazáno', tone: 'amber' } }))
  }

  if (doors.length === 0) return null

  return (
    <div className="space-y-1 max-h-96 overflow-y-auto">
      {doors.map(d => {
        const draft = drafts[d.id] || hwToDraft(d.hw, d.box_number)
        return (
          <DoorHwRow key={d.id} door={d} draft={draft} devices={devices} audio={audio} devOptions={devOptions} dupes={dupes} dupZones={dupZones} dupOuts={dupOuts}
            busy={busy} msg={msg[d.id]} onPatch={fn => patch(d.id, fn)} onSave={() => save(d)} onClear={() => clear(d)} />
        )
      })}
      {dupes.size > 0 && (
        <div className="text-[12px] font-bold p-2 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626' }}>
          Duplicitní kanály: {[...dupes].join(', ')} — každý kanál smí používat jen jedna zóna/role.
        </div>
      )}
      {dupZones.size > 0 && (
        <div className="text-[12px] font-bold p-2 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626' }}>
          Duplicitní čísla zón: {[...dupZones].join(', ')} — každé dveře musí mít vlastní číslo zóny (jednotka by celou mapu odmítla).
        </div>
      )}
      {dupOuts.size > 0 && (
        <div className="text-[12px] font-bold p-2 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626' }}>
          Sdílené audio výstupy: {[...dupOuts].join(', ')} — každý výstup smí používat jen jedna zóna nebo kanál venek.
        </div>
      )}
    </div>
  )
}

function DoorHwRow({ door, draft, devices, audio, devOptions, dupes, dupZones, dupOuts, busy, msg, onPatch, onSave, onClear }) {
  const isAcc = door.door_kind === 'accessories'
  const configured = !!(door.hw && typeof door.hw === 'object' && Object.keys(door.hw).length)
  const zoneNo = parseInt(draft.zone, 10)
  const zoneDup = dupZones.has(zoneNo)
  const zoneBad = draft.zone !== '' && !(zoneNo >= 1)
  return (
    <div className="p-2 rounded-lg" style={{ background: isAcc ? '#eff6ff' : '#f1faf7', border: `1px solid ${isAcc && !configured ? '#fca5a5' : draft.dirty ? '#f59e0b' : '#d4e8e0'}` }}>
      <div className="flex items-end gap-2 flex-wrap">
        <div className="flex flex-col gap-1 self-center" style={{ minWidth: 76 }}>
          <Chip tone={isAcc ? 'blue' : 'green'}>{doorTitle(door)}</Chip>
          <Chip tone={configured ? 'gray' : isAcc ? 'red' : 'amber'}>{configured ? 'RPi mapa' : 'Bez mapy'}</Chip>
        </div>
        <Input label="Zóna" type="number" min={1} width={64} value={draft.zone} invalid={zoneBad || zoneDup}
          title={zoneDup ? `Zónu ${zoneNo} mají i jiné dveře — čísla zón musí být unikátní` : 'Číslo zóny (kóje = číslo boxu; oblečení = volné číslo)'}
          onChange={v => onPatch(p => ({ ...p, zone: v }))} />
        {ZONE_REFS.map(role => {
          const ref = draft[role.key] || { dev: '', [role.idx]: '' }
          const key = channelKey(ref, role)
          const dup = key ? dupes.has(key) : false
          if (role.key === 'audio') {
            const out = String(ref.out ?? '').trim()
            return <DoorAudioCell key={role.key} zoneNo={Number.isFinite(zoneNo) ? zoneNo : '?'} audioRef={ref} audio={audio} devices={devices}
              devOptions={devOptions} dup={dup} dupOut={!!out && dupOuts.has(out)} onPatch={onPatch} />
          }
          const typeErr = roleTypeError(Number.isFinite(zoneNo) ? zoneNo : '?', role, ref.dev, devices)
          const title = dup ? 'Kanál už používá jiná zóna/role' : typeErr ? `${typeErr} Povolené: ${role.types.join('/')}.` : `${role.label}: zařízení + ${role.idx}`
          const unknownDev = !!(ref.dev && !devices?.[ref.dev])
          return (
            <div key={role.key} className="flex flex-col gap-0.5" title={title}>
              <Label>{role.label}{role.key === 'lock' || role.key === 'contact' ? ' *' : ''}</Label>
              <div className="flex gap-1">
                <Select width={96} value={ref.dev} options={unknownDev ? [...devOptions, { value: ref.dev, label: `${ref.dev} (?)` }] : devOptions}
                  invalid={dup || !!typeErr}
                  onChange={v => onPatch(p => ({ ...p, [role.key]: { ...p[role.key], dev: v } }))} />
                <Input width={54} type="number" min={0} value={ref[role.idx]} placeholder={role.idx}
                  invalid={dup || !!typeErr}
                  onChange={v => onPatch(p => ({ ...p, [role.key]: { ...p[role.key], [role.idx]: v } }))} />
              </div>
            </div>
          )
        })}
        <Input label="Zavřeno =" width={70} value={draft.closed_level} placeholder="glob."
          title="Úroveň vstupu při zavřených dveřích (prázdné = globální nastavení)"
          invalid={draft.closed_level !== '' && draft.closed_level !== '0' && draft.closed_level !== '1'}
          onChange={v => onPatch(p => ({ ...p, closed_level: v }))} />
        <div className="flex gap-1 self-center ml-auto">
          <Btn tone="dark" disabled={busy} onClick={onSave}>Uložit</Btn>
          <Btn tone="red" disabled={busy || !configured} onClick={onClear}>Vymazat</Btn>
        </div>
      </div>
      {isAcc && !configured && (
        <div className="text-[11px] font-bold mt-1" style={{ color: '#dc2626' }}>
          Skříň oblečení nemá HW zónu — kód k oblečení na displeji nebude fungovat (jednotka hlásí „relé pro tyto dveře není ve Velíně nastaveno“). Zadejte volné číslo zóny, zámek (WAV645) a kontakt (WAV617) a uložte.
        </div>
      )}
      {msg && <div className="text-[11px] font-bold mt-1" style={{ color: msg.tone === 'red' ? '#dc2626' : msg.tone === 'amber' ? '#b45309' : '#1a8a18' }}>{msg.text}</div>}
    </div>
  )
}

export { DoorHwEditor }
