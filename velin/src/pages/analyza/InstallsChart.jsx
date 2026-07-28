/**
 * MotoGo24 Velín — Analýza / Aplikace: graf instalací appky v čase.
 *
 * Data: RPC `get_app_install_timeseries()` (SECURITY DEFINER, is_admin gate)
 *  - installs      = nové instalace per den × platforma (Android/iOS) z
 *                    `app_installations.first_seen_at` — PŘESNÉ od 2026-06-28
 *                    (build s InstallationService); starší instalace se
 *                    objeví v den prvního heartbeatu po updatu.
 *  - registrations = registrace účtů per den (`profiles.created_at`) —
 *                    kompletní historie růstu uživatelské základny.
 *
 * Režimy: Nové (přírůstky za období) / Celkem (kumulativní křivka);
 * období 14 dní – Vše; agregace den/týden/měsíc se volí automaticky.
 */
import { useEffect, useMemo, useState } from 'react'
import {
  ResponsiveContainer, ComposedChart, Bar, Line, Area, XAxis, YAxis,
  CartesianGrid, Tooltip, Legend,
} from 'recharts'
import { supabase } from '../../lib/supabase'

const RANGES = [
  { label: '14 dní', days: 14 },
  { label: '30 dní', days: 30 },
  { label: '90 dní', days: 90 },
  { label: '6 měsíců', days: 183 },
  { label: '1 rok', days: 365 },
  { label: 'Vše', days: null },
]

const C = { android: '#3ddc84', ios: '#5f7c8a', total: '#1a2e22', regs: '#b08d2f' }

const dayMs = 86400000
const toDate = (s) => new Date(`${s}T00:00:00`)

/** Klíč bucketu pro daný den: day → ISO den, week → pondělí týdne, month → 1. den měsíce */
function bucketKey(date, bucket) {
  const d = new Date(date)
  if (bucket === 'month') return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
  if (bucket === 'week') {
    const shift = (d.getDay() + 6) % 7
    d.setDate(d.getDate() - shift)
  }
  return d.toISOString().slice(0, 10)
}

function bucketLabel(key, bucket) {
  const d = toDate(key)
  if (bucket === 'month') return d.toLocaleDateString('cs-CZ', { month: 'short', year: '2-digit' })
  return d.toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' })
}

/** Denní řádky → řada bucketů (vyplní i prázdné buckety nulami). */
function buildSeries(rows, fromDate, toDateEnd, bucket, fields, baseline, cumulative) {
  const map = new Map()
  for (const r of rows) {
    const d = toDate(r.d)
    if (d < fromDate || d > toDateEnd) continue
    const k = bucketKey(d, bucket)
    if (!map.has(k)) map.set(k, Object.fromEntries(fields.map((f) => [f, 0])))
    const row = map.get(k)
    for (const f of fields) row[f] += Number(r[f] || 0)
  }
  const out = []
  const cum = { ...baseline }
  const cursor = new Date(bucketKey(fromDate, bucket))
  const last = new Date(bucketKey(toDateEnd, bucket))
  while (cursor <= last) {
    const k = cursor.toISOString().slice(0, 10)
    const vals = map.get(k) || Object.fromEntries(fields.map((f) => [f, 0]))
    const row = { key: k, name: bucketLabel(k, bucket) }
    for (const f of fields) {
      cum[f] = (cum[f] || 0) + vals[f]
      row[f] = cumulative ? cum[f] : vals[f]
    }
    out.push(row)
    if (bucket === 'month') cursor.setMonth(cursor.getMonth() + 1)
    else cursor.setDate(cursor.getDate() + (bucket === 'week' ? 7 : 1))
  }
  return out
}

const btnStyle = (active) => ({
  padding: '5px 12px', borderRadius: 8, fontSize: 12.5, fontWeight: 700,
  cursor: 'pointer', border: '1px solid ' + (active ? '#1a2e22' : '#d7e3dd'),
  background: active ? '#1a2e22' : '#fff', color: active ? '#74FB71' : '#41564b',
})

const cardStyle = {
  background: '#fff', border: '1px solid #e3ece8', borderRadius: 14,
  padding: '16px 18px', boxShadow: '0 2px 10px rgba(26,46,34,.05)', marginBottom: 16,
}

