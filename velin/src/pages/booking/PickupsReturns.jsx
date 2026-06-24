import { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import StatusBadge, { getDisplayStatus } from '../../components/ui/StatusBadge'
import Card from '../../components/ui/Card'

// Odjezdy (vyzvednutí) a návraty (vrácení) — události seřazené podle data a času,
// kdy se zákazník má dostavit na pobočku. Plus kalendář (heatmapa) zvýrazňující
// světlostí barvy pracovně náročné dny + odkazy na konkrétní rezervace.

function localIso(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
const dateOnly = (s) => (s ? String(s).split('T')[0] : '')
const fmtTime = (t) => (t ? String(t).slice(0, 5) : null)
// Default čas, když u rezervace chybí: vyzvednutí 9:00, vrácení 20:00.
const DEFAULT_TIME = { pickup: '09:00', return: '20:00' }
function eventDateTime(dateStr, time) {
  const d = dateOnly(dateStr)
  if (!d) return null
  const t = fmtTime(time) || '00:00'
  const dt = new Date(`${d}T${t}:00`)
  return isNaN(dt.getTime()) ? new Date(`${d}T00:00:00`) : dt
}
// Řazení událostí: dle data+času, při shodě je vyzvednutí (pickup) vždy před vrácením.
const typeRank = (e) => (e.type === 'pickup' ? 0 : 1)
function cmpEvents(a, b) {
  const diff = (a.when?.getTime() || 0) - (b.when?.getTime() || 0)
  return diff !== 0 ? diff : typeRank(a) - typeRank(b)
}
const fmtDay = (s) => {
  const d = dateOnly(s)
  if (!d) return '—'
  return new Date(`${d}T00:00:00`).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' })
}
const fmtDayShort = (s) => {
  const d = dateOnly(s)
  if (!d) return '—'
  return new Date(`${d}T00:00:00`).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric' })
}
const bookingNo = (id) => (id ? '#' + String(id).slice(-8).toUpperCase() : '—')

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS_FULL = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

// odjezd = vyzvednutí (zákazník odjíždí na motorce), návrat = vrácení
const TYPE = {
  pickup: { label: 'Odjezd', emoji: '🛫', color: '#1a8a18' },
  return: { label: 'Návrat', emoji: '🛬', color: '#b45309' },
}

// Heatmapa pracovní náročnosti dne dle počtu událostí (odjezdy + návraty).
// Bílá = žádný odjezd ani návrat; čím víc, tím tmavší/sytější zelená.
function heatColor(count, max) {
  if (!count) return { bg: '#ffffff', color: '#9ca3af', border: '#e5e7eb' }
  // poměr vůči nejrušnějšímu dni měsíce (min. škála 4, ať jsou rozdíly vidět)
  const ratio = Math.min(1, count / Math.max(4, max))
  // interpolace světle → tmavě zelená
  const stops = [
    [0.0001, '#e7f9ee', '#15803d'],
    [0.25, '#bbf7d0', '#15803d'],
    [0.5, '#74e88a', '#0f1a14'],
    [0.7, '#34c759', '#0f1a14'],
    [0.85, '#1a9e3a', '#ffffff'],
    [1.01, '#13803d', '#ffffff'],
  ]
  for (const [thr, bg, color] of stops) if (ratio <= thr) return { bg, color, border: bg }
  return { bg: '#13803d', color: '#fff', border: '#13803d' }
}

function buildEvents(bookings) {
  const out = []
  for (const b of bookings) {
    const branch = b.motorcycles?.branches?.name || null
    const base = {
      booking: b,
      customer: b.profiles?.full_name || 'Zákazník',
      moto: b.motorcycles?.model || '—',
      spz: b.motorcycles?.spz || null,
      branch,
    }
    if (b.start_date) {
      const time = fmtTime(b.pickup_time) || DEFAULT_TIME.pickup
      out.push({ ...base, type: 'pickup', day: dateOnly(b.start_date), time, timeDefault: !fmtTime(b.pickup_time),
        when: eventDateTime(b.start_date, time), done: !!b.picked_up_at,
        delivery: b.pickup_method === 'delivery', address: b.pickup_address })
    }
    if (b.end_date) {
      const time = fmtTime(b.return_time) || DEFAULT_TIME.return
      out.push({ ...base, type: 'return', day: dateOnly(b.end_date), time, timeDefault: !fmtTime(b.return_time),
        when: eventDateTime(b.end_date, time), done: !!b.returned_at,
        delivery: b.return_method === 'delivery', address: b.return_address })
    }
  }
  return out
}

const TimeCell = ({ ev, t }) => (
  <span className="font-extrabold" style={{ color: '#0f1a14' }}>
    {fmtDayShort(ev.day)} <span className="font-mono" style={{ color: t.color }} title={ev.timeDefault ? 'Výchozí čas (není zadán)' : undefined}>{ev.timeDefault ? '~' : ''}{ev.time}</span>
  </span>
)

// Jednořádková kompaktní položka události. `dense` = úzký dvouřádkový layout
// (pro boční panel detailu dne, kde by horizontální řádek přetékal).
function EventRow({ ev, onClick, showStatus, dense }) {
  const t = TYPE[ev.type]
  const wrap = {
    padding: dense ? '8px 10px' : '7px 10px', borderLeft: `4px solid ${t.color}`,
    background: ev.done ? '#f3f4f6' : '#f8fdfb', borderBottom: '1px solid #eef5f1', opacity: ev.done ? 0.6 : 1,
  }
  const place = ev.delivery ? '🚚 ' + (ev.address || 'na adresu') : '🏍️ ' + (ev.branch || 'pobočka')
  const typeTag = (
    <span className="inline-flex items-center gap-1 shrink-0">
      <span className="text-base" title={t.label}>{t.emoji}</span>
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: t.color }}>{t.label}</span>
    </span>
  )

  if (dense) {
    return (
      <div onClick={onClick} className="cursor-pointer hover:bg-[#e9f7f1] transition-colors" style={wrap}>
        <div className="flex items-center gap-2">
          {typeTag}
          <span className="ml-auto text-sm"><TimeCell ev={ev} t={t} /></span>
        </div>
        <div className="font-extrabold text-sm mt-1 truncate" style={{ color: '#0f1a14' }}>{ev.moto}{ev.spz ? ` · ${ev.spz}` : ''}</div>
        <div className="text-sm truncate" style={{ color: '#1a2e22' }}>{ev.customer} <span className="font-mono" style={{ color: '#64748b' }}>{bookingNo(ev.booking.id)}</span></div>
        <div className="text-sm truncate" style={{ color: '#64748b' }}>{place}</div>
      </div>
    )
  }

  return (
    <div onClick={onClick}
      className="flex items-center gap-2 cursor-pointer hover:bg-[#e9f7f1] transition-colors"
      style={wrap}>
      <span className="shrink-0 hidden sm:flex" style={{ width: 86 }}>{typeTag}</span>
      <span className="shrink-0 sm:hidden text-base" title={t.label}>{t.emoji}</span>
      <span className="font-extrabold text-sm truncate" style={{ color: '#0f1a14', minWidth: 0, flex: '1 1 130px' }}>{ev.moto}{ev.spz ? ` · ${ev.spz}` : ''}</span>
      <span className="text-sm truncate hidden md:block" style={{ color: '#1a2e22', flex: '1 1 100px', minWidth: 0 }}>{ev.customer}</span>
      <span className="text-sm font-mono shrink-0 hidden lg:inline" style={{ color: '#64748b' }}>{bookingNo(ev.booking.id)}</span>
      <span className="text-sm truncate hidden lg:block" style={{ color: '#64748b', flex: '1 1 90px', minWidth: 0 }}>{ev.delivery ? '🚚 ' + (ev.address || 'na adresu') : '🏍️ ' + (ev.branch || 'pobočka')}</span>
      <span className="shrink-0 text-sm text-right" style={{ minWidth: 96 }}><TimeCell ev={ev} t={t} /></span>
      {showStatus && <span className="shrink-0 hidden xl:inline"><StatusBadge status={getDisplayStatus(ev.booking)} /></span>}
      {ev.done && <span className="shrink-0 text-sm font-bold" style={{ color: '#15803d' }}>✓</span>}
    </div>
  )
}

