import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { useDebugMode } from '../../hooks/useDebugMode'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const PER_PAGE = 25

const STATUS_MAP = {
  queued:    { label: 'Ve frontě', color: '#b45309', bg: '#fef3c7' },
  sent:      { label: 'Odesláno', color: '#2563eb', bg: '#dbeafe' },
  delivered: { label: 'Doručeno', color: '#1a8a18', bg: '#dcfce7' },
  failed:    { label: 'Selhalo',  color: '#dc2626', bg: '#fee2e2' },
}

const STATUS_OPTIONS = [
  { value: 'queued', label: 'Ve frontě' },
  { value: 'sent', label: 'Odesláno' },
  { value: 'delivered', label: 'Doručeno' },
  { value: 'failed', label: 'Selhalo' },
]

const TYPE_OPTIONS = [
  { value: 'all', label: 'Všechny' },
  { value: 'auto', label: 'Automatické' },
  { value: 'marketing', label: 'Marketingové' },
]

const CHANNEL_LABELS = { sms: 'SMS', email: 'E-mail', whatsapp: 'WhatsApp' }

export default function MessageLogTab({ channel }) {
  const debugMode = useDebugMode()
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [detail, setDetail] = useState(null)

  const storageKey = `velin_msglog_${channel}_filters`
  const defaultFilters = { search: '', statuses: [], type: 'all', dateFrom: '', dateTo: '', sort: 'date_desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem(storageKey)
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })

  useEffect(() => { localStorage.setItem(storageKey, JSON.stringify(filters)) }, [filters, storageKey])
  useEffect(() => { setPage(1) }, [filters, channel])
  useEffect(() => { setFilters(defaultFilters); setPage(1) }, [channel])
  useEffect(() => { load() }, [page, filters, channel])

  async function load() {
    setLoading(true); setError(null)
    try {
      debugLog('MessageLogTab', 'load', { channel, page, filters })
      let query = supabase
        .from('message_log')
        .select('*', { count: 'exact' })
        .eq('channel', channel)

      if (filters.search) {
        query = query.or(`recipient_phone.ilike.%${filters.search}%,recipient_email.ilike.%${filters.search}%,content_preview.ilike.%${filters.search}%`)
      }
      if (filters.statuses?.length > 0) {
        query = query.in('status', filters.statuses)
      }
      if (filters.type === 'auto') {
        query = query.eq('is_marketing', false)
      } else if (filters.type === 'marketing') {
        query = query.eq('is_marketing', true)
      }
      if (filters.dateFrom) {
        query = query.gte('created_at', filters.dateFrom + 'T00:00:00')
      }
      if (filters.dateTo) {
        query = query.lte('created_at', filters.dateTo + 'T23:59:59')
      }

      query = query
        .order('created_at', { ascending: filters.sort === 'date_asc' })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)

      const { data, count, error: err } = await debugAction('message_log.list', 'MessageLogTab', () => query)
      if (err) throw err
      setLogs(data || [])
      setTotal(count || 0)
    } catch (e) {
      debugError('MessageLogTab', 'load', e)
      setError(e.message)
    } finally { setLoading(false) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  function truncate(str, len) {
    if (!str) return '—'
    return str.length > len ? str.slice(0, len) + '…' : str
  }

  function formatDate(iso) {
    if (!iso) return '—'
    const d = new Date(iso)
    return d.toLocaleString('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  function recipient(log) {
    if (channel === 'email') return log.recipient_email || '—'
    return log.recipient_phone || '—'
  }

  return (
    <div>
      {/* Filtry */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput
          value={filters.search}
          onChange={v => setFilters(f => ({ ...f, search: v }))}
          placeholder={channel === 'email' ? 'Hledat email, obsah…' : 'Hledat telefon, obsah…'}
        />

        <CheckboxFilterGroup
          label="Stav"
          values={filters.statuses || []}
          onChange={v => setFilters(f => ({ ...f, statuses: v }))}
          options={STATUS_OPTIONS}
        />

        <select
          value={filters.type}
          onChange={e => setFilters(f => ({ ...f, type: e.target.value }))}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
        >
          {TYPE_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>

        <div className="flex items-center gap-1">
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Od:</span>
          <input
            type="date"
            value={filters.dateFrom}
            onChange={e => setFilters(f => ({ ...f, dateFrom: e.target.value }))}
            className="rounded-btn text-sm outline-none"
            style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
          />
          <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Do:</span>
          <input
            type="date"
            value={filters.dateTo}
            onChange={e => setFilters(f => ({ ...f, dateTo: e.target.value }))}
            className="rounded-btn text-sm outline-none"
            style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
          />
        </div>

        <select
          value={filters.sort}
          onChange={e => setFilters(f => ({ ...f, sort: e.target.value }))}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
        >
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
        </select>

        <button
          onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem(storageKey) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}
        >
          Reset
        </button>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA MessageLogTab ({channel})</strong><br/>
          <div>logs: {logs.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
          <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, type={filters.type}, sort={filters.sort}, search="{filters.search}"</div>
          <div>dateFrom={filters.dateFrom || '—'}, dateTo={filters.dateTo || '—'}</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {/* Error */}
      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Tabulka */}
      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Čas</TH>
                <TH>Příjemce</TH>
                <TH>Šablona</TH>
                <TH>Náhled</TH>
                <TH>Status</TH>
                <TH>Cena</TH>
              </TRow>
            </thead>
            <tbody>
              {logs.map(log => {
                const st = STATUS_MAP[log.status] || { label: log.status || '—', color: '#1a2e22', bg: '#f3f4f6' }
                return (
                  <TRow key={log.id}>
                    <TD mono>{formatDate(log.created_at)}</TD>
                    <TD bold>{recipient(log)}</TD>
                    <TD>
                      {log.template_slug
                        ? <Badge label={log.template_slug} color="#1a2e22" bg="#f1faf7" />
                        : <span style={{ color: '#1a2e22', fontSize: 13 }}>—</span>
                      }
                    </TD>
                    <TD>
                      <span
                        className="cursor-pointer"
                        style={{ color: '#2563eb', fontSize: 13 }}
                        onClick={() => setDetail(log)}
                        title="Zobrazit celou zprávu"
                      >
                        {truncate(log.content_preview, 60)}
                      </span>
                    </TD>
                    <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                    <TD mono>{log.cost_amount != null ? `${log.cost_amount} Kč` : '—'}</TD>
                  </TRow>
                )
              })}
              {logs.length === 0 && (
                <TRow>
                  <TD>Žádné {CHANNEL_LABELS[channel]} zprávy</TD>
                </TRow>
              )}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {/* Detail modal */}
      {detail && (
        <Modal open title={`${CHANNEL_LABELS[channel]} zpráva`} onClose={() => setDetail(null)} wide>
          <div className="space-y-3">
            <div className="flex flex-wrap gap-x-6 gap-y-1 text-sm" style={{ color: '#1a2e22' }}>
              <div><span className="font-bold">Příjemce:</span> {recipient(detail)}</div>
              <div><span className="font-bold">Čas:</span> {formatDate(detail.created_at)}</div>
              <div><span className="font-bold">Status:</span> {(STATUS_MAP[detail.status] || {}).label || detail.status}</div>
              {detail.template_slug && <div><span className="font-bold">Šablona:</span> {detail.template_slug}</div>}
              {detail.is_marketing && <Badge label="Marketing" color="#7c3aed" bg="#ede9fe" />}
              {detail.cost_amount != null && <div><span className="font-bold">Cena:</span> {detail.cost_amount} Kč</div>}
            </div>

            {detail.error_message && (
              <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>
                <span className="font-bold">Chyba:</span> {detail.error_message}
              </div>
            )}

            <div>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Obsah zprávy</div>
              <div className="rounded-card" style={{ padding: 16, background: '#f8fcfa', border: '1px solid #d4e8e0', whiteSpace: 'pre-wrap', fontSize: 13, maxHeight: 400, overflow: 'auto' }}>
                {detail.content_preview || detail.content_full || '—'}
              </div>
            </div>

            {detail.metadata && (
              <div>
                <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Metadata</div>
                <pre className="rounded-card" style={{ padding: 12, background: '#f1faf7', border: '1px solid #d4e8e0', fontSize: 11, maxHeight: 200, overflow: 'auto', color: '#1a2e22' }}>
                  {JSON.stringify(detail.metadata, null, 2)}
                </pre>
              </div>
            )}
          </div>

          <div className="flex justify-end mt-4">
            <Button onClick={() => setDetail(null)}>Zavřít</Button>
          </div>
        </Modal>
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
