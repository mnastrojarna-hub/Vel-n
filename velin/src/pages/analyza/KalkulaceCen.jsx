import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { isRealizedBooking } from '../../lib/revenueUtils'
import { useTableSort, sortRows, SortableHeaderRow } from '../../components/sortableTable'
import { DEFAULT_PARAMS, DAY_COEF, DAY_LABELS, calcMotoPrice, serviceIntervals, seasonDaysPerYear } from '../../lib/priceCalc'

// Analýza → Kalkulace cen: přepis horní tabulky excelu „Moto ceny.xlsx“.
// Servis = roční nájezd × Kč/km, nájezd i půjčené dny z reálných dat (viz lib/priceCalc.js).
// Jen analytika — reálný ceník (moto_day_prices / motorcycles.price_*) se NEMĚNÍ.
const fmt = n => (n == null || isNaN(n)) ? '—' : Math.round(n).toLocaleString('cs-CZ')
const fmtKc = n => (n == null || isNaN(n)) ? '—' : `${Math.round(n).toLocaleString('cs-CZ')} Kč`

const COLUMNS = [
  { label: 'Moto', key: 'model', str: true },
  { label: 'SPZ', key: 'spz', str: true },
  { label: 'Cena moto', key: 'purchase' },
  { label: 'Nájezd/rok', key: 'annualKm' },
  { label: 'Servis/rok', key: 'serviceYear' },
  { label: 'Poj.+čist.', key: 'insurance' },
  { label: 'Půjč. dní/rok', key: 'rentedDays' },
  { label: 'Náklady/rok', key: 'costsYear' },
  { label: 'Nákl. na návratnost', key: 'costsPayback' },
  { label: 'Základ bez marže', key: 'baseNoMargin' },
  { label: 'Zákl. cena', key: 'base' },
  ...Object.keys(DAY_COEF).map(k => ({ label: DAY_LABELS[k], key: `d_${k}` })),
  { label: 'Ceník Po', key: 'currentMon' },
  { label: 'Rozdíl', key: 'diffPct' },
]

const PARAM_FIELDS = [
  ['kcPerKm', 'Servis Kč/km', 0.1], ['insuranceYear', 'Pojištění+čistírna / rok', 100], ['paybackYears', 'Návratnost (roky)', 0.5],
  ['marginPct', 'Marže %', 1], ['seasonFrom', 'Sezóna od (měsíc)', 1], ['seasonTo', 'Sezóna do (měsíc)', 1],
  ['fallbackRentedDays', 'Průměr půjč. dní', 1], ['rentedMin', 'Půjč. dní min', 1], ['rentedMax', 'Půjč. dní max', 1],
  ['kmPerDay', 'Průměr km/den', 10], ['kmPerDayMin', 'Km/den min', 10], ['kmPerDayMax', 'Km/den max', 10],
]

