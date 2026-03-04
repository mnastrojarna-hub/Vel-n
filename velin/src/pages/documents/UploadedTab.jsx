import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'

import { Table, TRow, TH, TD } from '../../components/ui/Table'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'
import Modal from '../../components/ui/Modal'

const PER_PAGE = 25

export default function UploadedTab() {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [preview, setPreview] = useState(null)

  useEffect(() => { load() }, [page, search])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      let query = supabase
        .from('documents')
        .select('*, profiles(full_name)', { count: 'exact' })
      if (search) query = query.or(`type.ilike.%${search}%,profiles.full_name.ilike.%${search}%`)
      query = query.order('created_at', { ascending: false }).range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await query
      if (err) throw err
      setDocs(data || [])
      setTotal(count || 0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  function getPreviewUrl(doc) {
    if (!doc.file_path) return null
    return supabase.storage.from('documents').getPublicUrl(doc.file_path).data.publicUrl
  }

  const totalPages = Math.ceil(total / PER_PAGE)

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <SearchInput value={search} onChange={v => { setPage(1); setSearch(v) }} placeholder="Hledat zákazníka, typ…" />
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
                    <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
                      style={{ padding: '4px 10px', background: '#f1faf7', color: '#4a6357' }}>
                      {d.type || '—'}
                    </span>
                  </TD>
                  <TD>{d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                  <TD>
                    {d.file_path ? (
                      <button
                        onClick={() => setPreview(d)}
                        className="rounded-btn text-[10px] font-extrabold uppercase tracking-wide cursor-pointer"
                        style={{ padding: '3px 8px', background: '#f1faf7', color: '#4a6357', border: 'none' }}
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
        <Modal open title={`${preview.type || 'Doklad'} — ${preview.profiles?.full_name || ''}`} onClose={() => setPreview(null)} wide>
          {getPreviewUrl(preview) ? (
            <img
              src={getPreviewUrl(preview)}
              alt={preview.type}
              className="w-full rounded-lg"
              style={{ maxHeight: 500, objectFit: 'contain' }}
            />
          ) : (
            <p style={{ color: '#8aab99', fontSize: 13 }}>Náhled není dostupný</p>
          )}
        </Modal>
      )}
    </div>
  )
}
