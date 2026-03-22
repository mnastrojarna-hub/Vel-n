import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugError } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import MotoActionModal from '../../components/fleet/MotoActionModal'
import ScheduleServiceModal from './ScheduleServiceModal'
import ServiceLogCard from './ServiceLogCard'
import ServiceMotoActions from './ServiceMotoActions'

export default function ActiveServiceTab({ onRefresh }) {
  const [motos, setMotos] = useState([])
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState({})
  const [actionMoto, setActionMoto] = useState(null) // for MotoActionModal
  const [actionPanel, setActionPanel] = useState(null)
  const [showPicker, setShowPicker] = useState(false) // top-level moto picker
  const [showSchedule, setShowSchedule] = useState(false) // schedule modal
  const [allMotos, setAllMotos] = useState([])
  const [pickerSearch, setPickerSearch] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const [motosRes, logsRes] = await debugAction('activeService.load', 'ActiveServiceTab', () => Promise.all([
        supabase.from('motorcycles').select('*, branches(name, type)').eq('status', 'maintenance').order('model'),
        supabase.from('maintenance_log').select('*, motorcycles!moto_id(id, model, spz, status, branch_id, mileage, branches(name, type))').is('completed_date', null).order('created_at', { ascending: false }),
      ]))
      const maintenanceMotos = motosRes.data || []
      const openLogs = logsRes.data || []

      // Find motos with open logs but NOT in maintenance status (stuck state)
      const maintenanceIds = new Set(maintenanceMotos.map(m => m.id))
      const stuckMotoMap = {}
      for (const l of openLogs) {
        if (l.moto_id && !maintenanceIds.has(l.moto_id) && l.motorcycles) {
          stuckMotoMap[l.moto_id] = { ...l.motorcycles, _stuck: true }
        }
      }
      const stuckMotos = Object.values(stuckMotoMap)

      setMotos([...maintenanceMotos, ...stuckMotos])
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
  const statusLabel = { active: 'Aktivní', maintenance: 'Servis', out_of_service: 'Mimo provoz', retired: 'Vyřazena' }
  const statusColor = { active: '#1a8a18', maintenance: '#b45309', out_of_service: '#7c3aed', retired: '#6b7280' }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  const logsByMoto = {}
  logs.forEach(l => { if (!logsByMoto[l.moto_id]) logsByMoto[l.moto_id] = []; logsByMoto[l.moto_id].push(l) })

  return (
    <div className="space-y-4">
      {/* Top bar with Správa button */}
      <div className="flex items-center justify-between">
        <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{motos.length} motorek v servisu</div>
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

      {motos.length === 0 && logs.length === 0 && (
        <Card><div className="text-center py-8"><div className="text-sm font-bold" style={{ color: '#1a8a18' }}>Žádné motorky aktuálně v servisu</div></div></Card>
      )}

      {motos.map(m => {
        const mLogs = logsByMoto[m.id] || []
        const isExp = expanded[m.id]
        const hasUrgent = mLogs.some(l => l.is_urgent)
        const isStuck = m._stuck
        return (
          <Card key={m.id} style={isStuck ? { border: '2px solid #dc2626' } : undefined}>
            <div className="flex items-center gap-3 cursor-pointer select-none" onClick={() => setExpanded(e => ({ ...e, [m.id]: !e[m.id] }))}>
              <span style={{ fontSize: 14, fontWeight: 700, transition: 'transform .2s', transform: isExp ? 'rotate(90deg)' : 'rotate(0deg)', color: '#1a2e22' }}>▶</span>
              <div className="flex-1 flex items-center gap-2 flex-wrap">
                <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
                <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
                {m.branches?.name && <span className="text-sm" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
                {hasUrgent && <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}
                {isStuck && <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#fef3c7', color: '#b45309' }}>Otevřený log — stav: {m.status}</span>}
              </div>
              <StatusBadge status={isStuck ? m.status : 'maintenance'} />
              {mLogs.length > 0 && <span className="text-sm font-bold" style={{ color: '#b45309' }}>{mLogs.length} záznam{mLogs.length > 1 ? 'y' : ''}</span>}
              <button onClick={e => { e.stopPropagation(); setActionPanel(actionPanel === m.id ? null : m.id) }}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 10px', background: '#fef3c7', color: '#b45309', border: 'none' }}>Akce</button>
              <button onClick={e => { e.stopPropagation(); setActionMoto(m) }}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Správa</button>
            </div>
            {actionPanel === m.id && (
              <div className="mt-3"><ServiceMotoActions moto={m} logs={mLogs} onDone={() => { setActionPanel(null); load(); onRefresh?.() }} /></div>
            )}
            {isExp && (
              <div className="mt-4 space-y-3">
                {mLogs.length > 0 ? mLogs.map(l => (
                  <ServiceLogCard key={l.id} log={l} moto={m} onReload={() => { load(); onRefresh?.() }} />
                )) : <NoLogCard motoId={m.id} onReload={() => { load(); onRefresh?.() }} />}
              </div>
            )}
          </Card>
        )
      })}
      <MotoActionModal open={!!actionMoto} moto={actionMoto} onClose={() => setActionMoto(null)} onUpdated={() => { load(); onRefresh?.(); setActionMoto(null) }} />
      <ScheduleServiceModal open={showSchedule} onClose={() => setShowSchedule(false)} onDone={() => { setShowSchedule(false); load(); onRefresh?.() }} />
    </div>
  )
}

function NoLogCard({ motoId, onReload }) {
  const [desc, setDesc] = useState('')
  const [saving, setSaving] = useState(false)
  const [ending, setEnding] = useState(false)

  async function create() {
    if (!desc.trim()) return; setSaving(true)
    await supabase.from('maintenance_log').insert({ moto_id: motoId, description: desc.trim(), service_type: 'repair', service_date: new Date().toISOString().slice(0, 10) })
    setSaving(false); onReload()
  }
  async function endDirect() {
    setEnding(true)
    const today = new Date().toISOString().slice(0, 10)
    await supabase.from('motorcycles').update({ status: 'active', last_service_date: today }).eq('id', motoId)
    await supabase.from('maintenance_log').update({ completed_date: today, status: 'completed' }).eq('moto_id', motoId).is('completed_date', null)
    setEnding(false); onReload()
  }

  return (
    <div className="p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
      <div className="text-sm font-bold mb-2" style={{ color: '#b45309' }}>Motorka v servisu bez záznamu.</div>
      <div className="flex gap-2 items-end">
        <textarea value={desc} onChange={e => setDesc(e.target.value)} placeholder="Popište závadu…"
          className="flex-1 rounded-btn text-sm outline-none" style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', minHeight: 40, resize: 'vertical' }} />
        <Button onClick={create} disabled={saving || !desc.trim()} style={{ fontSize: 13, padding: '6px 12px' }}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
        <Button green onClick={endDirect} disabled={ending} style={{ fontSize: 13, padding: '6px 12px' }}>{ending ? 'Vracím…' : 'Ukončit servis'}</Button>
      </div>
    </div>
  )
}
