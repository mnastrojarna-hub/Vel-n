import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'
import { isRealizedBooking } from '../../lib/revenueUtils'
import { useTableSort, sortRows, SortableHeaderRow } from '../../components/sortableTable'
import NavratnostKapitalu from './NavratnostKapitalu'
import RezervaceDnyTydne from './RezervaceDnyTydne'

const NoData = () => (
  <div className="p-6 text-center" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
    <div style={{ fontSize: 32 }}>⏳</div>
    <div className="font-bold mt-2">Zatím žádná data</div>
    <div className="mt-1">Jakmile přibude první rezervace, zobrazí se tu závěry (i orientačně za kratší období).</div>
  </div>
)

// Sloupce ranking tabulky — key odpovídá poli v motoStats (textové řadíme abecedně).
const RANK_COLUMNS = [
  { label: 'Model', key: 'model', str: true },
  { label: 'Značka', key: 'brand', str: true },
  { label: 'Kategorie', key: 'category', str: true },
  { label: 'Pobočka', key: 'branchName', str: true },
  { label: 'Počet rezervací', key: 'reservationCount' },
  { label: 'Pronajato dní', key: 'rentedDays' },
  { label: 'Dní/rezervace', key: 'avgDaysPerReservation' },
  { label: 'Revenue', key: 'revenue' },
  { label: 'Najeto celkem', key: 'kmDriven' },
  { label: 'Kč/km', key: 'revenuePerKm' },
  { label: 'Revenue/100 km', key: 'revenuePer100km', value: m => m.revenuePerKm },
  { label: 'Obsazenost %', key: 'utilizationIndex' },
  { label: 'Avg Kč/den', key: 'avgDailyRate' },
]

const BRAND_COLUMNS = [
  { label: 'Značka', key: 'brand', str: true },
  { label: 'Počet motorek', key: 'count' },
  { label: 'Prům. obsazenost %', key: 'avgUtilization' },
  { label: 'Revenue/motorku', key: 'revenuePerMoto' },
  { label: 'Performance Score', key: 'performanceScore' },
]

