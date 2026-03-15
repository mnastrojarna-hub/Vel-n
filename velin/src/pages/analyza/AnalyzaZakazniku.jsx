import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'

const COLORS = ['#74FB71', '#22c55e', '#16a34a', '#15803d', '#166534', '#14532d', '#eab308', '#f59e0b', '#dc2626', '#7c3aed']

const NoData = () => (
  <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
    <div style={{ fontSize: 32 }}>⏳</div>
    <div className="font-bold mt-2">Nedostatek dat pro závěry</div>
    <div className="mt-1">Pro zobrazení závěrů jsou potřeba data alespoň za 3 měsíce.</div>
  </div>
)

export default function AnalyzaZakazniku() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [pRes, bRes, mRes, iRes] = await Promise.all([
        supabase.from('profiles').select('id, full_name, email, phone, city, date_of_birth, license_group, riding_experience, preferred_branch, created_at'),
        supabase.from('bookings').select('id, user_id, moto_id, start_date, end_date, total_price, status, created_at, rating, booking_source, payment_status'),
        supabase.from('motorcycles').select('id, model, category, branch_id'),
        supabase.from('invoices').select('id, customer_id, total, status, issue_date, type').eq('type', 'issued'),
      ])
      if (pRes.error) throw pRes.error
      if (bRes.error) throw bRes.error
      if (mRes.error) throw mRes.error
      // invoices may fail if table is empty, that's ok
      setRaw({
        profiles: pRes.data || [],
        bookings: bRes.data || [],
        motorcycles: mRes.data || [],
        invoices: iRes.data || [],
      })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.profiles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádní zákazníci</div>

  const { profiles, bookings, motorcycles, invoices } = raw
  const filtered = filterByPeriod(bookings, period, 'created_at')
  const completed = filtered.filter(b => b.status === 'completed')
  const has3mo = hasMinimumData(bookings)

  const motoMap = {}
  for (const m of motorcycles) motoMap[m.id] = m

  // ── KPI ──
  const totalCustomers = profiles.length
  const activeCustomers = new Set(completed.map(b => b.user_id)).size
  const totalRevenue = completed.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
  const avgRevenuePerCustomer = activeCustomers > 0 ? totalRevenue / activeCustomers : 0
  const avgBookingsPerCustomer = activeCustomers > 0 ? completed.length / activeCustomers : 0
  const ratings = completed.filter(b => b.rating > 0).map(b => b.rating)
  const avgRating = ratings.length > 0 ? ratings.reduce((a, b) => a + b, 0) / ratings.length : 0

  // ── Per-customer stats ──
  const customerStats = profiles.map(p => {
    const cb = completed.filter(b => b.user_id === p.id)
    const revenue = cb.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const bookingCount = cb.length
    const avgDays = cb.length > 0 ? cb.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0) / cb.length : 0
    const lastBooking = cb.length > 0 ? cb.sort((a, b) => new Date(b.created_at) - new Date(a.created_at))[0].created_at : null
    const categories = [...new Set(cb.map(b => motoMap[b.moto_id]?.category).filter(Boolean))]
    const pRatings = cb.filter(b => b.rating > 0).map(b => b.rating)
    const avgR = pRatings.length > 0 ? pRatings.reduce((a, b) => a + b, 0) / pRatings.length : null
    return { ...p, revenue, bookingCount, avgDays, lastBooking, categories, avgRating: avgR }
  }).filter(c => c.bookingCount > 0).sort((a, b) => b.revenue - a.revenue)

  // ── Segmentation ──
  const segments = { vip: [], regular: [], occasional: [], inactive: [] }
  for (const c of customerStats) {
    if (c.revenue >= 20000 || c.bookingCount >= 5) segments.vip.push(c)
    else if (c.bookingCount >= 2) segments.regular.push(c)
    else segments.occasional.push(c)
  }
  const inactiveIds = new Set(customerStats.map(c => c.id))
  segments.inactive = profiles.filter(p => !inactiveIds.has(p.id))

  const segmentData = [
    { name: 'VIP', value: segments.vip.length, color: '#74FB71' },
    { name: 'Pravidelní', value: segments.regular.length, color: '#22c55e' },
    { name: 'Příležitostní', value: segments.occasional.length, color: '#eab308' },
    { name: 'Neaktivní', value: segments.inactive.length, color: '#dc2626' },
  ].filter(s => s.value > 0)

  // ── Category preference ──
  const catPref = {}
  for (const c of customerStats) {
    for (const cat of c.categories) {
      catPref[cat] = (catPref[cat] || 0) + 1
    }
  }
  const catPrefData = Object.entries(catPref).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)

  // ── Booking source ──
  const sourceMap = {}
  for (const b of completed) {
    const src = b.booking_source || 'app'
    sourceMap[src] = (sourceMap[src] || 0) + 1
  }
  const sourceData = Object.entries(sourceMap).map(([name, value]) => ({ name, value }))

  // ── New vs returning ──
  const firstBookingMap = {}
  for (const b of bookings.filter(bb => bb.status === 'completed')) {
    if (!firstBookingMap[b.user_id] || new Date(b.created_at) < new Date(firstBookingMap[b.user_id])) {
      firstBookingMap[b.user_id] = b.created_at
    }
  }
  let newCustomers = 0, returningCustomers = 0
  for (const b of completed) {
    const first = firstBookingMap[b.user_id]
    if (first && first === b.created_at) newCustomers++
    else returningCustomers++
  }

  // ── License groups ──
  const licenseMap = {}
  for (const p of profiles) {
    const groups = p.license_group || []
    for (const g of groups) licenseMap[g] = (licenseMap[g] || 0) + 1
  }
  const licenseData = Object.entries(licenseMap).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)

  // ── City distribution ──
  const cityMap = {}
  for (const c of customerStats) {
    const city = c.city || 'Neuvedeno'
    cityMap[city] = (cityMap[city] || 0) + 1
  }
  const cityData = Object.entries(cityMap).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value).slice(0, 10)

  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
  const kpis = [
    { label: 'Zákazníků celkem', value: totalCustomers },
    { label: 'Aktivních (s rezervací)', value: activeCustomers },
    { label: 'Průměrný obrat/zákazník', value: `${Math.round(avgRevenuePerCustomer).toLocaleString('cs-CZ')} Kč` },
    { label: 'Průměr rezervací/zákazník', value: avgBookingsPerCustomer.toFixed(1) },
    { label: 'Průměrné hodnocení', value: avgRating > 0 ? `${avgRating.toFixed(1)} / 5` : '—' },
    { label: 'Nových / vracejících se', value: `${newCustomers} / ${returningCustomers}` },
  ]

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />

      {/* KPIs */}
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
        {kpis.map(k => (
          <div key={k.label} style={{ background: '#fff', borderRadius: 14, padding: '18px 16px', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
            <div className="text-xl font-extrabold" style={{ color: '#166534' }}>{k.value}</div>
            <div className="text-xs mt-1" style={{ color: '#888' }}>{k.label}</div>
          </div>
        ))}
      </div>

      {/* Segments + Category preference */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <div style={cardStyle}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Segmentace zákazníků</div>
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie data={segmentData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={50} outerRadius={90} paddingAngle={2}>
                {segmentData.map((s, i) => <Cell key={i} fill={s.color} />)}
              </Pie>
              <Tooltip />
              <Legend layout="vertical" align="right" verticalAlign="middle" />
            </PieChart>
          </ResponsiveContainer>
          <div className="flex flex-wrap gap-2 mt-3">
            {segmentData.map(s => (
              <span key={s.name} style={{ background: s.color + '22', color: s.color === '#74FB71' ? '#166534' : s.color === '#eab308' ? '#854d0e' : s.color === '#dc2626' ? '#991b1b' : '#166534', borderRadius: 8, padding: '3px 10px', fontSize: 11, fontWeight: 700 }}>
                {s.name}: {s.value}
              </span>
            ))}
          </div>
        </div>

        <div style={cardStyle}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Oblíbené kategorie motorek</div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={catPrefData}>
              <XAxis dataKey="name" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip />
              <Bar dataKey="value" fill="#74FB71" radius={[6, 6, 0, 0]} name="Zákazníků" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Source + License + Cities */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
        <div style={cardStyle}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Zdroj rezervací</div>
          <ResponsiveContainer width="100%" height={180}>
            <PieChart>
              <Pie data={sourceData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={70} paddingAngle={2}>
                {sourceData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
              </Pie>
              <Tooltip />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>

        <div style={cardStyle}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Řidičské průkazy</div>
          {licenseData.length === 0 ? <div className="text-sm" style={{ color: '#888' }}>Žádná data</div> : (
            <div className="space-y-2">
              {licenseData.map(l => (
                <div key={l.name} className="flex items-center gap-2">
                  <span className="text-sm font-bold" style={{ minWidth: 30 }}>{l.name}</span>
                  <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}>
                    <div style={{ width: `${(l.value / totalCustomers) * 100}%`, height: '100%', borderRadius: 4, background: '#74FB71' }} />
                  </div>
                  <span className="text-xs font-bold" style={{ minWidth: 30 }}>{l.value}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        <div style={cardStyle}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Top 10 měst</div>
          {cityData.length === 0 ? <div className="text-sm" style={{ color: '#888' }}>Žádná data</div> : (
            <div className="space-y-1">
              {cityData.map((c, i) => (
                <div key={c.name} className="flex items-center justify-between text-sm">
                  <span className="font-semibold">{i + 1}. {c.name}</span>
                  <span className="font-bold" style={{ color: '#166534' }}>{c.value}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Top customers table */}
      <div style={{ ...cardStyle, overflowX: 'auto', marginBottom: 24 }}>
        <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Top zákazníci podle obratu</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Jméno', 'Město', 'Rezervací', 'Prům. dní', 'Obrat', 'Hodnocení', 'Kategorie', 'Poslední rezervace'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {customerStats.slice(0, 20).map((c, i) => (
              <tr key={c.id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent' }}>
                <td className="py-2 px-3 font-semibold">{c.full_name || c.email || '—'}</td>
                <td className="py-2 px-3">{c.city || '—'}</td>
                <td className="py-2 px-3">{c.bookingCount}</td>
                <td className="py-2 px-3">{c.avgDays.toFixed(1)}</td>
                <td className="py-2 px-3 font-bold" style={{ color: '#166534' }}>{Math.round(c.revenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{c.avgRating != null ? `${c.avgRating.toFixed(1)}` : '—'}</td>
                <td className="py-2 px-3">
                  <div className="flex flex-wrap gap-1">{c.categories.map(cat => <span key={cat} style={{ background: '#f3f4f6', borderRadius: 6, padding: '1px 6px', fontSize: 10, fontWeight: 700 }}>{cat}</span>)}</div>
                </td>
                <td className="py-2 px-3 text-xs">{c.lastBooking ? new Date(c.lastBooking).toLocaleDateString('cs-CZ') : '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {!has3mo && <NoData />}
    </div>
  )
}
