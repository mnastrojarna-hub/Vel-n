import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod, hasMinimumData } from './TimePeriodSelector'
import { isRealizedBooking } from '../../lib/revenueUtils'
import { effBranchId } from '../../lib/bookingBranch'
import { fetchAllRows, loadMotoMoves, periodWindow, buildFleetTimeline, summarizeByBranch, MIN_EXPOSURE_DAYS } from '../../lib/branchFleet'
import { useTableSort, sortRows, SortableHeaderRow, STACK_WRAP } from '../../components/sortableTable'

const TOTAL_SLOTS = 8

const CURRENT_COLUMNS = [
  { label: 'Kategorie', key: 'category', str: true },
  { label: 'Počet', key: 'motorcycleCount' },
  { label: 'Obsazenost %', key: 'utilizationPct' },
  { label: 'Rev/slot', key: 'revenuePerSlot' },
]
const RECOMMENDED_COLUMNS = [
  { label: 'Kategorie', key: 'category', str: true },
  { label: 'Doporučeno', key: 'recommended' },
  { label: 'Est. Rev/slot', key: 'revenuePerSlot' },
]
const BENCHMARK_COLUMNS = [
  { label: 'Pobočka', key: 'name', str: true },
  { label: 'Typ', key: 'location', str: true },
  { label: 'Aktuální rev/slot', key: 'currentRevPerSlot', value: b => (b.hasBookings ? b.currentRevPerSlot : null) },
  { label: 'Optimalizovaný rev/slot', key: 'optimizedRevPerSlot', value: b => (b.hasBookings ? b.optimizedRevPerSlot : null) },
  { label: 'Potenciál %', key: 'potentialPct', value: b => (b.hasBookings ? b.potentialPct : null) },
]

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
    <div className="font-bold mt-2">Zatím žádná data pro doporučení</div>
    <div className="mt-1">Jakmile přibude první rezervace, zobrazí se tu optimalizace flotily (i orientačně za kratší období).</div>
  </div>
)

