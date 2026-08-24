import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import TimePeriodSelector, { filterByPeriod } from './TimePeriodSelector'
import { useTableSort, sortRows, SortableHeaderRow } from '../../components/sortableTable'

const MOTO_COLUMNS = [
  { label: 'Model', key: 'model', str: true },
  { label: 'SPZ', key: 'spz', str: true },
  { label: 'Najeto (období)', key: 'totalKm' },
  { label: 'Půjčení', key: 'rentals' },
  { label: 'Km/půjčení', key: 'kmPerRental' },
  { label: 'Km při nákupu', key: 'purchaseKm' },
  { label: 'Aktuální km', key: 'currentKm' },
  { label: 'Najeto celkem', key: 'totalDriven' },
  { label: 'Ø na kalend. den', key: 'perCalDay' },
  { label: 'Ø na půjč. den', key: 'perRentalDay' },
]

const CUST_COLUMNS = [
  { label: 'Zákazník', key: 'name', str: true },
  { label: 'Najeto km (období)', key: 'totalKm' },
  { label: 'Půjčení', key: 'rentals' },
  { label: 'Km/půjčení', key: 'kmPerRental' },
]

// Nájezd km — odvozeno z předávacích protokolů (mileage_start). „Najeto za půjčení"
// = rozdíl po sobě jdoucích předávacích čtení téže motorky (RPC analytics_moto_rental_km).
// Per-den průměry (kalendářní i půjčovní) z analytics_moto_km (celkově od pořízení).
export default function VykonNajezd() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [period, setPeriod] = useState({ type: 'all' })
  const motoSort = useTableSort(MOTO_COLUMNS, { key: 'totalKm', dir: 'desc' })
  const custSort = useTableSort(CUST_COLUMNS, { key: 'totalKm', dir: 'desc' })

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

  // Per motorka — v tabulce jsou i motorky bez segmentu v období, pokud mají
  // celkový nájezd (total_driven = aktuální km dle posledního protokolu − km při nákupu).
  const byMoto = {}
  for (const s of inPeriod) {
    if (!byMoto[s.moto_id]) byMoto[s.moto_id] = { moto_id: s.moto_id, totalKm: 0, rentals: 0 }
    byMoto[s.moto_id].totalKm += Number(s.km_driven) || 0
    byMoto[s.moto_id].rentals++
  }
  const motoIds = new Set([...Object.keys(byMoto), ...motoKm.filter(k => Number(k.total_driven) > 0).map(k => k.moto_id)])
  const motoStats = [...motoIds].map(id => {
    const r = byMoto[id] || { moto_id: id, totalKm: 0, rentals: 0 }
    const m = motoMap[id] || {}
    const km = motoKmMap[id] || {}
    return {
      ...r,
      model: m.model || '—', spz: m.spz || '—', unit: (m.tracking_unit === 'mh' ? 'MH' : 'km'),
      kmPerRental: r.rentals > 0 ? Math.round(r.totalKm / r.rentals) : 0,
      purchaseKm: Number(km.purchase_km) || 0, currentKm: Number(km.current_km) || 0,
      totalDriven: Number(km.total_driven) || 0,
      perCalDay: km.avg_km_per_calendar_day, perRentalDay: km.avg_km_per_rental_day,
    }
  }).sort((a, b) => (b.totalKm - a.totalKm) || (b.totalDriven - a.totalDriven))
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
            <SortableHeaderRow columns={MOTO_COLUMNS} sort={motoSort.sort} toggle={motoSort.toggle} />
          </thead>
          <tbody>
            {sortRows(motoStats, MOTO_COLUMNS, motoSort.sort).map((m, i) => (
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
                <td className="py-2 px-3">{m.purchaseKm > 0 ? `${m.purchaseKm.toLocaleString('cs-CZ')} ${m.unit}` : '0'}</td>
                <td className="py-2 px-3">{m.currentKm > 0 ? `${m.currentKm.toLocaleString('cs-CZ')} ${m.unit}` : '—'}</td>
                <td className="py-2 px-3 font-semibold" style={{ color: '#166534' }}>{m.totalDriven > 0 ? `${m.totalDriven.toLocaleString('cs-CZ')} ${m.unit}` : '—'}</td>
                <td className="py-2 px-3">{m.perCalDay != null ? `${Number(m.perCalDay).toLocaleString('cs-CZ')} ${m.unit}` : '—'}</td>
                <td className="py-2 px-3">{m.perRentalDay != null ? `${Number(m.perRentalDay).toLocaleString('cs-CZ')} ${m.unit}` : '—'}</td>
              </tr>
            ))}
            {motoStats.length === 0 && <tr><td colSpan={10} className="py-3 px-3" style={{ color: '#888' }}>Žádná data pro vybrané období.</td></tr>}
          </tbody>
        </table>
        <p className="text-xs mt-2" style={{ color: '#6b7280' }}>Najeto celkem = aktuální km (dle posledního předávacího protokolu) − km při nákupu; km, se kterými byla motorka koupena, se do nájezdu nepočítají. Ø na kalendářní/půjčovní den = celkový průměr od pořízení (nezávisí na zvoleném období).</p>
      </div>

      {/* Per zákazník */}
      <div style={cardStyle}>
        <div className="font-bold mb-3" style={th}>Nájezd podle zákazníka</div>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse' }}>
          <thead>
            <SortableHeaderRow columns={CUST_COLUMNS} sort={custSort.sort} toggle={custSort.toggle} />
          </thead>
          <tbody>
            {sortRows(custStats, CUST_COLUMNS, custSort.sort).map((c, i) => (
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