function EventList({ events, onOpen, limit, showStatus }) {
  const shown = limit ? events.slice(0, limit) : events
  if (shown.length === 0) return <p className="text-sm" style={{ color: '#64748b', padding: '8px 4px' }}>Žádné nadcházející odjezdy ani návraty</p>
  return (
    <div className="rounded-lg overflow-hidden" style={{ border: '1px solid #eef5f1' }}>
      {shown.map((ev, i) => <EventRow key={ev.booking.id + '_' + ev.type + '_' + i} ev={ev} showStatus={showStatus} onClick={() => onOpen(ev.booking.id)} />)}
    </div>
  )
}

export default function PickupsReturns({ compact = false, onExpand }) {
  const navigate = useNavigate()
  const [bookings, setBookings] = useState([])
  const [branches, setBranches] = useState([])
  const [branchFilter, setBranchFilter] = useState('')
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)
  const [selectedDay, setSelectedDay] = useState(localIso(new Date()))
  const [subView, setSubView] = useState('list') // 'list' | 'calendar'
  const [splitList, setSplitList] = useState(false) // seznam: společně vs. dvě tabulky

  useEffect(() => { loadData() }, [])
  useEffect(() => {
    if (compact) return
    supabase.from('branches').select('id, name').order('name').then(({ data }) => setBranches(data || []))
  }, [compact])

  async function loadData() {
    setLoading(true)
    const { data } = await supabase.from('bookings')
      .select('id, start_date, end_date, pickup_time, return_time, status, payment_status, picked_up_at, returned_at, pickup_method, return_method, pickup_address, return_address, user_id, moto_id, ended_by_sos, profiles(full_name), motorcycles!moto_id(model, spz, branch_id, branches(name))')
      .in('status', ['reserved', 'active', 'pending'])
      .order('start_date', { ascending: true })
    setBookings(data || [])
    setLoading(false)
  }

  const filtered = useMemo(
    () => (branchFilter ? bookings.filter(b => b.motorcycles?.branch_id === branchFilter) : bookings),
    [bookings, branchFilter]
  )
  const events = useMemo(() => buildEvents(filtered), [filtered])

  const todayIso = localIso(new Date())
  const upcoming = useMemo(() => events
    .filter(e => !e.done && e.day && e.day >= todayIso)
    .sort(cmpEvents), [events, todayIso])
  const upcomingPickups = useMemo(() => upcoming.filter(e => e.type === 'pickup'), [upcoming])
  const upcomingReturns = useMemo(() => upcoming.filter(e => e.type === 'return'), [upcoming])

  const openBooking = (id) => navigate(`/rezervace/${id}`)

  // ── Compact (Dashboard widget) ──
  if (compact) {
    return (
      <Card style={{ padding: 16 }}>
        <div className="flex items-center gap-2 mb-3 cursor-pointer" onClick={onExpand}>
          <span className="text-base">🛫🛬</span>
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#0f1a14' }}>Odjezdy a návraty</h3>
          <span className="inline-block rounded-full text-sm font-extrabold" style={{ background: '#dcfce7', color: '#15803d', padding: '1px 9px' }}>{upcoming.length}</span>
          <span className="ml-auto text-sm font-bold" style={{ color: '#1a8a18' }}>Otevřít kalendář →</span>
        </div>
        {loading ? (
          <div className="py-6 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
        ) : (
          <EventList events={upcoming} onOpen={openBooking} limit={8} />
        )}
      </Card>
    )
  }

  // ── Full (Rezervace → Odjezdy a návraty) ──
  const year = month.getFullYear()
  const mon = month.getMonth()
  const daysInMonth = new Date(year, mon + 1, 0).getDate()
  const firstDayOfWeek = (new Date(year, mon, 1).getDay() + 6) % 7
  const dayStr = (day) => `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
  const dayEvents = (iso) => events.filter(e => e.day === iso).sort(cmpEvents)
  const selected = selectedDay ? dayEvents(selectedDay) : []
  const monthMax = useMemo(() => {
    let m = 0
    for (let d = 1; d <= daysInMonth; d++) m = Math.max(m, dayEvents(dayStr(d)).length)
    return m
  }, [events, month])

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  const toggleBtn = (key, label) => (
    <button onClick={() => setSubView(key)}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '7px 14px', border: '1px solid #d4e8e0',
        background: subView === key ? '#74FB71' : '#f1faf7', color: '#1a2e22',
        boxShadow: subView === key ? '0 4px 14px rgba(116,251,113,.35)' : 'none' }}>
      {label}
    </button>
  )

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        {toggleBtn('list', '☰ Seznam')}
        {toggleBtn('calendar', '🗓️ Kalendář')}
        {subView === 'list' && (
          <button onClick={() => setSplitList(s => !s)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '7px 14px', border: '1px solid #d4e8e0', background: splitList ? '#74FB71' : '#f1faf7', color: '#1a2e22' }}>
            {splitList ? '⇆ Společně' : '⇆ Rozdělit'}
          </button>
        )}
        <span className="inline-block rounded-full text-sm font-extrabold" style={{ background: '#dcfce7', color: '#15803d', padding: '2px 10px' }}>{upcoming.length} nadcházejících</span>
        {branches.length > 1 && (
          <select value={branchFilter} onChange={e => setBranchFilter(e.target.value)}
            className="rounded-btn text-sm font-bold cursor-pointer ml-auto"
            style={{ padding: '7px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="">Všechny pobočky</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        )}
      </div>

      {subView === 'list' ? (
        splitList ? (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card style={{ padding: 14 }}>
              <div className="flex items-center gap-2 mb-3">
                <span className="text-base">🛫</span>
                <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: TYPE.pickup.color }}>Odjezdy (vyzvednutí)</h3>
                <span className="inline-block rounded-full text-sm font-extrabold ml-auto" style={{ background: '#dcfce7', color: '#15803d', padding: '1px 9px' }}>{upcomingPickups.length}</span>
              </div>
              <EventList events={upcomingPickups} onOpen={openBooking} showStatus />
            </Card>
            <Card style={{ padding: 14 }}>
              <div className="flex items-center gap-2 mb-3">
                <span className="text-base">🛬</span>
                <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: TYPE.return.color }}>Návraty (vrácení)</h3>
                <span className="inline-block rounded-full text-sm font-extrabold ml-auto" style={{ background: '#fef3c7', color: '#b45309', padding: '1px 9px' }}>{upcomingReturns.length}</span>
              </div>
              <EventList events={upcomingReturns} onOpen={openBooking} showStatus />
            </Card>
          </div>
        ) : (
          <Card style={{ padding: 14 }}>
            <EventList events={upcoming} onOpen={openBooking} showStatus />
          </Card>
        )
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
          <div className="lg:col-span-2">
            <Card>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
                <button onClick={() => setMonth(new Date(year, mon - 1, 1))} style={navBtnStyle}>←</button>
                <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS_FULL[mon]} {year}</span>
                <button onClick={() => setMonth(new Date(year, mon + 1, 1))} style={navBtnStyle}>→</button>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
                {DAYS.map(d => <div key={d} style={{ textAlign: 'center', fontSize: 13, fontWeight: 800, color: '#1a2e22', padding: 4 }}>{d}</div>)}
                {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
                {Array.from({ length: daysInMonth }).map((_, i) => {
                  const day = i + 1
                  const iso = dayStr(day)
                  const evs = dayEvents(iso)
                  const pickups = evs.filter(e => e.type === 'pickup').length
                  const returns = evs.filter(e => e.type === 'return').length
                  const isToday = iso === todayIso
                  const isSel = iso === selectedDay
                  const h = heatColor(evs.length, monthMax)
                  return (
                    <div key={day} onClick={() => setSelectedDay(iso)}
                      title={evs.length ? `${evs.length} událostí (🛫 ${pickups} / 🛬 ${returns})` : 'Žádný odjezd ani návrat'}
                      style={{ minHeight: 60, padding: '5px 4px', borderRadius: 8, cursor: 'pointer',
                        background: h.bg, color: h.color, border: `1px solid ${h.border}`,
                        outline: isSel ? '2px solid #0f1a14' : (isToday ? '2px solid #15803d' : 'none') }}>
                      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                        <span style={{ fontSize: 12, fontWeight: 800 }}>{day}</span>
                        {evs.length > 0 && <span style={{ fontSize: 15, fontWeight: 900 }}>{evs.length}</span>}
                      </div>
                      {evs.length > 0 && (
                        <div style={{ fontSize: 9, fontWeight: 800, marginTop: 2, opacity: 0.85 }}>
                          🛫{pickups} 🛬{returns}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
              <div style={{ marginTop: 14, fontSize: 13, fontWeight: 700 }}>
                <div className="flex items-center gap-2 flex-wrap">
                  <span style={{ color: '#1a2e22' }}>Méně</span>
                  {['#ffffff', '#e7f9ee', '#bbf7d0', '#74e88a', '#34c759', '#1a9e3a', '#13803d'].map((c, i) => (
                    <span key={i} style={{ width: 18, height: 14, borderRadius: 3, background: c, border: '1px solid #e5e7eb', display: 'inline-block' }} />
                  ))}
                  <span style={{ color: '#1a2e22' }}>Více odjezdů/návratů</span>
                </div>
                <div className="mt-1 text-sm" style={{ color: '#64748b' }}>Bílá = žádný odjezd ani návrat. Číslo v buňce = celkový počet (🛫 odjezdy / 🛬 návraty).</div>
              </div>
            </Card>
          </div>
          <div>
            <Card>
              <h3 className="text-sm font-extrabold mb-3" style={{ color: '#0f1a14' }}>{selectedDay ? fmtDay(selectedDay) : 'Vyberte den'}</h3>
              {selected.length === 0 ? (
                <p className="text-sm" style={{ color: '#64748b' }}>Žádné odjezdy ani návraty v tento den</p>
              ) : (
                <div className="rounded-lg overflow-hidden" style={{ border: '1px solid #eef5f1' }}>
                  {selected.map((ev, i) => <EventRow key={ev.booking.id + '_' + ev.type + '_' + i} ev={ev} dense onClick={() => openBooking(ev.booking.id)} />)}
                </div>
              )}
            </Card>
          </div>
        </div>
      )}
    </div>
  )
}