export default function InstallsChart() {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const [range, setRange] = useState(RANGES[1])
  const [mode, setMode] = useState('new') // 'new' | 'cum'

  useEffect(() => {
    supabase.rpc('get_app_install_timeseries').then(({ data, error }) => {
      if (error) setError(error.message || String(error))
      else setData(typeof data === 'string' ? JSON.parse(data) : data)
    })
  }, [])

  const installs = data?.installs || []
  const regs = data?.registrations || []

  const { series, bucket } = useMemo(() => {
    if (!installs.length) return { series: [], bucket: 'day' }
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const firstDay = toDate(installs[0].d)
    const from = range.days ? new Date(today.getTime() - (range.days - 1) * dayMs) : firstDay
    const start = from < firstDay && !range.days ? firstDay : from
    const spanDays = Math.round((today - start) / dayMs) + 1
    const bucket = spanDays <= 92 ? 'day' : spanDays <= 400 ? 'week' : 'month'
    // kumulativní baseline = instalace před začátkem rozsahu (ať „Celkem" ukazuje pravé totály)
    const baseline = { android: 0, ios: 0, other: 0 }
    for (const r of installs) {
      if (toDate(r.d) < start) {
        baseline.android += Number(r.android || 0)
        baseline.ios += Number(r.ios || 0)
        baseline.other += Number(r.other || 0)
      }
    }
    const s = buildSeries(installs, start, today, bucket, ['android', 'ios', 'other'], baseline, mode === 'cum')
      .map((r) => ({ ...r, celkem: r.android + r.ios + r.other }))
    return { series: s, bucket }
  }, [installs, range, mode])

  const regSeries = useMemo(() => {
    if (!regs.length) return []
    const today = new Date(); today.setHours(0, 0, 0, 0)
    const start = toDate(regs[0].d)
    const spanDays = Math.round((today - start) / dayMs) + 1
    const bucket = spanDays <= 92 ? 'day' : spanDays <= 400 ? 'week' : 'month'
    return buildSeries(regs, start, today, bucket, ['n'], { n: 0 }, true)
  }, [regs])

  if (error) return (
    <div style={{ ...cardStyle, background: '#fff3f3', border: '1px solid #f0c0c0', color: '#9a2a2a' }}>
      <strong>Graf instalací se nepodařilo načíst.</strong>
      <div style={{ fontSize: 13, marginTop: 6 }}>{error}</div>
      <div style={{ fontSize: 13, marginTop: 6, color: '#666' }}>
        Zkontroluj, že v Supabase existuje RPC <code>get_app_install_timeseries()</code>.
      </div>
    </div>
  )
  if (!data) return <div style={{ padding: 12, color: '#888' }}>Načítám graf instalací…</div>

  const bucketNote = bucket === 'day' ? 'po dnech' : bucket === 'week' ? 'po týdnech' : 'po měsících'

  return (
    <>
      <div style={cardStyle}>
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, marginBottom: 10 }}>
          <h3 style={{ fontSize: 14, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.4px', color: '#1a2e22', marginRight: 'auto' }}>
            📈 Instalace appky v čase <span style={{ fontWeight: 600, color: '#7a8b82', textTransform: 'none' }}>({bucketNote})</span>
          </h3>
          <div style={{ display: 'flex', gap: 6 }}>
            <button style={btnStyle(mode === 'new')} onClick={() => setMode('new')}>Nové</button>
            <button style={btnStyle(mode === 'cum')} onClick={() => setMode('cum')}>Celkem</button>
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {RANGES.map((r) => (
              <button key={r.label} style={btnStyle(range.label === r.label)} onClick={() => setRange(r)}>{r.label}</button>
            ))}
          </div>
        </div>
        <ResponsiveContainer width="100%" height={280}>
          <ComposedChart data={series}>
            <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
            <XAxis dataKey="name" tick={{ fontSize: 11 }} />
            <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
            <Tooltip />
            <Legend />
            {mode === 'new' ? (
              <>
                <Bar dataKey="android" name="Android" stackId="p" fill={C.android} />
                <Bar dataKey="ios" name="iOS" stackId="p" fill={C.ios} />
                <Line type="monotone" dataKey="celkem" name="Celkem" stroke={C.total} strokeWidth={2} dot={false} />
              </>
            ) : (
              <>
                <Line type="monotone" dataKey="android" name="Android" stroke={C.android} strokeWidth={2.5} dot={false} />
                <Line type="monotone" dataKey="ios" name="iOS" stroke={C.ios} strokeWidth={2.5} dot={false} />
                <Line type="monotone" dataKey="celkem" name="Celkem" stroke={C.total} strokeWidth={2.5} dot={false} />
              </>
            )}
          </ComposedChart>
        </ResponsiveContainer>
        <p style={{ fontSize: 12, color: '#7a8b82', lineHeight: 1.55, marginTop: 8 }}>
          Přesná evidence instalací běží od <strong>{data.tracking_since ? toDate(data.tracking_since).toLocaleDateString('cs-CZ') : '—'}</strong>
          {' '}(build s vlastní evidencí). Zařízení nainstalovaná dřív se v grafu objeví v den, kdy se poprvé
          ohlásila po aktualizaci — starší per-platform historie z Google Play / App Store není v DB dostupná.
        </p>
      </div>

      <div style={cardStyle}>
        <h3 style={{ fontSize: 14, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.4px', color: '#1a2e22', marginBottom: 10 }}>
          👤 Uživatelské účty — celá historie <span style={{ fontWeight: 600, color: '#7a8b82', textTransform: 'none' }}>(kumulativně, registrace profilů)</span>
        </h3>
        <ResponsiveContainer width="100%" height={220}>
          <ComposedChart data={regSeries}>
            <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
            <XAxis dataKey="name" tick={{ fontSize: 11 }} />
            <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
            <Tooltip />
            <Area type="monotone" dataKey="n" name="Účty celkem" stroke={C.regs} fill="#f4e9c8" strokeWidth={2.5} />
          </ComposedChart>
        </ResponsiveContainer>
        <p style={{ fontSize: 12, color: '#7a8b82', lineHeight: 1.55, marginTop: 8 }}>
          Historický pohled na růst uživatelské základny (registrace účtů, vč. registrací z webu) —
          jde nejdál do minulosti, kam data sahají; rozpad na Android/iOS u starých období neexistuje.
        </p>
      </div>
    </>
  )
}
