import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'

const PER_PAGE = 25
const LS_KEY = 'velin_received_invoices_filters'

const STATUS_MAP = {
  draft: { label: 'Koncept', color: '#1a2e22', bg: '#f3f4f6' },
  issued: { label: 'Přijata', color: '#b45309', bg: '#fef3c7' },
  paid: { label: 'Zaplacena', color: '#1a8a18', bg: '#dcfce7' },
  cancelled: { label: 'Stornována', color: '#dc2626', bg: '#fee2e2' },
}

const STATUS_OPTIONS = [
  { value: 'issued', label: 'Přijata' },
  { value: 'paid', label: 'Zaplacena' },
  { value: 'cancelled', label: 'Stornována' },
]

const defaultFilters = { search: '', statuses: [], sort: 'date_desc' }

function loadFilters() {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      return { ...defaultFilters, ...parsed }
    }
  } catch { /* ignore */ }
  return { ...defaultFilters }
}

export default function ReceivedInvoicesTab() {
  const debugMode = useDebugMode()
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState(loadFilters)
  const [showAdd, setShowAdd] = useState(false)
  const [detail, setDetail] = useState(null)

  useEffect(() => {
    try { localStorage.setItem(LS_KEY, JSON.stringify(filters)) } catch { /* ignore */ }
  }, [filters])

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true); setError(null)
    try {
      debugLog('ReceivedInvoicesTab', 'load', { page, filters })
      let query = supabase
        .from('invoices')
        .select('*, profiles:customer_id(full_name)', { count: 'exact' })
        .eq('type', 'received')
      if (filters.search) query = query.or(`number.ilike.%${filters.search}%,notes.ilike.%${filters.search}%`)
      if (filters.statuses?.length > 0) query = query.in('status', filters.statuses)
      query = query.order(filters.sort.startsWith('amount') ? 'total' : 'issue_date', { ascending: filters.sort.endsWith('_asc'), nullsFirst: false })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('invoices.received.list', 'ReceivedInvoicesTab', () => query)
      if (err) throw err
      setInvoices(data || [])
      setTotal(count || 0)
    } catch (e) { debugError('ReceivedInvoicesTab', 'load', e); setError(e.message) }
    setLoading(false)
  }

  async function markPaid(inv) {
    try {
      const { error: err } = await supabase.from('invoices')
        .update({ status: 'paid', paid_date: new Date().toISOString().slice(0, 10) })
        .eq('id', inv.id)
      if (err) throw err
      load()
    } catch (e) { setError(e.message) }
  }

  function handleReset() {
    setPage(1)
    setFilters({ ...defaultFilters })
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'
  const hasActiveFilters = filters.search || filters.statuses.length > 0 || filters.sort !== 'date_desc'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat číslo, dodavatele…" />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        {hasActiveFilters && (
          <button onClick={handleReset}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Resetovat filtry
          </button>
        )}
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nová přijatá faktura</Button>
        </div>
      </div>

      <CheckboxFilterGroup
        label="Stav"
        options={STATUS_OPTIONS}
        selected={filters.statuses}
        onChange={statuses => { setPage(1); setFilters(f => ({ ...f, statuses })) }}
      />

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <details className="mb-4">
        <summary className="text-xs font-bold uppercase tracking-wide cursor-pointer" style={{ color: '#6b7280' }}>Diagnostika filtrů</summary>
        <div className="mt-1 p-3 rounded-card text-xs font-mono" style={{ background: '#f9fafb', border: '1px solid #e5e7eb', color: '#374151' }}>
          <div><strong>search:</strong> {JSON.stringify(filters.search)}</div>
          <div><strong>statuses:</strong> {JSON.stringify(filters.statuses)}</div>
          <div><strong>sort:</strong> {JSON.stringify(filters.sort)}</div>
        </div>
      </details>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Číslo</TH><TH>Dodavatel</TH><TH>Popis</TH><TH>Částka</TH>
                <TH>Datum</TH><TH>Splatnost</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {invoices.map(inv => {
                const st = STATUS_MAP[inv.status] || STATUS_MAP.draft
                return (
                  <TRow key={inv.id}>
                    <TD mono bold>{inv.number || '—'}</TD>
                    <TD>{inv.notes?.split('\n')[0] || inv.profiles?.full_name || '—'}</TD>
                    <TD>{inv.notes || '—'}</TD>
                    <TD bold>{fmt(inv.total)}</TD>
                    <TD>{inv.issue_date ? new Date(inv.issue_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>{inv.due_date ? new Date(inv.due_date).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                    <TD>
                      <div className="flex gap-1">
                        {inv.status !== 'paid' && (
                          <button onClick={() => markPaid(inv)} className="text-sm font-bold cursor-pointer"
                            style={{ color: '#1a8a18', background: 'none', border: 'none', padding: '4px 6px' }}>Zaplatit</button>
                        )}
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {invoices.length === 0 && <TRow><TD>Žádné přijaté faktury</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddReceivedModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
    </div>
  )
}

function AddReceivedModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ number: '', supplier: '', total: '', due_date: '', notes: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    if (!form.number || !form.total) return setErr('Vyplňte číslo faktury a částku.')
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('invoices').insert({
        number: form.number,
        type: 'received',
        total: Number(form.total) || 0,
        subtotal: Number(form.total) || 0,
        tax_amount: 0,
        issue_date: new Date().toISOString().slice(0, 10),
        due_date: form.due_date || null,
        notes: [form.supplier, form.notes].filter(Boolean).join('\n'),
        status: 'issued',
      })
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'received_invoice_created', details: { number: form.number },
      })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nová přijatá faktura" onClose={onClose}>
      <div className="space-y-3">
        <div>
          <Label>Číslo faktury *</Label>
          <input value={form.number} onChange={e => set('number', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="FV-2026-0001" />
        </div>
        <div>
          <Label>Dodavatel</Label>
          <input value={form.supplier} onChange={e => set('supplier', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Název dodavatele" />
        </div>
        <div>
          <Label>Částka (Kč) *</Label>
          <input type="number" value={form.total} onChange={e => set('total', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Splatnost</Label>
          <input type="date" value={form.due_date} onChange={e => set('due_date', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Poznámka</Label>
          <textarea value={form.notes} onChange={e => set('notes', e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }}
            placeholder="Popis, za co je faktura…" />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function CheckboxFilterGroup({ label, options, selected, onChange }) {
  function toggle(value) {
    if (selected.includes(value)) {
      onChange(selected.filter(v => v !== value))
    } else {
      onChange([...selected, value])
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-3 mb-4">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(opt => (
        <label key={opt.value} className="flex items-center gap-1.5 cursor-pointer text-sm" style={{ color: '#1a2e22' }}>
          <input
            type="checkbox"
            checked={selected.includes(opt.value)}
            onChange={() => toggle(opt.value)}
            className="cursor-pointer"
            style={{ accentColor: '#1a8a18' }}
          />
          {opt.label}
        </label>
      ))}
    </div>
  )
}
