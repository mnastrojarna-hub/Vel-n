import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import Modal from '../components/ui/Modal'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import InvoicesTab from './accounting/InvoicesTab'
import TaxTab from './accounting/TaxTab'
import ReceivedInvoicesTab from './accounting/ReceivedInvoicesTab'

const PERIODS = [
  { value: 'month', label: 'Měsíc' },
  { value: 'quarter', label: 'Kvartál' },
  { value: 'year', label: 'Rok' },
]

const TYPES = [
  { value: '', label: 'Vše' },
  { value: 'revenue', label: 'Příjmy' },
  { value: 'expense', label: 'Výdaje' },
]

// Kategorie, které jsou VŽDY příjmy (i když type = 'expense')
const REVENUE_CATEGORIES = ['pronájem', 'pronajem', 'rezervace', 'booking', 'rental']
// Popisy, které indikují příjem
const REVENUE_DESCRIPTIONS = ['platba za rezervaci', 'platba za pronájem', 'příjem z pronájmu']

function classifyEntry(entry) {
  const cat = (entry.category || '').toLowerCase()
  const desc = (entry.description || '').toLowerCase()
  // If category or description matches revenue patterns, it's revenue
  if (REVENUE_CATEGORIES.some(rc => cat.includes(rc)) ||
      REVENUE_DESCRIPTIONS.some(rd => desc.includes(rd))) {
    return 'revenue'
  }
  return entry.type || 'expense'
}

const FINANCE_TABS = ['Přehled', 'Faktury', 'Daňové podklady', 'Faktury přijaté']

