import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
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
  issued: { label: 'Vystavená', color: '#6b7280', bg: '#f3f4f6' },
  received: { label: 'Přijatá', color: '#6b7280', bg: '#f3f4f6' },
  final: { label: 'Konečná (KF)', color: '#1a8a18', bg: '#dcfce7' },
  payment_receipt: { label: 'Doklad k platbě (DP)', color: '#0891b2', bg: '#cffafe' },
  shop_proforma: { label: 'Shop zálohová', color: '#8b5cf6', bg: '#ede9fe' },
  shop_final: { label: 'Shop konečná', color: '#059669', bg: '#d1fae5' },
}

const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#6b7280', bg: '#f3f4f6' },
  issued: { label: 'Vystavena', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
  refunded: { label: 'Refundována', color: '#6b7280', bg: '#f3f4f6' },
}

export default function InvoicesTab() {
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState({ search: '', type: '', status: '' })
  const [summary, setSummary] = useState({ total: 0, paid: 0, unpaid: 0, cancelled: 0 })
  const [detail, setDetail] = useState(null)
  const [showCreate, setShowCreate] = useState(false)
  const [cancelConfirm, setCancelConfirm] = useState(null)

  useEffect(() => { loadInvoices() }, [page, filters])
  useEffect(() => { loadSummary() }, [])

  async function loadInvoices() {
    setLoading(true); setError(null)
    try {
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name, email), bookings:booking_id(id, start_date, motorcycles:moto_id(model))', { count: 'exact' })
        .order('issue_date', { ascending: false, nullsFirst: false })

      if (filters.type === 'advance') {
        // ZF: match both 'advance' and 'proforma' types
        query = query.in('type', ['advance', 'proforma'])
      } else if (filters.type) {
        query = query.eq('type', filters.type)
      }
      if (filters.status) query = query.eq('status', filters.status)
      if (filters.search) query = query.or(`number.ilike.%${filters.search}%`)
      query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      const { data, count, error: err } = await query
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function loadSummary() {
    try {
      const { data } = await supabase.from('invoices').select('status, total')
      if (data) {
        setSummary({
          total: data.length,
          paid: data.filter(i => i.status === 'paid').reduce((s, i) => s + (i.total || 0), 0),
          unpaid: data.filter(i => i.status === 'issued').reduce((s, i) => s + (i.total || 0), 0),
          cancelled: data.filter(i => i.status === 'cancelled').length,
        })
      }
    } catch {}
  }

  async function handleCancel(invoice) {
    try {
      const { error: err } = await supabase.from('invoices').update({ status: 'cancelled' }).eq('id', invoice.id)
      if (err) throw err
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'invoice_cancelled', details: { invoice_id: invoice.id, number: invoice.number },
      })
      setCancelConfirm(null)
      loadInvoices()
      loadSummary()
    } catch (e) { setError(e.message) }
  }

  async function handleDownload(invoice) {
    if (!invoice.pdf_path) return
    try {
      const { data, error: err } = await supabase.storage.from('documents').download(invoice.pdf_path)
      if (err) throw err
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = `faktura_${invoice.number || 'doc'}.html`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) { setError(`Stažení selhalo: ${e.message}`) }
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
                const tp = TYPE_MAP[inv.type] || { label: inv.type || 'Neznámý', color: '#6b7280', bg: '#f3f4f6' }
                const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
                return (
                  <TRow key={inv.id}>
                    <TD mono bold>{inv.number || '—'}</TD>
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
                        {inv.pdf_path && <ActionBtn color="#4a6357" onClick={() => handleDownload(inv)}>Stáhnout</ActionBtn>}
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
      <div className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function ActionBtn({ children, color, onClick }) {
  return (
    <button onClick={onClick} className="text-[10px] font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}>{children}</button>
  )
}

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}
