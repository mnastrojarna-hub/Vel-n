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
      <div
        className="w-8 h-8 rounded-full animate-spin"
        style={{ border: '3px solid #d4e8e0', borderTopColor: '#74FB71' }}
      />
    </div>
  )
}

export default function Dashboard() {
  const [stats, setStats] = useState(null)
  const [revenueChart, setRevenueChart] = useState([])
  const [upcomingEvents, setUpcomingEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    fetchDashboardData()
  }, [])

  async function fetchDashboardData() {
    setLoading(true)
    setError(null)

    try {
      const [
        motorcyclesRes,
        bookingsRes,
        revenueRes,
        messagesRes,
        inventoryRes,
        chartRes,
        eventsRes,
      ] = await Promise.all([
        // Active motorcycles count
        supabase
          .from('motorcycles')
          .select('id, status', { count: 'exact' }),
        // Bookings by status
        supabase
          .from('bookings')
          .select('id, status')
          .in('status', ['active', 'pending', 'confirmed']),
        // Monthly revenue
        supabase
          .from('accounting_entries')
          .select('amount')
          .eq('type', 'revenue')
          .gte('date', new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]),
        // Unread messages
        supabase
          .from('messages')
          .select('id', { count: 'exact' })
          .eq('read', false),
        // Low stock items
        supabase
          .from('inventory')
          .select('id, stock, min_stock'),
        // Revenue chart data (last 12 months from accounting_entries)
        supabase
          .from('accounting_entries')
          .select('amount, date')
          .eq('type', 'revenue')
          .gte('date', new Date(new Date().getFullYear() - 1, new Date().getMonth(), 1).toISOString().split('T')[0])
          .order('date', { ascending: true }),
        // Upcoming events (bookings + services)
        supabase
          .from('bookings')
          .select('id, customer_name, motorcycle_name, start_date, end_date, status, total_price')
          .gte('start_date', new Date().toISOString().split('T')[0])
          .order('start_date', { ascending: true })
          .limit(5),
      ])

      // Process motorcycles
      const allMotos = motorcyclesRes.data || []
      const activeMotos = allMotos.filter((m) => m.status === 'active').length
      const totalMotos = allMotos.length

      // Process bookings
      const bookings = bookingsRes.data || []
      const activeBookings = bookings.filter(
        (b) => b.status === 'active' || b.status === 'confirmed'
      ).length
      const pendingBookings = bookings.filter((b) => b.status === 'pending').length

      // Process revenue
      const monthRevenue = (revenueRes.data || []).reduce(
        (sum, entry) => sum + (Number(entry.amount) || 0),
        0
      )

      // Process messages
      const unreadMessages = messagesRes.count || (messagesRes.data || []).length

      // Process inventory
      const lowStock = (inventoryRes.data || []).filter(
        (item) => item.stock <= (item.min_stock || 0)
      ).length

      // Utilization (approximate: active bookings / active motos)
      const utilization =
        activeMotos > 0 ? Math.round((activeBookings / activeMotos) * 100) : 0

      setStats({
        activeMotos,
        totalMotos,
        activeBookings,
        pendingBookings,
        monthRevenue,
        unreadMessages,
        lowStock,
        utilization: Math.min(utilization, 100),
      })

      // Process chart data — aggregate by month
      const chartEntries = chartRes.data || []
      const monthlyData = new Array(12).fill(0)
      chartEntries.forEach((entry) => {
        const d = new Date(entry.date)
        const monthIndex = d.getMonth()
        monthlyData[monthIndex] += Number(entry.amount) || 0
      })
      setRevenueChart(monthlyData)

      // Process upcoming events
      setUpcomingEvents(eventsRes.data || [])
    } catch (err) {
      setError(err.message || 'Chyba při načítání dat.')
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <Spinner />

  if (error) {
    return (
      <Card>
        <div className="text-center py-8">
          <div className="text-3xl mb-3">⚠️</div>
          <div className="text-sm font-bold" style={{ color: '#991b1b' }}>
            {error}
          </div>
          <button
            onClick={fetchDashboardData}
            className="mt-4 text-xs font-bold underline cursor-pointer bg-transparent border-none"
            style={{ color: '#1a8a18' }}
          >
            Zkusit znovu
          </button>
        </div>
      </Card>
    )
  }

  const formatCurrency = (val) => {
    if (val >= 1_000_000) return `${(val / 1_000_000).toFixed(1)}M Kč`
    if (val >= 1_000) return `${Math.round(val / 1_000)}k Kč`
    return `${val} Kč`
  }

  return (
    <div>
      {/* Stat cards */}
      <div className="flex gap-3.5 mb-5 flex-wrap">
        <Stat
          icon="🏍️"
          label="Aktivní motorky"
          value={`${stats.activeMotos}/${stats.totalMotos}`}
          sub={`Ø využití ${stats.utilization}%`}
        />
        <Stat
          icon="💰"
          label="Tržby měsíc"
          value={formatCurrency(stats.monthRevenue)}
          color="#f59e0b"
        />
        <Stat
          icon="📅"
          label="Akt. / Čekající"
          value={`${stats.activeBookings} / ${stats.pendingBookings}`}
          sub="rezervací"
          color="#3b82f6"
        />
        <Stat
          icon="💬"
          label="Nepřečtené"
          value={stats.unreadMessages}
          sub="zpráv"
          color="#8b5cf6"
        />
        <Stat
          icon="📦"
          label="Nízké zásoby"
          value={stats.lowStock}
          sub="položek pod minimem"
          color={stats.lowStock > 0 ? '#ef4444' : '#1a8a18'}
        />
        <Stat
          icon="📊"
          label="Využití flotily"
          value={`${stats.utilization}%`}
          sub={`${stats.activeMotos} aktivních strojů`}
          color="#1a8a18"
        />
      </div>

      {/* Charts and tables */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Revenue chart */}
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>
            📈 Tržby dle měsíců (Kč)
          </div>
          <MiniChart data={revenueChart} color="#1a8a18" height={70} />
          <div className="flex justify-between mt-1.5">
            {MONTHS.map((m, i) => (
              <span key={i} className="text-[8px] font-bold" style={{ color: '#8aab99' }}>
                {m}
              </span>
            ))}
          </div>
          <div className="flex gap-4 mt-2">
            <span className="text-[10px] font-bold" style={{ color: '#1a8a18' }}>
              ● Tržby
            </span>
          </div>
        </Card>

        {/* Upcoming events */}
        <Card>
          <div className="text-[13px] font-extrabold mb-2.5" style={{ color: '#0f1a14' }}>
            📅 Nejbližší události
          </div>
          {upcomingEvents.length === 0 ? (
            <div className="text-xs font-medium py-4 text-center" style={{ color: '#8aab99' }}>
              Žádné nadcházející události
            </div>
          ) : (
            upcomingEvents.map((event) => (
              <div
                key={event.id}
                className="flex items-center mb-1.5"
                style={{
                  padding: '8px 10px',
                  background: '#f1faf7',
                  borderRadius: 12,
                  fontSize: 12,
                }}
              >
                <div className="flex-1">
                  <div className="font-bold" style={{ color: '#0f1a14' }}>
                    {event.customer_name || 'Zákazník'}
                  </div>
                  <div className="text-[11px]" style={{ color: '#8aab99' }}>
                    {event.motorcycle_name || 'Motorka'} · {event.start_date}→
                    {event.end_date}
                  </div>
                </div>
                <div className="text-right">
                  {event.total_price && (
                    <div className="font-extrabold" style={{ color: '#3dba3a' }}>
                      {Number(event.total_price).toLocaleString('cs-CZ')} Kč
                    </div>
                  )}
                  {event.status && STATUS_MAP[event.status] && (
                    <Badge {...STATUS_MAP[event.status]} />
                  )}
                </div>
              </div>
            ))
          )}
        </Card>
      </div>

      {/* Alerts */}
      {stats.lowStock > 0 && (
        <div className="flex gap-2.5 mt-4 flex-wrap">
          <div
            className="text-xs font-bold"
            style={{
              background: '#fef3c7',
              borderRadius: 50,
              padding: '8px 18px',
              color: '#92400e',
            }}
          >
            ⚠️ {stats.lowStock} položek pod minimem
          </div>
        </div>
      )}

      {/* Export bar */}
      <ExportBar />
    </div>
  )
}
