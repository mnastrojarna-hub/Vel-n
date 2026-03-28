import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) { return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label> }

export default function QuickOrderModal({ onClose, onSaved }) {
  const [suppliers, setSuppliers] = useState([])
  const [inventory, setInventory] = useState([])
  const [form, setForm] = useState({ supplier_id: '', email_override: '', notes: '' })
  const [items, setItems] = useState([{ item_id: '', quantity: 1, unit_price: '' }])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const [sendEmail, setSendEmail] = useState(true)

  useEffect(() => {
    supabase.from('suppliers').select('id, name, contact_email').order('name').then(({ data }) => setSuppliers(data || []))
    supabase.from('inventory').select('id, name, sku, unit_price').order('name').then(({ data }) => setInventory(data || []))
  }, [])

  const selectedSupplier = suppliers.find(s => s.id === form.supplier_id)

  function addItem() { setItems(i => [...i, { item_id: '', quantity: 1, unit_price: '' }]) }
  function updateItem(idx, key, val) { setItems(i => i.map((it, j) => j === idx ? { ...it, [key]: val } : it)) }
  function removeItem(idx) { setItems(i => i.filter((_, j) => j !== idx)) }

  function selectItem(idx, itemId) {
    const inv = inventory.find(i => i.id === itemId)
    setItems(i => i.map((it, j) => j === idx ? { ...it, item_id: itemId, unit_price: inv?.unit_price || it.unit_price } : it))
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const total = items.reduce((s, it) => s + (Number(it.quantity) || 0) * (Number(it.unit_price) || 0), 0)
      const orderPayload = { supplier_id: form.supplier_id, notes: form.notes, status: 'draft', total_amount: total }
      const { data: order, error: oErr } = await supabase.from('purchase_orders').insert(orderPayload).select().single()
      if (oErr) throw oErr
      const orderItems = items.filter(it => it.item_id).map(it => ({ order_id: order.id, item_id: it.item_id, quantity: Number(it.quantity), unit_price: Number(it.unit_price) }))
      if (orderItems.length > 0) { const { error: iErr } = await supabase.from('purchase_order_items').insert(orderItems); if (iErr) throw iErr }
      if (sendEmail) {
        const email = form.email_override || selectedSupplier?.contact_email
        if (!email) throw new Error('Dodavatel nema email a nebyl zadan zadny override email.')
        const emailItems = items.filter(it => it.item_id).map(it => { const inv = inventory.find(i => i.id === it.item_id); return { name: inv?.name || '', sku: inv?.sku || '', quantity: Number(it.quantity), unit_price: Number(it.unit_price) } })
        await supabase.functions.invoke('send-order-email', { body: { supplier_email: email, supplier_name: selectedSupplier?.name || '', items: emailItems, notes: form.notes, order_id: order.id } })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nova objednavka" onClose={onClose} wide>
      <div className="space-y-3">
        <div><Label>Dodavatel</Label>
          <select value={form.supplier_id} onChange={e => setForm(f => ({ ...f, supplier_id: e.target.value }))} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">— Vyberte —</option>
            {suppliers.map(s => <option key={s.id} value={s.id}>{s.name} {s.contact_email ? `(${s.contact_email})` : ''}</option>)}
          </select>
        </div>
        <div><Label>Email dodavatele (override)</Label>
          <input value={form.email_override} onChange={e => setForm(f => ({ ...f, email_override: e.target.value }))} placeholder={selectedSupplier?.contact_email || 'email@dodavatel.cz'} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          <p style={{ fontSize: 11, color: '#6b7280', marginTop: 2 }}>Ponechte prazdne pro pouziti emailu dodavatele.</p>
        </div>
        <div><Label>Polozky</Label>
          {items.map((it, idx) => (
            <div key={idx} className="flex items-center gap-2 mb-2">
              <select value={it.item_id} onChange={e => selectItem(idx, e.target.value)} className="flex-1 rounded-btn text-sm outline-none" style={inputStyle}>
                <option value="">— Polozka —</option>
                {inventory.map(i => <option key={i.id} value={i.id}>{i.name} ({i.sku})</option>)}
              </select>
              <input type="number" value={it.quantity} onChange={e => updateItem(idx, 'quantity', e.target.value)} placeholder="Ks" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 70 }} />
              <input type="number" value={it.unit_price} onChange={e => updateItem(idx, 'unit_price', e.target.value)} placeholder="Cena/ks" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 100 }} />
              <button onClick={() => removeItem(idx)} className="text-sm cursor-pointer bg-transparent border-none" style={{ color: '#dc2626' }}>{'\u2715'}</button>
            </div>
          ))}
          <button onClick={addItem} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#1a8a18' }}>+ Pridat polozku</button>
        </div>
        <div><Label>Poznamky</Label>
          <textarea value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} />
        </div>
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={sendEmail} onChange={e => setSendEmail(e.target.checked)} className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ihned odeslat objednavkovy email</span>
        </label>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.supplier_id || !items.some(i => i.item_id)}>{saving ? 'Odesilam...' : sendEmail ? 'Vytvorit a odeslat' : 'Vytvorit'}</Button>
      </div>
    </Modal>
  )
}
