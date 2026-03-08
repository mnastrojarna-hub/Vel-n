import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const SAMPLE_VARS = {
  customer_name: 'Jan Novák',
  customer_email: 'jan@novak.cz',
  customer_phone: '+420 777 123 456',
  customer_address: 'Hlavní 1, 393 01 Pelhřimov',
  moto_model: 'BMW R 1200 GS Adventure',
  moto_spz: '4A2 1234',
  start_date: '15. 6. 2026',
  end_date: '18. 6. 2026',
  total_price: '7 800 Kč',
  deposit: '3 000 Kč',
  pickup_location: 'Mezná 9, 393 01 Mezná',
  booking_number: '#RES-2026-0099',
  contract_date: '14. 6. 2026',
  company_name: 'MotoGo24 s.r.o.',
  company_ico: '12345678',
}

export default function TemplatesTab() {
  const [templates, setTemplates] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [regenerate, setRegenerate] = useState(null)
  const [search, setSearch] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('document_templates')
      .select('*')
      .order('name')
    if (err) setError(err.message)
    else setTemplates(data || [])
    setLoading(false)
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error) return <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>

  const filtered = templates.filter(t => {
    if (!search) return true
    const s = search.toLowerCase()
    return (t.name || '').toLowerCase().includes(s) || (t.type || '').toLowerCase().includes(s)
  })

  return (
    <div>
      <div className="flex items-center gap-3 mb-4">
        <input type="text" value={search} onChange={e => setSearch(e.target.value)}
          placeholder="Hledat šablonu…"
          className="rounded-btn text-xs outline-none"
          style={{ padding: '8px 14px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#4a6357', minWidth: 200 }} />
      </div>
      {filtered.length === 0 ? (
        <Card><p style={{ color: '#8aab99', fontSize: 13 }}>Žádné šablony</p></Card>
      ) : (
        <div className="grid grid-cols-2 gap-4">
          {filtered.map(t => (
            <Card key={t.id}>
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <h4 className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{t.name}</h4>
                  <span className="text-[10px] font-bold" style={{ color: '#8aab99' }}>v{t.version || 1}</span>
                </div>
                <span className="text-[10px] font-extrabold uppercase tracking-wide" style={{ color: '#8aab99' }}>{t.type}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[10px]" style={{ color: '#8aab99' }}>
                  Proměnné: {extractVars(t.html_content).join(', ') || '—'}
                </span>
              </div>
              <div className="flex items-center gap-2 mt-3">
                <Button onClick={() => setEditing(t)} style={{ padding: '4px 14px', fontSize: 10 }}>
                  Upravit
                </Button>
                <Button onClick={() => setRegenerate(t)} style={{ padding: '4px 14px', fontSize: 10 }}>
                  Znovu vygenerovat
                </Button>
              </div>
            </Card>
          ))}
        </div>
      )}

      {editing && (
        <EditTemplateModal
          template={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load() }}
        />
      )}

      {regenerate && (
        <RegenerateModal
          template={regenerate}
          onClose={() => setRegenerate(null)}
        />
      )}
    </div>
  )
}

function extractVars(content) {
  if (!content) return []
  const matches = content.match(/\{\{(\w+)\}\}/g)
  return matches ? [...new Set(matches.map(m => m.replace(/[{}]/g, '')))] : []
}

