import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod, hasMinimumData } from './TimePeriodSelector'
import { isRealizedBooking } from '../../lib/revenueUtils'
import { fetchAllRows, loadMotoMoves, periodWindow, buildFleetTimeline, summarizeByBranch, dayMonth, MIN_EXPOSURE_DAYS } from '../../lib/branchFleet'
import { useTableSort, sortRows, SortableHeaderRow, STACK_WRAP, TabScroll, TAB_STICKY } from '../../components/sortableTable'

const SEASONAL_COLUMNS = [
  { label: 'Pobočka', key: 'locName', str: true },
  { label: 'Kategorie', key: 'cat', str: true },
  { label: 'Léto', key: 'leto' },
  { label: 'Jaro/Podzim', key: 'jaro_podzim' },
  { label: 'Zima', key: 'zima' },
  { label: 'Doporučení', key: 'recommendation', str: true },
]
const BULK_COLUMNS = [
  { label: 'Kategorie', key: 'category', str: true },
  { label: 'Z pobočky', key: 'fromName', str: true, value: r => r.fromLoc.name },
  { label: 'Obsazenost', key: 'fromUtil' },
  { label: 'Do pobočky', key: 'toName', str: true, value: r => r.toLoc.name },
  { label: 'Obsazenost', key: 'toUtil' },
  { label: 'Počet', key: 'count' },
  { label: 'Akce' },
]
const BUY_COLUMNS = [
  { label: 'Model', key: 'model', str: true },
  { label: 'Značka', key: 'brand', str: true },
  { label: 'Kategorie', key: 'category', str: true },
  { label: 'ROI', key: 'roi' },
  { label: 'Utilization', key: 'utilization' },
  { label: 'Demand', key: 'demandIndex' },
  { label: 'Buy Score', key: 'buyScore' },
  { label: 'Doporučení', key: 'recommendation', str: true },
]

const NoData = () => (
  <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
    <div style={{ fontSize: 32 }}>⏳</div>
    <div className="font-bold mt-2">Zatím žádná data pro doporučení přesunů</div>
    <div className="mt-1">Jakmile přibude první rezervace, zobrazí se tu doporučení (i orientačně za kratší období).</div>
  </div>
)

