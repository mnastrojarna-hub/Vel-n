import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'

const NoData = () => (
  <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
    <div style={{ fontSize: 32 }}>⏳</div>
    <div className="font-bold mt-2">Nedostatek dat pro doporučení přesunů</div>
    <div className="mt-1">Pro zobrazení jsou potřeba data alespoň za 3 měsíce.</div>
  </div>
)

export default function DoporuceniPresunu() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const [planned, setPlanned] = useState(() => { try { return JSON.parse(localStorage.getItem('velin_relocations') || '[]') } catch { return [] } })
  const [bulkPlanned, setBulkPlanned] = useState(() => { try { return JSON.parse(localStorage.getItem('velin_bulk_relocations') || '[]') } catch { return [] } })

  useEffect(() => { loadData() }, [])

  function togglePlan(motoId, targetLocId) {
    const key = `${motoId}_${targetLocId}`
    const next = planned.includes(key) ? planned.filter(k => k !== key) : [...planned, key]
    setPlanned(next); localStorage.setItem('velin_relocations', JSON.stringify(next))
  }
  function toggleBulkPlan(category, fromId, toId, count) {
    const key = `${category}_${fromId}_${toId}`
    const exists = bulkPlanned.find(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` === key)
    const next = exists ? bulkPlanned.filter(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` !== key) : [...bulkPlanned, { category, fromLocationId: fromId, toLocationId: toId, count, plannedAt: new Date().toISOString() }]
    setBulkPlanned(next); localStorage.setItem('velin_bulk_relocations', JSON.stringify(next))
  }

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [mRes, bRes, lRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, branch_id, purchase_price, status'),
        supabase.from('bookings').select('moto_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('branches').select('id, name, location, type'),
      ])
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error
      if (lRes.error) throw lRes.error
      setRaw({ motorcycles: mRes.data || [], bookings: bRes.data || [], locations: lRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné motorky</div>

  const { motorcycles, bookings, locations } = raw
  const completed = filterByPeriod(bookings.filter(b => b.status === 'completed'), period, 'created_at')
  const has3mo = hasMinimumData(bookings)

  let periodDays = 365
  if (period.type === 'month') periodDays = new Date(period.year, period.month + 1, 0).getDate()
  else if (period.type === 'custom' && period.from && period.to) periodDays = Math.max(1, diffDays(period.from, period.to))

  const locMap = {}
  for (const l of locations) locMap[l.id] = l

  // Per-moto stats
  const motoStats = motorcycles.map(m => {
    const mc = completed.filter(b => b.moto_id === m.id)
    const rentedDays = mc.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
    const revenue = mc.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const utilization = rentedDays / periodDays
    const pp = Number(m.purchase_price) || 0
    const annualCosts = pp * 0.20
    const roi = pp > 0 ? (revenue - annualCosts) / pp : 0
    return { ...m, rentedDays, revenue, reservationCount: mc.length, utilization, purchasePrice: pp, roi }
  })

  // Per loc×cat utilization
  const locCatUtil = {}
  for (const m of motoStats) {
    const cat = (m.category || '').toLowerCase()
    const lid = m.branch_id
    if (!cat || !lid) continue
    const key = `${lid}_${cat}`
    if (!locCatUtil[key]) locCatUtil[key] = { total: 0, count: 0 }
    locCatUtil[key].total += m.utilization
    locCatUtil[key].count++
  }
  for (const k in locCatUtil) locCatUtil[k].avg = locCatUtil[k].total / locCatUtil[k].count

  // Relocations
  const relocations = []
  for (const m of motoStats) {
    if (m.utilization >= 0.60) continue
    const cat = (m.category || '').toLowerCase()
    if (!cat) continue
    let bestLoc = null, bestUtil = 0
    for (const l of locations) {
      if (l.id === m.branch_id) continue
      const avg = locCatUtil[`${l.id}_${cat}`]?.avg || 0
      if (avg > 0.75 && avg > bestUtil) { bestLoc = l; bestUtil = avg }
    }
    if (bestLoc) {
      const fromLoc = locMap[m.branch_id]
      relocations.push({ motoId: m.id, model: m.model, brand: m.brand, category: cat, fromName: fromLoc?.name || '—', fromUtil: m.utilization, toName: bestLoc.name, toLocId: bestLoc.id, toUtil: bestUtil, diffPp: Math.round((bestUtil - m.utilization) * 100) })
    }
  }

  // Buy score
  const modelMap = {}
  for (const m of motoStats) {
    const key = `${m.model}_${m.brand}_${(m.category || '').toLowerCase()}`
    if (!modelMap[key]) modelMap[key] = { model: m.model, brand: m.brand, category: (m.category || '').toLowerCase(), count: 0, totalRoi: 0, totalUtil: 0, totalRes: 0 }
    modelMap[key].count++; modelMap[key].totalRoi += m.roi; modelMap[key].totalUtil += m.utilization; modelMap[key].totalRes += m.reservationCount
  }
  const buyScores = Object.values(modelMap).map(g => {
    const roi = g.count > 0 ? g.totalRoi / g.count : 0
    const util = g.count > 0 ? g.totalUtil / g.count : 0
    const demand = g.count > 0 ? g.totalRes / g.count : 0
    const score = roi * util * demand
    const rec = score > 0.4 ? 'Koupit' : score >= 0.2 ? 'Sledovat' : 'Neprioritní'
    return { ...g, roi, utilization: util, demandIndex: demand, buyScore: score, recommendation: rec }
  }).sort((a, b) => b.buyScore - a.buyScore).slice(0, 10)

  // Retiring
  const retiring = motoStats.filter(m => m.utilization < 0.40 || (m.roi < 0.20 && m.purchasePrice > 0))

  // Seasonal
  const SEASON_DAYS = { leto: 92, jaro_podzim: 153, zima: 120 }
  function getSeason(date) { const m = new Date(date).getMonth() + 1; if (m >= 6 && m <= 8) return 'leto'; if ((m >= 3 && m <= 5) || (m >= 9 && m <= 10)) return 'jaro_podzim'; return 'zima' }
  const seasonalMap = {}
  for (const b of completed) {
    const moto = motorcycles.find(mm => mm.id === b.moto_id)
    if (!moto || !moto.branch_id) continue
    const cat = (moto.category || '').toLowerCase()
    if (!cat) continue
    const key = `${moto.branch_id}_${cat}`
    if (!seasonalMap[key]) seasonalMap[key] = { lid: moto.branch_id, cat, leto: 0, jaro_podzim: 0, zima: 0 }
    seasonalMap[key][getSeason(b.start_date || b.created_at)] += diffDays(b.start_date, b.end_date)
  }
  const seasonalRows = []
  for (const key in seasonalMap) {
    const s = seasonalMap[key]
    const mc = locCatUtil[`${s.lid}_${s.cat}`]?.count || 0
    if (mc === 0) continue
    const utilL = s.leto / (mc * SEASON_DAYS.leto), utilJP = s.jaro_podzim / (mc * SEASON_DAYS.jaro_podzim), utilZ = s.zima / (mc * SEASON_DAYS.zima)
    const maxU = Math.max(utilL, utilJP, utilZ), minU = Math.min(utilL, utilJP, utilZ)
    let rec = 'Stabilní'
    if (maxU > 0.75 && minU < 0.45) {
      const utils = { leto: utilL, jaro_podzim: utilJP, zima: utilZ }
      const maxS = Object.entries(utils).sort((a, b) => b[1] - a[1])[0][0]
      rec = maxS === 'leto' ? 'Posílit léto' : maxS === 'zima' ? 'Přesunout na zimu' : 'Přesunout na léto'
    }
    seasonalRows.push({ locName: locMap[s.lid]?.name || '—', cat: s.cat, leto: utilL, jaro_podzim: utilJP, zima: utilZ, recommendation: rec, hasSeasonal: maxU > 0.75 && minU < 0.45 })
  }

  // Bulk relocations
  const bulkRelocations = []
  const allCats = [...new Set(motorcycles.map(m => (m.category || '').toLowerCase()).filter(Boolean))]
  for (const cat of allCats) {
    const surplus = [], deficit = []
    for (const l of locations) {
      const e = locCatUtil[`${l.id}_${cat}`]
      if (!e) continue
      if (e.avg < 0.50 && e.count > 1) surplus.push({ loc: l, avg: e.avg, count: e.count })
      if (e.avg > 0.80) deficit.push({ loc: l, avg: e.avg, count: e.count })
    }
    if (surplus.length > 0 && deficit.length > 0) {
      for (const s of surplus) for (const d of deficit) {
        const mc = Math.floor(s.count / 2)
        if (mc > 0) bulkRelocations.push({ category: cat, fromLoc: s.loc, fromUtil: s.avg, toLoc: d.loc, toUtil: d.avg, count: mc })
      }
    }
  }

  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
  function seasonCellStyle(val) {
    if (val > 0.70) return { background: 'rgba(116,251,113,0.2)', color: '#166534' }
    if (val >= 0.40) return { background: 'rgba(251,191,36,0.15)', color: '#92400e' }
    return { background: 'rgba(220,38,38,0.12)', color: '#991b1b' }
  }

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />
      {!has3mo && <NoData />}
      {has3mo && (
        <>
          {/* Relocations */}
          <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
            <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Doporučení přesunů</div>
            {relocations.length === 0 ? (
              <div style={{ ...cardStyle, textAlign: 'center', padding: 24 }}><div style={{ fontSize: 36 }}>✅</div><div className="font-bold mt-2" style={{ color: '#166534' }}>Flotila je optimálně rozmístěna</div></div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {relocations.map(r => {
                  const isP = planned.includes(`${r.motoId}_${r.toLocId}`)
                  return (
                    <div key={`${r.motoId}_${r.toLocId}`} style={cardStyle}>
                      <div className="font-bold text-sm mb-2" style={{ color: '#1a2e22' }}>{r.model} {r.brand}<span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 10, fontWeight: 700, marginLeft: 8 }}>{r.category}</span></div>
                      <div className="text-xs mb-1" style={{ color: '#888' }}>Z: <span className="font-semibold" style={{ color: '#1a2e22' }}>{r.fromName}</span> ({(r.fromUtil * 100).toFixed(0)}%)</div>
                      <div className="text-xs mb-1" style={{ color: '#888' }}>→ Do: <span className="font-semibold" style={{ color: '#166534' }}>{r.toName}</span> ({(r.toUtil * 100).toFixed(0)}%)</div>
                      <div className="text-xs mb-3" style={{ color: '#854d0e' }}>Vyšší poptávka o {r.diffPp} p.b.</div>
                      <button onClick={() => togglePlan(r.motoId, r.toLocId)} className="text-xs font-bold cursor-pointer" style={{ padding: '6px 14px', borderRadius: 8, border: 'none', background: isP ? '#74FB71' : '#f1faf7', color: '#1a2e22' }}>{isP ? '✓ Naplánováno' : '✓ Naplánovat'}</button>
                    </div>
                  )
                })}
              </div>
            )}
          </div>

          {/* Seasonal */}
          <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
            <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Sezónní přesuny</div>
            {seasonalRows.length === 0 ? <div style={{ ...cardStyle, textAlign: 'center', padding: 24, color: '#888' }}>Žádná sezónní data</div> : (
              <div style={{ ...cardStyle, overflowX: 'auto' }}>
                <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                  <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}>{['Pobočka', 'Kategorie', 'Léto', 'Jaro/Podzim', 'Zima', 'Doporučení'].map(h => <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>)}</tr></thead>
                  <tbody>
                    {seasonalRows.map((r, i) => (
                      <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                        <td className="py-2 px-3 font-semibold">{r.locName}</td>
                        <td className="py-2 px-3">{r.cat}</td>
                        {['leto', 'jaro_podzim', 'zima'].map(s => <td key={s} className="py-2 px-3"><span style={{ ...seasonCellStyle(r[s]), borderRadius: 6, padding: '2px 8px', fontSize: 12, fontWeight: 700 }}>{(r[s] * 100).toFixed(0)}%</span></td>)}
                        <td className="py-2 px-3 font-bold text-xs" style={{ color: r.hasSeasonal ? '#854d0e' : '#166534' }}>{r.recommendation}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Bulk relocations */}
          <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
            <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Hromadné relokace kategorií</div>
            {bulkRelocations.length === 0 ? (
              <div style={{ ...cardStyle, textAlign: 'center', padding: 24 }}><div className="font-bold" style={{ color: '#166534' }}>✅ Žádné hromadné relokace potřeba</div></div>
            ) : (
              <div style={{ ...cardStyle, overflowX: 'auto' }}>
                <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                  <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}>{['Kategorie', 'Z pobočky', 'Obsazenost', 'Do pobočky', 'Obsazenost', 'Počet', 'Akce'].map(h => <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>)}</tr></thead>
                  <tbody>
                    {bulkRelocations.map((r, i) => {
                      const bKey = `${r.category}_${r.fromLoc.id}_${r.toLoc.id}`
                      const isBP = bulkPlanned.some(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` === bKey)
                      return (
                        <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                          <td className="py-2 px-3 font-semibold">{r.category}</td>
                          <td className="py-2 px-3">{r.fromLoc.name}</td>
                          <td className="py-2 px-3">{(r.fromUtil * 100).toFixed(1)}%</td>
                          <td className="py-2 px-3">{r.toLoc.name}</td>
                          <td className="py-2 px-3">{(r.toUtil * 100).toFixed(1)}%</td>
                          <td className="py-2 px-3 font-bold">{r.count}</td>
                          <td className="py-2 px-3"><button onClick={() => toggleBulkPlan(r.category, r.fromLoc.id, r.toLoc.id, r.count)} className="text-xs font-bold cursor-pointer" style={{ padding: '5px 12px', borderRadius: 8, border: 'none', background: isBP ? '#e5e7eb' : '#f1faf7', color: isBP ? '#6b7280' : '#1a2e22' }}>{isBP ? '✓ Naplánováno' : 'Naplánovat'}</button></td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Buy Score */}
          <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
            <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Top kandidáti na dokoupení</div>
            <div style={{ ...cardStyle, overflowX: 'auto' }}>
              <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}>{['Model', 'Značka', 'Kategorie', 'ROI', 'Utilization', 'Demand', 'Buy Score', 'Doporučení'].map(h => <th key={h} className="text-left font-bold py-2 px-3" style={{ color: '#1a2e22' }}>{h}</th>)}</tr></thead>
                <tbody>
                  {buyScores.map((b, i) => {
                    const sc = b.buyScore > 0.4 ? '#166534' : b.buyScore >= 0.2 ? '#854d0e' : '#991b1b'
                    const sbg = b.buyScore > 0.4 ? '#dcfce7' : b.buyScore >= 0.2 ? '#fef9c3' : '#fecaca'
                    return (
                      <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                        <td className="py-2 px-3 font-semibold">{b.model}</td>
                        <td className="py-2 px-3">{b.brand || '—'}</td>
                        <td className="py-2 px-3">{b.category}</td>
                        <td className="py-2 px-3">{(b.roi * 100).toFixed(1)}%</td>
                        <td className="py-2 px-3">{(b.utilization * 100).toFixed(1)}%</td>
                        <td className="py-2 px-3">{b.demandIndex.toFixed(2)}</td>
                        <td className="py-2 px-3"><span style={{ background: sbg, color: sc, borderRadius: 8, padding: '2px 10px', fontSize: 11, fontWeight: 700 }}>{b.buyScore.toFixed(3)}</span></td>
                        <td className="py-2 px-3 font-bold" style={{ color: sc }}>{b.recommendation}</td>
                      </tr>
                    )
                  })}
                  {buyScores.length === 0 && <tr><td colSpan={8} className="py-4 text-center" style={{ color: '#888' }}>Žádné modely k hodnocení</td></tr>}
                </tbody>
              </table>
            </div>
          </div>

          {/* Retiring */}
          <div>
            <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Zvažte vyřazení</div>
            {retiring.length === 0 ? (
              <div style={{ ...cardStyle, textAlign: 'center', padding: 24 }}><div className="font-bold" style={{ color: '#166534' }}>Žádné motorky k vyřazení</div></div>
            ) : (
              <div className="flex flex-col gap-3">
                {retiring.map(m => (
                  <div key={m.id} style={{ background: '#fffbeb', borderRadius: 14, padding: '14px 18px', border: '1px solid #fde68a' }}>
                    <span className="text-sm font-bold" style={{ color: '#854d0e' }}>⚠️ {m.model} {m.brand || ''} — Utilization: {(m.utilization * 100).toFixed(1)}%, ROI: {(m.roi * 100).toFixed(1)}%</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}
