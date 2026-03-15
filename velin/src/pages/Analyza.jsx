import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import { supabase } from '../lib/supabase'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'

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

function VykonMotorek() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [data, setData] = useState(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      const [mRes, bRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, daily_rate, purchase_price, location_id, status'),
        supabase.from('bookings').select('motorcycle_id, start_date, end_date, total_price, status'),
      ])
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error

      const motorcycles = mRes.data || []
      const bookings = bRes.data || []
      const completed = bookings.filter(b => b.status === 'completed')

      const motoStats = motorcycles.map(m => {
        const mCompleted = completed.filter(b => b.motorcycle_id === m.id)
        const rentedDays = mCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
        const revenue = mCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const reservationCount = mCompleted.length
        const availableDays = 365
        const utilizationIndex = availableDays > 0 ? (rentedDays / availableDays) * 100 : 0
        const avgDailyRate = rentedDays > 0 ? revenue / rentedDays : 0
        return { ...m, rentedDays, revenue, reservationCount, utilizationIndex, avgDailyRate }
      }).sort((a, b) => b.revenue - a.revenue)

      // Brand aggregation
      const brandMap = {}
      for (const m of motoStats) {
        const br = m.brand || 'Neznámá'
        if (!brandMap[br]) brandMap[br] = { brand: br, count: 0, totalRevenue: 0, totalUtilization: 0 }
        brandMap[br].count++
        brandMap[br].totalRevenue += m.revenue
        brandMap[br].totalUtilization += m.utilizationIndex
      }
      const brandStats = Object.values(brandMap).map(b => ({
        ...b,
        revenuePerMoto: b.count > 0 ? b.totalRevenue / b.count : 0,
        avgUtilization: b.count > 0 ? b.totalUtilization / b.count : 0,
      }))
      const maxRevenuePerMoto = Math.max(...brandStats.map(b => b.revenuePerMoto), 1)
      for (const b of brandStats) {
        b.performanceScore = ((b.revenuePerMoto / maxRevenuePerMoto) + (b.avgUtilization / 100)) / 2
      }

      setData({ motoStats, brandStats, motorcycles })
    } catch (e) {
      setError(e.message || 'Chyba při načítání dat')
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!data || data.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}><div style={{ fontSize: 48 }}>🏍️</div><div className="font-bold mt-2">Žádné motorky</div></div>

  const { motoStats, brandStats } = data

  return (
    <div>
      {/* Ranking table */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Ranking motorek podle revenue</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Model', 'Značka', 'Kategorie', 'Pronajato dní', 'Revenue', 'Obsazenost %', 'Avg Kč/den'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {motoStats.map((m, i) => (
              <tr key={m.id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent', transition: 'background .15s' }}
                onMouseEnter={e => { e.currentTarget.style.background = '#f0faf4' }}
                onMouseLeave={e => { e.currentTarget.style.background = i % 2 === 1 ? '#f9fdfb' : 'transparent' }}>
                <td className="py-2 px-3 font-semibold">{m.model}</td>
                <td className="py-2 px-3">{m.brand}</td>
                <td className="py-2 px-3">{m.category}</td>
                <td className="py-2 px-3">{m.rentedDays}</td>
                <td className="py-2 px-3">{Math.round(m.revenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3" style={{ minWidth: 120 }}>
                  <div className="flex items-center gap-2">
                    <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}>
                      <div style={{ width: `${Math.min(m.utilizationIndex, 100)}%`, height: '100%', borderRadius: 4, background: '#74FB71' }} />
                    </div>
                    <span style={{ fontSize: 11, minWidth: 40 }}>{m.utilizationIndex.toFixed(1)}%</span>
                  </div>
                </td>
                <td className="py-2 px-3">{Math.round(m.avgDailyRate).toLocaleString('cs-CZ')} Kč</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Brand table */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Výkon značek</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Značka', 'Počet motorek', 'Průměrná obsazenost %', 'Revenue/motorku', 'Performance Score'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {brandStats.map(b => {
              const sc = b.performanceScore
              const dotColor = sc > 0.6 ? '#22c55e' : sc >= 0.3 ? '#eab308' : '#dc2626'
              return (
                <tr key={b.brand} style={{ borderBottom: '1px solid #f3f4f6' }}>
                  <td className="py-2 px-3 font-semibold">{b.brand}</td>
                  <td className="py-2 px-3">{b.count}</td>
                  <td className="py-2 px-3">{b.avgUtilization.toFixed(1)} %</td>
                  <td className="py-2 px-3">{Math.round(b.revenuePerMoto).toLocaleString('cs-CZ')} Kč</td>
                  <td className="py-2 px-3">
                    <span className="flex items-center gap-2">
                      <span style={{ width: 10, height: 10, borderRadius: '50%', background: dotColor, display: 'inline-block' }} />
                      {sc.toFixed(2)}
                    </span>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}

const CATEGORY_COLORS = ['#74FB71', '#22c55e', '#16a34a', '#15803d', '#166534', '#14532d']
const CATEGORIES = ['adventure', 'naked', 'sport', 'touring', 'retro', 'A2']

function PoptavkaKategorii() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [data, setData] = useState(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      const [mRes, bRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, daily_rate, purchase_price, location_id, status'),
        supabase.from('bookings').select('motorcycle_id, start_date, end_date, total_price, status'),
      ])
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error

      const motorcycles = mRes.data || []
      const bookings = bRes.data || []
      const completed = bookings.filter(b => b.status === 'completed')

      // Build moto lookup for category
      const motoMap = {}
      for (const m of motorcycles) motoMap[m.id] = m

      const catStats = CATEGORIES.map(cat => {
        const catMotos = motorcycles.filter(m => (m.category || '').toLowerCase() === cat.toLowerCase())
        const motorcycleCount = catMotos.length
        const catMotoIds = new Set(catMotos.map(m => m.id))
        const catCompleted = completed.filter(b => catMotoIds.has(b.motorcycle_id))
        const totalRevenue = catCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const revenuePerMoto = motorcycleCount > 0 ? totalRevenue / motorcycleCount : 0
        const totalRentedDays = catCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
        const avgUtilization = motorcycleCount > 0 ? (totalRentedDays / (motorcycleCount * 365)) * 100 : 0
        return { category: cat, motorcycleCount, totalRevenue, revenuePerMoto, avgUtilization }
      }).sort((a, b) => b.avgUtilization - a.avgUtilization)

      setData({ catStats, motorcycles })
    } catch (e) {
      setError(e.message || 'Chyba při načítání dat')
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!data || data.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}><div style={{ fontSize: 48 }}>🏍️</div><div className="font-bold mt-2">Žádné motorky</div></div>

  const { catStats } = data
  const pieData = catStats.filter(c => c.totalRevenue > 0).map(c => ({ name: c.category, value: c.totalRevenue }))
  const barData = catStats.map(c => ({ name: c.category, utilization: Math.round(c.avgUtilization * 10) / 10 }))

  return (
    <div>
      {/* Category table */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Poptávka podle kategorií</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Kategorie', 'Počet motorek', 'Obsazenost %', 'Revenue celkem', 'Revenue/motorku'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {catStats.map(c => (
              <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{c.category}</td>
                <td className="py-2 px-3">{c.motorcycleCount}</td>
                <td className="py-2 px-3">{c.avgUtilization.toFixed(1)} %</td>
                <td className="py-2 px-3">{Math.round(c.totalRevenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{Math.round(c.revenuePerMoto).toLocaleString('cs-CZ')} Kč</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Donut chart */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Podíl revenue podle kategorie</div>
        <ResponsiveContainer width="100%" height={260}>
          <PieChart>
            <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={55} outerRadius={100} paddingAngle={2}>
              {pieData.map((_, i) => <Cell key={i} fill={CATEGORY_COLORS[i % CATEGORY_COLORS.length]} />)}
            </Pie>
            <Tooltip formatter={v => [`${Number(v).toLocaleString('cs-CZ')} Kč`, 'Revenue']} />
            <Legend layout="vertical" align="right" verticalAlign="middle" />
          </PieChart>
        </ResponsiveContainer>
      </div>

      {/* Bar chart */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Obsazenost podle kategorie</div>
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={barData}>
            <XAxis dataKey="name" tick={{ fontSize: 11 }} />
            <YAxis domain={[0, 100]} tick={{ fontSize: 11 }} tickFormatter={v => `${v}%`} />
            <Tooltip formatter={v => [`${v} %`, 'Obsazenost']} />
            <Bar dataKey="utilization" fill="#74FB71" radius={[6, 6, 0, 0]} label={{ position: 'top', fontSize: 11, formatter: v => `${v}%` }} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

const TOTAL_SLOTS = 8

function computeOptimalFleet(catScores) {
  // Filter categories with utilization > 40%
  const eligible = catScores.filter(c => c.utilizationPct > 40).sort((a, b) => b.score - a.score)
  if (eligible.length === 0) return catScores.map(c => ({ ...c, recommended: 0 }))

  const totalScore = eligible.reduce((s, c) => s + c.score, 0)
  // Proportional allocation
  let slots = eligible.map(c => {
    const raw = totalScore > 0 ? (c.score / totalScore) * TOTAL_SLOTS : 0
    return { ...c, rawSlots: raw, recommended: Math.max(1, Math.floor(raw)) }
  })

  let assigned = slots.reduce((s, c) => s + c.recommended, 0)
  // Distribute remaining slots to highest fractional parts
  const remaining = TOTAL_SLOTS - assigned
  if (remaining > 0) {
    const fractions = slots.map((c, i) => ({ i, frac: c.rawSlots - Math.floor(c.rawSlots) })).sort((a, b) => b.frac - a.frac)
    for (let r = 0; r < remaining && r < fractions.length; r++) {
      slots[fractions[r].i].recommended++
    }
  }
  // If over-assigned, trim from lowest score
  assigned = slots.reduce((s, c) => s + c.recommended, 0)
  if (assigned > TOTAL_SLOTS) {
    const sorted = [...slots].sort((a, b) => a.score - b.score)
    let excess = assigned - TOTAL_SLOTS
    for (const s of sorted) {
      if (excess <= 0) break
      const trim = Math.min(s.recommended - 1, excess)
      if (trim > 0) { s.recommended -= trim; excess -= trim }
    }
  }

  // Merge back non-eligible with 0
  const slotMap = {}
  for (const s of slots) slotMap[s.category] = s.recommended
  return catScores.map(c => ({ ...c, recommended: slotMap[c.category] || 0 }))
}

function OptimalniFlotila() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [data, setData] = useState(null)
  const [selectedLoc, setSelectedLoc] = useState(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      const [lRes, mRes, bRes] = await Promise.all([
        supabase.from('locations').select('id, name, city, type'),
        supabase.from('motorcycles').select('id, location_id, category, daily_rate, status'),
        supabase.from('bookings').select('motorcycle_id, location_id, start_date, end_date, total_price, status'),
      ])
      if (lRes.error) throw lRes.error
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error

      const locations = lRes.data || []
      const motorcycles = mRes.data || []
      const bookings = bRes.data || []
      const completed = bookings.filter(b => b.status === 'completed')

      // Build moto->location map
      const motoLocMap = {}
      for (const m of motorcycles) motoLocMap[m.id] = m.location_id

      // Compute per-location per-category stats
      const locData = {}
      for (const loc of locations) {
        const locMotos = motorcycles.filter(m => m.location_id === loc.id)
        const locCompleted = completed.filter(b => {
          const mLocId = motoLocMap[b.motorcycle_id]
          return mLocId === loc.id || b.location_id === loc.id
        })

        // Gather unique categories at this location
        const cats = [...new Set(locMotos.map(m => (m.category || '').toLowerCase()).filter(Boolean))]
        const hasBookings = locCompleted.length > 0

        const catScores = cats.map(cat => {
          const catMotos = locMotos.filter(m => (m.category || '').toLowerCase() === cat)
          const motorcycleCount = catMotos.length
          const catMotoIds = new Set(catMotos.map(m => m.id))
          const catCompleted = locCompleted.filter(b => catMotoIds.has(b.motorcycle_id))
          const totalRevenue = catCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
          const rentedDays = catCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
          const utilizationPct = motorcycleCount > 0 ? (rentedDays / (motorcycleCount * 365)) * 100 : 0
          const revenuePerSlot = motorcycleCount > 0 ? totalRevenue / motorcycleCount : 0
          const score = revenuePerSlot * (utilizationPct / 100)
          return { category: cat, motorcycleCount, totalRevenue, utilizationPct, revenuePerSlot, score }
        })

        const optimal = computeOptimalFleet(catScores)

        // Compute current & optimized rev/slot
        const totalMotos = locMotos.length
        const totalRevenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const currentRevPerSlot = totalMotos > 0 ? totalRevenue / totalMotos : 0

        // Optimized rev/slot: weighted by recommended allocation
        let optimizedRevPerSlot = 0
        const totalRecommended = optimal.reduce((s, c) => s + c.recommended, 0)
        if (totalRecommended > 0) {
          optimizedRevPerSlot = optimal.reduce((s, c) => s + c.revenuePerSlot * c.recommended, 0) / totalRecommended
        }

        const potentialAbs = optimizedRevPerSlot - currentRevPerSlot
        const potentialPct = currentRevPerSlot > 0 ? (potentialAbs / currentRevPerSlot) * 100 : 0

        locData[loc.id] = {
          ...loc, catScores: optimal, hasBookings,
          currentRevPerSlot, optimizedRevPerSlot, potentialAbs, potentialPct, totalMotos,
        }
      }

      setData({ locations, locData })
      if (locations.length > 0) setSelectedLoc(locations[0].id)
    } catch (e) {
      setError(e.message || 'Chyba při načítání dat')
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!data || data.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}><div style={{ fontSize: 48 }}>🏢</div><div className="font-bold mt-2">Žádné pobočky</div></div>

  const { locations, locData } = data
  const loc = locData[selectedLoc] || locData[locations[0].id]
  const cats = loc?.catScores || []

  // Diff badges
  const diffs = cats.map(c => {
    const diff = c.recommended - c.motorcycleCount
    if (diff > 0) return { label: `+${diff} ${c.category}`, type: 'add' }
    if (diff < 0) return { label: `${diff} ${c.category}`, type: 'remove' }
    return { label: `= ${c.category}`, type: 'same' }
  })
  const diffColors = { add: { bg: '#dcfce7', color: '#166534' }, remove: { bg: '#fecaca', color: '#991b1b' }, same: { bg: '#f3f4f6', color: '#6b7280' } }

  // Benchmark table
  const benchmark = locations.map(l => locData[l.id]).sort((a, b) => b.potentialPct - a.potentialPct)

  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }

  return (
    <div>
      {/* Location select */}
      <div className="mb-5">
        <select
          value={selectedLoc || ''}
          onChange={e => setSelectedLoc(e.target.value)}
          className="text-sm font-bold"
          style={{
            padding: '8px 14px', borderRadius: 10, border: '2px solid #e5e7eb',
            background: '#fff', color: '#1a2e22', cursor: 'pointer', minWidth: 220,
          }}
        >
          {locations.map(l => <option key={l.id} value={l.id}>{l.name} — {l.city}</option>)}
        </select>
      </div>

      {/* Two tables side by side */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-5">
        {/* Current composition */}
        <div style={{ ...cardStyle, overflowX: 'auto' }}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Aktuální složení</div>
          <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                {['Kategorie', 'Počet', 'Obsazenost %', 'Rev/slot/rok'].map(h => (
                  <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {cats.length === 0 && (
                <tr><td colSpan={4} className="py-4 text-center" style={{ color: '#888' }}>Nedostatek dat</td></tr>
              )}
              {cats.map(c => {
                const changed = c.recommended !== c.motorcycleCount
                return (
                  <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6', background: changed ? '#fffbeb' : 'transparent' }}>
                    <td className="py-2 px-3 font-semibold">{c.category}</td>
                    <td className="py-2 px-3">{c.motorcycleCount}</td>
                    <td className="py-2 px-3">{c.utilizationPct.toFixed(1)} %</td>
                    <td className="py-2 px-3">{Math.round(c.revenuePerSlot).toLocaleString('cs-CZ')} Kč</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>

        {/* Recommended composition */}
        <div style={{ ...cardStyle, overflowX: 'auto' }}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Doporučené složení</div>
          <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                {['Kategorie', 'Doporučený počet', 'Odhadovaný Rev/slot/rok'].map(h => (
                  <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {cats.length === 0 && (
                <tr><td colSpan={3} className="py-4 text-center" style={{ color: '#888' }}>Nedostatek dat</td></tr>
              )}
              {cats.map(c => {
                const changed = c.recommended !== c.motorcycleCount
                return (
                  <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6', background: changed ? '#fffbeb' : 'transparent' }}>
                    <td className="py-2 px-3 font-semibold">{c.category}</td>
                    <td className="py-2 px-3">{c.recommended}</td>
                    <td className="py-2 px-3">{Math.round(c.revenuePerSlot).toLocaleString('cs-CZ')} Kč</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Diff badges */}
      <div className="flex flex-wrap gap-2 mb-5">
        {diffs.map((d, i) => (
          <span key={i} style={{
            background: diffColors[d.type].bg, color: diffColors[d.type].color,
            borderRadius: 8, padding: '4px 12px', fontSize: 12, fontWeight: 700,
          }}>{d.label}</span>
        ))}
      </div>

      {/* Key metric card */}
      <div style={{
        background: '#1a2e22', borderRadius: 14, padding: '24px 20px', marginBottom: 24,
        display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 16,
      }}>
        <div>
          <div className="text-xs font-bold uppercase mb-1" style={{ color: 'rgba(255,255,255,.5)' }}>Aktuální rev/slot/rok</div>
          <div className="text-2xl font-extrabold" style={{ color: '#74FB71' }}>
            {Math.round(loc.currentRevPerSlot).toLocaleString('cs-CZ')} Kč
          </div>
        </div>
        <div>
          <div className="text-xs font-bold uppercase mb-1" style={{ color: 'rgba(255,255,255,.5)' }}>Optimalizovaný rev/slot/rok</div>
          <div className="text-2xl font-extrabold" style={{ color: '#74FB71' }}>
            {Math.round(loc.optimizedRevPerSlot).toLocaleString('cs-CZ')} Kč
          </div>
        </div>
        <div>
          <div className="text-xs font-bold uppercase mb-1" style={{ color: 'rgba(255,255,255,.5)' }}>Potenciál</div>
          <div className="text-2xl font-extrabold" style={{ color: '#74FB71' }}>
            +{Math.round(loc.potentialAbs).toLocaleString('cs-CZ')} Kč
            <span className="text-sm ml-2" style={{ color: 'rgba(255,255,255,.6)' }}>/ +{loc.potentialPct.toFixed(1)}%</span>
          </div>
        </div>
      </div>

      {/* Benchmark table */}
      <div style={{ ...cardStyle, overflowX: 'auto' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Benchmark všech poboček</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Pobočka', 'Typ', 'Aktuální rev/slot', 'Optimalizovaný rev/slot', 'Potenciál růstu %'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {benchmark.map(b => (
              <tr key={b.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{b.name}</td>
                <td className="py-2 px-3">
                  <span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 11, fontWeight: 700 }}>
                    {b.type || '—'}
                  </span>
                </td>
                {!b.hasBookings ? (
                  <td colSpan={3} className="py-2 px-3" style={{ color: '#888' }}>Nedostatek dat</td>
                ) : (
                  <>
                    <td className="py-2 px-3">{Math.round(b.currentRevPerSlot).toLocaleString('cs-CZ')} Kč</td>
                    <td className="py-2 px-3">{Math.round(b.optimizedRevPerSlot).toLocaleString('cs-CZ')} Kč</td>
                    <td className="py-2 px-3 font-bold" style={{ color: b.potentialPct > 0 ? '#166534' : '#888' }}>
                      {b.potentialPct > 0 ? '+' : ''}{b.potentialPct.toFixed(1)} %
                    </td>
                  </>
                )}
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
      {tab === 'Výkon motorek' && <VykonMotorek />}
      {tab === 'Poptávka kategorií' && <PoptavkaKategorii />}
      {tab === 'Optimální flotila' && <OptimalniFlotila />}
      {!['Výkon poboček', 'Výkon motorek', 'Poptávka kategorií', 'Optimální flotila'].includes(tab) && (
        <div className="p-8 text-center" style={{ color: '#888' }}>
          <div style={{ fontSize: 48 }}>📊</div>
          <div className="font-bold mt-2">Sekce se připravuje</div>
        </div>
      )}
    </div>
  )
}
