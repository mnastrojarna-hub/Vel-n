import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { findCustomerReturnCodes, resolveCodeOwners } from '../lib/promoOwners'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import BulkActionsBar, { SelectAllCheckbox, RowCheckbox } from '../components/ui/BulkActionsBar'
import { bulkUpdate, bulkDelete, exportToCsv } from '../lib/bulkActions'
import { PromoModal, PromoDetailModal } from './PromoCodesModals'

const PER_PAGE = 25

// Slevomat je u nás VŽDY voucher (tabulka vouchers, source='slevomat') — nikdy
// promo kód. Zdroj 'slevomat' proto patří jen do dárkových poukazů, ne sem.
const SOURCE_OPTIONS = [
  { value: 'eshop', label: 'E-shop' },
  { value: 'spoluprace', label: 'Spolupráce' },
  { value: 'vraceni', label: 'Vrácení' },
  { value: 'ostatni', label: 'Ostatní' },
]

const SORT_OPTIONS = [
  { value: 'created_at', label: 'Vytvořeno' },
  { value: 'valid_to', label: 'Platnost' },
  { value: 'value', label: 'Výše slevy / %' },
  { value: 'used_count', label: 'Počet použití' },
]

export default function PromoCodes() {
  const debugMode = useDebugMode()
  const navigate = useNavigate()
  const [codes, setCodes] = useState([])
  const [owners, setOwners] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { statuses: [], redeemed: [], types: [], sources: [], search: '', customer: '', sortBy: 'created_at', sortDir: 'desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_promo_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_promo_filters', JSON.stringify(filters)) }, [filters])
  const [summary, setSummary] = useState({ total: 0, active: 0, inactive: 0, expired: 0, totalUsed: 0, totalValue: 0 })
  const [showModal, setShowModal] = useState(false)
  const [editCode, setEditCode] = useState(null)
  const [detailCode, setDetailCode] = useState(null)
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [selectedIds, setSelectedIds] = useState(new Set())

  useEffect(() => { loadCodes() }, [page, filters])
  useEffect(() => { autoExpirePromos(); loadSummary() }, [])

  async function autoExpirePromos() {
    try {
      await supabase.from('promo_codes')
        .update({ active: false })
        .eq('active', true)
        .lt('valid_to', new Date().toISOString().slice(0, 10))
    } catch (e) { console.warn('Auto-expire promos error:', e) }
  }

  async function loadCodes() {
    setLoading(true)
    setError(null)
    try {
      const sortBy = SORT_OPTIONS.some(o => o.value === filters.sortBy) ? filters.sortBy : 'created_at'

      // Filtr dle zákazníka: kódy z vrácení (VRACENI-*) náležící jeho rezervacím
      let customerCodes = null
      if (filters.customer?.trim()) {
        customerCodes = await findCustomerReturnCodes(filters.customer)
        if (customerCodes !== null && customerCodes.length === 0) {
          setCodes([]); setOwners({}); setTotal(0); setLoading(false)
          return
        }
      }

      let query = supabase
        .from('promo_codes')
        .select('*', { count: 'exact' })
        .order(sortBy, { ascending: filters.sortDir === 'asc', nullsFirst: false })

      if (filters.statuses?.length > 0) {
        if (filters.statuses.includes('active') && !filters.statuses.includes('inactive') && !filters.statuses.includes('expired')) {
          query = query.eq('active', true)
        } else if (filters.statuses.includes('inactive') && !filters.statuses.includes('active') && !filters.statuses.includes('expired')) {
          query = query.eq('active', false)
        } else if (filters.statuses.includes('expired') && !filters.statuses.includes('active') && !filters.statuses.includes('inactive')) {
          query = query.lt('valid_to', new Date().toISOString().split('T')[0])
        }
      } else if (filters.status === 'active') query = query.eq('active', true)
      else if (filters.status === 'inactive') query = query.eq('active', false)
      else if (filters.status === 'expired') {
        query = query.lt('valid_to', new Date().toISOString().split('T')[0])
      }

      // Uplatnění (počet použití)
      if (filters.redeemed?.length === 1) {
        if (filters.redeemed.includes('redeemed')) query = query.gt('used_count', 0)
        else if (filters.redeemed.includes('unredeemed')) query = query.eq('used_count', 0)
      }

      // Typ slevy: % vs. absolutní
      if (filters.types?.length > 0) query = query.in('type', filters.types)

      // Zdroj kódu
      if (filters.sources?.length > 0) {
        const named = filters.sources.filter(s => s !== 'ostatni')
        const orParts = []
        if (named.length) orParts.push(`source.in.(${named.join(',')})`)
        if (filters.sources.includes('ostatni')) { orParts.push('source.is.null'); orParts.push('source.eq.ostatni') }
        if (orParts.length) query = query.or(orParts.join(','))
      }

      if (filters.search) {
        query = query.ilike('code', `%${filters.search}%`)
      }

      if (customerCodes?.length) {
        query = query.in('code', customerCodes)
      }

      query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('loadCodes', 'PromoCodes', () => query, { page, filters })
      if (err) throw err
      setCodes(data || [])
      setTotal(count || 0)
      resolveCodeOwners(data || []).then(setOwners).catch(() => setOwners({}))
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadSummary() {
    try {
      const { data } = await supabase.from('promo_codes').select('active, used_count, value, type, valid_to')
      if (data) {
        const now = new Date()
        setSummary({
          total: data.length,
          active: data.filter(c => c.active && (!c.valid_to || new Date(c.valid_to) >= now)).length,
          inactive: data.filter(c => !c.active).length,
          expired: data.filter(c => c.valid_to && new Date(c.valid_to) < now).length,
          totalUsed: data.reduce((s, c) => s + (c.used_count || 0), 0),
        })
      }
    } catch {}
  }

  async function toggleStatus(code) {
    const newActive = !code.active
    const { error: err } = await debugAction('toggleStatus', 'PromoCodes', () => supabase.from('promo_codes').update({ active: newActive }).eq('id', code.id), { id: code.id, active: newActive })
    if (err) { setError(err.message); return }
    await logAudit(newActive ? 'promo_code_activated' : 'promo_code_deactivated', { code: code.code })
    setCodes(prev => prev.map(c => c.id === code.id ? { ...c, active: newActive } : c))
    loadSummary()
  }

  async function handleDelete(code) {
    const { error: err } = await debugAction('handleDelete', 'PromoCodes', () => supabase.from('promo_codes').delete().eq('id', code.id), { id: code.id, code: code.code })
    if (err) { setError(err.message); return }
    await logAudit('promo_code_deleted', { code: code.code })
    setDeleteConfirm(null)
    loadCodes()
    loadSummary()
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  function openEdit(code) {
    setEditCode(code)
    setShowModal(true)
    setDetailCode(null)
  }

  function openCreate() {
    setEditCode(null)
    setShowModal(true)
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  const ids = [...selectedIds]
  const bulkActions = [
    { label: 'Aktivovat', icon: '✓', onClick: async () => {
      await bulkUpdate('promo_codes', ids, { active: true }, 'promo_codes_bulk_activated')
      setSelectedIds(new Set()); loadCodes(); loadSummary()
    } },
    { label: 'Deaktivovat', icon: '⏸', onClick: async () => {
      await bulkUpdate('promo_codes', ids, { active: false }, 'promo_codes_bulk_deactivated')
      setSelectedIds(new Set()); loadCodes(); loadSummary()
    } },
    { label: 'Export CSV', icon: '⬇', onClick: () => exportToCsv('promo_codes', [
      { key: 'code', label: 'Kód' },
      { key: 'type', label: 'Typ' },
      { key: 'value', label: 'Sleva' },
      { key: 'active', label: 'Aktivní', format: v => v ? 'ANO' : 'NE' },
      { key: 'valid_from', label: 'Platnost od' },
      { key: 'valid_to', label: 'Platnost do' },
      { key: 'used_count', label: 'Použití' },
      { key: 'max_uses', label: 'Limit' },
      { key: 'created_at', label: 'Vytvořeno', format: v => v ? new Date(v).toLocaleString('cs-CZ') : '' },
    ], codes.filter(c => selectedIds.has(c.id))) },
    { label: 'Smazat', icon: '🗑', danger: true, confirm: 'Trvale smazat {count} promo kódů? Akci nelze vrátit.', onClick: async () => {
      await bulkDelete('promo_codes', ids, 'promo_codes_bulk_deleted')
      setSelectedIds(new Set()); loadCodes(); loadSummary()
    } },
  ]

  return (
    <div>
      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA PromoCodes</strong><br/>
        <div>codes: {codes.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>summary: total={summary.total}, active={summary.active}, inactive={summary.inactive}, expired={summary.expired}</div>
        <div>totalUsed: {summary.totalUsed}</div>
        <div>filtry: status={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}", zákazník="{filters.customer}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {/* Summary */}
      <div className="grid grid-cols-5 gap-3 mb-5">
        <SummaryCard label="Celkem kódů" value={summary.total} color="#0f1a14" />
        <SummaryCard label="Aktivní" value={summary.active} color="#1a8a18" />
        <SummaryCard label="Neaktivní" value={summary.inactive} color="#6b7280" />
        <SummaryCard label="Expirované" value={summary.expired} color="#dc2626" />
        <SummaryCard label="Celkem použití" value={summary.totalUsed} color="#2563eb" />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <SearchInput
          value={filters.search}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }}
          placeholder="Hledat kód…"
        />
        <SearchInput
          value={filters.customer}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, customer: v })) }}
          placeholder="Zákazník (kódy z vrácení)…"
        />
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, statuses: v })) }}
          options={[{ value: 'active', label: 'Aktivní' }, { value: 'inactive', label: 'Neaktivní' }, { value: 'expired', label: 'Expirované' }]} />
        <CheckboxFilterGroup label="Uplatnění" values={filters.redeemed || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, redeemed: v })) }}
          options={[{ value: 'redeemed', label: 'Uplatněné' }, { value: 'unredeemed', label: 'Neuplatněné' }]} />
        <CheckboxFilterGroup label="Typ slevy" values={filters.types || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, types: v })) }}
          options={[{ value: 'percent', label: '% sleva' }, { value: 'fixed', label: 'Absolutní sleva' }]} />
        <CheckboxFilterGroup label="Zdroj" values={filters.sources || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, sources: v })) }}
          options={SOURCE_OPTIONS} />
        <SortControl options={SORT_OPTIONS} sortBy={filters.sortBy} sortDir={filters.sortDir}
          onChange={(by, dir) => { setPage(1); setFilters(f => ({ ...f, sortBy: by, sortDir: dir })) }} />
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_promo_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
        <div className="ml-auto">
          <Button green onClick={openCreate}>+ Nový promo kód</Button>
        </div>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
          {error}
          <button onClick={loadCodes} className="ml-3 underline cursor-pointer">Zkusit znovu</button>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <BulkActionsBar count={selectedIds.size} onClear={() => setSelectedIds(new Set())} actions={bulkActions} />
          <Table>
            <thead>
              <TRow header>
                <TH><SelectAllCheckbox items={codes} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TH>
                <TH>Kód</TH><TH>Zákazník</TH><TH>Sleva</TH><TH>Platnost</TH>
                <TH>Použití / Limit</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {codes.map(c => {
                const isActive = c.active && (!c.valid_to || new Date(c.valid_to) >= new Date())
                const isExpired = c.valid_to && new Date(c.valid_to) < new Date()
                const isLimitReached = c.max_uses && (c.used_count || 0) >= c.max_uses
                return (
                  <tr key={c.id} style={{ borderBottom: '1px solid #d4e8e0', background: selectedIds.has(c.id) ? '#fef9c3' : undefined }}>
                    <TD><RowCheckbox id={c.id} selectedIds={selectedIds} setSelectedIds={setSelectedIds} /></TD>
                    <TD>
                      <button
                        onClick={() => setDetailCode(c)}
                        className="font-mono font-bold text-sm cursor-pointer"
                        style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}
                      >
                        {c.code}
                      </button>
                    </TD>
                    <TD>
                      {owners[c.code] ? (
                        <button
                          onClick={() => navigate(`/zakaznici/${owners[c.code].userId}`)}
                          className="text-sm font-bold cursor-pointer"
                          style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}
                          title="Detail zákazníka"
                        >
                          {owners[c.code].name || 'Zákazník'}
                        </button>
                      ) : <span className="text-sm" style={{ color: '#6b7280' }}>—</span>}
                    </TD>
                    <TD bold>
                      {c.type === 'percent'
                        ? `${c.value}%`
                        : `${(c.value || 0).toLocaleString('cs-CZ')} Kč`
                      }
                    </TD>
                    <TD>
                      <span className="text-sm">
                        {c.valid_from ? new Date(c.valid_from).toLocaleDateString('cs-CZ') : '—'}
                        {' → '}
                        {c.valid_to ? (
                          <span style={{ color: isExpired ? '#dc2626' : undefined, fontWeight: isExpired ? 700 : undefined }}>
                            {new Date(c.valid_to).toLocaleDateString('cs-CZ')}
                          </span>
                        ) : '∞'}
                      </span>
                    </TD>
                    <TD>
                      <span style={{ color: isLimitReached ? '#dc2626' : undefined, fontWeight: isLimitReached ? 700 : undefined }}>
                        {c.used_count ?? 0} / {c.max_uses ?? '∞'}
                      </span>
                      {isLimitReached && <span className="text-sm ml-1" style={{ color: '#dc2626' }}>(vyčerpáno)</span>}
                    </TD>
                    <TD>
                      <button
                        onClick={() => toggleStatus(c)}
                        className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase cursor-pointer"
                        style={{
                          padding: '4px 10px',
                          background: isActive ? '#dcfce7' : isExpired ? '#fee2e2' : '#f3f4f6',
                          color: isActive ? '#1a8a18' : isExpired ? '#dc2626' : '#6b7280',
                          border: 'none',
                        }}
                        title={isExpired ? 'Expirovaný' : isActive ? 'Klikni pro deaktivaci' : 'Klikni pro aktivaci'}
                      >
                        {isExpired ? 'Expirovaný' : isActive ? 'Aktivní' : 'Neaktivní'}
                      </button>
                    </TD>
                    <TD>
                      <div className="flex gap-1">
                        <ActionBtn color="#2563eb" onClick={() => openEdit(c)}>Upravit</ActionBtn>
                        <ActionBtn color="#b45309" onClick={() => toggleStatus(c)}>
                          {c.active ? 'Deaktivovat' : 'Aktivovat'}
                        </ActionBtn>
                        <ActionBtn color="#dc2626" onClick={() => setDeleteConfirm(c)}>Smazat</ActionBtn>
                      </div>
                    </TD>
                  </tr>
                )
              })}
              {codes.length === 0 && <TRow><TD colSpan={8}>Žádné promo kódy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Detail panel */}
      {detailCode && (
        <PromoDetailModal code={detailCode} owner={owners[detailCode.code]} onClose={() => setDetailCode(null)} onEdit={() => openEdit(detailCode)} />
      )}

      {/* Create/Edit modal */}
      {showModal && (
        <PromoModal
          existing={editCode}
          onClose={() => { setShowModal(false); setEditCode(null) }}
          onSaved={() => { setShowModal(false); setEditCode(null); loadCodes(); loadSummary() }}
        />
      )}

      {/* Delete confirm */}
      {deleteConfirm && (
        <ConfirmDialog
          open
          title="Smazat promo kód?"
          message={`Opravdu chcete trvale smazat promo kód "${deleteConfirm.code}"? Tuto akci nelze vrátit.`}
          danger
          onConfirm={() => handleDelete(deleteConfirm)}
          onCancel={() => setDeleteConfirm(null)}
        />
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

function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

function ActionBtn({ children, color, onClick }) {
  return (
    <button
      onClick={onClick}
      className="text-sm font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}
    >
      {children}
    </button>
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

function FilterSelect({ value, onChange, options }) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
      style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  )
}

function SortControl({ options, sortBy, sortDir, onChange }) {
  const by = options.some(o => o.value === sortBy) ? sortBy : options[0].value
  const dir = sortDir === 'asc' ? 'asc' : 'desc'
  return (
    <div className="flex items-center gap-1 rounded-btn"
      style={{ padding: '4px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>Řadit:</span>
      <select value={by} onChange={e => onChange(e.target.value, dir)}
        className="rounded-btn text-sm font-bold cursor-pointer outline-none"
        style={{ padding: '4px 8px', background: '#fff', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
      <button onClick={() => onChange(by, dir === 'asc' ? 'desc' : 'asc')}
        className="rounded-btn text-sm font-extrabold cursor-pointer"
        title={dir === 'asc' ? 'Vzestupně (klikni pro sestupně)' : 'Sestupně (klikni pro vzestupně)'}
        style={{ padding: '4px 10px', background: '#74FB71', border: 'none', color: '#1a2e22' }}>
        {dir === 'asc' ? '↑ Vzestupně' : '↓ Sestupně'}
      </button>
    </div>
  )
}

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
