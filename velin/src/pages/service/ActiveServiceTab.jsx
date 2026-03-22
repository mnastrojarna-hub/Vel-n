import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import MotoActionModal from '../../components/fleet/MotoActionModal'
import ServiceLogCard from './ServiceLogCard'
import ServiceMotoActions from './ServiceMotoActions'

export default function ActiveServiceTab({ onRefresh }) {
  const [motos, setMotos] = useState([])
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState({})
  const [actionMoto, setActionMoto] = useState(null)
  const [actionPanel, setActionPanel] = useState(null) // motoId for action panel

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const [motosRes, logsRes] = await debugAction('activeService.load', 'ActiveServiceTab', () => Promise.all([
        supabase.from('motorcycles').select('*, branches(name, type)')
          .eq('status', 'maintenance').order('model'),
        supabase.from('maintenance_log').select('*, motorcycles!moto_id(model, spz)')
          .is('completed_date', null).order('created_at', { ascending: false }),
      ]))
      setMotos(motosRes.data || [])
      setLogs(logsRes.data || [])
    } catch (e) {
      debugError('activeService.load', 'ActiveServiceTab', e)
    } finally { setLoading(false) }
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (motos.length === 0 && logs.length === 0) return (
    <Card><div className="text-center py-8"><div className="text-sm font-bold" style={{ color: '#1a8a18' }}>Žádné motorky aktuálně v servisu</div></div></Card>
  )

  const logsByMoto = {}
  logs.forEach(l => { if (!logsByMoto[l.moto_id]) logsByMoto[l.moto_id] = []; logsByMoto[l.moto_id].push(l) })

  return (
    <div className="space-y-4">
      {motos.map(m => {
        const mLogs = logsByMoto[m.id] || []
        const isExp = expanded[m.id]
        const hasUrgent = mLogs.some(l => l.is_urgent)
        return (
          <Card key={m.id}>
            <div className="flex items-center gap-3 cursor-pointer select-none" onClick={() => setExpanded(e => ({ ...e, [m.id]: !e[m.id] }))}>
              <span style={{ fontSize: 14, fontWeight: 700, transition: 'transform .2s', transform: isExp ? 'rotate(90deg)' : 'rotate(0deg)', color: '#1a2e22' }}>▶</span>
              <div className="flex-1 flex items-center gap-2 flex-wrap">
                <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
                <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
                {m.branches?.name && <span className="text-sm" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
                {hasUrgent && <span className="text-xs font-bold px-2 py-0.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}
              </div>
              <StatusBadge status="maintenance" />
              {mLogs.length > 0 && <span className="text-sm font-bold" style={{ color: '#b45309' }}>{mLogs.length} záznam{mLogs.length > 1 ? 'y' : ''}</span>}
              <button onClick={e => { e.stopPropagation(); setActionPanel(actionPanel === m.id ? null : m.id) }}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 10px', background: '#fef3c7', color: '#b45309', border: 'none' }}>Akce</button>
              <button onClick={e => { e.stopPropagation(); setActionMoto(m) }}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Správa</button>
            </div>

            {/* Service Actions Panel (deactivate, retire, replace) */}
            {actionPanel === m.id && (
              <div className="mt-3">
                <ServiceMotoActions moto={m} logs={mLogs} onDone={() => { setActionPanel(null); load(); onRefresh?.() }} />
              </div>
            )}

            {isExp && (
              <div className="mt-4 space-y-3">
                {mLogs.length > 0 ? mLogs.map(l => (
                  <ServiceLogCard key={l.id} log={l} moto={m} onReload={() => { load(); onRefresh?.() }} />
                )) : (
                  <NoLogCard motoId={m.id} onReload={() => { load(); onRefresh?.() }} />
                )}
              </div>
            )}
          </Card>
        )
      })}
      <MotoActionModal open={!!actionMoto} moto={actionMoto} onClose={() => setActionMoto(null)} onUpdated={() => { load(); onRefresh?.(); setActionMoto(null) }} />
    </div>
  )
}

function NoLogCard({ motoId, onReload }) {
  const [desc, setDesc] = useState('')
  const [saving, setSaving] = useState(false)
  const [ending, setEnding] = useState(false)

  async function create() {
    if (!desc.trim()) return
    setSaving(true)
    await supabase.from('maintenance_log').insert({ moto_id: motoId, description: desc.trim(), service_type: 'repair', service_date: new Date().toISOString().slice(0, 10) })
    setSaving(false); onReload()
  }
  async function endDirect() {
    setEnding(true)
    await supabase.from('motorcycles').update({ status: 'active', last_service_date: new Date().toISOString().slice(0, 10) }).eq('id', motoId)
    await supabase.from('maintenance_log').update({ completed_date: new Date().toISOString().slice(0, 10), status: 'completed' }).eq('moto_id', motoId).is('completed_date', null)
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
