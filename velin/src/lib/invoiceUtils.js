import { supabase } from './supabase'

/**
 * Generate next invoice number
 * Format: FV-2026-0001 (final), ZF-2026-0001 (proforma)
 */
export async function generateInvoiceNumber(type) {
  const prefix = (type === 'proforma' || type === 'shop_proforma') ? 'ZF' : 'FV'
  const year = new Date().getFullYear()
  const pattern = `${prefix}-${year}-%`

  const { data } = await supabase
    .from('invoices')
    .select('number')
    .like('number', pattern)
    .order('number', { ascending: false })
    .limit(1)

  let seq = 1
  if (data && data.length > 0) {
    const last = data[0].number
    const match = last.match(/-(\d+)$/)
    if (match) seq = parseInt(match[1], 10) + 1
  }

  return `${prefix}-${year}-${String(seq).padStart(4, '0')}`
}

/**
 * Calculate invoice totals from items
 * Neplátce DPH — DPH = 0, cena je konečná
 */
export function calculateTotals(items) {
  const subtotal = items.reduce((sum, it) => sum + (it.unit_price || 0) * (it.qty || 1), 0)
  const taxAmount = 0
  const total = subtotal
  return { subtotal, taxAmount, total }
}

/**
 * Create invoice record in DB
 */
export async function createInvoice({ type, customer_id, booking_id, items, notes, due_date }) {
  const number = await generateInvoiceNumber(type)
  const { subtotal, taxAmount, total } = calculateTotals(items)
  const issueDate = new Date().toISOString().slice(0, 10)

  const { data, error } = await supabase
    .from('invoices')
    .insert({
      number,
      type,
      customer_id: customer_id || null,
      booking_id: booking_id || null,
      items,
      subtotal,
      tax_amount: taxAmount,
      total,
      notes: notes || null,
      issue_date: issueDate,
      due_date: due_date || null,
      status: 'issued',
    })
    .select()
    .single()

  if (error) throw error

  const { data: { user } } = await supabase.auth.getUser()
  await supabase.from('admin_audit_log').insert({
    admin_id: user?.id,
    action: 'invoice_created',
    details: { invoice_id: data.id, number, type },
  })

  return data
}

/**
 * Open invoice HTML in new window for printing / PDF save
 */
export function printInvoiceHtml(html) {
  const win = window.open('', '_blank')
  if (!win) return
  win.document.write(html)
  win.document.close()
  win.onload = () => {
    win.print()
  }
}

/**
 * Store invoice HTML as blob in Supabase Storage
 */
export async function storeInvoicePdf(invoiceId, html) {
  const blob = new Blob([html], { type: 'text/html' })
  const path = `invoices/${invoiceId}.html`

  const { error: upErr } = await supabase.storage
    .from('documents')
    .upload(path, blob, { upsert: true, contentType: 'text/html' })

  if (upErr) throw upErr

  await supabase
    .from('invoices')
    .update({ pdf_path: path })
    .eq('id', invoiceId)

  return path
}

/**
 * Load full invoice data with relations
 */
export async function loadInvoiceData(invoiceId) {
  const { data, error } = await supabase
    .from('invoices')
    .select('*, profiles:customer_id(full_name, email, phone, street, city, zip, country, ico, dic), bookings:booking_id(id, start_date, end_date, total_price, motorcycles(model, spz))')
    .eq('id', invoiceId)
    .single()

  if (error) throw error
  return data
}