export default function KalkulaceCen() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [raw, setRaw] = useState(null)
  const [form, setForm] = useState({ ...DEFAULT_PARAMS, marginPct: DEFAULT_PARAMS.margin * 100 })
  const sort = useTableSort(COLUMNS, { key: 'base', dir: 'desc' })

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [mRes, bRes, lRes, oRes, segRes, kmRes] = await Promise.all([
        supabase.from('motorcycles').select('id, model, brand, spz, status, is_trailer, purchase_price, acquired_at, price_mon, price_weekday, tracking_unit'),
        supabase.from('bookings').select('id, moto_id, start_date, end_date, status, payment_status, is_test'),
        supabase.from('maintenance_log').select('moto_id, service_date, completed_date, status, is_test'),
        supabase.from('service_orders').select('moto_id, created_at, completed_at, status, is_test'),
        supabase.rpc('analytics_moto_rental_km'),
        supabase.rpc('analytics_moto_km'),
      ])
      for (const r of [mRes, bRes, segRes, kmRes]) if (r.error) throw r.error
      setRaw({ motos: mRes.data || [], bookings: bRes.data || [], logs: lRes.data || [], orders: oRes.data || [], segments: segRes.data || [], km: kmRes.data || [] })
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-t-2" style={{ borderColor: '#74FB71' }} /></div>
  if (error) return <div className="p-4 text-center" style={{ color: '#dc2626' }}>{error}</div>
  if (!raw) return null

  const p = { ...form, margin: (Number(form.marginPct) || 0) / 100 }
  for (const k of ['kcPerKm', 'insuranceYear', 'paybackYears', 'seasonFrom', 'seasonTo', 'fallbackRentedDays', 'rentedMin', 'rentedMax', 'kmPerDay', 'kmPerDayMin', 'kmPerDayMax']) p[k] = Number(form[k]) || DEFAULT_PARAMS[k]
  const today = new Date()
  const kmMap = Object.fromEntries(raw.km.map(r => [r.moto_id, r]))
  const by = (arr, key = 'moto_id') => arr.reduce((acc, x) => ((acc[x[key]] ||= []).push(x), acc), {})
  const segsBy = by(raw.segments), bookBy = by(raw.bookings.filter(isRealizedBooking)), logsBy = by(raw.logs), ordersBy = by(raw.orders)

  // Do kalkulace vstupují VŠECHNY motorky flotily kromě vyřazených a vozíků — nové se objeví samy.
  const rows = raw.motos.filter(m => m.status !== 'retired' && !m.is_trailer).map(m => {
    const c = calcMotoPrice(m, segsBy[m.id], kmMap[m.id], bookBy[m.id], serviceIntervals(logsBy[m.id], ordersBy[m.id], today), p, today)
    const r = { id: m.id, model: m.model, spz: m.spz || '—', unit: m.tracking_unit === 'mh' ? 'mh' : 'km', insurance: p.insuranceYear, ...c }
    for (const k of Object.keys(DAY_COEF)) r[`d_${k}`] = c.days[k]
    return r
  })
  const priced = rows.filter(r => r.ok)
  const avgBase = priced.length ? priced.reduce((s, r) => s + r.base, 0) / priced.length : 0
  const noKm = rows.filter(r => r.kmPerDayRaw == null).length
  const setF = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const card = { background: '#fff', borderRadius: 14, padding: 16, marginBottom: 20, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }

  return (
    <div>
      <div style={{ ...card, background: '#f1faf7' }}>
        <div className="font-bold mb-2" style={{ color: '#1a2e22' }}>Parametry kalkulace <span style={{ fontWeight: 400, fontSize: 12, color: '#666' }}>— jen analýza, reálný ceník se nemění</span></div>
        <div className="flex gap-3 flex-wrap">
          {PARAM_FIELDS.map(([k, label, step]) => (
            <label key={k} style={{ fontSize: 11, color: '#555' }}>{label}<br />
              <input type="number" step={step} value={form[k]} onChange={e => setF(k, e.target.value)}
                style={{ width: 120, padding: '6px 8px', borderRadius: 8, border: '1px solid #cfe5d9', fontWeight: 700, color: '#1a2e22' }} />
            </label>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <Kpi value={fmtKc(avgBase)} label="Ø základní cena (excel B1)" />
        <Kpi value={`${priced.length} / ${rows.length}`} label="Motorek s pořizovací cenou" />
        <Kpi value={`${seasonDaysPerYear(p)} dní`} label="Sezóna / rok (roční přepočet)" />
        <Kpi value={noKm} label="Bez dat o km/den (průměr)" />
      </div>

      <div style={{ ...card, overflowX: 'auto' }}>
        <table className="w-full text-sm" style={{ borderCollapse: 'collapse', whiteSpace: 'nowrap' }}>
          <thead><SortableHeaderRow columns={COLUMNS} sort={sort.sort} toggle={sort.toggle} /></thead>
          <tbody>
            {sortRows(rows, COLUMNS, sort.sort).map((r, i) => (
              <tr key={r.id} style={{ borderBottom: '1px solid #f3f4f6', background: i % 2 === 1 ? '#f9fdfb' : 'transparent', opacity: r.ok ? 1 : 0.55 }}>
                <td className="py-2 px-3 font-semibold">{r.model}</td>
                <td className="py-2 px-3 font-mono">{r.spz}</td>
                <td className="py-2 px-3">{r.ok ? fmtKc(r.purchase) : <span style={{ color: '#b45309' }}>chybí</span>}</td>
                <td className="py-2 px-3" title={r.kmPerDayRaw == null ? `Bez protokolů s km — průměr ${p.kmPerDay} km/den` : `Z dat: ${fmt(r.kmObserved)} ${r.unit} za ${r.kmObservedDays} půjčených dní (${r.kmSource === 'tachometr' ? 'tachometr − koupeno s km' : 'předávací protokoly'}; čtení pod „koupeno s km“ ${fmt(r.purchaseKm)} podlaženo)${r.kmSource === 'mimo' ? ` → mimo ${p.kmPerDayMin}–${p.kmPerDayMax} km/den, použit průměr ${p.kmPerDay}` : ''}`}>
                  {fmt(r.annualKm)} {r.unit}
                  <div style={{ fontSize: 10, color: '#888' }}>
                    {fmt(r.kmPerDay)} {r.unit}/den × {fmt(r.rentedDays)} d
                    {r.kmSource === 'mimo' && <span style={{ color: '#b45309' }}> (z dat {fmt(r.kmPerDayRaw)}/den)</span>}
                    {r.kmSource === 'odhad' && <sup style={{ color: '#b45309' }}> o</sup>}
                  </div>
                </td>
                <td className="py-2 px-3">{fmtKc(r.serviceYear)}</td>
                <td className="py-2 px-3">{fmtKc(r.insurance)}</td>
                <td className="py-2 px-3" title={r.rentedRaw == null ? 'Bez dostatečných dat — průměr' : `Dopočet ${fmt(r.rentedRaw)} dní/rok (${r.rentedObserved} dní za ${r.ownEffDays} sezónních dní vlastnění, −${r.ownServiceDays} servis)${r.rentedSource === 'mimo' ? ` je mimo ${p.rentedMin}–${p.rentedMax} → průměr ${p.fallbackRentedDays}` : ''}`}>
                  {fmt(r.rentedDays)}
                  {r.rentedSource === 'mimo' && <span style={{ color: '#b45309', fontSize: 11 }}> ({fmt(r.rentedRaw)})</span>}
                  {r.rentedSource === 'odhad' && <sup style={{ color: '#b45309' }}> o</sup>}
                </td>
                <td className="py-2 px-3">{fmtKc(r.costsYear)}</td>
                <td className="py-2 px-3">{r.ok ? fmtKc(r.costsPayback) : '—'}</td>
                <td className="py-2 px-3">{r.ok ? fmtKc(r.baseNoMargin) : '—'}</td>
                <td className="py-2 px-3 font-extrabold" style={{ color: '#166534' }}>{r.ok ? fmtKc(r.base) : '—'}</td>
                {Object.keys(DAY_COEF).map(k => <td key={k} className="py-2 px-3">{r.ok ? fmt(r[`d_${k}`]) : '—'}</td>)}
                <td className="py-2 px-3">{r.currentMon > 0 ? fmtKc(r.currentMon) : '—'}</td>
                <td className="py-2 px-3 font-semibold" style={{ color: r.diffPct == null ? '#888' : r.diffPct > 0 ? '#dc2626' : '#16a34a' }}>
                  {r.ok && r.diffPct != null ? `${r.diffPct > 0 ? '+' : ''}${r.diffPct.toFixed(0)} %` : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="text-xs mt-3" style={{ color: '#6b7280', whiteSpace: 'normal' }}>
          Servis/rok = nájezd/rok × Kč/km. Nájezd/rok = km na půjčený den × půjčené dny/rok; km/den z předávacích protokolů (najeté km rezervace / její dny, čtení pod „koupeno s km“ podlaženo),
          mimo {p.kmPerDayMin}–{p.kmPerDayMax} km/den se nahradí průměrem {p.kmPerDay} (hodnota z dat v závorce); <sup>o</sup> = průměr bez dat.
          Půjč. dní/rok z realizovaných rezervací za dobu vlastnění (jen sezónní dny minus dny v servisu, přepočet na sezónu); dopočet pod {p.rentedMin} nebo nad {p.rentedMax} dní se nahradí průměrem {p.fallbackRentedDays} (původní dopočet v závorce); <sup>o</sup> = průměr bez dat (méně než {p.minObsDays} dní).
          Náklady na návratnost = (cena moto + náklady/rok) × roky; základ bez marže = / (půjč. dní × roky); zákl. cena = + marže. Po=Pá=zákl., Út=St=×0,8, Čt=×0,9, So=×1,2, Ne=×1,1.
          Rozdíl = zákl. cena vs. aktuální pondělní ceník (červeně = ceník je pod kalkulací).
        </p>
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
