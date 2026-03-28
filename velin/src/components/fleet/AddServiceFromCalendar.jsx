import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../ui/Button'
import Modal from '../ui/Modal'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }

const CAL_SERVICE_CHECKLIST = [
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

function AddServiceFromCalendar({ motoId, onClose, onSaved }) {
  const today = new Date().toISOString().slice(0, 10)
  const [form, setForm] = useState({
    type: 'extraordinary', description: '', cost: '', date_from: today, date_to: '', extra_note: '',
  })
  const [checkedItems, setCheckedItems] = useState(() => {
    const m = {}
    CAL_SERVICE_CHECKLIST.forEach(cat => cat.items.forEach(it => { m[it] = false }))
    return m
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const toggleCheck = (label) => setCheckedItems(c => ({ ...c, [label]: !c[label] }))
  const checkedCount = Object.values(checkedItems).filter(Boolean).length

  function buildItems() {
    const items = []
    CAL_SERVICE_CHECKLIST.forEach(cat => {
      cat.items.forEach(label => {
        if (checkedItems[label]) items.push({ label, done: false, note: '' })
      })
    })
    return items
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const items = buildItems()
      if (!form.description?.trim() && items.length === 0) {
        setErr('Vyplňte popis nebo zaškrtněte alespoň jednu položku')
        setSaving(false)
        return
      }
      const { error: logErr } = await supabase.from('maintenance_log').insert({
        moto_id: motoId,
        service_type: form.type,
        description: form.description?.trim() || null,
        service_date: form.date_from || today,
        scheduled_date: form.date_to || form.date_from || today,
        status: 'pending',
        items: items.length > 0 ? items : null,
        planned_end: form.date_to || null,
        extra_note: form.extra_note?.trim() || null,
        cost: Number(form.cost) || null,
      })
      if (logErr) throw logErr
      try {
        const { data: { user } } = await supabase.auth.getUser()
        await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action: 'service_event_created', details: { moto_id: motoId } })
      } catch {}
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová servisní událost" onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ</label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="extraordinary">Mimořádný servis</option>
            <option value="regular">Pravidelný servis</option>
            <option value="repair">Oprava</option>
          </select>
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servis od</label>
          <input type="date" value={form.date_from} onChange={e => set('date_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Plánované dokončení</label>
          <input type="date" value={form.date_to} onChange={e => set('date_to', e.target.value)} min={form.date_from} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Odhadované náklady (Kč)</label>
          <input type="number" value={form.cost} onChange={e => set('cost', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>

      {/* Servisní checklist */}
      <div className="mt-4">
        <label className="block text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
          Škrtněte co je potřeba opravit / zkontrolovat {checkedCount > 0 && <span style={{ color: '#1a8a18' }}>({checkedCount} vybráno)</span>}
        </label>
        <div className="grid grid-cols-2 gap-3" style={{ maxHeight: 350, overflowY: 'auto' }}>
          {CAL_SERVICE_CHECKLIST.map(cat => (
            <div key={cat.category} className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="text-xs font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a8a18' }}>{cat.category}</div>
              <div className="space-y-1">
                {cat.items.map(label => (
                  <label key={label} className="flex items-center gap-2 cursor-pointer p-1 rounded hover:bg-[#e8fde8] transition-colors">
                    <input
                      type="checkbox"
                      checked={checkedItems[label] || false}
                      onChange={() => toggleCheck(label)}
                      style={{ accentColor: '#16a34a', width: 16, height: 16, cursor: 'pointer' }}
                    />
                    <span className="text-sm" style={{ color: '#1a2e22', fontWeight: checkedItems[label] ? 700 : 400 }}>{label}</span>
                  </label>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 mt-4">
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Servisní záznam (volný text)</label>
          <textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} placeholder="Popište závadu / důvod servisu…" />
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Doplňující poznámka</label>
          <textarea value={form.extra_note} onChange={e => set('extra_note', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} placeholder="Vlastní poznámka k servisu…" />
        </div>
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
export { CAL_SERVICE_CHECKLIST }
