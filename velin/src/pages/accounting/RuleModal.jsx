import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) { return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label> }

export default function RuleModal({ rule, onClose, onSaved }) {
  const [suppliers, setSuppliers] = useState([])
  const [inventory, setInventory] = useState([])
  const [form, setForm] = useState(rule ? {
    supplier_id: rule.supplier_id || '', inventory_item_id: rule.inventory_item_id || '',
    trigger_type: rule.trigger_type || 'stock_low', threshold_quantity: rule.threshold_quantity ?? '',
    interval_days: rule.interval_days ?? '', order_quantity: rule.order_quantity ?? '',
    notes: rule.notes || '', is_active: rule.is_active ?? true, email_override: rule.email_override || '',
  } : {
    supplier_id: '', inventory_item_id: '', trigger_type: 'stock_low',
    threshold_quantity: '', interval_days: '', order_quantity: '',
    notes: '', is_active: true, email_override: '',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('suppliers').select('id, name, contact_email').order('name').then(({ data }) => setSuppliers(data || []))
    supabase.from('inventory').select('id, name, sku, stock, min_stock').order('name').then(({ data }) => setInventory(data || []))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))
  const selectedItem = inventory.find(i => i.id === form.inventory_item_id)

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const payload = {
        supplier_id: form.supplier_id, inventory_item_id: form.inventory_item_id || null,
        trigger_type: form.trigger_type,
        threshold_quantity: form.trigger_type === 'stock_low' ? (Number(form.threshold_quantity) || 0) : null,
        interval_days: form.trigger_type === 'interval' ? (Number(form.interval_days) || 7) : null,
        order_quantity: Number(form.order_quantity) || 0, notes: form.notes,
        is_active: form.is_active, email_override: form.email_override || null,
      }
      if (rule) { const { error } = await supabase.from('auto_order_rules').update(payload).eq('id', rule.id); if (error) throw error }
      else { const { error } = await supabase.from('auto_order_rules').insert(payload); if (error) throw error }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={rule ? 'Upravit pravidlo' : 'Nove automaticke pravidlo'} onClose={onClose} wide>
      <div className="space-y-3">
        <div><Label>Typ triggeru</Label>
          <div className="flex gap-2">
            {[{ v: 'stock_low', l: 'Nizky sklad' }, { v: 'interval', l: 'Pravidelny interval' }, { v: 'manual', l: 'Jednorazova' }].map(t => (
              <button key={t.v} onClick={() => set('trigger_type', t.v)}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{ padding: '6px 14px', background: form.trigger_type === t.v ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>{t.l}</button>
            ))}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Skladova polozka</Label>
            <select value={form.inventory_item_id} onChange={e => set('inventory_item_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              <option value="">— Vyberte —</option>
              {inventory.map(i => <option key={i.id} value={i.id}>{i.name} ({i.sku}) — sklad: {i.stock}/{i.min_stock}</option>)}
            </select>
            {selectedItem && <p style={{ fontSize: 11, color: selectedItem.stock <= selectedItem.min_stock ? '#dc2626' : '#6b7280', marginTop: 2 }}>Aktualni stav: {selectedItem.stock} ks (min: {selectedItem.min_stock})</p>}
          </div>
          <div><Label>Dodavatel</Label>
            <select value={form.supplier_id} onChange={e => set('supplier_id', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              <option value="">— Vyberte —</option>
              {suppliers.map(s => <option key={s.id} value={s.id}>{s.name} {s.contact_email ? `(${s.contact_email})` : ''}</option>)}
            </select>
          </div>
        </div>
        {form.trigger_type === 'stock_low' && <div><Label>Prahove mnozstvi (objednat, kdyz sklad klesne pod)</Label><input type="number" value={form.threshold_quantity} onChange={e => set('threshold_quantity', e.target.value)} placeholder={selectedItem ? String(selectedItem.min_stock) : '5'} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>}
        {form.trigger_type === 'interval' && <div><Label>Interval (dni)</Label><input type="number" value={form.interval_days} onChange={e => set('interval_days', e.target.value)} placeholder="7" className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>}
        <div><Label>Objednaci mnozstvi (ks)</Label><input type="number" value={form.order_quantity} onChange={e => set('order_quantity', e.target.value)} placeholder="10" className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Email dodavatele (override)</Label><input value={form.email_override} onChange={e => set('email_override', e.target.value)} placeholder="Pouzije se email z profilu dodavatele" className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Poznamky</Label><textarea value={form.notes} onChange={e => set('notes', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} /></div>
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)} className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Pravidlo aktivni</span>
        </label>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.supplier_id}>{saving ? 'Ukladam...' : rule ? 'Ulozit' : 'Vytvorit'}</Button>
      </div>
    </Modal>
  )
}
