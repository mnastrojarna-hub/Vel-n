import { useState, useEffect } from 'react'
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Cell, Text,
} from 'recharts'
import { supabase } from '../../lib/supabase'
import { useIsMobile, useMediaQuery } from '../../hooks/useIsMobile'
import { isRealizedBooking } from '../../lib/revenueUtils'
import { effBranchId } from '../../lib/bookingBranch'
import { fetchAllRows, buildFleetTimeline, dayNum } from '../../lib/branchFleet'

import Card from '../../components/ui/Card'

const COLORS = ['#74FB71', '#3dba3a', '#1a8a18', '#fbbf24', '#f87171']

// Karty počítají z rezervací (tabulky moto_performance / branch_performance nikdo neplní a dotazy na ně
// mířily na neexistující sloupce → grafy byly tiše prázdné). Obrat = realizované rezervace (revenueUtils),
// pobočka = pobočka REZERVACE (bookings.branch_id, u NULL pobočka motorky). Jedno načtení pro všechny 3 karty.
let statsCache = null
function loadFleetStats() {
  if (statsCache && Date.now() - statsCache.ts < 30000) return statsCache.promise
  const one = r => { if (r.error) throw r.error; return r.data || [] }
  const promise = Promise.all([
    fetchAllRows(() => supabase.from('bookings').select('id, moto_id, trailer_moto_id, branch_id, start_date, end_date, total_price, status, payment_status, is_test').not('is_test', 'is', true).order('id')),
    supabase.from('motorcycles').select('id, model, branch_id, category, status, acquired_at, created_at, is_trailer').then(one),
    supabase.from('branches').select('id, name').then(one),
  ]).then(([bookings, motorcycles, branches]) => ({ bookings, motorcycles, branches }))
  statsCache = { ts: Date.now(), promise }
  promise.catch(() => { statsCache = null })
  return promise
}

// Desktop popisek osy X „Vytíženost flotily“ (šikmo −20°, ukotvený středem jako dřív). POSLEDNÍ popisek končí
// přímo u svého bodu (kotva end, x = skutečná souřadnice bodu) — se středem přečníval pravý okraj grafu a ořízl
// se (recharts 3 ignoruje textAnchor osy a jeho posun posledního popisku nestačí). Delší název se zkrátí „…“ na
// 112 px ≈ (výška osy 50 + okraj 5 − odsazení 8 − písmo 8) / sin 20°, aby nepřetekl dolní okraj; celý název je
// v tooltipu. Ostatní popisky beze změny (stejné props jako výchozí tick recharts).
// Měří se canvasem — NE přes `style`/`maxLines` u <Text>: recharts by font-size nechal na sdíleném měřicím
// <span> a rozbil zalamování popisků v ostatních grafech.
let measureCtx
function fitLabel(s, maxW) {
  try {
    measureCtx ||= document.createElement('canvas').getContext('2d')
    measureCtx.font = `9px ${getComputedStyle(document.body).fontFamily}`
    if (measureCtx.measureText(s).width <= maxW) return s
    let t = s
    while (t.length > 1 && measureCtx.measureText(t.trimEnd() + '…').width > maxW) t = t.slice(0, -1)
    return t.trimEnd() + '…'
  } catch { return s }
}

function FleetDesktopTick(p) {
  // jen poslední bod u pravého okraje (payload.index > 0); jediná motorka má bod uprostřed → popisek beze změny
  const last = p.index === p.visibleTicksCount - 1 && p.payload.index > 0
  const value = String(p.payload.value)
  // první bod (≥ 2 body) u levého okraje: popisek je vystředěný pod bodem (šikmo −20°) → zkrátit jen když by
  // jeho levá polovina přetekla levý okraj grafu (dlouhé názvy typu „Honda Africa Twin Adventure Sports…“)
  const first = p.index === 0 && p.visibleTicksCount > 1
  const label = last ? fitLabel(value, 112) : first ? fitLabel(value, Math.max(40, 2 * (p.payload.coordinate - 2) / Math.cos(Math.PI / 9))) : value
  return (
    <Text {...p} fontSize={9} fill="#1a2e22" className="recharts-cartesian-axis-tick-value"
      {...(last ? { x: p.payload.coordinate, textAnchor: 'end' } : {})}>
      {label}
    </Text>
  )
}

