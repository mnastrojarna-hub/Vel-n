import { useState, useEffect } from 'react'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'
import { exportToCsv, bulkDelete } from '../../lib/bulkActions'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'

const PER_PAGE = 25
const defaultFilters = { search: '', types: [], sort: 'date_desc' }

export default function CashRegisterTab() {
  const debugMode = useDebugMode()
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [selectedIds, setSelectedIds] = useState(new Set())
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_cashregister_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })

  useEffect(() => {
    localStorage.setItem('velin_cashregister_filters', JSON.stringify(filters))
  }, [filters])

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('CashRegisterTab', 'load', { page, filters })
      const { data, count, error: err } = await debugAction('cash_register.list', 'CashRegisterTab', () =>
        supabase
          .from('cash_register')
          .select('*', { count: 'exact' })
          .order(filters.sort.startsWith('amount') ? 'amount' : 'date', { ascending: filters.sort.endsWith('_asc') })
          .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      )
      if (err) throw err
      let filtered = data || []
      setEntries(filtered)
      setTotal(count || 0)
    } catch (e) {
      debugError('CashRegisterTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <input type="text" value={filters.search} onChange={e => { setPage(1); setFilters(f => ({ ...f, search: e.target.value })) }}
          placeholder="Hledat popis…"
          className="rounded-btn text-sm outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', minWidth: 180 }} />
        <CheckboxFilterGroup label="Typ" values={filters.types || []} onChange={v => { setPage(1); setFilters(f => ({ ...f, types: v })) }}
          options={[{ value: 'income', label: 'Příjem' }, { value: 'expense', label: 'Výdej' }]} />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
          <option value="amount_desc">Částka ↓ nejvyšší</option>
          <option value="amount_asc">Částka ↑ nejnižší</option>
        </select>
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_cashregister_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>Reset</button>
        <div className="ml-auto">
          <Button green onClick={() => setShowAdd(true)}>+ Nový záznam</Button>
        </div>
      </div>

      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA CashRegisterTab</strong><br/>
        <div>entries: {entries.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: types={filters.types?.length > 0 ? filters.types.join(',') : 'vše'}, sort={filters.sort}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={[
            { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('cash-register', [
              { key: 'date', label: 'Datum' }, { key: 'type', label: 'Typ' },
              { key: 'description', label: 'Popis' }, { key: 'amount', label: 'Částka' }, { key: 'balance', label: 'Zůstatek' },
            ], entries.filter(e => selectedIds.has(e.id))) },
            { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} pokladních záznamů?', onClick: async () => { await bulkDelete('cash_register', [...selectedIds], 'cash_register_bulk_deleted'); setSelectedIds(new Set()); load() } },
          ]} />
          <Table>
            <thead>
              <TRow header>
                <TH><SelectAllCheckbox items={entries} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
                <TH>Datum</TH><TH>Typ</TH><TH>Popis</TH><TH>Částka</TH><TH>Zůstatek</TH>
              </TRow>
            </thead>
            <tbody>
              {entries.filter(e => {
                if (filters.types?.length > 0 && !filters.types.includes(e.type)) return false
                if (filters.search && !(e.description || '').toLowerCase().includes(filters.search.toLowerCase())) return false
                return true
              }).map(e => (
                <TRow key={e.id}>
                  <TD><RowCheckbox id={e.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TD>
                  <TD>{e.date ? new Date(e.date).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                      style={{
                        padding: '4px 10px',
                        background: e.type === 'income' ? '#dcfce7' : '#fee2e2',
                        color: e.type === 'income' ? '#1a8a18' : '#dc2626',
                      }}>
                      {e.type === 'income' ? 'Příjem' : 'Výdej'}
                    </span>
                  </TD>
                  <TD>{e.description || '—'}</TD>
                  <TD bold color={e.type === 'income' ? '#1a8a18' : '#dc2626'}>{fmt(e.amount)}</TD>
                  <TD bold>{fmt(e.balance)}</TD>
                </TRow>
              ))}
              {entries.length === 0 && <TRow><TD>Žádné záznamy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddCashModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
    </div>
  )
}

function AddCashModal({ onClose, onSaved }) {
  const [form, setForm] = useState({ type: 'income', amount: '', description: '' })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      debugLog('CashRegisterTab', 'handleSave', { type: form.type, amount: form.amount })
      const { error } = await debugAction('cash_register.insert', 'CashRegisterTab', () =>
        supabase.from('cash_register').insert({
          type: form.type,
          amount: Number(form.amount) || 0,
          description: form.description,
          date: new Date().toISOString().slice(0, 10),
        })
      )
      if (error) throw error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'cash_register_entry', details: { type: form.type },
      })
      onSaved()
    } catch (e) { debugError('CashRegisterTab', 'handleSave', e); setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Nový pokladní záznam" onClose={onClose}>
      <div className="space-y-3">
        <div>
          <Label>Typ</Label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="income">Příjem</option>
            <option value="expense">Výdej</option>
          </select>
        </div>
        <div>
          <Label>Částka (Kč)</Label>
          <input type="number" value={form.amount} onChange={e => set('amount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Popis</Label>
          <input type="text" value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.amount}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
      </div>
    </Modal>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
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
