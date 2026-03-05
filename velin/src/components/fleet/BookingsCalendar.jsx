import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import StatusBadge from '../ui/StatusBadge'

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

/* Kalendář rezervací pro jednu motorku */
export default function BookingsCalendar({ motoId }) {
  const [bookings, setBookings] = useState([])
  const [maintenance, setMaintenance] = useState([])
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)

  useEffect(() => { loadData() }, [motoId, month])

  async function loadData() {
    setLoading(true)
    const start = new Date(month.getFullYear(), month.getMonth(), 1)
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 0)
    const startStr = start.toISOString().split('T')[0]
    const endStr = end.toISOString().split('T')[0]

    const [bRes, mRes] = await Promise.all([
      supabase.from('bookings')
        .select('id, start_date, end_date, status, user_id, profiles(full_name), total_price')
        .eq('moto_id', motoId)
        .in('status', ['pending', 'active', 'reserved', 'completed'])
        .gte('end_date', startStr).lte('start_date', endStr),
      supabase.from('maintenance_log')
        .select('id, created_at, type')
        .eq('moto_id', motoId)
        .gte('created_at', startStr).lte('created_at', endStr + 'T23:59:59'),
    ])
    setBookings(bRes.data || [])
    setMaintenance(mRes.data || [])
    setLoading(false)
  }

  const year = month.getFullYear()
  const mon = month.getMonth()
  const daysInMonth = new Date(year, mon + 1, 0).getDate()
  const firstDayOfWeek = (new Date(year, mon, 1).getDay() + 6) % 7
  const todayStr = new Date().toISOString().split('T')[0]

  function getDayInfo(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    const isPast = dateStr < todayStr
    const hasService = maintenance.some(m => m.created_at?.slice(0, 10) === dateStr)
    if (hasService) return { type: 'service', bg: '#dc2626', color: '#fff', label: 'Servis' }

    const booking = bookings.find(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0])
    if (booking) {
      if (booking.status === 'pending' || booking.status === 'reserved')
        return { type: 'unconfirmed', bg: '#ffffff', color: '#0f1a14', border: '2px solid #d4e8e0', label: `${booking.profiles?.full_name || '?'} · Nepotvrzeno`, booking }
      if (booking.status === 'completed' || isPast)
        return { type: 'history', bg: '#166534', color: '#fff', label: `${booking.profiles?.full_name || '?'} · Dokončeno`, booking }
      return { type: 'occupied', bg: '#15803d', color: '#fff', label: `${booking.profiles?.full_name || '?'} · ${booking.status}`, booking }
    }
    const isToday = dateStr === todayStr
    return { type: 'free', bg: isToday ? '#bbf7d0' : '#dcfce7', color: isToday ? '#166534' : '#15803d', label: 'Volno' }
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <Card>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <button onClick={() => setMonth(new Date(year, mon - 1, 1))} style={navBtnStyle}>←</button>
        <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS[mon]} {year}</span>
        <button onClick={() => setMonth(new Date(year, mon + 1, 1))} style={navBtnStyle}>→</button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
        {DAYS.map(d => <div key={d} style={{ textAlign: 'center', fontSize: 10, fontWeight: 800, color: '#8aab99', padding: 4 }}>{d}</div>)}
        {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
        {Array.from({ length: daysInMonth }).map((_, i) => {
          const day = i + 1
          const info = getDayInfo(day)
          return (
            <div key={day} title={info.label} style={{
              textAlign: 'center', padding: '8px 2px', borderRadius: 8,
              background: info.bg, color: info.color, fontSize: 12, fontWeight: 800,
              cursor: info.booking ? 'pointer' : 'default', border: info.border || 'none',
            }}>{day}</div>
          )
        })}
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 14, fontSize: 10, fontWeight: 700 }}>
        <Legend bg="#dcfce7" label="Volno" />
        <Legend bg="#15803d" label="Obsazeno" white />
        <Legend bg="#166534" label="Historie" white />
        <Legend bg="#dc2626" label="Servis" white />
        <Legend bg="#fff" label="Nepotvrzeno" border />
      </div>

      {bookings.length > 0 && (
        <div style={{ marginTop: 16 }}>
          {bookings.map(b => (
            <div key={b.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 10px', background: '#f1faf7', borderRadius: 10, marginBottom: 4, fontSize: 12 }}>
              <div>
                <span style={{ fontWeight: 700 }}>{b.profiles?.full_name || 'Zákazník'}</span>
                <span style={{ color: '#8aab99', marginLeft: 8 }}>{b.start_date.split('T')[0]} → {b.end_date.split('T')[0]}</span>
              </div>
              <div className="flex items-center gap-2">
                <StatusBadge status={b.status} />
                <span style={{ fontWeight: 800, color: '#3dba3a' }}>{Number(b.total_price).toLocaleString('cs-CZ')} Kč</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function Legend({ bg, label, white, border }) {
  return (
    <span className="flex items-center gap-1">
      <span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3, background: bg, border: border ? '2px solid #d4e8e0' : 'none' }} />
      <span style={{ color: '#4a6357' }}>{label}</span>
    </span>
  )
}
