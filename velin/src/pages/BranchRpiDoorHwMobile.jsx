import { Btn, Chip, doorKindLabel } from './BranchRpiUi'
import { ZONE_REFS, ZONE_TIMING_FIELDS, ZONE_MUSIC_OPTIONS, channelKey, channelName, channelRangeError, roleTypeError, audioMode, audioOutputNames } from './BranchRpiHardwareDefaults'

// ─── Mapování dveří → zóny: sbalený řádek dveří na TELEFONU (< 768 px) ────────────────────────
// Celý editor jedněch dveří má na telefonu ~700 px (role pod sebou) — 8 dveří by byla nekonečná stránka.
// Na telefonu je proto každý řádek sbalený do souhrnu (zóna, zapojené kanály, stav uložení/chyby) s tlačítkem
// „Upravit“, které rozbalí plný editor (BranchRpiDoorHw.jsx → DoorHwRow). Tablet a PC: vždy plný editor (beze změny).
// Souhrn čte stejný draft jako editor — nic neukládá sám, jen „Uložit“ = stejné onSave jako v editoru.

const MSG_COLOR = { red: '#dc2626', amber: '#b45309', green: '#1a8a18' }

// Zapojené kanály draftu → „Zámek wav617a R1 · Kontakt wav617a DI1 · …“ (indexy v draftu jsou od 0)
function channelsText(draft) {
  const parts = []
  for (const role of ZONE_REFS) {
    const ref = draft?.[role.key]
    const out = role.key === 'audio' ? String(ref?.out ?? '').trim() : ''
    const raw = ref?.[role.idx]
    const ch = ref?.dev && raw !== '' && raw != null ? `${ref.dev} ${channelName(role.kind, raw)}` : ''
    if (out || ch) parts.push(`${role.label} ${[out, ch].filter(Boolean).join(' + ')}`)
  }
  return parts.join(' · ')
}

// Pole, která plný editor (DoorHwFull / DoorAudioCell) zvýrazní červeně kvůli typu zařízení, rozsahu kanálu,
// neexistujícímu nebo sdílenému audio výstupu či neplatné hodnotě — souhrn je musí ukázat i sbalený
function invalidFields(draft, devices, audio, dupOuts) {
  const zoneNo = parseInt(draft.zone, 10)
  const zn = Number.isFinite(zoneNo) ? zoneNo : '?'
  if (draft.zone !== '' && !(zoneNo >= 1)) return true
  const roleBad = ZONE_REFS.some(role => {
    const ref = draft[role.key] || {}
    if (roleTypeError(zn, role, ref.dev, devices)) return true
    const idx = parseInt(ref[role.idx], 10)
    return role.key !== 'audio' && !!ref.dev && Number.isFinite(idx) && !!channelRangeError(zn, role, ref.dev, idx, devices)
  })
  const out = String(draft.audio?.out ?? '').trim()
  const outBad = audioMode(audio) === 'multi' && !!out && (dupOuts.has(out) || !audioOutputNames(audio).includes(out))
  const closedBad = draft.closed_level !== '' && draft.closed_level !== '0' && draft.closed_level !== '1'
  const timingBad = ZONE_TIMING_FIELDS.some(f => { const v = String(draft.timings?.[f.key] ?? ''); return v !== '' && !(parseInt(v, 10) >= 0) })
  return roleBad || outBad || closedBad || timingBad
}

export function DoorHwSummary({ door, draft, configured, devices, audio, dupes, dupZones, dupOuts, busy, msg, onOpen, onSave }) {
  const isAcc = door.door_kind === 'accessories'
  const zoneNo = parseInt(draft.zone, 10)
  const dup = dupZones.has(zoneNo) || ZONE_REFS.some(role => { const k = channelKey(draft[role.key], role); return k && dupes.has(k) })
  const invalid = invalidFields(draft, devices, audio, dupOuts)
  const bad = dup || invalid
  const chText = channelsText(draft)
  const music = ZONE_MUSIC_OPTIONS.find(o => o.value === (draft.music_enabled ?? ''))
  const ownTimes = ZONE_TIMING_FIELDS.filter(f => String(draft.timings?.[f.key] ?? '') !== '').length
  return (
    <div className="p-2 rounded-lg" style={{ background: isAcc ? '#eff6ff' : '#f1faf7', border: `1px solid ${bad || (isAcc && !configured) ? '#fca5a5' : draft.dirty ? '#f59e0b' : '#d4e8e0'}` }}>
      <div className="flex items-center gap-1.5 flex-wrap">
        <Chip tone={isAcc ? 'blue' : 'green'}>{doorKindLabel(door)}</Chip>
        <Chip tone={configured ? 'gray' : isAcc ? 'red' : 'amber'}>{configured ? 'RPi mapa' : 'Bez mapy'}</Chip>
        <span className="text-[13px] font-extrabold" style={{ color: '#0f1a14' }}>zóna {draft.zone === '' ? '?' : draft.zone}</span>
        {draft.dirty && <Chip tone="amber">{draft.prefilled ? 'předvyplněno — neuloženo' : 'neuloženo'}</Chip>}
        {dup && <Chip tone="red">duplicitní kanál / zóna</Chip>}
        {invalid && <Chip tone="red">chyba v zapojení — Upravit</Chip>}
        <span className="ml-auto flex gap-2">
          {draft.dirty && <Btn tone="dark" disabled={busy} onClick={onSave}>Uložit</Btn>}
          <Btn tone="blue" onClick={onOpen}>Upravit ▾</Btn>
        </span>
      </div>
      <div className="text-[12px] mt-1" style={{ color: chText ? '#1a2e22' : '#b45309' }}>
        {chText || 'Žádný kanál — zámek a kontakt jsou povinné.'}
      </div>
      {(music?.value || ownTimes > 0 || draft.light_until_moto_code === '1' || draft.closed_level !== '') && (
        <div className="text-[12px] mt-0.5" style={{ color: '#6b8c7a' }}>
          {[music?.value ? `hudba: ${music.label.toLowerCase()}` : '', draft.light_until_moto_code === '1' ? 'světlo do kódu motorky' : '',
            ownTimes ? `vlastní časování (${ownTimes})` : '', draft.closed_level !== '' ? `zavřeno = ${draft.closed_level}` : ''].filter(Boolean).join(' · ')}
        </div>
      )}
      {isAcc && !configured && !draft.prefilled && (
        <div className="text-[12px] font-bold mt-1" style={{ color: '#dc2626' }}>Šatna nemá HW zónu — kód k výbavě na displeji nebude fungovat.</div>
      )}
      {msg && <div className="text-[12px] font-bold mt-1" style={{ color: MSG_COLOR[msg.tone] || MSG_COLOR.green }}>{msg.text}</div>}
    </div>
  )
}
