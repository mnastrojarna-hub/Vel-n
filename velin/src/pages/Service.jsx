import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

import Card from '../components/ui/Card'
import ServiceSchedule from './service/ServiceSchedule'
import ServiceLog from './service/ServiceLog'

const TABS = ['Plánované', 'Servisní log']

export default function Service() {
  const [tab, setTab] = useState('Servisní log')
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
      setStats({ planned: 0, inService: 0, avgCost: 0 })
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

      {tab === 'Plánované' && <ServiceSchedule />}
      {tab === 'Servisní log' && <ServiceLog />}
    </div>
  )
}
