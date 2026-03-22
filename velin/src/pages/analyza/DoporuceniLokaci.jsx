import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { FLEET_CALC, calcLocationEconomics } from '../../lib/fleetCalc'
import TimePeriodSelector, { filterByPeriod, diffDays } from './TimePeriodSelector'

function DataSourceBadge({ source, derivedFrom }) {
  if (source === 'real') return <span style={{ background: 'rgba(116,251,113,0.15)', color: '#166534', fontSize: 11, fontWeight: 700, padding: '2px 8px', borderRadius: 99 }}>📊 Real data</span>
  if (source === 'derived') return <span style={{ background: 'rgba(59,130,246,0.12)', color: '#1e40af', fontSize: 11, fontWeight: 700, padding: '2px 8px', borderRadius: 99 }}>📊 Odvozeno z: {derivedFrom || 'existující pobočky'}</span>
  return <span style={{ background: 'rgba(0,0,0,0.06)', color: '#6b7280', fontSize: 11, fontWeight: 700, padding: '2px 8px', borderRadius: 99 }}>📐 Odhad</span>
}

function resolveLocationType(env) {
  const map = { 'Centrum města': 'centrum', 'Předměstí': 'předměstí', 'Letiště': 'letiště', 'Hory': 'horská', 'Přehrada/jezero': 'rekreační voda', 'Turistická oblast': 'turistická' }
  return map[env] || 'turistická'
}

