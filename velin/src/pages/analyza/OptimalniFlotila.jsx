import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'

const TOTAL_SLOTS = 8

function computeOptimalFleet(catScores) {
  const eligible = catScores.filter(c => c.utilizationPct > 40).sort((a, b) => b.score - a.score)
  if (eligible.length === 0) return catScores.map(c => ({ ...c, recommended: 0 }))
  const totalScore = eligible.reduce((s, c) => s + c.score, 0)
  let slots = eligible.map(c => {
    const raw = totalScore > 0 ? (c.score / totalScore) * TOTAL_SLOTS : 0
    return { ...c, rawSlots: raw, recommended: Math.max(1, Math.floor(raw)) }
  })
  let assigned = slots.reduce((s, c) => s + c.recommended, 0)
  const remaining = TOTAL_SLOTS - assigned
  if (remaining > 0) {
    const fracs = slots.map((c, i) => ({ i, frac: c.rawSlots - Math.floor(c.rawSlots) })).sort((a, b) => b.frac - a.frac)
    for (let r = 0; r < remaining && r < fracs.length; r++) slots[fracs[r].i].recommended++
  }
  assigned = slots.reduce((s, c) => s + c.recommended, 0)
  if (assigned > TOTAL_SLOTS) {
    const sorted = [...slots].sort((a, b) => a.score - b.score)
    let excess = assigned - TOTAL_SLOTS
    for (const s of sorted) { if (excess <= 0) break; const t = Math.min(s.recommended - 1, excess); if (t > 0) { s.recommended -= t; excess -= t } }
  }
  const slotMap = {}
  for (const s of slots) slotMap[s.category] = s.recommended
  return catScores.map(c => ({ ...c, recommended: slotMap[c.category] || 0 }))
}

const NoData = () => (
  <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
    <div style={{ fontSize: 32 }}>⏳</div>
    <div className="font-bold mt-2">Nedostatek dat pro doporučení</div>
    <div className="mt-1">Pro optimalizaci flotily jsou potřeba data alespoň za 3 měsíce.</div>
  </div>
)

