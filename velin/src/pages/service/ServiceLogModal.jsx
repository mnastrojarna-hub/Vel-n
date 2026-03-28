import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { TYPE_LABELS } from './serviceScheduleUtils'

const TYPES = Object.keys(TYPE_LABELS)

const SERVICE_CHECKLIST = [
  { category: 'Motor & olej', items: [
    'Výměna oleje', 'Výměna olejového filtru', 'Výměna vzduchového filtru',
    'Výměna svíček', 'Kontrola / výměna chladicí kapaliny', 'Neobvyklý zvuk motoru',
  ]},
  { category: 'Brzdy & podvozek', items: [
    'Brzdové destičky přední', 'Brzdové destičky zadní', 'Výměna brzdové kapaliny',
    'Kontrola brzdových kotoučů', 'Kontrola tlumičů / pružin',
  ]},
  { category: 'Pneumatiky & kola', items: [
    'Výměna přední pneumatiky', 'Výměna zadní pneumatiky',
    'Kontrola tlaku pneumatik', 'Kontrola ložisek kol',
  ]},
  { category: 'Řetěz & převody', items: [
    'Seřízení řetězu', 'Výměna řetězu + rozet', 'Promazání řetězu',
  ]},
  { category: 'Elektrika & světla', items: [
    'Kontrola / výměna baterie', 'Kontrola světel',
    'Kontrola pojistek', 'Problém se startérem',
  ]},
  { category: 'Ostatní', items: [
    'Příprava na STK', 'Kontrola / seřízení spojky',
    'Kosmetická oprava (lak, plasty)', 'Oprava po nehodě', 'Jiná oprava',
  ]},
]

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