export default function DoporuceniPresunu() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const [planned, setPlanned] = useState(() => { try { return JSON.parse(localStorage.getItem('velin_relocations') || '[]') } catch { return [] } })
  const [bulkPlanned, setBulkPlanned] = useState(() => { try { return JSON.parse(localStorage.getItem('velin_bulk_relocations') || '[]') } catch { return [] } })
  const seasonalSort = useTableSort(SEASONAL_COLUMNS)
  const bulkSort = useTableSort(BULK_COLUMNS)
  const buySort = useTableSort(BUY_COLUMNS, { key: 'buyScore', dir: 'desc' })

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
      const [mRes, bookings, lRes, moves] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, branch_id, purchase_price, status, acquired_at, created_at, is_trailer'),
        fetchAllRows(() => supabase.from('bookings').select('id, moto_id, trailer_moto_id, branch_id, start_date, end_date, total_price, status, created_at, payment_status, is_test').not('is_test', 'is', true).order('id')),
        supabase.from('branches').select('id, name, location, type'),
        loadMotoMoves(),
      ])
      if (mRes.error) throw mRes.error
      if (lRes.error) throw lRes.error
      setRaw({ motorcycles: (mRes.data || []).filter(m => !m.is_trailer), bookings, locations: lRes.data || [], moves })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  // Kde motorky v období reálně stály (moto-dny, lib/branchFleet.js) — obsazenost pobočky × kategorie
  const fleet = useMemo(() => {
    if (!raw) return null
    const win = periodWindow(period, raw.bookings)
    const tl = buildFleetTimeline({ motorcycles: raw.motorcycles, bookings: raw.bookings, moves: raw.moves, fromDay: win.fromDay, toDay: win.toDay })
    return { tl, byBranch: summarizeByBranch(tl, m => (m.category || '').toLowerCase()) }
  }, [raw, period])

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné motorky</div>

  const { motorcycles, bookings, locations } = raw
  const completed = filterByPeriod(bookings.filter(isRealizedBooking), period, 'created_at')
  const has3mo = hasMinimumData(bookings)

  const locMap = {}
  for (const l of locations) locMap[l.id] = l
  const { tl, byBranch } = fleet
  const tlByMoto = Object.fromEntries(tl.motos.map(t => [t.moto.id, t]))

  // Per-moto stats. Obsazenost = dny pronájmu / dny, kdy motorka v období reálně byla ve flotile — na své
  // AKTUÁLNÍ pobočce (≥ MIN_EXPOSURE_DAYS dní tam), jinak za celé období (právě přesunutá motorka).
  const motoStats = motorcycles.map(m => {
    const mc = completed.filter(b => b.moto_id === m.id)
    const revenue = mc.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const t = tlByMoto[m.id]
    let present = 0, rented = 0, presentCur = 0, rentedCur = 0
    for (let i = 0; i < (t?.loc.length || 0); i++) {
      present++; if (t.rented[i]) rented++
      if (m.branch_id && t.loc[i] === m.branch_id) { presentCur++; if (t.rented[i]) rentedCur++ }
    }
    const utilization = presentCur >= MIN_EXPOSURE_DAYS ? rentedCur / presentCur : (present > 0 ? rented / present : 0)
    const pp = Number(m.purchase_price) || 0
    const annualCosts = pp * 0.20
    const roi = pp > 0 ? (revenue - annualCosts) / pp : 0
    return { ...m, rentedDays: rented, revenue, reservationCount: mc.length, utilization, purchasePrice: pp, roi }
  })

  // Per loc×cat utilization = dny pronájmu / moto-dny kategorie na pobočce; count = AKTUÁLNÍ počet kusů (kolik lze přesunout)
  const locCatUtil = {}
  for (const [lid, st] of Object.entries(byBranch)) {
    for (const [cat, c] of Object.entries(st.cats)) {
      if (!cat || c.motoDays < MIN_EXPOSURE_DAYS) continue
      const count = motorcycles.filter(m => m.branch_id === lid && (m.category || '').toLowerCase() === cat).length
      locCatUtil[`${lid}_${cat}`] = { avg: c.rentedDays / c.motoDays, count, motoDays: c.motoDays }
    }
  }

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

  // Seasonal — po dnech časové osy: den pronájmu jde pobočce rezervace (bookings.branch_id), nečinný den
  // pobočce, kde motorka stála; obsazenost sezóny = dny pronájmu / moto-dny pobočky × kategorie v sezóně.
  function seasonOfMonth(m) { if (m >= 6 && m <= 8) return 'leto'; if ((m >= 3 && m <= 5) || (m >= 9 && m <= 10)) return 'jaro_podzim'; return 'zima' }
  const seasonalMap = {}
  for (const t of tl.motos) {
    const cat = (t.moto.category || '').toLowerCase()
    if (!cat) continue
    for (let i = 0; i < t.loc.length; i++) {
      const lid = t.loc[i]
      if (!lid) continue
      const key = `${lid}_${cat}`, sn = seasonOfMonth(dayMonth(t.start + i))
      const e = seasonalMap[key] ||= { lid, cat, md: { leto: 0, jaro_podzim: 0, zima: 0 }, rd: { leto: 0, jaro_podzim: 0, zima: 0 } }
      e.md[sn]++; if (t.rented[i]) e.rd[sn]++
    }
  }
  const seasonalRows = []
  for (const key in seasonalMap) {
    const s = seasonalMap[key]
    if (s.rd.leto + s.rd.jaro_podzim + s.rd.zima === 0) continue
    const u = sn => (s.md[sn] > 0 ? s.rd[sn] / s.md[sn] : 0)
    const utilL = u('leto'), utilJP = u('jaro_podzim'), utilZ = u('zima')
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
                      <button onClick={() => togglePlan(r.motoId, r.toLocId)} className="text-xs font-bold cursor-pointer max-lg:min-h-[40px]" style={{ padding: '6px 14px', borderRadius: 8, border: 'none', background: isP ? '#74FB71' : '#f1faf7', color: '#1a2e22' }}>{isP ? '✓ Naplánováno' : '✓ Naplánovat'}</button>
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
              // Telefon: řádky jako karty (mg-stack), obal bez bílé karty a paddingu
              <div className={STACK_WRAP} style={{ ...cardStyle, padding: undefined, overflowX: 'auto' }}>
                <table className="w-full text-sm mg-stack" style={{ borderCollapse: 'collapse' }}>
                  <thead><SortableHeaderRow columns={SEASONAL_COLUMNS} sort={seasonalSort.sort} toggle={seasonalSort.toggle} /></thead>
                  <tbody>
                    {sortRows(seasonalRows, SEASONAL_COLUMNS, seasonalSort.sort).map((r, i) => (
                      <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                        <td className="py-2 px-3 font-semibold mg-stack-full">{r.locName}</td>
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
              <div className={STACK_WRAP} style={{ ...cardStyle, padding: undefined, overflowX: 'auto' }}>
                <table className="w-full text-sm mg-stack" style={{ borderCollapse: 'collapse' }}>
                  <thead><SortableHeaderRow columns={BULK_COLUMNS} sort={bulkSort.sort} toggle={bulkSort.toggle} /></thead>
                  <tbody>
                    {sortRows(bulkRelocations, BULK_COLUMNS, bulkSort.sort).map((r, i) => {
                      const bKey = `${r.category}_${r.fromLoc.id}_${r.toLoc.id}`
                      const isBP = bulkPlanned.some(b => `${b.category}_${b.fromLocationId}_${b.toLocationId}` === bKey)
                      return (
                        <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                          <td className="py-2 px-3 font-semibold mg-stack-full">{r.category}</td>
                          <td className="py-2 px-3">{r.fromLoc.name}</td>
                          <td className="py-2 px-3">{(r.fromUtil * 100).toFixed(1)}%</td>
                          <td className="py-2 px-3">{r.toLoc.name}</td>
                          <td className="py-2 px-3">{(r.toUtil * 100).toFixed(1)}%</td>
                          <td className="py-2 px-3 font-bold">{r.count}</td>
                          <td className="py-2 px-3 mg-stack-full"><button onClick={() => toggleBulkPlan(r.category, r.fromLoc.id, r.toLoc.id, r.count)} className="text-xs font-bold cursor-pointer max-lg:min-h-[40px]" style={{ padding: '5px 12px', borderRadius: 8, border: 'none', background: isBP ? '#e5e7eb' : '#f1faf7', color: isBP ? '#6b7280' : '#1a2e22' }}>{isBP ? '✓ Naplánováno' : 'Naplánovat'}</button></td>
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
            <div className={STACK_WRAP} style={{ ...cardStyle, padding: undefined, overflowX: 'auto' }}>
              <TabScroll>
              <table className="w-full text-sm mg-stack" style={{ borderCollapse: 'collapse' }}>
                <thead><SortableHeaderRow columns={BUY_COLUMNS} sort={buySort.sort} toggle={buySort.toggle} stickyFirst /></thead>
                <tbody>
                  {sortRows(buyScores, BUY_COLUMNS, buySort.sort).map((b, i) => {
                    const sc = b.buyScore > 0.4 ? '#166534' : b.buyScore >= 0.2 ? '#854d0e' : '#991b1b'
                    const sbg = b.buyScore > 0.4 ? '#dcfce7' : b.buyScore >= 0.2 ? '#fef9c3' : '#fecaca'
                    return (
                      <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                        <td className={`py-2 px-3 font-semibold mg-stack-full ${TAB_STICKY}`}>{b.model}</td>
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
              </TabScroll>
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
