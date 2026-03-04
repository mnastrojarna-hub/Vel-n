import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { isDemoMode } from '../../lib/demoData'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'

const PER_PAGE = 25
const STATUS_LABELS = { draft: 'Koncept', sent: 'Odesláno', received: 'Přijato', cancelled: 'Zrušeno' }

export default function OrdersTab() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [detail, setDetail] = useState(null)

  useEffect(() => { load() }, [page])

  async function load() {
    if (isDemoMode()) {
      setOrders([])
      setTotal(0)
      setLoading(false)
      return
    }
    setLoading(true)
    const { data, count } = await supabase
      .from('purchase_orders')
      .select('*, suppliers(name)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    setOrders(data || [])
    setTotal(count || 0)
    setLoading(false)
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => n ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová objednávka</Button>
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Číslo</TH><TH>Dodavatel</TH><TH>Datum</TH><TH>Celkem</TH><TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {orders.map(o => (
                <tr key={o.id} onClick={() => setDetail(o)} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD mono bold>{o.order_number || `#${o.id?.slice(0, 8)}`}</TD>
                  <TD>{o.suppliers?.name || '—'}</TD>
                  <TD>{o.created_at ? new Date(o.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD bold>{fmt(o.total_amount)}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase" style={{
                      padding: '4px 10px',
                      background: o.status === 'received' ? '#dcfce7' : o.status === 'cancelled' ? '#fee2e2' : '#fef3c7',
                      color: o.status === 'received' ? '#1a8a18' : o.status === 'cancelled' ? '#dc2626' : '#b45309',
                    }}>
                      {STATUS_LABELS[o.status] || o.status}
                    </span>
                  </TD>
                </tr>
              ))}
              {orders.length === 0 && <TRow><TD>Žádné objednávky</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <NewOrderModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {detail && <OrderDetail order={detail} onClose={() => setDetail(null)} onUpdated={() => { setDetail(null); load() }} />}
    </div>
  )
}

function NewOrderModal({ onClose, onSaved }) {
  const [suppliers, setSuppliers] = useState([])
  const [form, setForm] = useState({ supplier_id: '', notes: '' })
  const [items, setItems] = useState([{ item_id: '', quantity: 1, unit_price: '' }])
  const [inventory, setInventory] = useState([])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  useEffect(() => {
    supabase.from('suppliers').select('id, name').order('name').then(({ data }) => setSuppliers(data || []))
    supabase.from('inventory').select('id, name, sku').order('name').then(({ data }) => setInventory(data || []))
  }, [])

  function addItem() { setItems(i => [...i, { item_id: '', quantity: 1, unit_price: '' }]) }
  function updateItem(idx, key, val) { setItems(i => i.map((it, j) => j === idx ? { ...it, [key]: val } : it)) }
  function removeItem(idx) { setItems(i => i.filter((_, j) => j !== idx)) }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const total = items.reduce((s, it) => s + (Number(it.quantity) || 0) * (Number(it.unit_price) || 0), 0)
      const { data: order, error: oErr } = await supabase.from('purchase_orders')
        .insert({ supplier_id: form.supplier_id, notes: form.notes, status: 'draft', total_amount: total })
        .select().single()
      if (oErr) throw oErr
      const orderItems = items.filter(it => it.item_id).map(it => ({
        order_id: order.id, item_id: it.item_id, quantity: Number(it.quantity), unit_price: Number(it.unit_price),
      }))
      if (orderItems.length > 0) {
        const { error: iErr } = await supabase.from('purchase_order_items').insert(orderItems)
        if (iErr) throw iErr
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová objednávka" onClose={onClose} wide>
      <div className="space-y-3">
        <div>
          <Label>Dodavatel</Label>
          <select value={form.supplier_id} onChange={e => setForm(f => ({ ...f, supplier_id: e.target.value }))}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="">— Vyberte —</option>
            {suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </div>

        <div>
          <Label>Položky</Label>
          {items.map((it, idx) => (
            <div key={idx} className="flex items-center gap-2 mb-2">
              <select value={it.item_id} onChange={e => updateItem(idx, 'item_id', e.target.value)}
                className="flex-1 rounded-btn text-sm outline-none" style={inputStyle}>
                <option value="">— Položka —</option>
                {inventory.map(i => <option key={i.id} value={i.id}>{i.name} ({i.sku})</option>)}
              </select>
              <input type="number" value={it.quantity} onChange={e => updateItem(idx, 'quantity', e.target.value)}
                placeholder="Ks" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 70 }} />
              <input type="number" value={it.unit_price} onChange={e => updateItem(idx, 'unit_price', e.target.value)}
                placeholder="Cena/ks" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 100 }} />
              <button onClick={() => removeItem(idx)} className="text-sm cursor-pointer bg-transparent border-none" style={{ color: '#dc2626' }}>✕</button>
            </div>
          ))}
          <button onClick={addItem} className="text-xs font-bold cursor-pointer bg-transparent border-none" style={{ color: '#1a8a18' }}>+ Přidat položku</button>
        </div>

        <div><Label>Poznámky</Label><textarea value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.supplier_id}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function OrderDetail({ order, onClose, onUpdated }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { loadItems() }, [order.id])

  async function loadItems() {
    setLoading(true)
    const { data } = await supabase
      .from('purchase_order_items')
      .select('*, inventory(name, sku)')
      .eq('order_id', order.id)
    setItems(data || [])
    setLoading(false)
  }

  async function markReceived() {
    await supabase.from('purchase_orders').update({ status: 'received' }).eq('id', order.id)
    for (const item of items) {
      if (item.item_id && item.quantity) {
        const { data: inv } = await supabase.from('inventory').select('stock').eq('id', item.item_id).single()
        if (inv) await supabase.from('inventory').update({ stock: (inv.stock || 0) + item.quantity }).eq('id', item.item_id)
      }
    }
    onUpdated()
  }

  const fmt = n => n ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'
  const total = items.reduce((s, it) => s + (it.quantity || 0) * (it.unit_price || 0), 0)

  return (
    <Modal open title={`Objednávka ${order.order_number || `#${order.id?.slice(0, 8)}`}`} onClose={onClose} wide>
      <div className="mb-3 text-xs" style={{ color: '#8aab99' }}>
        Dodavatel: <b style={{ color: '#0f1a14' }}>{order.suppliers?.name}</b> · Stav: <b>{STATUS_LABELS[order.status] || order.status}</b>
      </div>
      {loading ? (
        <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : (
        <Table>
          <thead><TRow header><TH>Položka</TH><TH>SKU</TH><TH>Množství</TH><TH>Cena/ks</TH><TH>Celkem</TH></TRow></thead>
          <tbody>
            {items.map(it => (
              <TRow key={it.id}>
                <TD bold>{it.inventory?.name || '—'}</TD>
                <TD mono>{it.inventory?.sku || '—'}</TD>
                <TD>{it.quantity}</TD>
                <TD>{fmt(it.unit_price)}</TD>
                <TD bold>{fmt((it.quantity || 0) * (it.unit_price || 0))}</TD>
              </TRow>
            ))}
            <TRow><TD /><TD /><TD /><TD bold>Celkem:</TD><TD bold>{fmt(total)}</TD></TRow>
          </tbody>
        </Table>
      )}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zavřít</Button>
        {order.status !== 'received' && order.status !== 'cancelled' && (
          <Button green onClick={markReceived}>Potvrdit přijetí</Button>
        )}
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
