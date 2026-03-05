import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import BookingsCalendar from '../components/fleet/BookingsCalendar'
import ServiceTab from '../components/fleet/ServiceTab'
import MotoMap from '../components/shared/MotoMap'

const TABS = ['Info', 'Rezervace', 'Servis', 'Mapa', 'Výkon']

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
    const { data, error: err } = await supabase.from('motorcycles').select('*, branches(name)').eq('id', id).single()
    if (err) setError(err.message)
    else setMoto(data)
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true); setError(null)
    const { model, spz, vin, category, branch_id, price_weekday, price_weekend, mileage, status, year, engine_cc, color } = moto
    const { error: err } = await supabase.from('motorcycles').update({ model, spz, vin, category, branch_id, price_weekday, price_weekend, mileage, status, year, engine_cc, color }).eq('id', id)
    if (err) setError(err.message)
    await logAudit('motorcycle_updated', { moto_id: id })
    setSaving(false)
  }

  async function handleDeactivate() {
    const { data: activeBookings } = await supabase.from('bookings')
      .select('id, user_id, start_date, end_date, status, profiles(full_name)')
      .eq('moto_id', id).in('status', ['pending', 'active', 'confirmed'])
    if (activeBookings?.length > 0) {
      setConfirm({ type: 'deactivate', title: `${activeBookings.length} aktivních rezervací`, message: 'Při deaktivaci budou stornovány. Pokračovat?',
        action: async () => {
          const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
          await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
          if (newStatus !== 'active') {
            for (const b of activeBookings) await supabase.from('bookings').update({ status: 'cancelled', notes: 'Motorka vyřazena' }).eq('id', b.id)
          }
          await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus, affected: activeBookings.length })
          setMoto(m => ({ ...m, status: newStatus })); setConfirm(null)
        },
      })
      return
    }
    const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
    await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
    await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus })
    setMoto(m => ({ ...m, status: newStatus }))
  }

  async function handleDelete() {
    await supabase.from('motorcycles').delete().eq('id', id)
    await logAudit('motorcycle_deleted', { moto_id: id })
    navigate('/flotila')
  }

  async function logAudit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser(); await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details }) } catch {}
  }

  const set = (k, v) => setMoto(m => ({ ...m, [k]: v }))

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (!moto) return <div className="p-4" style={{ color: '#8aab99' }}>{error || 'Motorka nenalezena'}</div>

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
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {tab === 'Info' && <InfoTab moto={moto} set={set} error={error} saving={saving} onSave={handleSave} onDeactivate={handleDeactivate} onDelete={() => setConfirm({ type: 'delete' })} />}
      {tab === 'Rezervace' && <BookingsCalendar motoId={id} />}
      {tab === 'Servis' && <ServiceTab motoId={id} motoMileage={moto.mileage} logAudit={logAudit} />}
      {tab === 'Mapa' && <MotoMap singleMotoId={id} />}
      {tab === 'Výkon' && <PerformanceTab motoId={id} />}
      <ConfirmDialog open={confirm?.type === 'deactivate'} title={confirm?.title || ''} message={confirm?.message || ''} onConfirm={() => confirm?.action?.()} onCancel={() => setConfirm(null)} danger />
      <ConfirmDialog open={confirm?.type === 'delete'} title="Smazat motorku?" message="Tato akce je nevratná." danger onConfirm={handleDelete} onCancel={() => setConfirm(null)} />
    </div>
  )
}

