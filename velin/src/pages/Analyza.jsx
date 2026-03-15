import { useState, useEffect } from 'react'
import { debugLog } from '../lib/debugLog'
import { supabase } from '../lib/supabase'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'

const TABS = ['Výkon poboček', 'Výkon motorek', 'Poptávka kategorií', 'Optimální flotila', 'Doporučení přesunů', 'Doporučení lokací']

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

function DoporuceniPresunu() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [data, setData] = useState(null)
  const [planned, setPlanned] = useState(() => {
    try { return JSON.parse(localStorage.getItem('velin_relocations') || '[]') } catch { return [] }
  })
  const [bulkPlanned, setBulkPlanned] = useState(() => {
    try { return JSON.parse(localStorage.getItem('velin_bulk_relocations') || '[]') } catch { return [] }
  })

  useEffect(() => { loadData() }, [])

  function togglePlan(motoId, targetLocId) {
    const key = `${motoId}_${targetLocId}`
    let next
    if (planned.includes(key)) {
      next = planned.filter(k => k !== key)
    } else {
      next = [...planned, key]
    }
    setPlanned(next)
    localStorage.setItem('velin_relocations', JSON.stringify(next))
  }

  function toggleBulkPlan(category, fromLocationId, toLocationId, count) {
    const key = `${category}_${fromLocationId}_${toLocationId}`
    const exists = bulkPlanned.find(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` === key)
    let next
    if (exists) {
      next = bulkPlanned.filter(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` !== key)
    } else {
      next = [...bulkPlanned, { category, fromLocationId, toLocationId, count, plannedAt: new Date().toISOString() }]
    }
    setBulkPlanned(next)
    localStorage.setItem('velin_bulk_relocations', JSON.stringify(next))
  }

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      const [mRes, bRes, lRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, location_id, daily_rate, purchase_price, status'),
        supabase.from('bookings').select('motorcycle_id, location_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('locations').select('id, name, type'),
      ])
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error
      if (lRes.error) throw lRes.error

      const motorcycles = mRes.data || []
      const bookings = bRes.data || []
      const locations = lRes.data || []
      const completed = bookings.filter(b => b.status === 'completed')

      const locMap = {}
      for (const l of locations) locMap[l.id] = l

      // Moto location lookup
      const motoLocLookup = {}
      for (const m of motorcycles) motoLocLookup[m.id] = m.location_id

      // Per-moto stats
      const motoStats = motorcycles.map(m => {
        const mCompleted = completed.filter(b => b.motorcycle_id === m.id)
        const rentedDays = mCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
        const revenue = mCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const reservationCount = mCompleted.length
        const utilization = rentedDays / 365
        const purchasePrice = Number(m.purchase_price) || 0
        const annualCosts = purchasePrice * 0.20
        const roi = purchasePrice > 0 ? (revenue - annualCosts) / purchasePrice : 0
        return { ...m, rentedDays, revenue, reservationCount, utilization, purchasePrice, roi }
      })

      // Per location×category avg utilization
      const locCatUtil = {}
      for (const m of motoStats) {
        const cat = (m.category || '').toLowerCase()
        const lid = m.location_id
        if (!cat || !lid) continue
        const key = `${lid}_${cat}`
        if (!locCatUtil[key]) locCatUtil[key] = { total: 0, count: 0 }
        locCatUtil[key].total += m.utilization
        locCatUtil[key].count++
      }
      for (const k in locCatUtil) locCatUtil[k].avg = locCatUtil[k].total / locCatUtil[k].count

      // Section A: relocation recommendations
      const relocations = []
      for (const m of motoStats) {
        if (m.utilization >= 0.60) continue
        const cat = (m.category || '').toLowerCase()
        if (!cat) continue

        let bestLoc = null
        let bestUtil = 0
        for (const l of locations) {
          if (l.id === m.location_id) continue
          const key = `${l.id}_${cat}`
          const avg = locCatUtil[key]?.avg || 0
          if (avg > 0.75 && avg > bestUtil) {
            bestLoc = l
            bestUtil = avg
          }
        }
        if (bestLoc) {
          const fromLoc = locMap[m.location_id]
          const diffPp = Math.round((bestUtil - m.utilization) * 100)
          relocations.push({
            motoId: m.id, model: m.model, brand: m.brand, category: cat,
            fromName: fromLoc?.name || '—', fromUtil: m.utilization,
            toName: bestLoc.name, toLocId: bestLoc.id, toUtil: bestUtil, diffPp,
          })
        }
      }

      // Section B: buy score per unique model
      const modelMap = {}
      for (const m of motoStats) {
        const key = `${m.model}_${m.brand}_${(m.category || '').toLowerCase()}`
        if (!modelMap[key]) modelMap[key] = { model: m.model, brand: m.brand, category: (m.category || '').toLowerCase(), count: 0, totalRoi: 0, totalUtil: 0, totalRes: 0, totalRevenue: 0, totalPurchasePrice: 0 }
        modelMap[key].count++
        modelMap[key].totalRoi += m.roi
        modelMap[key].totalUtil += m.utilization
        modelMap[key].totalRes += m.reservationCount
        modelMap[key].totalRevenue += m.revenue
        modelMap[key].totalPurchasePrice += m.purchasePrice
      }
      const buyScores = Object.values(modelMap).map(g => {
        const roi = g.count > 0 ? g.totalRoi / g.count : 0
        const utilization = g.count > 0 ? g.totalUtil / g.count : 0
        const demandIndex = g.count > 0 ? g.totalRes / g.count : 0
        const buyScore = roi * utilization * demandIndex
        let recommendation = 'Neprioritní'
        if (buyScore > 0.4) recommendation = 'Koupit'
        else if (buyScore >= 0.2) recommendation = 'Sledovat'
        return { ...g, roi, utilization, demandIndex, buyScore, recommendation }
      }).sort((a, b) => b.buyScore - a.buyScore).slice(0, 10)

      // Section C: consider retiring
      const retiring = motoStats.filter(m => m.utilization < 0.40 || (m.roi < 0.20 && m.purchasePrice > 0))

      // Section B2: Seasonal relocations
      const SEASON_DAYS = { leto: 92, jaro_podzim: 153, zima: 120 }
      function getSeason(date) {
        const m = new Date(date).getMonth() + 1
        if (m >= 6 && m <= 8) return 'leto'
        if ((m >= 3 && m <= 5) || (m >= 9 && m <= 10)) return 'jaro_podzim'
        return 'zima'
      }

      // Compute per loc×cat×season rented days
      const seasonalMap = {}
      for (const b of completed) {
        const mLocId = motoLocLookup[b.motorcycle_id]
        const lid = b.location_id || mLocId
        const moto = motorcycles.find(mm => mm.id === b.motorcycle_id)
        if (!moto || !lid) continue
        const cat = (moto.category || '').toLowerCase()
        if (!cat) continue
        const season = getSeason(b.start_date || b.created_at)
        const days = diffDays(b.start_date, b.end_date)
        const key = `${lid}_${cat}`
        if (!seasonalMap[key]) seasonalMap[key] = { lid, cat, leto: 0, jaro_podzim: 0, zima: 0 }
        seasonalMap[key][season] += days
      }

      // Compute utilization by season
      const seasonalRows = []
      const seasonalActions = []
      for (const key in seasonalMap) {
        const s = seasonalMap[key]
        const locCatKey = `${s.lid}_${s.cat}`
        const motoCount = locCatUtil[locCatKey]?.count || 0
        if (motoCount === 0) continue
        const utilLeto = motoCount > 0 ? s.leto / (motoCount * SEASON_DAYS.leto) : 0
        const utilJP = motoCount > 0 ? s.jaro_podzim / (motoCount * SEASON_DAYS.jaro_podzim) : 0
        const utilZima = motoCount > 0 ? s.zima / (motoCount * SEASON_DAYS.zima) : 0
        const utils = { leto: utilLeto, jaro_podzim: utilJP, zima: utilZima }
        const vals = [utilLeto, utilJP, utilZima]
        const maxU = Math.max(...vals)
        const minU = Math.min(...vals)

        let recommendation = 'Stabilní'
        if (maxU > 0.75 && minU < 0.45) {
          const maxSeason = Object.entries(utils).sort((a, b) => b[1] - a[1])[0][0]
          const minSeason = Object.entries(utils).sort((a, b) => a[1] - b[1])[0][0]
          const seasonLabels = { leto: 'léto', jaro_podzim: 'jaro/podzim', zima: 'zimu' }
          if (maxSeason === 'leto') recommendation = 'Posílit léto'
          else if (maxSeason === 'zima') recommendation = 'Přesunout na zimu'
          else recommendation = 'Přesunout na léto'

          const loc = locMap[s.lid]
          if (loc) {
            const emoji = maxSeason === 'leto' ? '🌞 Léto' : maxSeason === 'zima' ? '❄️ Zima' : '🍂 Jaro/Podzim'
            seasonalActions.push(`${emoji}: +${motoCount} ${s.cat} → ${loc.name}`)
          }
        }

        const loc = locMap[s.lid]
        seasonalRows.push({
          locName: loc?.name || '—', cat: s.cat,
          leto: utilLeto, jaro_podzim: utilJP, zima: utilZima,
          recommendation, hasSeasonal: maxU > 0.75 && minU < 0.45,
        })
      }

      // Section C2: Bulk relocations
      const bulkRelocations = []
      const allCats = [...new Set(motorcycles.map(m => (m.category || '').toLowerCase()).filter(Boolean))]
      for (const cat of allCats) {
        const surplus = []
        const deficit = []
        for (const l of locations) {
          const key = `${l.id}_${cat}`
          const entry = locCatUtil[key]
          if (!entry) continue
          const avg = entry.avg || 0
          const count = entry.count || 0
          if (avg < 0.50 && count > 1) surplus.push({ loc: l, avg, count })
          if (avg > 0.80) deficit.push({ loc: l, avg, count })
        }
        if (surplus.length > 0 && deficit.length > 0) {
          for (const s of surplus) {
            for (const d of deficit) {
              const moveCount = Math.floor(s.count / 2)
              if (moveCount > 0) {
                bulkRelocations.push({
                  category: cat,
                  fromLoc: s.loc, fromUtil: s.avg,
                  toLoc: d.loc, toUtil: d.avg,
                  count: moveCount,
                })
              }
            }
          }
        }
      }

      setData({ relocations, buyScores, retiring, motorcycles, seasonalRows, seasonalActions, bulkRelocations, locations })
    } catch (e) {
      setError(e.message || 'Chyba při načítání dat')
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!data || data.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}><div style={{ fontSize: 48 }}>🏍️</div><div className="font-bold mt-2">Žádné motorky</div></div>

  const { relocations, buyScores, retiring, seasonalRows, seasonalActions, bulkRelocations, locations: locs } = data
  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }

  function seasonCellStyle(val) {
    if (val > 0.70) return { background: 'rgba(116,251,113,0.2)', color: '#166534' }
    if (val >= 0.40) return { background: 'rgba(251,191,36,0.15)', color: '#92400e' }
    return { background: 'rgba(220,38,38,0.12)', color: '#991b1b' }
  }

  return (
    <div>
      {/* Section A: Relocations */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Doporučení přesunů</div>
        {relocations.length === 0 ? (
          <div style={{ ...cardStyle, textAlign: 'center', padding: 24 }}>
            <div style={{ fontSize: 36 }}>✅</div>
            <div className="font-bold mt-2" style={{ color: '#166534' }}>Flotila je optimálně rozmístěna</div>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {relocations.map(r => {
              const isPlanned = planned.includes(`${r.motoId}_${r.toLocId}`)
              return (
                <div key={`${r.motoId}_${r.toLocId}`} style={cardStyle}>
                  <div className="font-bold text-sm mb-2" style={{ color: '#1a2e22' }}>
                    {r.model} {r.brand}
                    <span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 10, fontWeight: 700, marginLeft: 8 }}>{r.category}</span>
                  </div>
                  <div className="text-xs mb-1" style={{ color: '#888' }}>
                    Z pobočky: <span className="font-semibold" style={{ color: '#1a2e22' }}>{r.fromName}</span> (utilization: {(r.fromUtil * 100).toFixed(0)}%)
                  </div>
                  <div className="text-xs mb-1" style={{ color: '#888' }}>
                    → Do pobočky: <span className="font-semibold" style={{ color: '#166534' }}>{r.toName}</span> (poptávka: {(r.toUtil * 100).toFixed(0)}%)
                  </div>
                  <div className="text-xs mb-3" style={{ color: '#854d0e' }}>
                    Důvod: Vyšší poptávka o {r.diffPp} procentních bodů
                  </div>
                  <button
                    onClick={() => togglePlan(r.motoId, r.toLocId)}
                    className="text-xs font-bold cursor-pointer"
                    style={{
                      padding: '6px 14px', borderRadius: 8, border: 'none',
                      background: isPlanned ? '#74FB71' : '#f1faf7',
                      color: '#1a2e22',
                    }}
                  >
                    {isPlanned ? '✓ Naplánováno' : '✓ Naplánovat'}
                  </button>
                </div>
              )
            })}
          </div>
        )}
      </div>

      {/* Section B: Seasonal relocations */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Sezónní přesuny</div>
        {seasonalRows.length === 0 ? (
          <div style={{ ...cardStyle, textAlign: 'center', padding: 24, color: '#888' }}>Žádná sezónní data</div>
        ) : (
          <>
            <div style={{ ...cardStyle, overflowX: 'auto', marginBottom: seasonalActions.length > 0 ? 16 : 0 }}>
              <div className="font-bold mb-3 text-sm" style={{ color: '#1a2e22' }}>Sezónní obsazenost podle kategorií</div>
              <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                <thead>
                  <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                    {['Pobočka', 'Kategorie', 'Léto', 'Jaro/Podzim', 'Zima', 'Doporučení'].map(h => (
                      <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {seasonalRows.map((r, i) => (
                    <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                      <td className="py-2 px-3 font-semibold">{r.locName}</td>
                      <td className="py-2 px-3">{r.cat}</td>
                      {['leto', 'jaro_podzim', 'zima'].map(s => (
                        <td key={s} className="py-2 px-3">
                          <span style={{ ...seasonCellStyle(r[s]), borderRadius: 6, padding: '2px 8px', fontSize: 12, fontWeight: 700 }}>
                            {(r[s] * 100).toFixed(0)}%
                          </span>
                        </td>
                      ))}
                      <td className="py-2 px-3 font-bold text-xs" style={{ color: r.hasSeasonal ? '#854d0e' : '#166534' }}>{r.recommendation}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {seasonalActions.length > 0 && (
              <div>
                <div className="text-sm font-bold mb-2" style={{ color: '#1a2e22' }}>Doporučené sezónní akce</div>
                <div className="flex flex-wrap gap-2">
                  {seasonalActions.map((a, i) => (
                    <span key={i} style={{
                      background: '#dcfce7', color: '#166534',
                      borderRadius: 8, padding: '4px 12px', fontSize: 12, fontWeight: 700,
                    }}>{a}</span>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Section C: Bulk relocations */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Hromadné relokace kategorií</div>
        {bulkRelocations.length === 0 ? (
          <div style={{ ...cardStyle, textAlign: 'center', padding: 24 }}>
            <div className="font-bold" style={{ color: '#166534' }}>✅ Žádné hromadné relokace potřeba — kategorie jsou rovnoměrně rozmístěny</div>
          </div>
        ) : (
          <div style={{ ...cardStyle, overflowX: 'auto' }}>
            <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                  {['Kategorie', 'Z pobočky', 'Obsazenost (přebytek)', 'Do pobočky', 'Obsazenost (nedostatek)', 'Počet k přesunu', 'Akce'].map(h => (
                    <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {bulkRelocations.map((r, i) => {
                  const bKey = `${r.category}_${r.fromLoc.id}_${r.toLoc.id}`
                  const isBulkPlanned = bulkPlanned.some(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` === bKey)
                  return (
                    <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                      <td className="py-2 px-3 font-semibold">{r.category}</td>
                      <td className="py-2 px-3">{r.fromLoc.name}</td>
                      <td className="py-2 px-3">{(r.fromUtil * 100).toFixed(1)}%</td>
                      <td className="py-2 px-3">{r.toLoc.name}</td>
                      <td className="py-2 px-3">{(r.toUtil * 100).toFixed(1)}%</td>
                      <td className="py-2 px-3 font-bold">{r.count}</td>
                      <td className="py-2 px-3">
                        <button
                          onClick={() => toggleBulkPlan(r.category, r.fromLoc.id, r.toLoc.id, r.count)}
                          className="text-xs font-bold cursor-pointer"
                          style={{
                            padding: '5px 12px', borderRadius: 8, border: 'none',
                            background: isBulkPlanned ? '#e5e7eb' : '#f1faf7',
                            color: isBulkPlanned ? '#6b7280' : '#1a2e22',
                          }}
                        >
                          {isBulkPlanned ? '✓ Naplánováno' : 'Naplánovat'}
                        </button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Section D: Buy Score */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Top kandidáti na dokoupení</div>
        <div style={{ ...cardStyle, overflowX: 'auto' }}>
          <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                {['Model', 'Značka', 'Kategorie', 'ROI', 'Utilization', 'Demand Index', 'Buy Score', 'Doporučení'].map(h => (
                  <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {buyScores.map((b, i) => {
                const scoreColor = b.buyScore > 0.4 ? '#166534' : b.buyScore >= 0.2 ? '#854d0e' : '#991b1b'
                const scoreBg = b.buyScore > 0.4 ? '#dcfce7' : b.buyScore >= 0.2 ? '#fef9c3' : '#fecaca'
                return (
                  <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                    <td className="py-2 px-3 font-semibold">{b.model}</td>
                    <td className="py-2 px-3">{b.brand}</td>
                    <td className="py-2 px-3">{b.category}</td>
                    <td className="py-2 px-3">{(b.roi * 100).toFixed(1)}%</td>
                    <td className="py-2 px-3">{(b.utilization * 100).toFixed(1)}%</td>
                    <td className="py-2 px-3">{b.demandIndex.toFixed(2)}</td>
                    <td className="py-2 px-3">
                      <span style={{ background: scoreBg, color: scoreColor, borderRadius: 8, padding: '2px 10px', fontSize: 11, fontWeight: 700 }}>
                        {b.buyScore.toFixed(3)}
                      </span>
                    </td>
                    <td className="py-2 px-3 font-bold" style={{ color: scoreColor }}>{b.recommendation}</td>
                  </tr>
                )
              })}
              {buyScores.length === 0 && (
                <tr><td colSpan={8} className="py-4 text-center" style={{ color: '#888' }}>Žádné modely k hodnocení</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Section C: Consider retiring */}
      <div>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Zvažte vyřazení</div>
        {retiring.length === 0 ? (
          <div style={{ ...cardStyle, textAlign: 'center', padding: 24 }}>
            <div className="font-bold" style={{ color: '#166534' }}>Žádné motorky k vyřazení</div>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {retiring.map(m => (
              <div key={m.id} style={{
                background: '#fffbeb', borderRadius: 14, padding: '14px 18px',
                border: '1px solid #fde68a', boxShadow: '0 1px 4px rgba(0,0,0,.04)',
              }}>
                <span className="text-sm font-bold" style={{ color: '#854d0e' }}>
                  ⚠️ {m.model} {m.brand} — Utilization: {(m.utilization * 100).toFixed(1)}%, ROI: {(m.roi * 100).toFixed(1)}% — Zvažte vyřazení z flotily
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

const IDEAL_PORTFOLIO = [
  { type: 'metropolitní centrum', min: 1, max: 2, label: 'Metropolitní centrum' },
  { type: 'městská tranzitní', min: 2, max: 3, label: 'Městská tranzitní' },
  { type: 'turistická', min: 3, max: 4, label: 'Turistická' },
  { type: 'horská', min: 1, max: 2, label: 'Horská' },
  { type: 'rekreační voda', min: 1, max: 2, label: 'Rekreační voda' },
]

const REGION_SUGGESTIONS = {
  'turistická': [
    { region: 'Český Krumlov / Třeboň', reason: 'Vysoká turistická návštěvnost, adventure poptávka' },
    { region: 'Znojmo / Pálava', reason: 'Vinařský turismus, touring kategorie' },
  ],
  'horská': [
    { region: 'Špindlerův Mlýn / Pec pod Sněžkou', reason: 'Sezónní peak léto+zima' },
    { region: 'Železná Ruda / Kvilda', reason: 'Šumava, adventure/enduro' },
  ],
  'rekreační voda': [
    { region: 'Lipno nad Vltavou', reason: 'Největší přehrada ČR, rodinný turismus' },
    { region: 'Máchovo jezero', reason: 'Blízkost Prahy, víkendové výlety' },
  ],
  'metropolitní centrum': [
    { region: 'Praha — Smíchov nebo Holešovice', reason: 'Poblíž vlakových nádraží, vysoká poptávka' },
    { region: 'Brno — Židenice nebo Husovice', reason: 'Druhé největší město, tranzitní hub' },
  ],
  'městská tranzitní': [
    { region: 'Okraj Prahy — D1/D5 koridor', reason: 'Tranzitní bod pro dálkové výlety' },
    { region: 'Ostrava — průjezd do Beskyd', reason: 'Brána do Beskyd a Polska' },
  ],
}

const DEFAULT_FLEET = {
  'turistická': [{ cat: 'adventure', n: 4 }, { cat: 'touring', n: 2 }, { cat: 'naked', n: 1 }, { cat: 'sport', n: 1 }],
  'horská': [{ cat: 'adventure', n: 4 }, { cat: 'enduro', n: 2 }, { cat: 'touring', n: 1 }, { cat: 'sport', n: 1 }],
  'rekreační voda': [{ cat: 'adventure', n: 3 }, { cat: 'touring', n: 2 }, { cat: 'naked', n: 2 }, { cat: 'retro', n: 1 }],
  'metropolitní centrum': [{ cat: 'naked', n: 3 }, { cat: 'A2', n: 2 }, { cat: 'sport', n: 2 }, { cat: 'touring', n: 1 }],
  'městská tranzitní': [{ cat: 'naked', n: 3 }, { cat: 'A2', n: 2 }, { cat: 'sport', n: 2 }, { cat: 'adventure', n: 1 }],
}

function resolveLocationType(environment, distance, seasonality) {
  if (environment === 'Centrum města' && distance === 'Do 50 km') return 'metropolitní centrum'
  if (environment === 'Okraj města' && distance === 'Do 50 km') return 'městská tranzitní'
  if (environment === 'Turistická oblast' && (seasonality === 'Převážně zima' || seasonality === 'Léto + zima')) return 'horská'
  if (environment === 'Turistická oblast') return 'turistická'
  if (environment === 'Hory') return 'horská'
  if (environment === 'Přehrada/jezero') return 'rekreační voda'
  if (environment === 'Průmyslová zóna') return 'městská tranzitní'
  if (environment === 'Centrum města') return 'metropolitní centrum'
  if (environment === 'Okraj města') return 'městská tranzitní'
  return 'turistická'
}

function resolveFleet(locType) {
  return DEFAULT_FLEET[locType] || DEFAULT_FLEET['turistická']
}

function resolveRisk(seasonality) {
  if (seasonality === 'Převážně léto') return 'Nízká zimní obsazenost — zvažte sezónní přesuny'
  if (seasonality === 'Převážně zima') return 'Nízká letní obsazenost — zvažte doplnění touring kategorií'
  if (seasonality === 'Léto + zima') return 'Slabé jaro/podzim — zvažte promo akce v přechodných měsících'
  return 'Celoroční provoz — udržujte rovnoměrné pokrytí kategorií'
}

function DoporuceniLokaci() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [data, setData] = useState(null)
  // Calculator state
  const [calcEnv, setCalcEnv] = useState('Centrum města')
  const [calcDist, setCalcDist] = useState('Do 50 km')
  const [calcSeason, setCalcSeason] = useState('Celoroční')
  const [calcResult, setCalcResult] = useState(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      const [lRes, bRes, mRes] = await Promise.all([
        supabase.from('locations').select('id, name, city, type'),
        supabase.from('bookings').select('location_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('motorcycles').select('location_id, category, status'),
      ])
      if (lRes.error) throw lRes.error
      if (bRes.error) throw bRes.error
      if (mRes.error) throw mRes.error

      const locations = lRes.data || []
      const bookings = bRes.data || []
      const motorcycles = mRes.data || []
      const completed = bookings.filter(b => b.status === 'completed')

      // Per-location stats
      const locStats = locations.map(loc => {
        const locMotos = motorcycles.filter(m => m.location_id === loc.id)
        const locCompleted = completed.filter(b => b.location_id === loc.id)
        const revenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
        const rentedDays = locCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
        const motoCount = locMotos.length
        const utilizationPct = motoCount > 0 ? (rentedDays / (motoCount * 365)) * 100 : 0
        const revPerSlot = motoCount > 0 ? revenue / motoCount : 0
        return { ...loc, revenue, motoCount, utilizationPct, revPerSlot }
      }).sort((a, b) => b.revenue - a.revenue)

      // Avg rev/slot across all
      const totalRevenue = locStats.reduce((s, l) => s + l.revenue, 0)
      const totalMotos = locStats.reduce((s, l) => s + l.motoCount, 0)
      const avgRevPerSlot = totalMotos > 0 ? totalRevenue / totalMotos : 0
      const avgUtil = locStats.length > 0 ? locStats.reduce((s, l) => s + l.utilizationPct, 0) / locStats.length : 0

      // Star rating (1-5) based on revPerSlot vs average
      for (const l of locStats) {
        if (avgRevPerSlot === 0) { l.stars = 3; continue }
        const ratio = l.revPerSlot / avgRevPerSlot
        if (ratio >= 1.5) l.stars = 5
        else if (ratio >= 1.2) l.stars = 4
        else if (ratio >= 0.8) l.stars = 3
        else if (ratio >= 0.5) l.stars = 2
        else l.stars = 1
      }

      // Type counts
      const typeCounts = {}
      for (const l of locations) {
        const t = (l.type || '').toLowerCase()
        typeCounts[t] = (typeCounts[t] || 0) + 1
      }

      // Avg revenue by type for estimation
      const typeRevenue = {}
      for (const l of locStats) {
        const t = (l.type || '').toLowerCase()
        if (!typeRevenue[t]) typeRevenue[t] = { total: 0, count: 0 }
        typeRevenue[t].total += l.revenue
        typeRevenue[t].count++
      }
      const avgRevenueByType = {}
      for (const t in typeRevenue) {
        avgRevenueByType[t] = typeRevenue[t].count > 0 ? typeRevenue[t].total / typeRevenue[t].count : 0
      }

      setData({ locStats, totalRevenue, avgUtil, typeCounts, avgRevenueByType, locations })
    } catch (e) {
      setError(e.message || 'Chyba při načítání dat')
    } finally {
      setLoading(false)
    }
  }

  function handleCalc() {
    const locType = resolveLocationType(calcEnv, calcDist, calcSeason)
    const fleet = resolveFleet(locType)
    const risk = resolveRisk(calcSeason)
    const estRevenue = data?.avgRevenueByType[locType] || data?.avgRevenueByType[Object.keys(data?.avgRevenueByType || {})[0]] || 0
    const topCats = fleet.slice(0, 3).map(f => f.cat)
    const label = IDEAL_PORTFOLIO.find(p => p.type === locType)?.label || locType
    setCalcResult({ locType, label, fleet, risk, estRevenue, topCats })
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!data || data.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}><div style={{ fontSize: 48 }}>🏢</div><div className="font-bold mt-2">Žádné pobočky</div></div>

  const { locStats, totalRevenue, avgUtil, typeCounts, avgRevenueByType } = data
  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
  const selectStyle = {
    padding: '8px 14px', borderRadius: 10, border: '2px solid #e5e7eb',
    background: '#fff', color: '#1a2e22', cursor: 'pointer', fontSize: 13, fontWeight: 600, minWidth: 180,
  }

  // Missing types analysis
  const missingTypes = IDEAL_PORTFOLIO.map(p => {
    const current = typeCounts[p.type] || 0
    const missing = Math.max(0, p.min - current)
    let priority = 'Nízká'
    if (missing > 1 && (p.type === 'turistická' || p.type === 'horská')) priority = 'Vysoká'
    else if (missing > 0) priority = 'Střední'
    return { ...p, current, missing, priority }
  })

  // Expansion cards for missing types
  const expansionCards = missingTypes.filter(m => m.missing > 0).flatMap(m => {
    const suggestions = REGION_SUGGESTIONS[m.type] || []
    const estRevenue = avgRevenueByType[m.type] || avgRevenueByType[Object.keys(avgRevenueByType)[0]] || 0
    const fleet = DEFAULT_FLEET[m.type] || DEFAULT_FLEET['turistická']
    return suggestions.map(s => ({
      ...s, type: m.type, label: m.label, priority: m.priority, estRevenue, fleet,
    }))
  })

  return (
    <div>
      {/* Section A: Branch performance cards */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-2" style={{ color: '#1a2e22' }}>Mapa stávajících poboček</div>
        <div className="text-sm mb-5" style={{ color: '#888' }}>
          {locStats.length} poboček celkem, průměrná obsazenost {avgUtil.toFixed(1)}%, celkový obrat {Math.round(totalRevenue).toLocaleString('cs-CZ')} Kč
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {locStats.map(l => {
            const status = l.stars >= 4 ? { icon: '🟢', text: 'Výkonná' } : l.stars >= 3 ? { icon: '🟡', text: 'Průměrná' } : { icon: '🔴', text: 'Podvýkonná' }
            return (
              <div key={l.id} style={cardStyle}>
                <div className="flex items-start justify-between mb-2">
                  <div>
                    <div className="font-bold text-sm" style={{ color: '#1a2e22' }}>{l.name}</div>
                    <div className="text-xs" style={{ color: '#888' }}>{l.city}</div>
                  </div>
                  <span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 10, fontWeight: 700 }}>
                    {l.type || '—'}
                  </span>
                </div>
                <div className="text-xl font-extrabold mb-2" style={{ color: '#166534' }}>
                  {Math.round(l.revenue).toLocaleString('cs-CZ')} Kč
                </div>
                <div className="flex items-center gap-2 mb-2">
                  <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}>
                    <div style={{ width: `${Math.min(l.utilizationPct, 100)}%`, height: '100%', borderRadius: 4, background: '#74FB71' }} />
                  </div>
                  <span className="text-xs font-bold" style={{ minWidth: 40 }}>{l.utilizationPct.toFixed(1)}%</span>
                </div>
                <div className="flex items-center justify-between text-xs" style={{ color: '#888' }}>
                  <span>{l.motoCount} motorek</span>
                  <span style={{ letterSpacing: 1 }}>{'⭐'.repeat(l.stars)}{'☆'.repeat(5 - l.stars)}</span>
                  <span>{status.icon} {status.text}</span>
                </div>
              </div>
            )
          })}
        </div>
      </div>

      {/* Section B: Missing types */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Doporučení nových lokalit</div>

        <div style={{ ...cardStyle, overflowX: 'auto', marginBottom: 20 }}>
          <div className="font-bold mb-3 text-sm" style={{ color: '#1a2e22' }}>Chybějící typy poboček</div>
          <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                {['Typ', 'Ideální počet', 'Aktuální počet', 'Chybí', 'Priorita'].map(h => (
                  <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {missingTypes.map(m => {
                const prioStyle = m.priority === 'Vysoká' ? { bg: '#fecaca', color: '#991b1b' } : m.priority === 'Střední' ? { bg: '#fef9c3', color: '#854d0e' } : { bg: '#f3f4f6', color: '#6b7280' }
                return (
                  <tr key={m.type} style={{ borderBottom: '1px solid #f3f4f6' }}>
                    <td className="py-2 px-3 font-semibold">{m.label}</td>
                    <td className="py-2 px-3">{m.min}–{m.max}</td>
                    <td className="py-2 px-3">{m.current}</td>
                    <td className="py-2 px-3 font-bold" style={{ color: m.missing > 0 ? '#991b1b' : '#166534' }}>{m.missing}</td>
                    <td className="py-2 px-3">
                      <span style={{ background: prioStyle.bg, color: prioStyle.color, borderRadius: 8, padding: '2px 10px', fontSize: 11, fontWeight: 700 }}>
                        {m.priority}
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>

        {/* Expansion cards */}
        {expansionCards.length > 0 && (
          <>
            <div className="font-bold mb-3 text-sm" style={{ color: '#1a2e22' }}>Doporučené regiony pro expanzi</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {expansionCards.map((c, i) => (
                <div key={i} style={cardStyle}>
                  <div className="flex items-start justify-between mb-2">
                    <div className="font-bold text-sm" style={{ color: '#1a2e22' }}>{c.region}</div>
                    <span style={{
                      background: c.priority === 'Vysoká' ? '#fecaca' : '#fef9c3',
                      color: c.priority === 'Vysoká' ? '#991b1b' : '#854d0e',
                      borderRadius: 8, padding: '2px 10px', fontSize: 10, fontWeight: 700,
                    }}>
                      {c.priority === 'Vysoká' ? '🔥 Vysoká priorita' : '📍 Středně prioritní'}
                    </span>
                  </div>
                  <div className="text-xs mb-1" style={{ color: '#888' }}>
                    Typ: <span className="font-semibold" style={{ color: '#1a2e22' }}>{c.label}</span>
                  </div>
                  <div className="text-xs mb-2" style={{ color: '#854d0e' }}>{c.reason}</div>
                  <div className="text-sm font-extrabold mb-2" style={{ color: '#166534' }}>
                    Odhad revenue: {Math.round(c.estRevenue).toLocaleString('cs-CZ')} Kč/rok
                  </div>
                  <div className="text-xs mb-1 font-bold" style={{ color: '#1a2e22' }}>Doporučená flotila (8 slotů):</div>
                  <div className="flex flex-wrap gap-1">
                    {c.fleet.map((f, fi) => (
                      <span key={fi} style={{ background: '#f1faf7', color: '#1a2e22', borderRadius: 6, padding: '2px 8px', fontSize: 10, fontWeight: 700 }}>
                        {f.n}× {f.cat}
                      </span>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </div>

      {/* Section C: Location calculator */}
      <div>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Doporučený typ pobočky pro lokalitu</div>
        <div style={cardStyle}>
          <div className="flex flex-wrap gap-4 mb-4">
            <div>
              <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Typ prostředí</div>
              <select value={calcEnv} onChange={e => setCalcEnv(e.target.value)} style={selectStyle}>
                {['Centrum města', 'Okraj města', 'Turistická oblast', 'Hory', 'Přehrada/jezero', 'Průmyslová zóna'].map(o => (
                  <option key={o} value={o}>{o}</option>
                ))}
              </select>
            </div>
            <div>
              <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Vzdálenost od Prahy</div>
              <select value={calcDist} onChange={e => setCalcDist(e.target.value)} style={selectStyle}>
                {['Do 50 km', '50–150 km', 'Nad 150 km'].map(o => (
                  <option key={o} value={o}>{o}</option>
                ))}
              </select>
            </div>
            <div>
              <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Sezónnost</div>
              <select value={calcSeason} onChange={e => setCalcSeason(e.target.value)} style={selectStyle}>
                {['Celoroční', 'Převážně léto', 'Převážně zima', 'Léto + zima'].map(o => (
                  <option key={o} value={o}>{o}</option>
                ))}
              </select>
            </div>
          </div>
          <button
            onClick={handleCalc}
            className="text-sm font-extrabold cursor-pointer"
            style={{ padding: '10px 24px', borderRadius: 10, border: 'none', background: '#74FB71', color: '#1a2e22' }}
          >
            Doporučit typ pobočky
          </button>

          {calcResult && (
            <div className="mt-5" style={{ borderTop: '2px solid #e5e7eb', paddingTop: 16 }}>
              <div className="mb-4">
                <span className="text-sm font-extrabold" style={{
                  background: '#74FB71', color: '#1a2e22', borderRadius: 10, padding: '6px 18px', fontSize: 14,
                }}>
                  {calcResult.label}
                </span>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                <div>
                  <div className="text-xs font-bold mb-2" style={{ color: '#888' }}>Optimální složení flotily (8 motorek)</div>
                  <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                    <tbody>
                      {calcResult.fleet.map((f, i) => (
                        <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                          <td className="py-1 px-2 font-semibold">{f.cat}</td>
                          <td className="py-1 px-2 font-bold" style={{ color: '#166534' }}>{f.n}×</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div>
                  <div className="text-xs font-bold mb-2" style={{ color: '#888' }}>Odhadovaný roční revenue</div>
                  <div className="text-2xl font-extrabold mb-3" style={{ color: '#166534' }}>
                    {Math.round(calcResult.estRevenue).toLocaleString('cs-CZ')} Kč
                  </div>
                  <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Top 3 kategorie</div>
                  <div className="flex gap-2 mb-3">
                    {calcResult.topCats.map((c, i) => (
                      <span key={i} style={{ background: '#dcfce7', color: '#166534', borderRadius: 8, padding: '3px 10px', fontSize: 11, fontWeight: 700 }}>{c}</span>
                    ))}
                  </div>
                  <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Klíčové riziko</div>
                  <div style={{
                    background: '#fffbeb', borderRadius: 10, padding: '8px 12px',
                    border: '1px solid #fde68a', fontSize: 12, color: '#854d0e', fontWeight: 600,
                  }}>
                    ⚠️ {calcResult.risk}
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
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
      {tab === 'Doporučení přesunů' && <DoporuceniPresunu />}
      {tab === 'Doporučení lokací' && <DoporuceniLokaci />}
    </div>
  )
}
