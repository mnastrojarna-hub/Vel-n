import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'

const DOC_ICONS = {
  contract: '📋',
  protocol: '📝',
  terms: '📜',
}

export default function BookingDocumentsTab({ bookingId }) {
  const [docs, setDocs] = useState([])
  const [generatedDocs, setGeneratedDocs] = useState([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(null)
  const [error, setError] = useState(null)
  const [viewDoc, setViewDoc] = useState(null)

  useEffect(() => { loadAll() }, [bookingId])

  async function loadAll() {
    setLoading(true)
    try {
      const [docsRes, genRes] = await Promise.all([
        supabase.from('documents').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false }),
        supabase.from('generated_documents').select('*, document_templates(name, type)').eq('booking_id', bookingId).order('created_at', { ascending: false }),
      ])
      setDocs(docsRes.data || [])
      setGeneratedDocs(genRes.data || [])
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  async function handleGenerate(templateSlug) {
    setGenerating(templateSlug); setError(null)
    try {
      const { error: err } = await supabase.functions.invoke('generate-document', {
        body: { template_slug: templateSlug, booking_id: bookingId },
      })
      if (err) throw err
      await loadAll()
    } catch (e) {
      setError(`Generování selhalo: ${e.message || 'Edge Function nemusí být nasazena.'}`)
    }
    setGenerating(null)
  }

  async function handleDownload(doc) {
    if (!doc.file_path) return
    try {
      const { data, error: err } = await supabase.storage.from('documents').download(doc.file_path)
      if (err) throw err
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = doc.name || 'dokument.pdf'
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) { setError(`Stažení selhalo: ${e.message}`) }
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-5">
      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* Generate buttons */}
      <div className="flex gap-3">
        <Button green onClick={() => handleGenerate('rental_contract')} disabled={generating === 'rental_contract'}>
          {generating === 'rental_contract' ? 'Generuji…' : '📋 Vygenerovat smlouvu'}
        </Button>
        <Button green onClick={() => handleGenerate('handover_protocol')} disabled={generating === 'handover_protocol'}>
          {generating === 'handover_protocol' ? 'Generuji…' : '📝 Vygenerovat protokol'}
        </Button>
      </div>

      {/* Generated documents */}
      <Card>
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Vygenerované dokumenty</h3>
        {generatedDocs.length === 0 ? (
          <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné vygenerované dokumenty</p>
        ) : (
          generatedDocs.map(d => {
            const docType = d.document_templates?.type || d.type || 'contract'
            return (
              <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
                <span style={{ fontSize: 16 }}>{DOC_ICONS[docType] || '📄'}</span>
                <div className="flex-1">
                  <span className="text-sm font-bold">{d.name || d.document_templates?.name || 'Dokument'}</span>
                  <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{d.created_at?.slice(0, 10)}</span>
                  {d.signed && <span className="text-[10px] ml-2 font-bold" style={{ color: '#1a8a18' }}>Podepsáno</span>}
                </div>
                <div className="flex gap-2">
                  {d.content_html && (
                    <button onClick={() => setViewDoc(d)} className="text-[10px] font-bold cursor-pointer"
                      style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button>
                  )}
                  {d.file_path && (
                    <button onClick={() => handleDownload(d)} className="text-[10px] font-bold cursor-pointer"
                      style={{ color: '#4a6357', background: 'none', border: 'none' }}>Stáhnout</button>
                  )}
                </div>
              </div>
            )
          })
        )}
      </Card>

      {/* Uploaded documents */}
      <Card>
        <h3 className="text-[10px] font-extrabold uppercase tracking-wide mb-3" style={{ color: '#8aab99' }}>Nahrané doklady</h3>
        {docs.length === 0 ? (
          <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné nahrané doklady</p>
        ) : (
          docs.map(d => (
            <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
              <span className="text-sm font-bold">{d.name || d.type || 'Dokument'}</span>
              <span className="text-xs" style={{ color: '#8aab99' }}>{d.created_at?.slice(0, 10)}</span>
            </div>
          ))
        )}
      </Card>

      {viewDoc && (
        <Modal open title={viewDoc.name || 'Dokument'} onClose={() => setViewDoc(null)} wide>
          <div className="rounded-card" style={{ padding: 16, background: '#fff', border: '1px solid #d4e8e0', maxHeight: 500, overflow: 'auto' }}
            dangerouslySetInnerHTML={{ __html: viewDoc.content_html }} />
          <div className="flex justify-end gap-3 mt-4">
            {viewDoc.file_path && <Button onClick={() => handleDownload(viewDoc)}>Stáhnout PDF</Button>}
            <Button onClick={() => setViewDoc(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
