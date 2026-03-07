import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction, debugLog } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import StatusBadge from '../components/ui/StatusBadge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'
import BookingsCalendar from '../components/fleet/BookingsCalendar'
import ServiceTab from '../components/fleet/ServiceTab'
import PricingTab from '../components/fleet/PricingTab'
import MotoMap from '../components/shared/MotoMap'

const TABS = ['Info', 'Rezervace', 'Ceník', 'Servis', 'Mapa', 'Výkon']

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
    const result = await debugAction('fleet.load', 'FleetDetail', () =>
      supabase.from('motorcycles').select('*, branches(id, name)').eq('id', id).single()
    , { moto_id: id })
    if (result?.error) setError(result.error.message)
    else setMoto(result?.data)
    setLoading(false)
  }

  async function handleSave() {
    setSaving(true); setError(null)
    const { model, spz, vin, category, branch_id, mileage, status, year, engine_cc, color, acquired_at,
      power_kw, power_hp, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, license_required,
      has_abs, has_asc, description, ideal_usage, features, engine_type } = moto
    const updateData = { model, spz, vin, category, branch_id, mileage, status, year, engine_cc, color, acquired_at,
      power_kw, power_hp, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, license_required,
      has_abs, has_asc, description, ideal_usage, features, engine_type }
    const result = await debugAction('fleet.save', 'FleetDetail', () =>
      supabase.from('motorcycles').update(updateData).eq('id', id)
    , updateData)
    if (result?.error) setError(result.error.message)
    await logAudit('motorcycle_updated', { moto_id: id })
    setSaving(false)
  }

  async function handleDeactivate() {
    const { data: activeBookings } = await debugAction('fleet.checkBookings', 'FleetDetail', () =>
      supabase.from('bookings').select('id, user_id, start_date, end_date, status, profiles(full_name)')
        .eq('moto_id', id).in('status', ['pending', 'active', 'reserved'])
    , { moto_id: id })
    if (activeBookings?.length > 0) {
      setConfirm({ type: 'deactivate', title: `${activeBookings.length} aktivních rezervací`, message: 'Při deaktivaci budou stornovány. Pokračovat?',
        action: async () => {
          const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
          await debugAction('fleet.deactivate', 'FleetDetail', async () => {
            await supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
            if (newStatus !== 'active') {
              for (const b of activeBookings) await supabase.from('bookings').update({ status: 'cancelled', notes: 'Motorka vyřazena' }).eq('id', b.id)
            }
            return { data: { status: newStatus, affected: activeBookings.length } }
          }, { moto_id: id, newStatus })
          await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus, affected: activeBookings.length })
          setMoto(m => ({ ...m, status: newStatus })); setConfirm(null)
        },
      })
      return
    }
    const newStatus = moto.status === 'out_of_service' ? 'active' : 'out_of_service'
    await debugAction('fleet.toggleStatus', 'FleetDetail', () =>
      supabase.from('motorcycles').update({ status: newStatus }).eq('id', id)
    , { moto_id: id, newStatus })
    await logAudit('motorcycle_status_changed', { moto_id: id, status: newStatus })
    setMoto(m => ({ ...m, status: newStatus }))
  }

  async function handleDelete() {
    await debugAction('fleet.delete', 'FleetDetail', () =>
      supabase.from('motorcycles').delete().eq('id', id)
    , { moto_id: id })
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
      <div className="flex gap-2 mb-5 flex-wrap">
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>{t}</button>
        ))}
      </div>
      {tab === 'Info' && <InfoTab moto={moto} set={set} error={error} saving={saving} onSave={handleSave} onDeactivate={handleDeactivate} onDelete={() => setConfirm({ type: 'delete' })} onMotoReload={loadMoto} />}
      {tab === 'Rezervace' && <BookingsCalendar motoId={id} />}
      {tab === 'Ceník' && <PricingTab motoId={id} />}
      {tab === 'Servis' && <ServiceTab motoId={id} motoMileage={moto.mileage} logAudit={logAudit} />}
      {tab === 'Mapa' && <MotoMap singleMotoId={id} />}
      {tab === 'Výkon' && <PerformanceTab motoId={id} />}
      <ConfirmDialog open={confirm?.type === 'deactivate'} title={confirm?.title || ''} message={confirm?.message || ''} onConfirm={() => confirm?.action?.()} onCancel={() => setConfirm(null)} danger />
      <ConfirmDialog open={confirm?.type === 'delete'} title="Smazat motorku?" message="Tato akce je nevratná." danger onConfirm={handleDelete} onCancel={() => setConfirm(null)} />
    </div>
  )
}

