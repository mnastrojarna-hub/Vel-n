import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'

const TABS = ['Info', 'Rezervace', 'Servis', 'Výkon']

export default function FleetDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [moto, setMoto] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Info')
  const [confirm, setConfirm] = useState(null)

  useEffect(() => { loadMoto() }, [id])

  async function loadMoto() {
    setLoading(true)
    try {
      const { data, error: err } = await supabase
        .from('motorcycles')
        .select('*, branches(name)')
        .eq('id', id)
        .single()
      if (err) setError(err.message)
      else setMoto(data)
    } catch (e) {
      setError(e.message)
    }
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true)
    setError(null)
    const { model, spz, vin, category, branch_id, price_per_day, km, status, year, engine_cc, color } = moto
    const { error: err } = await supabase
      .from('motorcycles')
      .update({ model, spz, vin, category, branch_id, price_per_day, km, status, year, engine_cc, color })
      .eq('id', id)
    if (err) setError(err.message)
    await logAudit('motorcycle_updated', { moto_id: id })
    setSaving(false)
  }

  async function handleDeactivate() {
    const { data: activeBookings } = await supabase
      .from('bookings')
      .select('id, user_id, start_date, end_date, status, profiles(full_name, email)')
      .eq('moto_id', id)
      .in('status', ['pending', 'active', 'confirmed'])

    if (activeBookings && activeBookings.length > 0) {
      setConfirm({
        type: 'deactivate_with_bookings',
        title: `Motorka má ${activeBookings.length} aktivních rezervací`,
        message: 'Při deaktivaci budou zákazníci upozorněni. Pokračovat?',
        action: async () => {
          const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
          await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
          if (newStatus !== 'active') {
            for (const b of activeBookings) {
              await supabase.from('bookings')
                .update({ status: 'cancelled', notes: 'Motorka vyřazena z provozu' })
                .eq('id', b.id)
            }
          }
          await logAudit('motorcycle_status_changed', {
            moto_id: id, status: newStatus, affected_bookings: activeBookings.length,
          })
          setMoto(m => ({ ...m, status: newStatus }))
          setConfirm(null)
        },
      })
      return
    }

    const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
    await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
    await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus })
    setMoto(m => ({ ...m, status: newStatus }))
    setConfirm(null)
  }

  async function handleDelete() {
    await supabase.from('motorcycles').delete().eq('id', id)
    await logAudit('motorcycle_deleted', { moto_id: id })
    navigate('/flotila')
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  const set = (k, v) => setMoto(m => ({ ...m, [k]: v }))

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error && !moto) return <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>
  if (!moto) return <div className="p-4" style={{ color: '#8aab99' }}>Motorka nenalezena</div>

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/flotila')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#8aab99' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>{moto.model}</h2>
        <StatusBadge status={moto.status} />
        <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{moto.spz}</span>
      </div>

      <div className="flex gap-2 mb-5">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Info' && <InfoTab moto={moto} set={set} error={error} saving={saving} onSave={handleSave} onDeactivate={handleDeactivate} onDelete={() => setConfirm({ type: 'delete' })} logAudit={logAudit} />}
      {tab === 'Rezervace' && <BookingsTab motoId={id} />}
      {tab === 'Servis' && <ServiceTab motoId={id} motoKm={moto.km} logAudit={logAudit} />}
      {tab === 'Výkon' && <PerformanceTab motoId={id} />}

      <ConfirmDialog
        open={confirm?.type === 'deactivate_with_bookings'}
        title={confirm?.title || ''}
        message={confirm?.message || ''}
        onConfirm={() => confirm?.action?.()}
        onCancel={() => setConfirm(null)}
        danger
      />
      <ConfirmDialog
        open={confirm?.type === 'delete'}
        title="Smazat motorku?"
        message="Tato akce je nevratná. Motorka bude trvale odstraněna."
        danger
        onConfirm={handleDelete}
        onCancel={() => setConfirm(null)}
      />
    </div>
  )
}

