import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Pagination from '../../components/ui/Pagination'
import SearchInput from '../../components/ui/SearchInput'
import Modal from '../../components/ui/Modal'

const PER_PAGE = 25

const STATUS_LABELS = {
  new: 'Nová', confirmed: 'Potvrzeno', processing: 'Zpracovává se',
  shipped: 'Odesláno', delivered: 'Doručeno', cancelled: 'Zrušeno',
  returned: 'Vráceno', refunded: 'Refundováno',
}
const STATUS_COLORS = {
  new: { bg: '#dbeafe', color: '#2563eb' },
  confirmed: { bg: '#dcfce7', color: '#1a8a18' },
  processing: { bg: '#fef3c7', color: '#b45309' },
  shipped: { bg: '#e0e7ff', color: '#4338ca' },
  delivered: { bg: '#dcfce7', color: '#15803d' },
  cancelled: { bg: '#fee2e2', color: '#dc2626' },
  returned: { bg: '#fef3c7', color: '#92400e' },
  refunded: { bg: '#f3f4f6', color: '#6b7280' },
}

const PAYMENT_LABELS = { pending: 'Nezaplaceno', paid: 'Zaplaceno', refunded: 'Vráceno', failed: 'Selhalo' }
const PAYMENT_COLORS = {
  pending: { bg: '#fee2e2', color: '#dc2626' },
  paid: { bg: '#dcfce7', color: '#1a8a18' },
  refunded: { bg: '#f3f4f6', color: '#6b7280' },
  failed: { bg: '#fee2e2', color: '#dc2626' },
}

