import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { filterByPeriod } from './TimePeriodSelector'

// ───────────────────────────────────────────────────────────────────────────
// Web / App funnel — Návštěvy vs. Zahájeno + Použili kalkulačku.
// Zdroj: RPC `get_web_engagement_daily` (tabulka `web_engagement`):
//  • web  — /api/engage z js/engage.js: člověk byl na libovolné stránce ≥5 s
//    s viditelnou kartou a interagoval (myš/dotyk/klávesa); boti, automatizace
//    a ne-prohlížeče se nezapočítají; „calc“ = kalkulačka ceny v katalogu.
//  • app  — core/engagement_service.dart: appka ≥5 s v popředí + dotyk displeje
//    (debug buildy ne); „calc“ = rezervační formulář spočítal cenu.
// 1 člověk = 1 návštěva za den. Zahájené rezervace se srovnávají jen za dny,
// kdy už se návštěvy měřily.
// ───────────────────────────────────────────────────────────────────────────

const cardStyle = { background: '#fff', borderRadius: 14, padding: 16, boxShadow: '0 1px 4px rgba(0,0,0,.06)' }
const pct = (n, d) => (d > 0 ? (n / d) * 100 : 0)
const fmtPct = (n, d) => `${pct(n, d).toFixed(1)} %`
const fmtDay = (iso) => { const [y, m, d] = String(iso).split('-'); return `${+d}. ${+m}. ${y}` }
// lokální den (YYYY-MM-DD) z timestampu rezervace
const localDay = (ts) => {
  const t = new Date(ts)
  if (isNaN(t)) return ''
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`
}

const ALL = () => true
const TEXT = {
  web: {
    calc: 'Použili kalkulačku', started: 'Zahájeno (krok 1)',
    visit: 'Návštěva = člověk byl na libovolné stránce aspoň 5 s a reagoval (myš/dotyk/klávesa); 1 člověk = 1 návštěva za den.',
    sub: 'lidé za den, bez botů',
  },
  app: {
    calc: 'Spočítali cenu (formulář)', started: 'Zahájeno (krok platby)',
    visit: 'Návštěva = appka aspoň 5 s v popředí a dotyk displeje; „Spočítali cenu“ = rezervační formulář ukázal cenu za vybraný termín (appka nemá samostatnou kalkulačku); 1 člověk = 1 návštěva za den.',
    sub: 'lidé za den (Android + iOS)',
  },
}

export default function WebFunnelVisits({ source = 'web', period, inPhase = ALL, bookings }) {
  const L = TEXT[source] || TEXT.web
  const [days, setDays] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    let alive = true
    supabase.rpc('get_web_engagement_daily', { p_source: source }).then(({ data, error: e }) => {
      if (!alive) return
      if (e) setError(e.message)
      else setDays((data || []).map(r => ({ ...r, at: `${r.day}T12:00:00` })))
    })
    return () => { alive = false }
  }, [source])

  const m = useMemo(() => {
    if (!days) return null
    const rows = filterByPeriod(days, period, 'at').filter(r => inPhase(new Date(r.at)))
    const firstDay = days.length ? days[0].day : null
    const visits = rows.reduce((s, r) => s + (r.visits || 0), 0)
    const calc = rows.reduce((s, r) => s + (r.calc || 0), 0)
    const started = firstDay ? bookings.filter(b => localDay(b.created_at) >= firstDay).length : 0
    return { visits, calc, started, firstDay }
  }, [days, period, inPhase, bookings])

  if (error) return <div className="text-xs mb-4" style={{ color: '#dc2626' }}>Návštěvy: {error}</div>
  if (!m) return null

  const bars = [
    { label: 'Návštěvy (≥ 5 s, jen lidé)', value: m.visits, color: '#4285f4' },
    { label: L.calc, value: m.calc, color: '#0ea5e9' },
    { label: L.started, value: m.started, color: '#1a2e22' },
  ]
  const max = Math.max(1, ...bars.map(b => b.value))
  const tiles = [
    { label: 'Návštěvy (≥ 5 s)', value: m.visits, sub: L.sub },
    { label: L.calc, value: m.calc, sub: `${fmtPct(m.calc, m.visits)} z návštěv` },
    { label: L.started, value: m.started, sub: 'za stejné dny jako návštěvy' },
    { label: 'Konverze návštěva → zahájeno', value: fmtPct(m.started, m.visits), sub: `${m.started} z ${m.visits} návštěv` },
  ]

  return (
    <div style={{ ...cardStyle, marginBottom: 24 }}>
      <div className="text-sm font-extrabold mb-1" style={{ color: '#1a2e22' }}>Návštěvy vs. zahájeno</div>
      <div className="text-xs mb-3" style={{ color: '#888' }}>
        {m.firstDay ? `Měří se od ${fmtDay(m.firstDay)}.` : `Zatím žádná data — měření běží od nasazení ${source === 'app' ? 'nové verze appky' : 'webu'}.`}
        {' '}{L.visit}
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
        {tiles.map(k => (
          <div key={k.label} style={{ background: '#f8fcfa', borderRadius: 12, padding: '14px 14px' }}>
            <div className="text-2xl font-extrabold" style={{ color: '#166534' }}>{k.value}</div>
            <div className="text-xs mt-1 font-bold" style={{ color: '#1a2e22' }}>{k.label}</div>
            <div className="text-xs mt-0.5" style={{ color: '#888' }}>{k.sub}</div>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-2">
        {bars.map(b => (
          <div key={b.label}>
            <div className="flex justify-between text-xs mb-1">
              <span className="font-bold" style={{ color: '#1a2e22' }}>{b.label}</span>
              <span style={{ color: '#888' }}>{b.value} • {fmtPct(b.value, m.visits)}</span>
            </div>
            <div style={{ background: '#f1faf7', borderRadius: 8, height: 22, overflow: 'hidden' }}>
              <div style={{ width: `${Math.max(pct(b.value, max), 1.5)}%`, height: '100%', background: b.color, borderRadius: 8, transition: 'width .3s' }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
