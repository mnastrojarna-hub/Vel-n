import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import ConfirmDialog from '../../components/ui/ConfirmDialog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import InvoiceCreateModal from './InvoiceCreateModal'
import InvoicePreviewModal from './InvoicePreviewModal'

const PER_PAGE = 25

const TYPE_MAP = {
  proforma: { label: 'Zálohová (ZF)', color: '#2563eb', bg: '#dbeafe' },
  advance: { label: 'Zálohová (ZF)', color: '#2563eb', bg: '#dbeafe' },
  issued: { label: 'Vystavená', color: '#1a2e22', bg: '#f3f4f6' },
  received: { label: 'Přijatá', color: '#1a2e22', bg: '#f3f4f6' },
  final: { label: 'Konečná (KF)', color: '#1a8a18', bg: '#dcfce7' },
  payment_receipt: { label: 'Doklad k platbě (DP)', color: '#0891b2', bg: '#cffafe' },
  shop_proforma: { label: 'Shop zálohová', color: '#8b5cf6', bg: '#ede9fe' },
  shop_final: { label: 'Shop konečná', color: '#059669', bg: '#d1fae5' },
}

const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#1a2e22', bg: '#f3f4f6' },
  issued: { label: 'Vystavena', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
  refunded: { label: 'Refundována', color: '#1a2e22', bg: '#f3f4f6' },
}

