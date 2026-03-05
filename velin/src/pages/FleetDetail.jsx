import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'

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
    // Zkontroluj existující rezervace
    const { data: activeBookings } = await supabase
      .from('bookings')
      .select('id, user_id, start_date, end_date, status, profiles(full_name, email)')
      .eq('moto_id', id)
      .in('status', ['pending', 'active', 'confirmed'])

    if (activeBookings && activeBookings.length > 0) {
      // Zobraz varování s počtem rezervací
      setConfirm({
        type: 'deactivate_with_bookings',
        title: `Motorka má ${activeBookings.length} aktivních rezervací`,
        message: 'Při deaktivaci budou zákazníci upozorněni. Pokračovat?',
        action: async () => {
          const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
          await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)

          // Stornovat čekající rezervace
          if (newStatus !== 'active') {
            for (const b of activeBookings) {
              await supabase.from('bookings')
                .update({ status: 'cancelled', notes: 'Motorka vyřazena z provozu' })
                .eq('id', b.id)
            }
          }

          await logAudit('motorcycle_status_changed', {
            moto_id: id, status: newStatus,
            affected_bookings: activeBookings.length,
          })
          setMoto(m => ({ ...m, status: newStatus }))
          setConfirm(null)
        },
      })
      return
    }

    // Bez aktivních rezervací — rovnou změň status
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
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action, details,
      })
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
          <button
            key={t}
            onClick={() => setTab(t)}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{
              padding: '8px 18px',
              background: tab === t ? '#74FB71' : '#f1faf7',
              color: tab === t ? '#1a2e22' : '#4a6357',
              border: 'none',
              boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'Info' && <InfoTab moto={moto} set={set} error={error} saving={saving} onSave={handleSave} onDeactivate={handleDeactivate} onDelete={() => setConfirm({ type: 'delete' })} />}
      {tab === 'Rezervace' && <BookingsTab motoId={id} />}
      {tab === 'Servis' && <ServiceTab motoId={id} />}
      {tab === 'Výkon' && <PerformanceTab motoId={id} />}

      {/* Potvrzení deaktivace s aktivními rezervacemi */}
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

