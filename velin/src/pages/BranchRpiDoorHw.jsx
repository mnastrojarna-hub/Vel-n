import { useState, useEffect, useMemo } from 'react'
import { Btn, Chip, Input, Select, Label } from './BranchRpiUi'
import { ZONE_REFS, channelKey, findDuplicateChannels, draftToHw, hwToDraft } from './BranchRpiHardwareDefaults'

// ─── Editor `branch_doors.hw` — mapování zóny na kanály hardwaru ────────────
// Lokální drafty per dveře; uložení tlačítkem → onSaveDoor(id, { hw }).
// Duplicitní kanály mezi dveřmi (i uvnitř jedněch) se zvýrazní červeně.

function doorTitle(d) {
  return d.door_kind === 'accessories' ? 'Oblečení' : `Kóje #${d.box_number}`
}

function DoorHwEditor({ doors, devices, busy, onSaveDoor }) {
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
  const deviceNames = Object.keys(devices || {})
  const devOptions = [{ value: '', label: '—' }, ...deviceNames.map(n => ({ value: n, label: n }))]

  function patch(id, fn) {
    setDrafts(prev => ({ ...prev, [id]: { ...fn(prev[id]), dirty: true } }))
  }

  async function save(d) {
    const { hw, error } = draftToHw(drafts[d.id])
    if (error) { setMsg(m => ({ ...m, [d.id]: { text: error, tone: 'red' } })); return }
    await onSaveDoor(d.id, { hw })
    setDrafts(prev => ({ ...prev, [d.id]: { ...prev[d.id], dirty: false } }))
    setMsg(m => ({ ...m, [d.id]: { text: 'Uloženo', tone: 'green' } }))
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
          <DoorHwRow key={d.id} door={d} draft={draft} devices={devices} devOptions={devOptions} dupes={dupes}
            busy={busy} msg={msg[d.id]} onPatch={fn => patch(d.id, fn)} onSave={() => save(d)} onClear={() => clear(d)} />
        )
      })}
      {dupes.size > 0 && (
        <div className="text-[12px] font-bold p-2 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626' }}>
          Duplicitní kanály: {[...dupes].join(', ')} — každý kanál smí používat jen jedna zóna/role.
        </div>
      )}
    </div>
  )
}

function DoorHwRow({ door, draft, devices, devOptions, dupes, busy, msg, onPatch, onSave, onClear }) {
  const isAcc = door.door_kind === 'accessories'
  const configured = !!(door.hw && typeof door.hw === 'object' && Object.keys(door.hw).length)
  return (
    <div className="p-2 rounded-lg" style={{ background: isAcc ? '#eff6ff' : '#f1faf7', border: `1px solid ${draft.dirty ? '#f59e0b' : '#d4e8e0'}` }}>
      <div className="flex items-end gap-2 flex-wrap">
        <div className="flex flex-col gap-1 self-center" style={{ minWidth: 76 }}>
          <Chip tone={isAcc ? 'blue' : 'green'}>{doorTitle(door)}</Chip>
          <Chip tone={configured ? 'gray' : 'amber'}>{configured ? 'RPi mapa' : 'Bez mapy'}</Chip>
        </div>
        <Input label="Zóna" type="number" min={1} width={64} value={draft.zone}
          invalid={draft.zone !== '' && !(parseInt(draft.zone, 10) >= 1)}
          onChange={v => onPatch(p => ({ ...p, zone: v }))} />
        {ZONE_REFS.map(role => {
          const ref = draft[role.key] || { dev: '', [role.idx]: '' }
          const key = channelKey(ref, role)
          const dup = key ? dupes.has(key) : false
          const dev = devices?.[ref.dev]
          const wrongType = !!(ref.dev && dev && !role.types.includes(dev.type))
          const unknownDev = !!(ref.dev && !dev)
          const title = dup ? 'Kanál už používá jiná zóna/role' : wrongType ? `Role ${role.label} vyžaduje ${role.types.join('/')}` : unknownDev ? 'Neznámé zařízení (není v seznamu)' : `${role.label}: zařízení + ${role.idx}`
          return (
            <div key={role.key} className="flex flex-col gap-0.5" title={title}>
              <Label>{role.label}{role.key === 'lock' || role.key === 'contact' ? ' *' : ''}</Label>
              <div className="flex gap-1">
                <Select width={96} value={ref.dev} options={ref.dev && unknownDev ? [...devOptions, { value: ref.dev, label: `${ref.dev} (?)` }] : devOptions}
                  invalid={dup} warn={wrongType || unknownDev}
                  onChange={v => onPatch(p => ({ ...p, [role.key]: { ...p[role.key], dev: v } }))} />
                <Input width={54} type="number" min={0} value={ref[role.idx]} placeholder={role.idx}
                  invalid={dup} warn={wrongType || unknownDev}
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
      {msg && <div className="text-[11px] font-bold mt-1" style={{ color: msg.tone === 'red' ? '#dc2626' : msg.tone === 'amber' ? '#b45309' : '#1a8a18' }}>{msg.text}</div>}
    </div>
  )
}

export { DoorHwEditor }