export default function InvoicesTab() {
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ search: '', type: '', status: '', sort: 'date_desc' })
  const [summary, setSummary] = useState({ total: 0, paid: 0, unpaid: 0, cancelled: 0 })
  const [detail, setDetail] = useState(null)
  const [showCreate, setShowCreate] = useState(false)
  const [cancelConfirm, setCancelConfirm] = useState(null)

  useEffect(() => { loadInvoices() }, [page, filters])
  useEffect(() => { loadSummary() }, [])

  async function loadInvoices() {
    setLoading(true); setError(null)
    try {
      debugLog('DocInvoicesTab', 'loadInvoices', { page, filters })
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name, email), bookings:booking_id(id, start_date, modification_history, sos_incident_id, motorcycles:moto_id(model))', { count: 'exact' })
        .order(filters.sort.startsWith('amount') ? 'total' : 'issue_date', { ascending: filters.sort.endsWith('_asc'), nullsFirst: false })

      if (filters.type === 'advance') {
        // ZF: match both 'advance' and 'proforma' types
        query = query.in('type', ['advance', 'proforma'])
      } else if (filters.type) {
        query = query.eq('type', filters.type)
      }
      if (filters.status) query = query.eq('status', filters.status)
      if (filters.search) query = query.or(`number.ilike.%${filters.search}%`)
      query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      const { data, count, error: err } = await debugAction('invoices.list', 'DocInvoicesTab', () => query)
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)
    } catch (e) { debugError('DocInvoicesTab', 'loadInvoices', e); setError(e.message) }
    setLoading(false)
  }

  async function loadSummary() {
    try {
      const { data } = await debugAction('invoices.summary', 'DocInvoicesTab', () =>
        supabase.from('invoices').select('status, total')
      )
      if (data) {
        setSummary({
          total: data.length,
          paid: data.filter(i => i.status === 'paid').reduce((s, i) => s + (i.total || 0), 0),
          unpaid: data.filter(i => i.status === 'issued').reduce((s, i) => s + (i.total || 0), 0),
          cancelled: data.filter(i => i.status === 'cancelled').length,
        })
      }
    } catch (e) { debugError('DocInvoicesTab', 'loadSummary', e) }
  }

  async function handleCancel(invoice) {
    try {
      debugLog('DocInvoicesTab', 'handleCancel', { invoiceId: invoice.id })
      const { error: err } = await debugAction('invoices.cancel', 'DocInvoicesTab', () =>
        supabase.from('invoices').update({ status: 'cancelled' }).eq('id', invoice.id)
      )
      if (err) throw err
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'invoice_cancelled', details: { invoice_id: invoice.id, number: invoice.number },
      })
      setCancelConfirm(null)
      loadInvoices()
      loadSummary()
    } catch (e) { debugError('DocInvoicesTab', 'handleCancel', e); setError(e.message) }
  }

  async function handleDownload(invoice) {
    try {
      // Always generate from template (storage bucket may not exist)
      const { loadInvoiceData } = await import('../../lib/invoiceUtils')
      const { generateInvoiceHtml } = await import('../../lib/invoiceTemplate')
      const fullInv = await loadInvoiceData(invoice.id)
      const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
      const blob = new Blob([html], { type: 'text/html' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a'); a.href = url; a.download = `faktura_${invoice.number || 'doc'}.html`; a.click(); URL.revokeObjectURL(url)
    } catch (e) { debugError('DocInvoicesTab', 'handleDownload', e); setError(`Stažení selhalo: ${e.message}`) }
  }

  function handleCreated() {
    setShowCreate(false)
    loadInvoices()
    loadSummary()
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      {/* Summary */}
      <div className="grid grid-cols-4 gap-3 mb-5">
        <SummaryCard label="Celkem faktur" value={summary.total} color="#0f1a14" />
        <SummaryCard label="Zaplaceno" value={fmt(summary.paid)} color="#1a8a18" />
        <SummaryCard label="Nezaplaceno" value={fmt(summary.unpaid)} color="#b45309" />
        <SummaryCard label="Stornováno" value={summary.cancelled} color="#dc2626" />
      </div>

      {/* Filters + Create */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat číslo faktury…"
        />
        <FilterSelect value={filters.type} onChange={v => { setPage(1); setFilters(f => ({ ...f, type: v })) }}
          options={[
            { value: '', label: 'Všechny typy' },
            { value: 'advance', label: 'Zálohové (ZF)' },
            { value: 'payment_receipt', label: 'Doklady k platbě (DP)' },
            { value: 'final', label: 'Konečné (KF)' },
            { value: 'issued', label: 'Vystavené' },
            { value: 'shop_proforma', label: 'Shop zálohové' },
            { value: 'shop_final', label: 'Shop konečné' },
          ]} />
        <FilterSelect value={filters.status} onChange={v => { setPage(1); setFilters(f => ({ ...f, status: v })) }}
          options={[
            { value: '', label: 'Všechny stavy' },
            { value: 'issued', label: 'Vystavené' },
            { value: 'paid', label: 'Zaplacené' },
            { value: 'cancelled', label: 'Stornované' },
            { value: 'refunded', label: 'Refundované' },
          ]} />
        <FilterSelect value={filters.sort} onChange={v => { setPage(1); setFilters(f => ({ ...f, sort: v })) }}
          options={[
            { value: 'date_desc', label: 'Datum ↓ nejnovější' },
            { value: 'date_asc', label: 'Datum ↑ nejstarší' },
            { value: 'amount_desc', label: 'Částka ↓ nejvyšší' },
            { value: 'amount_asc', label: 'Částka ↑ nejnižší' },
          ]} />
        <div className="ml-auto">
          <Button green onClick={() => setShowCreate(true)}>+ Nová faktura</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Číslo</TH><TH>Typ</TH><TH>Zákazník</TH><TH>Motorka</TH>
                <TH>Částka</TH><TH>Stav</TH><TH>Datum</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {invoices.map(inv => {
                const tp = TYPE_MAP[inv.type] || { label: inv.type || 'Neznámý', color: '#1a2e22', bg: '#f3f4f6' }
                const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
                const isSOS = inv.source === 'sos' || !!inv.bookings?.sos_incident_id
                const isModified = inv.bookings?.modification_history && Array.isArray(inv.bookings.modification_history) && inv.bookings.modification_history.length > 0
                return (
                  <TRow key={inv.id}>
                    <TD mono bold>
                      <div className="flex items-center gap-1">
                        {inv.number || '—'}
                        {isSOS && <span title="SOS faktura" style={{ color: '#dc2626', fontSize: 14, fontWeight: 800 }}>SOS</span>}
                        {isModified && <span title="Změna rezervace" style={{ color: '#b45309', fontSize: 14, fontWeight: 800 }}>MOD</span>}
                      </div>
                    </TD>
                    <TD><Badge label={tp.label} color={tp.color} bg={tp.bg} /></TD>
                    <TD>{inv.profiles?.full_name || '—'}</TD>
                    <TD>{inv.bookings?.motorcycles?.model || '—'}</TD>
                    <TD>
                      <span className="font-bold" style={{ color: inv.status === 'paid' ? '#1a8a18' : '#0f1a14' }}>
                        {fmt(inv.total)}
                      </span>
                    </TD>
                    <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                    <TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>
                      <div className="flex gap-1">
                        <ActionBtn color="#2563eb" onClick={() => setDetail(inv)}>Náhled</ActionBtn>
                        <ActionBtn color="#1a2e22" onClick={() => handleDownload(inv)}>Stáhnout</ActionBtn>
                        {inv.status !== 'cancelled' && inv.status !== 'refunded' && (
                          <ActionBtn color="#dc2626" onClick={() => setCancelConfirm(inv)}>Storno</ActionBtn>
                        )}
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {invoices.length === 0 && <TRow><TD>Žádné faktury</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showCreate && (
        <InvoiceCreateModal onClose={() => setShowCreate(false)} onSaved={handleCreated} />
      )}

      {detail && (
        <InvoicePreviewModal
          invoice={detail}
          onClose={() => setDetail(null)}
          onUpdated={() => { loadInvoices(); loadSummary() }}
        />
      )}

      {cancelConfirm && (
        <ConfirmDialog open title="Stornovat fakturu?"
          message={`Opravdu chcete stornovat fakturu ${cancelConfirm.number}?`}
          danger onConfirm={() => handleCancel(cancelConfirm)} onCancel={() => setCancelConfirm(null)} />
      )}
    </div>
  )
}

function SummaryCard({ label, value, color }) {
  return (
    <Card>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function ActionBtn({ children, color, onClick }) {
  return (
    <button onClick={onClick} className="text-sm font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}>{children}</button>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
