import { useState, useRef, useEffect } from 'react'
import { Btn, Chip, Select, formatAge, ageSeconds, txt, isRpiDevice } from './BranchRpiUi'
import { ACCEPT, targetOptions, publicUrl, downloadUrl, formatBytes, libraryStatus, libraryChip, audioModeOf, targetLabel } from './branchMusicHelpers'

// ─── Hudba pobočky — dílčí komponenty (drop zóna, řádek skladby, stav jednotky) ──

const ONLINE_MS = 70 * 1000

// Drop zóna + výběr cíle před nahráním + progres po souborech
function MusicDropZone({ doors, target, onTarget, uploading, progress, onFiles }) {
  const [dragOver, setDragOver] = useState(false)
  const inputRef = useRef(null)
  function pick(fileList) {
    const files = Array.from(fileList || [])
    if (files.length) onFiles(files)
  }
  return (
    <div className="space-y-2">
      <div className="flex items-end gap-2 flex-wrap">
        <Select label="Cíl nahrávaných skladeb (lze změnit i po nahrání)" value={target} onChange={onTarget} options={targetOptions(doors)} width={320} />
        <span className="text-[11px] pb-1.5" style={{ color: '#6b8c7a' }}>Max 200 MB na soubor · více souborů najednou</span>
      </div>
      <div role="button" tabIndex={0}
        onClick={() => { if (!uploading) inputRef.current?.click() }}
        onKeyDown={e => { if (e.key === 'Enter' && !uploading) inputRef.current?.click() }}
        onDragOver={e => { e.preventDefault(); if (!uploading) setDragOver(true) }}
        onDragLeave={() => setDragOver(false)}
        onDrop={e => { e.preventDefault(); setDragOver(false); if (!uploading) pick(e.dataTransfer?.files) }}
        className="rounded-card text-center cursor-pointer"
        style={{ padding: '26px 14px', background: dragOver ? '#dcfce7' : '#f1faf7', border: `2px dashed ${dragOver ? '#22c55e' : '#74FB71'}`, opacity: uploading ? 0.7 : 1 }}>
        <div style={{ fontSize: 30, lineHeight: 1 }}>🎵</div>
        <div className="text-sm font-extrabold mt-1" style={{ color: '#1a2e22' }}>
          {uploading
            ? `Nahrávám ${progress.done + 1}/${progress.total} — ${progress.name || ''}`
            : 'Přetáhněte hudbu z PC (mp3, wav, flac, ogg, m4a…) nebo klikněte pro výběr'}
        </div>
        <div className="text-xs mt-0.5" style={{ color: '#6b8f7b' }}>
          Nahraje se do cíle „{targetLabel(target, doors)}“ — jakýkoli formát, který přehraje mpv/ffmpeg, bez překódování
        </div>
        <input ref={inputRef} type="file" accept={ACCEPT} multiple style={{ display: 'none' }}
          onChange={e => { pick(e.target.files); e.target.value = '' }} />
      </div>
    </div>
  )
}

