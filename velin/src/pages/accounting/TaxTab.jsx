import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'

const STATUS_OPTIONS = [
  { value: 'submitted', label: 'Odesláno' },
  { value: 'prepared', label: 'Připraveno' },
]

export default function TaxTab() {
  const [records, setRecords] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [generating, setGenerating] = useState(false)
  const defaultFilters = { search: '', statuses: [], sort: 'date_desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_tax_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_tax_filters', JSON.stringify(filters)) }, [filters])

  useEffect(() => { load() }, [filters])

  async function load() {
    setLoading(true)
    debugLog('TaxTab', 'load', { sort: filters.sort })
    const { data, error: err } = await debugAction('tax_records.list', 'TaxTab', () =>
      supabase
        .from('tax_records')
        .select('*')
        .order(filters.sort.startsWith('amount') ? 'total' : 'period_to', { ascending: filters.sort.endsWith('_asc') })
    )
    if (err) { debugError('TaxTab', 'load', err); setError(err.message) }
    else setRecords(data || [])
    setLoading(false)
  }

  async function generateTax(period) {
    setGenerating(true)
    setError(null)
    try {
      debugLog('TaxTab', 'generateTax', { period })
      const { data, error } = await debugAction('functions.generate-tax', 'TaxTab', () =>
        supabase.functions.invoke('generate-tax', {
          body: { period, type: 'vat_summary' },
        })
      )
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
      await load()
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'tax_generated', details: { period },
      })
    } catch (e) {
      debugError('TaxTab', 'generateTax', e)
      setError('Generování selhalo: ' + e.message)
    } finally {
      setGenerating(false)
    }
  }

  async function handleExport(format) {
    try {
      debugLog('TaxTab', 'handleExport', { format })
      const { data, error } = await debugAction('functions.export-data', 'TaxTab', () =>
        supabase.functions.invoke('export-data', {
          body: { type: 'tax_records', format },
        })
      )
      if (error) throw error
      if (data?.url) window.open(data.url, '_blank')
    } catch (e) {
      debugError('TaxTab', 'handleExport', e)
      setError('Export selhal: ' + e.message)
    }
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
  const now = new Date()
  const currentQ = `${now.getFullYear()}-Q${Math.ceil((now.getMonth() + 1) / 3)}`

  const filtered = records.filter(r => {
    if (filters.statuses?.length > 0 && !filters.statuses.includes(r.status)) return false
    if (filters.search) {
      const s = filters.search.toLowerCase()
      if (!(r.period_to || '').toLowerCase().includes(s) && !(r.type || '').toLowerCase().includes(s)) return false
    }
    return true
  })

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Button green onClick={() => generateTax(currentQ)} disabled={generating}>
          {generating ? 'Generuji…' : `Generovat DPH ${currentQ}`}
        </Button>
        <input type="text" value={filters.search} onChange={e => setFilters(f => ({ ...f, search: e.target.value }))}
          placeholder="Hledat období, typ…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 150 }} />
        <select value={filters.sort} onChange={e => setFilters(f => ({ ...f, sort: e.target.value }))}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Období ↓ nejnovější</option>
          <option value="date_asc">Období ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => setFilters(f => ({ ...f, statuses: v }))}
          options={STATUS_OPTIONS} />
        <button onClick={() => { setFilters({ ...defaultFilters }); localStorage.removeItem('velin_tax_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto flex gap-2">
          <Button onClick={() => handleExport('csv')}>CSV</Button>
          <Button onClick={() => handleExport('xlsx')}>XLSX</Button>
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA TaxTab</strong><br/>
        <div>records: {filtered.length} zobrazeno / {records.length} celkem</div>
        <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, sort={filters.sort}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : filtered.length === 0 ? (
        <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné daňové záznamy</p></Card>
      ) : (
        <Table>
          <thead>
            <TRow header>
              <TH>Období</TH><TH>Typ</TH><TH>Základ daně</TH>
              <TH>DPH</TH><TH>Celkem</TH><TH>Stav</TH>
            </TRow>
          </thead>
          <tbody>
            {filtered.map(r => (
              <TRow key={r.id}>
                <TD bold>{r.period_from && r.period_to ? `${r.period_from} — ${r.period_to}` : r.period_to || '—'}</TD>
                <TD>{r.type || '—'}</TD>
                <TD>{fmt(r.tax_base)}</TD>
                <TD bold>{fmt(r.vat_amount)}</TD>
                <TD bold>{fmt(r.total)}</TD>
                <TD>
                  <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                    style={{
                      padding: '4px 10px',
                      background: r.status === 'submitted' ? '#dcfce7' : '#fef3c7',
                      color: r.status === 'submitted' ? '#1a8a18' : '#b45309',
                    }}>
                    {r.status === 'submitted' ? 'Odesláno' : 'Připraveno'}
                  </span>
                </TD>
              </TRow>
            ))}
          </tbody>
        </Table>
      )}
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
