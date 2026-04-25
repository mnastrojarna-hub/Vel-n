import { useState, useMemo } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'
import ImageUploader from '../components/ui/ImageUploader'

const CATEGORIES = [
  { value: 'cestovni', label: 'Cestovní' },
  { value: 'sportovni', label: 'Sportovní' },
  { value: 'naked', label: 'Naked' },
  { value: 'chopper', label: 'Chopper' },
  { value: 'detske', label: 'Dětské' },
]

function FormField({ label, value, onChange, type = 'text' }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

export default function AddMotoModal({ branches, onClose, onSaved }) {
  // Pre-generujeme ID, aby bylo možné ukládat fotky do správné složky ještě před uložením do DB
  const motoId = useMemo(() => (
    (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`
  ), [])

  const [form, setForm] = useState({
    model: '', spz: '', vin: '', category: '', branch_id: '',
    acquired_at: '', mileage: 0, status: 'active',
    brand: '', purchase_price: '',
    oil_interval_km: 10000, oil_interval_days: 365,
    tire_interval_km: 25000, full_service_interval_km: 20000,
    full_service_interval_days: 730, stk_valid_until: '',
    images: [],
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true)
    setErr(null)
    try {
      const mileageVal = Number(form.mileage) || 0
      const oilKm = Number(form.oil_interval_km) || 10000
      const oilDays = Number(form.oil_interval_days) || 365
      const tireKm = Number(form.tire_interval_km) || 25000
      const fullKm = Number(form.full_service_interval_km) || 20000
      const fullDays = Number(form.full_service_interval_days) || 730
      const images = (form.images || []).filter(Boolean)
      const motoData = {
        id: motoId,
        model: form.model, spz: form.spz, vin: form.vin,
        category: form.category, status: form.status,
        acquired_at: form.acquired_at || null, mileage: mileageVal, purchase_mileage: mileageVal,
        branch_id: form.branch_id || null, brand: form.brand?.trim() || null,
        purchase_price: form.purchase_price ? Number(form.purchase_price) : 0,
        stk_valid_until: form.stk_valid_until || null,
        oil_interval_km: oilKm, oil_interval_days: oilDays, tire_interval_km: tireKm,
        full_service_interval_km: fullKm, full_service_interval_days: fullDays,
        image_url: images[0] || null,
        images,
      }
      const result = await debugAction('fleet.create', 'AddMotoModal', () =>
        supabase.from('motorcycles').insert(motoData).select().single()
      , motoData)
      if (result?.error) throw result.error
      const newMoto = result?.data

      if (newMoto) {
        const schedules = [
          { moto_id: newMoto.id, schedule_type: 'both', interval_km: oilKm, interval_days: oilDays, description: 'Výměna oleje', active: true },
          { moto_id: newMoto.id, schedule_type: 'mileage', interval_km: tireKm, description: 'Výměna pneumatik', active: true },
          { moto_id: newMoto.id, schedule_type: 'both', interval_km: fullKm, interval_days: fullDays, description: 'Kompletní servis', active: true },
        ]
        await supabase.from('maintenance_schedules').insert(schedules)
        await supabase.from('moto_day_prices').insert({
          moto_id: newMoto.id, price_mon: 0, price_tue: 0, price_wed: 0, price_thu: 0, price_fri: 0, price_sat: 0, price_sun: 0,
        })
      }

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'motorcycle_created', details: { moto_id: newMoto.id } })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open wide title="Nová motorka" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Model" value={form.model} onChange={v => set('model', v)} />
        <FormField label="SPZ" value={form.spz} onChange={v => set('spz', v)} />
        <FormField label="VIN" value={form.vin} onChange={v => set('vin', v)} />
        <FormField label="Značka" value={form.brand} onChange={v => set('brand', v)} placeholder="např. BMW, Honda, Yamaha" />
        <FormField label="Pořizovací cena (Kč)" value={form.purchase_price} onChange={v => set('purchase_price', v)} type="number" />
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Kategorie</label>
          <select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">—</option>
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Pobočka</label>
          <select value={form.branch_id} onChange={e => set('branch_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">—</option>
            {branches.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </div>
        <FormField label="Datum pořízení" value={form.acquired_at} onChange={v => set('acquired_at', v)} type="date" />
        <FormField label="Nájezd (km)" value={form.mileage} onChange={v => set('mileage', v)} type="number" />
      </div>

      <h4 className="text-sm font-extrabold uppercase tracking-widest mt-5 mb-3" style={{ color: '#1a2e22' }}>Fotky motorky</h4>
      <ImageUploader
        value={form.images}
        onChange={urls => set('images', urls)}
        folder={`motos/${motoId}`}
        helperText="Přetáhněte fotky z počítače nebo klikněte pro výběr. První fotka bude hlavní (zobrazí se v kalendáři, výběru motorky a v aplikaci)."
      />

      <h4 className="text-sm font-extrabold uppercase tracking-widest mt-5 mb-3" style={{ color: '#1a2e22' }}>Servisní intervaly</h4>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Olej — interval (km)" value={form.oil_interval_km} onChange={v => set('oil_interval_km', v)} type="number" />
        <FormField label="Olej — interval (dní)" value={form.oil_interval_days} onChange={v => set('oil_interval_days', v)} type="number" />
        <FormField label="Pneumatiky — interval (km)" value={form.tire_interval_km} onChange={v => set('tire_interval_km', v)} type="number" />
        <FormField label="Kompletní servis (km)" value={form.full_service_interval_km} onChange={v => set('full_service_interval_km', v)} type="number" />
        <FormField label="Kompletní servis (dní)" value={form.full_service_interval_days} onChange={v => set('full_service_interval_days', v)} type="number" />
        <FormField label="STK platné do" value={form.stk_valid_until} onChange={v => set('stk_valid_until', v)} type="date" />
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.model}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}