export default function ShopOrdersTab() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [detail, setDetail] = useState(null)
  const [showAdd, setShowAdd] = useState(false)

  useEffect(() => { load() }, [page, statusFilter])

  // Auto-confirm paid voucher orders from app
  useEffect(() => {
    autoConfirmPaidVouchers()
    const channel = supabase
      .channel('shop-orders-paid')
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'shop_orders', filter: 'payment_status=eq.paid' },
        () => { autoConfirmPaidVouchers(); load() })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [])

  async function autoConfirmPaidVouchers() {
    try {
      const { data: paidNew } = await supabase
        .from('shop_orders')
        .select('*, shop_order_items(*)')
        .eq('payment_status', 'paid')
        .eq('status', 'new')
      if (!paidNew || paidNew.length === 0) return
      for (const order of paidNew) {
        // Guard: skip if vouchers already generated (avoid duplicates with processVoucherOrder)
        const { data: existingVouchers } = await supabase
          .from('vouchers').select('code').eq('order_id', order.id)
        if (existingVouchers && existingVouchers.length > 0) continue

        const items = order.shop_order_items || []
        const voucherItems = items.filter(it =>
          (it.product_name || '').toLowerCase().includes('voucher') ||
          (it.product_name || '').toLowerCase().includes('poukaz')
        )
        const isAllVouchers = voucherItems.length === items.length && items.length > 0

        // All vouchers (digital or physical) → delivered (codes sent electronically)
        // Mixed (vouchers + physical products) → confirmed (vouchers sent, physical processed separately)
        const newStatus = isAllVouchers ? 'delivered' : 'confirmed'
        await supabase.from('shop_orders').update({
          status: newStatus,
          confirmed_at: new Date().toISOString(),
          ...(isAllVouchers ? { delivered_at: new Date().toISOString() } : {}),
        }).eq('id', order.id)

        // Generate voucher codes for voucher items
        const generatedCodes = []
        if (voucherItems.length > 0) {
          for (const item of voucherItems) {
            const code = 'MG' + Math.random().toString(36).substring(2, 8).toUpperCase()
            generatedCodes.push(code)
            const validUntil = new Date()
            validUntil.setFullYear(validUntil.getFullYear() + 1)
            await supabase.from('vouchers').insert({
              code,
              amount: item.unit_price || item.total_price || 0,
              currency: 'CZK',
              status: 'active',
              buyer_id: order.customer_id || null,
              buyer_name: order.customer_name || '',
              buyer_email: order.customer_email || '',
              valid_from: new Date().toISOString().split('T')[0],
              valid_until: validUntil.toISOString().split('T')[0],
              source: 'eshop',
              order_id: order.id,
            })
            // Send voucher email
            supabase.functions.invoke('send-booking-email', {
              body: {
                type: 'voucher_purchased',
                to: order.customer_email,
                voucher_code: code,
                voucher_amount: item.unit_price || item.total_price || 0,
                buyer_name: order.customer_name || '',
              },
            }).catch(e => console.warn('[Voucher email]', e))
          }
          // In-app message with voucher codes
          if (order.customer_id) {
            const codesStr = generatedCodes.join(', ')
            supabase.from('admin_messages').insert({
              user_id: order.customer_id,
              title: 'Dárkový poukaz — potvrzení',
              message: 'Děkujeme za nákup! Vaše kódy: ' + codesStr + '. Kód můžete ihned uplatnit při rezervaci motorky.',
              type: 'info',
              read: false,
            }).then(() => {}).catch(() => {})
          }
        }

        // Generate final invoice with voucher codes
        supabase.functions.invoke('generate-invoice', {
          body: {
            type: 'shop_final',
            order_id: order.id,
            ...(generatedCodes.length > 0 ? { voucher_codes: generatedCodes } : {}),
          }
        }).catch(e => console.warn('[Auto final invoice]', e))
      }
      load()
    } catch (e) { console.error('[AutoConfirmVoucher]', e) }
  }

  async function load() {
    setLoading(true)
    let q = supabase
      .from('shop_orders')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })

    if (statusFilter !== 'all') q = q.eq('status', statusFilter)
    if (search.trim()) {
      q = q.or(`order_number.ilike.%${search.trim()}%,customer_name.ilike.%${search.trim()}%,customer_email.ilike.%${search.trim()}%`)
    }

    const { data, count } = await q.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    setOrders(data || [])
    setTotal(count || 0)
    setLoading(false)
  }

  useEffect(() => {
    const t = setTimeout(() => { setPage(1); load() }, 300)
    return () => clearTimeout(t)
  }, [search])

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => n != null ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'
  const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={search} onChange={setSearch} placeholder="Hledat objednávku…" />
        <div className="flex items-center gap-1">
          {['all', 'new', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'].map(s => (
            <button key={s} onClick={() => { setStatusFilter(s); setPage(1) }}
              className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer border-none"
              style={{
                padding: '5px 12px',
                background: statusFilter === s ? '#1a2e22' : '#f1faf7',
                color: statusFilter === s ? '#74FB71' : '#4a6357',
              }}>
              {s === 'all' ? 'Vše' : STATUS_LABELS[s] || s}
            </button>
          ))}
        </div>
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
                <TH>Číslo</TH><TH>Zákazník</TH><TH>Datum</TH><TH>Celkem</TH><TH>Platba</TH><TH>Stav</TH>
              </TRow>
            </thead>
            <tbody>
              {orders.map(o => {
                const sc = STATUS_COLORS[o.status] || { bg: '#f3f4f6', color: '#6b7280' }
                const pc = PAYMENT_COLORS[o.payment_status] || { bg: '#f3f4f6', color: '#6b7280' }
                return (
                  <tr key={o.id} onClick={() => setDetail(o)} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
                    <TD mono bold>{o.order_number}</TD>
                    <TD>{o.customer_name || o.customer_email || '—'}</TD>
                    <TD>{fmtDate(o.created_at)}</TD>
                    <TD bold>{fmt(o.total)}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                        style={{ padding: '3px 8px', background: pc.bg, color: pc.color }}>
                        {PAYMENT_LABELS[o.payment_status] || o.payment_status}
                      </span>
                    </TD>
                    <TD>
                      <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                        style={{ padding: '3px 8px', background: sc.bg, color: sc.color }}>
                        {STATUS_LABELS[o.status] || o.status}
                      </span>
                    </TD>
                  </tr>
                )
              })}
              {orders.length === 0 && <TRow><TD colSpan={6}>Žádné objednávky</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <NewShopOrderModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {detail && <ShopOrderDetail order={detail} onClose={() => setDetail(null)} onUpdated={() => { setDetail(null); load() }} />}
    </div>
  )
}

