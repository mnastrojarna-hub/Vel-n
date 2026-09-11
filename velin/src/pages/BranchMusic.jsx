import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { EmptyState } from './BranchHelpers'
import { RpiSection, Btn, Chip, ErrorBoundary } from './BranchRpiUi'
import { MusicDropZone, TrackRow, UnitSyncStatus } from './BranchMusicParts'
import { fetchTracks, uploadTrack, updateTrack, deleteTrack, groupTracks, targetLabel, summaryFor, nextSortOrder, isAllowedFile, MAX_SIZE_BYTES } from './branchMusicHelpers'

// ─── Hudba pobočky — knihovna skladeb (branch_music_tracks + bucket branch-music) ──
// Kód kóje → hudba kóje; kód šatny → hudba šatny; venek hraje při jakémkoli kódu; cíl bez vlastních skladeb hraje společnou (all).
// Jednotka si soubory stáhne sama (kiosk_sync_config.music) — stav v kiosk_devices.status.audio.library.

const HINT = 'Zadání kódu kóje spustí hudbu dané kóje, kód šatny hudbu šatny, venek hraje při zadání jakéhokoli kódu. Cíl bez vlastních skladeb '
  + 'hraje společnou hudbu. Formát libovolný (mp3, wav, flac, ogg, m4a, aac, wma, aiff…) — nic se nepřekódovává. Nezávislé kanály vyžadují režim '
  + '„multi“ se samostatnými zvukovými výstupy v bloku „Řídicí jednotka (Raspberry) — hardware“ → Audio; v režimu „selector“ hraje vždy jen jedna kóje a venek nefunguje.'

function BranchMusicBlock(props) {
  return (
    <ErrorBoundary title="Hudba pobočky">
      <BranchMusicInner {...props} />
    </ErrorBoundary>
  )
}

