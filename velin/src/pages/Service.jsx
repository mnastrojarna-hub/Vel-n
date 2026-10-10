import { useState, useEffect } from 'react'
import { useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog, debugError } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Card from '../components/ui/Card'
import ServiceOverview from './service/ServiceOverview'
import ActiveServiceTab from './service/ActiveServiceTab'
import ServiceSchedule from './service/ServiceSchedule'
import ServiceLog from './service/ServiceLog'
import ServiceBookIndex from './service/ServiceBookIndex'
import ServiceProviderProfile from './service/ServiceProviderProfile'
import StkTab from './government/StkTab'
import { fetchServiceDueCount, effectiveCost } from '../lib/serviceBook'

const TABS = [
  { key: 'prehled', label: 'Přehled' }, { key: 'aktivni', label: 'Aktivní v servisu' }, { key: 'planovane', label: 'Plánované' },
  { key: 'kniha', label: 'Servisní knížka' }, { key: 'log', label: 'Servisní log' }, { key: 'stk', label: 'STK & Emise' },
]

export default function Service() {
  const debugMode = useDebugMode()
  const [params, setParams] = useSearchParams()
  const tab = TABS.some(t => t.key === params.get('tab')) ? params.get('tab') : 'prehled'
  const setTab = (k) => { debugLog('tab.switch', 'Service', { tab: k }); setParams(k === 'prehled' ? {} : { tab: k }) }
  const [stats, setStats] = useState({ inService: 0, openLogs: 0, overdue: 0, dueSoon: 0, unknown: 0, avgCost: 0 })

  useEffect(() => { debugLog('page.mount', 'Service'); loadStats() }, [])

  async function loadStats() {
    try {
      const [inService, openLogs, costs, due] = await debugAction('service.loadStats', 'Service', () => Promise.all([
        supabase.from('motorcycles').select('id', { count: 'exact', head: true }).eq('status', 'maintenance'),
        supabase.from('maintenance_log').select('id', { count: 'exact', head: true }).is('completed_date', null),
        supabase.from('maintenance_log').select('cost, invoiced_amount').eq('status', 'completed'),
        fetchServiceDueCount(),
      ]))
      const costArr = (costs.data || []).map(effectiveCost).filter(Boolean)
      setStats({
        inService: inService.count || 0, openLogs: openLogs.count || 0,
        overdue: due?.overdue || 0, dueSoon: due?.due_soon || 0, unknown: due?.unknown || 0,
        avgCost: costArr.length ? Math.round(costArr.reduce((s, c) => s + c, 0) / costArr.length) : 0,
      })
    } catch (err) { debugError('service.loadStats', 'Service', err) }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ')
  const Stat = ({ title, value, color = '#0f1a14', sub, onClick }) => (
    <Card style={onClick ? { cursor: 'pointer' } : undefined}>
      <div onClick={onClick}>
        <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{title}</div>
        <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
        {sub && <div className="text-xs mt-1" style={{ color: '#6b7280' }}>{sub}</div>}
      </div>
    </Card>
  )

  return (
    <div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-5">
        <Stat title="Po termínu" value={fmt(stats.overdue)} color={stats.overdue ? '#dc2626' : '#1a8a18'} sub={stats.dueSoon ? `+ ${fmt(stats.dueSoon)} blíží se` : 'intervaly údržby'} onClick={() => setTab('planovane')} />
        <Stat title="Motorky v servisu" value={fmt(stats.inService)} color="#b45309" sub={`${fmt(stats.openLogs)} otevřených záznamů`} onClick={() => setTab('aktivni')} />
        <Stat title="Neověřené intervaly" value={fmt(stats.unknown)} color={stats.unknown ? '#6b7280' : '#1a8a18'} sub="doplnit poslední provedení" onClick={() => setTab('kniha')} />
        <Stat title="Ø náklady / servis" value={`${fmt(stats.avgCost)} Kč`} sub="dokončené servisy" />
      </div>

      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA Service</strong><br />
          <div>inService: {stats.inService}, openLogs: {stats.openLogs}, overdue: {stats.overdue}, dueSoon: {stats.dueSoon}, unknown: {stats.unknown}, avgCost: {fmt(stats.avgCost)} · tab: {tab}</div>
        </div>
      )}

      <div className="flex gap-2 mb-4 flex-wrap">
        {TABS.map(t => (
          <button key={t.key} onClick={() => setTab(t.key)} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer px-[18px] py-2 max-lg:py-2.5"
            style={{ background: tab === t.key ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', boxShadow: tab === t.key ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t.label}
          </button>
        ))}
      </div>

      <div className="mb-4"><ServiceProviderProfile /></div>

      {tab === 'prehled' && <ServiceOverview />}
      {tab === 'aktivni' && <ActiveServiceTab onRefresh={loadStats} />}
      {tab === 'planovane' && <ServiceSchedule onRefresh={loadStats} />}
      {tab === 'kniha' && <ServiceBookIndex />}
      {tab === 'log' && <ServiceLog />}
      {tab === 'stk' && <StkTab />}
    </div>
  )
}
