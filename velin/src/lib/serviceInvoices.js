import { supabase } from './supabase'
import { audit, todayIso } from './serviceBook'

// Faktury / daňové doklady k servisnímu záznamu (zadání majitele: externí servis u konkrétního servisu
// klikne „+ Přidat fakturu“, nahraje PDF nebo fotku a doklad se objeví ve Financích → Přijaté faktury).
// Tok: 1) soubor → bucket invoices-received (servis/<log_id>/<uuid>.<ext>)
//      2) volitelně OCR přes edge fn receive-invoice (mode=extract) — jen u fotek/obrázků (vyčte dodavatele, číslo, částku)
//      3) řádek invoices (type=received, source=service, pdf_path) + financial_events (expense, manual)
//      4) vazba maintenance_invoices → maintenance_log.invoiced_amount (trigger)
export const INVOICE_BUCKET = 'invoices-received'
const MAX_MB = 20

export function fileToBase64(file) {
  return new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = rej; r.readAsDataURL(file) })
}

/** OCR (jen obrázky) — vrací { supplier, supplier_ico, invoice_number, amount, date, due_date } nebo null. */
export async function extractInvoiceData(file) {
  if (!/^image\//.test(file.type || '')) return null
  try {
    const b64 = await fileToBase64(file)
    const { data, error } = await supabase.functions.invoke('receive-invoice', { body: { mode: 'extract', image_base64: b64, file_name: file.name || 'doklad.jpg', source: 'velin-service' } })
    if (error || !data?.success) return null
    const ex = data.extracted || {}
    return { supplier: ex.supplier || '', supplier_ico: ex.supplier_ico || '', invoice_number: ex.invoice_number || '', amount: ex.amount || data.amount_czk || '', date: ex.date || '', due_date: ex.due_date || '' }
  } catch { return null }
}

export async function uploadInvoiceFile(logId, file) {
  if (file.size > MAX_MB * 1024 * 1024) throw new Error(`Soubor je větší než ${MAX_MB} MB`)
  const ext = (file.name?.split('.').pop() || (file.type === 'application/pdf' ? 'pdf' : 'jpg')).toLowerCase().replace(/[^a-z0-9]/g, '') || 'bin'
  const path = `servis/${logId}/${crypto.randomUUID()}.${ext}`
  const { error } = await supabase.storage.from(INVOICE_BUCKET).upload(path, file, { contentType: file.type || undefined, upsert: false, cacheControl: '3600' })
  if (error) throw new Error('Nahrání souboru selhalo: ' + error.message)
  return path
}

/**
 * Zaeviduje doklad k servisu. meta = { invoice_number, supplier_name, supplier_ico, amount, issue_date, due_date, note }.
 * Vrací řádek maintenance_invoices.
 */
export async function registerServiceInvoice({ log, moto, file, storagePath, meta, uploadedBy }) {
  const amount = Number(meta.amount) || 0
  const issue = meta.issue_date || todayIso()
  const supplier = (meta.supplier_name || '').trim()
  const number = (meta.invoice_number || '').trim() || `SERVIS-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${String(log.id).slice(0, 6).toUpperCase()}-${crypto.randomUUID().slice(0, 4).toUpperCase()}`
  const motoLabel = moto ? `${moto.model}${moto.spz ? ` (${moto.spz})` : ''}` : ''
  let invoiceId = null, feId = null
  // při selhání dalšího kroku nenechat osiřelý soubor / fakturu / událost
  const cleanup = async () => {
    try { if (feId) await supabase.from('financial_events').delete().eq('id', feId) } catch { /* best effort */ }
    try { if (invoiceId) await supabase.from('invoices').delete().eq('id', invoiceId) } catch { /* best effort */ }
    try { await supabase.storage.from(INVOICE_BUCKET).remove([storagePath]) } catch { /* best effort */ }
  }
  // 1) přijatá faktura (Finance → Přijaté faktury); trigger post_invoice_to_financial_event přijaté přeskakuje → událost níže
  const notes = [supplier || null, meta.supplier_ico ? `IČO: ${meta.supplier_ico}` : null, 'Kategorie: servis_opravy', `Servis: ${motoLabel}`.trim(), meta.note || null].filter(Boolean).join('\n')
  const { data: inv, error: invErr } = await supabase.from('invoices').insert({
    number, type: 'received', total: amount, subtotal: amount, tax_amount: 0,
    issue_date: issue, due_date: meta.due_date || issue, status: 'issued', source: 'service',
    pdf_path: storagePath, notes,
  }).select('id').single()
  if (invErr) { await cleanup(); throw new Error(invErr.code === '23505' ? 'Doklad s tímto číslem už je zaevidován — zadejte jiné číslo dokladu.' : 'Faktura se nepodařila zaevidovat: ' + invErr.message) }
  invoiceId = inv.id
  // 2) účetní událost (náklad) — stejný tvar jako ruční přijatá faktura (AddReceivedModal)
  const { data: fe } = await supabase.from('financial_events').insert({
    event_type: 'expense', source: 'manual', amount_czk: amount, duzp: issue, status: 'enriched', vat_rate: 0,
    linked_entity_type: 'invoice', linked_entity_id: invoiceId, document_type: 'invoice',
    metadata: {
      supplier_name: supplier || null, supplier_ico: meta.supplier_ico || null, invoice_number: number, due_date: meta.due_date || null,
      storage_path: storagePath, source_app: 'velin-service', maintenance_log_id: log.id, moto_id: log.moto_id, moto: motoLabel || null,
      ai_classification: { category: 'servis_opravy', classification_note: `Servis motorky ${motoLabel}` },
    },
  }).select('id').single()
  feId = fe?.id || null
  // 3) vazba na servis
  const { data: row, error: miErr } = await supabase.from('maintenance_invoices').insert({
    maintenance_log_id: log.id, moto_id: log.moto_id, invoice_id: invoiceId, financial_event_id: feId,
    storage_bucket: INVOICE_BUCKET, storage_path: storagePath, file_name: file?.name || null, mime_type: file?.type || null, file_size: file?.size || null,
    invoice_number: number, supplier_name: supplier || null, supplier_ico: meta.supplier_ico || null, amount,
    issue_date: issue, due_date: meta.due_date || null, ocr_status: meta.ocr ? 'done' : 'none', note: meta.note || null,
    uploaded_by: uploadedBy?.id || null, uploaded_by_name: uploadedBy?.name || null,
  }).select('*').single()
  if (miErr) { await cleanup(); throw new Error('Vazba faktury na servis selhala: ' + miErr.message) }
  await audit('service_invoice_uploaded', { log_id: log.id, moto_id: log.moto_id, invoice_id: invoiceId, amount, number })
  return row
}

export async function fetchServiceInvoices(logIds) {
  if (!logIds?.length) return []
  const { data } = await supabase.from('maintenance_invoices').select('*').in('maintenance_log_id', logIds).order('created_at', { ascending: false })
  return data || []
}

export async function signedInvoiceUrl(row) {
  const { data } = await supabase.storage.from(row.storage_bucket || INVOICE_BUCKET).createSignedUrl(row.storage_path, 600)
  return data?.signedUrl || null
}

export async function deleteServiceInvoice(row) {
  await supabase.storage.from(row.storage_bucket || INVOICE_BUCKET).remove([row.storage_path])
  if (row.financial_event_id) await supabase.from('financial_events').delete().eq('id', row.financial_event_id)
  if (row.invoice_id) await supabase.from('invoices').delete().eq('id', row.invoice_id)
  const { error } = await supabase.from('maintenance_invoices').delete().eq('id', row.id)
  if (error) throw error
  await audit('service_invoice_deleted', { log_id: row.maintenance_log_id, invoice_id: row.invoice_id })
}
