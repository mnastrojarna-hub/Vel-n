import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import StatusBadge, { getDisplayStatus } from '../../components/ui/StatusBadge'
import Card from '../../components/ui/Card'

function localIso(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS_FULL = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

export default function GlobalCalendar() {
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [motos, setMotos] = useState([])
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)
  const [selectedDay, setSelectedDay] = useState(null)
  const [showFree, setShowFree] = useState(false)

  useEffect(() => { loadData() }, [month])

  async function loadData() {
    setLoading(true)
    const start = new Date(month.getFullYear(), month.getMonth(), 1)
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 0)
    const startStr = localIso(start)
    const endStr = localIso(end)

    const [bRes, mRes] = await Promise.all([
      supabase.from('bookings')
        .select('id, start_date, end_date, status, moto_id, profiles(full_name), motorcycles(model, spz), total_price')
        .in('status', ['pending', 'active', 'reserved', 'completed'])
        .gte('end_date', startStr).lte('start_date', endStr),
      supabase.from('motorcycles').select('id, model, spz, branch_id, branches(name)').eq('status', 'active'),
    ])
    setBookings(bRes.data || [])
    setMotos(mRes.data || [])
    setLoading(false)
  }

  const year = month.getFullYear()
  const mon = month.getMonth()
  const daysInMonth = new Date(year, mon + 1, 0).getDate()
  const firstDayOfWeek = (new Date(year, mon, 1).getDay() + 6) % 7
  const todayStr = localIso(new Date())
  const totalMotos = motos.length || 1

  function getDayBookings(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    return bookings.filter(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0])
  }

  function getDayInfo(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    const dayBookings = getDayBookings(day)
    const occupiedCount = new Set(dayBookings.map(b => b.moto_id)).size
    const isToday = dateStr === todayStr
    const ratio = occupiedCount / totalMotos
    if (occupiedCount === 0) return { bg: isToday ? '#bbf7d0' : '#dcfce7', color: '#15803d', label: 'Vše volné', count: 0 }
    if (ratio >= 1) return { bg: '#166534', color: '#fff', label: `Plně obsazeno (${occupiedCount}/${totalMotos})`, count: occupiedCount }
    if (ratio >= 0.5) return { bg: '#15803d', color: '#fff', label: `${occupiedCount}/${totalMotos} obsazeno`, count: occupiedCount }
    return { bg: '#4ade80', color: '#0f1a14', label: `${occupiedCount}/${totalMotos} obsazeno`, count: occupiedCount }
  }

  const prevMonth = () => setMonth(new Date(year, mon - 1, 1))
  const nextMonth = () => setMonth(new Date(year, mon + 1, 1))

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  const dayDetail = selectedDay ? getDayBookings(selectedDay) : []

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
      <div className="lg:col-span-2">
        <Card>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
            <button onClick={prevMonth} style={navBtnStyle}>←</button>
            <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS_FULL[mon]} {year}</span>
            <button onClick={nextMonth} style={navBtnStyle}>→</button>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
            {DAYS.map(d => (
              <div key={d} style={{ textAlign: 'center', fontSize: 13, fontWeight: 800, color: '#1a2e22', padding: 4 }}>{d}</div>
            ))}
            {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
            {Array.from({ length: daysInMonth }).map((_, i) => {
              const day = i + 1
              const info = getDayInfo(day)
              return (
                <div key={day} title={info.label} onClick={() => setSelectedDay(day)}
                  style={{ textAlign: 'center', padding: '10px 2px', borderRadius: 8, background: info.bg, color: info.color, fontSize: 12, fontWeight: 800, cursor: 'pointer', outline: selectedDay === day ? '2px solid #0f1a14' : 'none' }}>
                  <div>{day}</div>
                  {info.count > 0 && <div style={{ fontSize: 9, marginTop: 2, opacity: 0.8 }}>{info.count}/{totalMotos}</div>}
                </div>
              )
            })}
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 14, fontSize: 13, fontWeight: 700 }}>
            <LegendItem bg="#dcfce7" color="#15803d" label="Vše volné" />
            <LegendItem bg="#4ade80" color="#0f1a14" label="Částečně" />
            <LegendItem bg="#15803d" color="#fff" label=">50% obsazeno" />
            <LegendItem bg="#166534" color="#fff" label="Plně obsazeno" />
          </div>
        </Card>
      </div>
      <div>
        <Card>
          {selectedDay ? (
            <>
              <h3 className="text-sm font-extrabold mb-3" style={{ color: '#0f1a14' }}>{selectedDay}. {MONTHS_FULL[mon]} {year}</h3>
              <label className="flex items-center gap-2 cursor-pointer mb-3 pb-3" style={{ borderBottom: '1px solid #d4e8e0' }}>
                <input type="checkbox" checked={showFree} onChange={e => setShowFree(e.target.checked)} className="accent-[#1a8a18]" />
                <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: showFree ? '#1a8a18' : '#1a2e22' }}>Zobrazit volné motorky</span>
              </label>
              {dayDetail.length === 0 && !showFree ? (
                <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné rezervace v tento den</p>
              ) : (
                <div className="space-y-2">
                  {dayDetail.map(b => (
                    <div key={b.id} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="font-bold text-sm">{b.motorcycles?.model || '—'}</span>
                        <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{b.motorcycles?.spz}</span>
                        <StatusBadge status={getDisplayStatus(b)} />
                      </div>
                      <div className="text-sm" style={{ color: '#1a2e22' }}>
                        {b.profiles?.full_name || 'Zákazník'}
                        <span className="ml-2" style={{ color: '#1a2e22' }}>{b.start_date ? new Date(b.start_date).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' }) : ''} → {b.end_date ? new Date(b.end_date).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' }) : ''}</span>
                      </div>
                      {b.total_price && <div className="text-sm font-bold mt-1" style={{ color: '#3dba3a' }}>{Number(b.total_price).toLocaleString('cs-CZ')} Kč</div>}
                    </div>
                  ))}
                  {showFree && (() => {
                    const occupiedMotoIds = new Set(dayDetail.map(b => b.moto_id))
                    const freeMotos = motos.filter(m => !occupiedMotoIds.has(m.id))
                    if (freeMotos.length === 0) return <p style={{ color: '#1a2e22', fontSize: 12, marginTop: 8 }}>Žádné volné motorky</p>
                    return (
                      <>
                        <div className="text-sm font-extrabold uppercase tracking-wide mt-3 mb-1" style={{ color: '#1a8a18' }}>Volné motorky ({freeMotos.length})</div>
                        {freeMotos.map(m => (
                          <div key={m.id} onClick={() => navigate(`/flotila/${m.id}`)}
                            className="p-3 rounded-lg cursor-pointer hover:ring-2 hover:ring-[#74FB71] transition-all"
                            style={{ background: '#f0fdf4', border: '1px solid #bbf7d0' }}>
                            <div className="flex items-center gap-2">
                              <span className="font-bold text-sm">{m.model}</span>
                              <span className="text-sm font-mono" style={{ color: '#1a2e22' }}>{m.spz}</span>
                            </div>
                            <div className="flex items-center gap-2 mt-1">
                              <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase" style={{ padding: '2px 6px', background: '#dcfce7', color: '#15803d' }}>Volná</span>
                              {m.branches?.name && <span className="text-sm" style={{ color: '#1a2e22' }}>{m.branches.name}</span>}
                              <span className="text-sm ml-auto" style={{ color: '#3dba3a' }}>Detail flotily →</span>
                            </div>
                          </div>
                        ))}
                      </>
                    )
                  })()}
                </div>
              )}
            </>
          ) : (
            <p style={{ color: '#1a2e22', fontSize: 13 }}>Klikněte na den pro zobrazení detailu</p>
          )}
        </Card>
      </div>
    </div>
  )
}

function LegendItem({ bg, color, label }) {
  return <span className="flex items-center gap-1"><span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3, background: bg }} /><span style={{ color: '#1a2e22' }}>{label}</span></span>
}
