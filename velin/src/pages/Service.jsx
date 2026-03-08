import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import StatusBadge from '../components/ui/StatusBadge'
import Button from '../components/ui/Button'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import ServiceSchedule from './service/ServiceSchedule'
import ServiceLog from './service/ServiceLog'

const TABS = ['Aktivní v servisu', 'Servisní log', 'Plánované']

export default function Service() {
  const [tab, setTab] = useState('Aktivní v servisu')
  const [stats, setStats] = useState({ planned: 0, inService: 0, avgCost: 0 })

  useEffect(() => { loadStats() }, [])

  async function loadStats() {
    try {
      const now = new Date()
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10)
      const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10)

      const [planned, inService, costs] = await Promise.all([
        supabase.from('maintenance_schedules').select('id', { count: 'exact', head: true })
          .gte('next_date', monthStart).lte('next_date', monthEnd),
        supabase.from('motorcycles').select('id', { count: 'exact', head: true })
          .eq('status', 'maintenance'),
        supabase.from('maintenance_log').select('cost').not('cost', 'is', null),
      ])

      const costArr = (costs.data || []).map(c => c.cost).filter(Boolean)
      const avg = costArr.length > 0 ? costArr.reduce((s, c) => s + c, 0) / costArr.length : 0

      setStats({
        planned: planned.count || 0,
        inService: inService.count || 0,
        avgCost: Math.round(avg),
      })
    } catch {
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ')

  return (
    <div>
      <div className="grid grid-cols-3 gap-4 mb-5">
        <Card>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Plánované tento měsíc</div>
          <div className="text-xl font-extrabold" style={{ color: '#0f1a14' }}>{fmt(stats.planned)}</div>
        </Card>
        <Card>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Motorky v servisu</div>
          <div className="text-xl font-extrabold" style={{ color: '#b45309' }}>{fmt(stats.inService)}</div>
        </Card>
        <Card>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Ø náklady/servis</div>
          <div className="text-xl font-extrabold" style={{ color: '#0f1a14' }}>{fmt(stats.avgCost)} Kč</div>
        </Card>
      </div>

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
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

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const [motosRes, logsRes] = await Promise.all([
      supabase.from('motorcycles').select('*, branches(name)')
        .eq('status', 'maintenance').order('model'),
      supabase.from('maintenance_log').select('*, motorcycles(model, spz)')
        .eq('status', 'in_service').order('created_at', { ascending: false }),
    ])
    setMotos(motosRes.data || [])
    setLogs(logsRes.data || [])
    setLoading(false)
  }

  async function markCompleted(logEntry) {
    if (!window.confirm(`Dokončit servis pro ${logEntry.motorcycles?.model || 'motorku'}?`)) return
    await supabase.from('maintenance_log').update({
      status: 'completed',
      completed_date: new Date().toISOString().slice(0, 10),
    }).eq('id', logEntry.id)
    if (logEntry.moto_id) {
      const { data: otherActive } = await supabase.from('maintenance_log')
        .select('id').eq('moto_id', logEntry.moto_id).eq('status', 'in_service').neq('id', logEntry.id)
      if (!otherActive || otherActive.length === 0) {
        await supabase.from('motorcycles').update({
          status: 'active', last_service_date: new Date().toISOString().slice(0, 10),
        }).eq('id', logEntry.moto_id)
      }
    }
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id, action: 'service_completed',
      details: { log_id: logEntry.id, moto_id: logEntry.moto_id },
    })
    load()
    onRefresh?.()
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
        return (
          <Card key={m.id}>
            <div className="flex items-center gap-4 mb-3">
              <div>
                <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{m.model}</span>
                <span className="font-mono text-xs ml-2" style={{ color: '#8aab99' }}>{m.spz}</span>
              </div>
              <span className="text-xs" style={{ color: '#8aab99' }}>{m.branches?.name || ''}</span>
              <StatusBadge status="maintenance" />
            </div>
            {mLogs.length > 0 ? (
              <Table>
                <thead>
                  <TRow header>
                    <TH>Popis</TH><TH>Typ</TH><TH>Vytvořeno</TH><TH>Technik</TH><TH>Akce</TH>
                  </TRow>
                </thead>
                <tbody>
                  {mLogs.map(l => (
                    <TRow key={l.id}>
                      <TD>{l.description || '—'}</TD>
                      <TD>{l.type || '—'}</TD>
                      <TD>{l.created_at ? new Date(l.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD>{l.performed_by || '—'}</TD>
                      <TD>
                        <Button green onClick={() => markCompleted(l)} style={{ fontSize: 10, padding: '4px 10px' }}>
                          Dokončit
                        </Button>
                      </TD>
                    </TRow>
                  ))}
                </tbody>
              </Table>
            ) : (
              <div className="text-xs p-3 rounded-lg" style={{ background: '#fef3c7', color: '#b45309' }}>
                Motorka je ve stavu servis, ale nemá aktivní servisní záznam.
              </div>
            )}
          </Card>
        )
      })}
    </div>
  )
}