/* ═══ INFO TAB — s servisními intervaly a průměrným nájezdem ═══ */
function InfoTab({ moto, set, error, saving, onSave, onDeactivate, onDelete, logAudit }) {
  const [schedules, setSchedules] = useState([])
  const [avgKm, setAvgKm] = useState(null)
  const [loadingSched, setLoadingSched] = useState(true)

  useEffect(() => {
    loadSchedules()
    loadAvgMileage()
  }, [moto.id])

  async function loadSchedules() {
    setLoadingSched(true)
    const { data } = await supabase
      .from('maintenance_schedules')
      .select('*')
      .eq('moto_id', moto.id)
      .eq('active', true)
    setSchedules(data || [])
    setLoadingSched(false)
  }

  async function loadAvgMileage() {
    // Spočítej průměrný nájezd z maintenance_log
    const { data } = await supabase
      .from('maintenance_log')
      .select('km_at_service, created_at')
      .eq('moto_id', moto.id)
      .order('created_at', { ascending: true })
    if (data && data.length >= 2) {
      const first = data[0]
      const last = data[data.length - 1]
      const kmDiff = (last.km_at_service || 0) - (first.km_at_service || 0)
      const daysDiff = (new Date(last.created_at) - new Date(first.created_at)) / 86400000
      if (daysDiff > 0) {
        setAvgKm(Math.round((kmDiff / daysDiff) * 30))
        return
      }
    }
    // Fallback — km motorky / stáří v měsících (rok výroby)
    if (moto.year && moto.km) {
      const monthsOld = Math.max(1, (new Date().getFullYear() - moto.year) * 12)
      setAvgKm(Math.round(moto.km / monthsOld))
    }
  }

  function estimateNextService(schedule) {
    const currentKm = Number(moto.km) || 0
    const intervalKm = schedule.interval_km || 0
    if (!intervalKm) return null
    const lastServiceKm = schedule.last_service_km || 0
    const remaining = (lastServiceKm + intervalKm) - currentKm
    if (remaining <= 0) return { overdue: true, km: Math.abs(remaining) }
    if (avgKm && avgKm > 0) {
      const daysUntil = Math.round((remaining / avgKm) * 30)
      return { overdue: false, km: remaining, days: daysUntil }
    }
    return { overdue: false, km: remaining }
  }

  return (
    <div className="space-y-5">
      <Card>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Model" value={moto.model} onChange={v => set('model', v)} />
          <Field label="SPZ" value={moto.spz} onChange={v => set('spz', v)} />
          <Field label="VIN" value={moto.vin} onChange={v => set('vin', v)} />
          <Field label="Kategorie" value={moto.category} onChange={v => set('category', v)} />
          <Field label="Rok výroby" value={moto.year} onChange={v => set('year', v)} type="number" />
          <Field label="Objem (cc)" value={moto.engine_cc} onChange={v => set('engine_cc', v)} type="number" />
          <Field label="Barva" value={moto.color} onChange={v => set('color', v)} />
          <Field label="Cena/den (Kč)" value={moto.price_per_day} onChange={v => set('price_per_day', v)} type="number" />
          <Field label="Km" value={moto.km} onChange={v => set('km', v)} type="number" />
          <Field label="Pobočka" value={moto.branches?.name || '—'} disabled />
        </div>
        <PhotoGallery motoId={moto.id} />
        {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
        <div className="flex gap-3 mt-6">
          <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
          <Button outline onClick={onDeactivate}>{moto.status === 'out_of_service' ? 'Aktivovat' : 'Deaktivovat'}</Button>
          <Button onClick={onDelete} style={{ color: '#dc2626' }}>Smazat</Button>
        </div>
      </Card>

      {/* Průměrný nájezd */}
      <Card>
        <SectionTitle>Průměrný nájezd</SectionTitle>
        <div className="flex items-center gap-6">
          <div className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Měsíční průměr</div>
            <div className="text-lg font-extrabold" style={{ color: '#0f1a14' }}>{avgKm != null ? `${avgKm.toLocaleString('cs-CZ')} km` : '—'}</div>
          </div>
          <div className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Celkový nájezd</div>
            <div className="text-lg font-extrabold" style={{ color: '#0f1a14' }}>{moto.km ? `${Number(moto.km).toLocaleString('cs-CZ')} km` : '—'}</div>
          </div>
        </div>
      </Card>

      {/* Servisní intervaly a odhad dalšího servisu */}
      <Card>
        <SectionTitle>Servisní intervaly</SectionTitle>
        {loadingSched ? (
          <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>
        ) : schedules.length === 0 ? (
          <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné servisní plány</p>
        ) : (
          <div className="space-y-3">
            {schedules.map(s => {
              const est = estimateNextService(s)
              return (
                <div key={s.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: est?.overdue ? '#fee2e2' : '#f1faf7' }}>
                  <div className="flex-1">
                    <span className="font-bold text-sm">{s.description}</span>
                    <span className="text-xs ml-3" style={{ color: '#8aab99' }}>
                      každých {s.interval_km?.toLocaleString('cs-CZ')} km
                      {s.interval_days ? ` / ${s.interval_days} dní` : ''}
                    </span>
                  </div>
                  {est && (
                    <div className="text-right">
                      {est.overdue ? (
                        <Badge label={`PO TERMÍNU ${est.km.toLocaleString('cs-CZ')} km`} color="#dc2626" bg="#fee2e2" />
                      ) : (
                        <span className="text-xs font-bold" style={{ color: '#1a8a18' }}>
                          za {est.km.toLocaleString('cs-CZ')} km
                          {est.days != null ? ` (~${est.days} dní)` : ''}
                        </span>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </Card>
    </div>
  )
}

/* ═══ CALENDAR ═══ */
const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

function BookingsTab({ motoId }) {
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
      supabase
        .from('bookings')
        .select('id, start_date, end_date, status, user_id, profiles(full_name), total_price')
        .eq('moto_id', motoId)
        .in('status', ['pending', 'active', 'confirmed', 'completed', 'reserved'])
        .gte('end_date', startStr)
        .lte('start_date', endStr),
      supabase
        .from('maintenance_log')
        .select('id, created_at, type, description')
        .eq('moto_id', motoId)
        .gte('created_at', startStr)
        .lte('created_at', endStr + 'T23:59:59'),
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

    // Servis v daný den
    const hasService = maintenance.some(m => m.created_at?.slice(0, 10) === dateStr)
    if (hasService) return { type: 'service', bg: '#dc2626', color: '#fff', label: 'Servis' }

    const booking = bookings.find(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0])
    if (booking) {
      // Nepotvrzená / nezaplacená (pending, reserved)
      if (booking.status === 'pending' || booking.status === 'reserved') {
        return { type: 'unconfirmed', bg: '#ffffff', color: '#0f1a14', border: '2px solid #d4e8e0', label: `${booking.profiles?.full_name || 'Zákazník'} · Nepotvrzeno`, booking }
      }
      // Historická (completed)
      if (booking.status === 'completed' || isPast) {
        return { type: 'history', bg: '#166534', color: '#fff', label: `${booking.profiles?.full_name || 'Zákazník'} · Dokončeno`, booking }
      }
      // Aktivní / potvrzená (obsazeno)
      return { type: 'occupied', bg: '#15803d', color: '#fff', label: `${booking.profiles?.full_name || 'Zákazník'} · ${booking.status}`, booking }
    }

    // Volno
    const isToday = dateStr === todayStr
    return { type: 'free', bg: isToday ? '#bbf7d0' : '#dcfce7', color: isToday ? '#166534' : '#15803d', label: 'Volno' }
  }

  const prevMonth = () => setMonth(new Date(year, mon - 1, 1))
  const nextMonth = () => setMonth(new Date(year, mon + 1, 1))

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <Card>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <button onClick={prevMonth} style={navBtnStyle}>←</button>
        <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS[mon]} {year}</span>
        <button onClick={nextMonth} style={navBtnStyle}>→</button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 3 }}>
        {DAYS.map(d => (
          <div key={d} style={{ textAlign: 'center', fontSize: 10, fontWeight: 800, color: '#8aab99', padding: 4 }}>{d}</div>
        ))}
        {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
        {Array.from({ length: daysInMonth }).map((_, i) => {
          const day = i + 1
          const info = getDayInfo(day)
          return (
            <div key={day} title={info.label}
              style={{
                textAlign: 'center', padding: '8px 2px', borderRadius: 8,
                background: info.bg, color: info.color,
                fontSize: 12, fontWeight: 800,
                cursor: info.booking ? 'pointer' : 'default',
                border: info.border || 'none',
              }}>
              {day}
            </div>
          )
        })}
      </div>

      {/* Legenda */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginTop: 14, fontSize: 10, fontWeight: 700 }}>
        <LegendItem bg="#dcfce7" color="#15803d" label="Volno" />
        <LegendItem bg="#15803d" color="#fff" label="Obsazeno" />
        <LegendItem bg="#166534" color="#fff" label="Historie" />
        <LegendItem bg="#dc2626" color="#fff" label="Servis" />
        <LegendItem bg="#fff" color="#0f1a14" border label="Nepotvrzeno" />
      </div>

      {/* Seznam rezervací */}
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

function LegendItem({ bg, color, label, border }) {
  return (
    <span className="flex items-center gap-1">
      <span style={{ display: 'inline-block', width: 12, height: 12, borderRadius: 3, background: bg, border: border ? '2px solid #d4e8e0' : 'none' }} />
      <span style={{ color: '#4a6357' }}>{label}</span>
    </span>
  )
}

/* ═══ SERVIS TAB — s objednávkami pro technika ═══ */
function ServiceTab({ motoId, motoKm, logAudit }) {
  const [logs, setLogs] = useState([])
  const [schedules, setSchedules] = useState([])
  const [loading, setLoading] = useState(true)
  const [confirmService, setConfirmService] = useState(null)
  const [showOrder, setShowOrder] = useState(null)

  useEffect(() => { loadAll() }, [motoId])

  async function loadAll() {
    setLoading(true)
    const [logRes, schedRes] = await Promise.all([
      supabase.from('maintenance_log').select('*').eq('moto_id', motoId).order('created_at', { ascending: false }),
      supabase.from('maintenance_schedules').select('*').eq('moto_id', motoId).eq('active', true),
    ])
    setLogs(logRes.data || [])
    setSchedules(schedRes.data || [])
    setLoading(false)
  }

  async function handleConfirmService(schedule) {
    // Vytvoř servisní záznam + aktualizuj plán
    const { data: newLog, error: err } = await supabase.from('maintenance_log').insert({
      moto_id: motoId,
      type: schedule.description,
      description: `Plánovaný servis: ${schedule.description}`,
      km_at_service: Number(motoKm) || 0,
    }).select().single()

    if (err) return

    // Aktualizuj last_service_km v plánu
    await supabase.from('maintenance_schedules')
      .update({ last_service_km: Number(motoKm) || 0, last_service_date: new Date().toISOString().split('T')[0] })
      .eq('id', schedule.id)

    await logAudit('service_confirmed', { moto_id: motoId, schedule_id: schedule.id })

    // Generuj objednávku pro technika
    const order = {
      moto_id: motoId,
      type: schedule.description,
      items: getServiceItems(schedule.description),
      km: Number(motoKm) || 0,
      created_at: new Date().toISOString(),
      status: 'pending',
      maintenance_log_id: newLog?.id,
    }

    await supabase.from('service_orders').insert(order)
    setConfirmService(null)
    setShowOrder(order)
    await loadAll()
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-5">
      {/* Nadcházející servisy */}
      {schedules.length > 0 && (
        <Card>
          <SectionTitle>Nadcházející servisy</SectionTitle>
          <div className="space-y-3">
            {schedules.map(s => {
              const currentKm = Number(motoKm) || 0
              const nextAt = (s.last_service_km || 0) + (s.interval_km || 0)
              const remaining = nextAt - currentKm
              const overdue = remaining <= 0
              return (
                <div key={s.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: overdue ? '#fee2e2' : '#f1faf7' }}>
                  <div className="flex-1">
                    <span className="font-bold text-sm">{s.description}</span>
                    <span className="text-xs ml-3" style={{ color: overdue ? '#dc2626' : '#8aab99' }}>
                      {overdue ? `PO TERMÍNU o ${Math.abs(remaining).toLocaleString('cs-CZ')} km` : `za ${remaining.toLocaleString('cs-CZ')} km`}
                    </span>
                  </div>
                  <Button green onClick={() => setConfirmService(s)}>Potvrdit servis</Button>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      {/* Historie servisu */}
      <Card>
        <SectionTitle>Historie servisu</SectionTitle>
        {logs.length === 0 ? <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné servisní záznamy</p> : (
          <div className="space-y-3">
            {logs.map(l => (
              <div key={l.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
                <div className="flex-1">
                  <span className="font-bold text-sm">{l.type || 'Servis'}</span>
                  <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{l.created_at?.slice(0, 10)}</span>
                  {l.km_at_service && <span className="text-xs ml-2 font-mono" style={{ color: '#8aab99' }}>{l.km_at_service.toLocaleString('cs-CZ')} km</span>}
                </div>
                <span className="text-sm" style={{ color: '#4a6357' }}>{l.description || '—'}</span>
                <span className="text-sm font-bold">{l.cost ? `${l.cost.toLocaleString('cs-CZ')} Kč` : '—'}</span>
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Dialog potvrzení servisu */}
      <ConfirmDialog
        open={!!confirmService}
        title={`Potvrdit servis: ${confirmService?.description || ''}`}
        message={`Bude vytvořen servisní záznam a vygenerována objednávka pro technika. Aktuální stav tachometru: ${Number(motoKm || 0).toLocaleString('cs-CZ')} km.`}
        onConfirm={() => confirmService && handleConfirmService(confirmService)}
        onCancel={() => setConfirmService(null)}
      />

      {/* Objednávka pro technika */}
      {showOrder && (
        <Modal open title="Servisní objednávka vygenerována" onClose={() => setShowOrder(null)}>
          <div className="space-y-3">
            <div className="p-4 rounded-lg" style={{ background: '#dcfce7' }}>
              <div className="text-sm font-bold mb-2" style={{ color: '#166534' }}>Objednávka vytvořena</div>
              <div className="text-xs space-y-1" style={{ color: '#4a6357' }}>
                <div><strong>Typ:</strong> {showOrder.type}</div>
                <div><strong>Km:</strong> {showOrder.km.toLocaleString('cs-CZ')}</div>
                <div><strong>Datum:</strong> {showOrder.created_at.slice(0, 10)}</div>
              </div>
            </div>
            <div>
              <div className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>Co je potřeba udělat</div>
              {showOrder.items.map((item, i) => (
                <div key={i} className="flex items-center gap-2 p-2 rounded-lg mb-1" style={{ background: '#f1faf7' }}>
                  <span className="text-sm">{item}</span>
                </div>
              ))}
            </div>
            <Button green onClick={() => setShowOrder(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function getServiceItems(description) {
  const desc = (description || '').toLowerCase()
  if (desc.includes('olej')) return ['Vypustit starý olej', 'Vyměnit olejový filtr', 'Doplnit nový olej dle specifikace', 'Zkontrolovat únik oleje']
  if (desc.includes('pneumat')) return ['Demontovat kola', 'Namontovat nové pneumatiky', 'Vyvážit kola', 'Zkontrolovat brzdové destičky']
  if (desc.includes('kompletní') || desc.includes('servis')) return ['Výměna oleje a filtru', 'Kontrola brzd', 'Kontrola řetězu/rozvodů', 'Kontrola elektroinstalace', 'Kontrola pneumatik', 'Seřízení ventilů', 'Kontrola chladicí kapaliny', 'Celková vizuální kontrola']
  return ['Provést servisní úkon dle popisu', 'Vizuální kontrola', 'Zkušební jízda']
}

/* ═══ HELPER COMPONENTS ═══ */
function SectionTitle({ children }) {
  return <h3 className="text-[10px] font-extrabold uppercase tracking-widest mb-4" style={{ color: '#8aab99' }}>{children}</h3>
}

function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled} className="w-full rounded-btn text-sm outline-none disabled:opacity-50" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function PhotoGallery({ motoId }) {
  const [photos, setPhotos] = useState([])
  const [uploading, setUploading] = useState(false)

  useEffect(() => { loadPhotos() }, [motoId])

  async function loadPhotos() {
    try {
      const { data } = await supabase.storage.from('media').list(`motos/${motoId}`)
      if (data) setPhotos(data.filter(f => f.name !== '.emptyFolderPlaceholder'))
    } catch { setPhotos([]) }
  }

  async function handleUpload(e) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    await supabase.storage.from('media').upload(`motos/${motoId}/${file.name}`, file)
    await loadPhotos()
    setUploading(false)
  }

  async function handleDelete(name) {
    await supabase.storage.from('media').remove([`motos/${motoId}/${name}`])
    await loadPhotos()
  }

  const getUrl = (name) => supabase.storage.from('media').getPublicUrl(`motos/${motoId}/${name}`).data.publicUrl

  return (
    <div className="mt-5">
      <div className="flex items-center gap-3 mb-3">
        <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Fotogalerie</span>
        <label className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '4px 14px', background: '#f1faf7', color: '#4a6357' }}>
          {uploading ? 'Nahrávám…' : '+ Foto'}
          <input type="file" accept="image/*" onChange={handleUpload} className="hidden" />
        </label>
      </div>
      <div className="flex flex-wrap gap-2">
        {photos.map(p => (
          <div key={p.name} className="relative group" style={{ width: 100, height: 100 }}>
            <img src={getUrl(p.name)} alt={p.name} className="w-full h-full object-cover rounded-lg" />
            <button onClick={() => handleDelete(p.name)} className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 cursor-pointer" style={{ background: 'rgba(220,38,38,.8)', color: '#fff', border: 'none', borderRadius: 50, width: 20, height: 20, fontSize: 10 }}>✕</button>
          </div>
        ))}
      </div>
    </div>
  )
}

function PerformanceTab({ motoId }) {
  const [perf, setPerf] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('moto_performance').select('*').eq('moto_id', motoId).single()
      .then(({ data }) => { setPerf(data); setLoading(false) })
      .catch(() => { setPerf(null); setLoading(false) })
  }, [motoId])

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
  if (!perf) return <Card><p style={{ color: '#8aab99', fontSize: 13 }}>Žádné výkonové statistiky</p></Card>

  return (
    <Card>
      <div className="grid grid-cols-3 gap-4">
        {Object.entries(perf).filter(([k]) => !['id', 'moto_id', 'created_at', 'updated_at'].includes(k)).map(([k, v]) => (
          <div key={k} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{k.replace(/_/g, ' ')}</div>
            <div className="text-lg font-bold" style={{ color: '#0f1a14' }}>{typeof v === 'number' ? v.toLocaleString('cs-CZ') : String(v ?? '—')}</div>
          </div>
        ))}
      </div>
    </Card>
  )
}
