import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugLog, debugError } from '../../lib/debugLog'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import { loadInvoiceData, printInvoiceHtml } from '../../lib/invoiceUtils'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function CreditNotesTab() {
  const [creditNotes, setCreditNotes] = useState([])
  const [refundEntries, setRefundEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState('date_desc')
  const [viewInvoice, setViewInvoice] = useState(null)
  const [viewHtml, setViewHtml] = useState(null)
  const [stats, setStats] = useState({ totalRefunded: 0, count: 0, thisMonth: 0, thisMonthCount: 0 })

  useEffect(() => { load() }, [page, search, sort])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('CreditNotesTab', 'load', { page, search, sort })

      // Load credit notes
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name, email), bookings:booking_id(start_date, end_date, motorcycles(model, spz))', { count: 'exact' })
        .eq('type', 'credit_note')
      if (search) query = query.or(`number.ilike.%${search}%`)
      const sortField = sort.startsWith('amount') ? 'total' : 'issue_date'
      const ascending = sort.endsWith('_asc')
      query = query.order(sortField, { ascending, nullsFirst: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      const { data, count, error: err } = await query
      if (err) throw err
      setCreditNotes(data || [])
      setTotal(count || 0)

      // Load refund accounting entries
      const { data: entries } = await supabase
        .from('accounting_entries')
        .select('*')
        .eq('category', 'refund')
        .order('date', { ascending: false })
        .limit(50)
      setRefundEntries(entries || [])

      // Stats
      const { data: allCN } = await supabase
        .from('invoices')
        .select('total, issue_date')
        .eq('type', 'credit_note')
      const all = allCN || []
      const totalRefunded = all.reduce((s, cn) => s + Math.abs(cn.total || 0), 0)
      const now = new Date()
      const monthStart = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`
      const thisMonthCNs = all.filter(cn => cn.issue_date >= monthStart)
      setStats({
        totalRefunded,
        count: all.length,
        thisMonth: thisMonthCNs.reduce((s, cn) => s + Math.abs(cn.total || 0), 0),
        thisMonthCount: thisMonthCNs.length,
      })
    } catch (e) {
      debugError('CreditNotesTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function handleView(inv) {
    try {
      const fullInv = await loadInvoiceData(inv.id)
      const html = generateInvoiceHtml({
        ...fullInv,
        customer: fullInv.profiles || {},
        items: fullInv.items || [],
      })
      setViewHtml(html)
      setViewInvoice(inv)
    } catch (e) {
      setError(`Náhled dobropisu selhal: ${e.message}`)
    }
  }

  async function handlePrint(inv) {
    try {
      const fullInv = await loadInvoiceData(inv.id)
      const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
      printInvoiceHtml(html)
    } catch (e) {
      setError(`Tisk dobropisu selhal: ${e.message}`)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      {/* Stats */}
      <div className="grid grid-cols-4 gap-4 mb-5">
        <StatCard label="Celkem dobropisů" value={stats.count} color="#dc2626" />
        <StatCard label="Celkem vráceno" value={fmt(stats.totalRefunded)} color="#dc2626" />
        <StatCard label="Tento měsíc" value={stats.thisMonthCount} color="#b45309" />
        <StatCard label="Tento měsíc vráceno" value={fmt(stats.thisMonth)} color="#b45309" />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat číslo dobropisu…" />
        <select value={sort} onChange={e => { setPage(1); setSort(e.target.value) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          {/* Credit Notes Table */}
          <Card className="mb-5">
            <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#dc2626' }}>Dobropisy (DB)</h3>
            {creditNotes.length === 0 ? (
              <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné dobropisy</p>
            ) : (
              <Table>
                <thead>
                  <TRow header>
                    <TH>Číslo</TH><TH>Zákazník</TH><TH>Rezervace</TH><TH>Částka</TH><TH>Datum</TH><TH>Stav</TH><TH>Akce</TH>
                  </TRow>
                </thead>
                <tbody>
                  {creditNotes.map(cn => (
                    <tr key={cn.id} className="cursor-pointer hover:bg-[#fef2f2] transition-colors"
                      style={{ borderBottom: '1px solid #fecaca' }} onClick={() => handleView(cn)}>
                      <TD mono bold style={{ color: '#dc2626' }}>{cn.number || '—'}</TD>
                      <TD>{cn.profiles?.full_name || '—'}</TD>
                      <TD>
                        {cn.bookings ? (
                          <span className="text-sm">
                            {cn.bookings.motorcycles?.model || '—'} ({cn.bookings.start_date ? new Date(cn.bookings.start_date).toLocaleDateString('cs-CZ') : '—'})
                          </span>
                        ) : '—'}
                      </TD>
                      <TD bold style={{ color: '#dc2626' }}>−{fmt(Math.abs(cn.total))}</TD>
                      <TD>{cn.issue_date ? new Date(cn.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD><Badge label="Dobropis" color="#dc2626" bg="#fee2e2" /></TD>
                      <TD>
                        <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                          <SmallBtn onClick={() => handleView(cn)}>Náhled</SmallBtn>
                          <SmallBtn onClick={() => handlePrint(cn)}>PDF</SmallBtn>
                        </div>
                      </TD>
                    </tr>
                  ))}
                </tbody>
              </Table>
            )}
            <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
          </Card>

          {/* Refund Accounting Entries */}
          <Card>
            <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#dc2626' }}>Vrácené platby (účetní záznamy)</h3>
            {refundEntries.length === 0 ? (
              <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné vrácené platby</p>
            ) : (
              <Table>
                <thead>
                  <TRow header>
                    <TH>Datum</TH><TH>Popis</TH><TH>Částka</TH><TH>Rezervace</TH>
                  </TRow>
                </thead>
                <tbody>
                  {refundEntries.map(e => (
                    <TRow key={e.id}>
                      <TD>{e.date ? new Date(e.date).toLocaleDateString('cs-CZ') : '—'}</TD>
                      <TD>{e.description || '—'}</TD>
                      <TD bold style={{ color: '#dc2626' }}>−{fmt(Math.abs(e.amount))}</TD>
                      <TD mono>{e.booking_id ? e.booking_id.slice(-8).toUpperCase() : '—'}</TD>
                    </TRow>
                  ))}
                </tbody>
              </Table>
            )}
          </Card>
        </>
      )}

      {viewInvoice && viewHtml && (
        <Modal open title={`Dobropis ${viewInvoice.number || ''}`} onClose={() => { setViewInvoice(null); setViewHtml(null) }} wide>
          <div className="border rounded-lg overflow-auto" style={{ maxHeight: 550, background: '#fff', borderColor: '#fca5a5' }}>
            <iframe srcDoc={viewHtml} style={{ width: '100%', height: 500, border: 'none' }} title="Náhled dobropisu" />
          </div>
          <div className="flex justify-end gap-3 mt-4">
            <Button onClick={() => { const win = window.open('', '_blank'); if (win) { win.document.write(viewHtml); win.document.close(); win.onload = () => win.print() } }}>Tisk / PDF</Button>
            <Button onClick={() => { setViewInvoice(null); setViewHtml(null) }}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <div className="p-4 rounded-card" style={{ background: '#fef2f2', border: '1px solid #fecaca' }}>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#991b1b' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

function SmallBtn({ children, onClick }) {
  return (
    <button onClick={onClick} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '3px 8px', background: '#fef2f2', color: '#dc2626', border: '1px solid #fca5a5' }}>
      {children}
    </button>
  )
}
