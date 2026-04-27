import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import { seasonDaysBetween, SEASON_MONTHS, ServiceScheduleCard, SOSIncidentsCard } from './FleetDetailServiceCard'
import { PhotoGallery } from './FleetDetailPhotos'

function InfoTab({ moto, set, error, saving, onSave, onDeactivate, onDelete, onMotoReload }) {
  const navigate = useNavigate()
  const [schedules, setSchedules] = useState([])
  const [motoBookings, setMotoBookings] = useState([])
  const [avgKm, setAvgKm] = useState(null)
  const [branches, setBranches] = useState([])
  const [showMigrate, setShowMigrate] = useState(false)
  const [migrateTo, setMigrateTo] = useState('')
  const [migrating, setMigrating] = useState(false)
  const [manualUrl, setManualUrl] = useState(null)
  const [uploadingManual, setUploadingManual] = useState(false)
  const [sosIncidents, setSosIncidents] = useState([])
  const unit = moto.tracking_unit || 'km'
  const unitLabel = unit === 'mh' ? 'MH' : 'km'

  useEffect(() => {
    supabase.from('maintenance_schedules').select('*').eq('moto_id', moto.id).eq('active', true)
      .then(({ data }) => setSchedules(data || []))
    supabase.from('bookings').select('moto_id, start_date, end_date')
      .eq('moto_id', moto.id).in('status', ['pending', 'reserved', 'active'])
      .gte('end_date', new Date().toISOString().slice(0, 10))
      .then(({ data }) => setMotoBookings(data || []))
    supabase.from('sos_incidents').select('id, type, status, severity, created_at, description, booking_id')
      .eq('moto_id', moto.id).order('created_at', { ascending: false }).limit(10)
      .then(({ data }) => setSosIncidents(data || []))
    supabase.from('maintenance_log').select('mileage_at_service, created_at').eq('moto_id', moto.id).order('created_at', { ascending: true })
      .then(({ data }) => {
        if (data?.length >= 2) {
          const validEntries = data.filter(d => d.mileage_at_service != null && d.mileage_at_service > 0)
          if (validEntries.length >= 2) {
            const diff = validEntries[validEntries.length - 1].mileage_at_service - validEntries[0].mileage_at_service
            const sDays = seasonDaysBetween(new Date(validEntries[0].created_at), new Date(validEntries[validEntries.length - 1].created_at))
            if (sDays > 0 && diff > 0) { setAvgKm(Math.round((diff / sDays) * 30)); return }
          }
        }
        // Fallback: (current - purchase) / season months since purchase
        const currentVal = Number(moto.mileage) || 0
        const purchaseVal = Number(moto.purchase_mileage) || 0
        const driven = currentVal - purchaseVal
        if (driven > 0 && moto.acquired_at) {
          const acqDate = new Date(moto.acquired_at)
          const sDays = seasonDaysBetween(acqDate, new Date())
          if (sDays > 0) { setAvgKm(Math.round((driven / sDays) * 30)); return }
        }
        if (driven > 0 && moto.year) {
          const seasonMonths = Math.max(1, (new Date().getFullYear() - moto.year) * SEASON_MONTHS)
          setAvgKm(Math.round(driven / seasonMonths))
        }
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
          <Field label="Značka" value={moto.brand} onChange={v => set('brand', v)} placeholder="např. BMW, Honda, Yamaha" />
          <Field label="Pořizovací cena (Kč)" value={moto.purchase_price} onChange={v => set('purchase_price', v)} type="number" />
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kategorie</label>
            <select value={moto.category || ''} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
              <option value="">—</option>
              <option value="cestovni">Cestovní</option>
              <option value="sportovni">Sportovní</option>
              <option value="naked">Naked</option>
              <option value="chopper">Chopper</option>
              <option value="detske">Dětské</option>
            </select>
          </div>
          <Field label="Rok výroby" value={moto.year} onChange={v => set('year', v)} type="number" />
          <Field label="Objem (cc)" value={moto.engine_cc} onChange={v => set('engine_cc', v)} type="number" />
          <Field label="Barva" value={moto.color} onChange={v => set('color', v)} />
          <Field label="Datum pořízení" value={moto.acquired_at || ''} onChange={v => set('acquired_at', v)} type="date" />
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>STK platné do</label>
            <div className="flex items-center gap-2">
              <input type="date" value={moto.stk_valid_until || ''} onChange={e => set('stk_valid_until', e.target.value)}
                className="flex-1 rounded-btn text-sm outline-none"
                style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
              {moto.stk_valid_until && (() => {
                const days = Math.ceil((new Date(moto.stk_valid_until) - new Date()) / 86400000)
                const color = days < 0 ? '#dc2626' : days < 30 ? '#dc2626' : days < 90 ? '#b45309' : '#1a8a18'
                return <span className="text-sm font-bold whitespace-nowrap" style={{ color }}>
                  {days < 0 ? `${Math.abs(days)} dní po` : `${days} dní`}
                </span>
              })()}
            </div>
          </div>
          <Field label={unit === 'mh' ? 'Nájezd (MH)' : 'Nájezd (km)'} value={moto.mileage} onChange={v => set('mileage', v)} type="number" />
          <Field label={unit === 'mh' ? 'Zakoupeno s MH' : 'Zakoupeno s KM'} value={moto.purchase_mileage} onChange={v => set('purchase_mileage', v)} type="number" placeholder={unit === 'mh' ? 'MH při zakoupení' : 'Km při zakoupení'} />
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Sledování nájezdu</label>
            <div className="flex rounded-btn overflow-hidden" style={{ border: '1px solid #d4e8e0' }}>
              <button type="button" onClick={() => set('tracking_unit', 'km')}
                className="flex-1 text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '8px 12px', background: unit === 'km' ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
                Kilometry
              </button>
              <button type="button" onClick={() => set('tracking_unit', 'mh')}
                className="flex-1 text-sm font-extrabold uppercase cursor-pointer"
                style={{ padding: '8px 12px', background: unit === 'mh' ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none', borderLeft: '1px solid #d4e8e0' }}>
                Motohodiny
              </button>
            </div>
          </div>
          <Field label="Typ motoru" value={moto.engine_type} onChange={v => set('engine_type', v)} placeholder="např. boxer, řadový 4V" />
          <Field label="Výkon (kW)" value={moto.power_kw} onChange={v => set('power_kw', v)} type="number" />
          <Field label="Točivý moment (Nm)" value={moto.torque_nm} onChange={v => set('torque_nm', v)} type="number" />
          <Field label="Hmotnost (kg)" value={moto.weight_kg} onChange={v => set('weight_kg', v)} type="number" />
          <Field label="Nádrž (L)" value={moto.fuel_tank_l} onChange={v => set('fuel_tank_l', v)} type="number" />
          <Field label="Výška sedla (mm)" value={moto.seat_height_mm} onChange={v => set('seat_height_mm', v)} type="number" />
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>ŘP kategorie</label>
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
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>ABS</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={moto.has_asc || false} onChange={e => set('has_asc', e.target.checked)} />
              <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>ASC</span>
            </label>
          </div>
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pobočka</label>
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium" style={{ color: '#0f1a14' }}>{moto.branches?.name || '—'}</span>
              <button onClick={() => setShowMigrate(!showMigrate)}
                className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
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
                  className="rounded-btn text-sm font-extrabold uppercase cursor-pointer"
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
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Popis motorky</label>
            <textarea value={moto.description || ''} onChange={e => set('description', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
              placeholder="Popis motorky pro zákazníky…" />
          </div>
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Ideální použití (každé na nový řádek)</label>
            <textarea value={(moto.ideal_usage || []).join('\n')} onChange={e => set('ideal_usage', e.target.value.split('\n'))}
              className="w-full rounded-btn text-sm outline-none" rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
              placeholder="Cestování&#10;Adventure&#10;Offroad" />
          </div>
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Vlastnosti / Features (každá na nový řádek)</label>
            <textarea value={(moto.features || []).join('\n')} onChange={e => set('features', e.target.value.split('\n'))}
              className="w-full rounded-btn text-sm outline-none" rows={3}
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', resize: 'vertical' }}
              placeholder="Vyhřívaná madla&#10;Cruise control&#10;Tempomat" />
          </div>
        </div>

        {/* Manual upload */}
        <div className="mt-5 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center gap-3">
            <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Návod k motorce (PDF)</span>
            <label className="rounded-btn text-sm font-extrabold cursor-pointer"
              style={{ padding: '4px 14px', background: '#dbeafe', color: '#2563eb' }}>
              {uploadingManual ? 'Nahrávám...' : manualUrl ? 'Aktualizovat' : '+ Nahrát'}
              <input type="file" accept=".pdf" onChange={handleManualUpload} className="hidden" />
            </label>
            {manualUrl && (
              <a href={manualUrl} target="_blank" rel="noopener noreferrer"
                className="text-sm font-bold underline" style={{ color: '#1a8a18' }}>
                Zobrazit PDF ↗
              </a>
            )}
          </div>
          <p className="text-sm mt-1" style={{ color: '#1a2e22' }}>Návod se zobrazí zákazníkům na webu i v aplikaci.</p>
        </div>

        <PhotoGallery motoId={moto.id} />
        {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
        <div className="flex gap-3 mt-6">
          <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
          <Button outline onClick={onDeactivate}>{moto.status === 'unavailable' ? 'Aktivovat' : 'Deaktivovat'}</Button>
          <Button onClick={onDelete} style={{ color: '#dc2626' }}>Smazat</Button>
        </div>
      </Card>
      <ServiceScheduleCard moto={moto} schedules={schedules} avgKm={avgKm} unitLabel={unitLabel} unit={unit} motoBookings={motoBookings} />
      <SOSIncidentsCard sosIncidents={sosIncidents} motoId={moto.id} />
    </div>
  )
}

function Field({ label, value, onChange, type = 'text', disabled = false, placeholder = '' }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled} placeholder={placeholder} className="w-full rounded-btn text-sm outline-none disabled:opacity-50" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

export default InfoTab