function InfoTab({ moto, set, error, saving, onSave, onDeactivate, onDelete, onMotoReload }) {
  const [schedules, setSchedules] = useState([])
  const [avgKm, setAvgKm] = useState(null)
  const [branches, setBranches] = useState([])
  const [showMigrate, setShowMigrate] = useState(false)
  const [migrateTo, setMigrateTo] = useState('')
  const [migrating, setMigrating] = useState(false)
  const [manualUrl, setManualUrl] = useState(null)
  const [uploadingManual, setUploadingManual] = useState(false)

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
    supabase.from('branches').select('id, name').order('name').then(({ data }) => setBranches(data || []))
    loadManual()
  }, [moto.id])

  async function loadManual() {
    try {
      const { data } = await supabase.storage.from('media').list(`motos/${moto.id}/manual`)
      const file = data?.find(f => f.name !== '.emptyFolderPlaceholder')
      if (file) {
        const url = supabase.storage.from('media').getPublicUrl(`motos/${moto.id}/manual/${file.name}`).data.publicUrl
        setManualUrl(url)
        // Sync manual_url to DB for app access
        await supabase.from('motorcycles').update({ manual_url: url }).eq('id', moto.id)
      }
    } catch {}
  }

  async function handleManualUpload(e) {
    const file = e.target.files?.[0]; if (!file) return
    setUploadingManual(true)
    // Remove old manual
    const { data: old } = await supabase.storage.from('media').list(`motos/${moto.id}/manual`)
    if (old?.length) await supabase.storage.from('media').remove(old.map(f => `motos/${moto.id}/manual/${f.name}`))
    await supabase.storage.from('media').upload(`motos/${moto.id}/manual/${file.name}`, file)
    await loadManual()
    setUploadingManual(false)
  }

  async function handleMigrate() {
    if (!migrateTo) return
    setMigrating(true)
    const targetBranch = branches.find(b => b.id === migrateTo)
    await debugAction('fleet.migrate', 'FleetDetail', async () => {
      await supabase.from('motorcycles').update({ branch_id: migrateTo }).eq('id', moto.id)
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'motorcycle_migrated',
        details: { moto_id: moto.id, from_branch: moto.branches?.name, to_branch: targetBranch?.name },
      })
      return { data: { migrated: true } }
    }, { moto_id: moto.id, to_branch: targetBranch?.name })
    setMigrating(false)
    setShowMigrate(false)
    onMotoReload()
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
          <Field label="Datum pořízení" value={moto.acquired_at || ''} onChange={v => set('acquired_at', v)} type="date" />
          <Field label="Nájezd (km)" value={moto.mileage} onChange={v => set('mileage', v)} type="number" />
          <Field label="Typ motoru" value={moto.engine_type} onChange={v => set('engine_type', v)} placeholder="např. boxer, řadový 4V" />
          <Field label="Výkon (kW)" value={moto.power_kw} onChange={v => set('power_kw', v)} type="number" />
          <Field label="Výkon (HP)" value={moto.power_hp} onChange={v => set('power_hp', v)} type="number" />
          <Field label="Točivý moment (Nm)" value={moto.torque_nm} onChange={v => set('torque_nm', v)} type="number" />
          <Field label="Hmotnost (kg)" value={moto.weight_kg} onChange={v => set('weight_kg', v)} type="number" />
          <Field label="Nádrž (L)" value={moto.fuel_tank_l} onChange={v => set('fuel_tank_l', v)} type="number" />
          <Field label="Výška sedla (mm)" value={moto.seat_height_mm} onChange={v => set('seat_height_mm', v)} type="number" />
          <div>
            <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>ŘP kategorie</label>
            <select value={moto.license_required || ''} onChange={e => set('license_required', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
              <option value="">—</option>
              <option value="A">A</option>
              <option value="A2">A2</option>
              <option value="A1">A1</option>
              <option value="AM">AM</option>
              <option value="N">N – nevyžaduje</option>
            </select>
          </div>
          <div className="flex items-center gap-6">
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={moto.has_abs || false} onChange={e => set('has_abs', e.target.checked)} />
              <span className="text-xs font-bold" style={{ color: '#4a6357' }}>ABS</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={moto.has_asc || false} onChange={e => set('has_asc', e.target.checked)} />
              <span className="text-xs font-bold" style={{ color: '#4a6357' }}>ASC</span>
            </label>
          </div>
          <div>
            <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Pobočka</label>
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium" style={{ color: '#0f1a14' }}>{moto.branches?.name || '—'}</span>
              <button onClick={() => setShowMigrate(!showMigrate)}
                className="rounded-btn text-[10px] font-extrabold uppercase cursor-pointer"
                style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                Přesunout
              </button>
            </div>
            {showMigrate && (
              <div className="flex items-center gap-2 mt-2 p-2 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
                <select value={migrateTo} onChange={e => setMigrateTo(e.target.value)}
                  className="flex-1 rounded-btn text-sm outline-none"
                  style={{ padding: '6px 10px', background: '#fff', border: '1px solid #d4e8e0' }}>
                  <option value="">— Vyberte pobočku —</option>
                  {branches.filter(b => b.id !== moto.branch_id).map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
                </select>
                <button onClick={handleMigrate} disabled={!migrateTo || migrating}
                  className="rounded-btn text-[10px] font-extrabold uppercase cursor-pointer"
                  style={{ padding: '6px 12px', background: migrating ? '#d4e8e0' : '#74FB71', color: '#1a2e22', border: 'none' }}>
                  {migrating ? 'Přesouvám...' : 'Potvrdit'}
                </button>
              </div>
            )}
          </div>
        </div>

        {/* Description & features */}
        <div className="mt-5 space-y-3">
          <div>
            <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Popis motorky</label>
            <textarea value={moto.description || ''} onChange={e => set('description', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
              placeholder="Popis motorky pro zákazníky…" />
          </div>
          <div>
            <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Ideální použití (každé na nový řádek)</label>
            <textarea value={(moto.ideal_usage || []).join('\n')} onChange={e => set('ideal_usage', e.target.value.split('\n').filter(Boolean))}
              className="w-full rounded-btn text-sm outline-none" rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
              placeholder="Cestování&#10;Adventure&#10;Offroad" />
          </div>
          <div>
            <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Vlastnosti / Features (každá na nový řádek)</label>
            <textarea value={(moto.features || []).join('\n')} onChange={e => set('features', e.target.value.split('\n').filter(Boolean))}
              className="w-full rounded-btn text-sm outline-none" rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
              placeholder="Vyhřívaná madla&#10;Cruise control&#10;Tempomat" />
          </div>
        </div>

        {/* Manual upload */}
        <div className="mt-5 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center gap-3">
            <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Návod k motorce (PDF)</span>
            <label className="rounded-btn text-xs font-extrabold cursor-pointer"
              style={{ padding: '4px 14px', background: '#dbeafe', color: '#2563eb' }}>
              {uploadingManual ? 'Nahrávám...' : manualUrl ? 'Aktualizovat' : '+ Nahrát'}
              <input type="file" accept=".pdf" onChange={handleManualUpload} className="hidden" />
            </label>
            {manualUrl && (
              <a href={manualUrl} target="_blank" rel="noopener noreferrer"
                className="text-xs font-bold underline" style={{ color: '#1a8a18' }}>
                Zobrazit PDF ↗
              </a>
            )}
          </div>
          <p className="text-[10px] mt-1" style={{ color: '#8aab99' }}>Návod se zobrazí zákazníkům na webu i v aplikaci.</p>
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

function Field({ label, value, onChange, type = 'text', disabled = false, placeholder = '' }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled} placeholder={placeholder} className="w-full rounded-btn text-sm outline-none disabled:opacity-50" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function PhotoGallery({ motoId }) {
  const [photos, setPhotos] = useState([])
  const [dbImages, setDbImages] = useState([])
  const [uploading, setUploading] = useState(false)
  const [urlInput, setUrlInput] = useState('')
  const [showUrlInput, setShowUrlInput] = useState(false)

  useEffect(() => { loadPhotos(); loadDbImages() }, [motoId])

  async function loadDbImages() {
    try {
      const { data } = await supabase.from('motorcycles').select('image_url, images').eq('id', motoId).single()
      if (data) setDbImages(data.images || [])
    } catch {}
  }

  async function syncToDb(urls) {
    const cleaned = urls.filter(u => u && typeof u === 'string')
    await supabase.from('motorcycles').update({
      image_url: cleaned[0] || null,
      images: cleaned
    }).eq('id', motoId)
    setDbImages(cleaned)
  }

  async function loadPhotos() {
    try {
      const { data } = await supabase.storage.from('media').list(`motos/${motoId}`)
      if (data) setPhotos(data.filter(f => f.name !== '.emptyFolderPlaceholder' && f.name !== 'manual'))
    } catch { setPhotos([]) }
  }

  async function handleUpload(e) {
    const file = e.target.files?.[0]; if (!file) return; setUploading(true)
    const { error } = await supabase.storage.from('media').upload(`motos/${motoId}/${file.name}`, file, { upsert: true })
    if (error) { console.error('Upload error:', error); setUploading(false); return }
    await loadPhotos()
    const url = getUrl(file.name)
    // Re-read current DB state to avoid stale data
    const { data: fresh } = await supabase.from('motorcycles').select('images').eq('id', motoId).single()
    const current = (fresh?.images || []).filter(u => u && typeof u === 'string')
    if (!current.includes(url)) {
      await syncToDb([...current, url])
    }
    setUploading(false)
  }

  async function handleAddUrl() {
    const url = urlInput.trim(); if (!url) return
    const updated = [...dbImages, url]
    await syncToDb(updated)
    setUrlInput(''); setShowUrlInput(false)
  }

  async function handleRemoveImage(url, storageName) {
    if (storageName) {
      await supabase.storage.from('media').remove([`motos/${motoId}/${storageName}`])
      await loadPhotos()
    }
    const updated = dbImages.filter(u => u !== url)
    await syncToDb(updated)
  }

  const getUrl = (name) => supabase.storage.from('media').getPublicUrl(`motos/${motoId}/${name}`).data.publicUrl

  const allImages = [...new Set([...dbImages, ...photos.map(p => getUrl(p.name))])]

  return (
    <div className="mt-5">
      <div className="flex items-center gap-3 mb-2">
        <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>Fotogalerie ({allImages.length})</span>
        <label className="rounded-btn text-xs font-extrabold cursor-pointer" style={{ padding: '4px 14px', background: '#f1faf7', color: '#4a6357' }}>
          {uploading ? 'Nahrávám…' : '+ Foto'}<input type="file" accept="image/*" onChange={handleUpload} className="hidden" />
        </label>
        <button onClick={() => setShowUrlInput(!showUrlInput)} className="rounded-btn text-xs font-extrabold cursor-pointer"
          style={{ padding: '4px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
          + URL
        </button>
      </div>
      {showUrlInput && (
        <div className="flex gap-2 mb-2">
          <input type="url" value={urlInput} onChange={e => setUrlInput(e.target.value)}
            placeholder="https://..."
            className="flex-1 rounded-btn text-sm outline-none"
            style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
            onKeyDown={e => e.key === 'Enter' && handleAddUrl()} />
          <button onClick={handleAddUrl} className="rounded-btn text-xs font-extrabold cursor-pointer"
            style={{ padding: '6px 12px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>
            Přidat
          </button>
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        {allImages.map((url, i) => {
          const storagePhoto = photos.find(p => getUrl(p.name) === url)
          return (
            <div key={url} className="relative group" style={{ width: 80, height: 80 }}>
              {i === 0 && <div className="absolute top-1 left-1 z-10" style={{ background: '#74FB71', color: '#1a2e22', borderRadius: 4, padding: '1px 4px', fontSize: 8, fontWeight: 800 }}>HLAVNÍ</div>}
              <img src={url} alt={`Foto ${i + 1}`} className="w-full h-full object-cover rounded-lg" onError={e => { e.target.style.display = 'none' }} />
              <button onClick={() => handleRemoveImage(url, storagePhoto?.name)}
                className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 cursor-pointer"
                style={{ background: 'rgba(220,38,38,.8)', color: '#fff', border: 'none', borderRadius: 50, width: 18, height: 18, fontSize: 9 }}>✕</button>
            </div>
          )
        })}
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