export default function ServiceLogModal({ entry, onClose, onSaved }) {
  const [motos, setMotos] = useState([])
  const [employees, setEmployees] = useState([])
  const existingChecked = new Set()
  if (entry?.items && Array.isArray(entry.items)) {
    entry.items.forEach(it => existingChecked.add(it.label))
  }
  const [form, setForm] = useState(entry ? {
    moto_id: entry.moto_id || '', type: entry.type || '',
    scheduled_date: entry.scheduled_date || '',
    completed_date: entry.completed_date || '', description: entry.description || '',
    cost: entry.cost || '', performed_by: entry.performed_by || '',
    technician_id: entry.technician_id || '',
    status: entry.status || 'pending',
    mileage_at_service: entry.mileage_at_service || entry.km_at_service || '',
    service_from: entry.service_date || '',
    labor_hours: entry.labor_hours || '',
    extra_cost: entry.extra_cost || '',
  } : {
    moto_id: '', type: '', scheduled_date: '', completed_date: '', description: '',
    cost: '', performed_by: '', technician_id: '', status: 'pending',
    mileage_at_service: '', service_from: '', labor_hours: '', extra_cost: '',
  })
  const [checkedItems, setCheckedItems] = useState(() => {
    const m = {}
    SERVICE_CHECKLIST.forEach(cat => cat.items.forEach(it => { m[it] = existingChecked.has(it) }))
    return m
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('motorcycles').select('id, model, spz, tracking_unit, mileage').order('model').then(({ data }) => setMotos(data || []))
    supabase.from('acc_employees').select('id, name, position, hourly_rate').order('name').then(({ data }) => setEmployees(data || []))
  }, [])

  const selectedMoto = motos.find(m => m.id === form.moto_id)
  const unitLabel = selectedMoto?.tracking_unit === 'mh' ? 'MH' : 'km'
  const selectedEmployee = employees.find(e => e.id === form.technician_id)

  const laborCost = (Number(form.labor_hours) || 0) * (selectedEmployee?.hourly_rate || 500)
  const extraCost = Number(form.extra_cost) || 0
  const calculatedCost = laborCost + extraCost

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const toggleCheck = (label) => setCheckedItems(c => ({ ...c, [label]: !c[label] }))

  function handleSelectTechnician(val) {
    if (val === '__external__') { set('technician_id', ''); set('performed_by', '') }
    else if (val) { const emp = employees.find(e => e.id === val); set('technician_id', val); set('performed_by', emp?.name || '') }
    else { set('technician_id', ''); set('performed_by', '') }
  }

  function buildItems() {
    const items = []
    SERVICE_CHECKLIST.forEach(cat => { cat.items.forEach(label => { if (checkedItems[label]) items.push({ label, done: false, note: '' }) }) })
    return items
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      debugLog('ServiceLog', 'handleSave', { isEdit: !!entry, moto_id: form.moto_id })
      const TYPE_TO_SERVICE = { oil_change: 'regular', tire_change: 'regular', brake_check: 'regular', full_service: 'regular', inspection: 'regular', repair: 'repair' }
      const items = buildItems()
      const fullDescription = form.description?.trim() || null
      const finalCost = Number(form.cost) || calculatedCost || null
      const today = new Date().toISOString().slice(0, 10)
      const isNewService = !entry
      const shouldSetMaintenance = form.status === 'in_service' && form.moto_id

      if (isNewService && shouldSetMaintenance) {
        const { data: active } = await supabase.from('bookings').select('id, status, profiles(full_name)').eq('moto_id', form.moto_id).eq('status', 'active').gte('end_date', today)
        if (active?.length > 0) {
          const names = active.map(b => b.profiles?.full_name || '?').join(', ')
          if (!window.confirm(`Motorka má ${active.length} aktivní pronájem (${names}). Pokračovat? Zákazníkovi bude potřeba nabídnout náhradu.`)) { setSaving(false); return }
        }
        const { data: future } = await supabase.from('bookings').select('id, start_date, end_date, profiles(full_name)').eq('moto_id', form.moto_id).in('status', ['pending', 'reserved']).gte('start_date', today).order('start_date').limit(5)
        if (future?.length > 0) {
          const lines = future.map(b => `  ${b.profiles?.full_name || '?'}: ${new Date(b.start_date).toLocaleDateString('cs-CZ')} – ${new Date(b.end_date).toLocaleDateString('cs-CZ')}`).join('\n')
          window.alert(`Upozornění — nadcházející rezervace (${future.length}):\n${lines}\nMotorka musí být ze servisu zpět včas, nebo nabídněte náhradu.`)
        }
      }

      const payload = {
        moto_id: form.moto_id, type: form.type || null, service_type: TYPE_TO_SERVICE[form.type] || 'repair',
        description: fullDescription, cost: finalCost, km_at_service: Number(form.mileage_at_service) || null,
        performed_by: form.performed_by || null, technician_id: form.technician_id || null,
        labor_hours: Number(form.labor_hours) || null, extra_cost: Number(form.extra_cost) || null,
        status: form.status || 'pending', service_date: form.service_from || today,
        scheduled_date: form.scheduled_date || null, completed_date: form.completed_date || null,
        items: items.length > 0 ? items : null,
      }
      if (entry) {
        const { error } = await debugAction('maintenance_log.update', 'ServiceLog', () => supabase.from('maintenance_log').update(payload).eq('id', entry.id))
        if (error) throw error
      } else {
        const { error } = await debugAction('maintenance_log.insert', 'ServiceLog', () => supabase.from('maintenance_log').insert(payload))
        if (error) throw error
      }
      if (form.status === 'completed' && form.moto_id) {
        await supabase.from('motorcycles').update({ status: 'active', last_service_date: today }).eq('id', form.moto_id)
      } else if (shouldSetMaintenance) {
        await supabase.from('motorcycles').update({ status: 'maintenance' }).eq('id', form.moto_id)
      }
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: entry ? 'service_updated' : 'service_created', details: { moto_id: form.moto_id } })
      onSaved()
    } catch (e) { debugError('ServiceLog', 'handleSave', e); setErr(e.message) } finally { setSaving(false) }
  }

  const checkedCount = Object.values(checkedItems).filter(Boolean).length

  return (
    <Modal open title={entry ? 'Upravit servis' : 'Nový servis'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Motorka</Label>
          <select value={form.moto_id} onChange={e => set('moto_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">—</option>
            {motos.map(m => <option key={m.id} value={m.id}>{m.model} ({m.spz})</option>)}
          </select>
        </div>
        <div><Label>Typ servisu</Label><select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}><option value="">—</option>{TYPES.map(t => <option key={t} value={t}>{TYPE_LABELS[t]}</option>)}</select></div>
        <div><Label>Stav</Label><select value={form.status} onChange={e => set('status', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}><option value="pending">Plánovaný</option><option value="in_service">V servisu</option><option value="completed">Dokončeno</option></select></div>
        <div><Label>Servis od</Label><input type="date" value={form.service_from} onChange={e => set('service_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Plánované dokončení</Label><input type="date" value={form.scheduled_date} onChange={e => set('scheduled_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Skutečné dokončení</Label><input type="date" value={form.completed_date} onChange={e => set('completed_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>{unitLabel} při servisu</Label><input type="number" value={form.mileage_at_service} onChange={e => set('mileage_at_service', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder={selectedMoto ? String(selectedMoto.mileage || '') : ''} /></div>
      </div>

      <div className="mt-4">
        <Label>Technik</Label>
        <div className="grid grid-cols-2 gap-3">
          <select value={form.technician_id || (form.performed_by && !form.technician_id ? '__external__' : '')} onChange={e => handleSelectTechnician(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">— Vyberte technika —</option>
            {employees.map(e => <option key={e.id} value={e.id}>{e.name}{e.position ? ` (${e.position})` : ''} — {e.hourly_rate || 500} Kč/h</option>)}
            <option value="__external__">Externí technik</option>
          </select>
          {(form.technician_id === '' && form.performed_by !== '') || (!form.technician_id && form.performed_by) ? (
            <input type="text" value={form.performed_by} onChange={e => set('performed_by', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Jméno externího technika…" />
          ) : (
            <div className="text-sm flex items-center" style={{ color: '#6b7280' }}>{selectedEmployee ? `Sazba: ${selectedEmployee.hourly_rate || 500} Kč/h` : 'Vyberte technika'}</div>
          )}
        </div>
      </div>

      <div className="mt-4">
        <Label>Náklady</Label>
        <div className="grid grid-cols-3 gap-3">
          <div><div className="text-xs font-bold mb-1" style={{ color: '#6b7280' }}>Hodiny práce</div><input type="number" step="0.5" min="0" value={form.labor_hours} onChange={e => set('labor_hours', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="0" /></div>
          <div><div className="text-xs font-bold mb-1" style={{ color: '#6b7280' }}>Extra náklady (Kč)</div><input type="number" min="0" value={form.extra_cost} onChange={e => set('extra_cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="0" /></div>
          <div><div className="text-xs font-bold mb-1" style={{ color: '#6b7280' }}>Celkem (Kč)</div><input type="number" min="0" value={form.cost} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, background: form.cost ? '#fff' : '#f1faf7' }} placeholder={calculatedCost ? String(calculatedCost) : '0'} />
            {calculatedCost > 0 && !form.cost && (
              <div className="text-xs mt-1" style={{ color: '#1a8a18' }}>
                Kalkulace: {laborCost > 0 ? `${Number(form.labor_hours)}h × ${selectedEmployee?.hourly_rate || 500} = ${laborCost} Kč` : ''}
                {laborCost > 0 && extraCost > 0 ? ' + ' : ''}{extraCost > 0 ? `extra ${extraCost} Kč` : ''}
                {calculatedCost > 0 ? ` = ${calculatedCost} Kč` : ''}
              </div>
            )}
          </div>
        </div>
        <div className="text-xs mt-1" style={{ color: '#9ca3af' }}>Ponechte celkem prázdné pro automatický výpočet z hodin a extra nákladů. Vyplněním přepíšete kalkulaci.</div>
      </div>

      <div className="mt-4">
        <Label>Zaškrtněte co je potřeba opravit / zkontrolovat {checkedCount > 0 && <span style={{ color: '#1a8a18' }}>({checkedCount} vybráno)</span>}</Label>
        <div className="grid grid-cols-2 gap-3 mt-2">
          {SERVICE_CHECKLIST.map(cat => (
            <div key={cat.category} className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a8a18' }}>{cat.category}</div>
              <div className="space-y-1">
                {cat.items.map(label => (
                  <label key={label} className="flex items-center gap-2 cursor-pointer p-1 rounded hover:bg-[#e8fde8] transition-colors">
                    <input type="checkbox" checked={checkedItems[label] || false} onChange={() => toggleCheck(label)} style={{ accentColor: '#16a34a', width: 16, height: 16, cursor: 'pointer' }} />
                    <span className="text-sm" style={{ color: '#1a2e22', fontWeight: checkedItems[label] ? 700 : 400 }}>{label}</span>
                  </label>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-4">
        <Label>Popis servisu</Label>
        <textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} placeholder="Popište co vše se opravovalo / vyměnilo…" />
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.moto_id}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}
