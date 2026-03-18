import { useState, useEffect } from 'react'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import { supabase } from '../../lib/supabase'
import { isRevenueEntry } from '../../lib/revenueUtils'

import Card from '../../components/ui/Card'

export default function RevenueChart() {
  const [data, setData] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    const months = []
    const now = new Date()
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
      months.push({
        start: d.toISOString().slice(0, 10),
        end: new Date(d.getFullYear(), d.getMonth() + 1, 0).toISOString().slice(0, 10),
        label: d.toLocaleDateString('cs-CZ', { month: 'short', year: '2-digit' }),
      })
    }

    const { data: entries } = await supabase
      .from('accounting_entries')
      .select('type, amount, date, category, description')
      .gte('date', months[0].start)

    const chart = months.map(m => {
      const mEntries = (entries || []).filter(e => e.date >= m.start && e.date <= m.end)
      return {
        name: m.label,
        tržby: mEntries.filter(e => isRevenueEntry(e)).reduce((s, e) => s + Math.abs(e.amount || 0), 0),
        náklady: mEntries.filter(e => !isRevenueEntry(e)).reduce((s, e) => s + Math.abs(e.amount || 0), 0),
      }
    })
    setData(chart)
    setLoading(false)
  }

  if (loading) return <Card><div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div></Card>

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Tržby vs. náklady (12 měsíců)</h3>
      <ResponsiveContainer width="100%" height={250}>
        <BarChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          <XAxis dataKey="name" tick={{ fontSize: 13, fill: '#1a2e22' }} />
          <YAxis tick={{ fontSize: 13, fill: '#1a2e22' }} />
          <Tooltip formatter={(v) => `${v.toLocaleString('cs-CZ')} Kč`} />
          <Legend wrapperStyle={{ fontSize: 13 }} />
          <Bar dataKey="tržby" fill="#74FB71" radius={[4, 4, 0, 0]} />
          <Bar dataKey="náklady" fill="#fca5a5" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </Card>
  )
}
