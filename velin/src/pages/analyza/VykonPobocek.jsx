import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { calcBikeEconomics } from '../../lib/fleetCalc'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'

function classifyGrowth(cur, prev) {
  if (!prev || !cur) return 'Nedostatek dat'
  const ch = ((cur - prev) / prev) * 100
  if (ch > 10) return 'Rostoucí'
  if (ch < -5) return 'Klesající'
  if (ch >= -5 && ch <= 5) return 'Stagnující'
  return 'Nedostatek dat'
}

const classColors = {
  'Rostoucí': { bg: '#dcfce7', color: '#166534' },
  'Stagnující': { bg: '#fef9c3', color: '#854d0e' },
  'Klesající': { bg: '#fecaca', color: '#991b1b' },
  'Nedostatek dat': { bg: '#f3f4f6', color: '#6b7280' },
}

const NoData = () => (
  <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
    <div style={{ fontSize: 32 }}>⏳</div>
    <div className="font-bold mt-2">Nedostatek dat pro analýzu</div>
    <div className="mt-1">Pro zobrazení závěrů jsou potřeba data alespoň za 3 měsíce zpětně.</div>
  </div>
)

export default function VykonPobocek() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [bRes, mRes, lRes] = await Promise.all([
        supabase.from('bookings').select('id, moto_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('motorcycles').select('id, branch_id, model, category, brand, status'),
        supabase.from('branches').select('id, name, city, type'),
      ])
      if (bRes.error) throw bRes.error
      if (mRes.error) throw mRes.error
      if (lRes.error) throw lRes.error
      setRaw({ bookings: bRes.data || [], motorcycles: mRes.data || [], locations: lRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné pobočky</div>

  const { bookings, motorcycles, locations } = raw
  const completed = filterByPeriod(bookings.filter(b => b.status === 'completed'), period, 'created_at')
  const has3mo = hasMinimumData(bookings)

  const motoBranchMap = {}
  for (const m of motorcycles) motoBranchMap[m.id] = m.branch_id

  // Determine period days for utilization calc
  let periodDays = 365
  if (period.type === 'month') periodDays = new Date(period.year, period.month + 1, 0).getDate()
  else if (period.type === 'custom' && period.from && period.to) periodDays = Math.max(1, diffDays(period.from, period.to))

  const now = new Date()
  const branchStats = locations.map(loc => {
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id)
    const locMotoIds = new Set(locMotos.map(m => m.id))
    const locCompleted = completed.filter(b => locMotoIds.has(b.moto_id))
    const revenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const reservationCount = locCompleted.length
    const motorcycleCount = locMotos.length
    const revenuePerMoto = motorcycleCount > 0 ? revenue / motorcycleCount : 0

    const days = locCompleted.map(b => diffDays(b.start_date, b.end_date))
    const avgDays = days.length > 0 ? days.reduce((a, b) => a + b, 0) / days.length : 0
    const totalRentedDays = days.reduce((a, b) => a + b, 0)
    const utilizationPct = motorcycleCount > 0 ? (totalRentedDays / (motorcycleCount * periodDays)) * 100 : 0

    // Profit estimate per bike
    let avgProfitPerBike = null
    if (locMotos.length > 0) {
      let profitSum = 0, profitCount = 0
      for (const m of locMotos) {
        const mBookings = locCompleted.filter(b => b.moto_id === m.id)
        const rented = mBookings.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
        const realUtil = rented / periodDays
        const econ = calcBikeEconomics(m.category, loc.type || 'turistická', realUtil)
        if (econ) { profitSum += econ.annualProfit; profitCount++ }
      }
      if (profitCount > 0) avgProfitPerBike = profitSum / profitCount
    }

    // Classification: compare current period to previous period (only if enough data)
    let classification = 'Nedostatek dat'
    if (has3mo && period.type === 'month') {
      const thisM = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
      const prevCompleted = filterByPeriod(
        bookings.filter(b => b.status === 'completed'),
        { type: 'month', year: period.month === 0 ? period.year - 1 : period.year, month: period.month === 0 ? 11 : period.month - 1 },
        'created_at'
      ).filter(b => locMotoIds.has(b.moto_id))
      const prevM = prevCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
      classification = classifyGrowth(thisM, prevM)
    } else if (has3mo) {
      const thisYear = now.getFullYear()
      const thisMonth = now.getMonth()
      const thisMonthRev = bookings.filter(b => b.status === 'completed' && locMotoIds.has(b.moto_id))
        .filter(b => { const d = new Date(b.created_at); return d.getMonth() === thisMonth && d.getFullYear() === thisYear })
        .reduce((s, b) => s + (Number(b.total_price) || 0), 0)
      const lastYearRev = bookings.filter(b => b.status === 'completed' && locMotoIds.has(b.moto_id))
        .filter(b => { const d = new Date(b.created_at); return d.getMonth() === thisMonth && d.getFullYear() === thisYear - 1 })
        .reduce((s, b) => s + (Number(b.total_price) || 0), 0)
      classification = classifyGrowth(thisMonthRev, lastYearRev)
    }

    return { ...loc, revenue, reservationCount, motorcycleCount, revenuePerMoto, avgDays, utilizationPct, classification, avgProfitPerBike }
  })

  const totalRevenue = branchStats.reduce((s, b) => s + b.revenue, 0)
  const totalReservations = branchStats.reduce((s, b) => s + b.reservationCount, 0)
  const allDays = completed.map(b => diffDays(b.start_date, b.end_date))
  const avgDaysTotal = allDays.length > 0 ? allDays.reduce((a, b) => a + b, 0) / allDays.length : 0
  const totalMotos = motorcycles.length
  const totalRented = allDays.reduce((a, b) => a + b, 0)
  const avgUtilization = totalMotos > 0 ? (totalRented / (totalMotos * periodDays)) * 100 : 0

  const typeMap = {}
  for (const b of branchStats) {
    const t = b.type || 'Neznámý'
    if (!typeMap[t]) typeMap[t] = { type: t, count: 0, totalRevenue: 0, totalUtilization: 0 }
    typeMap[t].count++
    typeMap[t].totalRevenue += b.revenue
    typeMap[t].totalUtilization += b.utilizationPct
  }
  const byType = Object.values(typeMap).map(t => ({ ...t, avgRevenue: t.count > 0 ? t.totalRevenue / t.count : 0, avgUtilization: t.count > 0 ? t.totalUtilization / t.count : 0 }))
  const chartData = [...branchStats].sort((a, b) => b.revenue - a.revenue).map(b => ({ name: b.name, revenue: b.revenue }))

  const kpis = [
    { label: 'Celkový obrat', value: `${Math.round(totalRevenue).toLocaleString('cs-CZ')} Kč` },
    { label: 'Počet rezervací', value: totalReservations },
    { label: 'Prům. délka pronájmu', value: `${avgDaysTotal.toFixed(1)} dní` },
    { label: 'Prům. obsazenost', value: `${avgUtilization.toFixed(1)} %` },
  ]

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />
      {completed.length === 0 && <div className="p-4 text-center mb-4" style={{ background: '#f3f4f6', borderRadius: 14, color: '#6b7280' }}>Žádné dokončené rezervace pro vybrané období</div>}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {kpis.map(k => (
          <div key={k.label} style={{ background: '#fff', borderRadius: 14, padding: '20px 16px', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
            <div className="text-xl font-extrabold" style={{ color: '#166534' }}>{k.value}</div>
            <div className="text-xs mt-1" style={{ color: '#888' }}>{k.label}</div>
          </div>
        ))}
      </div>

      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Název', 'Typ', 'Obrat', 'Obrat/motorku', 'Zisk/motorku', 'Rezervace', 'Obsazenost %', has3mo ? 'Klasifikace' : null].filter(Boolean).map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {branchStats.map(b => (
              <tr key={b.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{b.name}</td>
                <td className="py-2 px-3">
                  <span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 11, fontWeight: 700 }}>{b.type || '—'}</span>
                  {!b.type && <span className="text-xs ml-1" style={{ color: '#dc2626' }}>⚠️</span>}
                </td>
                <td className="py-2 px-3">{Math.round(b.revenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{Math.round(b.revenuePerMoto).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{b.avgProfitPerBike != null ? `${Math.round(b.avgProfitPerBike).toLocaleString('cs-CZ')} Kč` : '—'}</td>
                <td className="py-2 px-3">{b.reservationCount}</td>
                <td className="py-2 px-3">{b.utilizationPct.toFixed(1)} %</td>
                {has3mo && (
                  <td className="py-2 px-3">
                    <span style={{ background: classColors[b.classification]?.bg, color: classColors[b.classification]?.color, borderRadius: 8, padding: '2px 10px', fontSize: 11, fontWeight: 700 }}>{b.classification}</span>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {!has3mo && <NoData />}

      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Obrat poboček</div>
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={chartData}>
            <XAxis dataKey="name" tick={{ fontSize: 11 }} />
            <YAxis tickFormatter={v => `${(v / 1000).toFixed(0)}tis`} tick={{ fontSize: 11 }} />
            <Tooltip formatter={v => [`${Number(v).toLocaleString('cs-CZ')} Kč`, 'Obrat']} />
            <Bar dataKey="revenue" fill="#74FB71" radius={[6, 6, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>

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
