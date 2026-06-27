import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import { renderAndStoreInvoicePdf } from '../../lib/invoiceUtils'
import InvoiceCreateModal from './InvoiceCreateModal'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'
import { exportToCsv, bulkUpdate, bulkDelete } from '../../lib/bulkActions'

const PER_PAGE = 25

const TYPE_LABELS = {
  proforma: 'Zálohová (ZF)',
  advance: 'Zálohová (ZF)',
  issued: 'Vystavená',
  received: 'Přijatá',
  final: 'Konečná (KF)',
  payment_receipt: 'Doklad k platbě (DP)',
  shop_proforma: 'Shop zálohová',
  shop_final: 'Shop konečná',
  credit_note: 'Dobropis (DB)',
}

const TYPE_OPTIONS = [
  { value: 'issued', label: 'Vystavené (FV)' },
  { value: 'advance', label: 'Zálohové (ZF)' },
  { value: 'payment_receipt', label: 'Doklady k platbě (DP)' },
  { value: 'final', label: 'Konečné (KF)' },
  { value: 'credit_note', label: 'Dobropisy (DB)' },
  { value: 'shop_proforma', label: 'Shop zálohové' },
  { value: 'shop_final', label: 'Shop konečné' },
]

export default function InvoicesTab() {
  const debugMode = useDebugMode()
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', types: [], sort: 'date_desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_acc_invoices_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_acc_invoices_filters', JSON.stringify(filters)) }, [filters])
  const [showAdd, setShowAdd] = useState(false)
  const [detailInv, setDetailInv] = useState(null)
  const [selectedIds, setSelectedIds] = useState(new Set())

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('AccInvoicesTab', 'load', { page, filters })
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name), bookings:booking_id(modification_history, sos_incident_id)', { count: 'exact' })
      if (filters.types?.length > 0) {
        const expandedTypes = filters.types.includes('advance') ? [...filters.types, 'proforma'] : filters.types
        query = query.in('type', expandedTypes)
      }
      if (filters.search) query = query.or(`number.ilike.%${filters.search}%`)
      query = query.order(filters.sort.startsWith('amount') ? 'total' : 'issue_date', { ascending: filters.sort.endsWith('_asc'), nullsFirst: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('invoices.list', 'AccInvoicesTab', () => query)
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)
    } catch (e) {
      debugError('AccInvoicesTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function generatePdf(invoiceId) {
    try {
      debugLog('AccInvoicesTab', 'generatePdf', { invoiceId })
      const { loadInvoiceData, invoiceCustomer } = await import('../../lib/invoiceUtils')
      const { generateInvoiceHtml } = await import('../../lib/invoiceTemplate')
      const fullInv = await loadInvoiceData(invoiceId)
      const html = generateInvoiceHtml({
        type: fullInv.type,
        number: fullInv.number,
        issue_date: fullInv.issue_date,
        due_date: fullInv.due_date,
        duzp: fullInv.issue_date,
        items: fullInv.items || [],
        subtotal: fullInv.subtotal,
        tax_amount: fullInv.tax_amount,
        total: fullInv.total,
        notes: fullInv.notes,
        variable_symbol: fullInv.number?.replace(/[^0-9]/g, ''),
        customer: invoiceCustomer(fullInv),
        cardInfo: fullInv.cardInfo, stripe_payment_intent_id: fullInv.stripe_payment_intent_id, paymentMethodLabel: fullInv.paymentMethodLabel,
        voucher_codes: fullInv.voucher_codes, voucherValidUntil: fullInv.voucherValidUntil, door_codes: fullInv.door_codes,
        paid_date: fullInv.paid_date, booking_id: fullInv.booking_id, bookings: fullInv.bookings,
      })
      const { printInvoiceHtml } = await import('../../lib/invoiceUtils')
      printInvoiceHtml(html)
    } catch (e) {
      debugError('AccInvoicesTab', 'generatePdf', e)
      setError('Generování PDF selhalo: ' + e.message)
    }
  }

  async function sendEmail(invoiceId) {
    try {
      debugLog('AccInvoicesTab', 'sendEmail', { invoiceId })
      // Nejdřív vyrenderuj + ulož PDF (pdf_path), aby ho mail mohl přiložit jako přílohu.
      try { await renderAndStoreInvoicePdf(invoiceId) } catch (e) { debugError('AccInvoicesTab', 'renderPdf', e) }
      // Přes `send-invoice-email` — použije e-mailovou ŠABLONU z Velína dle typu
      // dokladu a správné označení typu (zálohová/konečná/…), ne natvrdo psaný text.
      const { data, error } = await debugAction('functions.send-invoice-email', 'AccInvoicesTab', () =>
        supabase.functions.invoke('send-invoice-email', {
          body: { invoice_id: invoiceId },
        })
      )
      if (error) throw error
      if (data && data.success === false) throw new Error(data.error || 'Odeslání selhalo')
      alert('Email odeslán')
    } catch (e) {
      debugError('AccInvoicesTab', 'sendEmail', e)
      setError('Odeslání emailu selhalo: ' + e.message)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  const ids = [...selectedIds]
  const bulkActions = [
    { label: 'Označit zaplaceno', icon: '💰', onClick: async () => { await bulkUpdate('invoices', ids, { status: 'paid' }, 'invoices_bulk_paid'); setSelectedIds(new Set()); load() } },
    { label: 'Označit vystavené', icon: '📤', onClick: async () => { await bulkUpdate('invoices', ids, { status: 'issued' }, 'invoices_bulk_issued'); setSelectedIds(new Set()); load() } },
    { label: 'Stornovat', icon: '✗', onClick: async () => { await bulkUpdate('invoices', ids, { status: 'cancelled' }, 'invoices_bulk_cancelled'); setSelectedIds(new Set()); load() }, confirm: 'Stornovat {count} faktur?' },
    { label: 'Hromadný PDF (tisk)', icon: '🖨', onClick: async () => {
      for (const inv of invoices.filter(i => selectedIds.has(i.id))) await generatePdf(inv.id)
    } },
    { label: 'Odeslat e-mailem', icon: '✉', confirm: 'Odeslat {count} faktur e-mailem?', onClick: async () => {
      for (const inv of invoices.filter(i => selectedIds.has(i.id))) await sendEmail(inv.id)
    } },
    { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('invoices', [
      { key: 'number', label: 'Číslo' }, { key: 'type', label: 'Typ' },
      { key: 'profiles', label: 'Zákazník', format: (_, r) => r.customer_snapshot?.name || r.profiles?.full_name || '' },
      { key: 'total', label: 'Celkem' }, { key: 'tax_amount', label: 'DPH' },
      { key: 'issue_date', label: 'Vystavení' }, { key: 'due_date', label: 'Splatnost' },
      { key: 'status', label: 'Stav' },
    ], invoices.filter(i => selectedIds.has(i.id))) },
    { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} faktur? Tato akce je nevratná.', onClick: async () => { await bulkDelete('invoices', ids, 'invoices_bulk_deleted'); setSelectedIds(new Set()); load() } },
  ]

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat číslo, zákazníka…" />
        <CheckboxFilterGroup label="Typ" values={filters.types || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, types: v })) }}
          options={TYPE_OPTIONS} />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_acc_invoices_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová faktura</Button>
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA AccInvoicesTab</strong><br/>
        <div>invoices: {invoices.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: types={filters.types?.length > 0 ? filters.types.join(',') : 'vše'}, sort={filters.sort}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={bulkActions} />
          <Table>
            <thead>
              <TRow header>
                <TH><SelectAllCheckbox items={invoices} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
                <TH>Číslo</TH><TH>Typ</TH><TH>Zákazník</TH><TH>Částka</TH><TH>DPH</TH>
                <TH>Vystavení</TH><TH>Splatnost</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {invoices.map(inv => {
                const isSOS = inv.source === 'sos' || !!inv.bookings?.sos_incident_id
                const isModified = inv.bookings?.modification_history && Array.isArray(inv.bookings.modification_history) && inv.bookings.modification_history.length > 0
                return (
                <tr key={inv.id} onClick={() => setDetailInv(inv)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0', background: selectedIds.has(inv.id) ? '#fef9c3' : undefined }}>
                  <TD><RowCheckbox id={inv.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TD>
                  <TD mono bold>
                    <div className="flex items-center gap-1">
                      {inv.number || '—'}
                      {isSOS && <span title="SOS faktura" style={{ color: '#dc2626', fontSize: 12, fontWeight: 800 }}>SOS</span>}
                      {isModified && <span title="Změna rezervace" style={{ color: '#b45309', fontSize: 12, fontWeight: 800 }}>MOD</span>}
                    </div>
                  </TD>
                  <TD><span className="text-sm font-bold uppercase px-1.5 py-0.5 rounded" style={{
                    background: inv.type === 'credit_note' ? '#fee2e2' : inv.type === 'payment_receipt' ? '#cffafe' : inv.type === 'final' ? '#dcfce7' : '#dbeafe',
                    color: inv.type === 'credit_note' ? '#dc2626' : inv.type === 'payment_receipt' ? '#0891b2' : inv.type === 'final' ? '#1a8a18' : '#2563eb'
                  }}>{TYPE_LABELS[inv.type] || inv.type}</span></TD>
                  <TD>{inv.customer_snapshot?.name || inv.profiles?.full_name || '—'}</TD>
                  <TD bold style={inv.type === 'credit_note' ? { color: '#dc2626' } : {}}>{inv.type === 'credit_note' ? `−${fmt(Math.abs(inv.total))}` : fmt(inv.total)}</TD>
                  <TD>{fmt(inv.tax_amount)}</TD>
                  <TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>{inv.due_date ? new Date(inv.due_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD><StatusBadge status={inv.status || 'pending'} /></TD>
                  <TD>
                    <div className="flex gap-1">
                      <SmallBtn onClick={() => generatePdf(inv.id)}>PDF</SmallBtn>
                      <SmallBtn onClick={() => sendEmail(inv.id)}>Email</SmallBtn>
                    </div>
                  </TD>
                </tr>
              )})}
              {invoices.length === 0 && <TRow><TD>Žádné faktury</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <InvoiceCreateModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}

      {detailInv && (
        <Modal open title={`Faktura ${detailInv.number || '—'}`} onClose={() => setDetailInv(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DRow label="Číslo" value={detailInv.number} mono />
            <DRow label="Zákazník" value={detailInv.customer_snapshot?.name || detailInv.profiles?.full_name || '—'} />
            <DRow label="Částka" value={fmt(detailInv.total)} />
            <DRow label="DPH" value={fmt(detailInv.tax_amount)} />
            <DRow label="Základ" value={fmt(detailInv.subtotal)} />
            <DRow label="Stav" value={detailInv.status || '—'} />
            <DRow label="Vystavení" value={detailInv.issue_date ? new Date(detailInv.issue_date).toLocaleDateString('cs-CZ') : '—'} />
            <DRow label="Splatnost" value={detailInv.due_date ? new Date(detailInv.due_date).toLocaleDateString('cs-CZ') : '—'} />
            <DRow label="Typ" value={detailInv.type || '—'} />
            {detailInv.booking_id && <DRow label="ID rezervace" value={detailInv.booking_id.slice(-8).toUpperCase()} mono />}
          </div>
          <div className="flex justify-end gap-3 mt-5">
            <Button onClick={() => setDetailInv(null)}>Zavřít</Button>
            <SmallBtn onClick={() => generatePdf(detailInv.id)}>PDF</SmallBtn>
            <SmallBtn onClick={() => sendEmail(detailInv.id)}>Email</SmallBtn>
          </div>
        </Modal>
      )}
    </div>
  )
}

function DRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function SmallBtn({ children, onClick }) {
  return (
    <button onClick={onClick} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '3px 8px', background: '#f1faf7', color: '#1a2e22', border: 'none' }}>
      {children}
    </button>
  )
}

function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
