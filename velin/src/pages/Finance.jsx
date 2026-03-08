import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Modal from '../components/ui/Modal'
import { Table, TRow, TH, TD } from '../components/ui/Table'

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

export default function Finance() {
  const [summary, setSummary] = useState({ revenue: 0, expense: 0, unpaid: 0 })
  const [transactions, setTransactions] = useState([])
  const [chartData, setChartData] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [filters, setFilters] = useState({ period: 'month', type: '', category: '', search: '' })
  const [categories, setCategories] = useState([])
  const [detailTx, setDetailTx] = useState(null)

  useEffect(() => { loadData() }, [filters])

  async function loadData() {
    setLoading(true)
    setError(null)
    try {
      await Promise.all([loadSummary(), loadTransactions(), loadChart()])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
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
      .eq('status', 'unpaid')
    if (inv) {
      setSummary(s => ({ ...s, unpaid: inv.reduce((sum, i) => sum + (i.total || 0), 0) }))
    }
  }

  async function loadTransactions() {
    let query = supabase
      .from('accounting_entries')
      .select('*')
      .order('date', { ascending: false })
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
    if (filters.type) {
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
      <div className="flex flex-wrap items-center gap-3 mb-5">
        {PERIODS.map(p => (
          <button key={p.value} onClick={() => setFilters(f => ({ ...f, period: p.value }))}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 16px', background: filters.period === p.value ? '#74FB71' : '#f1faf7', color: filters.period === p.value ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: filters.period === p.value ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {p.label}
          </button>
        ))}
        <select value={filters.type} onChange={e => setFilters(f => ({ ...f, type: e.target.value }))}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
          {TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
        {categories.length > 0 && (
          <select value={filters.category} onChange={e => setFilters(f => ({ ...f, category: e.target.value }))}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
            style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
            <option value="">Všechny kategorie</option>
            {categories.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        )}
        <input type="text" value={filters.search} onChange={e => setFilters(f => ({ ...f, search: e.target.value }))}
          placeholder="Hledat popis…"
          className="rounded-btn text-xs outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357', minWidth: 150 }} />
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
              <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Tržby vs. náklady (12 měsíců)</h3>
              <div className="flex items-end gap-1" style={{ height: 120 }}>
                {chartData.map((m, i) => {
                  const max = Math.max(...chartData.map(c => Math.max(c.revenue, c.expense)), 1)
                  return (
                    <div key={i} className="flex-1 flex flex-col items-center gap-0.5">
                      <div className="w-full flex gap-0.5" style={{ height: 100 }}>
                        <div className="flex-1 rounded-t" style={{ background: '#74FB71', height: `${(m.revenue / max) * 100}%`, marginTop: 'auto' }} />
                        <div className="flex-1 rounded-t" style={{ background: '#fee2e2', height: `${(m.expense / max) * 100}%`, marginTop: 'auto' }} />
                      </div>
                      <span className="text-[8px] font-bold" style={{ color: '#8aab99' }}>{m.label}</span>
                    </div>
                  )
                })}
              </div>
            </Card>
          )}

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
                  <TD mono>{t.booking_id ? t.booking_id.slice(0, 8) : '—'}</TD>
                </tr>
              ))}
              {transactions.length === 0 && <TRow><TD>Žádné transakce</TD></TRow>}
            </tbody>
          </Table>
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
    </div>
  )
}

function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-[10px] font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#8aab99' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
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

function TypeBadge({ type }) {
  const isRev = type === 'revenue'
  return (
    <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
      style={{ padding: '4px 10px', background: isRev ? '#dcfce7' : '#fee2e2', color: isRev ? '#1a8a18' : '#dc2626' }}>
      {isRev ? 'Příjem' : 'Výdaj'}
    </span>
  )
}