export function FleetUtilization() {
  const isMobile = useIsMobile() // mobil/tablet: čitelnější popisky osy X (desktop: jen poslední popisek — FleetDesktopTick)
  const isPhone = useMediaQuery('(max-width: 767px)') // telefon: strmější popisky (body jsou blízko u sebe)
  const [data, setData] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  // Vytíženost = dny realizovaného pronájmu / dny, kdy motorka byla ve flotile, za posledních 365 dní (bez vozíků)
  async function load() {
    try {
      const { bookings, motorcycles } = await loadFleetStats()
      const today = dayNum(new Date())
      const tl = buildFleetTimeline({ motorcycles, bookings, moves: [], fromDay: today - 364, toDay: today, today })
      setData(tl.motos.filter(t => t.loc.length > 0)
        .map(t => ({ name: t.moto.model || 'Motorka', využití: Math.round(t.rented.reduce((a, b) => a + b, 0) / t.loc.length * 1000) / 10 }))
        .sort((a, b) => b.využití - a.využití).slice(0, 10))
    } catch (e) { console.error('FleetUtilization', e); setData([]) }
    setLoading(false)
  }

  if (loading) return <Card><div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div></Card>

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Vytíženost flotily</h3>
      {/* mobil/tablet: všechny popisky šikmo (nepřekrývají se), konec popisku u bodu (textAnchor v tick — recharts 3
          prop osy ignoruje), dlouhé názvy zkrácené — celý název v tooltipu */}
      <ResponsiveContainer width="100%" height={isMobile ? (isPhone ? 330 : 290) : 250}>
        <LineChart data={data} {...(isMobile ? { margin: { top: 5, right: 16, bottom: 5, left: isPhone ? 24 : 40 } } : {})}>
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          {isMobile
            ? <XAxis dataKey="name" tick={{ fontSize: 11, fill: '#1a2e22', textAnchor: 'end' }} angle={isPhone ? -55 : -35} height={isPhone ? 120 : 80} interval={0}
                tickFormatter={n => (n.length > 18 ? n.slice(0, 17) + '…' : n)} />
            : <XAxis dataKey="name" tick={FleetDesktopTick} angle={-20} textAnchor="end" height={50} />}
          <YAxis tick={{ fontSize: 13, fill: '#1a2e22' }} unit="%" />
          <Tooltip formatter={(v) => `${v}%`} />
          <Line type="monotone" dataKey="využití" stroke="#74FB71" strokeWidth={2} dot={{ fill: '#74FB71' }} />
        </LineChart>
      </ResponsiveContainer>
    </Card>
  )
}

export function TopMotoRevenue() {
  const isMobile = useIsMobile() // mobil/tablet: širší osa Y, aby se názvy motorek neořezávaly zleva
  const [data, setData] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const { bookings, motorcycles } = await loadFleetStats()
      const rev = {}
      for (const b of bookings) if (b.moto_id && isRealizedBooking(b)) rev[b.moto_id] = (rev[b.moto_id] || 0) + (Number(b.total_price) || 0)
      const model = Object.fromEntries(motorcycles.map(m => [m.id, m.model]))
      setData(Object.entries(rev).sort((a, b) => b[1] - a[1]).slice(0, 5)
        .map(([id, v]) => ({ name: model[id] || 'Motorka', tržby: Math.round(v) })))
    } catch (e) { console.error('TopMotoRevenue', e); setData([]) }
    setLoading(false)
  }

  if (loading) return <Card><div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div></Card>

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Top 5 motorek (tržby)</h3>
      <ResponsiveContainer width="100%" height={200}>
        <BarChart data={data} layout="vertical">
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          <XAxis type="number" tick={{ fontSize: 13, fill: '#1a2e22' }} />
          <YAxis type="category" dataKey="name" width={isMobile ? 160 : 100} tick={{ fontSize: isMobile ? 12 : 13, fill: '#1a2e22' }} />
          <Tooltip formatter={(v) => `${v.toLocaleString('cs-CZ')} Kč`} />
          <Bar dataKey="tržby" radius={[0, 4, 4, 0]}>
            {data.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}

export function BranchComparison() {
  const isPhone = useMediaQuery('(max-width: 767px)') // telefon: všechny názvy poboček šikmo (jinak recharts polovinu skryje)
  const [data, setData] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const { bookings, motorcycles, branches } = await loadFleetStats()
      const mb = Object.fromEntries(motorcycles.map(m => [m.id, m.branch_id]))
      const agg = {}
      for (const b of bookings) {
        if (!isRealizedBooking(b)) continue
        const id = effBranchId(b, mb)
        if (!id) continue
        const a = agg[id] ||= { tržby: 0, rezervace: 0 }
        a.tržby += Number(b.total_price) || 0; a.rezervace++
      }
      setData(branches.map(br => ({ name: br.name || 'Pobočka', tržby: Math.round(agg[br.id]?.tržby || 0), rezervace: agg[br.id]?.rezervace || 0 }))
        .sort((a, b) => b.tržby - a.tržby))
    } catch (e) { console.error('BranchComparison', e); setData([]) }
    setLoading(false)
  }

  if (loading) return <Card><div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div></Card>

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Pobočky — srovnání</h3>
      <ResponsiveContainer width="100%" height={isPhone ? 300 : 250}>
        <BarChart data={data} {...(isPhone ? { margin: { top: 5, right: 10, bottom: 5, left: 10 } } : {})}>
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          {isPhone
            ? <XAxis dataKey="name" tick={{ fontSize: 12, fill: '#1a2e22', textAnchor: 'end' }} angle={-45} height={90} interval={0}
                tickFormatter={n => (n.length > 18 ? n.slice(0, 17) + '…' : n)} />
            : <XAxis dataKey="name" tick={{ fontSize: 13, fill: '#1a2e22' }} />}
          <YAxis tick={{ fontSize: 13, fill: '#1a2e22' }} />
          <Tooltip />
          <Bar dataKey="tržby" fill="#74FB71" radius={[4, 4, 0, 0]} />
          <Bar dataKey="rezervace" fill="#93c5fd" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}
