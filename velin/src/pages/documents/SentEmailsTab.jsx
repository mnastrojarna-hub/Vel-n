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
  sent: { label: 'Odesláno', color: '#1a8a18', bg: '#dcfce7' },
  delivered: { label: 'Doručeno', color: '#1a8a18', bg: '#dcfce7' },
  queued: { label: 'Ve frontě', color: '#b45309', bg: '#fef3c7' },
  failed: { label: 'Selhalo', color: '#dc2626', bg: '#fee2e2' },
  bounced: { label: 'Nedoručeno', color: '#dc2626', bg: '#fee2e2' },
}

const STATUS_OPTIONS = [
  { value: 'sent', label: 'Odesláno' },
  { value: 'delivered', label: 'Doručeno' },
  { value: 'queued', label: 'Ve frontě' },
  { value: 'failed', label: 'Selhalo' },
  { value: 'bounced', label: 'Nedoručeno' },
]

export default function SentEmailsTab() {
  const debugMode = useDebugMode()
  const [emails, setEmails] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const defaultFilters = { search: '', statuses: [], sort: 'date_desc' }
  const [filters, setFilters] = useState(() => {
    try {
      const saved = localStorage.getItem('velin_sentemails_filters')
      if (saved) return { ...defaultFilters, ...JSON.parse(saved) }
    } catch {}
    return defaultFilters
  })
  useEffect(() => { localStorage.setItem('velin_sentemails_filters', JSON.stringify(filters)) }, [filters])
  const [preview, setPreview] = useState(null)

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true); setError(null)
    try {
      debugLog('SentEmailsTab', 'load', { page, filters })
      let query = supabase
        .from('sent_emails')
        .select('*', { count: 'exact' })
      if (filters.search) query = query.or(`recipient_email.ilike.%${filters.search}%,subject.ilike.%${filters.search}%,template_slug.ilike.%${filters.search}%`)
      if (filters.statuses?.length > 0) query = query.in('status', filters.statuses)
      query = query.order('created_at', { ascending: filters.sort === 'date_asc' })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('sent_emails.list', 'SentEmailsTab', () => query)
      if (err) throw err
      setEmails(data || [])
      setTotal(count || 0)
    } catch (e) {
      debugError('SentEmailsTab', 'load', e)
      setError(e.message)
    } finally { setLoading(false) }
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat email, předmět…" />
        <CheckboxFilterGroup label="Stav" values={filters.statuses || []}
          onChange={v => { setPage(1); setFilters(f => ({ ...f, statuses: v })) }}
          options={STATUS_OPTIONS} />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
        </select>
        <button onClick={() => { setPage(1); setFilters({ ...defaultFilters }); localStorage.removeItem('velin_sentemails_filters') }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
          Reset
        </button>
      </div>

      {/* DIAGNOSTIKA */}
      {debugMode && (
      <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
        <strong>DIAGNOSTIKA SentEmailsTab</strong><br/>
        <div>emails: {emails.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
        <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, sort={filters.sort}, search="{filters.search}"</div>
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
                <TH>Příjemce</TH><TH>Předmět</TH><TH>Šablona</TH>
                <TH>Stav</TH><TH>Datum</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {emails.map(e => {
                const st = STATUS_MAP[e.status] || { label: e.status || '—', color: '#1a2e22', bg: '#f3f4f6' }
                return (
                  <TRow key={e.id}>
                    <TD bold>{e.recipient_email || '—'}</TD>
                    <TD>{e.subject || '—'}</TD>
                    <TD>
                      <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
                        {e.template_slug || '—'}
                      </span>
                    </TD>
                    <TD><Badge label={st.label} color={st.color} bg={st.bg} /></TD>
                    <TD>{e.created_at ? new Date(e.created_at).toLocaleString('cs-CZ') : '—'}</TD>
                    <TD>
                      {e.body_html && (
                        <button onClick={() => setPreview(e)}
                          className="text-sm font-bold cursor-pointer"
                          style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 6px' }}>
                          Náhled
                        </button>
                      )}
                    </TD>
                  </TRow>
                )
              })}
              {emails.length === 0 && <TRow><TD>Žádné zaslané emaily</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {preview && (
        <Modal open title={`Email: ${preview.subject || '—'}`} onClose={() => setPreview(null)} wide>
          <div className="mb-3 text-sm" style={{ color: '#1a2e22' }}>
            <span className="font-bold">Příjemce:</span> {preview.recipient_email} | <span className="font-bold">Datum:</span> {preview.created_at ? new Date(preview.created_at).toLocaleString('cs-CZ') : '—'}
          </div>
          <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 500, overflow: 'auto' }}
            dangerouslySetInnerHTML={{ __html: preview.body_html }} />
          <div className="flex justify-end mt-4">
            <Button onClick={() => setPreview(null)}>Zavřít</Button>
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
