import { useState, useEffect } from 'react'
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Cell, Text,
} from 'recharts'
import { supabase } from '../../lib/supabase'
import { useIsMobile, useMediaQuery } from '../../hooks/useIsMobile'

import Card from '../../components/ui/Card'

const COLORS = ['#74FB71', '#3dba3a', '#1a8a18', '#fbbf24', '#f87171']

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

  async function load() {
    const { data: perf } = await supabase
      .from('moto_performance')
      .select('moto_id, utilization_rate, motorcycles(model)')
      .order('utilization_rate', { ascending: false })
      .limit(10)
    setData((perf || []).map(p => ({
      name: p.motorcycles?.model || 'Motorka',
      využití: p.utilization_rate || 0,
    })))
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
    const { data: perf } = await supabase
      .from('moto_performance')
      .select('moto_id, total_revenue, motorcycles(model)')
      .order('total_revenue', { ascending: false })
      .limit(5)
    setData((perf || []).map(p => ({
      name: p.motorcycles?.model || 'Motorka',
      tržby: p.total_revenue || 0,
    })))
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
    const { data: bp } = await supabase
      .from('branch_performance')
      .select('*, branches(name)')
      .order('total_revenue', { ascending: false })
    setData((bp || []).map(b => ({
      name: b.branches?.name || 'Pobočka',
      tržby: b.total_revenue || 0,
      rezervace: b.total_bookings || 0,
    })))
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
