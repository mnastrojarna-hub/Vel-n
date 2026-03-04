import { useState, useEffect } from 'react'
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Cell,
} from 'recharts'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'

const COLORS = ['#74FB71', '#3dba3a', '#1a8a18', '#fbbf24', '#f87171']

export function FleetUtilization() {
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
      <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Vytíženost flotily</h3>
      <ResponsiveContainer width="100%" height={250}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          <XAxis dataKey="name" tick={{ fontSize: 9, fill: '#8aab99' }} angle={-20} textAnchor="end" height={50} />
          <YAxis tick={{ fontSize: 10, fill: '#8aab99' }} unit="%" />
          <Tooltip formatter={(v) => `${v}%`} />
          <Line type="monotone" dataKey="využití" stroke="#74FB71" strokeWidth={2} dot={{ fill: '#74FB71' }} />
        </LineChart>
      </ResponsiveContainer>
    </Card>
  )
}

export function TopMotoRevenue() {
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
      <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Top 5 motorek (tržby)</h3>
      <ResponsiveContainer width="100%" height={200}>
        <BarChart data={data} layout="vertical">
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          <XAxis type="number" tick={{ fontSize: 10, fill: '#8aab99' }} />
          <YAxis type="category" dataKey="name" width={100} tick={{ fontSize: 10, fill: '#8aab99' }} />
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
      <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Pobočky — srovnání</h3>
      <ResponsiveContainer width="100%" height={250}>
        <BarChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          <XAxis dataKey="name" tick={{ fontSize: 10, fill: '#8aab99' }} />
          <YAxis tick={{ fontSize: 10, fill: '#8aab99' }} />
          <Tooltip />
          <Bar dataKey="tržby" fill="#74FB71" radius={[4, 4, 0, 0]} />
          <Bar dataKey="rezervace" fill="#93c5fd" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}