function InfoTab({ moto, set, error, saving, onSave, onDeactivate, onDelete }) {
  return (
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
        <Button outline onClick={onDeactivate}>
          {moto.status === 'out_of_service' ? 'Aktivovat' : 'Deaktivovat'}
        </Button>
        <Button onClick={onDelete} style={{ color: '#dc2626' }}>Smazat</Button>
      </div>
    </Card>
  )
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

const DAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
const MONTHS = ['Leden', 'Únor', 'Březen', 'Duben', 'Květen', 'Červen', 'Červenec', 'Srpen', 'Září', 'Říjen', 'Listopad', 'Prosinec']
const navBtnStyle = { background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 8, padding: '4px 12px', cursor: 'pointer', fontWeight: 800 }

function BookingsTab({ motoId }) {
  const [bookings, setBookings] = useState([])
  const [month, setMonth] = useState(new Date())
  const [loading, setLoading] = useState(true)

  useEffect(() => { loadBookings() }, [motoId, month])

  async function loadBookings() {
    setLoading(true)
    const start = new Date(month.getFullYear(), month.getMonth(), 1)
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 0)

    const { data } = await supabase
      .from('bookings')
      .select('id, start_date, end_date, status, user_id, profiles(full_name), total_price')
      .eq('moto_id', motoId)
      .in('status', ['pending', 'active', 'confirmed', 'completed'])
      .gte('end_date', start.toISOString().split('T')[0])
      .lte('start_date', end.toISOString().split('T')[0])

    setBookings(data || [])
    setLoading(false)
  }

  const year = month.getFullYear()
  const mon = month.getMonth()
  const daysInMonth = new Date(year, mon + 1, 0).getDate()
  const firstDayOfWeek = (new Date(year, mon, 1).getDay() + 6) % 7 // Po=0

  function getBookingForDay(day) {
    const dateStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    return bookings.find(b => dateStr >= b.start_date.split('T')[0] && dateStr <= b.end_date.split('T')[0])
  }

  const prevMonth = () => setMonth(new Date(year, mon - 1, 1))
  const nextMonth = () => setMonth(new Date(year, mon + 1, 1))

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <Card>
      {/* Navigace měsíce */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <button onClick={prevMonth} style={navBtnStyle}>←</button>
        <span style={{ fontWeight: 800, fontSize: 15 }}>{MONTHS[mon]} {year}</span>
        <button onClick={nextMonth} style={navBtnStyle}>→</button>
      </div>

      {/* Kalendářní mřížka */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2 }}>
        {DAYS.map(d => (
          <div key={d} style={{ textAlign: 'center', fontSize: 10, fontWeight: 800, color: '#8aab99', padding: 4 }}>{d}</div>
        ))}
        {Array.from({ length: firstDayOfWeek }).map((_, i) => <div key={`e${i}`} />)}
        {Array.from({ length: daysInMonth }).map((_, i) => {
          const day = i + 1
          const booking = getBookingForDay(day)
          const todayStr = new Date().toISOString().split('T')[0]
          const dayStr = `${year}-${String(mon + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
          const isToday = todayStr === dayStr
          const bg = booking
            ? booking.status === 'active' ? '#dcfce7' : booking.status === 'pending' ? '#fef3c7' : '#dbeafe'
            : isToday ? '#f1faf7' : 'transparent'
          const color = booking ? '#0f1a14' : isToday ? '#1a8a18' : '#4a6357'

          return (
            <div key={day} title={booking ? `${booking.profiles?.full_name || 'Zákazník'} · ${booking.status}` : ''}
              style={{ textAlign: 'center', padding: '6px 2px', borderRadius: 8, background: bg,
                       color, fontSize: 12, fontWeight: booking ? 800 : 500, cursor: booking ? 'pointer' : 'default' }}>
              {day}
            </div>
          )
        })}
      </div>

      {/* Legenda */}
      <div style={{ display: 'flex', gap: 12, marginTop: 12, fontSize: 10, fontWeight: 700 }}>
        <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: '#dcfce7', marginRight: 4 }} />Aktivní</span>
        <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: '#fef3c7', marginRight: 4 }} />Čekající</span>
        <span><span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: '#dbeafe', marginRight: 4 }} />Potvrzená</span>
      </div>

      {/* Seznam rezervací pod kalendářem */}
      {bookings.length > 0 && (
        <div style={{ marginTop: 16 }}>
          {bookings.map(b => (
            <div key={b.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 10px',
                                      background: '#f1faf7', borderRadius: 10, marginBottom: 4, fontSize: 12 }}>
              <div>
                <span style={{ fontWeight: 700 }}>{b.profiles?.full_name || 'Zákazník'}</span>
                <span style={{ color: '#8aab99', marginLeft: 8 }}>
                  {b.start_date.split('T')[0]} → {b.end_date.split('T')[0]}
                </span>
              </div>
              <span style={{ fontWeight: 800, color: '#3dba3a' }}>{Number(b.total_price).toLocaleString('cs-CZ')} Kč</span>
            </div>
          ))}
        </div>
      )}
    </Card>
  )
}

function ServiceTab({ motoId }) {
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('maintenance_log').select('*').eq('moto_id', motoId).order('created_at', { ascending: false })
      .then(({ data }) => { setLogs(data || []); setLoading(false) })
      .catch(() => { setLogs([]); setLoading(false) })
  }, [motoId])

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <Card>
      {logs.length === 0 ? <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné servisní záznamy</p> : (
        <div className="space-y-3">
          {logs.map(l => (
            <div key={l.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <div className="flex-1">
                <span className="font-bold text-sm">{l.type || 'Servis'}</span>
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{l.created_at?.slice(0, 10)}</span>
              </div>
              <span className="text-sm" style={{ color: '#4a6357' }}>{l.description || '—'}</span>
              <span className="text-sm font-bold">{l.cost ? `${l.cost.toLocaleString('cs-CZ')} Kč` : '—'}</span>
            </div>
          ))}
        </div>
      )}
    </Card>
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
