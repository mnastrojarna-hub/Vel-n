import { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import StatusBadge, { getDisplayStatus } from '../../components/ui/StatusBadge'
import Card from '../../components/ui/Card'

// Odjezdy (vyzvednutí) a návraty (vrácení) — události seřazené podle data a času,
// kdy se zákazník má dostavit na pobočku. Plus kalendář se zvýrazněnými přijezdy
// a odjezdy a odkazy na konkrétní rezervace.

function localIso(d) {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
const dateOnly = (s) => (s ? String(s).split('T')[0] : '')
const fmtTime = (t) => (t ? String(t).slice(0, 5) : null)
function eventDateTime(dateStr, time) {
  const d = dateOnly(dateStr)
  if (!d) return null
  const t = fmtTime(time) || '00:00'
  const dt = new Date(`${d}T${t}:00`)
  return isNaN(dt.getTime()) ? new Date(`${d}T00:00:00`) : dt
}
const fmtDay = (s) => {
  const d = dateOnly(s)
  if (!d) return '—'
  return new Date(`${d}T00:00:00`).toLocaleDateString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' })
}

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS_FULL = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

// odjezd = vyzvednutí (zákazník odjíždí na motorce), návrat = vrácení
const TYPE = {
  pickup: { label: 'Odjezd', emoji: '🛫', color: '#1a8a18', bg: '#dcfce7', dot: '#1a8a18' },
  return: { label: 'Návrat', emoji: '🛬', color: '#b45309', bg: '#fef3c7', dot: '#f59e0b' },
}

// Pracovní náročnost dne dle počtu událostí (odjezdy + návraty dohromady).
// Čím víc zákazníků se musí v jeden den odbavit, tím náročnější (tmavší) den.
function workloadInfo(count, isToday) {
  if (count === 0) return { bg: isToday ? '#dcfce7' : '#f1faf7', color: '#0f1a14', label: 'Volno' }
  if (count <= 2) return { bg: '#dcfce7', color: '#15803d', label: 'Klidný den' }
  if (count <= 4) return { bg: '#fde68a', color: '#92400e', label: 'Středně náročný' }
  if (count <= 6) return { bg: '#fb923c', color: '#fff', label: 'Náročný den' }
  return { bg: '#dc2626', color: '#fff', label: 'Velmi náročný' }
}

function buildEvents(bookings) {
  const out = []
  for (const b of bookings) {
    const branch = b.motorcycles?.branches?.name || null
    const base = {
      booking: b,
      customer: b.profiles?.full_name || 'Zákazník',
      phone: b.profiles?.phone || null,
      moto: b.motorcycles?.model || '—',
      spz: b.motorcycles?.spz || null,
      branch,
    }
    if (b.start_date) {
      out.push({
        ...base, type: 'pickup', day: dateOnly(b.start_date), time: fmtTime(b.pickup_time),
        when: eventDateTime(b.start_date, b.pickup_time), done: !!b.picked_up_at,
        delivery: b.pickup_method === 'delivery', address: b.pickup_address,
      })
    }
    if (b.end_date) {
      out.push({
        ...base, type: 'return', day: dateOnly(b.end_date), time: fmtTime(b.return_time),
        when: eventDateTime(b.end_date, b.return_time), done: !!b.returned_at,
        delivery: b.return_method === 'delivery', address: b.return_address,
      })
    }
  }
  return out
}

const bookingNo = (id) => (id ? '#' + String(id).slice(-8).toUpperCase() : '—')

function EventRow({ ev, onClick, compact }) {
  const t = TYPE[ev.type]
  return (
    <div onClick={onClick}
      className="rounded-lg cursor-pointer hover:ring-2 hover:ring-[#74FB71] transition-all"
      style={{ background: ev.done ? '#f3f4f6' : '#f1faf7', padding: compact ? '8px 10px' : '10px 12px', opacity: ev.done ? 0.65 : 1, borderLeft: `4px solid ${t.dot}` }}>
      {/* Typ + motorka + číslo rezervace */}
      <div className="flex items-center gap-2 flex-wrap">
        <span className="inline-flex items-center gap-1 rounded-btn text-[10px] font-extrabold uppercase tracking-wide shrink-0"
          style={{ padding: '2px 7px', background: t.bg, color: t.color }}>{t.emoji} {ev.type === 'pickup' ? 'Vyzvednutí' : 'Vrácení'}</span>
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{ev.moto}{ev.spz ? ` (${ev.spz})` : ''}</span>
        <span className="font-mono text-sm font-bold ml-auto" style={{ color: '#64748b' }}>{bookingNo(ev.booking.id)}</span>
      </div>
      {/* Jméno + datum + čas */}
      <div className="flex items-center gap-2 mt-1 flex-wrap text-sm" style={{ color: '#1a2e22' }}>
        <span className="font-bold">{ev.customer}</span>
        <span style={{ color: '#64748b' }}>·</span>
        <span className="font-extrabold" style={{ color: '#0f1a14' }}>{ev.day ? fmtDay(ev.day) : '—'}</span>
        {ev.time && <span className="font-mono font-bold" style={{ color: t.color }}>{ev.time}</span>}
        {ev.done && <span className="font-bold" style={{ color: '#15803d' }}>✓ hotovo</span>}
        {!compact && <span className="ml-auto"><StatusBadge status={getDisplayStatus(ev.booking)} /></span>}
      </div>
      {/* Pobočka / přistavení */}
      <div className="flex items-center gap-2 mt-0.5 text-sm" style={{ color: '#64748b' }}>
        <span>{ev.delivery ? '🚚 ' + (ev.address || 'Přistavení/svoz na adresu') : '🏍️ ' + (ev.branch || 'Na pobočce')}</span>
      </div>
    </div>
  )
}

function EventList({ events, onOpen, limit, compact }) {
  const shown = limit ? events.slice(0, limit) : events
  if (shown.length === 0) return <p className="text-sm" style={{ color: '#64748b' }}>Žádné nadcházející odjezdy ani návraty</p>
  return (
    <div className="space-y-2">
      {shown.map((ev, i) => <EventRow key={ev.booking.id + '_' + ev.type + '_' + i} ev={ev} compact={compact} onClick={() => onOpen(ev.booking.id)} />)}
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

  useEffect(() => { loadData() }, [])
  useEffect(() => {
    if (compact) return
    supabase.from('branches').select('id, name').order('name').then(({ data }) => setBranches(data || []))
  }, [compact])

  async function loadData() {
    setLoading(true)
    const { data } = await supabase.from('bookings')
      .select('id, start_date, end_date, pickup_time, return_time, status, payment_status, picked_up_at, returned_at, pickup_method, return_method, pickup_address, return_address, user_id, moto_id, total_price, ended_by_sos, profiles(full_name, phone), motorcycles!moto_id(model, spz, branch_id, branches(name))')
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
  const upcoming = useMemo(() => {
    return events
      .filter(e => !e.done && e.day && e.day >= todayIso)
      .sort((a, b) => (a.when?.getTime() || 0) - (b.when?.getTime() || 0))
  }, [events, todayIso])
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
          <EventList events={upcoming} onOpen={openBooking} limit={8} compact />
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
  const dayEvents = (iso) => events.filter(e => e.day === iso).sort((a, b) => (a.when?.getTime() || 0) - (b.when?.getTime() || 0))
  const selected = selectedDay ? dayEvents(selectedDay) : []

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-5">
      {branches.length > 1 && (
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Pobočka:</span>
          <select value={branchFilter} onChange={e => setBranchFilter(e.target.value)}
            className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '7px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="">Všechny pobočky</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </div>
      )}

      {/* Nadcházející události nahoře — odjezdy i návraty společně, nejbližší první */}
      <Card>
        <div className="flex items-center gap-2 mb-3">
          <span className="text-base">🛫🛬</span>
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#0f1a14' }}>Nejbližší odjezdy a návraty</h3>
          <span className="inline-block rounded-full text-sm font-extrabold ml-auto" style={{ background: '#dcfce7', color: '#15803d', padding: '1px 9px' }}>{upcoming.length}</span>
        </div>
        <EventList events={upcoming} onOpen={openBooking} limit={20} />
      </Card>

      {/* Kalendář s vyznačenými přijezdy a odjezdy */}
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
                const wl = workloadInfo(evs.length, isToday)
                return (
                  <div key={day} onClick={() => setSelectedDay(iso)} title={`${wl.label}${evs.length ? ` — ${evs.length} událostí` : ''}`}
                    style={{ minHeight: 58, padding: '6px 4px', borderRadius: 8, cursor: 'pointer',
                      background: wl.bg, color: wl.color,
                      outline: isSel ? '2px solid #0f1a14' : (isToday ? '2px solid #15803d' : 'none') }}>
                    <div style={{ fontSize: 12, fontWeight: 800 }}>{day}</div>
                    <div style={{ display: 'flex', gap: 3, marginTop: 4, flexWrap: 'wrap' }}>
                      {pickups > 0 && <span style={{ fontSize: 9, fontWeight: 800, background: 'rgba(255,255,255,.65)', color: TYPE.pickup.color, borderRadius: 5, padding: '1px 5px' }}>🛫 {pickups}</span>}
                      {returns > 0 && <span style={{ fontSize: 9, fontWeight: 800, background: 'rgba(255,255,255,.65)', color: TYPE.return.color, borderRadius: 5, padding: '1px 5px' }}>🛬 {returns}</span>}
                    </div>
                  </div>
                )
              })}
            </div>
            <div style={{ marginTop: 14, fontSize: 13, fontWeight: 700 }}>
              <div className="mb-2" style={{ color: '#1a2e22' }}>Pracovní náročnost dne (odjezdy + návraty):</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 14 }}>
                <LegendItem bg="#dcfce7" label="Klidný (1–2)" />
                <LegendItem bg="#fde68a" label="Středně (3–4)" />
                <LegendItem bg="#fb923c" label="Náročný (5–6)" />
                <LegendItem bg="#dc2626" label="Velmi náročný (7+)" />
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 14, marginTop: 8 }}>
                <span className="flex items-center gap-1"><span style={{ fontSize: 12 }}>🛫</span><span style={{ color: '#1a2e22' }}>Odjezd (vyzvednutí)</span></span>
                <span className="flex items-center gap-1"><span style={{ fontSize: 12 }}>🛬</span><span style={{ color: '#1a2e22' }}>Návrat (vrácení)</span></span>
              </div>
            </div>
          </Card>
        </div>
        <div>
          <Card>
            <h3 className="text-sm font-extrabold mb-3" style={{ color: '#0f1a14' }}>
              {selectedDay ? fmtDay(selectedDay) : 'Vyberte den'}
            </h3>
            {selected.length === 0 ? (
              <p className="text-sm" style={{ color: '#64748b' }}>Žádné odjezdy ani návraty v tento den</p>
            ) : (
              <div className="space-y-2">
                {selected.map((ev, i) => <EventRow key={ev.booking.id + '_' + i} ev={ev} onClick={() => openBooking(ev.booking.id)} />)}
              </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  )
}

function LegendItem({ bg, label }) {
  return <span className="flex items-center gap-1"><span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3, background: bg }} /><span style={{ color: '#1a2e22' }}>{label}</span></span>
}
