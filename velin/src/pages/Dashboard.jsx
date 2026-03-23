import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog, debugError } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { isRevenueEntry } from '../lib/revenueUtils'
import Card from '../components/ui/Card'
import Stat from '../components/ui/Stat'
import Badge from '../components/ui/Badge'
import MiniChart from '../components/ui/MiniChart'
import ExportBar from '../components/ui/ExportBar'
import { getDisplayStatus } from '../components/ui/StatusBadge'

const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  upcoming: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  maintenance: { label: 'V servisu', color: '#92400e', bg: '#fef3c7' },
  unavailable: { label: 'Dočasně vyřazena', color: '#7c3aed', bg: '#ede9fe' },
  pending: { label: 'Čekající', color: '#92400e', bg: '#fef3c7' },
  reserved: { label: 'Nadcházející', color: '#7c3aed', bg: '#ede9fe' },
  completed: { label: 'Dokončena', color: '#3b82f6', bg: '#dbeafe' },
  cancelled: { label: 'Zrušeno', color: '#dc2626', bg: '#fee2e2' },
}

const MONTHS = ['Led', 'Úno', 'Bře', 'Dub', 'Kvě', 'Čvn', 'Čvc', 'Srp', 'Zář', 'Říj', 'Lis', 'Pro']

function Spinner() {
  return (
    <div className="flex items-center justify-center py-8">
      <div className="w-8 h-8 rounded-full animate-spin"
        style={{ border: '3px solid #d4e8e0', borderTopColor: '#74FB71' }} />
    </div>
  )
}

