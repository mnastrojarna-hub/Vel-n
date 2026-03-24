import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog, debugError } from '../lib/debugLog'
// ActiveServiceTab extracted to ./service/ActiveServiceTab.jsx
import { useDebugMode } from '../hooks/useDebugMode'
import Card from '../components/ui/Card'
import ActiveServiceTab from './service/ActiveServiceTab'
import ServiceSchedule from './service/ServiceSchedule'
import ServiceLog from './service/ServiceLog'
import StkTab from './government/StkTab'

const TABS = ['Aktivní v servisu', 'Servisní log', 'Plánované', 'STK & Emise']

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

      const [planned, inService, openLogs, costs] = await debugAction('service.loadStats', 'Service', () => Promise.all([
        supabase.from('maintenance_schedules').select('id', { count: 'exact', head: true })
          .eq('active', true),
        supabase.from('motorcycles').select('id', { count: 'exact', head: true })
          .eq('status', 'maintenance'),
        supabase.from('maintenance_log').select('id', { count: 'exact', head: true })
          .is('completed_date', null),
        supabase.from('maintenance_log').select('cost').not('cost', 'is', null),
      ]))

      const costArr = (costs.data || []).map(c => c.cost).filter(Boolean)
      const avg = costArr.length > 0 ? costArr.reduce((s, c) => s + c, 0) / costArr.length : 0

      setStats({
        planned: planned.count || 0,
        inService: inService.count || 0,
        openLogs: openLogs.count || 0,
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
          {stats.openLogs > stats.inService && (
            <div className="text-xs mt-1" style={{ color: '#7c3aed' }}>{fmt(stats.openLogs)} otevřených záznamů</div>
          )}
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
      {tab === 'STK & Emise' && <StkTab />}
    </div>
  )
}

