import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import { useDebugMode } from '../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import SearchInput from '../components/ui/SearchInput'
import Pagination from '../components/ui/Pagination'
import Card from '../components/ui/Card'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import { PromoModal, PromoDetailModal } from './PromoCodesModals'

const PER_PAGE = 25

export default function PromoCodes() {
  const debugMode = useDebugMode()
  const [codes, setCodes] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { statuses: [], search: '' }
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
      let query = supabase
        .from('promo_codes')
        .select('*', { count: 'exact' })
        .order('created_at', { ascending: false })

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

      if (filters.search) {
        query = query.ilike('code', `%${filters.search}%`)
      }

      query = query.range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('loadCodes', 'PromoCodes', () => query, { page, filters })
      if (err) throw err
      setCodes(data || [])
      setTotal(count || 0)
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

  return (
    <div>
      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA PromoCodes</strong><br/>
        <div>codes: {codes.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>summary: total={summary.total}, active={summary.active}, inactive={summary.inactive}, expired={summary.expired}</div>
        <div>totalUsed: {summary.totalUsed}</div>
        <div>filtry: status={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}"</div>
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
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, statuses: v })) }}
          options={[{ value: 'active', label: 'Aktivní' }, { value: 'inactive', label: 'Neaktivní' }, { value: 'expired', label: 'Expirované' }]} />
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
          <Table>
            <thead>
              <TRow header>
                <TH>Kód</TH><TH>Sleva</TH><TH>Platnost</TH>
                <TH>Použití / Limit</TH><TH>Stav</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {codes.map(c => {
                const isActive = c.active && (!c.valid_to || new Date(c.valid_to) >= new Date())
                const isExpired = c.valid_to && new Date(c.valid_to) < new Date()
                const isLimitReached = c.max_uses && (c.used_count || 0) >= c.max_uses
                return (
                  <TRow key={c.id}>
                    <TD>
                      <button
                        onClick={() => setDetailCode(c)}
                        className="font-mono font-bold text-sm cursor-pointer"
                        style={{ color: '#2563eb', background: 'none', border: 'none', padding: 0 }}
                      >
                        {c.code}
                      </button>
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
                  </TRow>
                )
              })}
              {codes.length === 0 && <TRow><TD>Žádné promo kódy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Detail panel */}
      {detailCode && (
        <PromoDetailModal code={detailCode} onClose={() => setDetailCode(null)} onEdit={() => openEdit(detailCode)} />
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

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}
