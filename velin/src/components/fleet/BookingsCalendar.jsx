import { useState, useEffect, useMemo } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../ui/Card'
import Button from '../ui/Button'
import Modal from '../ui/Modal'
import StatusBadge, { getDisplayStatus } from '../ui/StatusBadge'
import NewBookingFromCalendar from './NewBookingFromCalendar'
import AddServiceFromCalendar from './AddServiceFromCalendar'

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const DAY_KEYS = { 0: 'price_sun', 1: 'price_mon', 2: 'price_tue', 3: 'price_wed', 4: 'price_thu', 5: 'price_fri', 6: 'price_sat' }
const PRICES_DAY_MAP = { 0: 'price_sunday', 1: 'price_monday', 2: 'price_tuesday', 3: 'price_wednesday', 4: 'price_thursday', 5: 'price_friday', 6: 'price_saturday' }
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }
const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

function isoDate(d) {
  if (!d) return ''
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
function fmtDate(d) { return d ? d.toLocaleDateString('cs-CZ') : '—' }
function sameDay(a, b) { return a && b && isoDate(a) === isoDate(b) }

/* Kalendář rezervací pro jednu motorku */
export default function BookingsCalendar({ motoId, onSwitchTab }) {
  const [bookings, setBookings] = useState([])
  const [maintenance, setMaintenance] = useState([])
  const [serviceOrders, setServiceOrders] = useState([])
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)
  const [showAddBooking, setShowAddBooking] = useState(false)
  const [showAddService, setShowAddService] = useState(false)
  const [selectedDay, setSelectedDay] = useState(null)
  const [expandedLog, setExpandedLog] = useState(null)

  useEffect(() => { loadData() }, [motoId, month])

  async function loadData() {
    setLoading(true)
    const start = new Date(month.getFullYear(), month.getMonth(), 1)
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 0)
    const startStr = start.toISOString().split('T')[0]
    const endStr = end.toISOString().split('T')[0]

    const [bRes, mRes, soRes] = await Promise.all([
      supabase.from('bookings')
        .select('id, start_date, end_date, status, user_id, profiles(full_name), total_price')
        .eq('moto_id', motoId)
        .in('status', ['pending', 'active', 'reserved', 'completed'])
        .gte('end_date', startStr).lte('start_date', endStr),
      supabase.from('maintenance_log')
        .select('id, created_at, type, service_type, description, service_date, scheduled_date, completed_date, km_at_service, performed_by, cost, status, items')
        .eq('moto_id', motoId)
        .or(`service_date.gte.${startStr},created_at.gte.${startStr}`)
        .or(`service_date.lte.${endStr},created_at.lte.${endStr}T23:59:59`),
      supabase.from('service_orders')
        .select('id, created_at, type, status, notes')
        .eq('moto_id', motoId)
        .gte('created_at', startStr).lte('created_at', endStr + 'T23:59:59'),
    ])
    setBookings(bRes.data || [])
    setMaintenance(mRes.data || [])
    setServiceOrders(soRes.data || [])
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

    // Service / maintenance check (red) — show on service_date range
    const mLog = maintenance.find(m => {
      const sd = (m.service_date || m.created_at)?.slice(0, 10)
      const ed = m.scheduled_date?.slice(0, 10) || sd
      return sd && dateStr >= sd && dateStr <= ed
    })
    const serviceOrder = serviceOrders.find(s => s.created_at?.slice(0, 10) === dateStr)
    if (mLog || serviceOrder) {
      const sType = { regular: 'Pravidelný', extraordinary: 'Mimořádný', repair: 'Oprava' }
      const serviceLabel = (mLog && (sType[mLog.service_type] || mLog.service_type)) || serviceOrder?.type || 'Servis'
      return { type: 'service', bg: '#dc2626', color: '#fff', label: serviceLabel, log: mLog }
    }

    // Booking check
    const booking = bookings.find(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0])
    if (booking) {
      if (booking.status === 'pending' || booking.status === 'reserved')
        return { type: 'unconfirmed', bg: '#ffffff', color: '#1a2e22', border: '2px dashed #d4e8e0', label: `${booking.profiles?.full_name || '?'} · Nepotvrzeno`, booking }
      if (booking.status === 'completed' || isPast)
        return { type: 'history', bg: '#166534', color: '#fff', label: `${booking.profiles?.full_name || '?'} · Dokončeno`, booking }
      return { type: 'occupied', bg: '#15803d', color: '#fff', label: `${booking.profiles?.full_name || '?'} · ${booking.status}`, booking }
    }

    // Free day (light green)
    const isToday = dateStr === todayStr
    return { type: 'free', bg: isToday ? '#bbf7d0' : '#dcfce7', color: isToday ? '#166534' : '#15803d', label: 'Volno' }
  }

  function handleDayClick(day) {
    const info = getDayInfo(day)
    if (info.type === 'service') {
      if (info.log) {
        setExpandedLog(prev => prev?.id === info.log.id ? null : info.log)
      }
      return
    }
    if (info.type === 'free') {
      const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
      setSelectedDay(dateStr)
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
          {DAYS.map(d => <div key={d} style={{ textAlign: 'center', fontSize: 13, fontWeight: 800, color: '#1a2e22', padding: 4 }}>{d}</div>)}
          {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const day = i + 1
            const info = getDayInfo(day)
            const isService = info.type === 'service'
            return (
              <div key={day} title={info.label} onClick={() => handleDayClick(day)} style={{
                textAlign: 'center', padding: '8px 2px', borderRadius: 8,
                background: info.bg, color: info.color, fontSize: 12, fontWeight: 800,
                cursor: isService ? 'pointer' : info.type === 'free' ? 'pointer' : 'default',
                border: info.border || 'none',
                position: 'relative',
              }}>
                {day}
                {info.type === 'unconfirmed' && (
                  <div style={{ position: 'absolute', top: 2, right: 2, width: 5, height: 5, borderRadius: '50%', background: '#fbbf24' }} />
                )}
              </div>
            )
          })}
        </div>

        {/* Legenda */}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 14, fontSize: 13, fontWeight: 700 }}>
          <Legend bg="#dcfce7" label="Volno" />
          <Legend bg="#15803d" label="Obsazeno" white />
          <Legend bg="#166534" label="Historie" white />
          <Legend bg="#dc2626" label="Servis" white />
          <Legend bg="#fff" label="Nepotvrzeno" border dot />
        </div>

        {/* Seznam rezervací pod kalendářem */}
        {bookings.length > 0 && (
          <div style={{ marginTop: 16 }}>
            {bookings.map(b => (
              <div key={b.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 10px', background: '#f1faf7', borderRadius: 10, marginBottom: 4, fontSize: 12 }}>
                <div>
                  <span style={{ fontWeight: 700 }}>{b.profiles?.full_name || 'Zákazník'}</span>
                  <span style={{ color: '#1a2e22', marginLeft: 8 }}>{b.start_date.split('T')[0]} → {b.end_date.split('T')[0]}</span>
                </div>
                <div className="flex items-center gap-2">
                  <StatusBadge status={getDisplayStatus(b)} />
                  <span style={{ fontWeight: 800, color: '#3dba3a' }}>{Number(b.total_price).toLocaleString('cs-CZ')} Kč</span>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Servisní historie */}
        {maintenance.length > 0 && (
          <div style={{ marginTop: 16 }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Servisní historie</div>
            {maintenance.map(m => {
              const isOpen = expandedLog?.id === m.id
              const sType = { regular: 'Pravidelný', extraordinary: 'Mimořádný', repair: 'Oprava' }[m.service_type] || m.service_type || m.type || '—'
              const dateFrom = m.service_date ? new Date(m.service_date).toLocaleDateString('cs-CZ') : m.created_at ? new Date(m.created_at).toLocaleDateString('cs-CZ') : '—'
              const dateTo = m.scheduled_date ? new Date(m.scheduled_date).toLocaleDateString('cs-CZ') : ''
              const items = Array.isArray(m.items) ? m.items : []
              return (
                <div key={m.id} style={{ marginBottom: 4 }}>
                  <div
                    onClick={() => setExpandedLog(isOpen ? null : m)}
                    style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 10px', background: '#fef2f2', borderRadius: isOpen ? '10px 10px 0 0' : 10, cursor: 'pointer', fontSize: 12, border: '1px solid #fecaca' }}
                  >
                    <div className="flex items-center gap-2">
                      <span style={{ fontWeight: 800, color: '#dc2626', transform: isOpen ? 'rotate(90deg)' : 'rotate(0)', transition: 'transform .2s', display: 'inline-block' }}>▶</span>
                      <span style={{ fontWeight: 700, color: '#991b1b' }}>{sType}</span>
                      <span style={{ color: '#7f1d1d' }}>{dateFrom}{dateTo && dateTo !== dateFrom ? ` → ${dateTo}` : ''}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      {m.completed_date
                        ? <span style={{ background: '#dcfce7', color: '#16a34a', padding: '2px 8px', borderRadius: 6, fontWeight: 700 }}>Dokončeno</span>
                        : <span style={{ background: '#fef3c7', color: '#b45309', padding: '2px 8px', borderRadius: 6, fontWeight: 700 }}>{m.status === 'in_service' ? 'V servisu' : 'Naplánováno'}</span>
                      }
                    </div>
                  </div>
                  {isOpen && (
                    <div style={{ padding: '12px', background: '#fff', border: '1px solid #fecaca', borderTop: 'none', borderRadius: '0 0 10px 10px' }}>
                      <div className="grid grid-cols-2 gap-x-4 gap-y-2 mb-3" style={{ fontSize: 13 }}>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Typ:</span> {sType}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Stav:</span> {m.completed_date ? 'Dokončeno' : m.status === 'in_service' ? 'V servisu' : 'Naplánováno'}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Servis od:</span> {dateFrom}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Plánované dokončení:</span> {dateTo || '—'}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Dokončeno:</span> {m.completed_date ? new Date(m.completed_date).toLocaleDateString('cs-CZ') : '—'}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Km:</span> {m.km_at_service ? Number(m.km_at_service).toLocaleString('cs-CZ') : '—'}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Technik:</span> {m.performed_by || '—'}</div>
                        <div><span style={{ fontWeight: 700, color: '#1a2e22' }}>Cena:</span> {m.cost ? `${Number(m.cost).toLocaleString('cs-CZ')} Kč` : '—'}</div>
                      </div>
                      {m.description && (
                        <div style={{ marginBottom: 8 }}>
                          <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Popis</div>
                          <div style={{ fontSize: 13, color: '#374151', whiteSpace: 'pre-wrap', background: '#f9fafb', padding: 8, borderRadius: 6 }}>{m.description}</div>
                        </div>
                      )}
                      {items.length > 0 && (
                        <div>
                          <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servisní úkony</div>
                          <div className="space-y-1">
                            {items.map((item, idx) => (
                              <div key={idx} className="flex items-center gap-2 p-2 rounded" style={{ background: item.done ? '#dcfce7' : '#f9fafb', border: '1px solid ' + (item.done ? '#86efac' : '#e5e7eb'), fontSize: 13 }}>
                                <span style={{ color: item.done ? '#16a34a' : '#9ca3af', fontWeight: 700 }}>{item.done ? '✓' : '○'}</span>
                                <span style={{ color: item.done ? '#16a34a' : '#374151', textDecoration: item.done ? 'line-through' : 'none' }}>{item.label}</span>
                                {item.note && <span style={{ color: '#6b7280', marginLeft: 8, fontStyle: 'italic' }}>— {item.note}</span>}
                              </div>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </Card>

      {showAddBooking && (
        <NewBookingFromCalendar
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
function Legend({ bg, label, white, border, dot }) {
  return (
    <span className="flex items-center gap-1">
      <span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3, background: bg, border: border ? '2px dashed #d4e8e0' : 'none', position: 'relative' }}>
        {dot && <span style={{ position: 'absolute', top: -1, right: -1, width: 4, height: 4, borderRadius: '50%', background: '#fbbf24' }} />}
      </span>
      <span style={{ color: '#1a2e22' }}>{label}</span>
    </span>
  )
}
