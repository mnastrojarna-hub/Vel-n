import { supabase } from './supabase'

const PREFIX_MAP = {
  advance: 'ZF',
  proforma: 'ZF',
  shop_proforma: 'ZF',
  payment_receipt: 'DP',
  final: 'KF',
  shop_final: 'FV',
}

const DAY_NAMES_CS = ['ne', 'po', 'út', 'st', 'čt', 'pá', 'so']
const MOTO_SELECT = 'model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend'

function getDayPrice(moto, dayOfWeek) {
  const map = { 0: moto.price_sun, 1: moto.price_mon, 2: moto.price_tue, 3: moto.price_wed, 4: moto.price_thu, 5: moto.price_fri, 6: moto.price_sat }
  return Number(map[dayOfWeek] || moto.price_weekday || moto.price_weekend || 0)
}

function toDateStr(d) {
  if (!d) return ''
  return String(d).split('T')[0]
}

function fmtDateCS(d) {
  if (!d) return '—'
  const dt = new Date(toDateStr(d) + 'T00:00:00')
  return `${dt.getDate()}.${dt.getMonth() + 1}.${dt.getFullYear()}`
}

/**
 * Build daily line items from motorcycle per-day prices
 * Each day = one line with day name, date, and that day's price
 */
function buildDailyLineItems(moto, startDate, endDate) {
  const items = []
  const start = new Date(toDateStr(startDate) + 'T00:00:00')
  const end = new Date(toDateStr(endDate) + 'T00:00:00')
  const current = new Date(start)
  const modelName = moto.model || 'motorky'

  while (current <= end) {
    const dow = current.getDay()
    const price = getDayPrice(moto, dow)
    const dayName = DAY_NAMES_CS[dow]
    const dateStr = `${current.getDate()}.${current.getMonth() + 1}.`
    items.push({
      description: `Pronájem ${modelName} – ${dayName} ${dateStr}`,
      qty: 1,
      unit_price: price,
    })
    current.setDate(current.getDate() + 1)
  }
  return items
}

/**
 * Build booking line items: daily breakdown + extras/delivery/discount
 */
function buildBookingItems(moto, booking) {
  const items = buildDailyLineItems(moto, booking.start_date, booking.end_date)
  if (booking.extras_price > 0) items.push({ description: 'Příslušenství / doplňky', qty: 1, unit_price: booking.extras_price })
  if (booking.delivery_fee > 0) items.push({ description: 'Doručení', qty: 1, unit_price: booking.delivery_fee })
  if (booking.discount_amount > 0) items.push({ description: `Sleva${booking.discount_code ? ` (${booking.discount_code})` : ''}`, qty: 1, unit_price: -booking.discount_amount })
  return items
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
 * Generate advance invoice (ZF) for a booking — daily price breakdown
 */
export async function generateAdvanceInvoice(bookingId, source = 'booking') {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles(${MOTO_SELECT}), profiles:user_id(id, full_name, email)`)
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const items = buildBookingItems(moto, booking)

  return createInvoice({
    type: 'advance',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    notes: `Období pronájmu: ${fmtDateCS(booking.start_date)} – ${fmtDateCS(booking.end_date)}`,
    source,
    status: 'paid',
  })
}

/**
 * Generate payment receipt (DP) for a booking — daily price breakdown
 */
export async function generatePaymentReceipt(bookingId, source = 'booking') {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles(${MOTO_SELECT}), profiles:user_id(id, full_name, email)`)
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const items = buildBookingItems(moto, booking)

  return createInvoice({
    type: 'payment_receipt',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    notes: `Období pronájmu: ${fmtDateCS(booking.start_date)} – ${fmtDateCS(booking.end_date)}`,
    source,
    status: 'paid',
  })
}

/**
 * Generate final invoice (KF) for a booking — daily price breakdown + deduct advances
 */
export async function generateFinalInvoice(bookingId) {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles(${MOTO_SELECT}), profiles:user_id(id, full_name, email)`)
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const items = buildBookingItems(moto, booking)

  // Deduct all previously paid invoices (DP = payment receipt, ZF = advance/proforma)
  // Priority: deduct DP (actual payments). If no DP exists, fall back to ZF (advance requests).
  // This prevents double-counting when both ZF and DP exist for the same payment.
  const { data: receipts } = await supabase
    .from('invoices').select('number, total, type, source')
    .eq('booking_id', bookingId).in('type', ['payment_receipt'])
    .neq('status', 'cancelled')
    .order('issue_date', { ascending: true })

  const { data: advances } = await supabase
    .from('invoices').select('number, total, type, source')
    .eq('booking_id', bookingId).in('type', ['advance', 'proforma'])
    .neq('status', 'cancelled')
    .order('issue_date', { ascending: true })

  // Use DP if available (documents actual payment), otherwise use ZF (advance invoice)
  const deductions = (receipts?.length ? receipts : advances) || []
  if (deductions.length) {
    deductions.forEach(a => {
      const label = a.type === 'payment_receipt' ? 'Odpočet dle dokladu k platbě' : 'Odpočet zálohy'
      items.push({ description: `${label} ${a.number}`, qty: 1, unit_price: -Number(a.total || 0) })
    })
  }

  return createInvoice({
    type: 'final',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    notes: `Období pronájmu: ${fmtDateCS(booking.start_date)} – ${fmtDateCS(booking.end_date)}`,
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
