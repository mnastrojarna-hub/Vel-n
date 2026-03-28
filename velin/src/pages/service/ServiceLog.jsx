import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import { TYPE_LABELS } from './serviceScheduleUtils'
import ServiceLogModal from './ServiceLogModal'

const PER_PAGE = 25
const TYPES = Object.keys(TYPE_LABELS)

export default function ServiceLog() {
  const debugMode = useDebugMode()
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', types: [] }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_servicelog_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_servicelog_filters', JSON.stringify(filters)) }, [filters])
  const [showAdd, setShowAdd] = useState(false)
  const [editing, setEditing] = useState(null)
  const [expandedLog, setExpandedLog] = useState(null)

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('ServiceLog', 'load', { page, filters })
      let query = supabase.from('maintenance_log').select('*, motorcycles!moto_id(model, spz)', { count: 'exact' })
      if (filters.types?.length > 0) {
        const typeFilter = filters.types.map(t => `type.eq.${t},service_type.eq.${t}`).join(',')
        query = query.or(typeFilter)
      }
      if (filters.search) query = query.or(`motorcycles!moto_id.model.ilike.%${filters.search}%,motorcycles!moto_id.spz.ilike.%${filters.search}%`)
      query = query.order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('maintenance_log.list', 'ServiceLog', () => query)
      if (err) throw err
      setLogs(data || [])
      setTotal(count || 0)
    } catch (e) { debugError('ServiceLog', 'load', e); setError(e.message) }
    finally { setLoading(false) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const fmt = (n) => n ? `${n.toLocaleString('cs-CZ')} Kč` : '—'

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat motorku…" />
        <CheckboxFilterGroup label="Typ" values={filters.types || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, types: v })) }}
          options={TYPES.map(t => ({ value: t, label: TYPE_LABELS[t] }))} />
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_servicelog_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>Reset</button>
        <div className="ml-auto"><Button green onClick={() => setShowAdd(true)}>+ Naplánovat servis</Button></div>
      </div>

      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA ServiceLog</strong><br/>
        <div>logs: {logs.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: types={filters.types?.length > 0 ? filters.types.join(',') : 'vše'}, search="{filters.search}"</div>
        {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
      </div>
      )}

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Motorka</TH><TH>SPZ</TH><TH>Typ</TH><TH>Do servisu</TH>
                <TH>Ze servisu</TH><TH>Km</TH><TH>Náklady</TH><TH>Stav</TH><TH>Technik</TH>
              </TRow>
            </thead>
            <tbody>
              {logs.map(l => {
                const startDate = l.service_date || l.created_at
                const isExp = expandedLog === l.id
                return (
                  <LogRow key={l.id} log={l} km={l.km_at_service || l.mileage_at_service} startDate={startDate}
                    isExpanded={isExp} onToggle={() => setExpandedLog(isExp ? null : l.id)}
                    onEdit={() => setEditing(l)} fmt={fmt} />
                )
              })}
              {logs.length === 0 && <TRow><TD>Žádné servisní záznamy</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {(showAdd || editing) && (
        <ServiceLogModal entry={editing} onClose={() => { setShowAdd(false); setEditing(null) }} onSaved={() => { setShowAdd(false); setEditing(null); load() }} />
      )}
    </div>
  )
}

function LogRow({ log: l, km, startDate, isExpanded, onToggle, onEdit, fmt }) {
  return (
    <>
      <tr onClick={onToggle} className="cursor-pointer hover:bg-[#f1faf7] transition-colors" style={{ borderBottom: isExpanded ? 'none' : '1px solid #d4e8e0' }}>
        <TD bold>{l.motorcycles?.model || '—'}</TD>
        <TD mono>{l.motorcycles?.spz || '—'}</TD>
        <TD><span>{TYPE_LABELS[l.type] || { regular: 'Pravidelný', extraordinary: 'Mimořádný', repair: 'Oprava' }[l.service_type] || l.type || '—'}</span>{l.is_urgent && <span className="ml-1 text-xs font-bold px-1 py-0.5 rounded" style={{ background: '#dc2626', color: '#fff' }}>URGENT</span>}</TD>
        <TD>{startDate ? new Date(startDate).toLocaleDateString('cs-CZ') : '—'}</TD>
        <TD>{l.completed_date ? new Date(l.completed_date).toLocaleDateString('cs-CZ') : '—'}</TD>
        <TD mono>{km ? km.toLocaleString('cs-CZ') : '—'}</TD>
        <TD bold>{fmt(l.cost)}</TD>
        <TD><StatusBadge status={l.completed_date && l.status !== 'completed' ? 'completed' : (l.status === 'pending' ? 'pending_service' : (l.status || 'pending_service'))} /></TD>
        <TD>{l.performed_by || '—'}</TD>
      </tr>
      {isExpanded && (
        <tr style={{ borderBottom: '1px solid #d4e8e0' }}>
          <td colSpan={9} style={{ padding: '8px 12px', background: '#f1faf7' }}>
            {l.items && Array.isArray(l.items) && l.items.length > 0 && (
              <div className="mb-3">
                <span className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>Servisní úkony:</span>
                <div className="flex flex-wrap gap-1 mt-1">
                  {l.items.map((it, i) => (
                    <span key={i} className="text-xs font-bold rounded-full" style={{ padding: '3px 10px', background: it.done ? '#dcfce7' : '#fef3c7', color: it.done ? '#166534' : '#b45309', border: `1px solid ${it.done ? '#86efac' : '#fde68a'}` }}>
                      {it.done ? '✓ ' : ''}{it.label}
                    </span>
                  ))}
                </div>
              </div>
            )}
            <div className="text-sm" style={{ color: '#0f1a14' }}>
              <span className="font-extrabold">Servisní záznam: </span>
              {l.description || <span style={{ color: '#9ca3af' }}>Bez popisu</span>}
            </div>
            {l.scheduled_date && (
              <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
                <span className="font-extrabold">Plánované dokončení: </span>{new Date(l.scheduled_date).toLocaleDateString('cs-CZ')}
              </div>
            )}
            <button onClick={e => { e.stopPropagation(); onEdit() }}
              className="mt-2 rounded-btn text-sm font-bold cursor-pointer"
              style={{ padding: '4px 12px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>Upravit</button>
          </td>
        </tr>
      )}
    </>
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
