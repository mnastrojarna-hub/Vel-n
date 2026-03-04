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
    const { data, error: err } = await supabase
      .from('motorcycles')
      .select('*, branches(name)')
      .eq('id', id)
      .single()
    if (err) setError(err.message)
    else setMoto(data)
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

      {tab === 'Info' && <InfoTab moto={moto} set={set} error={error} saving={saving} onSave={handleSave} onDeactivate={() => setConfirm('deactivate')} onDelete={() => setConfirm('delete')} />}
      {tab === 'Rezervace' && <BookingsTab motoId={id} />}
      {tab === 'Servis' && <ServiceTab motoId={id} />}
      {tab === 'Výkon' && <PerformanceTab motoId={id} />}

      <ConfirmDialog
        open={confirm === 'deactivate'}
        title={moto.status === 'out_of_service' ? 'Aktivovat motorku?' : 'Deaktivovat motorku?'}
        message={moto.status === 'out_of_service' ? 'Motorka bude opět dostupná.' : 'Motorka nebude dostupná pro rezervace.'}
        onConfirm={handleDeactivate}
        onCancel={() => setConfirm(null)}
      />
      <ConfirmDialog
        open={confirm === 'delete'}
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
    const { data } = await supabase.storage.from('media').list(`motos/${motoId}`)
    if (data) setPhotos(data.filter(f => f.name !== '.emptyFolderPlaceholder'))
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

function BookingsTab({ motoId }) {
  const [bookings, setBookings] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('bookings').select('*, profiles(full_name)').eq('moto_id', motoId).order('start_date', { ascending: false })
      .then(({ data }) => { setBookings(data || []); setLoading(false) })
  }, [motoId])

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <Card>
      {bookings.length === 0 ? <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné rezervace</p> : (
        <div className="space-y-3">
          {bookings.map(b => (
            <div key={b.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <div className="flex-1">
                <span className="font-bold text-sm">{b.profiles?.full_name || 'Zákazník'}</span>
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{b.start_date} → {b.end_date}</span>
              </div>
              <StatusBadge status={b.status} />
              <span className="text-sm font-bold">{b.total_price?.toLocaleString('cs-CZ')} Kč</span>
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
    supabase.from('maintenance_log').select('*').eq('moto_id', motoId).order('scheduled_date', { ascending: false })
      .then(({ data }) => { setLogs(data || []); setLoading(false) })
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
                <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{l.scheduled_date}</span>
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
