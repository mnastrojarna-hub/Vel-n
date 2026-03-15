import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'

const COLORS = ['#74FB71', '#22c55e', '#16a34a', '#15803d', '#166534', '#14532d', '#0d3520', '#eab308', '#f59e0b', '#dc2626']

export default function PoptavkaKategorii() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [mRes, bRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, purchase_price, branch_id, status'),
        supabase.from('bookings').select('moto_id, start_date, end_date, total_price, status, created_at'),
      ])
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error
      setRaw({ motorcycles: mRes.data || [], bookings: bRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné motorky</div>

  const { motorcycles, bookings } = raw
  const completed = filterByPeriod(bookings.filter(b => b.status === 'completed'), period, 'created_at')

  let periodDays = 365
  if (period.type === 'month') periodDays = new Date(period.year, period.month + 1, 0).getDate()
  else if (period.type === 'custom' && period.from && period.to) periodDays = Math.max(1, diffDays(period.from, period.to))

  // Get actual categories from data
  const categories = [...new Set(motorcycles.map(m => (m.category || '').toLowerCase()).filter(Boolean))]

  const catStats = categories.map(cat => {
    const catMotos = motorcycles.filter(m => (m.category || '').toLowerCase() === cat)
    const motorcycleCount = catMotos.length
    const catMotoIds = new Set(catMotos.map(m => m.id))
    const catCompleted = completed.filter(b => catMotoIds.has(b.moto_id))
    const totalRevenue = catCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const revenuePerMoto = motorcycleCount > 0 ? totalRevenue / motorcycleCount : 0
    const totalRentedDays = catCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
    const avgUtilization = motorcycleCount > 0 ? (totalRentedDays / (motorcycleCount * periodDays)) * 100 : 0
    const reservationCount = catCompleted.length
    return { category: cat, motorcycleCount, totalRevenue, revenuePerMoto, avgUtilization, reservationCount }
  }).sort((a, b) => b.avgUtilization - a.avgUtilization)

  const pieData = catStats.filter(c => c.totalRevenue > 0).map(c => ({ name: c.category, value: c.totalRevenue }))
  const barData = catStats.map(c => ({ name: c.category, utilization: Math.round(c.avgUtilization * 10) / 10 }))

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />
      {completed.length === 0 && <div className="p-4 text-center mb-4" style={{ background: '#f3f4f6', borderRadius: 14, color: '#6b7280' }}>Žádné dokončené rezervace pro vybrané období</div>}

      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Poptávka podle kategorií</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Kategorie', 'Motorek', 'Rezervací', 'Obsazenost %', 'Revenue celkem', 'Revenue/motorku'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {catStats.map(c => (
              <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6' }}>
                <td className="py-2 px-3 font-semibold">{c.category}</td>
                <td className="py-2 px-3">{c.motorcycleCount}</td>
                <td className="py-2 px-3">{c.reservationCount}</td>
                <td className="py-2 px-3">{c.avgUtilization.toFixed(1)} %</td>
                <td className="py-2 px-3">{Math.round(c.totalRevenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{Math.round(c.revenuePerMoto).toLocaleString('cs-CZ')} Kč</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Podíl revenue podle kategorie</div>
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={55} outerRadius={100} paddingAngle={2}>
                {pieData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
              </Pie>
              <Tooltip formatter={v => [`${Number(v).toLocaleString('cs-CZ')} Kč`, 'Revenue']} />
              <Legend layout="vertical" align="right" verticalAlign="middle" />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Obsazenost podle kategorie</div>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={barData}>
              <XAxis dataKey="name" tick={{ fontSize: 11 }} />
              <YAxis domain={[0, 100]} tick={{ fontSize: 11 }} tickFormatter={v => `${v}%`} />
              <Tooltip formatter={v => [`${v} %`, 'Obsazenost']} />
              <Bar dataKey="utilization" fill="#74FB71" radius={[6, 6, 0, 0]} label={{ position: 'top', fontSize: 11, formatter: v => `${v}%` }} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  )
}
