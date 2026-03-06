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
      // Try edge function first
      const { error: err } = await supabase.functions.invoke('generate-document', {
        body: { template_slug: templateSlug, booking_id: bookingId },
      })
      if (err) throw err
      await loadAll()
    } catch {
      // Fallback: client-side generation
      try {
        await generateClientSide(templateSlug)
        await loadAll()
      } catch (e2) {
        setError(`Generování selhalo: ${e2.message}`)
      }
    }
    setGenerating(null)
  }

  async function generateClientSide(templateSlug) {
    const { data: booking, error: bErr } = await supabase
      .from('bookings')
      .select('*, motorcycles(model, spz, vin, year), profiles(id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry)')
      .eq('id', bookingId).single()
    if (bErr || !booking) throw new Error('Rezervace nenalezena')

    const customer = booking.profiles || {}
    const moto = booking.motorcycles || {}
    const days = Math.max(1, Math.ceil((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000))
    const fmtDate = (d) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
    const fmtPrice = (n) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

    const vars = {
      customer_name: customer.full_name || '—', customer_email: customer.email || '',
      customer_phone: customer.phone || '', customer_address: [customer.street, customer.city, customer.zip, customer.country].filter(Boolean).join(', ') || '',
      customer_ico: customer.ico || '', customer_dic: customer.dic || '',
      customer_license: customer.license_number || '',
      customer_license_expiry: fmtDate(customer.license_expiry),
      moto_model: moto.model || '—', moto_spz: moto.spz || '', moto_vin: moto.vin || '',
      moto_year: String(moto.year || ''),
      start_date: fmtDate(booking.start_date), end_date: fmtDate(booking.end_date),
      days: String(days), total_price: fmtPrice(booking.total_price || 0),
      daily_rate: fmtPrice(Math.round((booking.total_price || 0) / days)),
      booking_id: bookingId.slice(0, 8), booking_number: bookingId.slice(0, 8).toUpperCase(),
      today: fmtDate(new Date().toISOString()),
      company_name: 'MotoGo24 s.r.o.', company_address: 'Mezná 9, 393 01 Pelhřimov',
      company_ico: '12345678', company_dic: 'CZ12345678',
    }

    let html = getClientTemplate(templateSlug)
    if (!html) throw new Error(`Šablona '${templateSlug}' nebyla nalezena`)
    for (const [key, val] of Object.entries(vars)) {
      html = html.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
    }

    // Store as generated_documents record
    const docId = crypto.randomUUID()
    const { error: gErr } = await supabase.from('generated_documents').insert({
      id: docId, template_id: null, booking_id: bookingId,
      customer_id: customer.id || booking.user_id,
      filled_data: vars, pdf_path: null,
    })
    if (gErr) throw gErr

    // Open in new tab for printing
    const win = window.open('', '_blank')
    if (win) { win.document.write(html); win.document.close() }
  }

  function getClientTemplate(slug) {
    if (slug === 'rental_contract') {
      return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Smlouva o pronájmu</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">SMLOUVA O PRONÁJMU MOTOCYKLU</h1><p style="text-align:center;font-size:12px;color:#666">č. {{booking_number}} ze dne {{today}}</p><div style="display:flex;gap:24px;margin:24px 0"><div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px"><p style="margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Pronajímatel</p><p style="margin:0;font-weight:700">{{company_name}}</p><p style="margin:2px 0;font-size:12px">{{company_address}}</p><p style="margin:2px 0;font-size:12px">IČO: {{company_ico}} | DIČ: {{company_dic}}</p></div><div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px"><p style="margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Nájemce</p><p style="margin:0;font-weight:700">{{customer_name}}</p><p style="margin:2px 0;font-size:12px">{{customer_address}}</p><p style="margin:2px 0;font-size:12px">Tel: {{customer_phone}} | Email: {{customer_email}}</p><p style="margin:2px 0;font-size:12px">ŘP: {{customer_license}} (platnost do {{customer_license_expiry}})</p></div></div><h3 style="font-size:13px;margin-top:24px">I. Předmět pronájmu</h3><table style="width:100%;border-collapse:collapse;font-size:12px;margin:8px 0"><tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600;width:120px">Model</td><td style="padding:4px 8px">{{moto_model}}</td></tr><tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600">SPZ</td><td style="padding:4px 8px">{{moto_spz}}</td></tr><tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600">VIN</td><td style="padding:4px 8px">{{moto_vin}}</td></tr><tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600">Rok výroby</td><td style="padding:4px 8px">{{moto_year}}</td></tr></table><h3 style="font-size:13px">II. Doba pronájmu</h3><p style="font-size:12px">Od: <strong>{{start_date}}</strong> do: <strong>{{end_date}}</strong> ({{days}} dní)</p><h3 style="font-size:13px">III. Cena</h3><p style="font-size:12px">Denní sazba: <strong>{{daily_rate}} Kč</strong> | Celkem: <strong>{{total_price}} Kč</strong> vč. DPH</p><div style="margin-top:48px;display:flex;justify-content:space-between"><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Pronajímatel</div></div><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Nájemce — {{customer_name}}</div></div></div></div></body></html>`
    }
    if (slug === 'handover_protocol') {
      return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Předávací protokol</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px">PŘEDÁVACÍ PROTOKOL</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci č. {{booking_number}} ze dne {{today}}</p><table style="width:100%;border-collapse:collapse;font-size:12px;margin:20px 0"><tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600;width:160px">Zákazník</td><td style="padding:6px 10px">{{customer_name}}</td></tr><tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">Motocykl</td><td style="padding:6px 10px">{{moto_model}} ({{moto_spz}})</td></tr><tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">VIN</td><td style="padding:6px 10px">{{moto_vin}}</td></tr><tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">Období</td><td style="padding:6px 10px">{{start_date}} — {{end_date}}</td></tr></table><h3 style="font-size:13px">Stav při předání</h3><table style="width:100%;border-collapse:collapse;font-size:12px;margin:8px 0;border:1px solid #ddd"><tr><td style="padding:8px;border:1px solid #ddd;width:50%">Stav km:</td><td style="padding:8px;border:1px solid #ddd"></td></tr><tr><td style="padding:8px;border:1px solid #ddd">Stav paliva:</td><td style="padding:8px;border:1px solid #ddd"></td></tr><tr><td style="padding:8px;border:1px solid #ddd">Viditelné poškození:</td><td style="padding:8px;border:1px solid #ddd"></td></tr><tr><td style="padding:8px;border:1px solid #ddd">Příslušenství:</td><td style="padding:8px;border:1px solid #ddd"></td></tr><tr><td style="padding:8px;border:1px solid #ddd">Poznámky:</td><td style="padding:8px;border:1px solid #ddd"></td></tr></table><div style="margin-top:48px;display:flex;justify-content:space-between"><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Předávající</div></div><div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Přebírající — {{customer_name}}</div></div></div></div></body></html>`
    }
    return null
  }

  async function handleDownload(doc) {
    const path = doc.pdf_path || doc.file_path
    if (!path) return
    try {
      const { data, error: err } = await supabase.storage.from('documents').download(path)
      if (err) throw err
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = doc.document_templates?.name || doc.file_name || 'dokument.pdf'
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
            const docType = d.document_templates?.type || 'contract'
            return (
              <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2" style={{ background: '#f1faf7' }}>
                <span style={{ fontSize: 16 }}>{DOC_ICONS[docType] || '📄'}</span>
                <div className="flex-1">
                  <span className="text-sm font-bold">{d.document_templates?.name || 'Dokument'}</span>
                  <span className="text-xs ml-3" style={{ color: '#8aab99' }}>{d.created_at?.slice(0, 10)}</span>
                </div>
                <div className="flex gap-2">
                  {d.pdf_path && (
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
              <span className="text-sm font-bold">{d.file_name || d.type || 'Dokument'}</span>
              <span className="text-xs" style={{ color: '#8aab99' }}>{d.created_at?.slice(0, 10)}</span>
            </div>
          ))
        )}
      </Card>

      {viewDoc && (
        <Modal open title={viewDoc.document_templates?.name || 'Dokument'} onClose={() => setViewDoc(null)} wide>
          <div className="py-8 text-center" style={{ color: '#8aab99', fontSize: 13 }}>
            {viewDoc.pdf_path ? 'Stáhněte PDF verzi dokumentu.' : 'Dokument nemá PDF.'}
          </div>
          <div className="flex justify-end gap-3 mt-4">
            {viewDoc.pdf_path && <Button onClick={() => handleDownload(viewDoc)}>Stáhnout PDF</Button>}
            <Button onClick={() => setViewDoc(null)}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
