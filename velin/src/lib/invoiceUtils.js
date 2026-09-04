import { supabase } from './supabase'
import { uploadHtmlAsPdf } from './htmlToPdf'
import { generateInvoiceHtml } from './invoiceTemplate'
import { openPrintWindow } from './sanitize'

const PREFIX_MAP = {
  issued: 'FV',
  advance: 'ZF',
  proforma: 'ZF',
  shop_proforma: 'ZF',
  payment_receipt: 'DP',
  final: 'KF',
  shop_final: 'FV',
  credit_note: 'DB',
}

const DAY_NAMES_CS = ['ne', 'po', 'út', 'st', 'čt', 'pá', 'so']
const MOTO_SELECT = 'model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend'

function getDayPrice(moto, dayOfWeek) {
  const map = { 0: moto.price_sun, 1: moto.price_mon, 2: moto.price_tue, 3: moto.price_wed, 4: moto.price_thu, 5: moto.price_fri, 6: moto.price_sat }
  return Number(map[dayOfWeek] || moto.price_weekday || moto.price_weekend || 0)
}

function toDateStr(d) {
  if (!d) return ''
  // Use local timezone to avoid UTC date shift (e.g. 2026-03-14T23:00Z → should be 2026-03-15 in CET)
  const dt = new Date(d)
  return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`
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
 * Build booking line items: daily breakdown + extras/delivery + VŠECHNY slevy.
 *
 * DŮLEŽITÉ: musí odečíst KAŽDÝ druh slevy zvlášť — promo/voucher (discount_amount),
 * věrnost (loyalty_discount_amount) i pozdní vyzvednutí (late_pickup_discount_amount) —
 * aby Celkem DP/KF == booking.total_price (netto). Když se odečte jen část slev, DP
 * vyjde vyšší než total_price a KF trigger na rozdíl vystaví fantomový dobropis
 * (bug: věrnostní a late sleva na DP chyběly → přeplatek 806 Kč). Zrcadlí edge
 * `generate-invoice` (samostatné řádky slev) i KF trigger generate_final_invoice_on_complete.
 */
function buildBookingItems(moto, booking) {
  const items = buildDailyLineItems(moto, booking.start_date, booking.end_date)
  if (booking.extras_price > 0) items.push({ description: 'Příslušenství / doplňky', qty: 1, unit_price: booking.extras_price })
  if (booking.delivery_fee > 0) items.push({ description: 'Doručení', qty: 1, unit_price: booking.delivery_fee })
  if (booking.discount_amount > 0) items.push({ description: `Sleva${booking.discount_code ? ` (${booking.discount_code})` : ''}`, qty: 1, unit_price: -booking.discount_amount })
  if (booking.loyalty_discount_amount > 0) items.push({ description: `Věrnostní sleva${booking.loyalty_percent ? ` ${booking.loyalty_percent} %` : ''} — rezervace přes aplikaci MotoGo24`, qty: 1, unit_price: -booking.loyalty_discount_amount })
  if (booking.late_pickup_discount_amount > 0) items.push({ description: 'Sleva 50 % na 1. den (pozdní vyzvednutí)', qty: 1, unit_price: -booking.late_pickup_discount_amount })
  // Korekce SMĚREM DOLŮ: když rozpis převyšuje bookings.total_price (zastaralá
  // late sleva po bezplatném posunu, historické úpravy…), dorovnej záporným
  // řádkem — jinak ZF/DP vyjde vyšší než skutečná cena a KF nevyjde na 0.
  // Zrcadlí „Korekce ceny pronájmu" v edge generate-invoice. Opačný směr
  // (total > rozpis) řeší KF řádek „Storno poplatek" v generateFinalInvoice.
  const itemsSum = items.reduce((s, i) => s + (Number(i.unit_price) || 0) * (Number(i.qty) || 1), 0)
  const bookingNet = Number(booking.total_price) || 0
  if (bookingNet > 0 && itemsSum - bookingNet >= 1) {
    items.push({ description: 'Korekce ceny pronájmu', qty: 1, unit_price: -Math.round(itemsSum - bookingNet) })
  }
  return items
}

// Hranice číselných řad: automatické doklady (rezervace, e-shop, refundy) běží
// v intervalu 0001–4999, RUČNÍ doklady (Velín → Nová faktura) mají vlastní řadu
// 5001+ (PREFIX-ROK-5001, 5002…). Obě řady se nesmí míchat — automatické
// generátory (tady, DB fce next_document_number, edge generate-invoice /
// process-refund) proto čísla >= 5000 ignorují.
const MANUAL_SEQ_START = 5000

/**
 * Generate next invoice number
 * Format: ZF-2026-0001 (advance), DP-2026-0001 (receipt), KF-2026-0001 (final)
 * manual=true → ruční řada: ZF-2026-5001, KF-2026-5001…
 */
export async function generateInvoiceNumber(type, manual = false) {
  const prefix = PREFIX_MAP[type] || 'FV'
  const year = new Date().getFullYear()
  const pattern = `${prefix}-${year}-%`
  const boundary = `${prefix}-${year}-${MANUAL_SEQ_START}`

  let query = supabase
    .from('invoices')
    .select('number')
    .like('number', pattern)
  query = manual ? query.gte('number', boundary) : query.lt('number', boundary)
  const { data } = await query
    .order('number', { ascending: false })
    .limit(1)

  let seq = manual ? MANUAL_SEQ_START + 1 : 1
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
 *
 * Retries on `invoices_number_key` unique-violation (race condition between
 * concurrent number generators — typically caused by React StrictMode double-mount,
 * concurrent autoGenerateKF + DB trigger, or two open tabs).
 */
export async function createInvoice({ type, customer_id, booking_id, order_id, items, notes, due_date, issue_date, source, status, payment, manual }) {
  const { subtotal, taxAmount, total } = calculateTotals(items)
  // Datum vystavení: ručně zadané (Velín → Nová faktura) má přednost VŽDY a ukládá
  // se beze změny — i zpětné datum (rozhodnutí provozovatele; řada pak může mít
  // vyšší číslo se starším datem). Jinak datum přijetí ruční platby
  // (převod / QR / hotově / krypto), jinak dnešek (jako dosud).
  const issueDate = issue_date || (payment && payment.paid_date) || new Date().toISOString().slice(0, 10)

  const buildPayload = (number, withOptional) => {
    const p = {
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
    }
    if (withOptional) {
      p.source = source || 'booking'
      if (order_id) p.order_id = order_id
      // VS = ručně zadaný (převod) NEBO číslo dokladu — VŽDY číselný (textový
      // VS „ZF-2026-0204" banka nepřijme, platba by se nespárovala).
      if (number) {
        const rawVs = String((payment && payment.vs) || number)
        p.variable_symbol = rawVs.replace(/\D/g, '') || rawVs
      }
      // Ruční platební údaje na doklad (DP/ZF) — způsob platby, datum úhrady, č. transakce.
      if (payment) {
        if (payment.method) p.payment_method = payment.method
        if (payment.transaction_ref) p.transaction_ref = payment.transaction_ref
        if (payment.paid_date) p.paid_date = payment.paid_date
        // Propojení DP ↔ zálohová faktura (ZF), aby šla platba + doklady spárovat.
        if (payment.advance_invoice_id) p.original_invoice_id = payment.advance_invoice_id
      }
    }
    return p
  }

  const isDuplicateNumber = (err) =>
    err && (err.code === '23505' || /duplicate key|invoices_number_key|unique constraint/i.test(err.message || ''))

  let data = null
  let lastErr = null
  let useOptional = true

  for (let attempt = 0; attempt < 5; attempt++) {
    const number = await generateInvoiceNumber(type, !!manual)
    const result = await supabase
      .from('invoices')
      .insert(buildPayload(number, useOptional))
      .select()
      .single()

    if (!result.error) { data = result.data; lastErr = null; break }

    lastErr = result.error
    if (isDuplicateNumber(result.error)) {
      // Race on invoice number — re-query max and retry with backoff
      await new Promise(r => setTimeout(r, 50 + Math.floor(Math.random() * 150)))
      continue
    }
    // Non-conflict error — try once without optional columns (legacy schemas)
    if (useOptional) {
      useOptional = false
      const retry = await supabase
        .from('invoices')
        .insert(buildPayload(number, false))
        .select()
        .single()
      if (!retry.error) { data = retry.data; lastErr = null; break }
      lastErr = retry.error
      if (isDuplicateNumber(retry.error)) continue
    }
    break
  }

  if (lastErr) {
    console.error('[createInvoice] Insert failed after retries:', lastErr.message, lastErr.details, lastErr.hint)
    throw lastErr
  }

  // Document sync is handled by DB trigger (sync_invoice_to_documents)
  // Do NOT manually insert into documents — the trigger does it automatically

  // Zamraž fakturační údaje odběratele (customer_snapshot) — STEJNĚ jako
  // generate-invoice na serveru. Bez toho by doklady vystavené z Velína
  // (ruční faktury, DP z potvrzení platby, dobropisy) zpětně měnily
  // odběratele při každé úpravě profilu. Non-fatal.
  if (data?.id && customer_id) {
    try {
      const { data: p } = await supabase.from('profiles')
        .select('full_name, email, phone, street, city, zip, ico, dic, company_name, company_address')
        .eq('id', customer_id).maybeSingle()
      if (p) {
        await supabase.from('invoices').update({
          customer_snapshot: {
            name: p.full_name || null, company: p.company_name || null,
            company_address: p.company_address || null,
            ico: p.ico || null, dic: p.dic || null,
            email: p.email || null, phone: p.phone || null,
            address: [p.street, p.city, p.zip].filter(Boolean).join(', ') || null,
          },
        }).eq('id', data.id)
      }
    } catch {} // non-blocking
  }

  // Audit log (non-blocking)
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id,
      action: 'invoice_created',
      // `data.number` — proměnná `number` žila jen uvnitř retry smyčky; odkaz na ni
      // tady házel ReferenceError a celý audit insert se tiše zahazoval.
      details: { invoice_id: data.id, number: data.number, type, source },
    })
  } catch {} // non-blocking

  return data
}

/**
 * Generate advance invoice (ZF) for a booking — daily price breakdown
 */
export async function generateAdvanceInvoice(bookingId, source = 'booking', payment = null) {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles!moto_id(${MOTO_SELECT}), profiles:user_id(id, full_name, email)`)
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
    payment,
  })
}

