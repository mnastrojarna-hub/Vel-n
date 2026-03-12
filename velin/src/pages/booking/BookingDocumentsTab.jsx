import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import { loadInvoiceData, printInvoiceHtml, storeInvoicePdf, generateAdvanceInvoice, generatePaymentReceipt } from '../../lib/invoiceUtils'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'

const DOC_ICONS = {
  contract: '📋',
  rental_contract: '📋',
  protocol: '📝',
  handover_protocol: '📝',
  terms: '📜',
  invoice: '🧾',
}

const INV_TYPE_MAP = {
  proforma: { label: 'Zálohová faktura (ZF)', color: '#2563eb', bg: '#dbeafe' },
  advance: { label: 'Zálohová faktura (ZF)', color: '#2563eb', bg: '#dbeafe' },
  payment_receipt: { label: 'Daňový doklad (DP)', color: '#0891b2', bg: '#cffafe' },
  final: { label: 'Konečná faktura (KF)', color: '#1a8a18', bg: '#dcfce7' },
  shop_proforma: { label: 'Shop zálohová', color: '#8b5cf6', bg: '#ede9fe' },
  shop_final: { label: 'Shop konečná', color: '#059669', bg: '#d1fae5' },
}

export default function BookingDocumentsTab({ bookingId }) {
  const [docs, setDocs] = useState([])
  const [generatedDocs, setGeneratedDocs] = useState([])
  const [invoices, setInvoices] = useState([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(null)
  const [error, setError] = useState(null)
  const [viewDoc, setViewDoc] = useState(null)
  const [viewHtml, setViewHtml] = useState(null)
  const [debug, setDebug] = useState(null)
  const [dbTemplates, setDbTemplates] = useState({})

  useEffect(() => { loadAll(); loadDbTemplates() }, [bookingId])

  async function loadAll() {
    setLoading(true)
    const diag = { bookingId, docs: null, gen: null, inv: null, errors: [] }
    try {
      debugLog('BookingDocumentsTab', 'loadAll', { bookingId })
      const [docsRes, genRes, invRes] = await Promise.all([
        debugAction('documents.byBooking', 'BookingDocumentsTab', () =>
          supabase.from('documents').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })),
        debugAction('generated_documents.byBooking', 'BookingDocumentsTab', () =>
          supabase.from('generated_documents').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })),
        debugAction('invoices.byBooking', 'BookingDocumentsTab', () =>
          supabase.from('invoices').select('*').eq('booking_id', bookingId).order('issue_date', { ascending: false, nullsFirst: false })),
      ])
      // If generated_documents found, try to enrich with template info (separate query, no FK needed)
      if (genRes.data?.length > 0) {
        const templateIds = [...new Set(genRes.data.map(d => d.template_id).filter(Boolean))]
        if (templateIds.length > 0) {
          const { data: templates } = await supabase.from('document_templates').select('id, name, type, html_content').in('id', templateIds)
          if (templates) {
            const tplMap = Object.fromEntries(templates.map(t => [t.id, t]))
            genRes.data.forEach(d => { d.document_templates = tplMap[d.template_id] || null })
          }
        }
      }
      if (docsRes.error) diag.errors.push('documents: ' + docsRes.error.message)
      if (genRes.error) diag.errors.push('generated_documents: ' + genRes.error.message)
      if (invRes.error) diag.errors.push('invoices: ' + invRes.error.message)
      // Filter out invoice-synced documents to avoid duplicates
      // (trigger trg_sync_invoice_to_documents copies invoices → documents table)
      const INVOICE_SYNCED_TYPES = ['invoice_advance', 'payment_receipt', 'invoice_final', 'invoice_shop']
      const filteredDocs = (docsRes.data || []).filter(d => !INVOICE_SYNCED_TYPES.includes(d.type))
      diag.docs = filteredDocs.map(d => ({ type: d.type, file_path: d.file_path, file_name: d.file_name }))
      diag.docsRaw = (docsRes.data || []).length
      diag.docsFiltered = filteredDocs.length
      diag.gen = (genRes.data || []).map(d => ({ tpl_id: d.template_id, tpl_type: d.document_templates?.type, tpl_name: d.document_templates?.name, has_filled: !!d.filled_data, has_pdf: !!d.pdf_path }))
      diag.inv = (invRes.data || []).map(i => ({ type: i.type, number: i.number, total: i.total, status: i.status, has_pdf: !!i.pdf_path }))
      setDocs(filteredDocs)
      setGeneratedDocs(genRes.data || [])
      setInvoices(invRes.data || [])
    } catch (e) { debugError('BookingDocumentsTab', 'loadAll', e); setError(e.message); diag.errors.push('EXCEPTION: ' + e.message) }
    setDebug(diag)
    setLoading(false)
  }

  async function loadDbTemplates() {
    try {
      const { data } = await supabase.from('document_templates').select('type, content_html')
        .in('type', ['rental_contract', 'handover_protocol', 'vop'])
      if (data) {
        const map = {}
        data.forEach(t => { map[t.type] = t.content_html })
        setDbTemplates(map)
      }
    } catch {}
  }

  async function handleGenerate(templateSlug) {
    setGenerating(templateSlug); setError(null)
    try {
      debugLog('BookingDocumentsTab', 'handleGenerate', { templateSlug, bookingId })
      const { error: err } = await debugAction('functions.generate-document', 'BookingDocumentsTab', () =>
        supabase.functions.invoke('generate-document', {
          body: { template_slug: templateSlug, booking_id: bookingId },
        })
      )
      if (err) throw err
      await loadAll()
    } catch {
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
      customer_id_number: '',
      moto_model: moto.model || '—', moto_spz: moto.spz || '', moto_vin: moto.vin || '',
      moto_year: String(moto.year || ''),
      start_date: fmtDate(booking.start_date), end_date: fmtDate(booking.end_date),
      days: String(days), total_price: fmtPrice(booking.total_price || 0),
      daily_rate: fmtPrice(Math.round((booking.total_price || 0) / days)),
      booking_id: bookingId.slice(-8).toUpperCase(), booking_number: bookingId.slice(-8).toUpperCase(),
      today: fmtDate(new Date().toISOString()),
      start_time: booking.pickup_time || '', end_time: '24:00',
      rental_period: `${fmtDate(booking.start_date)} — ${fmtDate(booking.end_date)} (${days} dní)`,
      total_price_words: '',
      pickup_location: booking.pickup_address || 'Mezná 9, 393 01 Mezná',
      return_location: booking.return_address || 'Mezná 9, 393 01 Mezná',
      mileage: String(booking.mileage_start || ''),
      fuel_state: '', technical_state: '',
      today_time: new Date().toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' }),
      company_name: 'Bc. Petra Semorádová', company_address: 'Mezná 9, 393 01 Mezná',
      company_ico: '21874263', company_dic: '',
    }

    let html = getClientTemplate(templateSlug)
    if (!html) throw new Error(`Šablona '${templateSlug}' nebyla nalezena`)
    for (const [key, val] of Object.entries(vars)) {
      html = html.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
    }

    const docId = crypto.randomUUID()
    const { error: gErr } = await supabase.from('generated_documents').insert({
      id: docId, template_id: null, booking_id: bookingId,
      customer_id: customer.id || booking.user_id,
      filled_data: vars, pdf_path: null,
    })
    if (gErr) throw gErr

    const win = window.open('', '_blank')
    if (win) { win.document.write(html); win.document.close() }
  }

  function getClientTemplate(slug) {
    // Prefer DB templates (loaded from document_templates table)
    if (dbTemplates[slug]) return dbTemplates[slug]
    // Fallback to hardcoded minimal templates
    if (slug === 'rental_contract') {
      return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Smlouva o pronájmu</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">SMLOUVA O PRONÁJMU MOTOCYKLU</h1><p style="text-align:center;font-size:12px;color:#666">č. {{booking_number}} ze dne {{today}}</p><p>Pronajímatel: Bc. Petra Semorádová, IČO: 21874263</p><p>Nájemce: {{customer_name}}, {{customer_address}}</p><p>Motocykl: {{moto_model}} ({{moto_spz}}), VIN: {{moto_vin}}</p><p>Období: {{start_date}} — {{end_date}} ({{days}} dní)</p><p>Celkem: {{total_price}} Kč</p><p style="color:#b45309;font-size:11px;margin-top:24px">⚠ Toto je záložní šablona. Plné texty smluv najdete v Dokumenty → Smluvní texty.</p></div></body></html>`
    }
    if (slug === 'handover_protocol') {
      return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Předávací protokol</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px">PŘEDÁVACÍ PROTOKOL</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci č. {{booking_number}} ze dne {{today}}</p><p>Nájemce: {{customer_name}}</p><p>Motocykl: {{moto_model}} ({{moto_spz}}), VIN: {{moto_vin}}</p><p style="color:#b45309;font-size:11px;margin-top:24px">⚠ Toto je záložní šablona. Plné texty najdete v Dokumenty → Smluvní texty.</p></div></body></html>`
    }
    return null
  }

  async function handleDownload(doc) {
    try {
      // For invoices — generate HTML on-the-fly
      if (doc.number && doc.type) {
        const html = await generateInvoiceHtmlForDoc(doc)
        if (html) { downloadBlob(html, `faktura_${doc.number}.html`); return }
      }
      // For generated docs — try regenerate from filled_data
      if (doc.filled_data) {
        const html = rebuildFromFilledData(doc)
        if (html) { downloadBlob(html, doc.document_templates?.name || 'dokument.html'); return }
      }
      // Try storage as last resort
      const path = doc.pdf_path || doc.file_path
      if (path) {
        const { data, error: err } = await supabase.storage.from('documents').download(path)
        if (!err && data) {
          const url = URL.createObjectURL(data)
          const a = document.createElement('a'); a.href = url; a.download = doc.file_name || 'dokument.html'; a.click(); URL.revokeObjectURL(url)
          return
        }
      }
      setError('Soubor není dostupný')
    } catch (e) { setError(`Stažení selhalo: ${e.message}`) }
  }

  function downloadBlob(html, filename) {
    const blob = new Blob([html], { type: 'text/html' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a'); a.href = url; a.download = filename; a.click(); URL.revokeObjectURL(url)
  }

  function rebuildFromFilledData(doc) {
    if (!doc.filled_data) return null
    const v = doc.filled_data
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Dokument</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h2>${v.company_name || 'MotoGo24'}</h2><p>Zákazník: ${v.customer_name || '—'}</p><p>Motocykl: ${v.moto_model || '—'} (${v.moto_spz || ''})</p><p>Období: ${v.start_date || '—'} — ${v.end_date || '—'} (${v.days || '—'} dní)</p><p>Cena: ${v.total_price || '—'} Kč</p></div></body></html>`
  }

  async function generateInvoiceHtmlForDoc(inv) {
    try {
      const fullInv = await loadInvoiceData(inv.id)
      return generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
    } catch { return null }
  }

  async function handleViewGeneratedDoc(doc) {
    // 1) Try template + filled_data
    if (doc.document_templates?.html_content && doc.filled_data) {
      let html = doc.document_templates.html_content
      for (const [k, v] of Object.entries(doc.filled_data)) {
        html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v || '')
      }
      setViewHtml(html); setViewDoc(doc); return
    }
    // 2) Try client template + filled_data
    if (doc.filled_data) {
      const docType = doc.document_templates?.type || ''
      const slug = docType === 'rental_contract' ? 'rental_contract' : docType === 'handover_protocol' ? 'handover_protocol' : null
      if (slug) {
        let html = getClientTemplate(slug)
        if (html) {
          for (const [k, v] of Object.entries(doc.filled_data)) {
            html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v || '')
          }
          setViewHtml(html); setViewDoc(doc); return
        }
      }
      // 3) Minimal rebuild
      const html = rebuildFromFilledData(doc)
      if (html) { setViewHtml(html); setViewDoc(doc); return }
    }
    // 4) If no filled_data, regenerate from booking
    try {
      const { data: booking } = await supabase.from('bookings')
        .select('*, motorcycles(model, spz, vin, year), profiles(id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry)')
        .eq('id', bookingId).single()
      if (booking) {
        const customer = booking.profiles || {}
        const moto = booking.motorcycles || {}
        const days = Math.max(1, Math.ceil((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000))
        const fmtD = (d) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
        const fmtP = (n) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })
        const vars = {
          customer_name: customer.full_name || '—', customer_email: customer.email || '',
          customer_phone: customer.phone || '', customer_address: [customer.street, customer.city, customer.zip].filter(Boolean).join(', '),
          customer_ico: customer.ico || '', customer_dic: customer.dic || '',
          customer_license: customer.license_number || '', customer_license_expiry: fmtD(customer.license_expiry),
          customer_id_number: '',
          moto_model: moto.model || '—', moto_spz: moto.spz || '', moto_vin: moto.vin || '', moto_year: String(moto.year || ''),
          start_date: fmtD(booking.start_date), end_date: fmtD(booking.end_date),
          days: String(days), total_price: fmtP(booking.total_price || 0),
          daily_rate: fmtP(Math.round((booking.total_price || 0) / days)),
          booking_id: bookingId.slice(-8).toUpperCase(), booking_number: bookingId.slice(-8).toUpperCase(),
          today: fmtD(new Date().toISOString()),
          today_time: new Date().toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' }),
          start_time: booking.pickup_time || '', end_time: '24:00',
          rental_period: `${fmtD(booking.start_date)} — ${fmtD(booking.end_date)} (${days} dní)`,
          total_price_words: '',
          pickup_location: booking.pickup_address || 'Mezná 9, 393 01 Mezná',
          return_location: booking.return_address || 'Mezná 9, 393 01 Mezná',
          mileage: String(booking.mileage_start || ''),
          fuel_state: '', technical_state: '',
          company_name: 'Bc. Petra Semorádová', company_address: 'Mezná 9, 393 01 Mezná', company_ico: '21874263', company_dic: '',
        }
        const docType = doc.document_templates?.type || ''
        const slug = docType === 'handover_protocol' ? 'handover_protocol' : 'rental_contract'
        let html = getClientTemplate(slug)
        if (html) {
          for (const [k, v] of Object.entries(vars)) {
            html = html.replace(new RegExp(`\\{\\{${k}\\}\\}`, 'g'), v || '')
          }
          setViewHtml(html); setViewDoc(doc); return
        }
      }
    } catch {}
    // 5) Try storage as absolute last resort
    const path = doc.pdf_path || doc.file_path
    if (path) {
      try {
        const { data, error: err } = await supabase.storage.from('documents').download(path)
        if (!err) { setViewHtml(await data.text()); setViewDoc(doc); return }
      } catch {}
    }
    setError('Dokument nemá obsah — zkuste jej znovu vygenerovat')
  }

  async function handleViewDoc(doc) {
    // For invoice-type docs from documents table (created by trigger), generate invoice HTML
    const INVOICE_DOC_TYPES = ['invoice', 'invoice_advance', 'payment_receipt', 'invoice_final', 'invoice_shop']
    if (INVOICE_DOC_TYPES.includes(doc.type) && doc.booking_id) {
      const inv = invoices.find(i => i.booking_id === doc.booking_id)
      if (inv) { handleViewInvoice(inv); return }
    }
    // For contract/protocol — regenerate from template (no storage needed)
    if (doc.type === 'rental_contract' || doc.type === 'contract') {
      handleViewGeneratedDoc({ ...doc, document_templates: { type: 'rental_contract' } }); return
    }
    if (doc.type === 'handover_protocol' || doc.type === 'protocol') {
      handleViewGeneratedDoc({ ...doc, document_templates: { type: 'handover_protocol' } }); return
    }
    // For VOP — try storage, fallback to inline notice
    const path = doc.pdf_path || doc.file_path
    if (!path) { setError('Dokument nemá cestu k souboru'); return }
    try {
      const { data, error: err } = await supabase.storage.from('documents').download(path)
      if (err) throw err
      const text = await data.text()
      setViewHtml(text)
      setViewDoc(doc)
    } catch {
      // VOP and other docs without storage — show info message
      const label = doc.file_name || doc.type || 'Dokument'
      setViewHtml(`<html><body style="font-family:sans-serif;padding:40px;text-align:center;color:#666"><h2>${label}</h2><p>Soubor není uložen v online úložišti.</p><p style="font-size:13px">Pokud máte PDF verzi, nahrajte ji do storage bucketu <code>documents</code>.</p></body></html>`)
      setViewDoc(doc)
    }
  }

  async function handleViewInvoice(inv) {
    // Always generate HTML from template on-the-fly (storage bucket may not exist)
    try {
      const fullInv = await loadInvoiceData(inv.id)
      const html = generateInvoiceHtml({
        ...fullInv,
        customer: fullInv.profiles || {},
        items: fullInv.items || [],
      })
      setViewHtml(html)
      setViewDoc(inv)
    } catch (e) {
      setError(`Náhled faktury selhal: ${e.message}`)
    }
  }

  async function handlePrintInvoice(inv) {
    try {
      const fullInv = await loadInvoiceData(inv.id)
      const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
      printInvoiceHtml(html)
    } catch (e) {
      setError(`Tisk faktury selhal: ${e.message}`)
    }
  }

  async function handleDeleteInvoice(inv) {
    if (!window.confirm(`Opravdu smazat ${inv.number || 'fakturu'}? Tato akce je nevratná.`)) return
    try {
      // Delete synced documents from documents table (created by trigger)
      const { data: syncedDocs } = await supabase.from('documents').select('id, file_name').eq('booking_id', inv.booking_id)
      const toDelete = (syncedDocs || []).filter(d => d.file_name?.includes(inv.number))
      if (toDelete.length > 0) {
        await supabase.from('documents').delete().in('id', toDelete.map(d => d.id))
      }
      // Delete invoice items
      await supabase.from('invoice_items').delete().eq('invoice_id', inv.id)
      // Try to delete storage file if exists
      if (inv.pdf_path) {
        try { await supabase.storage.from('documents').remove([inv.pdf_path]) } catch {}
      }
      // Delete the invoice itself
      const { error: err } = await supabase.from('invoices').delete().eq('id', inv.id)
      if (err) throw err
      await loadAll()
    } catch (e) {
      setError(`Smazání faktury selhalo: ${e.message}`)
    }
  }

  async function handleStoreInvoice(inv) {
    try {
      const fullInv = await loadInvoiceData(inv.id)
      const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] })
      // Try storage, but don't fail if bucket doesn't exist
      try { await storeInvoicePdf(inv.id, html) } catch {}
      await loadAll()
    } catch (e) {
      setError(`Uložení selhalo: ${e.message}`)
    }
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-5">
      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {/* DIAGNOSTIKA — viditelný debug panel */}
      {debug && (
        <div className="p-3 rounded-card mb-3" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}>
          <strong>DIAGNOSTIKA (booking: ...{bookingId?.slice(-8)})</strong><br/>
          {debug.errors.length > 0 && <div style={{ color: '#dc2626' }}>CHYBY: {debug.errors.join(' | ')}</div>}
          <div>documents tabulka: {debug.docsRaw || 0} záznamů (zobrazeno {debug.docsFiltered || 0}, fakturní typy odfiltrovány) {debug.docs?.length > 0 && `[${debug.docs.map(d => d.type).join(', ')}]`}</div>
          <div>generated_documents: {debug.gen?.length || 0} záznamů {debug.gen?.length > 0 && `[${debug.gen.map(d => `${d.tpl_type||'?'}(filled:${d.has_filled},html:${d.has_html},pdf:${d.has_pdf})`).join(', ')}]`}</div>
          <div>invoices: {debug.inv?.length || 0} záznamů {debug.inv?.length > 0 && `[${debug.inv.map(i => `${i.type}/${i.number}/${i.total}Kč/${i.status}`).join(', ')}]`}</div>
        </div>
      )}

      {/* Generate buttons */}
      <div className="flex gap-3 flex-wrap">
        <Button green onClick={() => handleGenerate('rental_contract')} disabled={generating === 'rental_contract'}>
          {generating === 'rental_contract' ? 'Generuji...' : 'Vygenerovat smlouvu'}
        </Button>
        <Button green onClick={() => handleGenerate('handover_protocol')} disabled={generating === 'handover_protocol'}>
          {generating === 'handover_protocol' ? 'Generuji...' : 'Vygenerovat protokol'}
        </Button>
        {dbTemplates.vop && (
          <Button onClick={() => {
            setViewHtml(dbTemplates.vop)
            setViewDoc({ file_name: 'Obchodní podmínky (VOP)' })
          }}>
            Zobrazit VOP
          </Button>
        )}
      </div>

      {/* Invoices (ZF, DP, KF) */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Faktury a daňové doklady</h3>
        {invoices.length === 0 ? (
          <div>
            <p style={{ color: '#1a2e22', fontSize: 13, marginBottom: 8 }}>Žádné faktury k této rezervaci</p>
            <Button green onClick={async () => {
              setGenerating('invoices'); setError(null)
              try {
                await generateAdvanceInvoice(bookingId, 'booking')
                await generatePaymentReceipt(bookingId, 'booking')
                await loadAll()
              } catch (e) { setError(`Generování faktur selhalo: ${e.message}`) }
              setGenerating(null)
            }} disabled={generating === 'invoices'}>
              {generating === 'invoices' ? 'Generuji...' : 'Vygenerovat ZF + DP'}
            </Button>
          </div>
        ) : (
          invoices.map(inv => {
            const tp = INV_TYPE_MAP[inv.type] || { label: inv.type || 'Faktura', color: '#1a2e22', bg: '#f3f4f6' }
            return (
              <div key={inv.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer hover:shadow-sm transition-shadow"
                style={{ background: '#f1faf7' }} onClick={() => handleViewInvoice(inv)}>
                <span style={{ fontSize: 16 }}>🧾</span>
                <span className="text-sm font-bold font-mono">{inv.number || '—'}</span>
                <Badge label={tp.label} color={tp.color} bg={tp.bg} />
                <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>
                  {(inv.total || 0).toLocaleString('cs-CZ')} Kč
                </span>
                <span className="text-sm" style={{ color: '#1a2e22' }}>{inv.issue_date || '—'}</span>
                <div className="flex gap-2 ml-auto" onClick={e => e.stopPropagation()}>
                  <button onClick={() => handleViewInvoice(inv)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#2563eb', background: 'none', border: 'none' }}>Náhled</button>
                  <button onClick={() => handlePrintInvoice(inv)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Tisk</button>
                  <button onClick={() => handleDownload(inv)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stáhnout</button>
                  <button onClick={() => handleDeleteInvoice(inv)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button>
                </div>
              </div>
            )
          })
        )}
      </Card>

      {/* Generated documents */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Vygenerované dokumenty</h3>
        {generatedDocs.length === 0 ? (
          <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné vygenerované dokumenty</p>
        ) : (
          generatedDocs.map(d => {
            const docType = d.document_templates?.type || 'contract'
            return (
              <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer hover:shadow-sm transition-shadow"
                style={{ background: '#f1faf7' }} onClick={() => handleViewGeneratedDoc(d)}>
                <span style={{ fontSize: 16 }}>{DOC_ICONS[docType] || '📄'}</span>
                <div className="flex-1">
                  <span className="text-sm font-bold">{d.document_templates?.name || 'Dokument'}</span>
                  <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{d.created_at?.slice(0, 10)}</span>
                </div>
                <div className="flex gap-2" onClick={e => e.stopPropagation()}>
                  <button onClick={() => handleViewGeneratedDoc(d)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button>
                  <button onClick={() => handleDownload(d)} className="text-sm font-bold cursor-pointer"
                    style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stáhnout</button>
                </div>
              </div>
            )
          })
        )}
      </Card>

      {/* Uploaded documents (nahrané doklady) */}
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Nahrané doklady</h3>
        {docs.length === 0 ? (
          <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné nahrané doklady</p>
        ) : (
          docs.map(d => (
            <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer hover:shadow-sm transition-shadow"
              style={{ background: '#f1faf7' }} onClick={() => (d.file_path || d.pdf_path) ? handleViewDoc(d) : null}>
              <span style={{ fontSize: 16 }}>{DOC_ICONS[d.type] || '📄'}</span>
              <div className="flex-1">
                <span className="text-sm font-bold">{d.file_name || d.type || 'Dokument'}</span>
                <span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{d.created_at?.slice(0, 10)}</span>
              </div>
              <div className="flex gap-2" onClick={e => e.stopPropagation()}>
                {(d.file_path || d.pdf_path) && (
                  <>
                    <button onClick={() => handleViewDoc(d)} className="text-sm font-bold cursor-pointer"
                      style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button>
                    <button onClick={() => handleDownload(d)} className="text-sm font-bold cursor-pointer"
                      style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stáhnout</button>
                  </>
                )}
              </div>
            </div>
          ))
        )}
      </Card>

      {/* Document/Invoice preview modal */}
      {viewDoc && (
        <Modal open title={viewDoc.number ? `Faktura ${viewDoc.number}` : (viewDoc.document_templates?.name || viewDoc.file_name || 'Dokument')} onClose={() => { setViewDoc(null); setViewHtml(null) }} wide>
          {viewHtml ? (
            <div className="border rounded-lg overflow-auto" style={{ maxHeight: 600, background: '#fff' }}>
              <iframe
                srcDoc={viewHtml}
                style={{ width: '100%', height: 550, border: 'none' }}
                title="Náhled dokumentu"
              />
            </div>
          ) : (
            <div className="py-8 text-center" style={{ color: '#1a2e22', fontSize: 13 }}>
              Dokument nemá náhled.
            </div>
          )}
          <div className="flex justify-end gap-3 mt-4">
            {viewHtml && (
              <Button onClick={() => {
                const win = window.open('', '_blank')
                if (win) { win.document.write(viewHtml); win.document.close(); win.onload = () => win.print() }
              }}>Tisk / PDF</Button>
            )}
            {(viewDoc.pdf_path || viewDoc.file_path) && <Button onClick={() => handleDownload(viewDoc)}>Stáhnout</Button>}
            <Button onClick={() => { setViewDoc(null); setViewHtml(null) }}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