function EditTemplateModal({ template, onClose, onSaved }) {
  const [name, setName] = useState(template.name || '')
  const [content, setContent] = useState(template.html_content || '')
  const [saving, setSaving] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [err, setErr] = useState(null)
  const [showPreview, setShowPreview] = useState(false)

  function getPreviewHtml() {
    let html = content
    for (const [k, v] of Object.entries(SAMPLE_VARS)) {
      html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v)
    }
    return html
  }

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const newVersion = (template.version || 1) + 1
      const { data: { user } } = await supabase.auth.getUser()
      const updatePayload = { name, html_content: content, version: newVersion, updated_by: user?.id }
      const result = await debugAction('template.update', 'EditTemplateModal', () =>
        supabase.from('document_templates').update(updatePayload).eq('id', template.id)
      , updatePayload)
      if (result?.error) throw result.error
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'template_updated', details: { template_id: template.id, version: newVersion },
      })
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function handlePdfUpload(e) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true); setErr(null)
    try {
      const version = (template.version || 1) + 1
      const path = `templates/${template.id}_v${version}.pdf`
      const uploadResult = await debugAction('template.pdfUpload', 'EditTemplateModal', () =>
        supabase.storage.from('documents').upload(path, file, { upsert: true })
      , { template_id: template.id, path, fileName: file.name })
      if (uploadResult?.error) throw uploadResult.error
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id, action: 'template_pdf_uploaded', details: { template_id: template.id, path },
      })
    } catch (e) { setErr(e.message) }
    setUploading(false)
  }

  return (
    <Modal open title={`Upravit šablonu: ${template.name}`} onClose={onClose} wide>
      <div className="space-y-3">
        <div>
          <Label>Název</Label>
          <input type="text" value={name} onChange={e => setName(e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        <div>
          <Label>Obsah šablony</Label>
          <textarea value={content} onChange={e => setContent(e.target.value)}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={{ padding: '12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 300, resize: 'vertical' }} />
        </div>
        <p className="text-[10px]" style={{ color: '#8aab99' }}>
          Proměnné: {extractVars(content).map(v => `{{${v}}}`).join(', ') || 'žádné'}
        </p>

        {/* PDF upload */}
        <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <Label>PDF šablona</Label>
          <input type="file" accept=".pdf" onChange={handlePdfUpload}
            className="text-xs" style={{ color: '#4a6357' }} />
          {uploading && <span className="text-[10px] ml-2" style={{ color: '#8aab99' }}>Nahrávám…</span>}
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-between gap-3 mt-5">
        <Button onClick={() => setShowPreview(true)}>Náhled s ukázkovými daty</Button>
        <div className="flex gap-2">
          <Button onClick={onClose}>Zrušit</Button>
          <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
        </div>
      </div>

      {showPreview && (
        <Modal open title="Náhled šablony" onClose={() => setShowPreview(false)} wide>
          <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 500, overflow: 'auto' }}
            dangerouslySetInnerHTML={{ __html: getPreviewHtml() }} />
          <div className="flex justify-end mt-4">
            <Button onClick={() => setShowPreview(false)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </Modal>
  )
}

function RegenerateModal({ template, onClose }) {
  const [bookings, setBookings] = useState([])
  const [selectedBooking, setSelectedBooking] = useState('')
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)
  const [err, setErr] = useState(null)
  const [success, setSuccess] = useState(false)

  useEffect(() => {
    supabase.from('bookings')
      .select('id, start_date, profiles(full_name), motorcycles(model)')
      .neq('status', 'cancelled')
      .order('created_at', { ascending: false })
      .limit(20)
      .then(({ data }) => { setBookings(data || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  async function handleGenerate() {
    if (!selectedBooking) return
    setGenerating(true); setErr(null); setSuccess(false)
    try {
      // Load booking data for template filling
      const { data: booking, error: bErr } = await supabase
        .from('bookings')
        .select('*, profiles(full_name, email, phone, street, city, zip), motorcycles(model, spz)')
        .eq('id', selectedBooking)
        .single()
      if (bErr) throw bErr

      // Fill template variables
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
        booking_number: booking.id?.slice(0, 8) || '',
        contract_date: new Date().toLocaleDateString('cs-CZ'),
        company_name: 'MotoGo24 s.r.o.',
        company_ico: '12345678',
      }

      let filledHtml = template.html_content || ''
      for (const [k, v] of Object.entries(vars)) {
        filledHtml = filledHtml.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v)
      }

      // Store generated document
      const blob = new Blob([filledHtml], { type: 'text/html' })
      const path = `generated/${template.id}_${selectedBooking}.html`
      const { error: upErr } = await supabase.storage.from('documents').upload(path, blob, { upsert: true })
      if (upErr) throw upErr

      // Create record
      const { data: { user } } = await supabase.auth.getUser()
      const { error: insErr } = await supabase.from('generated_documents').insert({
        template_id: template.id,
        booking_id: selectedBooking,
        customer_id: booking.customer_id || null,
        filled_data: vars,
        pdf_path: path,
        generated_by: user?.id,
      })
      if (insErr) throw insErr

      setSuccess(true)
    } catch (e) {
      setErr(`Generování selhalo: ${e.message}`)
    }
    setGenerating(false)
  }

  return (
    <Modal open title={`Znovu vygenerovat: ${template.name}`} onClose={onClose}>
      <Label>Vyberte rezervaci</Label>
      {loading ? (
        <div className="py-4 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : (
        <select value={selectedBooking} onChange={e => setSelectedBooking(e.target.value)}
          className="w-full rounded-btn text-sm outline-none mb-4"
          style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <option value="">— Vyberte rezervaci —</option>
          {bookings.map(b => (
            <option key={b.id} value={b.id}>
              {b.profiles?.full_name || '—'} — {b.motorcycles?.model || '—'} ({b.start_date || '—'})
            </option>
          ))}
        </select>
      )}
      {err && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{err}</p>}
      {success && <p className="text-sm mb-3" style={{ color: '#1a8a18' }}>Dokument úspěšně vygenerován.</p>}
      <div className="flex justify-end gap-3">
        <Button onClick={onClose}>Zavřít</Button>
        <Button green onClick={handleGenerate} disabled={generating || !selectedBooking}>
          {generating ? 'Generuji…' : 'Vygenerovat'}
        </Button>
      </div>
    </Modal>
  )
}

function Label({ children }) {
  return <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{children}</label>
}
