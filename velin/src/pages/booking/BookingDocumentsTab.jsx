import { useState, useEffect } from 'react'
import { openPrintWindow } from '../../lib/sanitize'
import { supabase } from '../../lib/supabase'
import { debugAction, debugLog, debugError } from '../../lib/debugLog'
import { generateInvoiceHtml } from '../../lib/invoiceTemplate'
import { loadInvoiceData, printInvoiceHtml, storeInvoicePdf, generateAdvanceInvoice, generatePaymentReceipt } from '../../lib/invoiceUtils'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import { getClientTemplate, buildDocVars, fillTemplate, rebuildFromFilledData } from './bookingDocTemplates'
import { DOC_ICONS, INV_TYPE_MAP } from './bookingDocConstants'
import BookingCustomerDocsStatus from './BookingCustomerDocsStatus'
import ElectronicProtocolModal from './ElectronicProtocolModal'

export default function BookingDocumentsTab({ bookingId, userId }) {
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
  const [protocolChoice, setProtocolChoice] = useState(null) // 'handover_protocol' | 'damage_protocol' — dialog tištěný/elektronický
  const [electronicProtocol, setElectronicProtocol] = useState(null) // typ otevřeného elektronického protokolu
  const [sendOffer, setSendOffer] = useState(null) // info uloženého el. protokolu → nabídka odeslání zákazníkovi
  const [sendingProtocol, setSendingProtocol] = useState(false)
  const [sendResult, setSendResult] = useState(null)

  useEffect(() => { loadAll(); loadDbTemplates() }, [bookingId])

  async function loadAll() {
    setLoading(true)
    const diag = { bookingId, docs: null, gen: null, inv: null, errors: [] }
    try {
      debugLog('BookingDocumentsTab', 'loadAll', { bookingId })
      const [docsRes, genRes, invRes] = await Promise.all([
        debugAction('documents.byBooking', 'BookingDocumentsTab', () => supabase.from('documents').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })),
        debugAction('generated_documents.byBooking', 'BookingDocumentsTab', () => supabase.from('generated_documents').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false })),
        debugAction('invoices.byBooking', 'BookingDocumentsTab', () => supabase.from('invoices').select('*').eq('booking_id', bookingId).order('issue_date', { ascending: false, nullsFirst: false })),
      ])
      if (genRes.data?.length > 0) {
        const templateIds = [...new Set(genRes.data.map(d => d.template_id).filter(Boolean))]
        if (templateIds.length > 0) {
          const { data: templates } = await supabase.from('document_templates').select('id, name, type, content_html').in('id', templateIds)
          if (templates) { const tplMap = Object.fromEntries(templates.map(t => [t.id, t])); genRes.data.forEach(d => { d.document_templates = tplMap[d.template_id] || null }) }
        }
      }
      if (docsRes.error) diag.errors.push('documents: ' + docsRes.error.message)
      if (genRes.error) diag.errors.push('generated_documents: ' + genRes.error.message)
      if (invRes.error) diag.errors.push('invoices: ' + invRes.error.message)
      const SYNCED_TYPES = ['invoice_advance', 'payment_receipt', 'invoice_final', 'invoice_shop', 'rental_contract', 'contract', 'vop', 'handover_protocol', 'damage_protocol', 'protocol_damage', 'gdpr']
      const filteredDocs = (docsRes.data || []).filter(d => !SYNCED_TYPES.includes(d.type))
      diag.docs = filteredDocs.map(d => ({ type: d.type, file_path: d.file_path, file_name: d.file_name }))
      diag.docsRaw = (docsRes.data || []).length; diag.docsFiltered = filteredDocs.length
      diag.gen = (genRes.data || []).map(d => ({ tpl_id: d.template_id, tpl_type: d.document_templates?.type, tpl_name: d.document_templates?.name, has_filled: !!d.filled_data, has_pdf: !!d.pdf_path }))
      diag.inv = (invRes.data || []).map(i => ({ type: i.type, number: i.number, total: i.total, status: i.status, has_pdf: !!i.pdf_path }))
      setDocs(filteredDocs); setGeneratedDocs(genRes.data || []); setInvoices(invRes.data || [])
    } catch (e) { debugError('BookingDocumentsTab', 'loadAll', e); setError(e.message); diag.errors.push('EXCEPTION: ' + e.message) }
    setDebug(diag); setLoading(false)
  }

  async function loadDbTemplates() {
    try {
      const { data } = await supabase.from('document_templates').select('type, content_html').in('type', ['rental_contract', 'handover_protocol', 'vop', 'damage_protocol', 'gdpr'])
      if (data) { const map = {}; data.forEach(t => { map[t.type] = t.content_html }); setDbTemplates(map) }
    } catch {}
  }

  async function handleGenerate(templateSlug) {
    setGenerating(templateSlug); setError(null)
    try {
      const { error: err } = await debugAction('functions.generate-document', 'BookingDocumentsTab', () => supabase.functions.invoke('generate-document', { body: { template_slug: templateSlug, booking_id: bookingId } }))
      if (err) throw err; await loadAll()
    } catch {
      try { await generateClientSide(templateSlug); await loadAll() }
      catch (e2) { setError(`Generovani selhalo: ${e2.message}`) }
    }
    setGenerating(null)
  }

  async function generateClientSide(templateSlug) {
    const { data: booking, error: bErr } = await supabase.from('bookings').select('*, motorcycles!moto_id(model, spz, vin, year, license_required)').eq('id', bookingId).single()
    if (bErr || !booking) throw new Error('Rezervace nenalezena: ' + (bErr?.message || 'no data'))
    let customer = {}
    if (booking.user_id) { const { data: prof } = await supabase.from('profiles').select('id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry').eq('id', booking.user_id).single(); if (prof) customer = prof }
    const vars = buildDocVars(booking, customer, bookingId)
    let html = getClientTemplate(templateSlug, dbTemplates)
    if (!html) throw new Error(`Sablona '${templateSlug}' nebyla nalezena`)
    html = fillTemplate(html, vars)
    const docId = crypto.randomUUID()
    const { error: gErr } = await supabase.from('generated_documents').insert({ id: docId, template_id: null, booking_id: bookingId, customer_id: customer.id || booking.user_id, filled_data: vars, pdf_path: null })
    if (gErr) throw gErr
    openPrintWindow(html, { autoPrint: false })
  }

  async function handleDownload(doc) {
    try {
      if (doc.number && doc.type) { const html = await generateInvoiceHtmlForDoc(doc); if (html) { downloadBlob(html, `faktura_${doc.number}.html`); return } }
      if (doc.filled_data) { const html = rebuildFromFilledData(doc); if (html) { downloadBlob(html, doc.document_templates?.name || 'dokument.html'); return } }
      const path = doc.pdf_path || doc.file_path
      if (path) { const { data, error: err } = await supabase.storage.from('documents').download(path); if (!err && data) { const url = URL.createObjectURL(data); const a = document.createElement('a'); a.href = url; a.download = doc.file_name || 'dokument.html'; a.click(); URL.revokeObjectURL(url); return } }
      setError('Soubor neni dostupny')
    } catch (e) { setError(`Stazeni selhalo: ${e.message}`) }
  }

  function downloadBlob(html, filename) { const b = new Blob([html], { type: 'text/html' }); const u = URL.createObjectURL(b); const a = document.createElement('a'); a.href = u; a.download = filename; a.click(); URL.revokeObjectURL(u) }

  async function generateInvoiceHtmlForDoc(inv) { try { const f = await loadInvoiceData(inv.id); return generateInvoiceHtml({ ...f, customer: f.profiles || {}, items: f.items || [] }) } catch { return null } }

  async function handleViewGeneratedDoc(doc) {
    if ((doc.document_templates?.content_html || doc.document_templates?.html_content) && doc.filled_data) {
      let html = doc.document_templates.content_html || doc.document_templates.html_content
      html = fillTemplate(html, doc.filled_data); setViewHtml(html); setViewDoc(doc); return
    }
    if (doc.filled_data) {
      const docType = doc.document_templates?.type || ''
      const KNOWN_SLUGS = ['rental_contract', 'handover_protocol', 'vop', 'damage_protocol', 'gdpr']
      const slug = KNOWN_SLUGS.includes(docType) ? docType : null
      if (slug) { let html = getClientTemplate(slug, dbTemplates); if (html) { html = fillTemplate(html, doc.filled_data); setViewHtml(html); setViewDoc(doc); return } }
      const html = rebuildFromFilledData(doc); if (html) { setViewHtml(html); setViewDoc(doc); return }
    }
    try {
      const { data: booking } = await supabase.from('bookings').select('*, motorcycles!moto_id(model, spz, vin, year, license_required)').eq('id', bookingId).single()
      if (booking) {
        let customer = {}
        if (booking.user_id) { const { data: prof } = await supabase.from('profiles').select('id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry').eq('id', booking.user_id).single(); if (prof) customer = prof }
        const vars = buildDocVars(booking, customer, bookingId)
        const docType = doc.document_templates?.type || ''
        const slug = ['handover_protocol', 'vop', 'damage_protocol', 'gdpr'].includes(docType) ? docType : 'rental_contract'
        let html = getClientTemplate(slug, dbTemplates)
        if (html) { html = fillTemplate(html, vars); setViewHtml(html); setViewDoc(doc); return }
      }
    } catch {}
    const path = doc.pdf_path || doc.file_path
    if (path) { try { const { data, error: err } = await supabase.storage.from('documents').download(path); if (!err) { setViewHtml(await data.text()); setViewDoc(doc); return } } catch {} }
    setError('Dokument nema obsah \u2014 zkuste jej znovu vygenerovat')
  }

  async function handleViewDoc(doc) {
    const INVOICE_DOC_TYPES = ['invoice', 'invoice_advance', 'payment_receipt', 'invoice_final', 'invoice_shop']
    if (INVOICE_DOC_TYPES.includes(doc.type) && doc.booking_id) { const inv = invoices.find(i => i.booking_id === doc.booking_id); if (inv) { handleViewInvoice(inv); return } }
    if (doc.type === 'rental_contract' || doc.type === 'contract') { handleViewGeneratedDoc({ ...doc, document_templates: { type: 'rental_contract' } }); return }
    if (doc.type === 'handover_protocol' || doc.type === 'protocol') { handleViewGeneratedDoc({ ...doc, document_templates: { type: 'handover_protocol' } }); return }
    if (doc.type === 'damage_protocol' || doc.type === 'protocol_damage') { handleViewGeneratedDoc({ ...doc, document_templates: { type: 'damage_protocol' } }); return }
    if (doc.type === 'gdpr') { handleViewGeneratedDoc({ ...doc, document_templates: { type: 'gdpr' } }); return }
    const path = doc.pdf_path || doc.file_path
    if (!path) { setError('Dokument nema cestu k souboru'); return }
    try { const { data, error: err } = await supabase.storage.from('documents').download(path); if (err) throw err; setViewHtml(await data.text()); setViewDoc(doc) }
    catch { const label = doc.file_name || doc.type || 'Dokument'; setViewHtml(`<html><body style="font-family:sans-serif;padding:40px;text-align:center;color:#666"><h2>${label}</h2><p>Soubor neni ulozen v online ulozisti.</p></body></html>`); setViewDoc(doc) }
  }

  async function handleViewInvoice(inv) {
    try { const fullInv = await loadInvoiceData(inv.id); const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] }); setViewHtml(html); setViewDoc(inv) }
    catch (e) { setError(`Nahled faktury selhal: ${e.message}`) }
  }

  async function handlePrintInvoice(inv) {
    try { const fullInv = await loadInvoiceData(inv.id); const html = generateInvoiceHtml({ ...fullInv, customer: fullInv.profiles || {}, items: fullInv.items || [] }); printInvoiceHtml(html) }
    catch (e) { setError(`Tisk faktury selhal: ${e.message}`) }
  }

  async function handleDeleteInvoice(inv) {
    if (!window.confirm(`Opravdu smazat ${inv.number || 'fakturu'}? Tato akce je nevratna.`)) return
    try {
      const { data: syncedDocs } = await supabase.from('documents').select('id, file_name').eq('booking_id', inv.booking_id)
      const toDelete = (syncedDocs || []).filter(d => d.file_name?.includes(inv.number))
      if (toDelete.length > 0) await supabase.from('documents').delete().in('id', toDelete.map(d => d.id))
      await supabase.from('invoice_items').delete().eq('invoice_id', inv.id)
      if (inv.pdf_path) { try { await supabase.storage.from('documents').remove([inv.pdf_path]) } catch {} }
      const { error: err } = await supabase.from('invoices').delete().eq('id', inv.id); if (err) throw err; await loadAll()
    } catch (e) { setError(`Smazani faktury selhalo: ${e.message}`) }
  }

  async function handleStoreInvoice(inv) {
    try { const f = await loadInvoiceData(inv.id); const h = generateInvoiceHtml({ ...f, customer: f.profiles || {}, items: f.items || [] }); try { await storeInvoicePdf(inv.id, h) } catch {}; await loadAll() }
    catch (e) { setError(`Ulozeni: ${e.message}`) }
  }

  // Přegeneruje doklad aktuálními údaji a PŘEPÍŠE stávající řádek (zachová číslo).
  // ZF/DP → generate-invoice regenerate:true; KF (final) → render_existing
  // (KF vystavuje DB trigger s číslem KF-…, regenerate by vyrobil jiný doklad FV).
  async function handleRegenerateInvoice(inv) {
    setGenerating(`regen-${inv.id}`); setError(null)
    try {
      let body
      if (inv.type === 'final' || inv.type === 'issued') body = { render_existing: true, booking_id: bookingId, type: 'final' }
      else if (inv.type === 'payment_receipt') body = { regenerate: true, booking_id: bookingId, type: 'payment_receipt', send_email: false }
      else body = { regenerate: true, booking_id: bookingId, type: 'advance', send_email: false } // advance/proforma → ZF
      const { error: err } = await debugAction('functions.generate-invoice.regen', 'BookingDocumentsTab', () => supabase.functions.invoke('generate-invoice', { body }), { invoice_id: inv.id, type: inv.type })
      if (err) throw err
      await loadAll()
    } catch (e) { setError(`Přegenerování selhalo: ${e.message}`) }
    setGenerating(null)
  }

  // Po uložení el. protokolu nabídne Velín odeslat ho zákazníkovi e-mailem.
  // Použije e-mailovou šablonu z Velína (email_templates), protokol jde v příloze (PDF/HTML).
  async function sendProtocolEmail(info) {
    if (!info?.customerEmail) { setSendResult('Zákazník nemá uložený e-mail.'); return }
    setSendingProtocol(true); setSendResult(null)
    try {
      const isDamage = info.type === 'damage_protocol'
      const slug = isDamage ? 'damage_protocol_sent' : 'handover_protocol_sent'
      const template_vars = {
        customer_name: info.customerName || '', moto: info.moto || '', moto_model: info.moto || '',
        rental_period: info.rentalPeriod || '', booking_number: info.bookingNumber || '', doc_name: info.docName || '',
      }
      const ext = info.pdfPath && info.pdfPath.toLowerCase().endsWith('.html') ? '.html' : '.pdf'
      const filename = `${(info.docName || 'protokol').replace(/[^\wÀ-ſ]+/g, '_')}${ext}`
      const attachment_paths = info.pdfPath ? [{ filename, path: info.pdfPath }] : []
      const base = { to: info.customerEmail, customer_id: info.customerId || null, booking_id: info.bookingId || null, attachment_paths }
      // 1) Primárně přes šablonu z Velína
      let res = await supabase.functions.invoke('send-email', { body: { ...base, template_slug: slug, template_vars } })
      const failed = res?.error || (res?.data && res.data.success === false)
      if (failed) {
        // 2) Fallback (šablona ještě není v DB) — pošli protokol jako obsah e-mailu
        const res2 = await supabase.functions.invoke('send-email', { body: { ...base, template_slug: slug, subject: `${info.docName || 'Předávací protokol'} — MOTO GO 24`, raw_html: info.html } })
        if (res2?.error || (res2?.data && res2.data.success === false)) throw new Error(res2?.error?.message || res2?.data?.error || 'Odeslání selhalo')
      }
      setSendResult(`✓ Protokol odeslán zákazníkovi na ${info.customerEmail}.`)
    } catch (e) { setSendResult(`Odeslání selhalo: ${e.message || e}`) }
    setSendingProtocol(false)
  }

  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  return (
    <div className="space-y-5">
      {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {debug && <div className="p-3 rounded-card mb-3" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 13, fontFamily: 'monospace', color: '#78350f' }}><strong>DIAG ...{bookingId?.slice(-8)}</strong>{debug.errors.length > 0 && <span style={{ color: '#dc2626' }}> ERR: {debug.errors.join('|')}</span>} docs:{debug.docsFiltered||0} gen:{debug.gen?.length||0} inv:{debug.inv?.length||0}</div>}
      {userId && <BookingCustomerDocsStatus userId={userId} bookingId={bookingId} />}
      <div className="flex gap-3 flex-wrap">
        <Button green onClick={() => handleGenerate('rental_contract')} disabled={generating === 'rental_contract'}>{generating === 'rental_contract' ? 'Generuji...' : '+ Vygenerovat smlouvu'}</Button>
        <Button green onClick={() => setProtocolChoice('handover_protocol')} disabled={generating === 'handover_protocol'}>{generating === 'handover_protocol' ? 'Generuji...' : '+ Vygenerovat předávací protokol'}</Button>
        <Button green onClick={() => setProtocolChoice('damage_protocol')} disabled={generating === 'damage_protocol'}>{generating === 'damage_protocol' ? 'Generuji...' : '+ Vygenerovat protokol o poškození'}</Button>
        <Button green onClick={() => handleGenerate('vop')} disabled={generating === 'vop'}>{generating === 'vop' ? 'Generuji...' : '+ Vygenerovat VOP'}</Button>
        <Button green onClick={() => handleGenerate('gdpr')} disabled={generating === 'gdpr'}>{generating === 'gdpr' ? 'Generuji...' : '+ Vygenerovat GDPR'}</Button>
        {dbTemplates.vop && <Button onClick={() => { setViewHtml(dbTemplates.vop); setViewDoc({ file_name: 'Obchodni podminky (VOP)' }) }}>Zobrazit VOP</Button>}
      </div>
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Faktury a danove doklady</h3>
        {invoices.length === 0 ? (
          <div><p style={{ color: '#1a2e22', fontSize: 13, marginBottom: 8 }}>Zadne faktury k teto rezervaci</p>
            <Button green onClick={async () => {
              setGenerating('invoices'); setError(null)
              try {
                // Check if booking has actual paid amount > 0 before generating ZF + DP
                const { data: bk } = await supabase.from('bookings').select('total_price, payment_status').eq('id', bookingId).single()
                if (!bk || Number(bk.total_price || 0) <= 0) {
                  setError('ZF + DP nelze vygenerovat — rezervace má nulovou částku. Pouze smlouva a VOP jsou relevantní.')
                  setGenerating(null)
                  return
                }
                await generateAdvanceInvoice(bookingId, 'booking')
                await generatePaymentReceipt(bookingId, 'booking')
                await loadAll()
              } catch (e) { setError(`Generovani faktur selhalo: ${e.message}`) }
              setGenerating(null)
            }} disabled={generating === 'invoices'}>{generating === 'invoices' ? 'Generuji...' : 'Vygenerovat ZF + DP'}</Button></div>
        ) : invoices.map(inv => { const tp = INV_TYPE_MAP[inv.type] || { label: inv.type || 'Faktura', color: '#1a2e22', bg: '#f3f4f6' }; const isCN = inv.type === 'credit_note'; return (
          <div key={inv.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer hover:shadow-sm transition-shadow" style={{ background: isCN ? '#fef2f2' : '#f1faf7', border: isCN ? '1px solid #fca5a5' : 'none' }} onClick={() => handleViewInvoice(inv)}>
            <span style={{ fontSize: 16 }}>{isCN ? '\u274c' : '\ud83e\uddfe'}</span><span className="text-sm font-bold font-mono" style={isCN ? { color: '#dc2626' } : {}}>{inv.number || '\u2014'}</span><Badge label={tp.label} color={tp.color} bg={tp.bg} /><span className="text-sm font-bold" style={{ color: isCN ? '#dc2626' : '#0f1a14' }}>{isCN ? '\u2212' : ''}{Math.abs(inv.total || 0).toLocaleString('cs-CZ')} Kc</span><span className="text-sm" style={{ color: '#1a2e22' }}>{inv.issue_date || '\u2014'}</span>
            <div className="flex gap-2 ml-auto" onClick={e => e.stopPropagation()}><button onClick={() => handleViewInvoice(inv)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>Nahled</button><button onClick={() => handlePrintInvoice(inv)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Tisk</button><button onClick={() => handleDownload(inv)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stahnout</button>{!isCN && <button onClick={() => handleRegenerateInvoice(inv)} disabled={generating === `regen-${inv.id}`} className="text-sm font-bold cursor-pointer" style={{ color: '#7c3aed', background: 'none', border: 'none' }}>{generating === `regen-${inv.id}` ? 'Generuji…' : 'Přegenerovat'}</button>}<button onClick={() => handleDeleteInvoice(inv)} className="text-sm font-bold cursor-pointer" style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button></div>
          </div>
        ) })}
      </Card>
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Vygenerovane dokumenty</h3>
        {generatedDocs.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Zadne vygenerovane dokumenty</p> : generatedDocs.map(d => { const docType = d.document_templates?.type || d.filled_data?._doc_type || 'contract'; return (
          <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer hover:shadow-sm transition-shadow" style={{ background: '#f1faf7' }} onClick={() => handleViewGeneratedDoc(d)}>
            <span style={{ fontSize: 16 }}>{DOC_ICONS[docType] || '\ud83d\udcc4'}</span><div className="flex-1"><span className="text-sm font-bold">{d.document_templates?.name || d.filled_data?._doc_name || 'Dokument'}</span>{d.filled_data?._electronic && <span className="text-xs ml-2 px-2 py-0.5 rounded-full" style={{ background: '#dcfce7', color: '#166534', fontWeight: 700 }}>el. podeps\u00e1no</span>}<span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{d.created_at?.slice(0, 10)}</span></div>
            <div className="flex gap-2" onClick={e => e.stopPropagation()}><button onClick={() => handleViewGeneratedDoc(d)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button><button onClick={() => handleDownload(d)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stahnout</button></div>
          </div>
        ) })}
      </Card>
      <Card>
        <h3 className="text-sm font-extrabold uppercase tracking-wide mb-3" style={{ color: '#1a2e22' }}>Nahrane doklady</h3>
        {docs.length === 0 ? <p style={{ color: '#1a2e22', fontSize: 13 }}>Zadne nahrane doklady</p> : docs.map(d => (
          <div key={d.id} className="flex items-center gap-4 p-3 rounded-lg mb-2 cursor-pointer hover:shadow-sm transition-shadow" style={{ background: '#f1faf7' }} onClick={() => (d.file_path || d.pdf_path) ? handleViewDoc(d) : null}>
            <span style={{ fontSize: 16 }}>{DOC_ICONS[d.type] || '\ud83d\udcc4'}</span><div className="flex-1"><span className="text-sm font-bold">{d.file_name || d.type || 'Dokument'}</span><span className="text-sm ml-3" style={{ color: '#1a2e22' }}>{d.created_at?.slice(0, 10)}</span></div>
            <div className="flex gap-2" onClick={e => e.stopPropagation()}>{(d.file_path || d.pdf_path) && (<><button onClick={() => handleViewDoc(d)} className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb', background: 'none', border: 'none' }}>Zobrazit</button><button onClick={() => handleDownload(d)} className="text-sm font-bold cursor-pointer" style={{ color: '#1a2e22', background: 'none', border: 'none' }}>Stahnout</button></>)}</div>
          </div>
        ))}
      </Card>
      {viewDoc && (
        <Modal open title={viewDoc.number ? `Faktura ${viewDoc.number}` : (viewDoc.document_templates?.name || viewDoc.file_name || 'Dokument')} onClose={() => { setViewDoc(null); setViewHtml(null) }} wide>
          {viewHtml ? <div className="border rounded-lg overflow-auto" style={{ maxHeight: 600, background: '#fff' }}><iframe srcDoc={viewHtml} style={{ width: '100%', height: 550, border: 'none' }} title="Nahled dokumentu" /></div> : <div className="py-8 text-center" style={{ color: '#1a2e22', fontSize: 13 }}>Dokument nema nahled.</div>}
          <div className="flex justify-end gap-3 mt-4">
            {viewHtml && <Button onClick={() => openPrintWindow(viewHtml)}>Tisk / PDF</Button>}
            {(viewDoc.pdf_path || viewDoc.file_path) && <Button onClick={() => handleDownload(viewDoc)}>Stahnout</Button>}
            <Button onClick={() => { setViewDoc(null); setViewHtml(null) }}>Zavrit</Button>
          </div>
        </Modal>
      )}
      {protocolChoice && (
        <Modal open title={protocolChoice === 'damage_protocol' ? 'Protokol o poškození' : 'Předávací protokol'} onClose={() => setProtocolChoice(null)}>
          <p style={{ fontSize: 13, color: '#1a2e22', marginBottom: 16 }}>Zvolte formu protokolu:</p>
          <div className="flex flex-col gap-3">
            <Button onClick={() => { const t = protocolChoice; setProtocolChoice(null); handleGenerate(t) }}>🖨️ Tištěný (stávající verze)</Button>
            <Button green onClick={() => { const t = protocolChoice; setProtocolChoice(null); setElectronicProtocol(t) }}>✍️ Elektronický — vyplnit a podepsat na tabletu</Button>
          </div>
        </Modal>
      )}
      {electronicProtocol && (
        <ElectronicProtocolModal
          open
          type={electronicProtocol}
          bookingId={bookingId}
          onClose={() => setElectronicProtocol(null)}
          onSaved={(info) => {
            setElectronicProtocol(null)
            loadAll()
            setSendResult(null)
            setSendOffer(info || null)
          }}
        />
      )}
      {sendOffer && (
        <Modal open title="Protokol uložen" onClose={() => setSendOffer(null)}>
          <p style={{ fontSize: 14, color: '#1a2e22', marginBottom: 12 }}>
            <strong>{sendOffer.docName || 'Protokol'}</strong> byl uložen a elektronicky podepsán.
          </p>
          {sendOffer.customerEmail ? (
            <p style={{ fontSize: 13, color: '#1a2e22', marginBottom: 16 }}>Odeslat protokol zákazníkovi e-mailem na <strong>{sendOffer.customerEmail}</strong>?</p>
          ) : (
            <p style={{ fontSize: 13, color: '#b45309', marginBottom: 16 }}>Zákazník nemá uložený e-mail — protokol nelze odeslat.</p>
          )}
          {sendResult && <div className="p-3 rounded-card mb-3" style={{ background: sendResult.startsWith('✓') ? '#dcfce7' : '#fee2e2', color: sendResult.startsWith('✓') ? '#166534' : '#dc2626', fontSize: 13 }}>{sendResult}</div>}
          <div className="flex justify-end gap-3">
            <Button onClick={() => { if (sendOffer.html) { setViewHtml(sendOffer.html); setViewDoc({ document_templates: { name: sendOffer.docName || 'Protokol' } }) } setSendOffer(null) }}>Náhled</Button>
            <Button onClick={() => setSendOffer(null)}>Zavřít</Button>
            {sendOffer.customerEmail && !sendResult?.startsWith('✓') && <Button green disabled={sendingProtocol} onClick={() => sendProtocolEmail(sendOffer)}>{sendingProtocol ? 'Odesílám…' : 'Odeslat zákazníkovi'}</Button>}
          </div>
        </Modal>
      )}
    </div>
  )
}
