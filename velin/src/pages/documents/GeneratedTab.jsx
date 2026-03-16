import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { Table, TRow, TH, TD } from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import SearchInput from '../../components/ui/SearchInput'
import Pagination from '../../components/ui/Pagination'

const PER_PAGE = 25

const TYPE_LABELS = {
  vop: 'VOP',
  rental_contract: 'Smlouva',
  handover_protocol: 'Předávací protokol',
}

const TYPE_OPTIONS = [
  { value: 'vop', label: 'VOP' },
  { value: 'rental_contract', label: 'Smlouva' },
  { value: 'handover_protocol', label: 'Předávací protokol' },
]

const STORAGE_KEY = 'velin_generated_filters'
const defaultFilters = { search: '', types: [], sort: 'date_desc' }

function loadFilters() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw)
      return { ...defaultFilters, ...parsed }
    }
  } catch { /* ignore */ }
  return { ...defaultFilters }
}

export default function GeneratedTab() {
  const [docs, setDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState(loadFilters)
  const [preview, setPreview] = useState(null)
  const [previewHtml, setPreviewHtml] = useState('')
  const [showGenerate, setShowGenerate] = useState(false)

  // Persist filters to localStorage
  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(filters)) } catch { /* ignore */ }
  }, [filters])

  useEffect(() => { load() }, [page, filters])

  async function load() {
    setLoading(true); setError(null)
    try {
      debugLog('GeneratedTab', 'load', { page, filters })
      let query = supabase
        .from('generated_documents')
        .select('*, profiles(full_name), bookings(id, start_date, motorcycles:moto_id(model))', { count: 'exact' })
      query = query.order('created_at', { ascending: filters.sort === 'date_asc' })
        .range((page - 1) * PER_PAGE, page * PER_PAGE - 1)
      const { data, count, error: err } = await debugAction('generated_documents.list', 'GeneratedTab', () => query)
      if (err) throw err
      let items = data || []

      // Enrich with template data
      const templateIds = [...new Set(items.map(d => d.template_id).filter(Boolean))]
      let templatesMap = {}
      if (templateIds.length > 0) {
        const { data: tpls } = await supabase.from('document_templates').select('id, name, type, content_html').in('id', templateIds)
        for (const t of (tpls || [])) templatesMap[t.id] = t
      }
      items = items.map(d => ({ ...d, _template: templatesMap[d.template_id] || null }))

      // Apply local filters
      if (filters.search) {
        const s = filters.search.toLowerCase()
        items = items.filter(d =>
          (d._template?.name || d.type || '').toLowerCase().includes(s) ||
          (d.profiles?.full_name || '').toLowerCase().includes(s)
        )
      }
      if (filters.types?.length > 0) {
        items = items.filter(d => filters.types.includes(d._template?.type || d.type))
      }

      setDocs(items)
      setTotal(filters.search || filters.types?.length > 0 ? items.length : (count || 0))
    } catch (e) {
      debugError('GeneratedTab', 'load', e)
      setError(e.message)
    } finally { setLoading(false) }
  }

  function generateFilledHtml(doc) {
    const template = doc._template?.content_html
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
      if (doc.pdf_path) {
        const { data, error } = await supabase.storage.from('documents').download(doc.pdf_path)
        if (!error && data) {
          const url = URL.createObjectURL(data)
          const a = document.createElement('a'); a.href = url
          a.download = (doc._template?.name || 'document') + (doc.pdf_path.endsWith('.html') ? '.html' : '.pdf')
          a.click(); URL.revokeObjectURL(url); return
        }
      }
      const html = generateFilledHtml(doc)
      if (html) {
        const blob = new Blob([html], { type: 'text/html' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a'); a.href = url
        a.download = (doc._template?.name || 'document') + '.html'; a.click(); URL.revokeObjectURL(url)
      } else { setError('Dokument nemá obsah ke stažení.') }
    } catch (e) { setError('Stažení selhalo: ' + e.message) }
  }

  function showPreviewModal(doc) {
    const html = generateFilledHtml(doc)
    setPreviewHtml(html || '<p style="color:#1a2e22;text-align:center;padding:40px;">Obsah dokumentu není dostupný.</p>')
    setPreview(doc)
  }

  const totalPages = Math.ceil(total / PER_PAGE)
  const hasActiveFilters = filters.search || filters.types.length > 0 || filters.sort !== 'date_desc'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <SearchInput value={filters.search} onChange={v => { setPage(1); setFilters(f => ({ ...f, search: v })) }} placeholder="Hledat dokument, zákazníka…" />
        <select value={filters.sort} onChange={e => { setPage(1); setFilters(f => ({ ...f, sort: e.target.value })) }}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
          <option value="date_desc">Datum ↓</option>
          <option value="date_asc">Datum ↑</option>
        </select>
        <CheckboxFilterGroup
          label="Typ dokumentu"
          options={TYPE_OPTIONS}
          selected={filters.types}
          onChange={types => { setPage(1); setFilters(f => ({ ...f, types })) }}
        />
        {hasActiveFilters && (
          <button
            onClick={() => { setPage(1); setFilters({ ...defaultFilters }) }}
            className="text-sm font-bold cursor-pointer rounded-btn"
            style={{ padding: '8px 14px', background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
            Resetovat filtry
          </button>
        )}
        <div className="ml-auto">
          <Button green onClick={() => setShowGenerate(true)}>+ Vygenerovat dokument</Button>
        </div>
      </div>

      {/* DIAGNOSTIKA */}
      <details className="mb-4">
        <summary className="text-xs font-bold cursor-pointer" style={{ color: '#6b7280' }}>DIAGNOSTIKA</summary>
        <pre className="text-xs mt-1 p-2 rounded-card overflow-auto" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', maxHeight: 150 }}>
{JSON.stringify({ filters, page, total, docsCount: docs.length, hasActiveFilters }, null, 2)}
        </pre>
      </details>

      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        <>
          <Table>
            <thead>
              <TRow header>
                <TH>Typ</TH><TH>Zákazník</TH><TH>Motorka</TH>
                <TH>Rezervace</TH><TH>Datum</TH><TH>Akce</TH>
              </TRow>
            </thead>
            <tbody>
              {docs.map(d => {
                const typeName = TYPE_LABELS[d._template?.type] || d._template?.name || '—'
                return (
                  <TRow key={d.id}>
                    <TD>
                      <Badge label={typeName}
                        color={d._template?.type === 'rental_contract' ? '#2563eb' : d._template?.type === 'vop' ? '#059669' : '#b45309'}
                        bg={d._template?.type === 'rental_contract' ? '#dbeafe' : d._template?.type === 'vop' ? '#d1fae5' : '#fef3c7'} />
                    </TD>
                    <TD>{d.profiles?.full_name || '—'}</TD>
                    <TD>{d.bookings?.motorcycles?.model || '—'}</TD>
                    <TD mono>{d.bookings?.id ? d.bookings.id.slice(0, 8) : '—'}</TD>
                    <TD>{d.created_at ? new Date(d.created_at).toLocaleDateString('cs-CZ') : '—'}</TD>
                    <TD>
                      <div className="flex gap-1">
                        <button onClick={() => showPreviewModal(d)}
                          className="text-sm font-bold cursor-pointer"
                          style={{ color: '#2563eb', background: 'none', border: 'none', padding: '4px 6px' }}>Náhled</button>
                        <button onClick={() => download(d)}
                          className="text-sm font-bold cursor-pointer"
                          style={{ color: '#1a2e22', background: 'none', border: 'none', padding: '4px 6px' }}>Stáhnout</button>
                      </div>
                    </TD>
                  </TRow>
                )
              })}
              {docs.length === 0 && <TRow><TD>Žádné vygenerované dokumenty</TD></TRow>}
            </tbody>
          </Table>
          <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}

      {preview && (
        <Modal open title={`Náhled: ${TYPE_LABELS[preview._template?.type] || preview._template?.name || 'Dokument'}`} onClose={() => setPreview(null)} wide>
          {preview.filled_data && (
            <div className="mb-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Vyplněná data</div>
              <div className="grid grid-cols-2 gap-1 text-sm">
                {Object.entries(preview.filled_data).map(([k, v]) => (
                  <div key={k}>
                    <span style={{ color: '#1a2e22' }}>{k}: </span>
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

      {showGenerate && (
        <GenerateDocModal onClose={() => setShowGenerate(false)} onGenerated={() => { setShowGenerate(false); load() }} />
      )}
    </div>
  )
}

function GenerateDocModal({ onClose, onGenerated }) {
  const [templates, setTemplates] = useState([])
  const [bookings, setBookings] = useState([])
  const [selectedTemplate, setSelectedTemplate] = useState('')
  const [selectedBooking, setSelectedBooking] = useState('')
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)
  const [err, setErr] = useState(null)
  const [success, setSuccess] = useState(false)

  useEffect(() => {
    Promise.all([
      supabase.from('document_templates').select('id, name, type, content_html')
        .in('type', ['vop', 'rental_contract', 'handover_protocol']).order('type'),
      supabase.from('bookings')
        .select('id, start_date, end_date, total_price, profiles(full_name, email, phone, street, city, zip), motorcycles(model, spz)')
        .neq('status', 'cancelled').order('created_at', { ascending: false }).limit(30),
    ]).then(([{ data: tpls }, { data: bks }]) => {
      setTemplates(tpls || [])
      setBookings(bks || [])
      setLoading(false)
    })
  }, [])

  async function handleGenerate() {
    if (!selectedTemplate || !selectedBooking) return setErr('Vyberte šablonu a rezervaci.')
    setGenerating(true); setErr(null); setSuccess(false)
    try {
      const template = templates.find(t => t.id === selectedTemplate)
      const booking = bookings.find(b => b.id === selectedBooking)
      if (!template || !booking) throw new Error('Šablona nebo rezervace nebyla nalezena.')

      const vars = {
        customer_name: booking.profiles?.full_name || '',
        customer_email: booking.profiles?.email || '',
        customer_phone: booking.profiles?.phone || '',
        customer_address: [booking.profiles?.street, booking.profiles?.city, booking.profiles?.zip].filter(Boolean).join(', ') || '',
        moto_model: booking.motorcycles?.model || '',
        moto_spz: booking.motorcycles?.spz || '',
        start_date: booking.start_date ? new Date(booking.start_date).toLocaleDateString('cs-CZ') : '',
        end_date: booking.end_date ? new Date(booking.end_date).toLocaleDateString('cs-CZ') : '',
        total_price: (booking.total_price || 0).toLocaleString('cs-CZ') + ' Kč',
        booking_number: booking.id?.slice(0, 8).toUpperCase() || '',
        contract_date: new Date().toLocaleDateString('cs-CZ'),
        company_name: 'Bc. Petra Semorádová',
        company_ico: '21874263',
      }

      let filledHtml = template.content_html || ''
      for (const [k, v] of Object.entries(vars)) {
        filledHtml = filledHtml.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v)
      }

      const blob = new Blob([filledHtml], { type: 'text/html' })
      const path = `generated/${template.id}_${selectedBooking}.html`
      await supabase.storage.from('documents').upload(path, blob, { upsert: true })

      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('generated_documents').insert({
        template_id: template.id,
        booking_id: selectedBooking,
        customer_id: booking.profiles?.id || null,
        filled_data: vars,
        pdf_path: path,
        generated_by: user?.id,
      })

      setSuccess(true)
      setTimeout(() => onGenerated(), 1000)
    } catch (e) { setErr(e.message) }
    setGenerating(false)
  }

  const TYPE_LABELS = { vop: 'VOP', rental_contract: 'Nájemní smlouva', handover_protocol: 'Předávací protokol' }

  return (
    <Modal open title="Vygenerovat dokument ze šablony" onClose={onClose}>
      {loading ? (
        <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : (
        <div className="space-y-4">
          <div>
            <Label>Šablona (smluvní text) *</Label>
            <select value={selectedTemplate} onChange={e => setSelectedTemplate(e.target.value)}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <option value="">— Vyberte šablonu —</option>
              {templates.map(t => (
                <option key={t.id} value={t.id}>{TYPE_LABELS[t.type] || t.type} — {t.name}</option>
              ))}
            </select>
          </div>
          <div>
            <Label>Rezervace *</Label>
            <select value={selectedBooking} onChange={e => setSelectedBooking(e.target.value)}
              className="w-full rounded-btn text-sm outline-none"
              style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              <option value="">— Vyberte rezervaci —</option>
              {bookings.map(b => (
                <option key={b.id} value={b.id}>
                  {b.profiles?.full_name || '—'} — {b.motorcycles?.model || '—'} ({b.start_date || '—'})
                </option>
              ))}
            </select>
          </div>
        </div>
      )}
      {err && <p className="text-sm mt-3" style={{ color: '#dc2626' }}>{err}</p>}
      {success && <p className="text-sm mt-3" style={{ color: '#1a8a18' }}>Dokument úspěšně vygenerován.</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zavřít</Button>
        <Button green onClick={handleGenerate} disabled={generating || !selectedTemplate || !selectedBooking}>
          {generating ? 'Generuji…' : 'Vygenerovat'}
        </Button>
      </div>
    </Modal>
  )
}

function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function CheckboxFilterGroup({ label, options, selected, onChange }) {
  function toggle(value) {
    if (selected.includes(value)) {
      onChange(selected.filter(v => v !== value))
    } else {
      onChange([...selected, value])
    }
  }

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(opt => (
        <label key={opt.value} className="flex items-center gap-1 cursor-pointer text-sm" style={{ color: '#1a2e22' }}>
          <input
            type="checkbox"
            checked={selected.includes(opt.value)}
            onChange={() => toggle(opt.value)}
            className="cursor-pointer"
            style={{ accentColor: '#1a8a18' }}
          />
          <span className={selected.includes(opt.value) ? 'font-bold' : ''}>{opt.label}</span>
        </label>
      ))}
    </div>
  )
}
