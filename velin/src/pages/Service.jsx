import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog, debugError } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Card from '../components/ui/Card'
import StatusBadge from '../components/ui/StatusBadge'
import Button from '../components/ui/Button'
import MotoActionModal from '../components/fleet/MotoActionModal'
import ServiceSchedule from './service/ServiceSchedule'
import ServiceLog from './service/ServiceLog'

const TABS = ['Aktivní v servisu', 'Servisní log', 'Plánované']

export default function Service() {
  const debugMode = useDebugMode()
  const [tab, setTab] = useState('Aktivní v servisu')
  const [stats, setStats] = useState({ planned: 0, inService: 0, avgCost: 0 })

  useEffect(() => { debugLog('page.mount', 'Service'); loadStats() }, [])

  async function loadStats() {
    try {
      const now = new Date()
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10)
      const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10)

      const [planned, inService, costs] = await debugAction('service.loadStats', 'Service', () => Promise.all([
        supabase.from('maintenance_schedules').select('id', { count: 'exact', head: true })
          .eq('active', true),
        supabase.from('motorcycles').select('id', { count: 'exact', head: true })
          .eq('status', 'maintenance'),
        supabase.from('maintenance_log').select('cost').not('cost', 'is', null),
      ]))

      const costArr = (costs.data || []).map(c => c.cost).filter(Boolean)
      const avg = costArr.length > 0 ? costArr.reduce((s, c) => s + c, 0) / costArr.length : 0

      setStats({
        planned: planned.count || 0,
        inService: inService.count || 0,
        avgCost: Math.round(avg),
      })
    } catch (err) {
      debugError('service.loadStats', 'Service', err)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ')

  return (
    <div>
      <div className="grid grid-cols-3 gap-4 mb-5">
        <Card>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Aktivní servisní plány</div>
          <div className="text-xl font-extrabold" style={{ color: '#0f1a14' }}>{fmt(stats.planned)}</div>
        </Card>
        <Card>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Motorky v servisu</div>
          <div className="text-xl font-extrabold" style={{ color: '#b45309' }}>{fmt(stats.inService)}</div>
        </Card>
        <Card>
          <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Ø náklady/servis</div>
          <div className="text-xl font-extrabold" style={{ color: '#0f1a14' }}>{fmt(stats.avgCost)} Kč</div>
        </Card>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Service</strong><br/>
        <div>planned (this month): {stats.planned}, inService: {stats.inService}, avgCost: {fmt(stats.avgCost)}</div>
        <div>tab: {tab}</div>
      </div>
      )}

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => { debugLog('tab.switch', 'Service', { tab: t }); setTab(t) }} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Aktivní v servisu' && <ActiveServiceTab onRefresh={loadStats} />}
      {tab === 'Servisní log' && <ServiceLog />}
      {tab === 'Plánované' && <ServiceSchedule />}
    </div>
  )
}