function InfoTab({ moto, set, error, saving, onSave, onDeactivate, onDelete }) {
  const [schedules, setSchedules] = useState([])
  const [avgKm, setAvgKm] = useState(null)

  useEffect(() => {
    supabase.from('maintenance_schedules').select('*').eq('moto_id', moto.id).eq('active', true)
      .then(({ data }) => setSchedules(data || []))
    supabase.from('maintenance_log').select('mileage_at_service, created_at').eq('moto_id', moto.id).order('created_at', { ascending: true })
      .then(({ data }) => {
        if (data?.length >= 2) {
          const diff = (data[data.length - 1].mileage_at_service || 0) - (data[0].mileage_at_service || 0)
          const days = (new Date(data[data.length - 1].created_at) - new Date(data[0].created_at)) / 86400000
          if (days > 0) { setAvgKm(Math.round((diff / days) * 30)); return }
        }
        if (moto.year && moto.mileage) setAvgKm(Math.round(moto.mileage / Math.max(1, (new Date().getFullYear() - moto.year) * 12)))
      })
  }, [moto.id])

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
          <Field label="Cena pracovní den (Kč)" value={moto.price_weekday} onChange={v => set('price_weekday', v)} type="number" />
          <Field label="Cena víkend (Kč)" value={moto.price_weekend} onChange={v => set('price_weekend', v)} type="number" />
          <Field label="Nájezd (km)" value={moto.mileage} onChange={v => set('mileage', v)} type="number" />
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
      <Card>
        <h3 className="text-[10px] font-extrabold uppercase tracking-widest mb-3" style={{ color: '#8aab99' }}>Nájezd a servis</h3>
        <div className="flex gap-6 mb-3">
          <div className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="text-[10px] font-extrabold uppercase" style={{ color: '#8aab99' }}>Měsíční průměr</div>
            <div className="text-lg font-extrabold">{avgKm != null ? `${avgKm.toLocaleString('cs-CZ')} km` : '—'}</div>
          </div>
          <div className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="text-[10px] font-extrabold uppercase" style={{ color: '#8aab99' }}>Celkem</div>
            <div className="text-lg font-extrabold">{moto.mileage ? `${Number(moto.mileage).toLocaleString('cs-CZ')} km` : '—'}</div>
          </div>
        </div>
        {schedules.map(s => {
          const rem = ((s.last_service_km || 0) + (s.interval_km || 0)) - (Number(moto.mileage) || 0)
          const overdue = rem <= 0
          return (
            <div key={s.id} className="flex items-center gap-3 p-2 rounded-lg mb-1" style={{ background: overdue ? '#fee2e2' : '#f1faf7', fontSize: 12 }}>
              <span className="font-bold">{s.description}</span>
              <span style={{ color: '#8aab99' }}>každých {s.interval_km?.toLocaleString('cs-CZ')} km</span>
              <span className="ml-auto font-bold" style={{ color: overdue ? '#dc2626' : '#1a8a18' }}>
                {overdue ? `PO TERMÍNU ${Math.abs(rem).toLocaleString('cs-CZ')} km` : `za ${rem.toLocaleString('cs-CZ')} km`}
                {!overdue && avgKm > 0 ? ` (~${Math.round((rem / avgKm) * 30)} dní)` : ''}
              </span>
            </div>
          )
        })}
        {schedules.length === 0 && <p style={{ color: '#8aab99', fontSize: 12 }}>Žádné plány — přidejte v záložce Servis</p>}
      </Card>
    </div>
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
    try { const { data } = await supabase.storage.from('media').list(`motos/${motoId}`); if (data) setPhotos(data.filter(f => f.name !== '.emptyFolderPlaceholder')) } catch { setPhotos([]) }
  }
  async function handleUpload(e) {
    const file = e.target.files?.[0]; if (!file) return; setUploading(true)
    await supabase.storage.from('media').upload(`motos/${motoId}/${file.name}`, file); await loadPhotos(); setUploading(false)
  }
  const getUrl = (name) => supabase.storage.from('media').getPublicUrl(`motos/${motoId}/${name}`).data.publicUrl
  return (
    <div className="mt-5">
      <div className="flex items-center gap-3 mb-2">
        <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Fotogalerie</span>
        <label className="rounded-btn text-xs font-extrabold cursor-pointer" style={{ padding: '4px 14px', background: '#f1faf7', color: '#4a6357' }}>
          {uploading ? 'Nahrávám…' : '+ Foto'}<input type="file" accept="image/*" onChange={handleUpload} className="hidden" />
        </label>
      </div>
      <div className="flex flex-wrap gap-2">
        {photos.map(p => (
          <div key={p.name} className="relative group" style={{ width: 80, height: 80 }}>
            <img src={getUrl(p.name)} alt={p.name} className="w-full h-full object-cover rounded-lg" />
            <button onClick={async () => { await supabase.storage.from('media').remove([`motos/${motoId}/${p.name}`]); await loadPhotos() }} className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 cursor-pointer" style={{ background: 'rgba(220,38,38,.8)', color: '#fff', border: 'none', borderRadius: 50, width: 18, height: 18, fontSize: 9 }}>✕</button>
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
      .then(({ data }) => { setPerf(data); setLoading(false) }).catch(() => { setPerf(null); setLoading(false) })
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