export default function OptimalniFlotila() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const [selectedLoc, setSelectedLoc] = useState(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [lRes, mRes, bRes] = await Promise.all([
        supabase.from('branches').select('id, name, city, location, type'),
        supabase.from('motorcycles').select('id, branch_id, category, status'),
        supabase.from('bookings').select('moto_id, start_date, end_date, total_price, status, created_at'),
      ])
      if (lRes.error) throw lRes.error
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error
      setRaw({ locations: lRes.data || [], motorcycles: mRes.data || [], bookings: bRes.data || [] })
      if (lRes.data?.length > 0) setSelectedLoc(lRes.data[0].id)
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné pobočky</div>

  const { locations, motorcycles, bookings } = raw
  const completed = filterByPeriod(bookings.filter(b => b.status === 'completed'), period, 'created_at')
  const has3mo = hasMinimumData(bookings)

  let periodDays = 365
  if (period.type === 'month') periodDays = new Date(period.year, period.month + 1, 0).getDate()
  else if (period.type === 'custom' && period.from && period.to) periodDays = Math.max(1, diffDays(period.from, period.to))

  const motoLocMap = {}
  for (const m of motorcycles) motoLocMap[m.id] = m.branch_id

  const locData = {}
  for (const loc of locations) {
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id)
    const locCompleted = completed.filter(b => motoLocMap[b.moto_id] === loc.id)
    const cats = [...new Set(locMotos.map(m => (m.category || '').toLowerCase()).filter(Boolean))]
    const hasBookings = locCompleted.length > 0

    const catScores = cats.map(cat => {
      const catMotos = locMotos.filter(m => (m.category || '').toLowerCase() === cat)
      const mc = catMotos.length
      const catMotoIds = new Set(catMotos.map(m => m.id))
      const catCompleted = locCompleted.filter(b => catMotoIds.has(b.moto_id))
      const totalRevenue = catCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
      const rentedDays = catCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
      const utilizationPct = mc > 0 ? (rentedDays / (mc * periodDays)) * 100 : 0
      const revenuePerSlot = mc > 0 ? totalRevenue / mc : 0
      const score = revenuePerSlot * (utilizationPct / 100)
      return { category: cat, motorcycleCount: mc, totalRevenue, utilizationPct, revenuePerSlot, score }
    })

    const optimal = computeOptimalFleet(catScores)
    const totalMotos = locMotos.length
    const totalRevenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const currentRevPerSlot = totalMotos > 0 ? totalRevenue / totalMotos : 0
    let optimizedRevPerSlot = 0
    const totalRecommended = optimal.reduce((s, c) => s + c.recommended, 0)
    if (totalRecommended > 0) optimizedRevPerSlot = optimal.reduce((s, c) => s + c.revenuePerSlot * c.recommended, 0) / totalRecommended
    const potentialAbs = optimizedRevPerSlot - currentRevPerSlot
    const potentialPct = currentRevPerSlot > 0 ? (potentialAbs / currentRevPerSlot) * 100 : 0
    locData[loc.id] = { ...loc, catScores: optimal, hasBookings, currentRevPerSlot, optimizedRevPerSlot, potentialAbs, potentialPct, totalMotos }
  }

  const loc = locData[selectedLoc] || locData[locations[0].id]
  const cats = loc?.catScores || []
  const diffs = cats.map(c => {
    const diff = c.recommended - c.motorcycleCount
    if (diff > 0) return { label: `+${diff} ${c.category}`, type: 'add' }
    if (diff < 0) return { label: `${diff} ${c.category}`, type: 'remove' }
    return { label: `= ${c.category}`, type: 'same' }
  })
  const diffColors = { add: { bg: '#dcfce7', color: '#166534' }, remove: { bg: '#fecaca', color: '#991b1b' }, same: { bg: '#f3f4f6', color: '#6b7280' } }
  const benchmark = locations.map(l => locData[l.id]).sort((a, b) => b.potentialPct - a.potentialPct)
  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />
      {!has3mo && <NoData />}
      {has3mo && (
        <>
          <div className="mb-5">
            <select value={selectedLoc || ''} onChange={e => setSelectedLoc(e.target.value)} className="text-sm font-bold" style={{ padding: '8px 14px', borderRadius: 10, border: '2px solid #e5e7eb', background: '#fff', color: '#1a2e22', cursor: 'pointer', minWidth: 220 }}>
              {locations.map(l => <option key={l.id} value={l.id}>{l.name} — {l.city}</option>)}
            </select>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-5">
            <div style={{ ...cardStyle, overflowX: 'auto' }}>
              <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Aktuální složení</div>
              <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}>{['Kategorie', 'Počet', 'Obsazenost %', 'Rev/slot'].map(h => <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>)}</tr></thead>
                <tbody>
                  {cats.length === 0 && <tr><td colSpan={4} className="py-4 text-center" style={{ color: '#888' }}>Žádné motorky</td></tr>}
                  {cats.map(c => (
                    <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6', background: c.recommended !== c.motorcycleCount ? '#fffbeb' : 'transparent' }}>
                      <td className="py-2 px-3 font-semibold">{c.category}</td>
                      <td className="py-2 px-3">{c.motorcycleCount}</td>
                      <td className="py-2 px-3">{c.utilizationPct.toFixed(1)} %</td>
                      <td className="py-2 px-3">{Math.round(c.revenuePerSlot).toLocaleString('cs-CZ')} Kč</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div style={{ ...cardStyle, overflowX: 'auto' }}>
              <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Doporučené složení</div>
              <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}>{['Kategorie', 'Doporučeno', 'Est. Rev/slot'].map(h => <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>)}</tr></thead>
                <tbody>
                  {cats.length === 0 && <tr><td colSpan={3} className="py-4 text-center" style={{ color: '#888' }}>Žádné motorky</td></tr>}
                  {cats.map(c => (
                    <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6', background: c.recommended !== c.motorcycleCount ? '#fffbeb' : 'transparent' }}>
                      <td className="py-2 px-3 font-semibold">{c.category}</td>
                      <td className="py-2 px-3">{c.recommended}</td>
                      <td className="py-2 px-3">{Math.round(c.revenuePerSlot).toLocaleString('cs-CZ')} Kč</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="flex flex-wrap gap-2 mb-5">
            {diffs.map((d, i) => <span key={i} style={{ background: diffColors[d.type].bg, color: diffColors[d.type].color, borderRadius: 8, padding: '4px 12px', fontSize: 12, fontWeight: 700 }}>{d.label}</span>)}
          </div>

          <div style={{ background: '#1a2e22', borderRadius: 14, padding: '24px 20px', marginBottom: 24, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 16 }}>
            <div><div className="text-xs font-bold uppercase mb-1" style={{ color: 'rgba(255,255,255,.5)' }}>Aktuální rev/slot</div><div className="text-2xl font-extrabold" style={{ color: '#74FB71' }}>{Math.round(loc.currentRevPerSlot).toLocaleString('cs-CZ')} Kč</div></div>
            <div><div className="text-xs font-bold uppercase mb-1" style={{ color: 'rgba(255,255,255,.5)' }}>Optimalizovaný rev/slot</div><div className="text-2xl font-extrabold" style={{ color: '#74FB71' }}>{Math.round(loc.optimizedRevPerSlot).toLocaleString('cs-CZ')} Kč</div></div>
            <div><div className="text-xs font-bold uppercase mb-1" style={{ color: 'rgba(255,255,255,.5)' }}>Potenciál</div><div className="text-2xl font-extrabold" style={{ color: '#74FB71' }}>+{Math.round(loc.potentialAbs).toLocaleString('cs-CZ')} Kč <span className="text-sm ml-2" style={{ color: 'rgba(255,255,255,.6)' }}>/ +{loc.potentialPct.toFixed(1)}%</span></div></div>
          </div>

          <div style={{ ...cardStyle, overflowX: 'auto' }}>
            <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Benchmark všech poboček</div>
            <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
              <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}>{['Pobočka', 'Typ', 'Aktuální rev/slot', 'Optimalizovaný rev/slot', 'Potenciál %'].map(h => <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>)}</tr></thead>
              <tbody>
                {benchmark.map(b => (
                  <tr key={b.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                    <td className="py-2 px-3 font-semibold">{b.name}</td>
                    <td className="py-2 px-3"><span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 11, fontWeight: 700 }}>{b.location || '—'}</span></td>
                    {!b.hasBookings ? <td colSpan={3} className="py-2 px-3" style={{ color: '#888' }}>Nedostatek dat</td> : (
                      <>
                        <td className="py-2 px-3">{Math.round(b.currentRevPerSlot).toLocaleString('cs-CZ')} Kč</td>
                        <td className="py-2 px-3">{Math.round(b.optimizedRevPerSlot).toLocaleString('cs-CZ')} Kč</td>
                        <td className="py-2 px-3 font-bold" style={{ color: b.potentialPct > 0 ? '#166534' : '#888' }}>{b.potentialPct > 0 ? '+' : ''}{b.potentialPct.toFixed(1)} %</td>
                      </>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}
