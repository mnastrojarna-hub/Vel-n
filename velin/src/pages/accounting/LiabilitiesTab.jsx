import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Card from '../../components/ui/Card'
import Modal from '../../components/ui/Modal'
import Pagination from '../../components/ui/Pagination'
import { useDebugMode } from '../../hooks/useDebugMode'

const PER_PAGE = 25

const LIABILITY_TYPES = [
  { value: 'supplier', label: 'Dodavatele' },
  { value: 'tax', label: 'Dane a poplatky' },
  { value: 'social', label: 'Socialni pojisteni' },
  { value: 'health', label: 'Zdravotni pojisteni' },
  { value: 'salary', label: 'Mzdy zamestnancu' },
  { value: 'loan', label: 'Uvery a pujcky' },
  { value: 'other', label: 'Ostatni' },
]

const STATUS_OPTIONS = [
  { value: 'pending', label: 'Neuhrazeno' },
  { value: 'partial', label: 'Castecne' },
  { value: 'paid', label: 'Uhrazeno' },
  { value: 'overdue', label: 'Po splatnosti' },
]

export default function LiabilitiesTab() {
  const debugMode = useDebugMode()
  const [liabilities, setLiabilities] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [detail, setDetail] = useState(null)
  const [filters, setFilters] = useState({ type: '', status: '' })
  const [summary, setSummary] = useState({ total: 0, overdue: 0, byType: {} })

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase.from('acc_liabilities').select('*', { count: 'exact' })
        .order('due_date', { ascending: true })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      if (filters.type) query = query.eq('type', filters.type)
      if (filters.status) query = query.eq('status', filters.status)

      const { data, count, error: err } = await debugAction('liabilities.list', 'LiabilitiesTab', () => query)
      if (err) throw err
      setLiabilities(data || [])
      setTotal(count || 0)

      // Auto-detect overdue
      const today = new Date().toISOString().slice(0, 10)
      for (const l of (data || [])) {
        if (l.status === 'pending' && l.due_date && l.due_date < today) {
          await supabase.from('acc_liabilities').update({ status: 'overdue' }).eq('id', l.id)
        }
      }

      // Summary
      const { data: all } = await supabase.from('acc_liabilities').select('type, amount, paid_amount, status')
        .in('status', ['pending', 'partial', 'overdue'])
      const byType = {}
      let totalOwed = 0
      let totalOverdue = 0
      for (const l of (all || [])) {
        const remaining = (l.amount || 0) - (l.paid_amount || 0)
        totalOwed += remaining
        if (l.status === 'overdue') totalOverdue += remaining
        byType[l.type] = (byType[l.type] || 0) + remaining
      }
      setSummary({ total: totalOwed, overdue: totalOverdue, byType })
    } catch (e) {
      debugError('LiabilitiesTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function markPaid(id, amount) {
    const liability = liabilities.find(l => l.id === id)
    if (!liability) return

    const newPaid = (liability.paid_amount || 0) + amount
    const status = newPaid >= liability.amount ? 'paid' : 'partial'

    await supabase.from('acc_liabilities').update({
      paid_amount: newPaid,
      status,
      paid_date: status === 'paid' ? new Date().toISOString().slice(0, 10) : null,
    }).eq('id', id)

    // Auto accounting entry
    await supabase.from('accounting_entries').insert({
      type: 'expense',
      amount,
      description: `Uhrada zavazku: ${liability.description || liability.counterparty}`,
      category: 'zavazky',
      date: new Date().toISOString().slice(0, 10),
    })

    await load()
  }

  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kc'
  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <Button green onClick={() => setShowAdd(true)}>+ Novy zavazek</Button>
        <select value={filters.type} onChange={e => { setPage(1); setFilters(f => ({ ...f, type: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="">Vsechny typy</option>
          {LIABILITY_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
        <select value={filters.status} onChange={e => { setPage(1); setFilters(f => ({ ...f, status: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="">Vsechny stavy</option>
          {STATUS_OPTIONS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Summary */}
      <div className="grid grid-cols-4 gap-3 mb-4">
        <MiniStat label="Neuhrazeno celkem" value={fmt(summary.total)} color="#dc2626" />
        <MiniStat label="Po splatnosti" value={fmt(summary.overdue)} color="#b45309" />
        {Object.entries(summary.byType).slice(0, 2).map(([type, val]) => (
          <MiniStat key={type} label={LIABILITY_TYPES.find(t => t.value === type)?.label || type} value={fmt(val)} color="#6b7280" />
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Protistrana</TH><TH>Typ</TH><TH>Popis</TH><TH>Castka</TH>
                <TH>Uhrazeno</TH><TH>Zbyva</TH><TH>Splatnost</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {liabilities.map(l => {
                const remaining = (l.amount || 0) - (l.paid_amount || 0)
                const isOverdue = l.status === 'overdue'
                return (
                  <TRow key={l.id}>
                    <TD bold>{l.counterparty || '—'}</TD>
                    <TD>{LIABILITY_TYPES.find(t => t.value === l.type)?.label || l.type}</TD>
                    <TD>{l.description || '—'}</TD>
                    <TD bold>{fmt(l.amount)}</TD>
                    <TD color="#1a8a18">{fmt(l.paid_amount)}</TD>
                    <TD bold color={isOverdue ? '#dc2626' : '#b45309'}>{fmt(remaining)}</TD>
                    <TD>
                      <span style={{ color: isOverdue ? '#dc2626' : '#1a2e22', fontWeight: isOverdue ? 800 : 400 }}>
                        {l.due_date ? new Date(l.due_date).toLocaleDateString('cs-CZ') : '—'}
                      </span>
                    </TD>
                    <TD>
                      <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                        style={{
                          padding: '4px 10px',
                          background: l.status === 'paid' ? '#dcfce7' : l.status === 'overdue' ? '#fee2e2' : l.status === 'partial' ? '#fef3c7' : '#f3f4f6',
                          color: l.status === 'paid' ? '#1a8a18' : l.status === 'overdue' ? '#dc2626' : l.status === 'partial' ? '#b45309' : '#6b7280',
                        }}>
                        {STATUS_OPTIONS.find(s => s.value === l.status)?.label || l.status}
                      </span>
                    </TD>
                    <TD>
                      <div className="flex gap-1">
                        <button onClick={() => setDetail(l)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#2563eb' }}>Detail</button>
                        {l.status !== 'paid' && (
                          <button onClick={() => markPaid(l.id, remaining)} className="text-sm font-bold cursor-pointer bg-transparent border-none" style={{ color: '#1a8a18' }}>Uhradit</button>
                        )}
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {liabilities.length === 0 && <TRow><TD>Zadne zavazky</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {showAdd && <AddLiabilityModal onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {detail && (
        <Modal open title={`Zavazek: ${detail.counterparty || detail.description}`} onClose={() => setDetail(null)}>
          <div className="grid grid-cols-2 gap-4">
            <DetailRow label="Protistrana" value={detail.counterparty} />
            <DetailRow label="Typ" value={LIABILITY_TYPES.find(t => t.value === detail.type)?.label || detail.type} />
            <DetailRow label="Castka" value={fmt(detail.amount)} />
            <DetailRow label="Uhrazeno" value={fmt(detail.paid_amount)} />
            <DetailRow label="Zbyva" value={fmt((detail.amount || 0) - (detail.paid_amount || 0))} />
            <DetailRow label="Splatnost" value={detail.due_date ? new Date(detail.due_date).toLocaleDateString('cs-CZ') : '—'} />
            <DetailRow label="Var. symbol" value={detail.variable_symbol || '—'} />
            <DetailRow label="Stav" value={STATUS_OPTIONS.find(s => s.value === detail.status)?.label || detail.status} />
            {detail.description && <div className="col-span-2"><DetailRow label="Popis" value={detail.description} /></div>}
            {detail.invoice_number && <DetailRow label="Cislo faktury" value={detail.invoice_number} />}
            {detail.paid_date && <DetailRow label="Datum uhrazeni" value={new Date(detail.paid_date).toLocaleDateString('cs-CZ')} />}
            {detail.financial_event_id && <DetailRow label="Financni udalost" value={detail.financial_event_id.slice(0, 8)} />}
          </div>
          <div className="flex justify-end mt-5"><Button onClick={() => setDetail(null)}>Zavrit</Button></div>
        </Modal>
      )}
    </div>
  )
}

function AddLiabilityModal({ onClose, onSaved }) {
  const [form, setForm] = useState({
    counterparty: '', type: 'supplier', amount: '', due_date: '', description: '',
    variable_symbol: '', invoice_number: '',
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { error } = await supabase.from('acc_liabilities').insert({
        counterparty: form.counterparty,
        type: form.type,
        amount: Number(form.amount) || 0,
        paid_amount: 0,
        due_date: form.due_date || null,
        description: form.description || null,
        variable_symbol: form.variable_symbol || null,
        invoice_number: form.invoice_number || null,
        status: 'pending',
      })
      if (error) throw error
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title="Novy zavazek" onClose={onClose}>
      <div className="space-y-3">
        <div><Label>Protistrana (dodavatel)</Label><input type="text" value={form.counterparty} onChange={e => set('counterparty', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Typ</Label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            {LIABILITY_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select>
        </div>
        <div><Label>Castka (Kc)</Label><input type="number" value={form.amount} onChange={e => set('amount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Datum splatnosti</Label><input type="date" value={form.due_date} onChange={e => set('due_date', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Variabilni symbol</Label><input type="text" value={form.variable_symbol} onChange={e => set('variable_symbol', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Cislo faktury</Label><input type="text" value={form.invoice_number} onChange={e => set('invoice_number', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Popis</Label><textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60 }} /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrusit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.amount}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
      </div>
    </Modal>
  )
}

function DetailRow({ label, value }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-semibold" style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function MiniStat({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
