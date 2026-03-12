import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
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

export default function SentEmailsTab() {
  const [emails, setEmails] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState('date_desc')
  const [preview, setPreview] = useState(null)

  useEffect(() => { load() }, [page, search, sort])

  async function load() {
    setLoading(true); setError(null)
    try {
      debugLog('SentEmailsTab', 'load', { page, search, sort })
      let query = supabase
        .from('sent_emails')
        .select('*', { count: 'exact' })
      if (search) query = query.or(`recipient_email.ilike.%${search}%,subject.ilike.%${search}%,template_slug.ilike.%${search}%`)
      query = query.order('created_at', { ascending: sort === 'date_asc' })
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
      <div className="flex items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat email, předmět…" />
        <select value={sort} onChange={e => { setPage(1); setSort(e.target.value) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
        </select>
      </div>

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
