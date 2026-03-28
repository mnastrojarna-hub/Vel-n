import { useState } from 'react'

const SERVICE_PRESETS = [
  { key: 'oil', label: 'Vymena oleje', icon: '\ud83d\udee2\ufe0f', defaultKm: 5000, defaultDays: 365 },
  { key: 'tires', label: 'Vymena pneumatik', icon: '\ud83d\udd18', defaultKm: 15000, defaultDays: null },
  { key: 'brakes', label: 'Kontrola brzd', icon: '\ud83d\uded1', defaultKm: 10000, defaultDays: 365 },
  { key: 'full', label: 'Kompletni servis', icon: '\ud83d\udd27', defaultKm: 20000, defaultDays: 365 },
  { key: 'chain', label: 'Retez / rozvodovy remen', icon: '\u26d3\ufe0f', defaultKm: 20000, defaultDays: null },
  { key: 'coolant', label: 'Chladici kapalina', icon: '\ud83d\udca7', defaultKm: 30000, defaultDays: 730 },
  { key: 'air_filter', label: 'Vzduchovy filtr', icon: '\ud83c\udf2c\ufe0f', defaultKm: 15000, defaultDays: 365 },
  { key: 'stk', label: 'STK / Inspekce', icon: '\ud83d\udccb', defaultKm: null, defaultDays: 730 },
  { key: 'custom', label: 'Vlastni...', icon: '\u270f\ufe0f', defaultKm: 10000, defaultDays: null },
]

