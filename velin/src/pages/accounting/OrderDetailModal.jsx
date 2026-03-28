import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { Table, TRow, TH, TD } from '../../components/ui/Table'

const STATUS_LABELS = { draft: 'Koncept', sent: 'Odeslano', received: 'Prijato', cancelled: 'Zruseno' }

export default function OrderDetailModal({ order, onClose, onUpdated, onSendEmail }) {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.from('purchase_order_items').select('*, inventory(name, sku)').eq('order_id', order.id)
      .then(({ data }) => { setItems(data || []); setLoading(false) })
  }, [order.id])

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

  async function markCancelled() {
    await supabase.from('purchase_orders').update({ status: 'cancelled' }).eq('id', order.id)
    onUpdated()
  }

  const fmt = n => n ? `${Number(n).toLocaleString('cs-CZ')} Kc` : '\u2014'
  const total = items.reduce((s, it) => s + (it.quantity || 0) * (it.unit_price || 0), 0)

  return (
    <Modal open title={`Objednavka ${order.order_number || `#${order.id?.slice(0, 8)}`}`} onClose={onClose} wide>
      <div className="mb-3 text-sm grid grid-cols-2 gap-2" style={{ color: '#1a2e22' }}>
        <div>Dodavatel: <b>{order.suppliers?.name || '\u2014'}</b></div>
        <div>Email: <b>{order.suppliers?.contact_email || '\u2014'}</b></div>
        <div>Stav: <b>{STATUS_LABELS[order.status] || order.status}</b></div>
        <div>Vytvoreno: <b>{order.created_at ? new Date(order.created_at).toLocaleString('cs-CZ') : '\u2014'}</b></div>
        {order.sent_at && <div>Odeslano: <b>{new Date(order.sent_at).toLocaleString('cs-CZ')}</b></div>}
        {order.notes && <div className="col-span-2">Poznamky: <b>{order.notes}</b></div>}
      </div>
      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <Table>
          <thead><TRow header><TH>Polozka</TH><TH>SKU</TH><TH>Mnozstvi</TH><TH>Cena/ks</TH><TH>Celkem</TH></TRow></thead>
          <tbody>
            {items.map(it => (
              <TRow key={it.id}>
                <TD bold>{it.inventory?.name || '\u2014'}</TD>
                <TD mono>{it.inventory?.sku || '\u2014'}</TD>
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
        {order.status === 'draft' && (
          <button onClick={() => { onClose(); onSendEmail(order) }} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '8px 16px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Odeslat email</button>
        )}
        {order.status !== 'cancelled' && order.status !== 'received' && (
          <button onClick={markCancelled} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '8px 16px', background: '#fee2e2', color: '#dc2626', border: 'none' }}>Zrusit</button>
        )}
        {order.status !== 'received' && order.status !== 'cancelled' && <Button green onClick={markReceived}>Potvrdit prijeti</Button>}
        <Button onClick={onClose}>Zavrit</Button>
      </div>
    </Modal>
  )
}