function NewShopOrderModal({ onClose, onSaved }) {
  const [form, setForm] = useState({
    customer_name: '', customer_email: '', customer_phone: '',
    shipping_address: '', billing_address: '', payment_method: '',
    notes: '',
  })
  const [items, setItems] = useState([{ product_name: '', product_sku: '', quantity: 1, unit_price: '' }])
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  function set(k, v) { setForm(f => ({ ...f, [k]: v })) }
  function addItem() { setItems(i => [...i, { product_name: '', product_sku: '', quantity: 1, unit_price: '' }]) }
  function updateItem(idx, key, val) { setItems(i => i.map((it, j) => j === idx ? { ...it, [key]: val } : it)) }
  function removeItem(idx) { setItems(i => i.filter((_, j) => j !== idx)) }

  const subtotal = items.reduce((s, it) => s + (Number(it.quantity) || 0) * (Number(it.unit_price) || 0), 0)

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const orderPayload = {
        customer_name: form.customer_name, customer_email: form.customer_email,
        customer_phone: form.customer_phone, shipping_address: form.shipping_address,
        billing_address: form.billing_address, payment_method: form.payment_method,
        notes: form.notes, subtotal, total: subtotal, status: 'new', payment_status: 'pending',
      }
      const result = await debugAction('shopOrder.create', 'NewShopOrderModal', () =>
        supabase.from('shop_orders').insert(orderPayload).select().single()
      , orderPayload)
      if (result?.error) throw result.error
      const order = result.data

      const orderItems = items.filter(it => it.product_name).map(it => ({
        order_id: order.id, product_name: it.product_name, product_sku: it.product_sku,
        quantity: Number(it.quantity), unit_price: Number(it.unit_price),
        total_price: (Number(it.quantity) || 0) * (Number(it.unit_price) || 0),
      }))
      if (orderItems.length > 0) {
        const itemsResult = await debugAction('shopOrder.createItems', 'NewShopOrderModal', () =>
          supabase.from('shop_order_items').insert(orderItems)
        , orderItems)
        if (itemsResult?.error) throw itemsResult.error
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová e-shop objednávka" onClose={onClose} wide>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Jméno zákazníka</Label><Input value={form.customer_name} onChange={v => set('customer_name', v)} /></div>
          <div><Label>Email</Label><Input value={form.customer_email} onChange={v => set('customer_email', v)} /></div>
          <div><Label>Telefon</Label><Input value={form.customer_phone} onChange={v => set('customer_phone', v)} /></div>
          <div><Label>Způsob platby</Label><Input value={form.payment_method} onChange={v => set('payment_method', v)} placeholder="Kartou / Převodem / Dobírka" /></div>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div><Label>Doručovací adresa</Label><textarea value={form.shipping_address} onChange={e => set('shipping_address', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} /></div>
          <div><Label>Fakturační adresa</Label><textarea value={form.billing_address} onChange={e => set('billing_address', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} /></div>
        </div>

        <div>
          <Label>Položky</Label>
          {items.map((it, idx) => (
            <div key={idx} className="flex items-center gap-2 mb-2">
              <input value={it.product_name} onChange={e => updateItem(idx, 'product_name', e.target.value)}
                placeholder="Název produktu" className="flex-1 rounded-btn text-sm outline-none" style={inputStyle} />
              <input value={it.product_sku} onChange={e => updateItem(idx, 'product_sku', e.target.value)}
                placeholder="SKU" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 90 }} />
              <input type="number" value={it.quantity} onChange={e => updateItem(idx, 'quantity', e.target.value)}
                placeholder="Ks" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 60 }} />
              <input type="number" value={it.unit_price} onChange={e => updateItem(idx, 'unit_price', e.target.value)}
                placeholder="Cena/ks" className="rounded-btn text-sm outline-none" style={{ ...inputStyle, width: 100 }} />
              <button onClick={() => removeItem(idx)} className="text-sm cursor-pointer bg-transparent border-none" style={{ color: '#dc2626' }}>✕</button>
            </div>
          ))}
          <div className="flex items-center gap-3">
            <button onClick={addItem} className="text-xs font-bold cursor-pointer bg-transparent border-none" style={{ color: '#1a8a18' }}>+ Přidat položku</button>
            {subtotal > 0 && <span className="text-xs font-bold ml-auto" style={{ color: '#1a2e22' }}>Celkem: {subtotal.toLocaleString('cs-CZ')} Kč</span>}
          </div>
        </div>

        <div><Label>Poznámky</Label><textarea value={form.notes} onChange={e => set('notes', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.customer_name}>{saving ? 'Ukládám…' : 'Vytvořit'}</Button>
      </div>
    </Modal>
  )
}

