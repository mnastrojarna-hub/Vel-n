import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugError } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import MotoActionModal from '../../components/fleet/MotoActionModal'
import ScheduleServiceModal from './ScheduleServiceModal'
import ServiceLogCard from './ServiceLogCard'
import { Section, MotoCard, UnavailableMotoCard, NoLogCard } from './ActiveServiceCards'

const TIME_FILTERS = [
  { key: 'today', label: 'Dnes' },
  { key: 'tomorrow', label: 'Zítra' },
  { key: 'week', label: '7 dní' },
  { key: 'all', label: 'Vše' },
]

function toDateStr(d) { return d.toISOString().slice(0, 10) }

export default function ActiveServiceTab({ onRefresh }) {
  const [motos, setMotos] = useState([])
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState({})
  const [actionMoto, setActionMoto] = useState(null)
  const [showPicker, setShowPicker] = useState(false)
  const [showSchedule, setShowSchedule] = useState(false)
  const [allMotos, setAllMotos] = useState([])
  const [pickerSearch, setPickerSearch] = useState('')
  const [timeFilter, setTimeFilter] = useState(() => {
    try { return localStorage.getItem('velin_activeservice_filter') || 'all' } catch { return 'all' }
  })

  useEffect(() => {
    try { localStorage.setItem('velin_activeservice_filter', timeFilter) } catch {}
  }, [timeFilter])

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const [motosRes, unavailableRes, logsRes] = await debugAction('activeService.load', 'ActiveServiceTab', () => Promise.all([
        // Motorcycles in maintenance
        supabase.from('motorcycles').select('*, branches(name, type)').eq('status', 'maintenance').order('model'),
        // Motorcycles temporarily unavailable (may have open service logs)
        supabase.from('motorcycles').select('*, branches(name, type)').eq('status', 'unavailable').order('model'),
        // All open maintenance logs
        supabase.from('maintenance_log').select('*, motorcycles!moto_id(id, model, spz, status, branch_id, mileage, tracking_unit, unavailable_reason, unavailable_until, branches(name, type))').is('completed_date', null).order('created_at', { ascending: false }),
      ]))
      const maintenanceMotos = motosRes.data || []
      const unavailableMotos = unavailableRes.data || []
      const openLogs = logsRes.data || []

      const maintenanceIds = new Set(maintenanceMotos.map(m => m.id))

      // Unavailable motos WITH open service logs → show in active service (temporarily removed from service)
      const unavailableWithLogs = []
      const unavailableIds = new Set()
      for (const l of openLogs) {
        if (l.moto_id && !maintenanceIds.has(l.moto_id) && l.motorcycles?.status === 'unavailable') {
          if (!unavailableIds.has(l.moto_id)) {
            unavailableIds.add(l.moto_id)
            const fullMoto = unavailableMotos.find(m => m.id === l.moto_id) || l.motorcycles
            unavailableWithLogs.push({ ...fullMoto, _unavailable: true })
          }
        }
      }

      // Stuck motos: open logs but moto is active (shouldn't happen but handle gracefully)
      const stuckMotoMap = {}
      for (const l of openLogs) {
        if (l.moto_id && !maintenanceIds.has(l.moto_id) && !unavailableIds.has(l.moto_id) && l.motorcycles) {
          stuckMotoMap[l.moto_id] = { ...l.motorcycles, _stuck: true }
        }
      }
      const stuckMotos = Object.values(stuckMotoMap)

      setMotos([...maintenanceMotos, ...unavailableWithLogs, ...stuckMotos])
      setLogs(openLogs)
    } catch (e) { debugError('activeService.load', 'ActiveServiceTab', e) }
    finally { setLoading(false) }
  }

  async function openPicker() {
    setShowPicker(true); setPickerSearch('')
    const { data } = await supabase.from('motorcycles').select('id, model, spz, status, branch_id, mileage, branches(name, type)').order('model')
    setAllMotos(data || [])
  }

  function selectMoto(m) { setShowPicker(false); setActionMoto(m) }
  const filtered = allMotos.filter(m => !pickerSearch || m.model?.toLowerCase().includes(pickerSearch.toLowerCase()) || m.spz?.toLowerCase().includes(pickerSearch.toLowerCase()))
  const statusLabel = { active: 'Aktivní', maintenance: 'V servisu', unavailable: 'Dočasně vyřazena', retired: 'Trvale vyřazena' }
  const statusColor = { active: '#1a8a18', maintenance: '#b45309', unavailable: '#7c3aed', retired: '#6b7280' }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  // Group logs by moto
  const logsByMoto = {}
  logs.forEach(l => { if (!logsByMoto[l.moto_id]) logsByMoto[l.moto_id] = []; logsByMoto[l.moto_id].push(l) })

  // Categorize motos
  const today = toDateStr(new Date())
  const tomorrow = toDateStr(new Date(Date.now() + 86400000))
  const weekEnd = toDateStr(new Date(Date.now() + 7 * 86400000))

  const urgentMotos = []
  const todayMotos = []
  const inProgressMotos = []
  const unavailableMotos = []
  const upcomingMotos = []

  for (const m of motos) {
    const mLogs = logsByMoto[m.id] || []
    const hasUrgent = mLogs.some(l => l.is_urgent)
    const isUnavailable = m._unavailable || m.status === 'unavailable'

    if (isUnavailable && mLogs.length > 0) {
      unavailableMotos.push(m)
      continue
    }

    if (hasUrgent) {
      urgentMotos.push(m)
      continue
    }

    // Check if any log is for today
    const hasTodayLog = mLogs.some(l => {
      const sDate = l.service_date || l.created_at?.slice(0, 10)
      return sDate === today
    })
    // Check if all logs are future (upcoming)
    const allFuture = mLogs.length > 0 && mLogs.every(l => {
      const sDate = l.service_date || l.created_at?.slice(0, 10)
      return sDate > today
    })

    if (allFuture) {
      upcomingMotos.push(m)
    } else if (hasTodayLog) {
      todayMotos.push(m)
    } else {
      // In progress — started before today, not completed
      inProgressMotos.push(m)
    }
  }

  // Apply time filter to upcoming section
  function filterUpcoming(motoList) {
    if (timeFilter === 'all') return motoList
    return motoList.filter(m => {
      const mLogs = logsByMoto[m.id] || []
      return mLogs.some(l => {
        const sDate = l.service_date || l.created_at?.slice(0, 10)
        if (timeFilter === 'today') return sDate <= today
        if (timeFilter === 'tomorrow') return sDate <= tomorrow
        if (timeFilter === 'week') return sDate <= weekEnd
        return true
      })
    })
  }

  const filteredUpcoming = filterUpcoming(upcomingMotos)

  // Split upcoming into tomorrow vs later
  const tomorrowMotos = filteredUpcoming.filter(m => {
    const mLogs = logsByMoto[m.id] || []
    return mLogs.some(l => (l.service_date || l.created_at?.slice(0, 10)) === tomorrow)
  })
  const laterMotos = filteredUpcoming.filter(m => {
    const mLogs = logsByMoto[m.id] || []
    return !mLogs.some(l => (l.service_date || l.created_at?.slice(0, 10)) === tomorrow)
  })

  const totalActive = urgentMotos.length + todayMotos.length + inProgressMotos.length + unavailableMotos.length

  return (
    <div className="space-y-4">
      {/* Top bar */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>
          {totalActive} aktivní{totalActive !== 1 ? 'ch' : ''} servisů
          {filteredUpcoming.length > 0 && <span style={{ color: '#6b7280' }}> + {filteredUpcoming.length} nadcházející{filteredUpcoming.length !== 1 ? 'ch' : ''}</span>}
        </div>
        <div className="flex gap-2">
          <button onClick={() => setShowSchedule(true)} className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
            style={{ padding: '8px 16px', background: '#fef3c7', color: '#b45309', border: 'none' }}>
            Naplánovat servis
          </button>
          <button onClick={openPicker} className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
            style={{ padding: '8px 16px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
            Správa motorky
          </button>
        </div>
      </div>

      {/* Time filter */}
      <div className="flex items-center gap-1 flex-wrap">
        <span className="text-xs font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>Zobrazit:</span>
        {TIME_FILTERS.map(f => (
          <button key={f.key} onClick={() => setTimeFilter(f.key)}
            className="rounded-btn text-sm font-bold cursor-pointer"
            style={{
              padding: '5px 14px', border: 'none',
              background: timeFilter === f.key ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              boxShadow: timeFilter === f.key ? '0 2px 8px rgba(116,251,113,.3)' : 'none',
            }}>
            {f.label}
          </button>
        ))}
      </div>

      {/* Moto picker overlay */}
      {showPicker && (
        <Card>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Vyberte motorku</div>
          <input value={pickerSearch} onChange={e => setPickerSearch(e.target.value)} placeholder="Hledat model / SPZ…"
            className="w-full rounded-btn text-sm outline-none mb-3" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
          <div style={{ maxHeight: 300, overflowY: 'auto' }} className="space-y-1">
            {filtered.map(m => (
              <div key={m.id} onClick={() => selectMoto(m)} className="flex items-center gap-3 p-2 rounded cursor-pointer" style={{ background: '#f9fafb', border: '1px solid #e5e7eb' }}>
                <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
                <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
                <span className="text-xs font-bold" style={{ color: statusColor[m.status] || '#6b7280' }}>{statusLabel[m.status] || m.status}</span>
                <span className="text-xs ml-auto" style={{ color: '#6b7280' }}>{m.branches?.name || 'Bez pobočky'}</span>
              </div>
            ))}
            {filtered.length === 0 && <div className="text-sm py-4 text-center" style={{ color: '#6b7280' }}>Žádné motorky</div>}
          </div>
          <div className="flex justify-end mt-2"><Button onClick={() => setShowPicker(false)}>Zavřít</Button></div>
        </Card>
      )}

      {/* Empty state */}
      {motos.length === 0 && logs.length === 0 && (
        <Card><div className="text-center py-8"><div className="text-sm font-bold" style={{ color: '#1a8a18' }}>Žádné motorky aktuálně v servisu</div></div></Card>
      )}

      {/* ═══ URGENT ═══ */}
      {urgentMotos.length > 0 && (
        <Section title="Urgentní" color="#dc2626" bg="#fef2f2" border="#fca5a5" count={urgentMotos.length}>
          {urgentMotos.map(m => (
            <MotoCard key={m.id} m={m} logs={logsByMoto[m.id] || []} expanded={expanded} setExpanded={setExpanded}
              onAction={setActionMoto} onReload={() => { load(); onRefresh?.() }} />
          ))}
        </Section>
      )}

      {/* ═══ DNES ═══ */}
      {todayMotos.length > 0 && (
        <Section title="Dnes" color="#b45309" bg="#fffbeb" border="#fde68a" count={todayMotos.length}>
          {todayMotos.map(m => (
            <MotoCard key={m.id} m={m} logs={logsByMoto[m.id] || []} expanded={expanded} setExpanded={setExpanded}
              onAction={setActionMoto} onReload={() => { load(); onRefresh?.() }} />
          ))}
        </Section>
      )}

      {/* ═══ PROBÍHAJÍCÍ ═══ */}
      {inProgressMotos.length > 0 && (
        <Section title="Probíhající" color="#2563eb" bg="#eff6ff" border="#bfdbfe" count={inProgressMotos.length}
          subtitle="Zahájené dříve — nedokončené, čekají na díly, probíhají">
          {inProgressMotos.map(m => (
            <MotoCard key={m.id} m={m} logs={logsByMoto[m.id] || []} expanded={expanded} setExpanded={setExpanded}
              onAction={setActionMoto} onReload={() => { load(); onRefresh?.() }} />
          ))}
        </Section>
      )}

      {/* ═══ DOČASNĚ VYŘAZENÉ (ze servisu) ═══ */}
      {unavailableMotos.length > 0 && (
        <Section title="Dočasně vyřazené" color="#7c3aed" bg="#f5f3ff" border="#c4b5fd" count={unavailableMotos.length}
          subtitle="Motorky dočasně mimo servis — servisní záznamy zachovány">
          {unavailableMotos.map(m => (
            <UnavailableMotoCard key={m.id} m={m} logs={logsByMoto[m.id] || []} expanded={expanded} setExpanded={setExpanded}
              onAction={setActionMoto} onReload={() => { load(); onRefresh?.() }} />
          ))}
        </Section>
      )}

      {/* ═══ SEPARATOR ═══ */}
      {filteredUpcoming.length > 0 && (urgentMotos.length > 0 || todayMotos.length > 0 || inProgressMotos.length > 0 || unavailableMotos.length > 0) && (
        <hr style={{ border: 'none', borderTop: '2px dashed #d4e8e0', margin: '16px 0' }} />
      )}

      {/* ═══ NADCHÁZEJÍCÍ — ZÍTRA ═══ */}
      {tomorrowMotos.length > 0 && (
        <Section title="Zítra" color="#059669" bg="#ecfdf5" border="#a7f3d0" count={tomorrowMotos.length}>
          {tomorrowMotos.map(m => (
            <MotoCard key={m.id} m={m} logs={logsByMoto[m.id] || []} expanded={expanded} setExpanded={setExpanded}
              onAction={setActionMoto} onReload={() => { load(); onRefresh?.() }} upcoming />
          ))}
        </Section>
      )}

      {/* ═══ NADCHÁZEJÍCÍ — POZDĚJI ═══ */}
      {laterMotos.length > 0 && (
        <Section title="Nadcházející" color="#6b7280" bg="#f9fafb" border="#e5e7eb" count={laterMotos.length}
          subtitle="Příští dny a týdny">
          {laterMotos.map(m => (
            <MotoCard key={m.id} m={m} logs={logsByMoto[m.id] || []} expanded={expanded} setExpanded={setExpanded}
              onAction={setActionMoto} onReload={() => { load(); onRefresh?.() }} upcoming />
          ))}
        </Section>
      )}

      <MotoActionModal open={!!actionMoto} moto={actionMoto} onClose={() => setActionMoto(null)} onUpdated={() => { load(); onRefresh?.(); setActionMoto(null) }} />
      <ScheduleServiceModal open={showSchedule} onClose={() => setShowSchedule(false)} onDone={() => { setShowSchedule(false); load(); onRefresh?.() }} />
    </div>
  )
}

/* Section, MotoCard, UnavailableMotoCard, NoLogCard extracted to ./ActiveServiceCards.jsx */

