import { useState, useEffect } from 'react'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'
import { exportToCsv, bulkUpdate, bulkDelete } from '../../lib/bulkActions'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Pagination from '../../components/ui/Pagination'
import Badge from '../../components/ui/Badge'
import QuickOrderModal from './QuickOrderModal'
import RuleModal from './RuleModal'
import OrderDetailModal from './OrderDetailModal'

const PER_PAGE = 25
const STATUS_LABELS = { draft: 'Koncept', sent: 'Odeslano', received: 'Prijato', cancelled: 'Zruseno' }
const TRIGGER_LABELS = { stock_low: 'Nizky sklad', interval: 'Pravidelny interval', manual: 'Jednorazova' }
const TRIGGER_COLORS = { stock_low: '#dc2626', interval: '#2563eb', manual: '#b45309' }
const TRIGGER_BGS = { stock_low: '#fee2e2', interval: '#dbeafe', manual: '#fef3c7' }

export default function AutoOrdersTab() {
  const debugMode = useDebugMode()
  const [tab, setTab] = useState('orders')
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
  const [selOrderIds, setSelOrderIds] = useState(new Set())
  const [selRuleIds, setSelRuleIds] = useState(new Set())

  useEffect(() => { load() }, [tab, page])

  async function load() {
    setLoading(true); setError(null)
    try {
      if (tab === 'orders') {
        const { data, count, error: err } = await supabase.from('purchase_orders').select('*, suppliers(name, contact_email)', { count: 'exact' }).order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
        if (err) throw err; setOrders(data || []); setTotal(count || 0)
      } else {
        const { data, error: err } = await supabase.from('auto_order_rules').select('*, suppliers(name, contact_email), inventory(name, sku, stock, min_stock)').order('created_at', { ascending: false })
        if (err) throw err; setRules(data || [])
      }
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  async function sendOrderEmail(order) {
    setResultMsg(null)
    try {
      const { data: items } = await supabase.from('purchase_order_items').select('*, inventory(name, sku)').eq('order_id', order.id)
      const emailItems = (items || []).map(it => ({ name: it.inventory?.name || 'Neznama polozka', sku: it.inventory?.sku || '', quantity: it.quantity, unit_price: it.unit_price }))
      const supplierEmail = order.suppliers?.contact_email
      if (!supplierEmail) { setError('Dodavatel nema vyplneny email.'); return }
      const result = await debugAction('order.sendEmail', 'AutoOrdersTab', () =>
        supabase.functions.invoke('send-order-email', { body: { supplier_email: supplierEmail, supplier_name: order.suppliers?.name, items: emailItems, notes: order.notes, order_id: order.id, order_number: order.order_number || `#${order.id?.slice(0, 8)}` } })
      , { order_id: order.id })
      if (result?.error) throw result.error
      setResultMsg(`Email odeslan na ${supplierEmail}`); load()
    } catch (e) { setError('Chyba pri odesilani: ' + e.message) }
  }

  async function deleteRule(id) { if (!confirm('Opravdu smazat toto pravidlo?')) return; await supabase.from('auto_order_rules').delete().eq('id', id); load() }
  async function toggleRule(rule) { await supabase.from('auto_order_rules').update({ is_active: !rule.is_active }).eq('id', rule.id); load() }

  async function runRuleNow(rule) {
    setResultMsg(null); setError(null)
    try {
      const { data: inv } = await supabase.from('inventory').select('*').eq('id', rule.inventory_item_id).single()
      const { data: sup } = await supabase.from('suppliers').select('*').eq('id', rule.supplier_id).single()
      if (!sup?.contact_email) { setError('Dodavatel nema vyplneny email.'); return }
      const qty = rule.order_quantity || (inv ? inv.min_stock * 2 - inv.stock : 10)
      const orderPayload = { supplier_id: rule.supplier_id, notes: rule.notes || `Auto-objednavka: ${inv?.name || 'polozka'}`, status: 'draft', total_amount: qty * (inv?.unit_price || 0) }
      const { data: order, error: oErr } = await supabase.from('purchase_orders').insert(orderPayload).select().single()
      if (oErr) throw oErr
      await supabase.from('purchase_order_items').insert({ order_id: order.id, item_id: rule.inventory_item_id, quantity: qty, unit_price: inv?.unit_price || 0 })
      const result = await supabase.functions.invoke('send-order-email', { body: { supplier_email: sup.contact_email, supplier_name: sup.name, items: [{ name: inv?.name || '', sku: inv?.sku || '', quantity: qty, unit_price: inv?.unit_price || 0 }], notes: orderPayload.notes, order_id: order.id } })
      if (result?.error) throw result.error
      await supabase.from('auto_order_rules').update({ last_triggered_at: new Date().toISOString() }).eq('id', rule.id)
      setResultMsg(`Objednavka vytvorena a email odeslan na ${sup.contact_email}`); load()
    } catch (e) { setError('Chyba: ' + e.message) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => n ? `${Number(n).toLocaleString('cs-CZ')} Kc` : '\u2014'

  return (
    <div>
      <div className="flex gap-2 mb-4">
        <button onClick={() => { setTab('orders'); setPage(1) }} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '6px 14px', background: tab === 'orders' ? '#1a2e22' : '#f1faf7', color: tab === 'orders' ? '#74FB71' : '#1a2e22', border: 'none', boxShadow: tab === 'orders' ? '0 2px 8px rgba(26,46,34,.25)' : 'none' }}>Objednavky</button>
        <button onClick={() => { setTab('rules'); setPage(1) }} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '6px 14px', background: tab === 'rules' ? '#1a2e22' : '#f1faf7', color: tab === 'rules' ? '#74FB71' : '#1a2e22', border: 'none', boxShadow: tab === 'rules' ? '0 2px 8px rgba(26,46,34,.25)' : 'none' }}>Automaticka pravidla</button>
      </div>

      {resultMsg && <div className="mb-3 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{resultMsg}</div>}
      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {debugMode && <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}><strong>DIAGNOSTIKA AutoOrders</strong><br/><div>tab: {tab} | orders: {orders.length} | rules: {rules.length}</div></div>}

      {tab === 'orders' && (
        <>
          <div className="flex items-center gap-3 mb-4"><div className="ml-auto"><Button green onClick={() => setShowNewOrder(true)}>+ Nova objednavka</Button></div></div>
          {loading ? <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div> : (
            <>
              <BulkActionsBar count={selOrderIds.size} onClear={() => setSelOrderIds(new Set())} actions={[
                { label: 'Označit odeslané', icon: '📤', onClick: async () => { await bulkUpdate('purchase_orders', [...selOrderIds], { status: 'sent', sent_at: new Date().toISOString() }, 'auto_orders_bulk_sent'); setSelOrderIds(new Set()); load() } },
                { label: 'Označit přijaté', icon: '✓', onClick: async () => { await bulkUpdate('purchase_orders', [...selOrderIds], { status: 'received' }, 'auto_orders_bulk_received'); setSelOrderIds(new Set()); load() } },
                { label: 'Zrušit', icon: '✗', onClick: async () => { await bulkUpdate('purchase_orders', [...selOrderIds], { status: 'cancelled' }, 'auto_orders_bulk_cancelled'); setSelOrderIds(new Set()); load() }, confirm: 'Zrušit {count} objednávek?' },
                { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('auto-orders', [
                  { key: 'order_number', label: 'Číslo' },
                  { key: 'suppliers', label: 'Dodavatel', format: (_, r) => r.suppliers?.name || '' },
                  { key: 'created_at', label: 'Datum' }, { key: 'total_amount', label: 'Celkem' }, { key: 'status', label: 'Stav' },
                ], orders.filter(o => selOrderIds.has(o.id))) },
                { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} objednávek?', onClick: async () => { await bulkDelete('purchase_orders', [...selOrderIds], 'auto_orders_bulk_deleted'); setSelOrderIds(new Set()); load() } },
              ]} />
              <Table>
                <thead><TRow header>
                  <TH><SelectAllCheckbox items={orders} selectedIds={selOrderIds} setSelectedIds={setSelOrderIds} /></TH>
                  <TH>Cislo</TH><TH>Dodavatel</TH><TH>Email</TH><TH>Datum</TH><TH>Celkem</TH><TH>Stav</TH><TH>Akce</TH>
                </TRow></thead>
                <tbody>
                  {orders.map(o => (
                    <tr key={o.id} className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                      style={{ borderBottom: '1px solid #d4e8e0', background: selOrderIds.has(o.id) ? '#fef9c3' : undefined }}>
                      <TD><RowCheckbox id={o.id} selectedIds={selOrderIds} setSelectedIds={setSelOrderIds} /></TD>
                      <TD mono bold onClick={() => setDetail(o)}>{o.order_number || `#${o.id?.slice(0, 8)}`}</TD>
                      <TD onClick={() => setDetail(o)}>{o.suppliers?.name || '\u2014'}</TD>
                      <TD onClick={() => setDetail(o)}><span style={{ fontSize: 12, color: '#6b7280' }}>{o.suppliers?.contact_email || '\u2014'}</span></TD>
                      <TD onClick={() => setDetail(o)}>{o.created_at ? new Date(o.created_at).toLocaleDateString('cs-CZ') : '\u2014'}</TD>
                      <TD bold onClick={() => setDetail(o)}>{fmt(o.total_amount)}</TD>
                      <TD onClick={() => setDetail(o)}>
                        <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{ padding: '4px 10px', background: o.status === 'received' ? '#dcfce7' : o.status === 'sent' ? '#dbeafe' : o.status === 'cancelled' ? '#fee2e2' : '#fef3c7', color: o.status === 'received' ? '#1a8a18' : o.status === 'sent' ? '#2563eb' : o.status === 'cancelled' ? '#dc2626' : '#b45309' }}>{STATUS_LABELS[o.status] || o.status}</span>
                      </TD>
                      <TD>{(o.status === 'draft' || o.status === 'sent') && <button onClick={() => sendOrderEmail(o)} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '4px 10px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>{o.status === 'draft' ? 'Odeslat email' : 'Preposlat'}</button>}</TD>
                    </tr>
                  ))}
                  {orders.length === 0 && <TRow><TD>Zadne objednavky</TD></TRow>}
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
            <p className="text-sm" style={{ color: '#6b7280' }}>Pravidla automaticky vytvareji objednavky a posilaji emaily dodavatelum.</p>
            <div className="ml-auto"><Button green onClick={() => setShowNewRule(true)}>+ Nove pravidlo</Button></div>
          </div>
          {loading ? <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div> : (
            <>
            <BulkActionsBar count={selRuleIds.size} onClear={() => setSelRuleIds(new Set())} actions={[
              { label: 'Aktivovat', icon: '✓', onClick: async () => { await bulkUpdate('auto_order_rules', [...selRuleIds], { is_active: true }, 'auto_rules_bulk_activated'); setSelRuleIds(new Set()); load() } },
              { label: 'Deaktivovat', icon: '⏸', onClick: async () => { await bulkUpdate('auto_order_rules', [...selRuleIds], { is_active: false }, 'auto_rules_bulk_deactivated'); setSelRuleIds(new Set()); load() } },
              { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} pravidel?', onClick: async () => { await bulkDelete('auto_order_rules', [...selRuleIds], 'auto_rules_bulk_deleted'); setSelRuleIds(new Set()); load() } },
            ]} />
            <Table>
              <thead><TRow header>
                <TH><SelectAllCheckbox items={rules} selectedIds={selRuleIds} setSelectedIds={setSelRuleIds} /></TH>
                <TH>Polozka</TH><TH>Dodavatel</TH><TH>Typ</TH><TH>Mnozstvi</TH><TH>Stav</TH><TH>Posledni spusteni</TH><TH>Akce</TH>
              </TRow></thead>
              <tbody>
                {rules.map(r => (
                  <TRow key={r.id}>
                    <TD><RowCheckbox id={r.id} selectedIds={selRuleIds} setSelectedIds={setSelRuleIds} /></TD>
                    <TD bold>{r.inventory?.name || '\u2014'} <span style={{ color: '#6b7280', fontSize: 11 }}>({r.inventory?.sku || ''})</span></TD>
                    <TD>{r.suppliers?.name || '\u2014'}</TD>
                    <TD><Badge label={TRIGGER_LABELS[r.trigger_type] || r.trigger_type} color={TRIGGER_COLORS[r.trigger_type] || '#6b7280'} bg={TRIGGER_BGS[r.trigger_type] || '#f3f4f6'} />{r.trigger_type === 'stock_low' && <span style={{ fontSize: 11, color: '#6b7280', marginLeft: 4 }}>{'\u2264'}{r.threshold_quantity}</span>}{r.trigger_type === 'interval' && <span style={{ fontSize: 11, color: '#6b7280', marginLeft: 4 }}>/{r.interval_days}d</span>}</TD>
                    <TD bold>{r.order_quantity || '\u2014'} ks</TD>
                    <TD><span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer" onClick={() => toggleRule(r)} style={{ padding: '4px 10px', background: r.is_active ? '#dcfce7' : '#f3f4f6', color: r.is_active ? '#1a8a18' : '#6b7280' }}>{r.is_active ? 'Aktivni' : 'Neaktivni'}</span></TD>
                    <TD>{r.last_triggered_at ? new Date(r.last_triggered_at).toLocaleString('cs-CZ') : '\u2014'}</TD>
                    <TD><div className="flex gap-1">
                      <button onClick={() => runRuleNow(r)} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '4px 8px', background: '#dcfce7', color: '#1a8a18', border: 'none' }}>Spustit</button>
                      <button onClick={() => setEditRule(r)} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '4px 8px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Upravit</button>
                      <button onClick={() => deleteRule(r.id)} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '4px 8px', background: '#fee2e2', color: '#dc2626', border: 'none' }}>Smazat</button>
                    </div></TD>
                  </TRow>
                ))}
                {rules.length === 0 && <TRow><TD>Zadna pravidla — pridejte prvni automatickou objednavku</TD></TRow>}
              </tbody>
            </Table>
            </>
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
