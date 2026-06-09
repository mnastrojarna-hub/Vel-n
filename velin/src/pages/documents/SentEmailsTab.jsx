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
  const [selected, setSelected] = useState(() => new Set())
  const [deleting, setDeleting] = useState(false)

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
      setSelected(new Set())
    } catch (e) {
      debugError('SentEmailsTab', 'load', e)
      setError(e.message)
    } finally { setLoading(false) }
  }

  function toggleOne(id) {
    setSelected(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id); else next.add(id)
      return next
    })
  }
  function toggleAll() {
    setSelected(prev => prev.size === emails.length && emails.length > 0 ? new Set() : new Set(emails.map(e => e.id)))
  }
  async function deleteSelected() {
    if (selected.size === 0) return
    if (!window.confirm(`Opravdu smazat ${selected.size} zaslaných emailů? Tato akce je nevratná.`)) return
    setDeleting(true); setError(null)
    try {
      const ids = [...selected]
      const { error: err } = await debugAction('sent_emails.delete', 'SentEmailsTab', () => supabase.from('sent_emails').delete().in('id', ids))
      if (err) throw err
      setSelected(new Set())
      if (emails.length === ids.length && page > 1) setPage(p => p - 1)
      else load()
    } catch (e) {
      debugError('SentEmailsTab', 'deleteSelected', e)
      setError('Mazání selhalo: ' + (e.message || e))
    } finally { setDeleting(false) }
  }

  // Smlouva / VOP / protokol se při úpravě rezervace přegenerují pod novým
  // `generated/<uuid>.pdf` a stará verze se z úložiště smaže (generate-document,
  // 2026-06-08). Uložený `storage_path` v sent_emails pak míří na neexistující
  // soubor → „Object not found". Dohledáme aktuální platný soubor přes booking_id
  // ze stejných tabulek, ze kterých čte i detail zákazníka (kde přílohy fungují).
  async function resolveLivePath(filename, stalePath) {
    const bookingId = preview?.booking_id
    if (!bookingId || !stalePath) return null
    const fn = (filename || '').toLowerCase()
    if (stalePath.startsWith('generated/')) {
      let docType = null
      if (fn.includes('smlouva') || fn.includes('contract')) docType = 'contract'
      else if (fn.includes('vop')) docType = 'vop'
      else if (fn.includes('protokol') || fn.includes('protocol')) docType = 'protocol'
      if (!docType) return null
      const { data } = await supabase.from('documents')
        .select('file_path').eq('booking_id', bookingId).eq('type', docType)
        .not('file_path', 'is', null).order('created_at', { ascending: false }).limit(1)
      return data?.[0]?.file_path || null
    }
    if (stalePath.startsWith('invoices/')) {
      let types = null
      if (fn.includes('doklad-platby')) types = ['payment_receipt']
      else if (fn.includes('zalohova-faktura')) types = ['advance', 'proforma']
      else if (fn.includes('konecna-faktura')) types = ['final']
      else if (fn.includes('dobropis')) types = ['credit_note']
      if (!types) return null
      const { data } = await supabase.from('invoices')
        .select('number, pdf_path').eq('booking_id', bookingId).in('type', types)
        .not('pdf_path', 'is', null).order('created_at', { ascending: false })
      if (!data?.length) return null
      // Mezi více doklady téhož typu vyber ten, jehož číslo je v názvu přílohy.
      const exact = data.find(r => r.number && fn.includes(String(r.number).toLowerCase()))
      return (exact || data[0]).pdf_path
    }
    return null
  }

  async function openAttachment(path, filename) {
    try {
      let { data, error } = await supabase.storage.from('documents').createSignedUrl(path, 60)
      if (error || !data?.signedUrl) {
        const live = await resolveLivePath(filename, path)
        if (live) ({ data, error } = await supabase.storage.from('documents').createSignedUrl(live, 60))
      }
      if (error || !data?.signedUrl) throw error || new Error('soubor v úložišti nenalezen')
      window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
    } catch (e) {
      debugError('SentEmailsTab', 'openAttachment', e)
      setError('Náhled přílohy selhal: ' + (e.message || e))
    }
  }

  async function downloadAttachment(path, filename) {
    try {
      let { data, error } = await supabase.storage.from('documents').download(path)
      if (error || !data) {
        const live = await resolveLivePath(filename, path)
        if (live) ({ data, error } = await supabase.storage.from('documents').download(live))
      }
      if (error || !data) throw error || new Error('soubor chybí')
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = filename || path.split('/').pop() || 'priloha'
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
    } catch (e) {
      debugError('SentEmailsTab', 'downloadAttachment', e)
      setError('Stažení přílohy selhalo: ' + (e.message || e))
    }
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
        {selected.size > 0 && (
          <button onClick={deleteSelected} disabled={deleting}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 14px', background: '#dc2626', border: '1px solid #b91c1c', color: '#fff', opacity: deleting ? 0.6 : 1 }}>
            {deleting ? 'Mažu…' : `Smazat vybrané (${selected.size})`}
          </button>
        )}
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
                <TH><input type="checkbox" checked={emails.length > 0 && selected.size === emails.length} onChange={toggleAll} className="accent-[#1a8a18] cursor-pointer" style={{ width: 15, height: 15 }} /></TH>
                <TH>Příjemce</TH><TH>Předmět</TH><TH>Šablona</TH>
                <TH>Stav</TH><TH>Datum</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {emails.map(e => {
                const st = STATUS_MAP[e.status] || { label: e.status || '—', color: '#1a2e22', bg: '#f3f4f6' }
                return (
                  <TRow key={e.id}>
                    <TD><input type="checkbox" checked={selected.has(e.id)} onChange={() => toggleOne(e.id)} className="accent-[#1a8a18] cursor-pointer" style={{ width: 15, height: 15 }} /></TD>
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
            {preview.template_slug && (
              <> | <span className="font-bold">Šablona:</span> {preview.template_slug}</>
            )}
          </div>
          {Array.isArray(preview.attachments_meta) && preview.attachments_meta.length > 0 && (
            <div className="mb-3 p-3 rounded-card" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
                Přílohy ({preview.attachments_meta.length})
              </div>
              <ul className="text-sm" style={{ color: '#1a2e22', listStyle: 'none', padding: 0, margin: 0 }}>
                {preview.attachments_meta.map((a, i) => {
                  const filename = (typeof a === 'string' ? a : a?.filename) || `příloha-${i + 1}`
                  const storagePath = typeof a === 'object' ? a?.storage_path : null
                  return (
                    <li key={i} className="flex items-center gap-2 py-1">
                      <span style={{ color: '#1a8a18', fontSize: 14 }}>📎</span>
                      <span style={{ fontFamily: 'monospace', fontSize: 12, flex: 1 }}>{filename}</span>
                      {storagePath ? (
                        <>
                          <button onClick={() => openAttachment(storagePath, filename)}
                            className="text-sm font-bold cursor-pointer rounded-btn"
                            style={{ padding: '4px 10px', background: '#e0e7ff', border: '1px solid #a5b4fc', color: '#3730a3' }}
                            title="Otevřít v novém okně">
                            Náhled
                          </button>
                          <button onClick={() => downloadAttachment(storagePath, filename)}
                            className="text-sm font-bold cursor-pointer rounded-btn"
                            style={{ padding: '4px 10px', background: '#dcfce7', border: '1px solid #86efac', color: '#166534' }}
                            title="Stáhnout soubor">
                            Stáhnout
                          </button>
                        </>
                      ) : (
                        <span className="text-xs" style={{ color: '#9ca3af', fontStyle: 'italic' }} title="Soubor nebyl uložen do storage">nedostupné</span>
                      )}
                    </li>
                  )
                })}
              </ul>
            </div>
          )}
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