export default function OptimalniFlotila() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const [selectedLoc, setSelectedLoc] = useState(null)
  const currentSort = useTableSort(CURRENT_COLUMNS)
  const recommendedSort = useTableSort(RECOMMENDED_COLUMNS)
  const benchmarkSort = useTableSort(BENCHMARK_COLUMNS, { key: 'potentialPct', dir: 'desc' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [lRes, mRes, bookings, moves] = await Promise.all([
        supabase.from('branches').select('id, name, city, location, type'),
        supabase.from('motorcycles').select('id, branch_id, category, status, acquired_at, created_at, is_trailer'),
        fetchAllRows(() => supabase.from('bookings').select('id, moto_id, trailer_moto_id, branch_id, start_date, end_date, total_price, status, created_at, payment_status, is_test').not('is_test', 'is', true).order('id')),
        loadMotoMoves(),
      ])
      if (lRes.error) throw lRes.error
      if (mRes.error) throw mRes.error
      setRaw({ locations: lRes.data || [], motorcycles: mRes.data || [], bookings, moves })
      if (lRes.data?.length > 0) setSelectedLoc(lRes.data[0].id)
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  // Sloty pobočky = moto-dny motorek dané kategorie, které na pobočce v období reálně stály (lib/branchFleet.js)
  const fleet = useMemo(() => {
    if (!raw) return null
    const win = periodWindow(period, raw.bookings)
    const tl = buildFleetTimeline({ motorcycles: raw.motorcycles, bookings: raw.bookings, moves: raw.moves, fromDay: win.fromDay, toDay: win.toDay })
    return { win, byBranch: summarizeByBranch(tl, m => (m.category || '').toLowerCase()) }
  }, [raw, period])

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné pobočky</div>

  const { locations, motorcycles, bookings } = raw
  const completed = filterByPeriod(bookings.filter(isRealizedBooking), period, 'created_at')
  const has3mo = hasMinimumData(bookings)

  const motoLocMap = {}, motoCatMap = {}
  for (const m of motorcycles) { motoLocMap[m.id] = m.branch_id; motoCatMap[m.id] = (m.category || '').toLowerCase() }
  const { win, byBranch } = fleet
  // Slot = průměrná motorka v období (moto-dny ÷ dny období); pod MIN_EXPOSURE_DAYS moto-dní se jmenovatel
  // drží na min. „jednom motoměsíci“, aby 1 výpůjčka u motorky přesunuté včera nedala nesmyslný Rev/slot.
  const minSlots = win.days > 0 ? Math.min(MIN_EXPOSURE_DAYS, win.days) / win.days : 0
  const perSlot = (rev, motoDays) => (win.days > 0 && (motoDays > 0 || rev > 0) ? rev / Math.max(motoDays / win.days, minSlots) : 0)

  const locData = {}
  for (const loc of locations) {
    // „Počet“ v Aktuálním složení = AKTUÁLNÍ flotila pobočky (bez vozíků) — vůči ní se počítá doporučený rozdíl;
    // obsazenost a Rev/slot z moto-dnů a rezervací pobočky (bookings.branch_id, u NULL pobočka motorky).
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id && !m.is_trailer)
    const locCompleted = completed.filter(b => effBranchId(b, motoLocMap) === loc.id)
    const st = byBranch[loc.id]
    const cats = [...new Set([...locMotos.map(m => (m.category || '').toLowerCase()), ...Object.keys(st?.cats || {})].filter(Boolean))]
    const hasBookings = locCompleted.length > 0

    const catScores = cats.map(cat => {
      const mc = locMotos.filter(m => (m.category || '').toLowerCase() === cat).length
      const cd = st?.cats[cat] || { motoDays: 0, rentedDays: 0 }
      const catCompleted = locCompleted.filter(b => motoCatMap[b.moto_id] === cat)
      const totalRevenue = catCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
      const utilizationPct = cd.motoDays > 0 ? (cd.rentedDays / cd.motoDays) * 100 : 0
      const revenuePerSlot = perSlot(totalRevenue, cd.motoDays)
      const score = revenuePerSlot * (utilizationPct / 100)
      return { category: cat, motorcycleCount: mc, totalRevenue, utilizationPct, revenuePerSlot, score }
    })

    const optimal = computeOptimalFleet(catScores)
    const totalMotos = locMotos.length
    const totalRevenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const currentRevPerSlot = perSlot(totalRevenue, st?.motoDays || 0)
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
            <select value={selectedLoc || ''} onChange={e => setSelectedLoc(e.target.value)} className="text-sm font-bold w-full md:w-auto" style={{ padding: '8px 14px', borderRadius: 10, border: '2px solid #e5e7eb', background: '#fff', color: '#1a2e22', cursor: 'pointer', minWidth: 220 }}>
              {locations.map(l => <option key={l.id} value={l.id}>{l.name} — {l.city}</option>)}
            </select>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-5">
            {/* Telefon: řádky jako karty (mg-stack) */}
            <div className={STACK_WRAP} style={{ ...cardStyle, padding: undefined, overflowX: 'auto' }}>
              <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Aktuální složení</div>
              <table className="w-full text-sm mg-stack" style={{ borderCollapse: 'collapse' }}>
                <thead><SortableHeaderRow columns={CURRENT_COLUMNS} sort={currentSort.sort} toggle={currentSort.toggle} /></thead>
                <tbody>
                  {cats.length === 0 && <tr><td colSpan={4} className="py-4 text-center" style={{ color: '#888' }}>Žádné motorky</td></tr>}
                  {sortRows(cats, CURRENT_COLUMNS, currentSort.sort).map(c => (
                    <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6', background: c.recommended !== c.motorcycleCount ? '#fffbeb' : undefined }}>
                      <td className="py-2 px-3 font-semibold mg-stack-full">{c.category}</td>
                      <td className="py-2 px-3">{c.motorcycleCount}</td>
                      <td className="py-2 px-3">{c.utilizationPct.toFixed(1)} %</td>
                      <td className="py-2 px-3">{Math.round(c.revenuePerSlot).toLocaleString('cs-CZ')} Kč</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className={STACK_WRAP} style={{ ...cardStyle, padding: undefined, overflowX: 'auto' }}>
              <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Doporučené složení</div>
              <table className="w-full text-sm mg-stack" style={{ borderCollapse: 'collapse' }}>
                <thead><SortableHeaderRow columns={RECOMMENDED_COLUMNS} sort={recommendedSort.sort} toggle={recommendedSort.toggle} /></thead>
                <tbody>
                  {cats.length === 0 && <tr><td colSpan={3} className="py-4 text-center" style={{ color: '#888' }}>Žádné motorky</td></tr>}
                  {sortRows(cats, RECOMMENDED_COLUMNS, recommendedSort.sort).map(c => (
                    <tr key={c.category} style={{ borderBottom: '1px solid #f3f4f6', background: c.recommended !== c.motorcycleCount ? '#fffbeb' : undefined }}>
                      <td className="py-2 px-3 font-semibold mg-stack-full">{c.category}</td>
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

          <div className={STACK_WRAP} style={{ ...cardStyle, padding: undefined, overflowX: 'auto' }}>
            <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Benchmark všech poboček</div>
            <table className="w-full text-sm mg-stack" style={{ borderCollapse: 'collapse' }}>
              <thead><SortableHeaderRow columns={BENCHMARK_COLUMNS} sort={benchmarkSort.sort} toggle={benchmarkSort.toggle} /></thead>
              <tbody>
                {sortRows(benchmark, BENCHMARK_COLUMNS, benchmarkSort.sort).map(b => (
                  <tr key={b.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                    <td className="py-2 px-3 font-semibold mg-stack-full">{b.name}</td>
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