function BranchMusicInner({ branchId, doors, devices, now, onCommand }) {
  const [tracks, setTracks] = useState([])
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState(null)
  const [notes, setNotes] = useState([])        // chyby jednotlivých souborů při nahrávání
  const [busy, setBusy] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState({ done: 0, total: 0, name: '' })
  const [target, setTarget] = useState('all')

  // keepError=true: po neúspěšné operaci znovu načíst seznam, ale hlášku chyby nesmazat (onClick předává event → ignorovat)
  const load = useCallback(async (keepError) => {
    try {
      setTracks(await fetchTracks(branchId))
      if (keepError !== true) setError(null)
    } catch (e) {
      setError(`Knihovnu hudby nelze načíst: ${e.message} (tabulka branch_music_tracks nemusí být ještě nasazená)`)
    } finally { setLoaded(true) }
  }, [branchId])
  useEffect(() => { load() }, [load])

  // Cíl 'door:<id>' smazaných dveří by ve výběru neexistoval — vrátit na společnou
  useEffect(() => {
    if (target.startsWith('door:') && !(doors || []).some(d => `door:${d.id}` === target)) setTarget('all')
  }, [doors, target])

  async function run(fn) {
    setBusy(true)
    try { await fn(); setError(null) } catch (e) {
      await load(true)                                 // vrátit optimistickou změnu ze serveru…
      setError(e.message || String(e))                 // …a chybu nechat viditelnou
    } finally { setBusy(false) }
  }

  async function handleFiles(files) {
    const bad = files.filter(f => !isAllowedFile(f) || f.size > MAX_SIZE_BYTES)
      .map(f => `„${f.name}“ — ${!isAllowedFile(f) ? 'nepodporovaný formát' : 'větší než 200 MB'}`)
    const ok = files.filter(f => isAllowedFile(f) && f.size <= MAX_SIZE_BYTES)
    setNotes(bad)
    if (ok.length === 0) return
    setUploading(true)
    setProgress({ done: 0, total: ok.length, name: ok[0].name })
    const { data: { user } } = await supabase.auth.getUser().catch(() => ({ data: { user: null } }))
    let current = tracks
    const errs = [...bad]
    for (let i = 0; i < ok.length; i++) {
      const file = ok[i]
      setProgress({ done: i, total: ok.length, name: file.name })
      try {
        const row = await uploadTrack({ branchId, file, target, sortOrder: nextSortOrder(current, target), userId: user?.id })
        current = [...current, row]
        setTracks(current)
      } catch (e) {
        errs.push(e.message || String(e))
        setNotes([...errs])
      }
    }
    setUploading(false)
    setProgress({ done: ok.length, total: ok.length, name: '' })
    await load()
  }

  // Přesun ▲▼ uvnitř skupiny: přečíslovat celou skupinu podle nového pořadí (řeší i shodné sort_order)
  function move(group, index, dir) {
    const j = index + dir
    if (j < 0 || j >= group.items.length) return
    const items = group.items.slice()
    ;[items[index], items[j]] = [items[j], items[index]]
    const changes = items.map((t, i) => ({ t, i })).filter(({ t, i }) => Number(t.sort_order) !== i)
    setTracks(ts => ts.map(t => { const c = changes.find(x => x.t.id === t.id); return c ? { ...t, sort_order: c.i } : t }))
    run(() => Promise.all(changes.map(({ t, i }) => updateTrack(t.id, { sort_order: i }))))
  }
  function patch(track, p) {
    setTracks(ts => ts.map(t => t.id === track.id ? { ...t, ...p } : t))
    run(() => updateTrack(track.id, p))
  }
  function moveTarget(track, newTarget) {
    if (newTarget === track.target) return
    patch(track, { target: newTarget, sort_order: nextSortOrder(tracks, newTarget) })
  }
  function remove(track) {
    if (!window.confirm(`Smazat skladbu „${track.title}“? Smaže se i soubor v úložišti a jednotka ji při dalším syncu odstraní.`)) return
    setTracks(ts => ts.filter(t => t.id !== track.id))
    run(() => deleteTrack(track))
  }

  const groups = groupTracks(tracks, doors)
  const total = tracks.length
  return (
    <RpiSection title="Hudba pobočky" hint={HINT}
      action={<Btn tone="blue" onClick={() => load()} disabled={busy || uploading}>Obnovit</Btn>}>
      <div className="p-3 rounded-card space-y-3" style={{ background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
        {error && <div className="p-2 rounded-card text-[12px]" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>}
        <MusicDropZone doors={doors} target={target} onTarget={setTarget} uploading={uploading} progress={progress} onFiles={handleFiles} />
        {notes.length > 0 && (
          <div className="p-2 rounded-card text-[12px] space-y-0.5" style={{ background: '#fef3c7', color: '#b45309' }}>
            {notes.map((n, i) => <div key={i}>{n}</div>)}
            <button type="button" onClick={() => setNotes([])} className="text-[11px] font-bold cursor-pointer border-none" style={{ background: 'none', color: '#b45309', padding: 0 }}>Skrýt</button>
          </div>
        )}
        <UnitSyncStatus devices={devices} now={now} onCommand={onCommand} />

        {/* Souhrn: co v jednotlivých cílech hraje */}
        <div className="flex flex-wrap gap-1.5">
          {groups.filter(g => g.target !== 'all').map(g => {
            const s = summaryFor(g.target, groups)
            return <Chip key={g.target} tone={s.warn ? 'amber' : 'gray'} title={s.warn ? 'Tento cíl nemá vlastní ani společnou hudbu — po zadání kódu nic nehraje' : undefined}>{targetLabel(g.target, doors)}: {s.text}</Chip>
          })}
        </div>

        {!loaded ? <EmptyState text="Načítám knihovnu…" /> : total === 0 ? (
          <EmptyState text="Zatím žádná hudba. Přetáhněte soubory do pole výše — do společné hudby, nebo rovnou ke konkrétní kóji / šatně / venku." />
        ) : (
          <div className="space-y-3">
            {groups.filter(g => g.items.length > 0 || g.target === 'all').map(g => (
              <TargetGroup key={g.target} group={g} groups={groups} doors={doors} busy={busy || uploading}
                onMove={(i, dir) => move(g, i, dir)} onRename={(t, title) => patch(t, { title })}
                onToggle={t => patch(t, { is_active: !t.is_active })} onTarget={moveTarget} onDelete={remove} />
            ))}
          </div>
        )}
      </div>
    </RpiSection>
  )
}

function TargetGroup({ group, groups, doors, busy, onMove, onRename, onToggle, onTarget, onDelete }) {
  const s = summaryFor(group.target, groups)
  const unknown = group.target !== 'all' && group.target !== 'outdoor' && !(doors || []).some(d => `door:${d.id}` === group.target)
  return (
    <div>
      <div className="flex items-center gap-2 mb-1 flex-wrap">
        <span className="text-[12px] font-extrabold uppercase" style={{ color: '#1a2e22' }}>{targetLabel(group.target, doors)}</span>
        <Chip tone="gray">{group.items.length} skladeb</Chip>
        <span className="text-[11px]" style={{ color: s.warn ? '#b45309' : '#6b8c7a' }}>{s.text}</span>
        {unknown && <Chip tone="amber" title="Dveře tohoto cíle už neexistují — skladby přesuňte do jiného cíle">smazané dveře</Chip>}
      </div>
      {group.items.length === 0 ? (
        <EmptyState text="Bez skladeb" />
      ) : (
        <div className="space-y-1">
          {group.items.map((t, i) => (
            <TrackRow key={t.id} track={t} doors={doors} index={i} count={group.items.length} busy={busy}
              onMove={dir => onMove(i, dir)} onRename={title => onRename(t, title)} onToggle={() => onToggle(t)}
              onTarget={v => onTarget(t, v)} onDelete={() => onDelete(t)} />
          ))}
        </div>
      )}
    </div>
  )
}

export { BranchMusicBlock }