export default function AddScheduleBtn({ onAdd, saving, unitLabel = 'km', existingTypes = [] }) {
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState(1)
  const [selected, setSelected] = useState(null)
  const [form, setForm] = useState({ description: '', interval_km: '', interval_days: '', first_service_km: '', first_service_desc: '' })
  const [hasFirstService, setHasFirstService] = useState(false)

  function reset() { setOpen(false); setStep(1); setSelected(null); setHasFirstService(false); setForm({ description: '', interval_km: '', interval_days: '', first_service_km: '', first_service_desc: '' }) }

  function selectPreset(preset) {
    setSelected(preset.key)
    setForm({ description: preset.key === 'custom' ? '' : preset.label, interval_km: preset.defaultKm || '', interval_days: preset.defaultDays || '', first_service_km: '', first_service_desc: '' })
    setStep(2)
  }

  function handleSubmit() { if (!form.description) return; const submitForm = { ...form }; if (!hasFirstService) { submitForm.first_service_km = ''; submitForm.first_service_desc = '' }; onAdd(submitForm); reset() }

  if (!open) return <button onClick={() => setOpen(true)} className="rounded-btn text-sm font-extrabold uppercase cursor-pointer" style={{ padding: '6px 16px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>+ Novy servisni plan</button>

  const existingLower = existingTypes.map(t => (t || '').toLowerCase())

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,.4)' }} onClick={e => { if (e.target === e.currentTarget) reset() }}>
      <div className="rounded-card shadow-xl w-full max-w-lg" style={{ background: '#fff', maxHeight: '85vh', overflow: 'auto' }}>
        <div className="flex items-center justify-between p-4" style={{ borderBottom: '1px solid #d4e8e0' }}>
          <h3 className="font-extrabold text-base" style={{ color: '#0f1a14' }}>{step === 1 ? 'Vyberte typ servisu' : 'Nastaveni planu'}</h3>
          <button onClick={reset} className="text-lg font-bold cursor-pointer" style={{ background: 'none', border: 'none', color: '#6b7280' }}>{'\u00d7'}</button>
        </div>
        {step === 1 && (
          <div className="p-4"><div className="grid grid-cols-2 gap-2">
            {SERVICE_PRESETS.map(p => {
              const alreadyExists = p.key !== 'custom' && existingLower.some(e => e.includes(p.label.toLowerCase().split(' ')[0]))
              return (
                <button key={p.key} onClick={() => selectPreset(p)} className="flex items-center gap-3 p-3 rounded-lg text-left cursor-pointer transition-all"
                  style={{ background: alreadyExists ? '#f9fafb' : '#f1faf7', border: '2px solid transparent', opacity: alreadyExists ? 0.6 : 1 }}
                  onMouseEnter={e => e.currentTarget.style.borderColor = '#74FB71'} onMouseLeave={e => e.currentTarget.style.borderColor = 'transparent'}>
                  <span style={{ fontSize: 22 }}>{p.icon}</span>
                  <div>
                    <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{p.label}</div>
                    {p.defaultKm && <div className="text-xs" style={{ color: '#6b7280' }}>~{p.defaultKm.toLocaleString('cs-CZ')} {unitLabel}</div>}
                    {p.defaultDays && !p.defaultKm && <div className="text-xs" style={{ color: '#6b7280' }}>~{p.defaultDays} dni</div>}
                    {alreadyExists && <div className="text-xs font-bold" style={{ color: '#b45309' }}>Jiz pridano</div>}
                  </div>
                </button>
              )
            })}
          </div></div>
        )}
        {step === 2 && (
          <div className="p-4 space-y-4">
            <button onClick={() => setStep(1)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>{'\u2190'} Zpet na vyber typu</button>
            {selected && selected !== 'custom' && <div className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#dcfce7' }}><span style={{ fontSize: 18 }}>{SERVICE_PRESETS.find(p => p.key === selected)?.icon}</span><span className="font-bold text-sm" style={{ color: '#166534' }}>{form.description}</span></div>}
            {selected === 'custom' && <div><label className="block text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Nazev servisu</label><input value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="napr. Vymena svicek, Kontrola ventilu..." autoFocus className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>}
            <div><label className="block text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Intervaly</label>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-xs mb-1" style={{ color: '#6b7280' }}>Interval ({unitLabel})</label><input type="number" value={form.interval_km} onChange={e => setForm(f => ({ ...f, interval_km: e.target.value }))} placeholder={`napr. 10 000 ${unitLabel}`} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
                <div><label className="block text-xs mb-1" style={{ color: '#6b7280' }}>Interval (dni)</label><input type="number" value={form.interval_days} onChange={e => setForm(f => ({ ...f, interval_days: e.target.value }))} placeholder="napr. 365" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} /></div>
              </div>
            </div>
            <div className="rounded-lg p-3" style={{ background: '#eff6ff', border: '1px solid #bfdbfe' }}>
              <label className="flex items-center gap-3 cursor-pointer">
                <input type="checkbox" checked={hasFirstService} onChange={e => setHasFirstService(e.target.checked)} style={{ width: 18, height: 18, accentColor: '#2563eb' }} />
                <div><div className="text-sm font-bold" style={{ color: '#1e40af' }}>Jiny interval pro 1. servis</div><div className="text-xs" style={{ color: '#6b7280' }}>Napr. prvni vymena oleje po 1 000 {unitLabel}, pak kazdych 5 000 {unitLabel}</div></div>
              </label>
              {hasFirstService && <div className="grid grid-cols-2 gap-3 mt-3">
                <div><label className="block text-xs mb-1" style={{ color: '#6b7280' }}>1. servis za ({unitLabel})</label><input type="number" value={form.first_service_km} onChange={e => setForm(f => ({ ...f, first_service_km: e.target.value }))} placeholder="napr. 1 000" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#fff', border: '1px solid #bfdbfe' }} /></div>
                <div><label className="block text-xs mb-1" style={{ color: '#6b7280' }}>Poznamka k 1. servisu</label><input value={form.first_service_desc} onChange={e => setForm(f => ({ ...f, first_service_desc: e.target.value }))} placeholder="Zabehovy servis" className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#fff', border: '1px solid #bfdbfe' }} /></div>
              </div>}
            </div>
            <div className="flex gap-3 pt-2">
              <button onClick={handleSubmit} disabled={saving || !form.description} className="flex-1 rounded-btn text-sm font-extrabold uppercase cursor-pointer" style={{ padding: '10px 20px', background: !form.description ? '#d4e8e0' : '#74FB71', color: '#1a2e22', border: 'none', opacity: saving ? 0.6 : 1 }}>{saving ? 'Vytvarem...' : 'Vytvorit servisni plan'}</button>
              <button onClick={reset} className="rounded-btn text-sm font-extrabold uppercase cursor-pointer" style={{ padding: '10px 20px', background: '#f1faf7', color: '#1a2e22', border: '1px solid #d4e8e0' }}>Zrusit</button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