function BannerEditor() {
  const [banner, setBanner] = useState({ enabled: false, text: '', bg: '#1a2e22', color: '#74FB71' })
  const [saving, setSaving] = useState(false)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    supabase.from('app_settings').select('value').eq('key', 'header_banner').maybeSingle()
      .then(({ data }) => {
        if (data?.value) {
          const v = typeof data.value === 'string' ? JSON.parse(data.value) : data.value
          setBanner(prev => ({ ...prev, ...v }))
        }
        setLoaded(true)
      })
      .catch(() => setLoaded(true))
  }, [])

  async function saveBanner() {
    setSaving(true)
    try {
      const { error } = await supabase.from('app_settings').upsert(
        { key: 'header_banner', value: banner },
        { onConflict: 'key' }
      )
      if (error) throw error
      alert('Banner uložen!')
    } catch (e) {
      alert('Chyba: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  if (!loaded) return null

  return (
    <Card>
      <div className="flex items-center justify-between mb-3">
        <div className="text-[13px] font-extrabold" style={{ color: '#0f1a14' }}>📢 Banner v aplikaci</div>
        <label className="flex items-center gap-2 cursor-pointer">
          <span className="text-xs font-bold" style={{ color: banner.enabled ? '#1a8a18' : '#8aab99' }}>
            {banner.enabled ? 'Zapnuto' : 'Vypnuto'}
          </span>
          <input
            type="checkbox"
            checked={banner.enabled}
            onChange={e => setBanner(prev => ({ ...prev, enabled: e.target.checked }))}
            className="w-4 h-4 accent-green-500"
          />
        </label>
      </div>
      <div className="space-y-2">
        <div>
          <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Text banneru</label>
          <input
            type="text"
            value={banner.text}
            onChange={e => setBanner(prev => ({ ...prev, text: e.target.value }))}
            placeholder="Letní akce -20% na všechny motorky!"
            className="w-full px-3 py-2 rounded-lg border text-sm font-medium"
            style={{ borderColor: '#d4e8e0', color: '#0f1a14' }}
          />
        </div>
        <div className="flex gap-3">
          <div className="flex-1">
            <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Barva pozadí</label>
            <div className="flex items-center gap-2">
              <input type="color" value={banner.bg} onChange={e => setBanner(prev => ({ ...prev, bg: e.target.value }))} className="w-8 h-8 rounded cursor-pointer border-0" />
              <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{banner.bg}</span>
            </div>
          </div>
          <div className="flex-1">
            <label className="text-xs font-bold block mb-1" style={{ color: '#1a2e22' }}>Barva textu</label>
            <div className="flex items-center gap-2">
              <input type="color" value={banner.color} onChange={e => setBanner(prev => ({ ...prev, color: e.target.value }))} className="w-8 h-8 rounded cursor-pointer border-0" />
              <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{banner.color}</span>
            </div>
          </div>
        </div>
        {banner.text && (
          <div className="rounded-lg overflow-hidden mt-2" style={{ background: banner.bg, padding: '6px 12px' }}>
            <div className="text-xs font-bold truncate" style={{ color: banner.color }}>Náhled: {banner.text}</div>
          </div>
        )}
        <button
          onClick={saveBanner}
          disabled={saving}
          className="w-full py-2 rounded-lg text-sm font-bold text-white mt-1"
          style={{ background: saving ? '#8aab99' : '#1a8a18' }}
        >
          {saving ? 'Ukládání...' : 'Uložit banner'}
        </button>
      </div>
    </Card>
  )
}

export default function Dashboard() {
  const debugMode = useDebugMode()
  const [stats, setStats] = useState(null)
  const [revenueChart, setRevenueChart] = useState([])
  const [upcomingEvents, setUpcomingEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [financeData, setFinanceData] = useState({ revenue: 0, expense: 0, profit: 0, unpaid: 0 })

  useEffect(() => {
    debugLog('page.mount', 'Dashboard')
    fetchDashboardData()
    const interval = setInterval(fetchDashboardData, 120000)
    return () => clearInterval(interval)
  }, [])

  async function fetchDashboardData() {
    setLoading(true)
    try {
      const today = new Date().toISOString().split('T')[0]
      const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]
      const yearAgoMonth = new Date(new Date().getFullYear() - 1, new Date().getMonth(), 1).toISOString().split('T')[0]
      const [motorcyclesRes, bookingsRes, messagesRes, inventoryRes, eventsRes, sosRes, stkRes, financeRes, chartFinanceRes, unpaidRes] = await debugAction('dashboard.fetchAll', 'Dashboard', () => Promise.all([
        supabase.from('motorcycles').select('id, status', { count: 'exact' }),
        supabase.from('bookings').select('id, status').in('status', ['active', 'pending', 'reserved']),
        supabase.from('messages').select('id', { count: 'exact' }).eq('direction', 'customer').is('read_at', null),
        supabase.from('inventory').select('id, stock, min_stock'),
        supabase.from('bookings').select('id, user_id, moto_id, start_date, end_date, status, total_price')
          .or(`start_date.gte.${today},status.eq.active`)
          .in('status', ['active', 'reserved', 'pending'])
          .order('start_date', { ascending: true }).limit(5),
        supabase.from('sos_incidents').select('id, type, severity, status', { count: 'exact' }).in('status', ['reported', 'acknowledged', 'in_progress']),
        supabase.from('motorcycles').select('id, model, spz, stk_valid_until'),
        supabase.from('accounting_entries').select('type, amount, category, description')
          .gte('date', monthStart),
        supabase.from('accounting_entries').select('type, amount, category, description, date')
          .gte('date', yearAgoMonth)
          .order('date', { ascending: true }),
        supabase.from('invoices').select('total').eq('status', 'unpaid'),
      ]))
      const allMotos = motorcyclesRes.data || []
      const activeMotos = allMotos.filter(m => m.status === 'active').length
      const bookings = bookingsRes.data || []
      const activeBookings = bookings.filter(b => b.status === 'active' || b.status === 'reserved').length
      const pendingBookings = bookings.filter(b => b.status === 'pending').length
      const unreadMessages = messagesRes.count || (messagesRes.data || []).length
      const lowStock = (inventoryRes.data || []).filter(i => i.stock <= (i.min_stock || 0)).length
      const utilization = activeMotos > 0 ? Math.round((activeBookings / activeMotos) * 100) : 0
      const in30days = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10)
      const stkExpiring = (stkRes.data || []).filter(m => m.stk_valid_until && m.stk_valid_until <= in30days)

      // Finance summary
      const finEntries = financeRes.data || []
      const finRev = finEntries.filter(e => isRevenueEntry(e)).reduce((s, e) => s + Math.abs(e.amount || 0), 0)
      const finExp = finEntries.filter(e => !isRevenueEntry(e)).reduce((s, e) => s + Math.abs(e.amount || 0), 0)
      const finUnpaid = (unpaidRes.data || []).reduce((s, i) => s + (i.total || 0), 0)
      setFinanceData({ revenue: finRev, expense: finExp, profit: finRev - finExp, unpaid: finUnpaid })

      // Month revenue stat uses same classification
      const monthRevenue = finRev

      setStats({
        activeMotos, totalMotos: allMotos.length, activeBookings, pendingBookings,
        monthRevenue, unreadMessages, lowStock, utilization: Math.min(utilization, 100),
        activeSos: sosRes.count || (sosRes.data || []).length,
        sosCritical: (sosRes.data || []).filter(s => s.severity === 'critical' || s.severity === 'high').length,
        stkExpiring,
      })

      // Revenue chart (last 12 months) — same classification
      const chartEntries = chartFinanceRes.data || []
      const monthlyData = new Array(12).fill(0)
      chartEntries.forEach(e => {
        if (isRevenueEntry(e)) monthlyData[new Date(e.date).getMonth()] += Math.abs(Number(e.amount) || 0)
      })
      setRevenueChart(monthlyData)

      // Enrich upcoming events with profile/motorcycle names
      const rawEvents = eventsRes.data || []
      let enrichedEvents = rawEvents
      if (rawEvents.length > 0) {
        const userIds = [...new Set(rawEvents.map(e => e.user_id).filter(Boolean))]
        const motoIds = [...new Set(rawEvents.map(e => e.moto_id).filter(Boolean))]
        const [profilesRes, motosRes] = await debugAction('dashboard.enrichEvents', 'Dashboard', () => Promise.all([
          userIds.length > 0 ? supabase.from('profiles').select('id, full_name').in('id', userIds) : { data: [] },
          motoIds.length > 0 ? supabase.from('motorcycles').select('id, model').in('id', motoIds) : { data: [] },
        ]))
        const profileMap = Object.fromEntries((profilesRes.data || []).map(p => [p.id, p.full_name]))
        const motoMap = Object.fromEntries((motosRes.data || []).map(m => [m.id, m.model]))
        enrichedEvents = rawEvents.map(e => ({
          ...e,
          customer_name: profileMap[e.user_id] || null,
          motorcycle_name: motoMap[e.moto_id] || null,
        }))
      }
      setUpcomingEvents(enrichedEvents)
    } catch (err) {
      debugError('dashboard.fetchAll', 'Dashboard', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <Spinner />
  if (!stats) return null

  const formatCurrency = (val) => {
    if (val >= 1_000_000) return `${(val / 1_000_000).toFixed(1)}M Kč`
    if (val >= 1_000) return `${Math.round(val / 1_000)}k Kč`
    return `${val} Kč`
  }

  return (
    <div>
      <div className="mb-4">
        <BannerEditor />
      </div>
      <div className="flex gap-3.5 mb-5 flex-wrap">
        <Stat icon="🏍️" label="Aktivní motorky" value={`${stats.activeMotos}/${stats.totalMotos}`} sub={`Ø využití ${stats.utilization}%`} />
        <Stat icon="💰" label="Tržby měsíc" value={formatCurrency(stats.monthRevenue)} color="#f59e0b" />
        <Stat icon="📅" label="Akt. / Čekající" value={`${stats.activeBookings} / ${stats.pendingBookings}`} sub="rezervací" color="#3b82f6" />
        <Stat icon="💬" label="Nepřečtené" value={stats.unreadMessages} sub="zpráv" color="#8b5cf6" />
        <Stat icon="📦" label="Nízké zásoby" value={stats.lowStock} sub="položek pod minimem" color={stats.lowStock > 0 ? '#ef4444' : '#1a8a18'} />
        <Stat icon="📊" label="Využití flotily" value={`${stats.utilization}%`} sub={`${stats.activeMotos} aktivních strojů`} color="#1a8a18" />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>📈 Tržby dle měsíců (Kč)</div>
          <MiniChart data={revenueChart} color="#1a8a18" height={70} />
          <div className="flex justify-between mt-1.5">
            {MONTHS.map((m, i) => <span key={i} className="text-[8px] font-bold" style={{ color: '#1a2e22' }}>{m}</span>)}
          </div>
        </Card>
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>📅 Nejbližší události</div>
          {upcomingEvents.length === 0 ? (
            <div className="text-sm font-medium py-4 text-center" style={{ color: '#1a2e22' }}>Žádné nadcházející události</div>
          ) : upcomingEvents.map(event => (
            <div key={event.id} className="flex items-center mb-1.5"
              style={{ padding: '8px 10px', background: '#f1faf7', borderRadius: 12, fontSize: 12 }}>
              <div className="flex-1">
                <div className="font-bold" style={{ color: '#0f1a14' }}>{event.customer_name || 'Zákazník'}</div>
                <div className="text-sm" style={{ color: '#1a2e22' }}>
                  {event.motorcycle_name || 'Motorka'} · {new Date(event.start_date).toLocaleDateString('cs-CZ')} – {new Date(event.end_date).toLocaleDateString('cs-CZ')}
                </div>
              </div>
              <div className="text-right">
                {event.total_price && <div className="font-extrabold" style={{ color: '#3dba3a' }}>{Number(event.total_price).toLocaleString('cs-CZ')} Kč</div>}
                {event.status && STATUS_MAP[getDisplayStatus(event)] && <Badge {...STATUS_MAP[getDisplayStatus(event)]} />}
              </div>
            </div>
          ))}
        </Card>
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>🚨 SOS Incidenty</div>
          {stats.activeSos > 0 ? (
            <div className="flex items-center gap-3">
              <div className="text-2xl font-black" style={{ color: '#dc2626' }}>{stats.activeSos}</div>
              <div>
                <div className="text-sm font-bold" style={{ color: '#dc2626' }}>aktivních incidentů</div>
                {stats.sosCritical > 0 && (
                  <div className="text-sm font-extrabold uppercase tracking-wide mt-0.5 animate-pulse" style={{ color: '#dc2626' }}>
                    {stats.sosCritical} kritických!
                  </div>
                )}
              </div>
            </div>
          ) : <div className="text-sm font-medium" style={{ color: '#1a8a18' }}>Žádné aktivní incidenty</div>}
        </Card>
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>🏛️ Blížící se STK</div>
          {stats.stkExpiring && stats.stkExpiring.length > 0 ? (
            <div className="space-y-1">
              {stats.stkExpiring.slice(0, 4).map(m => {
                const days = Math.ceil((new Date(m.stk_valid_until) - new Date()) / 86400000)
                return (
                  <div key={m.id} className="flex items-center text-sm"
                    style={{ padding: '6px 10px', background: days < 0 ? '#fee2e2' : '#fef3c7', borderRadius: 8 }}>
                    <span className="font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
                    <span className="ml-2 font-mono text-sm" style={{ color: '#1a2e22' }}>{m.spz}</span>
                    <span className="ml-auto font-bold" style={{ color: days < 0 ? '#dc2626' : '#b45309' }}>
                      {days < 0 ? `${Math.abs(days)} dní po` : `za ${days} dní`}
                    </span>
                  </div>
                )
              })}
            </div>
          ) : <div className="text-sm font-medium" style={{ color: '#1a8a18' }}>✅ Žádné STK nevyprší v nejbližších 30 dnech</div>}
        </Card>
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>💰 Finance — měsíční přehled</div>
          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-lg" style={{ padding: '10px 14px', background: '#dcfce7' }}>
              <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Příjmy</div>
              <div className="text-lg font-extrabold" style={{ color: '#1a8a18' }}>{formatCurrency(financeData.revenue)}</div>
            </div>
            <div className="rounded-lg" style={{ padding: '10px 14px', background: '#fee2e2' }}>
              <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Výdaje</div>
              <div className="text-lg font-extrabold" style={{ color: '#dc2626' }}>{formatCurrency(financeData.expense)}</div>
            </div>
            <div className="rounded-lg" style={{ padding: '10px 14px', background: financeData.profit >= 0 ? '#f0fdf4' : '#fef2f2' }}>
              <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Zisk</div>
              <div className="text-lg font-extrabold" style={{ color: financeData.profit >= 0 ? '#1a8a18' : '#dc2626' }}>{formatCurrency(financeData.profit)}</div>
            </div>
            <div className="rounded-lg" style={{ padding: '10px 14px', background: '#fef3c7' }}>
              <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Neuhrazené</div>
              <div className="text-lg font-extrabold" style={{ color: '#b45309' }}>{formatCurrency(financeData.unpaid)}</div>
            </div>
          </div>
        </Card>
      </div>
      {stats.lowStock > 0 && (
        <div className="flex gap-2.5 mt-4 flex-wrap">
          <div className="text-sm font-bold" style={{ background: '#fef3c7', borderRadius: 50, padding: '8px 18px', color: '#92400e' }}>
            ⚠️ {stats.lowStock} položek pod minimem
          </div>
        </div>
      )}
      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mt-4 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA Dashboard</strong><br/>
        <div>motorcycles: {stats.totalMotos} (active: {stats.activeMotos}, využití: {stats.utilization}%)</div>
        <div>bookings (active/pending): {stats.activeBookings}/{stats.pendingBookings}</div>
        <div>revenue (month): {stats.monthRevenue?.toLocaleString('cs-CZ')} Kč</div>
        <div>unread messages: {stats.unreadMessages}</div>
        <div>low stock items: {stats.lowStock}</div>
        <div>active SOS: {stats.activeSos} (critical: {stats.sosCritical})</div>
        <div>STK expiring (30d): {stats.stkExpiring?.length || 0}</div>
        <div>finance: příjmy={financeData.revenue?.toLocaleString('cs-CZ')} Kč, výdaje={financeData.expense?.toLocaleString('cs-CZ')} Kč, neuhrazené={financeData.unpaid?.toLocaleString('cs-CZ')} Kč</div>
        <div>revenueChart: {revenueChart.filter(v => v > 0).length}/12 měsíců s daty</div>
        <div>upcomingEvents: {upcomingEvents.length} záznamů</div>
      </div>
      )}
      <ExportBar />
    </div>
  )
}
