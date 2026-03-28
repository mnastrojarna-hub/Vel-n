import { useState, useEffect, lazy, Suspense } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import Modal from '../components/ui/Modal'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import ErrorBoundary from '../components/ErrorBoundary'
import { classifyEntry } from '../lib/revenueUtils'
import FinanceOverview from './FinanceOverview'

// Lazy-load accounting tabs to isolate crashes
const InvoicesTab = lazy(() => import('./accounting/InvoicesTab'))
const TaxTab = lazy(() => import('./accounting/TaxTab'))
const ReceivedInvoicesTab = lazy(() => import('./accounting/ReceivedInvoicesTab'))
const CashRegisterTab = lazy(() => import('./accounting/CashRegisterTab'))
const FinancialEventsTab = lazy(() => import('./accounting/FinancialEventsTab'))
const ExceptionsTab = lazy(() => import('./accounting/ExceptionsTab'))
// EmployeesTab presunut na /zamestnanci
const ShortTermAssetsTab = lazy(() => import('./accounting/ShortTermAssetsTab'))
const LongTermAssetsTab = lazy(() => import('./accounting/LongTermAssetsTab'))
const LiabilitiesTab = lazy(() => import('./accounting/LiabilitiesTab'))
const SuppliersTab = lazy(() => import('./accounting/SuppliersTab'))
const AutoOrdersTab = lazy(() => import('./accounting/AutoOrdersTab'))
const InventoryTab = lazy(() => import('./Inventory'))
const DeliveryNotesTab = lazy(() => import('./accounting/DeliveryNotesTab'))
const ContractsTab = lazy(() => import('./accounting/ContractsTab'))

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

const FINANCE_TABS = ['Přehled', 'Faktury', 'Dodací listy', 'Smlouvy', 'Objednávky', 'Účetnictví', 'Faktury přijaté', 'Pokladna', 'Sklad']

const ACCOUNTING_SUBTABS = [
  { id: 'events', label: 'Finanční události' },
  { id: 'exceptions', label: 'Výjimky' },
  { id: 'short_assets', label: 'Krátkodobý majetek' },
  { id: 'long_assets', label: 'Dlouhodobý majetek' },
  { id: 'liabilities', label: 'Závazky' },
  { id: 'suppliers', label: 'Dodavatelé' },
]

export default function Finance() {
  const debugMode = useDebugMode()
  const [activeTab, setActiveTab] = useState('Přehled')
  const [accountingSubTab, setAccountingSubTab] = useState('events')
  const [summary, setSummary] = useState({ revenue: 0, expense: 0, unpaid: 0, unpaidCount: 0 })
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
      const results = await Promise.allSettled([loadSummary(), loadTransactions(), loadChart(), loadRecentInvoices(), loadShopPayments(), loadInvoiceSums()])
      const errors = results.filter(r => r.status === 'rejected').map(r => r.reason?.message || String(r.reason))
      if (errors.length > 0) setError(errors.join('; '))
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
    // Exclude cancelled/refunded invoices from sums
    const invs = (invRes.data || []).filter(i => i.status !== 'cancelled' && i.status !== 'refunded')
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
      setSummary(s => ({ ...s, unpaid: inv.reduce((sum, i) => sum + (i.total || 0), 0), unpaidCount: inv.length }))
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

  const TabLoader = () => (
    <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  )

  return (
    <ErrorBoundary>
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

      <Suspense fallback={<TabLoader />}>
      {activeTab === 'Faktury' && <ErrorBoundary><InvoicesTab /></ErrorBoundary>}
      {activeTab === 'Objednávky' && <ErrorBoundary><AutoOrdersTab /></ErrorBoundary>}
      {activeTab === 'Dodací listy' && <ErrorBoundary><DeliveryNotesTab /></ErrorBoundary>}
      {activeTab === 'Smlouvy' && <ErrorBoundary><ContractsTab /></ErrorBoundary>}
      {activeTab === 'Faktury přijaté' && <ErrorBoundary><ReceivedInvoicesTab /></ErrorBoundary>}
      {activeTab === 'Pokladna' && <ErrorBoundary><CashRegisterTab /></ErrorBoundary>}
      {activeTab === 'Sklad' && <ErrorBoundary><InventoryTab /></ErrorBoundary>}

      {activeTab === 'Účetnictví' && (
        <div>
          <div className="flex gap-1 mb-4 flex-wrap">
            {ACCOUNTING_SUBTABS.map(st => (
              <button key={st.id} onClick={() => setAccountingSubTab(st.id)}
                className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                style={{
                  padding: '6px 14px',
                  background: accountingSubTab === st.id ? '#1a2e22' : '#f1faf7',
                  color: accountingSubTab === st.id ? '#74FB71' : '#1a2e22',
                  border: 'none',
                  boxShadow: accountingSubTab === st.id ? '0 2px 8px rgba(26,46,34,.25)' : 'none',
                }}>
                {st.label}
              </button>
            ))}
          </div>
          <ErrorBoundary>
          {accountingSubTab === 'events' && <FinancialEventsTab />}
          {accountingSubTab === 'exceptions' && <ExceptionsTab />}
          {accountingSubTab === 'short_assets' && <ShortTermAssetsTab />}
          {accountingSubTab === 'long_assets' && <LongTermAssetsTab />}
          {accountingSubTab === 'liabilities' && <LiabilitiesTab />}
          {accountingSubTab === 'suppliers' && <SuppliersTab />}
          </ErrorBoundary>
        </div>
      )}
      </Suspense>

      {activeTab === 'Přehled' && <>
        <FinanceOverview filters={filters} setFilters={setFilters} defaultFilters={defaultFilters} categories={categories} summary={summary} chartData={chartData} transactions={transactions} recentInvoices={recentInvoices} shopPayments={shopPayments} invoiceSums={invoiceSums} loading={loading} error={error} detailTx={detailTx} setDetailTx={setDetailTx} fmt={fmt} handleExport={handleExport} debugMode={debugMode} />
      </>}
    </div>
    </ErrorBoundary>
  )
}