function ShopOrderDetail({ order, onClose, onUpdated }) {
  const [items, setItems] = useState([])
  const [vouchers, setVouchers] = useState([])
  const [loading, setLoading] = useState(true)
  const [updating, setUpdating] = useState(false)

  useEffect(() => { loadItems() }, [order.id])

  async function loadItems() {
    setLoading(true)
    const [itemsRes, vouchersRes] = await Promise.all([
      supabase.from('shop_order_items').select('*').eq('order_id', order.id).order('created_at'),
      supabase.from('vouchers').select('code, amount, status').eq('order_id', order.id),
    ])
    setItems(itemsRes.data || [])
    setVouchers(vouchersRes.data || [])
    setLoading(false)
  }

  async function updateStatus(status) {
    setUpdating(true)
    const extra = {}
    if (status === 'confirmed') extra.confirmed_at = new Date().toISOString()
    if (status === 'shipped') extra.shipped_at = new Date().toISOString()
    if (status === 'delivered') extra.delivered_at = new Date().toISOString()
    if (status === 'cancelled') extra.cancelled_at = new Date().toISOString()
    const updateData = { status, ...extra }
    const result = await debugAction('shopOrder.updateStatus', 'ShopOrderDetail', () =>
      supabase.from('shop_orders').update(updateData).eq('id', order.id)
    , updateData)
    if (result?.error) throw result.error

    // Generate final invoice when order is confirmed (delivered for digital, confirmed for physical)
    if (status === 'confirmed' || status === 'delivered') {
      supabase.functions.invoke('generate-invoice', {
        body: { type: 'shop_final', order_id: order.id }
      }).catch(e => console.warn('[Final invoice]', e))
    }

    setUpdating(false)
    onUpdated()
  }

  async function updatePayment(payment_status) {
    setUpdating(true)
    try {
      const result = await debugAction('shopOrder.updatePayment', 'ShopOrderDetail', () =>
        supabase.from('shop_orders').update({ payment_status }).eq('id', order.id)
      , { payment_status })
      if (result?.error) throw result.error

      // When marking as paid, directly run voucher generation + auto-confirm
      if (payment_status === 'paid' && order.status === 'new') {
        await processVoucherOrder(order)
      }
    } catch (e) {
      console.error('[updatePayment]', e)
    }
    setUpdating(false)
    onUpdated()
  }

  async function processVoucherOrder(ord) {
    try {
      // Guard: check if vouchers already exist for this order (avoid duplicates)
      const { data: existingVouchers } = await supabase
        .from('vouchers').select('code').eq('order_id', ord.id)
      if (existingVouchers && existingVouchers.length > 0) {
        console.log('[processVoucherOrder] Vouchers already exist for order', ord.id)
        return
      }

      // Re-check order status from DB (avoid race with autoConfirmPaidVouchers)
      const { data: freshOrder } = await supabase
        .from('shop_orders').select('status, payment_status').eq('id', ord.id).single()
      if (freshOrder && freshOrder.status !== 'new') {
        console.log('[processVoucherOrder] Order already processed, status:', freshOrder.status)
        return
      }

      // Load items for this order
      const { data: orderItems } = await supabase
        .from('shop_order_items')
        .select('*')
        .eq('order_id', ord.id)
      const allItems = orderItems || []
      const voucherItems = allItems.filter(it =>
        (it.product_name || '').toLowerCase().includes('voucher') ||
        (it.product_name || '').toLowerCase().includes('poukaz')
      )
      const isAllVouchers = voucherItems.length === allItems.length && allItems.length > 0

      // All vouchers (digital or physical) → delivered (codes sent electronically)
      // Mixed (vouchers + physical products) → confirmed (vouchers sent, physical processed separately)
      const newStatus = isAllVouchers ? 'delivered' : 'confirmed'
      await supabase.from('shop_orders').update({
        status: newStatus,
        confirmed_at: new Date().toISOString(),
        ...(isAllVouchers ? { delivered_at: new Date().toISOString() } : {}),
      }).eq('id', ord.id)

      // Generate voucher codes
      const generatedCodes = []
      if (voucherItems.length > 0) {
        for (const item of voucherItems) {
          const code = 'MG' + Math.random().toString(36).substring(2, 8).toUpperCase()
          generatedCodes.push(code)
          const validUntil = new Date()
          validUntil.setFullYear(validUntil.getFullYear() + 1)
          await supabase.from('vouchers').insert({
            code,
            amount: item.unit_price || item.total_price || 0,
            currency: 'CZK',
            status: 'active',
            buyer_id: ord.customer_id || null,
            buyer_name: ord.customer_name || '',
            buyer_email: ord.customer_email || '',
            valid_from: new Date().toISOString().split('T')[0],
            valid_until: validUntil.toISOString().split('T')[0],
            source: 'eshop',
            order_id: ord.id,
          })
          // Send voucher email
          supabase.functions.invoke('send-booking-email', {
            body: {
              type: 'voucher_purchased',
              to: ord.customer_email,
              voucher_code: code,
              voucher_amount: item.unit_price || item.total_price || 0,
              buyer_name: ord.customer_name || '',
            },
          }).catch(e => console.warn('[Voucher email]', e))
        }
        // In-app message with voucher codes
        if (ord.customer_id) {
          const codesStr = generatedCodes.join(', ')
          supabase.from('admin_messages').insert({
            user_id: ord.customer_id,
            title: 'Dárkový poukaz — potvrzení',
            message: 'Děkujeme za nákup! Vaše kódy: ' + codesStr + '. Kód můžete ihned uplatnit při rezervaci motorky.',
            type: 'info',
            read: false,
          }).then(() => {}).catch(() => {})
        }
      }

      // Generate final invoice with voucher codes
      await supabase.functions.invoke('generate-invoice', {
        body: {
          type: 'shop_final',
          order_id: ord.id,
          ...(generatedCodes.length > 0 ? { voucher_codes: generatedCodes } : {}),
        }
      }).catch(e => console.warn('[Auto final invoice]', e))
    } catch (e) { console.error('[processVoucherOrder]', e) }
  }

  const fmt = n => n != null ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'
  const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
  const sc = STATUS_COLORS[order.status] || { bg: '#f3f4f6', color: '#6b7280' }
  const pc = PAYMENT_COLORS[order.payment_status] || { bg: '#f3f4f6', color: '#6b7280' }

  const NEXT_STATUS = {
    new: 'confirmed', confirmed: 'processing', processing: 'shipped', shipped: 'delivered',
  }
  const nextStatus = NEXT_STATUS[order.status]

  return (
    <Modal open title={`Objednávka ${order.order_number}`} onClose={onClose} wide>
      <div className="grid grid-cols-2 gap-4 mb-4">
        <div>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Zákazník</div>
          <div className="text-sm font-bold" style={{ color: '#0f1a14' }}>{order.customer_name || '—'}</div>
          <div className="text-xs" style={{ color: '#4a6357' }}>{order.customer_email}</div>
          <div className="text-xs" style={{ color: '#4a6357' }}>{order.customer_phone}</div>
        </div>
        <div>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Stav</div>
          <div className="flex items-center gap-2 flex-wrap">
            <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
              style={{ padding: '4px 10px', background: sc.bg, color: sc.color }}>
              {STATUS_LABELS[order.status] || order.status}
            </span>
            <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
              style={{ padding: '4px 10px', background: pc.bg, color: pc.color }}>
              {PAYMENT_LABELS[order.payment_status] || order.payment_status}
            </span>
          </div>
          <div className="text-xs mt-1" style={{ color: '#4a6357' }}>
            Vytvořeno: {fmtDate(order.created_at)}
            {order.shipped_at && <> · Odesláno: {fmtDate(order.shipped_at)}</>}
            {order.delivered_at && <> · Doručeno: {fmtDate(order.delivered_at)}</>}
          </div>
        </div>
      </div>

      {order.shipping_address && (
        <div className="mb-3">
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Doručovací adresa</div>
          <div className="text-xs" style={{ color: '#0f1a14' }}>{order.shipping_address}</div>
        </div>
      )}

      {order.tracking_number && (
        <div className="mb-3">
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Sledovací číslo</div>
          <div className="text-sm font-mono font-bold" style={{ color: '#0f1a14' }}>{order.tracking_number}</div>
        </div>
      )}

      {vouchers.length > 0 && (
        <div className="mb-3 p-3 rounded-btn" style={{ background: '#dcfce7', border: '1px solid #86efac' }}>
          <div className="text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#166534' }}>Kódy poukazů</div>
          <div className="flex flex-wrap gap-2">
            {vouchers.map(v => (
              <span key={v.code} className="inline-block rounded-btn font-mono text-xs font-bold"
                style={{ padding: '4px 10px', background: '#fff', color: '#166534', border: '1px solid #86efac' }}>
                {v.code} ({Number(v.amount).toLocaleString('cs-CZ')} Kč)
              </span>
            ))}
          </div>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : (
        <Table>
          <thead><TRow header><TH>Produkt</TH><TH>SKU</TH><TH>Množství</TH><TH>Cena/ks</TH><TH>Celkem</TH></TRow></thead>
          <tbody>
            {items.map(it => (
              <TRow key={it.id}>
                <TD bold>{it.product_name}</TD>
                <TD mono>{it.product_sku || '—'}</TD>
                <TD>{it.quantity}</TD>
                <TD>{fmt(it.unit_price)}</TD>
                <TD bold>{fmt(it.total_price)}</TD>
              </TRow>
            ))}
            {items.length === 0 && <TRow><TD colSpan={5}>Žádné položky</TD></TRow>}
            <TRow>
              <TD /><TD /><TD /><TD bold>Mezisoučet:</TD><TD bold>{fmt(order.subtotal)}</TD>
            </TRow>
            {Number(order.shipping_cost) > 0 && (
              <TRow><TD /><TD /><TD /><TD>Doprava:</TD><TD>{fmt(order.shipping_cost)}</TD></TRow>
            )}
            {Number(order.discount) > 0 && (
              <TRow><TD /><TD /><TD /><TD>Sleva:</TD><TD style={{ color: '#dc2626' }}>-{fmt(order.discount)}</TD></TRow>
            )}
            <TRow>
              <TD /><TD /><TD />
              <TD bold style={{ fontSize: 14 }}>Celkem:</TD>
              <TD bold style={{ fontSize: 14 }}>{fmt(order.total)}</TD>
            </TRow>
          </tbody>
        </Table>
      )}

      {order.notes && (
        <div className="mt-3 p-3 rounded-btn text-xs" style={{ background: '#f1faf7', color: '#4a6357' }}>
          <strong>Poznámky:</strong> {order.notes}
        </div>
      )}

      <div className="flex justify-end gap-2 mt-5 flex-wrap">
        {order.payment_status === 'pending' && (
          <Button onClick={() => updatePayment('paid')} disabled={updating}>Zaplaceno</Button>
        )}
        {order.status !== 'cancelled' && order.status !== 'delivered' && order.status !== 'refunded' && (
          <Button onClick={() => updateStatus('cancelled')} disabled={updating}>Zrušit</Button>
        )}
        {order.status === 'confirmed' && items.some(it =>
          ((it.product_name || '').toLowerCase().includes('voucher') || (it.product_name || '').toLowerCase().includes('poukaz')) &&
          (it.product_name || '').toLowerCase().includes('fyzick')
        ) && (
          <Button green onClick={() => updateStatus('shipped')} disabled={updating}>Odesláno (fyzický poukaz)</Button>
        )}
        {nextStatus && (
          <Button green onClick={() => updateStatus(nextStatus)} disabled={updating}>
            {STATUS_LABELS[nextStatus]}
          </Button>
        )}
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
function Input({ value, onChange, placeholder }) {
  return <input value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder}
    className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
}
