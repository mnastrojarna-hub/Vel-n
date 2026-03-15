import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import { supabase } from '../lib/supabase'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'

const TABS = ['Výkon poboček', 'Výkon motorek', 'Poptávka kategorií', 'Optimální flotila', 'Doporučení přesunů']

function diffDays(start, end) {
  const a = new Date(start)
  const b = new Date(end)
  return Math.max(1, Math.round((b - a) / 86400000))
}

function classifyGrowth(currentRevenue, previousRevenue) {
  if (!previousRevenue || !currentRevenue) return 'Nedostatek dat'
  const change = ((currentRevenue - previousRevenue) / previousRevenue) * 100
  if (change > 10) return 'Rostoucí'
  if (change < -5) return 'Klesající'
  if (change >= -5 && change <= 5) return 'Stagnující'
  return 'Nedostatek dat'
}

const classColors = {
  'Rostoucí': { bg: '#dcfce7', color: '#166534' },
  'Stagnující': { bg: '#fef9c3', color: '#854d0e' },
  'Klesající': { bg: '#fecaca', color: '#991b1b' },
  'Nedostatek dat': { bg: '#f3f4f6', color: '#6b7280' },
}

function VykonPobocek() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [data, setData] = useState(null)

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      const [bRes, mRes, lRes] = await Promise.all([
        supabase.from('bookings').select('id, location_id, motorcycle_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('motorcycles').select('id, location_id, model, category, brand, daily_rate, status'),
        supabase.from('locations').select('id, name, city, type'),
      ])
      if (bRes.error) throw bRes.error
      if (mRes.error) throw mRes.error
      if (lRes.error) throw lRes.error

      const bookings = bRes.data || []
      const motorcycles = mRes.data || []
      const locations = lRes.data || []

      const completed = bookings.filter(b => b.status === 'completed')

      const now = new Date()
      const thisMonth = now.getMonth()
      const thisYear = now.getFullYear()

      const branchStats = locations.map(loc => {
        const locCompleted = completed.filter(b => b.location_id === loc.id)
        const locMotos = motorcycles.filter(m => m.location_id === loc.id)
        const revenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const reservationCount = locCompleted.length
        const motorcycleCount = locMotos.length
        const revenuePerMoto = motorcycleCount > 0 ? revenue / motorcycleCount : 0

        const days = locCompleted.map(b => diffDays(b.start_date, b.end_date))
        const avgDays = days.length > 0 ? days.reduce((a, b) => a + b, 0) / days.length : 0
        const totalRentedDays = days.reduce((a, b) => a + b, 0)
        const utilizationPct = motorcycleCount > 0 ? (totalRentedDays / (motorcycleCount * 365)) * 100 : 0

        // Classification: this month vs same month last year
        const thisMonthRevenue = locCompleted
          .filter(b => { const d = new Date(b.created_at); return d.getMonth() === thisMonth && d.getFullYear() === thisYear })
          .reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const lastYearRevenue = locCompleted
          .filter(b => { const d = new Date(b.created_at); return d.getMonth() === thisMonth && d.getFullYear() === thisYear - 1 })
          .reduce((s, b) => s + (Number(b.total_price) || 0), 0)

        const classification = classifyGrowth(thisMonthRevenue, lastYearRevenue)

        return { ...loc, revenue, reservationCount, motorcycleCount, revenuePerMoto, avgDays, utilizationPct, classification }
      })

      // Totals
      const totalRevenue = branchStats.reduce((s, b) => s + b.revenue, 0)
      const totalReservations = branchStats.reduce((s, b) => s + b.reservationCount, 0)
      const allDays = completed.map(b => diffDays(b.start_date, b.end_date))
      const avgDaysTotal = allDays.length > 0 ? allDays.reduce((a, b) => a + b, 0) / allDays.length : 0
      const totalMotos = motorcycles.length
      const totalRentedDays = allDays.reduce((a, b) => a + b, 0)
      const avgUtilization = totalMotos > 0 ? (totalRentedDays / (totalMotos * 365)) * 100 : 0

      // By type aggregation
      const typeMap = {}
      for (const b of branchStats) {
        const t = b.type || 'Neznámý'
        if (!typeMap[t]) typeMap[t] = { type: t, count: 0, totalRevenue: 0, totalUtilization: 0 }
        typeMap[t].count++
        typeMap[t].totalRevenue += b.revenue
        typeMap[t].totalUtilization += b.utilizationPct
      }
      const byType = Object.values(typeMap).map(t => ({
        ...t,
        avgRevenue: t.count > 0 ? t.totalRevenue / t.count : 0,
        avgUtilization: t.count > 0 ? t.totalUtilization / t.count : 0,
      }))

      const chartData = [...branchStats].sort((a, b) => b.revenue - a.revenue).map(b => ({ name: b.name, revenue: b.revenue }))

      setData({ branchStats, totalRevenue, totalReservations, avgDaysTotal, avgUtilization, byType, chartData, locations })
    } catch (e) {
      setError(e.message || 'Chyba při načítání dat')
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} />
      </div>
    )
  }

  if (error) {
    return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  }

  if (!data || data.locations.length === 0) {
    return (
      <div className="p-8 text-center" style={{ color: '#888' }}>
        <div style={{ fontSize: 48 }}>🏢</div>
        <div className="font-bold mt-2">Žádné pobočky</div>
      </div>
    )
  }

  const { branchStats, totalRevenue, totalReservations, avgDaysTotal, avgUtilization, byType, chartData } = data

  const kpis = [
    { label: 'Celkový obrat', value: `${Math.round(totalRevenue).toLocaleString('cs-CZ')} Kč` },
    { label: 'Počet rezervací', value: totalReservations },
    { label: 'Průměrná délka pronájmu', value: `${avgDaysTotal.toFixed(1)} dní` },
    { label: 'Průměrná obsazenost', value: `${avgUtilization.toFixed(1)} %` },
  ]

  return (
    <div>
      {/* KPI Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {kpis.map(k => (
          <div key={k.label} style={{ background: '#fff', borderRadius: 14, padding: '20px 16px', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
            <div className="text-xl font-extrabold" style={{ color: '#166534' }}>{k.value}</div>
            <div className="text-xs mt-1" style={{ color: '#888' }}>{k.label}</div>
          </div>
        ))}
      </div>

      {/* Branch table */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Název', 'Typ', 'Obrat', 'Obrat/motorku', 'Rezervace', 'Obsazenost %', 'Klasifikace'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {branchStats.map(b => (
              <tr key={b.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{b.name}</td>
                <td className="py-2 px-3">
                  <span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 11, fontWeight: 700 }}>
                    {b.type || '—'}
                  </span>
                </td>
                <td className="py-2 px-3">{Math.round(b.revenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{Math.round(b.revenuePerMoto).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{b.reservationCount}</td>
                <td className="py-2 px-3">{b.utilizationPct.toFixed(1)} %</td>
                <td className="py-2 px-3">
                  <span style={{
                    background: classColors[b.classification]?.bg,
                    color: classColors[b.classification]?.color,
                    borderRadius: 8, padding: '2px 10px', fontSize: 11, fontWeight: 700,
                  }}>
                    {b.classification}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Bar chart */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Obrat poboček</div>
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={chartData}>
            <XAxis dataKey="name" tick={{ fontSize: 11 }} />
            <YAxis tickFormatter={v => `${(v / 1000).toFixed(0)}tis Kč`} tick={{ fontSize: 11 }} />
            <Tooltip formatter={v => [`${Number(v).toLocaleString('cs-CZ')} Kč`, 'Obrat']} />
            <Bar dataKey="revenue" fill="#74FB71" radius={[6, 6, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Comparison by type */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Srovnání podle typu pobočky</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Typ', 'Počet poboček', 'Průměrný obrat', 'Průměrná obsazenost'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {byType.map(t => (
              <tr key={t.type} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{t.type}</td>
                <td className="py-2 px-3">{t.count}</td>
                <td className="py-2 px-3">{Math.round(t.avgRevenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{t.avgUtilization.toFixed(1)} %</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

export default function Analyza() {
  const [tab, setTab] = useState(TABS[0])

  useEffect(() => { debugLog('page.mount', 'Analyza') }, [])

  return (
    <div>
      <h1 className="text-2xl font-extrabold mb-1" style={{ color: '#1a2e22' }}>Analýza flotily</h1>
      <p className="text-sm mb-5" style={{ color: '#888' }}>Fleet Intelligence Dashboard</p>

      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: '#1a2e22',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'Výkon poboček' && <VykonPobocek />}
      {tab !== 'Výkon poboček' && (
        <div className="p-8 text-center" style={{ color: '#888' }}>
          <div style={{ fontSize: 48 }}>📊</div>
          <div className="font-bold mt-2">Sekce se připravuje</div>
        </div>
      )}
    </div>
  )
}
