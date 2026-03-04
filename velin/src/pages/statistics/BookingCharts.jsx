import { useState, useEffect } from 'react'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, LineChart, Line, XAxis, YAxis, CartesianGrid } from 'recharts'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'

const STATUS_COLORS = {
  active: '#74FB71',
  pending: '#fbbf24',
  completed: '#94a3b8',
  cancelled: '#f87171',
  confirmed: '#3dba3a',
}

const STATUS_LABELS = {
  active: 'Aktivní',
  pending: 'Čekající',
  completed: 'Dokončené',
  cancelled: 'Zrušené',
  confirmed: 'Potvrzené',
}

export function BookingsByStatus() {
  const [data, setData] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    const { data: bookings } = await supabase.from('bookings').select('status')
    if (bookings) {
      const counts = {}
      bookings.forEach(b => { counts[b.status] = (counts[b.status] || 0) + 1 })
      setData(Object.entries(counts).map(([status, count]) => ({
        name: STATUS_LABELS[status] || status,
        value: count,
        color: STATUS_COLORS[status] || '#94a3b8',
      })))
    }
    setLoading(false)
  }

  if (loading) return <Card><div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div></Card>

  return (
    <Card>
      <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Rezervace podle statusu</h3>
      <div className="flex items-center">
        <ResponsiveContainer width="60%" height={200}>
          <PieChart>
            <Pie data={data} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={50} outerRadius={80}>
              {data.map((d, i) => <Cell key={i} fill={d.color} />)}
            </Pie>
            <Tooltip />
          </PieChart>
        </ResponsiveContainer>
        <div className="flex-1 space-y-2">
          {data.map(d => (
            <div key={d.name} className="flex items-center gap-2">
              <span className="inline-block w-3 h-3 rounded-full" style={{ background: d.color }} />
              <span className="text-xs font-medium" style={{ color: '#4a6357' }}>{d.name}</span>
              <span className="ml-auto text-xs font-bold" style={{ color: '#0f1a14' }}>{d.value}</span>
            </div>
          ))}
        </div>
      </div>
    </Card>
  )
}

export function CustomerRetention() {
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
        label: d.toLocaleDateString('cs-CZ', { month: 'short' }),
      })
    }

    const { data: bookings } = await supabase
      .from('bookings')
      .select('user_id, start_date')
      .gte('start_date', months[0].start)

    if (bookings) {
      // Count users with >1 booking as "returning"
      const userBookingCounts = {}
      bookings.forEach(b => { userBookingCounts[b.user_id] = (userBookingCounts[b.user_id] || 0) + 1 })

      const chart = months.map(m => {
        const mBookings = bookings.filter(b => b.start_date >= m.start && b.start_date <= m.end)
        const mUsers = [...new Set(mBookings.map(b => b.user_id))]
        const returning = mUsers.filter(u => userBookingCounts[u] > 1).length
        return {
          name: m.label,
          celkem: mUsers.length,
          vracející: returning,
        }
      })
      setData(chart)
    }
    setLoading(false)
  }

  if (loading) return <Card><div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div></Card>

  return (
    <Card>
      <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Zákaznická retence</h3>
      <ResponsiveContainer width="100%" height={250}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="#d4e8e0" />
          <XAxis dataKey="name" tick={{ fontSize: 10, fill: '#8aab99' }} />
          <YAxis tick={{ fontSize: 10, fill: '#8aab99' }} />
          <Tooltip />
          <Line type="monotone" dataKey="celkem" stroke="#74FB71" strokeWidth={2} name="Celkem zákazníků" />
          <Line type="monotone" dataKey="vracející" stroke="#3dba3a" strokeWidth={2} strokeDasharray="5 5" name="Vracející se" />
        </LineChart>
      </ResponsiveContainer>
    </Card>
  )
}
