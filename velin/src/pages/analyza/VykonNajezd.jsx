import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod } from './TimePeriodSelector'

// Nájezd km — odvozeno z předávacích protokolů (mileage_start). „Najeto za půjčení"
// = rozdíl po sobě jdoucích předávacích čtení téže motorky (RPC analytics_moto_rental_km).
// Per-den průměry (kalendářní i půjčovní) z analytics_moto_km (celkově od pořízení).
export default function VykonNajezd() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true); setError(null)
    try {
      const [segRes, motoRes, profRes, motoKmRes] = await Promise.all([
        supabase.rpc('analytics_moto_rental_km'),
        supabase.from('motorcycles').select('id, model, spz, tracking_unit'),
        supabase.from('profiles').select('id, full_name, email'),
        supabase.rpc('analytics_moto_km'),
      ])
      if (segRes.error) throw segRes.error
      setRaw({
        segments: segRes.data || [],
        motos: motoRes.data || [],
        profiles: profRes.data || [],
        motoKm: motoKmRes.data || [],
      })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw) return null

  const { segments, motos, profiles, motoKm } = raw
  const motoMap = Object.fromEntries(motos.map(m => [m.id, m]))
  const profMap = Object.fromEntries(profiles.map(p => [p.id, p]))
  const motoKmMap = Object.fromEntries(motoKm.map(r => [r.moto_id, r]))

  // Jen uzavřené segmenty (mají další čtení) lze přiřadit najeté km.
  const closed = segments.filter(s => s.next_reading != null)
  const inPeriod = filterByPeriod(closed, period, 'start_date')

  // Per motorka
  const byMoto = {}
  for (const s of inPeriod) {
    if (!byMoto[s.moto_id]) byMoto[s.moto_id] = { moto_id: s.moto_id, totalKm: 0, rentals: 0 }
    byMoto[s.moto_id].totalKm += Number(s.km_driven) || 0
    byMoto[s.moto_id].rentals++
  }
  const motoStats = Object.values(byMoto).map(r => {
    const m = motoMap[r.moto_id] || {}
    const km = motoKmMap[r.moto_id] || {}
    return {
      ...r,
      model: m.model || '—', spz: m.spz || '—', unit: (m.tracking_unit === 'mh' ? 'MH' : 'km'),
      kmPerRental: r.rentals > 0 ? Math.round(r.totalKm / r.rentals) : 0,
      perCalDay: km.avg_km_per_calendar_day, perRentalDay: km.avg_km_per_rental_day,
    }
  }).sort((a, b) => b.totalKm - a.totalKm)
  const maxMotoKm = Math.max(...motoStats.map(m => m.totalKm), 1)

  // Per zákazník
  const byCust = {}
  for (const s of inPeriod) {
    if (!s.user_id) continue
    if (!byCust[s.user_id]) byCust[s.user_id] = { user_id: s.user_id, totalKm: 0, rentals: 0 }
    byCust[s.user_id].totalKm += Number(s.km_driven) || 0
    byCust[s.user_id].rentals++
  }
  const custStats = Object.values(byCust).map(r => {
    const p = profMap[r.user_id] || {}
    return { ...r, name: p.full_name || p.email || '—', kmPerRental: r.rentals > 0 ? Math.round(r.totalKm / r.rentals) : 0 }
  }).sort((a, b) => b.totalKm - a.totalKm)

  const totalKm = inPeriod.reduce((s, x) => s + (Number(x.km_driven) || 0), 0)
  const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, marginBottom: 24, overflowX: 'auto', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
  const th = { color: '#1a2e22' }

  return (
    <div>
      <TimePeriodSelector value={period} onChange={setPeriod} />

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <Kpi value={`${totalKm.toLocaleString('cs-CZ')} km`} label="Najeto celkem (období)" />
        <Kpi value={motoStats.length} label="Motorek s nájezdem" />
        <Kpi value={custStats.length} label="Zákazníků s nájezdem" />
        <Kpi value={`${inPeriod.length ? Math.round(totalKm / inPeriod.length).toLocaleString('cs-CZ') : 0} km`} label="Průměr na půjčení" />
      </div>

      {closed.length === 0 && (
        <div className="p-4 text-center mb-4" style={{ background: '#fffbeb', borderRadius: 14, border: '1px solid #fde68a', color: '#854d0e', fontSize: 13 }}>
          Zatím nejsou data o nájezdu. Km se načítají z předávacích protokolů — „najeto za půjčení" se ukáže, jakmile má motorka aspoň dvě předávací čtení.
        </div>
      )}

      {/* Per motorka */}
      <div style={cardStyle}>
        <div className="font-bold mb-3" style={th}>Nájezd podle motorky</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Model', 'SPZ', 'Najeto (období)', 'Půjčení', 'Km/půjčení', 'Ø na kalend. den', 'Ø na půjč. den'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {motoStats.map((m, i) => (
              <tr key={m.moto_id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent' }}>
                <td className="py-2 px-3 font-semibold">{m.model}</td>
                <td className="py-2 px-3 font-mono">{m.spz}</td>
                <td className="py-2 px-3" style={{ minWidth: 160 }}>
                  <div className="flex items-center gap-2">
                    <div style={{ flex: 1, height: 8, borderRadius: 4, background: '#e5e7eb' }}>
                      <div style={{ width: `${Math.min((m.totalKm / maxMotoKm) * 100, 100)}%`, height: '100%', borderRadius: 4, background: '#74FB71' }} />
                    </div>
                    <span style={{ fontSize: 11, minWidth: 64 }}>{m.totalKm.toLocaleString('cs-CZ')} {m.unit}</span>
                  </div>
                </td>
                <td className="py-2 px-3">{m.rentals}</td>
                <td className="py-2 px-3">{m.kmPerRental.toLocaleString('cs-CZ')} {m.unit}</td>
                <td className="py-2 px-3">{m.perCalDay != null ? `${Number(m.perCalDay).toLocaleString('cs-CZ')} ${m.unit}` : '—'}</td>
                <td className="py-2 px-3">{m.perRentalDay != null ? `${Number(m.perRentalDay).toLocaleString('cs-CZ')} ${m.unit}` : '—'}</td>
              </tr>
            ))}
            {motoStats.length === 0 && <tr><td colSpan={7} className="py-3 px-3" style={{ color: '#888' }}>Žádná data pro vybrané období.</td></tr>}
          </tbody>
        </table>
        <p className="text-xs mt-2" style={{ color: '#6b7280' }}>Ø na kalendářní/půjčovní den = celkový průměr od pořízení (nezávisí na zvoleném období).</p>
      </div>

      {/* Per zákazník */}
      <div style={cardStyle}>
        <div className="font-bold mb-3" style={th}>Nájezd podle zákazníka</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
              {['Zákazník', 'Najeto km (období)', 'Půjčení', 'Km/půjčení'].map(h => (
                <th key={h} className="text-left font-bold py-2 px-3" style={th}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {custStats.map((c, i) => (
              <tr key={c.user_id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent' }}>
                <td className="py-2 px-3 font-semibold">{c.name}</td>
                <td className="py-2 px-3">{c.totalKm.toLocaleString('cs-CZ')} km</td>
                <td className="py-2 px-3">{c.rentals}</td>
                <td className="py-2 px-3">{c.kmPerRental.toLocaleString('cs-CZ')} km</td>
              </tr>
            ))}
            {custStats.length === 0 && <tr><td colSpan={4} className="py-3 px-3" style={{ color: '#888' }}>Žádná data pro vybrané období.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function Kpi({ value, label }) {
  return (
    <div style={{ background: '#fff', borderRadius: 14, padding: '18px 16px', boxShadow: '0 1px 4px rgba(0,0,0,.06)' }}>
      <div className="text-xl font-extrabold" style={{ color: '#166534' }}>{value}</div>
      <div className="text-xs mt-1" style={{ color: '#888' }}>{label}</div>
    </div>
  )
}