export default function VykonMotorek() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const rankSort = useTableSort(RANK_COLUMNS, { key: 'revenuePerKm', dir: 'desc' })
  const brandSort = useTableSort(BRAND_COLUMNS, { key: 'performanceScore', dir: 'desc' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [mRes, bRes, brRes, kmRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, category, purchase_price, branch_id, status, acquired_at, tracking_unit'),
        supabase.from('bookings').select('id, moto_id, start_date, end_date, total_price, status, created_at, payment_status, is_test'),
        supabase.from('branches').select('id, name'),
        supabase.rpc('analytics_moto_km'),
      ])
      if (mRes.error) throw mRes.error
      if (bRes.error) throw bRes.error
      if (brRes.error) throw brRes.error
      if (kmRes.error) throw kmRes.error
      setRaw({ motorcycles: mRes.data || [], bookings: bRes.data || [], branches: brRes.data || [], motoKm: kmRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.motorcycles.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné motorky</div>

  const { motorcycles, bookings, branches, motoKm } = raw
  const branchMap = Object.fromEntries((branches || []).map(b => [b.id, b.name]))
  // Výkon motorek počítá VÝHRADNĚ ukončené (completed) zaplacené rezervace —
  // bez nadcházejících/probíhajících a bez přičítání hodnoty dárkových poukazů.
  const allCompleted = bookings.filter(b => isRealizedBooking(b) && b.status === 'completed')
  const completed = filterByPeriod(allCompleted, period, 'created_at')
  const has3mo = hasMinimumData(bookings)

  // Zisk na 1 km — vždy CELKOVĚ (nezávisle na zvoleném období): celkové tržby
  // motorky / celkový skutečný nájezd. Nájezd z RPC analytics_moto_km:
  // total_driven = aktuální km (nejvyšší čtení z předávacích protokolů) − km při nákupu.
  const kmByMoto = Object.fromEntries((motoKm || []).map(r => [r.moto_id, r]))
  const totalRevenueByMoto = {}
  for (const b of allCompleted) {
    totalRevenueByMoto[b.moto_id] = (totalRevenueByMoto[b.moto_id] || 0) + (Number(b.total_price) || 0)
  }

  let periodDays = 365
  if (period.type === 'month') periodDays = new Date(period.year, period.month + 1, 0).getDate()
  else if (period.type === 'custom' && period.from && period.to) periodDays = Math.max(1, diffDays(period.from, period.to))

  // Reálné okno pozorování pro tempo tržeb (návratnost kapitálu) — konec okna
  // nejpozději dnes (budoucí část období ještě nic nevydělala).
  const now = new Date()
  let winFrom = null
  let winTo = now
  if (period.type === 'month') { winFrom = new Date(period.year, period.month, 1); winTo = new Date(period.year, period.month + 1, 0) }
  else if (period.type === 'calendar_year') { winFrom = new Date(period.year, 0, 1); winTo = new Date(period.year, 11, 31) }
  else if (period.type === 'fiscal_year') { winFrom = new Date(period.year - 1, 3, 1); winTo = new Date(period.year, 2, 31) }
  else if (period.type === 'custom' && period.from && period.to) { winFrom = new Date(period.from); winTo = new Date(period.to) }
  if (winTo > now) winTo = now

  const motoStats = motorcycles.map(m => {
    const mCompleted = completed.filter(b => b.moto_id === m.id)
    const rentedDays = mCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
    const revenue = mCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const reservationCount = mCompleted.length
    // Doba, po kterou motorka v okně reálně vydělávala — od data pořízení
    // (bez něj od první rezervace motorky). Základ ročního tempa splácení.
    const firstBookingAt = bookings.reduce((min, b) => (b.moto_id === m.id && b.is_test !== true && (!min || b.created_at < min) ? b.created_at : min), null)
    let opStart = m.acquired_at ? new Date(m.acquired_at) : (firstBookingAt ? new Date(firstBookingAt) : null)
    if (winFrom && (!opStart || winFrom > opStart)) opStart = winFrom
    const opDays = opStart ? (opStart > winTo ? 0 : diffDays(opStart, winTo)) : periodDays
    const avgDaysPerReservation = reservationCount > 0 ? rentedDays / reservationCount : 0
    const utilizationIndex = periodDays > 0 ? (rentedDays / periodDays) * 100 : 0
    const avgDailyRate = rentedDays > 0 ? revenue / rentedDays : 0
    const branchName = branchMap[m.branch_id] || '—'
    const kmDriven = Number(kmByMoto[m.id]?.total_driven) || 0
    const totalRevenue = totalRevenueByMoto[m.id] || 0
    const revenuePerKm = kmDriven > 0 ? totalRevenue / kmDriven : null
    const kmUnit = m.tracking_unit === 'mh' ? 'mh' : 'km'
    return { ...m, rentedDays, revenue, reservationCount, avgDaysPerReservation, utilizationIndex, avgDailyRate, branchName, opDays, kmDriven, totalRevenue, revenuePerKm, kmUnit }
  }).sort((a, b) => b.totalRevenue - a.totalRevenue) // výchozí pořadí prázdných hodnot při řazení
  const sortedMotoStats = sortRows(motoStats, RANK_COLUMNS, rankSort.sort)

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
  const maxRevPerMoto = Math.max(...brandStats.map(b => b.revenuePerMoto), 1)
  for (const b of brandStats) b.performanceScore = ((b.revenuePerMoto / maxRevPerMoto) + (b.avgUtilization / 100)) / 2

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />
      {completed.length === 0 && <div className="p-4 text-center mb-4" style={{ background: '#f3f4f6', borderRadius: 14, color: '#6b7280' }}>Žádné dokončené rezervace pro vybrané období</div>}

      {/* Ranking table */}
      <div style={{ background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
        <div className="font-bold" style={{ color: '#1a2e22' }}>Ranking motorek podle zisku na 1 km</div>
        <div className="mb-3" style={{ fontSize: 11, color: '#888' }}>Revenue = pouze UKONČENÉ zaplacené rezervace (dle zvoleného období), bez přičítání dárkových poukazů. Zisk na 1 km se počítá vždy CELKOVĚ: celkové tržby motorky z ukončených rezervací / celkový nájezd (aktuální km dle posledního předávacího protokolu − km při nákupu). Kliknutím na záhlaví sloupce seřadíš sestupně, dalším klikem vzestupně; motorky bez hodnoty jsou vždy na konci.</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <SortableHeaderRow columns={RANK_COLUMNS} sort={rankSort.sort} toggle={rankSort.toggle} />
          </thead>
          <tbody>
            {sortedMotoStats.map((m, i) => (
              <tr key={m.id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent' }}>
                <td className="py-2 px-3 font-semibold">{m.model}</td>
                <td className="py-2 px-3">{m.brand || '—'}</td>
                <td className="py-2 px-3">{m.category || '—'}</td>
                <td className="py-2 px-3">{m.branchName}</td>
                <td className="py-2 px-3">{m.reservationCount}</td>
                <td className="py-2 px-3">{m.rentedDays}</td>
                <td className="py-2 px-3">{m.avgDaysPerReservation.toFixed(1)}</td>
                <td className="py-2 px-3">{Math.round(m.revenue).toLocaleString('cs-CZ')} Kč</td>
                <td className="py-2 px-3">{m.kmDriven > 0 ? `${Math.round(m.kmDriven).toLocaleString('cs-CZ')} ${m.kmUnit}` : '—'}</td>
                <td className="py-2 px-3 font-semibold" style={{ color: '#166534' }}>{m.revenuePerKm != null ? `${m.revenuePerKm.toLocaleString('cs-CZ', { maximumFractionDigits: 1 })} Kč` : '—'}</td>
                <td className="py-2 px-3">{m.revenuePerKm != null ? `${Math.round(m.revenuePerKm * 100).toLocaleString('cs-CZ')} Kč` : '—'}</td>
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

      {/* Výjezdy dle dne v týdnu — vždy za celou dobu fungování */}
      <RezervaceDnyTydne bookings={bookings} motorcycles={motorcycles} />

      {/* KPI: návratnost kapitálu (tržby vs. pořizovací cena) */}
      <NavratnostKapitalu motoStats={motoStats} />

      {/* Brand table - only show conclusions if enough data */}
      {has3mo ? (
        <div style={{ background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
          <div className="font-bold mb-3" style={{ color: '#1a2e22' }}>Výkon značek</div>
          <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
            <thead>
              <SortableHeaderRow columns={BRAND_COLUMNS} sort={brandSort.sort} toggle={brandSort.toggle} />
            </thead>
            <tbody>
              {sortRows(brandStats, BRAND_COLUMNS, brandSort.sort).map(b => {
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
      ) : <NoData />}
    </div>
  )
}
