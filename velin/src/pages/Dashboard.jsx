import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Stat from '../components/ui/Stat'
import Badge from '../components/ui/Badge'
import MiniChart from '../components/ui/MiniChart'
import ExportBar from '../components/ui/ExportBar'

const STATUS_MAP = {
  active: { label: 'Aktivní', color: '#1a8a18', bg: '#dcfce7' },
  maintenance: { label: 'V servisu', color: '#92400e', bg: '#fef3c7' },
  out_of_service: { label: 'Vyřazena', color: '#991b1b', bg: '#fee2e2' },
  pending: { label: 'Čekající', color: '#92400e', bg: '#fef3c7' },
  confirmed: { label: 'Potvrzená', color: '#1a8a18', bg: '#dcfce7' },
  completed: { label: 'Dokončena', color: '#3b82f6', bg: '#dbeafe' },
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

export default function Dashboard() {
  const [stats, setStats] = useState(null)
  const [revenueChart, setRevenueChart] = useState([])
  const [upcomingEvents, setUpcomingEvents] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetchDashboardData()
  }, [])

  async function fetchDashboardData() {
    setLoading(true)
    try {
      const [motorcyclesRes, bookingsRes, revenueRes, messagesRes, inventoryRes, chartRes, eventsRes, sosRes, stkRes] = await Promise.all([
        supabase.from('motorcycles').select('id, status', { count: 'exact' }),
        supabase.from('bookings').select('id, status').in('status', ['active', 'pending', 'confirmed']),
        supabase.from('accounting_entries').select('amount').eq('type', 'revenue')
          .gte('date', new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]),
        supabase.from('messages').select('id', { count: 'exact' }).is('read_at', null),
        supabase.from('inventory').select('id, stock, min_stock'),
        supabase.from('accounting_entries').select('amount, date').eq('type', 'revenue')
          .gte('date', new Date(new Date().getFullYear() - 1, new Date().getMonth(), 1).toISOString().split('T')[0])
          .order('date', { ascending: true }),
        supabase.from('bookings').select('id, customer_name, motorcycle_name, start_date, end_date, status, total_price')
          .gte('start_date', new Date().toISOString().split('T')[0]).order('start_date', { ascending: true }).limit(5),
        supabase.from('sos_incidents').select('id', { count: 'exact', head: true }).in('status', ['reported', 'acknowledged']),
        supabase.from('motorcycles').select('id, model, spz, stk_valid_until'),
      ])
      const allMotos = motorcyclesRes.data || []
      const activeMotos = allMotos.filter(m => m.status === 'active').length
      const bookings = bookingsRes.data || []
      const activeBookings = bookings.filter(b => b.status === 'active' || b.status === 'confirmed').length
      const pendingBookings = bookings.filter(b => b.status === 'pending').length
      const monthRevenue = (revenueRes.data || []).reduce((s, e) => s + (Number(e.amount) || 0), 0)
      const unreadMessages = messagesRes.count || (messagesRes.data || []).length
      const lowStock = (inventoryRes.data || []).filter(i => i.stock <= (i.min_stock || 0)).length
      const utilization = activeMotos > 0 ? Math.round((activeBookings / activeMotos) * 100) : 0
      const in30days = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10)
      const stkExpiring = (stkRes.data || []).filter(m => m.stk_valid_until && m.stk_valid_until <= in30days)
      setStats({
        activeMotos, totalMotos: allMotos.length, activeBookings, pendingBookings,
        monthRevenue, unreadMessages, lowStock, utilization: Math.min(utilization, 100),
        activeSos: sosRes.count || 0, stkExpiring,
      })
      const chartEntries = chartRes.data || []
      const monthlyData = new Array(12).fill(0)
      chartEntries.forEach(e => { monthlyData[new Date(e.date).getMonth()] += Number(e.amount) || 0 })
      setRevenueChart(monthlyData)
      setUpcomingEvents(eventsRes.data || [])
    } catch {
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
            {MONTHS.map((m, i) => <span key={i} className="text-[8px] font-bold" style={{ color: '#8aab99' }}>{m}</span>)}
          </div>
        </Card>
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>📅 Nejbližší události</div>
          {upcomingEvents.length === 0 ? (
            <div className="text-xs font-medium py-4 text-center" style={{ color: '#8aab99' }}>Žádné nadcházející události</div>
          ) : upcomingEvents.map(event => (
            <div key={event.id} className="flex items-center mb-1.5"
              style={{ padding: '8px 10px', background: '#f1faf7', borderRadius: 12, fontSize: 12 }}>
              <div className="flex-1">
                <div className="font-bold" style={{ color: '#0f1a14' }}>{event.customer_name || 'Zákazník'}</div>
                <div className="text-[11px]" style={{ color: '#8aab99' }}>
                  {event.motorcycle_name || 'Motorka'} · {event.start_date}→{event.end_date}
                </div>
              </div>
              <div className="text-right">
                {event.total_price && <div className="font-extrabold" style={{ color: '#3dba3a' }}>{Number(event.total_price).toLocaleString('cs-CZ')} Kč</div>}
                {event.status && STATUS_MAP[event.status] && <Badge {...STATUS_MAP[event.status]} />}
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
              <div className="text-xs font-bold" style={{ color: '#dc2626' }}>aktivních incidentů</div>
            </div>
          ) : <div className="text-xs font-medium" style={{ color: '#1a8a18' }}>✅ Žádné aktivní incidenty</div>}
        </Card>
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>🏛️ Blížící se STK</div>
          {stats.stkExpiring && stats.stkExpiring.length > 0 ? (
            <div className="space-y-1">
              {stats.stkExpiring.slice(0, 4).map(m => {
                const days = Math.ceil((new Date(m.stk_valid_until) - new Date()) / 86400000)
                return (
                  <div key={m.id} className="flex items-center text-xs"
                    style={{ padding: '6px 10px', background: days < 0 ? '#fee2e2' : '#fef3c7', borderRadius: 8 }}>
                    <span className="font-bold" style={{ color: '#0f1a14' }}>{m.model}</span>
                    <span className="ml-2 font-mono text-[10px]" style={{ color: '#8aab99' }}>{m.spz}</span>
                    <span className="ml-auto font-bold" style={{ color: days < 0 ? '#dc2626' : '#b45309' }}>
                      {days < 0 ? `${Math.abs(days)} dní po` : `za ${days} dní`}
                    </span>
                  </div>
                )
              })}
            </div>
          ) : <div className="text-xs font-medium" style={{ color: '#1a8a18' }}>✅ Žádné STK nevyprší v nejbližších 30 dnech</div>}
        </Card>
      </div>
      {stats.lowStock > 0 && (
        <div className="flex gap-2.5 mt-4 flex-wrap">
          <div className="text-xs font-bold" style={{ background: '#fef3c7', borderRadius: 50, padding: '8px 18px', color: '#92400e' }}>
            ⚠️ {stats.lowStock} položek pod minimem
          </div>
        </div>
      )}
      <ExportBar />
    </div>
  )
}