// Jeden řádek skladby: přehrávač, název (inline přejmenování), pořadí, aktivní, cíl, stažení, smazání
function TrackRow({ track, doors, index, count, busy, onMove, onRename, onToggle, onTarget, onDelete }) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(track.title || '')
  useEffect(() => { if (!editing) setDraft(track.title || '') }, [track.title, editing])
  const url = publicUrl(track.file_path)
  const fileName = `${track.title || 'skladba'}.${track.ext || 'bin'}`
  function commit() {
    setEditing(false)
    const t = draft.trim()
    if (t && t !== track.title) onRename(t)
  }
  return (
    <div className="flex items-center gap-2 p-2 rounded-lg flex-wrap" style={{ background: track.is_active ? '#f8fcfa' : '#f3f4f6', border: '1px solid #d4e8e0', opacity: track.is_active ? 1 : 0.7 }}>
      <div className="flex flex-col">
        <Btn small tone="gray" disabled={busy || index === 0} onClick={() => onMove(-1)} title="Posunout výš" style={{ padding: '1px 6px' }}>▲</Btn>
        <Btn small tone="gray" disabled={busy || index >= count - 1} onClick={() => onMove(1)} title="Posunout níž" style={{ padding: '1px 6px' }}>▼</Btn>
      </div>
      <span className="text-[11px] font-bold" style={{ color: '#6b8c7a', minWidth: 20 }}>{index + 1}.</span>
      {editing ? (
        <input autoFocus value={draft} onChange={e => setDraft(e.target.value)} onBlur={commit}
          onKeyDown={e => { if (e.key === 'Enter') commit(); if (e.key === 'Escape') { setEditing(false); setDraft(track.title || '') } }}
          className="rounded-btn text-sm outline-none" style={{ padding: '4px 8px', background: '#fff', border: '1px solid #74FB71', minWidth: 200 }} />
      ) : (
        <button type="button" onClick={() => setEditing(true)} title="Kliknutím přejmenujete" className="text-sm font-bold text-left cursor-pointer border-none"
          style={{ background: 'none', color: '#0f1a14', padding: 0, minWidth: 120 }}>{txt(track.title)}</button>
      )}
      <span className="text-[11px]" style={{ color: '#6b8c7a' }}>{txt(track.ext).toUpperCase()} · {formatBytes(track.size_bytes)}</span>
      {!track.is_active && <Chip tone="amber">Vypnuto</Chip>}
      <audio controls preload="none" src={url} style={{ height: 30, maxWidth: 240 }} />
      <div className="ml-auto flex items-center gap-1 flex-wrap">
        <select value={track.target} onChange={e => onTarget(e.target.value)} disabled={busy} title="Přesunout do jiného cíle"
          className="rounded-btn text-[11px] outline-none" style={{ padding: '4px 6px', background: '#fff', border: '1px solid #d4e8e0', maxWidth: 170 }}>
          {targetOptions(doors).map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
          {!targetOptions(doors).some(o => o.value === track.target) && <option value={track.target}>{targetLabel(track.target, doors)}</option>}
        </select>
        <Btn small tone={track.is_active ? 'amber' : 'green'} disabled={busy} onClick={onToggle}>{track.is_active ? 'Vypnout' : 'Zapnout'}</Btn>
        <a href={downloadUrl(track.file_path, fileName)} download={fileName} target="_blank" rel="noreferrer"
          className="rounded-btn text-[11px] font-bold" style={{ padding: '4px 8px', background: '#dbeafe', color: '#2563eb', textDecoration: 'none' }}>Stáhnout</a>
        <Btn small tone="red" disabled={busy} onClick={onDelete}>Smazat</Btn>
      </div>
    </div>
  )
}

// Stav knihovny na řídicích jednotkách (kiosk_devices.status.audio.library) + „Znovu synchronizovat“
function UnitSyncStatus({ devices, now, onCommand }) {
  const [sent, setSent] = useState(null)
  const rpis = (Array.isArray(devices) ? devices : []).filter(isRpiDevice)
  if (rpis.length === 0) return null
  async function resync(dev) {
    const ok = await onCommand(dev, 'sync_config', {})
    if (ok) setSent({ id: dev.id, ts: Date.now() })
  }
  return (
    <div className="space-y-1">
      {rpis.map(dev => {
        const online = !!(dev.last_seen_at && (now - new Date(dev.last_seen_at).getTime()) < ONLINE_MS)
        const lib = libraryStatus(dev)
        const chip = libraryChip(lib)
        const mode = audioModeOf(dev)
        const targets = lib ? Object.entries(lib.targets).map(([k, v]) => `${k}: ${txt(v)}`).join(' · ') : ''
        return (
          <div key={dev.id} className="flex items-center gap-2 flex-wrap p-2 rounded-lg text-[12px]" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <span style={{ width: 8, height: 8, borderRadius: 999, background: online ? '#1a8a18' : '#dc2626', display: 'inline-block' }} />
            <span className="font-bold">{txt(dev.name || 'Raspberry')}</span>
            <Chip tone={chip.tone} title={targets || 'Jednotka zatím nehlásí stav knihovny (starší software nebo bez heartbeatu)'}>Jednotka: {chip.text}</Chip>
            {mode && <Chip tone={mode === 'multi' ? 'blue' : 'gray'} title={mode === 'multi' ? 'Každý kanál má vlastní zvukový výstup' : 'Jeden zesilovač + reléový přepínač — hraje vždy jen jedna kóje, venek nefunguje'}>režim {mode}</Chip>}
            {lib?.last_sync_at && <span style={{ color: '#6b8c7a' }}>sync {formatAge(ageSeconds(lib.last_sync_at, now))}</span>}
            <span className="ml-auto flex items-center gap-2">
              {sent?.id === dev.id && (now - sent.ts) < 60000 && <span style={{ color: '#1a8a18' }}>Odesláno</span>}
              <Btn small tone="blue" disabled={!online} title={online ? 'Jednotka si stáhne nové skladby a smaže odebrané' : 'Jednotka není online — synchronizuje se sama po připojení'}
                onClick={() => resync(dev)}>Znovu synchronizovat</Btn>
            </span>
          </div>
        )
      })}
    </div>
  )
}

export { MusicDropZone, TrackRow, UnitSyncStatus }
