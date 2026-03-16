import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'

const PER_PAGE = 25
const STORAGE_KEY = 'velin_uploaded_filters'
const defaultFilters = { search: '', sort: 'date_desc' }

function loadFilters() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      return { ...defaultFilters, ...parsed }
    }
  } catch (_) { /* ignore */ }
  return { ...defaultFilters }
}

export default function UploadedTab() {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState(loadFilters)
  const [preview, setPreview] = useState(null)

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(filters))
    } catch (_) { /* ignore */ }
  }, [filters])

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('UploadedTab', 'load', { page, filters })
      let query = supabase
        .from('documents')
        .select('*, profiles(full_name)', { count: 'exact' })
      if (filters.search) query = query.or(`type.ilike.%${filters.search}%,profiles.full_name.ilike.%${filters.search}%`)
      query = query.order('created_at', { ascending: filters.sort === 'date_asc' }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('documents.list', 'UploadedTab', () => query)
      if (err) throw err
      setDocs(data || [])
      setTotal(count || 0)
    } catch (e) {
      debugError('UploadedTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  // getPreviewUrl removed — bucket may not exist, use PreviewModal instead

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat zákazníka, typ…" />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
        </select>
        {(filters.search || filters.sort !== 'date_desc') && (
          <button
            onClick={() => { setPage(1); setFilters({ ...defaultFilters }) }}
            className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Reset
          </button>
        )}
      </div>

      {/* DIAGNOSTIKA */}
      <div className="mb-4 p-3 rounded-card text-xs" style={{ background: '#f0f9ff', border: '1px solid #bae6fd', color: '#0369a1' }}>
        <strong>DIAGNOSTIKA:</strong> sort={filters.sort} | search="{filters.search}"
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Zákazník</TH><TH>Typ dokladu</TH><TH>Datum nahrání</TH><TH>Preview</TH>
              </TRow>
            </thead>
            <tbody>
              {docs.map(d => (
                <TRow key={d.id}>
                  <TD bold>{d.profiles?.full_name || '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
                      style={{ padding: '4px 10px', background: '#f1faf7', color: '#1a2e22' }}>
                      {d.type || '—'}
                    </span>
                  </TD>
                  <TD>{d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    {d.file_path ? (
                      <button
                        onClick={() => setPreview(d)}
                        className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
                        style={{ padding: '3px 8px', background: '#f1faf7', color: '#1a2e22', border: 'none' }}
                      >
                        Zobrazit
                      </button>
                    ) : '—'}
                  </TD>
                </TRow>
              ))}
              {docs.length === 0 && <TRow><TD>Žádné nahrané doklady</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {preview && (
        <PreviewModal doc={preview} onClose={() => setPreview(null)} />
      )}
    </div>
  )
}

function PreviewModal({ doc, onClose }) {
  const [html, setHtml] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadContent()
  }, [doc.id])

  async function loadContent() {
    setLoading(true)
    if (doc.file_path) {
      try {
        debugLog('UploadedTab', 'loadContent', { docId: doc.id, filePath: doc.file_path })
        const { data, error } = await debugAction('documents.download', 'UploadedTab', () =>
          supabase.storage.from('documents').download(doc.file_path)
        )
        if (!error && data) {
          const text = await data.text()
          setHtml(text)
          setLoading(false)
          return
        }
      } catch (e) { debugError('UploadedTab', 'loadContent', e) }
    }
    setHtml(null)
    setLoading(false)
  }

  return (
    <Modal open title={`${doc.type || 'Doklad'} — ${doc.profiles?.full_name || ''}`} onClose={onClose} wide>
      {loading ? (
        <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : html ? (
        <div className="border rounded-lg overflow-auto" style={{ maxHeight: 500, background: '#fff' }}>
          <iframe srcDoc={html} style={{ width: '100%', height: 450, border: 'none' }} title="Náhled" />
        </div>
      ) : (
        <div className="py-8 text-center" style={{ color: '#1a2e22', fontSize: 13 }}>
          Náhled není dostupný — storage bucket neexistuje. Dokument: {doc.file_name || doc.file_path || '—'}
        </div>
      )}
    </Modal>
  )
}
