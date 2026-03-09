import { supabase } from './supabase'

const PREFIX_MAP = {
  advance: 'ZF',
  proforma: 'ZF',
  shop_proforma: 'ZF',
  payment_receipt: 'DP',
  final: 'KF',
  shop_final: 'FV',
}

/**
 * Generate next invoice number
 * Format: ZF-2026-0001 (advance), DP-2026-0001 (receipt), KF-2026-0001 (final)
 */
export async function generateInvoiceNumber(type) {
  const prefix = PREFIX_MAP[type] || 'FV'
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
    const match = data[0].number.match(/-(\d+)$/)
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
 * Create invoice record in DB (direct insert, no edge function dependency)
 */
export async function createInvoice({ type, customer_id, booking_id, order_id, items, notes, due_date, source, status }) {
  const number = await generateInvoiceNumber(type)
  const { subtotal, taxAmount, total } = calculateTotals(items)
  const issueDate = new Date().toISOString().slice(0, 10)

  const payload = {
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
    due_date: due_date || issueDate,
    status: status || 'issued',
    source: source || 'booking',
  }
  // Add optional columns only if they have values (columns may not exist in all environments)
  if (order_id) payload.order_id = order_id
  if (number) payload.variable_symbol = number

  let data = null
  let insertError = null

  // Try insert
  const result = await supabase
    .from('invoices')
    .insert(payload)
    .select()
    .single()

  if (result.error) {
    console.error('[createInvoice] Insert failed:', result.error.message, result.error.details, result.error.hint)
    // If insert fails (e.g. unknown column), retry without optional columns
    const minPayload = {
      number, type,
      customer_id: customer_id || null,
      booking_id: booking_id || null,
      items, subtotal, tax_amount: taxAmount, total,
      notes: notes || null,
      issue_date: issueDate,
      due_date: due_date || issueDate,
      status: status || 'issued',
    }
    const retry = await supabase.from('invoices').insert(minPayload).select().single()
    if (retry.error) {
      console.error('[createInvoice] Retry also failed:', retry.error.message)
      throw retry.error
    }
    data = retry.data
  } else {
    data = result.data
  }

  // Document sync is handled by DB trigger (sync_invoice_to_documents)
  // Do NOT manually insert into documents — the trigger does it automatically

  // Audit log (non-blocking)
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id,
      action: 'invoice_created',
      details: { invoice_id: data.id, number, type, source },
    })
  } catch {} // non-blocking

  return data
}

/**
 * Generate advance invoice (ZF) for a booking — mirrors mobile app logic
 */
export async function generateAdvanceInvoice(bookingId, source = 'booking') {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select('*, motorcycles(model, spz), profiles:user_id(id, full_name, email)')
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const desc = source === 'edit' ? 'úprava rezervace' : source === 'sos' ? 'SOS' : source === 'restore' ? 'obnova' : 'rezervace'
  const items = [{ description: `Záloha – ${desc} ${moto.model || ''}`.trim(), qty: 1, unit_price: booking.total_price || 0 }]

  return createInvoice({
    type: 'advance',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    source,
    status: 'paid',
  })
}

/**
 * Generate payment receipt (DP) for a booking — mirrors mobile app logic
 */
export async function generatePaymentReceipt(bookingId, source = 'booking') {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select('*, motorcycles(model, spz), profiles:user_id(id, full_name, email)')
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const desc = source === 'edit' ? 'úprava rezervace' : source === 'sos' ? 'SOS' : source === 'restore' ? 'obnova' : 'rezervace'
  const items = [{ description: `Přijatá platba – ${desc} ${moto.model || ''}`.trim(), qty: 1, unit_price: booking.total_price || 0 }]

  return createInvoice({
    type: 'payment_receipt',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    source,
    status: 'paid',
  })
}

/**
 * Generate final invoice (KF) for a booking — mirrors mobile app logic
 */
export async function generateFinalInvoice(bookingId) {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select('*, motorcycles(model, spz), profiles:user_id(id, full_name, email)')
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const days = Math.max(1, Math.ceil((new Date(booking.end_date) - new Date(booking.start_date)) / 86400000))
  const dailyRate = Math.round((booking.total_price || 0) / days)

  const items = [{ description: `Pronájem ${moto.model || 'motorky'} (${moto.spz || ''})`, qty: days, unit_price: dailyRate }]
  if (booking.extras_price > 0) items.push({ description: 'Příslušenství / doplňky', qty: 1, unit_price: booking.extras_price })
  if (booking.delivery_fee > 0) items.push({ description: 'Doručení', qty: 1, unit_price: booking.delivery_fee })
  if (booking.discount_amount > 0) items.push({ description: `Sleva${booking.discount_code ? ` (${booking.discount_code})` : ''}`, qty: 1, unit_price: -booking.discount_amount })

  // Deduct all advance invoices
  const { data: advances } = await supabase
    .from('invoices').select('number, total, source')
    .eq('booking_id', bookingId).in('type', ['advance', 'proforma'])
    .order('issue_date', { ascending: true })
  if (advances?.length) {
    advances.forEach(a => {
      items.push({ description: `Záloha ${a.number} (${a.source || ''})`, qty: 1, unit_price: -Number(a.total || 0) })
    })
  }

  return createInvoice({
    type: 'final',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    source: 'final_summary',
    status: 'paid',
  })
}

/**
 * Open invoice HTML in new window for printing / PDF save
 */
export function printInvoiceHtml(html) {
  const win = window.open('', '_blank')
  if (!win) return
  win.document.write(html)
  win.document.close()
  win.onload = () => { win.print() }
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
