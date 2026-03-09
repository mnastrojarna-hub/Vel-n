import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

export default function GeneratedTab() {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('')
  const [preview, setPreview] = useState(null)
  const [previewHtml, setPreviewHtml] = useState('')
  const [sort, setSort] = useState('date_desc')

  useEffect(() => { load() }, [page, search, typeFilter, sort])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      debugLog('GeneratedTab', 'load', { page, search, typeFilter, sort })
      let query = supabase
        .from('generated_documents')
        .select('*, profiles(full_name), bookings(id)', { count: 'exact' })
      query = query.order('created_at', { ascending: sort === 'date_asc' }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('generated_documents.list', 'GeneratedTab', () => query)
      if (err) throw err
      let items = data || []
      // Enrich with template data if template_id exists
      const templateIds = [...new Set(items.map(d => d.template_id).filter(Boolean))]
      let templatesMap = {}
      if (templateIds.length > 0) {
        const { data: tpls } = await supabase.from('document_templates').select('id, name, type, html_content').in('id', templateIds)
        for (const t of (tpls || [])) templatesMap[t.id] = t
      }
      items = items.map(d => ({ ...d, _template: templatesMap[d.template_id] || null }))
      let filtered = items
      if (search) {
        const s = search.toLowerCase()
        filtered = filtered.filter(d =>
          (d._template?.name || d.type || '').toLowerCase().includes(s) ||
          (d._template?.type || '').toLowerCase().includes(s) ||
          (d.profiles?.full_name || '').toLowerCase().includes(s)
        )
      }
      if (typeFilter) {
        filtered = filtered.filter(d => (d._template?.type || d.type) === typeFilter)
      }
      setDocs(filtered)
      setTotal(search || typeFilter ? filtered.length : (count || 0))
    } catch (e) {
      debugError('GeneratedTab', 'load', e)
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  function generateFilledHtml(doc) {
    const template = doc._template?.html_content
    const data = doc.filled_data
    if (!template || !data) return null
    let html = template
    for (const [k, v] of Object.entries(data)) {
      html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v || '')
    }
    return html
  }

  async function download(doc) {
    try {
      debugLog('GeneratedTab', 'download', { docId: doc.id, hasPdfPath: !!doc.pdf_path })
      if (doc.pdf_path) {
        const { data, error } = await debugAction('documents.download', 'GeneratedTab', () =>
          supabase.storage.from('documents').download(doc.pdf_path)
        )
        if (!error && data) {
          const url = URL.createObjectURL(data)
          const a = document.createElement('a')
          a.href = url
          a.download = (doc._template?.name || 'document') + (doc.pdf_path.endsWith('.html') ? '.html' : '.pdf')
          a.click()
          URL.revokeObjectURL(url)
          return
        }
      }
      // Fallback: generate from filled_data + template
      const html = generateFilledHtml(doc)
      if (html) {
        const blob = new Blob([html], { type: 'text/html' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = (doc._template?.name || 'document') + '.html'
        a.click()
        URL.revokeObjectURL(url)
      } else {
        setError('Dokument nemá obsah ke stažení.')
      }
    } catch (e) {
      debugError('GeneratedTab', 'download', e)
      setError('Stažení selhalo: ' + e.message)
    }
  }

  function showPreview(doc) {
    const html = generateFilledHtml(doc)
    setPreviewHtml(html || '<p style="color:#8aab99;text-align:center;padding:40px;">Obsah dokumentu není dostupný. Zkuste znovu vygenerovat dokument ze šablony.</p>')
    setPreview(doc)
  }

  const docTypes = [...new Set(docs.map(d => d._template?.type).filter(Boolean))]
  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat dokument, zákazníka…" />
        <select value={sort} onChange={e => { setPage(1); setSort(e.target.value) }}
          className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
          <option value="date_desc">Datum ↓ nejnovější</option>
          <option value="date_asc">Datum ↑ nejstarší</option>
        </select>
        {docTypes.length > 0 && (
          <select value={typeFilter} onChange={e => { setPage(1); setTypeFilter(e.target.value) }}
            className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer outline-none"
            style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357' }}>
            <option value="">Všechny typy</option>
            {docTypes.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
        )}
      </div>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Název</TH><TH>Typ</TH><TH>Zákazník</TH>
                <TH>Rezervace</TH><TH>Datum</TH><TH>Obsah</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {docs.map(d => {
                const hasContent = !!(d.filled_data && d._template?.html_content) || !!d.pdf_path
                return (
                  <TRow key={d.id}>
                    <TD bold>{d._template?.name || '—'}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                        style={{ padding: '4px 10px', background: '#f1faf7', color: '#4a6357' }}>
                        {d._template?.type || '—'}
                      </span>
                    </TD>
                    <TD>{d.profiles?.full_name || '—'}</TD>
                    <TD mono>{d.bookings?.id ? d.bookings.id.slice(0, 8) : '—'}</TD>
                    <TD>{d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>
                      <span className="inline-block rounded-btn text-[9px] font-extrabold tracking-wide uppercase"
                        style={{
                          padding: '3px 8px',
                          background: hasContent ? '#dcfce7' : '#fee2e2',
                          color: hasContent ? '#1a8a18' : '#dc2626',
                        }}>
                        {hasContent ? 'Vyplněno' : 'Prázdný'}
                      </span>
                    </TD>
                    <TD>
                      <div className="flex gap-1">
                        <button onClick={() => showPreview(d)}
                          className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
                          style={{ padding: '3px 8px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
                          Náhled
                        </button>
                        <Button onClick={() => download(d)} style={{ padding: '4px 12px', fontSize: 10 }}>
                          Stáhnout
                        </Button>
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {docs.length === 0 && <TRow><TD>Žádné dokumenty</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {preview && (
        <Modal open title={`Náhled: ${preview._template?.name || 'Dokument'}`} onClose={() => setPreview(null)} wide>
          {preview.filled_data && (
            <div className="mb-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="text-[10px] font-extrabold uppercase tracking-wide mb-2" style={{ color: '#8aab99' }}>Vyplněná data</div>
              <div className="grid grid-cols-2 gap-1 text-xs">
                {Object.entries(preview.filled_data).map(([k, v]) => (
                  <div key={k}>
                    <span style={{ color: '#8aab99' }}>{k}: </span>
                    <span className="font-bold" style={{ color: '#0f1a14' }}>{v || '—'}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
          <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 500, overflow: 'auto' }}
            dangerouslySetInnerHTML={{ __html: previewHtml }} />
          <div className="flex justify-end gap-3 mt-4">
            <Button onClick={() => download(preview)}>Stáhnout</Button>
            <Button onClick={() => setPreview(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
