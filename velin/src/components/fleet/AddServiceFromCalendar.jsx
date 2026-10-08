import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'
import Modal from '../ui/Modal'
import ServiceChecklistPicker from './ServiceChecklistPicker'
import { SERVICE_TASKS } from './serviceCatalog'
import { labelsToItems } from './CustomServiceItems'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

/** Nová servisní událost z kalendáře motorky (detail → Rezervace). Km i technik doplní DB automaticky. */
function AddServiceFromCalendar({ motoId, moto, onClose, onSaved }) {
  const today = new Date().toLocaleDateString('sv-SE')
  const [form, setForm] = useState({ type: 'extraordinary', description: '', cost: '', date_from: today, date_to: '' })
  const [checked, setChecked] = useState(new Set())
  const [customLabels, setCustomLabels] = useState([])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const toggle = (id) => setChecked(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const items = labelsToItems(SERVICE_TASKS.filter(t => checked.has(t.id)).map(t => t.label).concat(customLabels))
      if (!form.description?.trim() && items.length === 0) { setErr('Vyplňte zadání nebo zaškrtněte alespoň jeden úkon'); setSaving(false); return }
      const { error: logErr } = await supabase.from('maintenance_log').insert({
        moto_id: motoId, service_type: form.type, description: form.description?.trim() || null,
        service_date: form.date_from || today, scheduled_date: form.date_to || form.date_from || today,
        status: 'pending', items, cost: Number(form.cost) || null,
      })
      if (logErr) throw logErr
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'service_event_created', new_data: { moto_id: motoId } })
      } catch { /* audit nesmí shodit akci */ }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová servisní událost" onClose={onClose} wide>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ</label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="extraordinary">Mimořádný servis</option>
            <option value="regular">Pravidelný servis</option>
            <option value="repair">Oprava</option>
            <option value="inspection">Inspekce / kontrola</option>
          </select>
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Odhadované náklady (Kč)</label>
          <input type="number" value={form.cost} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servis od</label>
          <input type="date" value={form.date_from} onChange={e => set('date_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Plánované dokončení</label>
          <input type="date" value={form.date_to} onChange={e => set('date_to', e.target.value)} min={form.date_from} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>

      <div className="mt-4">
        <label className="block text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Co je potřeba opravit / zkontrolovat</label>
        <ServiceChecklistPicker checked={checked} onToggle={toggle} customLabels={customLabels} onCustomChange={setCustomLabels} moto={moto} compact maxHeight={320} />
      </div>

      <div className="mt-4">
        <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Zadání / popis závady</label>
        <textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 70, resize: 'vertical' }} placeholder="Popište závadu / důvod servisu, poznámky pro technika…" />
        <div className="text-xs mt-1" style={{ color: '#6b7280' }}>Km při servisu a technik se doplní automaticky; zprávu technika a faktury doplní technik v Servisu.</div>
      </div>

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

export default AddServiceFromCalendar