function ActiveServiceTab({ onRefresh }) {
  const [motos, setMotos] = useState([])
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState({})
  const [newDesc, setNewDesc] = useState({})
  const [savingDesc, setSavingDesc] = useState({})
  const [endingService, setEndingService] = useState({})
  const [actionMoto, setActionMoto] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const [motosRes, logsRes] = await debugAction('activeService.load', 'ActiveServiceTab', () => Promise.all([
        supabase.from('motorcycles').select('*, branches(name)')
          .eq('status', 'maintenance').order('model'),
        supabase.from('maintenance_log').select('*, motorcycles(model, spz)')
          .is('completed_date', null).order('created_at', { ascending: false }),
      ]))
      setMotos(motosRes.data || [])
      setLogs(logsRes.data || [])
    } catch (e) {
      debugError('activeService.load', 'ActiveServiceTab', e)
    } finally {
      setLoading(false)
    }
  }

  function toggleExpand(motoId) {
    setExpanded(e => ({ ...e, [motoId]: !e[motoId] }))
  }

  async function markCompleted(logEntry) {
    debugLog('service.markCompleted', 'ActiveServiceTab', { logId: logEntry.id, motoId: logEntry.moto_id })
    setEndingService(s => ({ ...s, [logEntry.id]: true }))
    try {
      const { error: logErr } = await supabase.from('maintenance_log').update({
        completed_date: new Date().toISOString().slice(0, 10),
      }).eq('id', logEntry.id)
      if (logErr) console.error('[markCompleted] log update failed:', logErr)

      if (logEntry.moto_id) {
        // Check if there are other uncompleted service logs for this moto
        const { data: otherActive } = await supabase.from('maintenance_log')
          .select('id').eq('moto_id', logEntry.moto_id).is('completed_date', null).neq('id', logEntry.id)
        if (!otherActive || otherActive.length === 0) {
          const { error: motoErr } = await supabase.from('motorcycles').update({
            status: 'active', last_service_date: new Date().toISOString().slice(0, 10),
          }).eq('id', logEntry.moto_id)
          if (motoErr) console.error('[markCompleted] moto update failed:', motoErr)
        }
      }
      const { data: { user } } = await supabase.auth.getUser()
      try {
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'service_completed',
          details: { log_id: logEntry.id, moto_id: logEntry.moto_id },
        })
      } catch {}
      await load()
      onRefresh?.()
    } catch (e) {
      debugError('service.markCompleted', 'ActiveServiceTab', e, { logId: logEntry.id })
    } finally {
      setEndingService(s => ({ ...s, [logEntry.id]: false }))
    }
  }

  async function endServiceDirect(moto) {
    debugLog('service.endDirect', 'ActiveServiceTab', { motoId: moto.id, model: moto.model })
    setEndingService(s => ({ ...s, [moto.id]: true }))
    try {
      const { error: motoErr } = await supabase.from('motorcycles').update({
        status: 'active', last_service_date: new Date().toISOString().slice(0, 10),
      }).eq('id', moto.id)
      if (motoErr) {
        console.error('[endServiceDirect] moto update failed:', motoErr)
        alert('Chyba při ukončení servisu: ' + motoErr.message)
        return
      }
      // Also complete any open maintenance_log entries for this moto
      await supabase.from('maintenance_log').update({
        completed_date: new Date().toISOString().slice(0, 10),
      }).eq('moto_id', moto.id).is('completed_date', null)

      const { data: { user } } = await supabase.auth.getUser()
      try {
        await supabase.from('admin_audit_log').insert({
          admin_id: user?.id, action: 'service_ended_direct',
          details: { moto_id: moto.id, model: moto.model },
        })
      } catch {}
      await load()
      onRefresh?.()
    } catch (e) {
      debugError('service.endDirect', 'ActiveServiceTab', e, { motoId: moto.id })
      alert('Chyba při ukončení servisu: ' + e.message)
    } finally {
      setEndingService(s => ({ ...s, [moto.id]: false }))
    }
  }

  async function saveDescription(motoId, logId) {
    const desc = newDesc[logId || motoId]
    if (!desc?.trim()) return
    setSavingDesc(s => ({ ...s, [logId || motoId]: true }))
    try {
      if (logId) {
        await supabase.from('maintenance_log').update({ description: desc.trim() }).eq('id', logId)
      } else {
        // Create a new maintenance_log entry for the moto
        await supabase.from('maintenance_log').insert({
          moto_id: motoId,
          description: desc.trim(),
          service_type: 'Neplánovaný servis',
        })
      }
      setNewDesc(d => ({ ...d, [logId || motoId]: '' }))
      load()
    } finally {
      setSavingDesc(s => ({ ...s, [logId || motoId]: false }))
    }
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  if (motos.length === 0 && logs.length === 0) {
    return (
      <Card>
        <div className="text-center py-8">
          <div className="text-sm font-bold" style={{ color: '#1a8a18' }}>Žádné motorky aktuálně v servisu</div>
        </div>
      </Card>
    )
  }

  const logsByMoto = {}
  logs.forEach(l => {
    const mid = l.moto_id
    if (!logsByMoto[mid]) logsByMoto[mid] = []
    logsByMoto[mid].push(l)
  })

  return (
    <div className="space-y-4">
      {motos.map(m => {
        const mLogs = logsByMoto[m.id] || []
        const isExpanded = expanded[m.id]
        return (
          <Card key={m.id}>
            <div
              className="flex items-center gap-4 cursor-pointer select-none"
              onClick={() => toggleExpand(m.id)}
            >
              <span style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700, transition: 'transform .2s', transform: isExpanded ? 'rotate(90deg)' : 'rotate(0deg)' }}>
                ▶
              </span>
              <div className="flex-1">
                <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
                <span className="font-mono text-sm ml-2" style={{ color: '#1a2e22' }}>{m.spz}</span>
                {m.branches?.name && <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
              </div>
              <StatusBadge status="maintenance" />
              {mLogs.length > 0 && (
                <span className="text-sm font-bold" style={{ color: '#b45309' }}>{mLogs.length} záznam{mLogs.length > 1 ? 'y' : ''}</span>
              )}
              <button
                onClick={e => { e.stopPropagation(); setActionMoto(m) }}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                Správa
              </button>
            </div>

            {isExpanded && (
              <div className="mt-4">
                {mLogs.length > 0 ? (
                  <div className="space-y-3">
                    {mLogs.map(l => (
                      <div key={l.id} className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                        <div className="flex items-start gap-3 mb-2 flex-wrap">
                          <div>
                            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ</div>
                            <div className="text-sm" style={{ color: '#1a2e22' }}>{l.service_type || l.type || '—'}</div>
                          </div>
                          <div>
                            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Do servisu</div>
                            <div className="text-sm" style={{ color: '#1a2e22' }}>{l.scheduled_date ? new Date(l.scheduled_date).toLocaleDateString('cs-CZ') : l.created_at ? new Date(l.created_at).toLocaleDateString('cs-CZ') : '—'}</div>
                          </div>
                          <div>
                            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Ze servisu</div>
                            <div className="text-sm" style={{ color: '#1a2e22' }}>{l.completed_date ? new Date(l.completed_date).toLocaleDateString('cs-CZ') : '—'}</div>
                          </div>
                          <div>
                            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Km</div>
                            <div className="text-sm font-mono" style={{ color: '#1a2e22' }}>{(l.mileage_at_service || l.km_at_service) ? (l.mileage_at_service || l.km_at_service).toLocaleString('cs-CZ') : '—'}</div>
                          </div>
                          <div>
                            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Technik</div>
                            <div className="text-sm" style={{ color: '#1a2e22' }}>{l.performed_by || '—'}</div>
                          </div>
                          <div className="flex-1 min-w-[200px]">
                            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servisní záznam</div>
                            <div className="text-sm" style={{ color: '#0f1a14', whiteSpace: 'pre-wrap' }}>{l.description || '—'}</div>
                          </div>
                        </div>
                        {/* Edit description */}
                        <div className="flex gap-2 items-end mt-2">
                          <div className="flex-1">
                            <textarea
                              value={newDesc[l.id] ?? l.description ?? ''}
                              onChange={e => setNewDesc(d => ({ ...d, [l.id]: e.target.value }))}
                              placeholder="Doplnit popis závady / detaily servisu…"
                              className="w-full rounded-btn text-sm outline-none"
                              style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', minHeight: 40, resize: 'vertical' }}
                            />
                          </div>
                          <Button
                            onClick={() => saveDescription(m.id, l.id)}
                            disabled={savingDesc[l.id]}
                            style={{ fontSize: 13, padding: '6px 12px' }}
                          >
                            {savingDesc[l.id] ? 'Ukládám…' : 'Uložit popis'}
                          </Button>
                          <Button
                            green
                            onClick={() => markCompleted(l)}
                            disabled={endingService[l.id]}
                            style={{ fontSize: 13, padding: '6px 12px' }}
                          >
                            {endingService[l.id] ? 'Dokončuji…' : 'Ukončit servis'}
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
                    <div className="text-sm font-bold mb-2" style={{ color: '#b45309' }}>
                      Motorka je ve stavu servis, ale nemá servisní záznam.
                    </div>
                    <div className="flex gap-2 items-end">
                      <div className="flex-1">
                        <textarea
                          value={newDesc[m.id] || ''}
                          onChange={e => setNewDesc(d => ({ ...d, [m.id]: e.target.value }))}
                          placeholder="Popište závadu / důvod servisu…"
                          className="w-full rounded-btn text-sm outline-none"
                          style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0', minHeight: 40, resize: 'vertical' }}
                        />
                      </div>
                      <Button
                        onClick={() => saveDescription(m.id, null)}
                        disabled={savingDesc[m.id] || !newDesc[m.id]?.trim()}
                        style={{ fontSize: 13, padding: '6px 12px' }}
                      >
                        {savingDesc[m.id] ? 'Ukládám…' : 'Vytvořit záznam'}
                      </Button>
                      <Button
                        green
                        onClick={() => endServiceDirect(m)}
                        disabled={endingService[m.id]}
                        style={{ fontSize: 13, padding: '6px 12px' }}
                      >
                        {endingService[m.id] ? 'Vracím…' : 'Ukončit servis'}
                      </Button>
                    </div>
                  </div>
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
