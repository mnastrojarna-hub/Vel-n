import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { FLEET_CALC, calcBikeEconomics, calcFleetEconomics } from '../../lib/fleetCalc'
import TimePeriodSelector, { filterByPeriod, hasMinimumData, diffDays } from './TimePeriodSelector'

function resolveLocationType(environment, seasonality) {
  if (environment === 'Centrum města') return 'centrum'
  if (environment === 'Předměstí') return 'předměstí'
  if (environment === 'Letiště') return 'letiště'
  if (environment === 'Hory') return 'horská'
  if (environment === 'Přehrada/jezero') return 'rekreační voda'
  if (environment === 'Turistická oblast') return 'turistická'
  return 'turistická'
}

function resolveRisk(seasonality) {
  if (seasonality === 'Převážně léto') return 'Nízká zimní obsazenost — zvažte sezónní přesuny'
  if (seasonality === 'Převážně zima') return 'Nízká letní obsazenost — zvažte doplnění touring kategorií'
  if (seasonality === 'Léto + zima') return 'Slabé jaro/podzim — zvažte promo akce v přechodných měsících'
  return 'Celoroční provoz — udržujte rovnoměrné pokrytí kategorií'
}

export default function DoporuceniLokaci() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const [calcEnv, setCalcEnv] = useState('Centrum města')
  const [calcSeason, setCalcSeason] = useState('Celoroční')
  const [calcResult, setCalcResult] = useState(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [lRes, bRes, mRes] = await Promise.all([
        supabase.from('branches').select('id, name, city, type'),
        supabase.from('bookings').select('moto_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('motorcycles').select('id, branch_id, category, status'),
      ])
      if (lRes.error) throw lRes.error
      if (bRes.error) throw bRes.error
      if (mRes.error) throw mRes.error
      setRaw({ locations: lRes.data || [], bookings: bRes.data || [], motorcycles: mRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné pobočky</div>

  const { locations, bookings, motorcycles } = raw
  const completed = filterByPeriod(bookings.filter(b => b.status === 'completed'), period, 'created_at')

  let periodDays = 365
  if (period.type === 'month') periodDays = new Date(period.year, period.month + 1, 0).getDate()
  else if (period.type === 'custom' && period.from && period.to) periodDays = Math.max(1, diffDays(period.from, period.to))

  // Compute real utilization by branchType × category
  const realUtilMap = {}
  for (const loc of locations) {
    const bt = loc.type || 'turistická'
    if (!realUtilMap[bt]) realUtilMap[bt] = {}
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id)
    for (const cat of Object.keys(FLEET_CALC.categoryParams)) {
      const catMotos = locMotos.filter(m => (m.category || '').toLowerCase() === cat)
      if (catMotos.length === 0) continue
      let totalRented = 0
      for (const moto of catMotos) {
        const mb = completed.filter(b => b.moto_id === moto.id)
        totalRented += mb.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
      }
      const realUtil = totalRented / (catMotos.length * periodDays)
      const existing = realUtilMap[bt][cat]
      realUtilMap[bt][cat] = existing !== undefined ? (existing + realUtil) / 2 : realUtil
    }
  }

  // Branch stats
  const locStats = locations.map(loc => {
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id)
    const locMotoIds = new Set(locMotos.map(m => m.id))
    const locCompleted = completed.filter(b => locMotoIds.has(b.moto_id))
    const revenue = locCompleted.reduce((s, b) => s + (Number(b.total_price) || 0), 0)
    const rentedDays = locCompleted.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
    const motoCount = locMotos.length
    const utilizationPct = motoCount > 0 ? (rentedDays / (motoCount * periodDays)) * 100 : 0
    const revPerSlot = motoCount > 0 ? revenue / motoCount : 0

    // Per-bike profit
    let avgProfitPerBike = null
    if (motoCount > 0) {
      let pSum = 0, pCount = 0
      for (const m of locMotos) {
        const mb = locCompleted.filter(b => b.moto_id === m.id)
        const rd = mb.reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
        const econ = calcBikeEconomics(m.category, loc.type || 'turistická', rd / periodDays)
        if (econ) { pSum += econ.annualProfit; pCount++ }
      }
      if (pCount > 0) avgProfitPerBike = pSum / pCount
    }

    return { ...loc, revenue, motoCount, utilizationPct, revPerSlot, avgProfitPerBike }
  }).sort((a, b) => b.revenue - a.revenue)

  const totalRevenue = locStats.reduce((s, l) => s + l.revenue, 0)
  const avgUtil = locStats.length > 0 ? locStats.reduce((s, l) => s + l.utilizationPct, 0) / locStats.length : 0
  const totalMotos = locStats.reduce((s, l) => s + l.motoCount, 0)
  const avgRevPerSlot = totalMotos > 0 ? totalRevenue / totalMotos : 0

  // Star rating
  for (const l of locStats) {
    if (avgRevPerSlot === 0) { l.stars = 3; continue }
    const r = l.revPerSlot / avgRevPerSlot
    l.stars = r >= 1.5 ? 5 : r >= 1.2 ? 4 : r >= 0.8 ? 3 : r >= 0.5 ? 2 : 1
  }

  function handleCalc() {
    const locType = resolveLocationType(calcEnv, calcSeason)
    const fleet = FLEET_CALC.defaultFleet[locType] || FLEET_CALC.defaultFleet['turistická']
    const risk = resolveRisk(calcSeason)
    const hasRealData = !!realUtilMap[locType] && Object.keys(realUtilMap[locType]).length > 0
    const economics = calcFleetEconomics(fleet, locType, hasRealData ? realUtilMap[locType] : null)
    const paybackMonths = economics.totalProfit > 0 ? (economics.totalInvestment / economics.totalProfit) * 12 : null
    setCalcResult({ locType, fleet, risk, economics, paybackMonths, hasRealData })
  }

  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
  const selStyle = { padding: '8px 14px', borderRadius: 10, border: '2px solid #e5e7eb', background: '#fff', color: '#1a2e22', cursor: 'pointer', fontSize: 13, fontWeight: 600, minWidth: 180 }

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />

      {/* Branch cards */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-2" style={{ color: '#1a2e22' }}>Přehled poboček</div>
        <div className="text-sm mb-5" style={{ color: '#888' }}>{locStats.length} poboček, průměrná obsazenost {avgUtil.toFixed(1)}%, celkový obrat {Math.round(totalRevenue).toLocaleString('cs-CZ')} Kč</div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {locStats.map(l => {
            const status = l.stars >= 4 ? { icon: '🟢', text: 'Výkonná' } : l.stars >= 3 ? { icon: '🟡', text: 'Průměrná' } : { icon: '🔴', text: 'Podvýkonná' }
            return (
              <div key={l.id} style={cardStyle}>
                <div className="flex items-start justify-between mb-2">
                  <div><div className="font-bold text-sm" style={{ color: '#1a2e22' }}>{l.name}</div><div className="text-xs" style={{ color: '#888' }}>{l.city}</div></div>
                  <span style={{ background: '#f3f4f6', color: '#6b7280', borderRadius: 8, padding: '2px 8px', fontSize: 10, fontWeight: 700 }}>{l.type || '⚠️ Nenastaveno'}</span>
                </div>
                {l.motoCount === 0 ? <div className="text-sm" style={{ color: '#888' }}>Žádná data</div> : (
                  <>
                    <div className="text-xl font-extrabold mb-1" style={{ color: '#166534' }}>{Math.round(l.revenue).toLocaleString('cs-CZ')} Kč</div>
                    {l.avgProfitPerBike != null && <div className="text-xs mb-2" style={{ color: '#854d0e' }}>Zisk / motorku: {Math.round(l.avgProfitPerBike).toLocaleString('cs-CZ')} Kč/rok</div>}
                    <div className="flex items-center gap-2 mb-2">
                      <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}><div style={{ width: `${Math.min(l.utilizationPct, 100)}%`, height: '100%', borderRadius: 4, background: '#74FB71' }} /></div>
                      <span className="text-xs font-bold" style={{ minWidth: 40 }}>{l.utilizationPct.toFixed(1)}%</span>
                    </div>
                    <div className="flex items-center justify-between text-xs" style={{ color: '#888' }}>
                      <span>{l.motoCount} motorek</span>
                      <span style={{ letterSpacing: 1 }}>{'⭐'.repeat(l.stars)}{'☆'.repeat(5 - l.stars)}</span>
                      <span>{status.icon} {status.text}</span>
                    </div>
                  </>
                )}
              </div>
            )
          })}
        </div>
      </div>

      {/* Calculator */}
      <div>
        <div className="text-lg font-extrabold mb-4" style={{ color: '#1a2e22' }}>Kalkulátor nové pobočky</div>
        <div style={cardStyle}>
          <div className="flex flex-wrap gap-4 mb-4">
            <div>
              <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Typ prostředí</div>
              <select value={calcEnv} onChange={e => setCalcEnv(e.target.value)} style={selStyle}>
                {['Centrum města', 'Předměstí', 'Letiště', 'Turistická oblast', 'Hory', 'Přehrada/jezero'].map(o => <option key={o} value={o}>{o}</option>)}
              </select>
            </div>
            <div>
              <div className="text-xs font-bold mb-1" style={{ color: '#888' }}>Sezónnost</div>
              <select value={calcSeason} onChange={e => setCalcSeason(e.target.value)} style={selStyle}>
                {['Celoroční', 'Převážně léto', 'Převážně zima', 'Léto + zima'].map(o => <option key={o} value={o}>{o}</option>)}
              </select>
            </div>
          </div>
          <button onClick={handleCalc} className="text-sm font-extrabold cursor-pointer" style={{ padding: '10px 24px', borderRadius: 10, border: 'none', background: '#74FB71', color: '#1a2e22' }}>Spočítat ekonomiku</button>

          {calcResult && (
            <div className="mt-5" style={{ borderTop: '2px solid #e5e7eb', paddingTop: 16 }}>
              <div className="mb-3 flex items-center gap-3">
                <span className="text-sm font-extrabold" style={{ background: '#74FB71', color: '#1a2e22', borderRadius: 10, padding: '6px 18px' }}>{calcResult.locType}</span>
                <span className="text-xs font-bold" style={{ background: calcResult.hasRealData ? '#dcfce7' : '#f3f4f6', color: calcResult.hasRealData ? '#166534' : '#6b7280', borderRadius: 8, padding: '3px 10px' }}>
                  {calcResult.hasRealData ? '📊 Kalkulováno z real dat' : '📐 Kalkulováno z benchmarků'}
                </span>
              </div>

              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
                <div style={{ background: '#f1faf7', borderRadius: 10, padding: 12 }}>
                  <div className="text-xs font-bold" style={{ color: '#888' }}>Roční revenue</div>
                  <div className="text-lg font-extrabold" style={{ color: '#166534' }}>{Math.round(calcResult.economics.totalRevenue).toLocaleString('cs-CZ')} Kč</div>
                </div>
                <div style={{ background: '#f1faf7', borderRadius: 10, padding: 12 }}>
                  <div className="text-xs font-bold" style={{ color: '#888' }}>Roční zisk</div>
                  <div className="text-lg font-extrabold" style={{ color: calcResult.economics.totalProfit > 0 ? '#166534' : '#dc2626' }}>{Math.round(calcResult.economics.totalProfit).toLocaleString('cs-CZ')} Kč</div>
                </div>
                <div style={{ background: '#f1faf7', borderRadius: 10, padding: 12 }}>
                  <div className="text-xs font-bold" style={{ color: '#888' }}>Investice</div>
                  <div className="text-lg font-extrabold" style={{ color: '#1a2e22' }}>{Math.round(calcResult.economics.totalInvestment).toLocaleString('cs-CZ')} Kč</div>
                </div>
                <div style={{ background: '#f1faf7', borderRadius: 10, padding: 12 }}>
                  <div className="text-xs font-bold" style={{ color: '#888' }}>Návratnost</div>
                  <div className="text-lg font-extrabold" style={{ color: '#1a2e22' }}>{calcResult.paybackMonths ? `~${Math.round(calcResult.paybackMonths)} měsíců` : '—'}</div>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                <div>
                  <div className="text-xs font-bold mb-2" style={{ color: '#888' }}>Doporučená flotila ({calcResult.fleet.reduce((s, f) => s + f.n, 0)} motorek)</div>
                  <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                    <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Kategorie</th><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Počet</th><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Rev/motorku/rok</th><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Zisk/motorku/rok</th></tr></thead>
                    <tbody>
                      {calcResult.economics.breakdown.map((b, i) => (
                        <tr key={i} style={{ borderBottom: '1px solid #f3f4f6' }}>
                          <td className="py-1 px-2 font-semibold">{b.category}</td>
                          <td className="py-1 px-2 font-bold" style={{ color: '#166534' }}>{b.count}×</td>
                          <td className="py-1 px-2">{Math.round(b.annualRevenue).toLocaleString('cs-CZ')} Kč</td>
                          <td className="py-1 px-2" style={{ color: b.annualProfit > 0 ? '#166534' : '#dc2626' }}>{Math.round(b.annualProfit).toLocaleString('cs-CZ')} Kč</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div>
                  <div className="text-xs font-bold mb-2" style={{ color: '#888' }}>Klíčové riziko</div>
                  <div style={{ background: '#fffbeb', borderRadius: 10, padding: '8px 12px', border: '1px solid #fde68a', fontSize: 12, color: '#854d0e', fontWeight: 600 }}>⚠️ {calcResult.risk}</div>
                  {calcResult.hasRealData && <div className="text-xs mt-3" style={{ color: '#166534' }}>Výpočet vychází z reálné obsazenosti vašich poboček tohoto typu.</div>}
                  {!calcResult.hasRealData && <div className="text-xs mt-3" style={{ color: '#6b7280' }}>Výpočet vychází z benchmarků odvětví (sezóna 7 měsíců).</div>}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
