import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'
import Badge from '../../components/ui/Badge'

const PER_PAGE = 25
const STATUS_LABELS = { draft: 'Koncept', sent: 'Odesláno', received: 'Přijato', cancelled: 'Zrušeno' }

export default function AutoOrdersTab() {
  const debugMode = useDebugMode()
  const [tab, setTab] = useState('orders') // orders | rules
  const [orders, setOrders] = useState([])
  const [rules, setRules] = useState([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showNewOrder, setShowNewOrder] = useState(false)
  const [showNewRule, setShowNewRule] = useState(false)
  const [detail, setDetail] = useState(null)
  const [editRule, setEditRule] = useState(null)
  const [error, setError] = useState(null)
  const [resultMsg, setResultMsg] = useState(null)

  useEffect(() => { load() }, [tab, page])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      if (tab === 'orders') {
        const { data, count, error: err } = await supabase
          .from('purchase_orders')
          .select('*, suppliers(name, contact_email)', { count: 'exact' })
          .order('created_at', { ascending: false })
          .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        if (err) throw err
        setOrders(data || [])
        setTotal(count || 0)
      } else {
        const { data, error: err } = await supabase
          .from('auto_order_rules')
          .select('*, suppliers(name, contact_email), inventory(name, sku, stock, min_stock)')
          .order('created_at', { ascending: false })
        if (err) throw err
        setRules(data || [])
      }
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function sendOrderEmail(order) {
    setResultMsg(null)
    try {
      // Load order items
      const { data: items } = await supabase
        .from('purchase_order_items')
        .select('*, inventory(name, sku)')
        .eq('order_id', order.id)

      const emailItems = (items || []).map(it => ({
        name: it.inventory?.name || 'Neznámá položka',
        sku: it.inventory?.sku || '',
        quantity: it.quantity,
        unit_price: it.unit_price,
      }))

      const supplierEmail = order.suppliers?.contact_email
      if (!supplierEmail) {
        setError('Dodavatel nemá vyplněný email. Nastavte contact_email u dodavatele.')
        return
      }

      const result = await debugAction('order.sendEmail', 'AutoOrdersTab', () =>
        supabase.functions.invoke('send-order-email', {
          body: {
            supplier_email: supplierEmail,
            supplier_name: order.suppliers?.name,
            items: emailItems,
            notes: order.notes,
            order_id: order.id,
            order_number: order.order_number || `#${order.id?.slice(0, 8)}`,
          }
        })
      , { order_id: order.id })

      if (result?.error) throw result.error
      setResultMsg(`Email odeslán na ${supplierEmail}`)
      load()
    } catch (e) {
      setError('Chyba při odesílání: ' + e.message)
    }
  }

  async function deleteRule(id) {
    if (!confirm('Opravdu smazat toto pravidlo?')) return
    await supabase.from('auto_order_rules').delete().eq('id', id)
    load()
  }

  async function toggleRule(rule) {
    await supabase.from('auto_order_rules').update({ is_active: !rule.is_active }).eq('id', rule.id)
    load()
  }

  async function runRuleNow(rule) {
    setResultMsg(null)
    setError(null)
    try {
      // Create purchase order from rule
      const { data: inv } = await supabase.from('inventory').select('*').eq('id', rule.inventory_item_id).single()
      const { data: sup } = await supabase.from('suppliers').select('*').eq('id', rule.supplier_id).single()

      if (!sup?.contact_email) {
        setError('Dodavatel nemá vyplněný email.')
        return
      }

      const qty = rule.order_quantity || (inv ? inv.min_stock * 2 - inv.stock : 10)
      const orderPayload = {
        supplier_id: rule.supplier_id,
        notes: rule.notes || `Auto-objednávka: ${inv?.name || 'položka'}`,
        status: 'draft',
        total_amount: qty * (inv?.unit_price || 0),
      }
      const { data: order, error: oErr } = await supabase.from('purchase_orders').insert(orderPayload).select().single()
      if (oErr) throw oErr

      await supabase.from('purchase_order_items').insert({
        order_id: order.id,
        item_id: rule.inventory_item_id,
        quantity: qty,
        unit_price: inv?.unit_price || 0,
      })

      // Send email immediately
      const result = await supabase.functions.invoke('send-order-email', {
        body: {
          supplier_email: sup.contact_email,
          supplier_name: sup.name,
          items: [{ name: inv?.name || '', sku: inv?.sku || '', quantity: qty, unit_price: inv?.unit_price || 0 }],
          notes: orderPayload.notes,
          order_id: order.id,
        }
      })
      if (result?.error) throw result.error

      // Update last_triggered
      await supabase.from('auto_order_rules').update({ last_triggered_at: new Date().toISOString() }).eq('id', rule.id)

      setResultMsg(`Objednávka vytvořena a email odeslán na ${sup.contact_email}`)
      load()
    } catch (e) {
      setError('Chyba: ' + e.message)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => n ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'
  const TRIGGER_LABELS = { stock_low: 'Nízký sklad', interval: 'Pravidelný interval', manual: 'Jednorázová' }
  const TRIGGER_COLORS = { stock_low: '#dc2626', interval: '#2563eb', manual: '#b45309' }
  const TRIGGER_BGS = { stock_low: '#fee2e2', interval: '#dbeafe', manual: '#fef3c7' }

  return (
    <div>
      {/* Sub-tabs: Orders | Auto-rules */}
      <div className="flex gap-2 mb-4">
        <button onClick={() => { setTab('orders'); setPage(1) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '6px 14px', background: tab === 'orders' ? '#1a2e22' : '#f1faf7', color: tab === 'orders' ? '#74FB71' : '#1a2e22', border: 'none', boxShadow: tab === 'orders' ? '0 2px 8px rgba(26,46,34,.25)' : 'none' }}>
          Objednávky
        </button>
        <button onClick={() => { setTab('rules'); setPage(1) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '6px 14px', background: tab === 'rules' ? '#1a2e22' : '#f1faf7', color: tab === 'rules' ? '#74FB71' : '#1a2e22', border: 'none', boxShadow: tab === 'rules' ? '0 2px 8px rgba(26,46,34,.25)' : 'none' }}>
          Automatická pravidla
        </button>
      </div>

      {resultMsg && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}
      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA AutoOrders</strong><br/>
          <div>tab: {tab} | orders: {orders.length} | rules: {rules.length}</div>
        </div>
      )}

      {tab === 'orders' && (
        <>
          <div className="flex items-center gap-3 mb-4">
            <div className="ml-auto">
              <Button green onClick={() => setShowNewOrder(true)}>+ Nová objednávka</Button>
            </div>
          </div>
          {loading ? <Spinner /> : (
            <>
              <Table>
                <thead>
                  <TRow header>
                    <TH>Číslo</TH><TH>Dodavatel</TH><TH>Email</TH><TH>Datum</TH><TH>Celkem</TH><TH>Stav</TH><TH>Akce</TH>
                  </TRow>
                </thead>
                <tbody>
                  {orders.map(o => (
                    <tr key={o.id} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: '1px solid #d4e8e0' }}>
                      <TD mono bold onClick={() => setDetail(o)}>{o.order_number || `#${o.id?.slice(0, 8)}`}</TD>
                      <TD onClick={() => setDetail(o)}>{o.suppliers?.name || '—'}</TD>
                      <TD onClick={() => setDetail(o)}><span style={{ fontSize: 12, color: '#6b7280' }}>{o.suppliers?.contact_email || '—'}</span></TD>
                      <TD onClick={() => setDetail(o)}>{o.created_at ? new Date(o.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD bold onClick={() => setDetail(o)}>{fmt(o.total_amount)}</TD>
                      <TD onClick={() => setDetail(o)}>
                        <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{
                          padding: '4px 10px',
                          background: o.status === 'received' ? '#dcfce7' : o.status === 'sent' ? '#dbeafe' : o.status === 'cancelled' ? '#fee2e2' : '#fef3c7',
                          color: o.status === 'received' ? '#1a8a18' : o.status === 'sent' ? '#2563eb' : o.status === 'cancelled' ? '#dc2626' : '#b45309',
                        }}>
                          {STATUS_LABELS[o.status] || o.status}
                        </span>
                      </TD>
                      <TD>
                        {(o.status === 'draft' || o.status === 'sent') && (
                          <button onClick={() => sendOrderEmail(o)}
                            className="rounded-btn text-sm font-bold cursor-pointer"
                            style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                            {o.status === 'draft' ? 'Odeslat email' : 'Přeposlat'}
                          </button>
                        )}
                      </TD>
                    </tr>
                  ))}
                  {orders.length === 0 && <TRow><TD>Žádné objednávky</TD></TRow>}
                </tbody>
              </Table>
              <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
            </>
          )}
        </>
      )}

      {tab === 'rules' && (
        <>
          <div className="flex items-center gap-3 mb-4">
            <p className="text-sm" style={{ color: '#6b7280' }}>
              Pravidla automaticky vytvářejí objednávky a posílají emaily dodavatelům.
            </p>
            <div className="ml-auto">
              <Button green onClick={() => setShowNewRule(true)}>+ Nové pravidlo</Button>
            </div>
          </div>
          {loading ? <Spinner /> : (
            <Table>
              <thead>
                <TRow header>
                  <TH>Položka</TH><TH>Dodavatel</TH><TH>Typ</TH><TH>Množství</TH><TH>Stav</TH><TH>Poslední spuštění</TH><TH>Akce</TH>
                </TRow>
              </thead>
              <tbody>
                {rules.map(r => (
                  <TRow key={r.id}>
                    <TD bold>{r.inventory?.name || '—'} <span style={{ color: '#6b7280', fontSize: 11 }}>({r.inventory?.sku || ''})</span></TD>
                    <TD>{r.suppliers?.name || '—'}</TD>
                    <TD>
                      <Badge label={TRIGGER_LABELS[r.trigger_type] || r.trigger_type} color={TRIGGER_COLORS[r.trigger_type] || '#6b7280'} bg={TRIGGER_BGS[r.trigger_type] || '#f3f4f6'} />
                      {r.trigger_type === 'stock_low' && <span style={{ fontSize: 11, color: '#6b7280', marginLeft: 4 }}>≤{r.threshold_quantity}</span>}
                      {r.trigger_type === 'interval' && <span style={{ fontSize: 11, color: '#6b7280', marginLeft: 4 }}>/{r.interval_days}d</span>}
                    </TD>
                    <TD bold>{r.order_quantity || '—'} ks</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer" onClick={() => toggleRule(r)}
                        style={{ padding: '4px 10px', background: r.is_active ? '#dcfce7' : '#f3f4f6', color: r.is_active ? '#1a8a18' : '#6b7280' }}>
                        {r.is_active ? 'Aktivní' : 'Neaktivní'}
                      </span>
                    </TD>
                    <TD>{r.last_triggered_at ? new Date(r.last_triggered_at).toLocaleString('cs-CZ') : '—'}</TD>
                    <TD>
                      <div className="flex gap-1">
                        <button onClick={() => runRuleNow(r)} className="rounded-btn text-sm font-bold cursor-pointer"
                          style={{ padding: '4px 8px', background: '#dcfce7', color: '#1a8a18', border: 'none' }}>
                          Spustit
                        </button>
                        <button onClick={() => setEditRule(r)} className="rounded-btn text-sm font-bold cursor-pointer"
                          style={{ padding: '4px 8px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                          Upravit
                        </button>
                        <button onClick={() => deleteRule(r.id)} className="rounded-btn text-sm font-bold cursor-pointer"
                          style={{ padding: '4px 8px', background: '#fee2e2', color: '#dc2626', border: 'none' }}>
                          Smazat
                        </button>
                      </div>
                    </TD>
                  </TRow>
                ))}
                {rules.length === 0 && <TRow><TD>Žádná pravidla — přidejte první automatickou objednávku</TD></TRow>}
              </tbody>
            </Table>
          )}
        </>
      )}

      {showNewOrder && <QuickOrderModal onClose={() => setShowNewOrder(false)} onSaved={() => { setShowNewOrder(false); load() }} />}
      {showNewRule && <RuleModal onClose={() => setShowNewRule(false)} onSaved={() => { setShowNewRule(false); load() }} />}
      {editRule && <RuleModal rule={editRule} onClose={() => setEditRule(null)} onSaved={() => { setEditRule(null); load() }} />}
      {detail && <OrderDetailModal order={detail} onClose={() => setDetail(null)} onUpdated={() => { setDetail(null); load() }} onSendEmail={sendOrderEmail} />}
    </div>
  )
}

/* ——— Quick Order Modal (just email + items, creates & sends) ——— */
function QuickOrderModal({ onClose, onSaved }) {
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

  // Auto-fill unit_price when selecting item
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

      const orderItems = items.filter(it => it.item_id).map(it => ({
        order_id: order.id, item_id: it.item_id, quantity: Number(it.quantity), unit_price: Number(it.unit_price),
      }))
      if (orderItems.length > 0) {
        const { error: iErr } = await supabase.from('purchase_order_items').insert(orderItems)
        if (iErr) throw iErr
      }

      // Send email if requested
      if (sendEmail) {
        const email = form.email_override || selectedSupplier?.contact_email
        if (!email) throw new Error('Dodavatel nemá email a nebyl zadán žádný override email.')

        const emailItems = items.filter(it => it.item_id).map(it => {
          const inv = inventory.find(i => i.id === it.item_id)
          return { name: inv?.name || '', sku: inv?.sku || '', quantity: Number(it.quantity), unit_price: Number(it.unit_price) }
        })

        await supabase.functions.invoke('send-order-email', {
          body: {
            supplier_email: email,
            supplier_name: selectedSupplier?.name || '',
            items: emailItems,
            notes: form.notes,
            order_id: order.id,
          }
        })
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
            {suppliers.map(s => <option key={s.id} value={s.id}>{s.name} {s.contact_email ? `(${s.contact_email})` : ''}</option>)}
          </select>
        </div>

        <div>
          <Label>Email dodavatele (override)</Label>
          <input value={form.email_override} onChange={e => setForm(f => ({ ...f, email_override: e.target.value }))}
            placeholder={selectedSupplier?.contact_email || 'email@dodavatel.cz'}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          <p style={{ fontSize: 11, color: '#6b7280', marginTop: 2 }}>Ponechte prázdné pro použití emailu dodavatele.</p>
        </div>

        <div>
          <Label>Položky</Label>
          {items.map((it, idx) => (
            <div key={idx} className="flex items-center gap-2 mb-2">
              <select value={it.item_id} onChange={e => selectItem(idx, e.target.value)}
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
          <button onClick={addItem} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#1a8a18' }}>+ Přidat položku</button>
        </div>

        <div>
          <Label>Poznámky</Label>
          <textarea value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))}
            className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} />
        </div>

        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={sendEmail} onChange={e => setSendEmail(e.target.checked)}
            className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ihned odeslat objednávkový email</span>
        </label>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.supplier_id || !items.some(i => i.item_id)}>
          {saving ? 'Odesílám…' : sendEmail ? 'Vytvořit a odeslat' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

/* ——— Rule Modal (create/edit auto-order rule) ——— */
function RuleModal({ rule, onClose, onSaved }) {
  const [suppliers, setSuppliers] = useState([])
  const [inventory, setInventory] = useState([])
  const [form, setForm] = useState(rule ? {
    supplier_id: rule.supplier_id || '',
    inventory_item_id: rule.inventory_item_id || '',
    trigger_type: rule.trigger_type || 'stock_low',
    threshold_quantity: rule.threshold_quantity ?? '',
    interval_days: rule.interval_days ?? '',
    order_quantity: rule.order_quantity ?? '',
    notes: rule.notes || '',
    is_active: rule.is_active ?? true,
    email_override: rule.email_override || '',
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

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const payload = {
        supplier_id: form.supplier_id,
        inventory_item_id: form.inventory_item_id || null,
        trigger_type: form.trigger_type,
        threshold_quantity: form.trigger_type === 'stock_low' ? (Number(form.threshold_quantity) || 0) : null,
        interval_days: form.trigger_type === 'interval' ? (Number(form.interval_days) || 7) : null,
        order_quantity: Number(form.order_quantity) || 0,
        notes: form.notes,
        is_active: form.is_active,
        email_override: form.email_override || null,
      }

      if (rule) {
        const { error } = await supabase.from('auto_order_rules').update(payload).eq('id', rule.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('auto_order_rules').insert(payload)
        if (error) throw error
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  const selectedItem = inventory.find(i => i.id === form.inventory_item_id)

  return (
    <Modal open title={rule ? 'Upravit pravidlo' : 'Nové automatické pravidlo'} onClose={onClose} wide>
      <div className="space-y-3">
        <div>
          <Label>Typ triggeru</Label>
          <div className="flex gap-2">
            {[{ v: 'stock_low', l: 'Nízký sklad' }, { v: 'interval', l: 'Pravidelný interval' }, { v: 'manual', l: 'Jednorázová' }].map(t => (
              <button key={t.v} onClick={() => set('trigger_type', t.v)}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{ padding: '6px 14px', background: form.trigger_type === t.v ? '#74FB71' : '#f1faf7', color: '#1a2e22', border: 'none' }}>
                {t.l}
              </button>
            ))}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>Skladová položka</Label>
            <select value={form.inventory_item_id} onChange={e => set('inventory_item_id', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              <option value="">— Vyberte —</option>
              {inventory.map(i => <option key={i.id} value={i.id}>{i.name} ({i.sku}) — sklad: {i.stock}/{i.min_stock}</option>)}
            </select>
            {selectedItem && (
              <p style={{ fontSize: 11, color: selectedItem.stock <= selectedItem.min_stock ? '#dc2626' : '#6b7280', marginTop: 2 }}>
                Aktuální stav: {selectedItem.stock} ks (min: {selectedItem.min_stock})
              </p>
            )}
          </div>
          <div>
            <Label>Dodavatel</Label>
            <select value={form.supplier_id} onChange={e => set('supplier_id', e.target.value)}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
              <option value="">— Vyberte —</option>
              {suppliers.map(s => <option key={s.id} value={s.id}>{s.name} {s.contact_email ? `(${s.contact_email})` : ''}</option>)}
            </select>
          </div>
        </div>

        {form.trigger_type === 'stock_low' && (
          <div>
            <Label>Prahové množství (objednat, když sklad klesne pod)</Label>
            <input type="number" value={form.threshold_quantity} onChange={e => set('threshold_quantity', e.target.value)}
              placeholder={selectedItem ? String(selectedItem.min_stock) : '5'}
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
        )}

        {form.trigger_type === 'interval' && (
          <div>
            <Label>Interval (dní)</Label>
            <input type="number" value={form.interval_days} onChange={e => set('interval_days', e.target.value)}
              placeholder="7"
              className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
          </div>
        )}

        <div>
          <Label>Objednací množství (ks)</Label>
          <input type="number" value={form.order_quantity} onChange={e => set('order_quantity', e.target.value)}
            placeholder="10"
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>

        <div>
          <Label>Email dodavatele (override)</Label>
          <input value={form.email_override} onChange={e => set('email_override', e.target.value)}
            placeholder="Použije se email z profilu dodavatele"
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>

        <div>
          <Label>Poznámky</Label>
          <textarea value={form.notes} onChange={e => set('notes', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 50, resize: 'vertical' }} />
        </div>

        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={form.is_active} onChange={e => set('is_active', e.target.checked)}
            className="accent-[#1a8a18]" style={{ width: 16, height: 16 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Pravidlo aktivní</span>
        </label>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.supplier_id}>
          {saving ? 'Ukládám…' : rule ? 'Uložit' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

/* ——— Order Detail Modal ——— */
function OrderDetailModal({ order, onClose, onUpdated, onSendEmail }) {
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

  const fmt = n => n ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'
  const total = items.reduce((s, it) => s + (it.quantity || 0) * (it.unit_price || 0), 0)

  return (
    <Modal open title={`Objednávka ${order.order_number || `#${order.id?.slice(0, 8)}`}`} onClose={onClose} wide>
      <div className="mb-3 text-sm grid grid-cols-2 gap-2" style={{ color: '#1a2e22' }}>
        <div>Dodavatel: <b>{order.suppliers?.name || '—'}</b></div>
        <div>Email: <b>{order.suppliers?.contact_email || '—'}</b></div>
        <div>Stav: <b>{STATUS_LABELS[order.status] || order.status}</b></div>
        <div>Vytvořeno: <b>{order.created_at ? new Date(order.created_at).toLocaleString('cs-CZ') : '—'}</b></div>
        {order.sent_at && <div>Odesláno: <b>{new Date(order.sent_at).toLocaleString('cs-CZ')}</b></div>}
        {order.notes && <div className="col-span-2">Poznámky: <b>{order.notes}</b></div>}
      </div>
      {loading ? <Spinner /> : (
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
        {order.status === 'draft' && (
          <button onClick={() => { onClose(); onSendEmail(order) }} className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '8px 16px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
            Odeslat email
          </button>
        )}
        {order.status !== 'cancelled' && order.status !== 'received' && (
          <button onClick={markCancelled} className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '8px 16px', background: '#fee2e2', color: '#dc2626', border: 'none' }}>
            Zrušit
          </button>
        )}
        {order.status !== 'received' && order.status !== 'cancelled' && (
          <Button green onClick={markReceived}>Potvrdit přijetí</Button>
        )}
        <Button onClick={onClose}>Zavřít</Button>
      </div>
    </Modal>
  )
}

function Spinner() {
  return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
