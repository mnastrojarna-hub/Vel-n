import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'
import Button from '../ui/Button'
import Modal from '../ui/Modal'
import StatusBadge, { getDisplayStatus } from '../ui/StatusBadge'

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }
const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

/* Kalendář rezervací pro jednu motorku */
export default function BookingsCalendar({ motoId }) {
  const [bookings, setBookings] = useState([])
  const [maintenance, setMaintenance] = useState([])
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)
  const [showAddBooking, setShowAddBooking] = useState(false)
  const [showAddService, setShowAddService] = useState(false)
  const [selectedDay, setSelectedDay] = useState(null)

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

  function handleDayClick(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    setSelectedDay(dateStr)
    const info = getDayInfo(day)
    if (info.type === 'free') {
      setShowAddBooking(true)
    }
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <>
      <Card>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          <button onClick={() => setMonth(new Date(year, mon - 1, 1))} style={navBtnStyle}>←</button>
          <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS[mon]} {year}</span>
          <button onClick={() => setMonth(new Date(year, mon + 1, 1))} style={navBtnStyle}>→</button>
        </div>

        <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
          <Button green onClick={() => setShowAddBooking(true)}>+ Nová rezervace</Button>
          <Button onClick={() => setShowAddService(true)} style={{ background: '#dbeafe', color: '#2563eb' }}>+ Servisní událost</Button>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
          {DAYS.map(d => <div key={d} style={{ textAlign: 'center', fontSize: 10, fontWeight: 800, color: '#8aab99', padding: 4 }}>{d}</div>)}
          {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const day = i + 1
            const info = getDayInfo(day)
            return (
              <div key={day} title={info.label} onClick={() => handleDayClick(day)} style={{
                textAlign: 'center', padding: '8px 2px', borderRadius: 8,
                background: info.bg, color: info.color, fontSize: 12, fontWeight: 800,
                cursor: 'pointer', border: info.border || 'none',
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
                  <StatusBadge status={getDisplayStatus(b)} />
                  <span style={{ fontWeight: 800, color: '#3dba3a' }}>{Number(b.total_price).toLocaleString('cs-CZ')} Kč</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {showAddBooking && (
        <AddBookingFromCalendar
          motoId={motoId}
          defaultDate={selectedDay}
          onClose={() => { setShowAddBooking(false); setSelectedDay(null) }}
          onSaved={() => { setShowAddBooking(false); setSelectedDay(null); loadData() }}
        />
      )}

      {showAddService && (
        <AddServiceFromCalendar
          motoId={motoId}
          onClose={() => setShowAddService(false)}
          onSaved={() => { setShowAddService(false); loadData() }}
        />
      )}
    </>
  )
}

function AddBookingFromCalendar({ motoId, defaultDate, onClose, onSaved }) {
  const [customers, setCustomers] = useState([])
  const [form, setForm] = useState({
    user_id: '', start_date: defaultDate || '', end_date: '', total_price: '', status: 'pending',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('profiles').select('id, full_name, email').order('full_name')
      .then(({ data }) => setCustomers(data || []))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('bookings').insert({
        ...form, moto_id: motoId, total_price: Number(form.total_price) || 0,
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'booking_created', details: { moto_id: motoId } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová rezervace (z kalendáře)" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Zákazník</label>
          <select value={form.user_id} onChange={e => set('user_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">— Vyberte zákazníka —</option>
            {customers.map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.email})</option>)}
          </select>
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Od</label>
          <input type="date" value={form.start_date} onChange={e => set('start_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Do</label>
          <input type="date" value={form.end_date} onChange={e => set('end_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Celková částka (Kč)</label>
          <input type="number" value={form.total_price} onChange={e => set('total_price', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.user_id || !form.start_date}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function AddServiceFromCalendar({ motoId, onClose, onSaved }) {
  const [form, setForm] = useState({
    type: 'regular', description: '', cost: '', scheduled_date: '',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('service_orders').insert({
        moto_id: motoId,
        type: form.type,
        description: form.description,
        estimated_cost: Number(form.cost) || 0,
        scheduled_date: form.scheduled_date || null,
        status: 'pending',
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'service_order_created', details: { moto_id: motoId } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová servisní událost" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Typ</label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="regular">Pravidelný servis</option>
            <option value="repair">Oprava</option>
            <option value="inspection">STK / Kontrola</option>
            <option value="tires">Pneumatiky</option>
            <option value="oil">Výměna oleje</option>
          </select>
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Datum</label>
          <input type="date" value={form.scheduled_date} onChange={e => set('scheduled_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div className="col-span-2">
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Popis</label>
          <textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} />
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Odhadované náklady (Kč)</label>
          <input type="number" value={form.cost} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.description}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
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
