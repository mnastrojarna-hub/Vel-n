import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
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

  useEffect(() => { load() }, [page, search])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('generated_documents')
        .select('*, document_templates(name, type), profiles(full_name), bookings(id)', { count: 'exact' })
      // Search is done client-side since we filter on joined document_templates columns
      query = query.order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      let filtered = data || []
      if (search) {
        const s = search.toLowerCase()
        filtered = filtered.filter(d =>
          (d.document_templates?.name || '').toLowerCase().includes(s) ||
          (d.document_templates?.type || '').toLowerCase().includes(s)
        )
      }
      setDocs(filtered)
      setTotal(search ? filtered.length : (count || 0))
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function download(doc) {
    try {
      if (!doc.pdf_path) return
      const { data, error } = await supabase.storage.from('documents').download(doc.pdf_path)
      if (error) throw error
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = doc.document_templates?.name || 'document'
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) {
      setError('Stažení selhalo: ' + e.message)
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat dokument…" />
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
                <TH>Rezervace</TH><TH>Datum</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {docs.map(d => (
                <TRow key={d.id}>
                  <TD bold>{d.document_templates?.name || '—'}</TD>
                  <TD>
                    <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                      style={{ padding: '4px 10px', background: '#f1faf7', color: '#4a6357' }}>
                      {d.document_templates?.type || '—'}
                    </span>
                  </TD>
                  <TD>{d.profiles?.full_name || '—'}</TD>
                  <TD mono>{d.bookings?.id ? d.bookings.id.slice(0, 8) : '—'}</TD>
                  <TD>{d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    <Button onClick={() => download(d)} style={{ padding: '4px 12px', fontSize: 10 }}>
                      Stáhnout
                    </Button>
                  </TD>
                </TRow>
              ))}
              {docs.length === 0 && <TRow><TD>Žádné dokumenty</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}