export default function Finance() {
  const [activeTab, setActiveTab] = useState('Přehled')
  const [summary, setSummary] = useState({ revenue: 0, expense: 0, unpaid: 0 })
  const [transactions, setTransactions] = useState([])
  const [chartData, setChartData] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const defaultFilters = { period: 'month', types: [], category: '', search: '', sort: 'date_desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_finance_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_finance_filters', JSON.stringify(filters)) }, [filters])
  const [categories, setCategories] = useState([])
  const [detailTx, setDetailTx] = useState(null)
  const [recentInvoices, setRecentInvoices] = useState([])
  const [shopPayments, setShopPayments] = useState([])
  const [invoiceSums, setInvoiceSums] = useState({ zf: 0, dp: 0, kf: 0, shopZf: 0, shopKf: 0, rental: 0, eshop: 0, vouchers: 0 })

  useEffect(() => { loadData() }, [filters])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      await Promise.all([loadSummary(), loadTransactions(), loadChart(), loadRecentInvoices(), loadShopPayments(), loadInvoiceSums()])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadInvoiceSums() {
    const [invRes, shopRes, rentalRes, voucherRes] = await Promise.all([
      supabase.from('invoices').select('type, total, status'),
      supabase.from('shop_orders').select('total').eq('payment_status', 'paid'),
      supabase.from('bookings').select('total_price').eq('status', 'completed').eq('payment_status', 'paid'),
      supabase.from('promo_code_usage').select('discount_amount'),
    ])
    const invs = invRes.data || []
    const zf = invs.filter(i => ['advance', 'proforma'].includes(i.type)).reduce((s, i) => s + (i.total || 0), 0)
    const dp = invs.filter(i => i.type === 'payment_receipt').reduce((s, i) => s + (i.total || 0), 0)
    const kf = invs.filter(i => i.type === 'final').reduce((s, i) => s + (i.total || 0), 0)
    const shopZf = invs.filter(i => i.type === 'shop_proforma').reduce((s, i) => s + (i.total || 0), 0)
    const shopKf = invs.filter(i => i.type === 'shop_final').reduce((s, i) => s + (i.total || 0), 0)
    const eshop = (shopRes.data || []).reduce((s, o) => s + (o.total || 0), 0)
    const rental = (rentalRes.data || []).reduce((s, b) => s + (b.total_price || 0), 0)
    const vouchers = (voucherRes.data || []).reduce((s, v) => s + (v.discount_amount || 0), 0)
    setInvoiceSums({ zf, dp, kf, shopZf, shopKf, rental, eshop, vouchers })
  }

  async function loadRecentInvoices() {
    const sortField = filters.sort.startsWith('amount') ? 'total' : 'issue_date'
    const ascending = filters.sort.endsWith('_asc')
    const result = await supabase
      .from('invoices')
      .select('*, profiles:customer_id(full_name)')
      .order(sortField, { ascending, nullsFirst: false })
      .limit(20)
    console.log('[Finance] invoices query:', result.error ? 'ERR: ' + result.error.message : (result.data?.length || 0) + ' rows')
    if (result.error) console.error('[Finance] invoices error details:', result.error)
    setRecentInvoices(result.data || [])
  }

  async function loadShopPayments() {
    const sortField = filters.sort.startsWith('amount') ? 'total' : 'created_at'
    const ascending = filters.sort.endsWith('_asc')
    const { data } = await supabase
      .from('shop_orders')
      .select('*, profiles:customer_id(full_name)')
      .eq('payment_status', 'paid')
      .order(sortField, { ascending })
      .limit(20)
    setShopPayments(data || [])
  }

  async function loadSummary() {
    const now = new Date()
    const start = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10)
    const { data } = await supabase
      .from('accounting_entries')
      .select('type, amount, category, description')
      .gte('date', start)
    if (data) {
      const rev = data.filter(d => classifyEntry(d) === 'revenue').reduce((s, d) => s + Math.abs(d.amount || 0), 0)
      const exp = data.filter(d => classifyEntry(d) === 'expense').reduce((s, d) => s + Math.abs(d.amount || 0), 0)
      setSummary({ revenue: rev, expense: exp, unpaid: 0 })
    }
    const { data: inv } = await supabase
      .from('invoices')
      .select('total')
      .eq('status', 'issued')
    if (inv) {
      setSummary(s => ({ ...s, unpaid: inv.reduce((sum, i) => sum + (i.total || 0), 0) }))
    }
  }

  async function loadTransactions() {
    const sortField = filters.sort.startsWith('amount') ? 'amount' : 'date'
    const ascending = filters.sort.endsWith('_asc')
    let query = supabase
      .from('accounting_entries')
      .select('*')
      .order(sortField, { ascending })
      .limit(200)
    if (filters.category) query = query.eq('category', filters.category)
    const { data, error: err } = await query
    if (err) throw err
    let results = data || []
    // Collect unique categories
    const cats = [...new Set(results.map(r => r.category).filter(Boolean))].sort()
    setCategories(cats)
    // Apply classification and filter
    results = results.map(r => ({ ...r, _classified: classifyEntry(r) }))
    if (filters.types?.length > 0) {
      results = results.filter(r => filters.types.includes(r._classified))
    } else if (filters.type) {
      results = results.filter(r => r._classified === filters.type)
    }
    if (filters.search) {
      const s = filters.search.toLowerCase()
      results = results.filter(r =>
        (r.description || '').toLowerCase().includes(s) ||
        (r.category || '').toLowerCase().includes(s)
      )
    }
    setTransactions(results.slice(0, 50))
  }

  async function loadChart() {
    const months = []
    const now = new Date()
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
      months.push({ start: d.toISOString().slice(0, 10), label: d.toLocaleDateString('cs-CZ', { month: 'short' }) })
    }
    const { data } = await supabase
      .from('accounting_entries')
      .select('type, amount, date, category, description')
      .gte('date', months[0].start)
    const chart = months.map(m => {
      const mEnd = new Date(new Date(m.start).getFullYear(), new Date(m.start).getMonth() + 1, 0).toISOString().slice(0, 10)
      const mData = (data || []).filter(d => d.date >= m.start && d.date <= mEnd)
      return {
        label: m.label,
        revenue: mData.filter(d => classifyEntry(d) === 'revenue').reduce((s, d) => s + Math.abs(d.amount || 0), 0),
        expense: mData.filter(d => classifyEntry(d) === 'expense').reduce((s, d) => s + Math.abs(d.amount || 0), 0),
      }
    })
    setChartData(chart)
  }

  async function handleExport(format) {
    try {
      const result = await debugAction(`finance.export.${format}`, 'Finance', () =>
        supabase.functions.invoke('export-data', { body: { type: 'accounting_entries', format, filters } })
      , { format, filters })
      if (result?.error) throw result.error
      if (result?.data?.url) window.open(result.data.url, '_blank')
    } catch (e) {
      setError('Export selhal: ' + e.message)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
  const profit = summary.revenue - summary.expense

  return (
    <div>
      <div className="flex gap-2 mb-5">
        {FINANCE_TABS.map(t => (
          <button key={t} onClick={() => setActiveTab(t)}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: activeTab === t ? '#74FB71' : '#f1faf7', color: activeTab === t ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: activeTab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {activeTab === 'Faktury' && <InvoicesTab />}
      {activeTab === 'Daňové podklady' && <TaxTab />}
      {activeTab === 'Faktury přijaté' && <ReceivedInvoicesTab />}

      {activeTab === 'Přehled' && <>
      <div className="flex flex-wrap items-center gap-3 mb-5">
        {PERIODS.map(p => (
          <button key={p.value} onClick={() => setFilters(f => ({ ...f, period: p.value }))}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 16px', background: filters.period === p.value ? '#74FB71' : '#f1faf7', color: filters.period === p.value ? '#1a2e22' : '#1a2e22', border: 'none', boxShadow: filters.period === p.value ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {p.label}
          </button>
        ))}
        <CheckboxFilterGroup label="Typ" values={filters.types || []}
          onChange={v => setFilters(f => ({ ...f, types: v }))}
          options={[{ value: 'revenue', label: 'Příjmy' }, { value: 'expense', label: 'Výdaje' }]} />
        {categories.length > 0 && (
          <select value={filters.category} onChange={e => setFilters(f => ({ ...f, category: e.target.value }))}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
            style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
            <option value="">Všechny kategorie</option>
            {categories.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        )}
        <input type="text" value={filters.search} onChange={e => setFilters(f => ({ ...f, search: e.target.value }))}
          placeholder="Hledat popis…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 150 }} />
        <select value={filters.sort} onChange={e => setFilters(f => ({ ...f, sort: e.target.value }))}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        <button onClick={() => { setFilters({ ...defaultFilters }); localStorage.removeItem('velin_finance_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto flex gap-2">
          <Button onClick={() => handleExport('csv')}>CSV</Button>
          <Button onClick={() => handleExport('xlsx')}>XLSX</Button>
        </div>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <div className="grid grid-cols-4 gap-4 mb-5">
            <SummaryCard label="Měsíční tržby" value={fmt(summary.revenue)} color="#1a8a18" />
            <SummaryCard label="Měsíční náklady" value={fmt(summary.expense)} color="#dc2626" />
            <SummaryCard label="Zisk" value={fmt(profit)} color={profit >= 0 ? '#1a8a18' : '#dc2626'} />
            <SummaryCard label="Neuhrazené faktury" value={fmt(summary.unpaid)} color="#b45309" />
          </div>

          {chartData.length > 0 && (
            <Card className="mb-5">
              <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Tržby vs. náklady (12 měsíců)</h3>
              <div className="flex items-end gap-1" style={{ height: 120 }}>
                {chartData.map((m, i) => {
                  const max = Math.max(...chartData.map(c => Math.max(c.revenue, c.expense)), 1)
                  return (
                    <div key={i} className="flex-1 flex flex-col items-center gap-0.5">
                      <div className="w-full flex gap-0.5" style={{ height: 100 }}>
                        <div className="flex-1 rounded-t" style={{ background: '#74FB71', height: `${(m.revenue / max) * 100}%`, marginTop: 'auto' }} />
                        <div className="flex-1 rounded-t" style={{ background: '#fee2e2', height: `${(m.expense / max) * 100}%`, marginTop: 'auto' }} />
                      </div>
                      <span className="text-[8px] font-bold" style={{ color: '#1a2e22' }}>{m.label}</span>
                    </div>
                  )
                })}
              </div>
            </Card>
          )}

          {/* DIAGNOSTIKA */}
          <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
            <strong>DIAGNOSTIKA Finance</strong><br/>
            <div>invoices: {recentInvoices.length} záznamů {recentInvoices.length > 0 && `[${recentInvoices.slice(0,5).map(i => `${i.type}/${i.number}/${i.total}Kč`).join(', ')}${recentInvoices.length > 5 ? '...' : ''}]`}</div>
            <div>accounting_entries: {transactions.length} záznamů</div>
            <div>shop_orders (paid): {shopPayments.length} záznamů</div>
          </div>

          {/* Invoice sums overview */}
          <Card className="mb-5">
            <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Přehled dle typu</h3>
            <div className="grid grid-cols-4 gap-3 mb-3">
              <MiniStat label="Zálohy (ZF)" value={fmt(invoiceSums.zf)} color="#2563eb" />
              <MiniStat label="Doklady k platbě (DP)" value={fmt(invoiceSums.dp)} color="#0891b2" />
              <MiniStat label="Konečné (KF)" value={fmt(invoiceSums.kf)} color="#1a8a18" />
              <MiniStat label="Pronájem (dokončeno)" value={fmt(invoiceSums.rental)} color="#059669" />
            </div>
            <div className="grid grid-cols-4 gap-3">
              <MiniStat label="E-shop prodeje" value={fmt(invoiceSums.eshop)} color="#8b5cf6" />
              <MiniStat label="Shop ZF" value={fmt(invoiceSums.shopZf)} color="#7c3aed" />
              <MiniStat label="Shop KF" value={fmt(invoiceSums.shopKf)} color="#059669" />
              <MiniStat label="Poukazy (slevy)" value={fmt(invoiceSums.vouchers)} color="#b45309" />
            </div>
          </Card>

          {/* Invoices (ZF, DP, KF) */}
          <Card className="mb-5">
            <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Faktury (ZF, DP, KF)</h3>
            {recentInvoices.length === 0 ? (
              <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné faktury</p>
            ) : (
              <Table>
                <thead>
                  <TRow header>
                    <TH>Číslo</TH><TH>Typ</TH><TH>Zákazník</TH><TH>Částka</TH><TH>Stav</TH><TH>Datum</TH>
                  </TRow>
                </thead>
                <tbody>
                  {recentInvoices.map(inv => {
                    const typeLabels = { advance: 'ZF', proforma: 'ZF', payment_receipt: 'DP', final: 'KF', shop_proforma: 'Shop ZF', shop_final: 'Shop KF' }
                    const typeColors = { advance: '#2563eb', proforma: '#2563eb', payment_receipt: '#0891b2', final: '#1a8a18', shop_proforma: '#8b5cf6', shop_final: '#059669' }
                    const typeBgs = { advance: '#dbeafe', proforma: '#dbeafe', payment_receipt: '#cffafe', final: '#dcfce7', shop_proforma: '#ede9fe', shop_final: '#d1fae5' }
                    const statusLabels = { draft: 'Koncept', issued: 'Vystavena', paid: 'Zaplacena', cancelled: 'Storno', refunded: 'Refund' }
                    const statusColors = { draft: '#6b7280', issued: '#b45309', paid: '#1a8a18', cancelled: '#dc2626', refunded: '#6b7280' }
                    return (
                      <TRow key={inv.id}>
                        <TD mono bold>{inv.number || '—'}</TD>
                        <TD><Badge label={typeLabels[inv.type] || inv.type} color={typeColors[inv.type] || '#6b7280'} bg={typeBgs[inv.type] || '#f3f4f6'} /></TD>
                        <TD>{inv.profiles?.full_name || '—'}</TD>
                        <TD bold>{fmt(inv.total)}</TD>
                        <TD><span className="text-sm font-bold" style={{ color: statusColors[inv.status] || '#6b7280' }}>{statusLabels[inv.status] || inv.status}</span></TD>
                        <TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                      </TRow>
                    )
                  })}
                </tbody>
              </Table>
            )}
          </Card>

          {/* Shop payments */}
          {shopPayments.length > 0 && (
            <Card className="mb-5">
              <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Platby z e-shopu</h3>
              <Table>
                <thead>
                  <TRow header>
                    <TH>Objednávka</TH><TH>Zákazník</TH><TH>Částka</TH><TH>Způsob</TH><TH>Datum</TH>
                  </TRow>
                </thead>
                <tbody>
                  {shopPayments.map(o => (
                    <TRow key={o.id}>
                      <TD mono bold>{o.order_number || o.id?.slice(-8).toUpperCase() || '—'}</TD>
                      <TD>{o.profiles?.full_name || '—'}</TD>
                      <TD bold color="#1a8a18">{fmt(o.total_amount)}</TD>
                      <TD>{o.payment_method || '—'}</TD>
                      <TD>{o.created_at ? new Date(o.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                    </TRow>
                  ))}
                </tbody>
              </Table>
            </Card>
          )}

          {/* Accounting entries (platby za rezervace) */}
          <Card className="mb-5">
            <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Účetní záznamy (platby za rezervace)</h3>
          <Table>
            <thead>
              <TRow header>
                <TH>Datum</TH><TH>Typ</TH><TH>Popis</TH><TH>Částka</TH><TH>Kategorie</TH><TH>Rezervace</TH>
              </TRow>
            </thead>
            <tbody>
              {transactions.map(t => (
                <tr key={t.id} onClick={() => setDetailTx(t)}
                  className="cursor-pointer hover:bg-[#f1faf7] transition-colors"
                  style={{ borderBottom: '1px solid #d4e8e0' }}>
                  <TD>{t.date ? new Date(t.date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD><TypeBadge type={t._classified || classifyEntry(t)} /></TD>
                  <TD>{t.description || '—'}</TD>
                  <TD bold color={(t._classified || classifyEntry(t)) === 'revenue' ? '#1a8a18' : '#dc2626'}>{fmt(Math.abs(t.amount))}</TD>
                  <TD>{t.category || '—'}</TD>
                  <TD mono>{t.booking_id ? t.booking_id.slice(-8).toUpperCase() : '—'}</TD>
                </tr>
              ))}
              {transactions.length === 0 && <TRow><TD>Žádné transakce</TD></TRow>}
            </tbody>
          </Table>
          </Card>
        </>
      )}

      {detailTx && (
        <Modal open title="Detail transakce" onClose={() => setDetailTx(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DetailRow label="Datum" value={detailTx.date ? new Date(detailTx.date).toLocaleDateString('cs-CZ') : '—'} />
            <DetailRow label="Typ" value={classifyEntry(detailTx) === 'revenue' ? 'Příjem' : 'Výdaj'} />
            <DetailRow label="Částka" value={fmt(detailTx.amount)} />
            <DetailRow label="Kategorie" value={detailTx.category || '—'} />
            <div className="col-span-2">
              <DetailRow label="Popis" value={detailTx.description || '—'} />
            </div>
            {detailTx.booking_id && <DetailRow label="ID rezervace" value={detailTx.booking_id} mono />}
            <DetailRow label="Vytvořeno" value={detailTx.created_at ? new Date(detailTx.created_at).toLocaleString('cs-CZ') : '—'} />
          </div>
          <div className="flex justify-end mt-5">
            <Button onClick={() => setDetailTx(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
      </>}
    </div>
  )
}

function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
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

function MiniStat({ label, value, color }) {
  return (
    <div className="p-2 rounded-lg" style={{ background: '#f1faf7' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
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

function TypeBadge({ type }) {
  const isRev = type === 'revenue'
  return (
    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
      style={{ padding: '4px 10px', background: isRev ? '#dcfce7' : '#fee2e2', color: isRev ? '#1a8a18' : '#dc2626' }}>
      {isRev ? 'Příjem' : 'Výdaj'}
    </span>
  )
}