/**
 * Generate payment receipt (DP) for a booking — daily price breakdown
 */
export async function generatePaymentReceipt(bookingId, source = 'booking', payment = null) {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles!moto_id(${MOTO_SELECT}, branch_id), profiles:user_id(id, full_name, email)`)
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const items = buildBookingItems(moto, booking)

  // Fetch door codes for this booking (if already generated by trigger)
  let doorCodesNote = ''
  try {
    const { data: codes } = await supabase
      .from('branch_door_codes')
      .select('code_type, door_code, withheld_reason')
      .eq('booking_id', bookingId)
    if (codes && codes.length > 0) {
      const withheld = codes.some(c => c.withheld_reason)
      if (withheld) {
        doorCodesNote = '\nPřístupové kódy budou zaslány po ověření dokladů.'
      } else {
        const motoCode = codes.find(c => c.code_type === 'motorcycle')
        const accCode = codes.find(c => c.code_type === 'accessories')
        doorCodesNote = '\nPŘÍSTUPOVÉ KÓDY:'
        if (motoCode) doorCodesNote += `\nKód k motorce: ${motoCode.door_code}`
        if (accCode) doorCodesNote += `\nKód k příslušenství: ${accCode.door_code}`
        doorCodesNote += '\nKódy jsou platné po dobu trvání pronájmu.'
      }
    }
  } catch (e) {
    console.warn('[generatePaymentReceipt] Failed to fetch door codes:', e.message)
  }

  // Vazba na zálohovou fakturu (ZF) na dokladu — pro spárování platby a dokladů.
  const advanceNote = payment?.advance_number ? `\nK zálohové faktuře ${payment.advance_number}` : ''

  const dp = await createInvoice({
    type: 'payment_receipt',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    notes: `Období pronájmu: ${fmtDateCS(booking.start_date)} – ${fmtDateCS(booking.end_date)}${advanceNote}${doorCodesNote}`,
    source,
    status: 'paid',
    payment,
  })

  // DP = doklad o PŘIJATÉ platbě → ZF téže rezervace už není „K úhradě".
  // Bez tohohle zůstala ZF navždy 'issued' a doklad i seznam ukazovaly K ÚHRADĚ.
  try {
    await supabase.from('invoices')
      .update({ status: 'paid', paid_date: (payment && payment.paid_date) || new Date().toISOString().slice(0, 10) })
      .eq('booking_id', bookingId).in('type', ['advance', 'proforma'])
      .neq('status', 'cancelled').neq('status', 'paid')
  } catch {} // non-blocking

  return dp
}

/**
 * Vyrenderuj fakturu/DP do HTML a ulož PDF (storeInvoicePdf → pdf_path).
 * Používá se po ručním potvrzení platby, aby `send-booking-email` mohl
 * uložené PDF znovupoužít jako přílohu (místo regenerace bez ručních údajů).
 */
export async function renderAndStoreInvoicePdf(invoiceId) {
  const data = await loadInvoiceData(invoiceId)
  const html = generateInvoiceHtml({
    type: data.type,
    number: data.number,
    issue_date: data.issue_date,
    due_date: data.due_date,
    duzp: data.issue_date,
    items: data.items || [],
    subtotal: data.subtotal,
    tax_amount: data.tax_amount,
    total: data.total,
    notes: data.notes,
    variable_symbol: data.variable_symbol || data.number,
    customer: invoiceCustomer(data),
    cardInfo: data.cardInfo,
    stripe_payment_intent_id: data.stripe_payment_intent_id,
    paymentMethodLabel: data.paymentMethodLabel,
    payment_method: data.payment_method,
    transaction_ref: data.transaction_ref,
    voucher_codes: data.voucher_codes,
    voucherValidUntil: data.voucherValidUntil,
    door_codes: data.door_codes,
    paid_date: data.paid_date,
    booking_id: data.booking_id,
    bookings: data.bookings,
  })
  return storeInvoicePdf(invoiceId, html)
}

/**
 * Generate final invoice (KF) for a booking — daily price breakdown + deduct advances
 */
export async function generateFinalInvoice(bookingId) {
  // Check if KF already exists (prevent duplicates)
  const { data: existingKf } = await supabase
    .from('invoices').select('id, number')
    .eq('booking_id', bookingId).eq('type', 'final').limit(1)
  if (existingKf?.length) return existingKf[0]

  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles!moto_id(${MOTO_SELECT}), profiles:user_id(id, full_name, email)`)
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const moto = booking.motorcycles || {}
  const items = buildBookingItems(moto, booking)

  // If total_price > service total (due to storno-absorbed shortening), add storno fee line
  const serviceTotal = calculateTotals(items).total
  const bookingTotal = Number(booking.total_price || 0)
  if (bookingTotal > serviceTotal && serviceTotal > 0) {
    const retainedAmount = Math.round(bookingTotal - serviceTotal)
    items.push({ description: 'Storno poplatek (dle storno podmínek)', qty: 1, unit_price: retainedAmount })
  }

  // Deduct ALL DP (doklady k přijaté platbě) — reservation, edits, SOS
  // ZF (zálohové faktury) se NEODEČÍTAJÍ — nejsou dokladem o přijaté platbě
  const { data: receipts } = await supabase
    .from('invoices').select('number, total, type, source')
    .eq('booking_id', bookingId).eq('type', 'payment_receipt')
    .neq('status', 'cancelled')
    .order('issue_date', { ascending: true })

  if (receipts?.length) {
    receipts.forEach(a => {
      items.push({ description: `Odpočet dle DP ${a.number}`, qty: 1, unit_price: -Number(a.total || 0) })
    })
  }

  // Připočti vrácené částky dle dobropisů (credit_note). Dobropis = peníze vrácené
  // zákazníkovi, takže v KF kompenzuje odpočet DP (kladná položka). `credit_note.total`
  // je uložen záporně → `-total` = kladná vrácená částka.
  // Příklad: služba 4 000, DP −5 000, dobropis +1 000 → Celkem 0 Kč.
  const { data: creditNotes } = await supabase
    .from('invoices').select('number, total, type, status')
    .eq('booking_id', bookingId).eq('type', 'credit_note')
    .neq('status', 'cancelled')
    .order('issue_date', { ascending: true })

  if (creditNotes?.length) {
    creditNotes.forEach(cn => {
      items.push({ description: `Vrácení dle dobropisu ${cn.number}`, qty: 1, unit_price: -Number(cn.total || 0) })
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
  openPrintWindow(html)
}

/**
 * Render invoice HTML to PDF (klient-side) a nahraj do Supabase Storage.
 * Při selhání PDF konverze se uloží HTML fallback (path končí .html).
 */
export async function storeInvoicePdf(invoiceId, html) {
  const targetPath = `invoices/${invoiceId}.pdf`
  const finalPath = await uploadHtmlAsPdf(supabase, targetPath, html, {
    filename: `${invoiceId}.pdf`,
  })

  await supabase
    .from('invoices')
    .update({ pdf_path: finalPath })
    .eq('id', invoiceId)

  return finalPath
}

/**
 * Generate credit note (DB - dobropis) for a booking refund
 * Links to original invoice, records Stripe refund ID
 */
export async function generateCreditNote(bookingId, { refundAmount, refundPercent, reason, stripeRefundId, originalInvoiceId } = {}) {
  const { data: booking, error: bErr } = await supabase
    .from('bookings')
    .select(`*, motorcycles!moto_id(${MOTO_SELECT}), profiles:user_id(id, full_name, email)`)
    .eq('id', bookingId).single()
  if (bErr || !booking) throw new Error(bErr?.message || 'Booking not found')

  const amount = refundAmount || Number(booking.total_price || 0)
  const percent = refundPercent || 100

  // Find original invoice to link (prefer KF, then DP, then ZF)
  let origInvId = originalInvoiceId || null
  if (!origInvId) {
    const { data: origInvs } = await supabase
      .from('invoices').select('id, type, number')
      .eq('booking_id', bookingId)
      .neq('status', 'cancelled')
      .in('type', ['final', 'payment_receipt', 'advance', 'proforma'])
      .order('issue_date', { ascending: false })
    if (origInvs?.length) {
      const kf = origInvs.find(i => i.type === 'final')
      const dp = origInvs.find(i => i.type === 'payment_receipt')
      origInvId = (kf || dp || origInvs[0]).id
    }
  }

  const reasonText = reason || 'Storno rezervace'
  const moto = booking.motorcycles || {}
  const items = [
    {
      description: `Dobropis – ${reasonText} (${moto.model || 'motorka'}, ${fmtDateCS(booking.start_date)} – ${fmtDateCS(booking.end_date)})`,
      qty: 1,
      unit_price: -amount,
    },
  ]

  const payload = {
    type: 'credit_note',
    customer_id: booking.profiles?.id || booking.user_id,
    booking_id: bookingId,
    items,
    notes: `Dobropis k rezervaci #${bookingId.slice(-8).toUpperCase()}. ${percent < 100 ? `Částečný refund ${percent}%.` : 'Plný refund.'} ${reasonText}`,
    source: 'refund',
    status: 'issued',
  }

  const invoice = await createInvoice(payload)

  // Update with extra fields (original_invoice_id, stripe_refund_id)
  const extraUpdate = {}
  if (origInvId) extraUpdate.original_invoice_id = origInvId
  if (stripeRefundId) extraUpdate.stripe_refund_id = stripeRefundId
  if (Object.keys(extraUpdate).length > 0) {
    await supabase.from('invoices').update(extraUpdate).eq('id', invoice.id).catch(() => {})
  }

  // Create negative accounting entry for the refund
  try {
    await supabase.from('accounting_entries').insert({
      type: 'expense',
      amount: -amount,
      description: `Dobropis ${invoice.number} – ${reasonText}`,
      category: 'refund',
      date: new Date().toISOString().slice(0, 10),
      booking_id: bookingId,
    })
  } catch {} // non-blocking

  return invoice
}

/**
 * Sestaví ODBĚRATELE pro render faktury. Priorita:
 *   1) invoices.customer_snapshot (zamražené fakturační údaje při vystavení —
 *      vyplní generate-invoice; jediný zdroj pro anonymní e-shop/voucher objednávky,
 *      kde customer_id=null a profil neexistuje),
 *   2) profiles join (booking faktury),
 *   3) prázdné.
 * Bez tohohle Velín (Finance/Dokumenty) renderoval ODBĚRATEL z profilu → u voucheru prázdno.
 */
export function invoiceCustomer(data) {
  const cs = data?.customer_snapshot
  const p = data?.profiles
  if (cs && (cs.name || cs.company || cs.ico || cs.email)) {
    // Zamražené hodnoty mají přednost; CHYBĚJÍCÍ pole doplní aktuální profil —
    // starší snapshoty vznikly před firemními sloupci a firma/sídlo v nich není.
    return {
      name: cs.name || p?.full_name || '', email: cs.email || p?.email || '', phone: cs.phone || p?.phone || '',
      address: cs.address || [p?.street, p?.city, p?.zip, p?.country].filter(Boolean).join(', ') || '',
      ico: cs.ico || p?.ico || '', dic: cs.dic || p?.dic || '',
      company: cs.company || p?.company_name || '',
      company_address: cs.company_address || p?.company_address || '',
    }
  }
  return {
    name: p?.full_name || '', email: p?.email || '', phone: p?.phone || '',
    address: [p?.street, p?.city, p?.zip, p?.country].filter(Boolean).join(', ') || '',
    ico: p?.ico || '', dic: p?.dic || '',
    company: p?.company_name || '', company_address: p?.company_address || '',
  }
}

/**
 * Load full invoice data with relations
 */
export async function loadInvoiceData(invoiceId) {
  const { data, error } = await supabase
    .from('invoices')
    .select('*, profiles:customer_id(full_name, email, phone, street, city, zip, country, ico, dic, company_name, company_address), bookings:booking_id(id, start_date, end_date, total_price, motorcycles!moto_id(model, spz)), shop_orders:order_id(stripe_payment_intent_id, stripe_session_id, payment_method)')
    .eq('id', invoiceId)
    .single()

  if (error) throw error

  // E-shop/voucher faktury platí kartou přes Stripe → na dokladu místo bank. účtu (mBank)
  // zobraz „Platba kartou (Stripe)" + identifikátor. Doplníme do dat pro client render.
  if (data) {
    const sp = data.shop_orders?.stripe_payment_intent_id || data.shop_orders?.stripe_session_id || data.stripe_payment_intent_id || null
    if (sp && !data.stripe_payment_intent_id) data.stripe_payment_intent_id = sp
    if (sp && !data.cardInfo) { data.cardInfo = { brand: 'card', last4: '' }; data.paymentMethodLabel = 'Platba kartou (Stripe)' }
  }

  // Dárkové poukazy (e-shop objednávka) — stejný formát jako generate-invoice,
  // aby se ve Velínu vykreslil blok DÁRKOVÉ POUKAZY 1:1 jako na e-shop/mailovém dokladu.
  // POZOR: kódy jen na ZAPLACENÉM dokladu (DP / konečná). NIKDY na ZF (zálohová
  // faktura) — ta nemusí být uhrazená a zveřejnění kódů by je „uvolnilo" před platbou.
  const isUnpaidProforma = ['proforma', 'shop_proforma', 'advance'].includes(data?.type)
  if (data && data.order_id && !isUnpaidProforma && data.type !== 'credit_note') {
    try {
      const { data: vouchers } = await supabase
        .from('vouchers').select('code, amount, valid_until').eq('order_id', data.order_id)
      if (vouchers && vouchers.length > 0) {
        data.voucher_codes = vouchers.map(v =>
          `${v.code} — ${(v.amount || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })} Kč, platný do ${v.valid_until ? new Date(v.valid_until).toLocaleDateString('cs-CZ') : '—'}`)
        data.voucherValidUntil = vouchers[0].valid_until
      }
    } catch (e) {
      console.warn('[loadInvoiceData] Failed to fetch vouchers:', e.message)
    }
  }

  // Pro DP (payment_receipt) načti přístupové kódy — ale jen dokud pronájem
  // trvá. Re-render/doposlání dokladu PO konci nájmu nesmí nést už neplatné kódy.
  if (data && data.type === 'payment_receipt' && data.booking_id) {
    const endDate = data.bookings?.end_date ? String(data.bookings.end_date).slice(0, 10) : null
    const rentalOver = endDate && endDate < new Date().toISOString().slice(0, 10)
    if (!rentalOver) {
      try {
        const { data: codes } = await supabase
          .from('branch_door_codes')
          .select('code_type, door_code, withheld_reason')
          .eq('booking_id', data.booking_id)
        if (codes && codes.length > 0) {
          data.door_codes = codes
        }
      } catch (e) {
        console.warn('[loadInvoiceData] Failed to fetch door codes:', e.message)
      }
    }
    // Zastaralá poznámka z doby vystavení („kódy budou zaslány po ověření
    // dokladů") si protiřečí s blokem už uvolněných kódů — jakmile kódy nejsou
    // zadržené (nebo pronájem skončil), poznámku z renderu odstraň.
    const stillWithheld = (data.door_codes || []).some(c => c.withheld_reason)
    if (data.notes && !stillWithheld) {
      data.notes = data.notes.replace(/\s*Přístupové kódy budou zaslány po ověření dokladů\.?/g, '').trim() || null
    }
  }

  return data
}
