import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { useDebugMode } from '../../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Pagination from '../../components/ui/Pagination'
import SearchInput from '../../components/ui/SearchInput'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'
import { exportToCsv, bulkUpdate, bulkDelete } from '../../lib/bulkActions'
import { NewShopOrderModal, ShopOrderDetail } from './ShopOrderModals'

const PER_PAGE = 25
const STATUS_LABELS = { new: 'Nová', confirmed: 'Potvrzeno', processing: 'Zpracovává se', shipped: 'Odesláno', delivered: 'Doručeno', cancelled: 'Zrušeno', returned: 'Vráceno', refunded: 'Refundováno' }
const STATUS_COLORS = { new: { bg: '#dbeafe', color: '#2563eb' }, confirmed: { bg: '#dcfce7', color: '#1a8a18' }, processing: { bg: '#fef3c7', color: '#b45309' }, shipped: { bg: '#e0e7ff', color: '#4338ca' }, delivered: { bg: '#dcfce7', color: '#15803d' }, cancelled: { bg: '#fee2e2', color: '#dc2626' }, returned: { bg: '#fef3c7', color: '#92400e' }, refunded: { bg: '#f3f4f6', color: '#1a2e22' } }
const STATUS_OPTIONS = [{ value: 'new', label: 'Nová' }, { value: 'confirmed', label: 'Potvrzeno' }, { value: 'processing', label: 'Zpracovává se' }, { value: 'shipped', label: 'Odesláno' }, { value: 'delivered', label: 'Doručeno' }, { value: 'cancelled', label: 'Zrušeno' }]
const PAYMENT_LABELS = { pending: 'Nezaplaceno', paid: 'Zaplaceno', refunded: 'Vráceno', failed: 'Selhalo' }
const PAYMENT_COLORS = { pending: { bg: '#fee2e2', color: '#dc2626' }, paid: { bg: '#dcfce7', color: '#1a8a18' }, refunded: { bg: '#f3f4f6', color: '#1a2e22' }, failed: { bg: '#fee2e2', color: '#dc2626' } }

export default function ShopOrdersTab() {
  const debugMode = useDebugMode()
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', statuses: [] }
  const [filters, setFilters] = useState(() => {
    try { const saved = localStorage.getItem('velin_shoporders_filters'); if (saved) return { ...defaultFilters, ...JSON.parse(saved) } } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_shoporders_filters', JSON.stringify(filters)) }, [filters])
  const [detail, setDetail] = useState(null)
  const [showAdd, setShowAdd] = useState(false)
  const [selectedIds, setSelectedIds] = useState(new Set())

  useEffect(() => { load() }, [page, filters])
  useEffect(() => {
    const channel = supabase.channel('shop-orders-changes').on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'shop_orders' }, () => { load() }).subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [])

  async function load() {
    setLoading(true)
    let q = supabase.from('shop_orders').select('*', { count: 'exact' }).order('created_at', { ascending: false })
    if (filters.statuses?.length > 0) q = q.in('status', filters.statuses)
    if (filters.search?.trim()) q = q.or(`order_number.ilike.%${filters.search.trim()}%,customer_name.ilike.%${filters.search.trim()}%,customer_email.ilike.%${filters.search.trim()}%`)
    const { data, count } = await q.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
    setOrders(data || []); setTotal(count || 0); setLoading(false)
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = n => n != null ? `${Number(n).toLocaleString('cs-CZ')} Kč` : '—'
  const fmtDate = d => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'

  const ids = [...selectedIds]
  const bulkActions = [
    { label: 'Potvrdit', icon: '✓', onClick: async () => { await bulkUpdate('shop_orders', ids, { status: 'confirmed', confirmed_at: new Date().toISOString() }, 'shop_orders_bulk_confirmed'); setSelectedIds(new Set()); load() } },
    { label: 'Odesláno', icon: '📦', onClick: async () => { await bulkUpdate('shop_orders', ids, { status: 'shipped' }, 'shop_orders_bulk_shipped'); setSelectedIds(new Set()); load() } },
    { label: 'Doručeno', icon: '✅', onClick: async () => { await bulkUpdate('shop_orders', ids, { status: 'delivered' }, 'shop_orders_bulk_delivered'); setSelectedIds(new Set()); load() } },
    { label: 'Zrušit', icon: '✗', onClick: async () => { await bulkUpdate('shop_orders', ids, { status: 'cancelled' }, 'shop_orders_bulk_cancelled'); setSelectedIds(new Set()); load() }, confirm: 'Zrušit {count} objednávek?' },
    { label: 'Označit zaplaceno', icon: '💰', onClick: async () => { await bulkUpdate('shop_orders', ids, { payment_status: 'paid' }, 'shop_orders_bulk_paid'); setSelectedIds(new Set()); load() } },
    { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('shop-orders', [
      { key: 'order_number', label: 'Číslo' }, { key: 'customer_name', label: 'Zákazník' },
      { key: 'customer_email', label: 'Email' }, { key: 'created_at', label: 'Datum', format: v => v ? new Date(v).toLocaleString('cs-CZ') : '' },
      { key: 'total', label: 'Celkem' }, { key: 'payment_status', label: 'Platba' }, { key: 'status', label: 'Stav' },
    ], orders.filter(o => selectedIds.has(o.id))) },
    { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} objednávek?', onClick: async () => { await bulkDelete('shop_orders', ids, 'shop_orders_bulk_deleted'); setSelectedIds(new Set()); load() } },
  ]

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={filters.search || ''} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat objednávku…" />
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []} onChange={v => { setPage(1); setFilters(f => ({ ...f, statuses: v })) }} options={STATUS_OPTIONS} />
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_shoporders_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer" style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>Reset</button>
        <div className="ml-auto"><Button green onClick={() => setShowAdd(true)}>+ Nová objednávka</Button></div>
      </div>

      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA ShopOrdersTab</strong><br/>
        <div>orders: {orders.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}"</div>
      </div>)}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={bulkActions} />
          <Table>
            <thead><TRow header>
              <TH><SelectAllCheckbox items={orders} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
              <TH>Číslo</TH><TH>Zákazník</TH><TH>Datum</TH><TH>Celkem</TH><TH>Platba</TH><TH>Stav</TH>
            </TRow></thead>
            <tbody>
              {orders.map(o => {
                const sc = STATUS_COLORS[o.status] || { bg: '#f3f4f6', color: '#1a2e22' }
                const pc = PAYMENT_COLORS[o.payment_status] || { bg: '#f3f4f6', color: '#1a2e22' }
                return (
                  <tr key={o.id} onClick={() => setDetail(o)} className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                    style={{ borderBottom: '1px solid #d4e8e0', background: selectedIds.has(o.id) ? '#fef9c3' : undefined }}>
                    <TD><RowCheckbox id={o.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TD>
                    <TD mono bold>{o.order_number}</TD><TD>{o.customer_name || o.customer_email || '—'}</TD><TD>{fmtDate(o.created_at)}</TD><TD bold>{fmt(o.total)}</TD>
                    <TD><span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{ padding: '3px 8px', background: pc.bg, color: pc.color }}>{PAYMENT_LABELS[o.payment_status] || o.payment_status}</span></TD>
                    <TD><span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase" style={{ padding: '3px 8px', background: sc.bg, color: sc.color }}>{STATUS_LABELS[o.status] || o.status}</span></TD>
                  </tr>
                )
              })}
              {orders.length === 0 && <TRow><TD colSpan={7}>Žádné objednávky</TD></TRow>}
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

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => { if (values.includes(val)) onChange(values.filter(v => v !== val)); else onChange([...values, val]) }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn" style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer" style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