function resolveRisk(season) {
  if (season === 'Převážně léto') return 'Nízká zimní obsazenost — zvažte sezónní přesuny'
  if (season === 'Převážně zima') return 'Nízká letní obsazenost — zvažte doplnění touring kategorií'
  if (season === 'Léto + zima') return 'Slabé jaro/podzim — zvažte promo akce v přechodných měsících'
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
        supabase.from('branches').select('id, name, city, location, type'),
        supabase.from('bookings').select('id, moto_id, start_date, end_date, total_price, status, created_at'),
        supabase.from('motorcycles').select('id, branch_id, category, model, purchase_price, status'),
      ])
      if (lRes.error) throw lRes.error; if (bRes.error) throw bRes.error; if (mRes.error) throw mRes.error
      setRaw({ locations: lRes.data || [], bookings: bRes.data || [], motorcycles: mRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw || raw.locations.length === 0) return <div className="p-8 text-center" style={{ color: '#888' }}>Žádné pobočky</div>

  const { locations, bookings, motorcycles } = raw
  const completed = filterByPeriod(bookings.filter(b => b.status === 'completed'), period, 'created_at')

  // Build real utilization map by branchType × category
  const realUtilByType = {}
  const typeSourceNames = {} // track which branch name provides real data per type
  for (const loc of locations) {
    const bt = loc.location || 'turistická'
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id)
    const locCompleted = completed.filter(b => locMotos.some(m => m.id === b.moto_id))
    if (locCompleted.length === 0) continue
    if (!realUtilByType[bt]) { realUtilByType[bt] = {}; typeSourceNames[bt] = loc.name }
    for (const cat of Object.keys(FLEET_CALC.categoryParams)) {
      const catMotos = locMotos.filter(m => (m.category || '').toLowerCase() === cat)
      if (catMotos.length === 0) continue
      let totalRented = 0
      for (const m of catMotos) totalRented += completed.filter(b => b.moto_id === m.id).reduce((s, b) => s + diffDays(b.start_date, b.end_date), 0)
      const realUtil = totalRented / (catMotos.length * 365)
      const existing = realUtilByType[bt][cat]
      realUtilByType[bt][cat] = existing !== undefined ? (existing + realUtil) / 2 : realUtil
    }
  }

  // Per-branch economics using calcLocationEconomics
  const locStats = locations.map(loc => {
    const locMotos = motorcycles.filter(m => m.branch_id === loc.id)
    const bt = loc.location || 'turistická'
    const econ = calcLocationEconomics(locMotos, completed, bt, null, realUtilByType)
    return { ...loc, ...econ, motoCount: locMotos.length }
  }).sort((a, b) => b.totalRevenue - a.totalRevenue)

  const totalRevenue = locStats.reduce((s, l) => s + l.totalRevenue, 0)
  const avgUtil = locStats.length > 0 ? locStats.reduce((s, l) => s + l.avgUtilization, 0) / locStats.length * 100 : 0
  const totalMotos = locStats.reduce((s, l) => s + l.motoCount, 0)
  const avgRevPerSlot = totalMotos > 0 ? totalRevenue / totalMotos : 0

  for (const l of locStats) {
    if (avgRevPerSlot === 0) { l.stars = 3; continue }
    const r = l.revenuePerSlot / avgRevPerSlot
    l.stars = r >= 1.5 ? 5 : r >= 1.2 ? 4 : r >= 0.8 ? 3 : r >= 0.5 ? 2 : 1
  }

  function handleCalc() {
    const locType = resolveLocationType(calcEnv)
    const fleet = FLEET_CALC.defaultFleet[locType] || FLEET_CALC.defaultFleet['turistická']
    const risk = resolveRisk(calcSeason)
    const econ = calcLocationEconomics([], [], locType, fleet, realUtilByType)
    const derivedFrom = typeSourceNames[locType] || null
    setCalcResult({ locType, fleet, risk, econ, derivedFrom })
  }

  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
  const selStyle = { padding: '8px 14px', borderRadius: 10, border: '2px solid #e5e7eb', background: '#fff', color: '#1a2e22', cursor: 'pointer', fontSize: 13, fontWeight: 600, minWidth: 180 }

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />

      {/* Branch cards */}
      <div style={{ marginBottom: 32, paddingBottom: 24, borderBottom: '2px solid #e5e7eb' }}>
        <div className="text-lg font-extrabold mb-2" style={{ color: '#1a2e22' }}>Přehled poboček</div>
        <div className="text-sm mb-5" style={{ color: '#888' }}>{locStats.length} poboček, prům. obsazenost {avgUtil.toFixed(1)}%, celkový obrat {Math.round(totalRevenue).toLocaleString('cs-CZ')} Kč</div>
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
                    <div className="text-xl font-extrabold mb-1" style={{ color: '#166534' }}>{Math.round(l.totalRevenue).toLocaleString('cs-CZ')} Kč</div>
                    <div className="text-xs mb-1" style={{ color: '#854d0e' }}>Zisk / motorku: {Math.round(l.totalProfit / l.motoCount).toLocaleString('cs-CZ')} Kč/rok</div>
                    <div className="flex items-center gap-2 mb-2">
                      <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}><div style={{ width: `${Math.min(l.avgUtilization * 100, 100)}%`, height: '100%', borderRadius: 4, background: '#74FB71' }} /></div>
                      <span className="text-xs font-bold" style={{ minWidth: 40 }}>{(l.avgUtilization * 100).toFixed(1)}%</span>
                    </div>
                    <div className="flex items-center justify-between text-xs" style={{ color: '#888' }}>
                      <span>{l.motoCount} motorek</span>
                      <DataSourceBadge source={l.dataSource} />
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
                <DataSourceBadge source={calcResult.econ.dataSource} derivedFrom={calcResult.derivedFrom} />
              </div>
              {calcResult.econ.dataSource !== 'real' && (
                <p style={{ fontSize: 11, color: '#9ca3af', marginBottom: 12 }}>Odhad z benchmarků odvětví — zpřesní se automaticky po nasbírání dat</p>
              )}

              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
                {[
                  { label: 'Roční revenue', value: `${Math.round(calcResult.econ.totalRevenue).toLocaleString('cs-CZ')} Kč`, color: '#166534' },
                  { label: 'Roční zisk', value: `${Math.round(calcResult.econ.totalProfit).toLocaleString('cs-CZ')} Kč`, color: calcResult.econ.totalProfit > 0 ? '#166534' : '#dc2626' },
                  { label: 'Investice', value: `${Math.round(calcResult.econ.totalInvestment).toLocaleString('cs-CZ')} Kč`, color: '#1a2e22' },
                  { label: 'Návratnost', value: calcResult.econ.paybackMonths ? `~${Math.round(calcResult.econ.paybackMonths)} měsíců` : '—', color: '#1a2e22' },
                ].map(k => (
                  <div key={k.label} style={{ background: '#f1faf7', borderRadius: 10, padding: 12 }}>
                    <div className="text-xs font-bold" style={{ color: '#888' }}>{k.label}</div>
                    <div className="text-lg font-extrabold" style={{ color: k.color }}>{k.value}</div>
                  </div>
                ))}
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <div className="text-xs font-bold mb-2" style={{ color: '#888' }}>Doporučená flotila ({calcResult.fleet.reduce((s, f) => s + f.n, 0)} motorek)</div>
                  <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
                    <thead><tr style={{ borderBottom: '2px solid #e5e7eb' }}><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Kategorie</th><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Ks</th><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Rev/ks/rok</th><th className="text-left font-bold py-1 px-2" style={{ color: '#1a2e22' }}>Zisk/ks/rok</th></tr></thead>
                    <tbody>
                      {calcResult.econ.breakdown.map((b, i) => (
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
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
