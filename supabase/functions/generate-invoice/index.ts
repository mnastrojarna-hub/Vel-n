import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { generateInvoiceHtml, generateEmailHtml } from './template.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'

const COMPANY_FALLBACK = {
  name: 'Bc. Petra Semorádová', address: 'Mezná 9, 393 01 Mezná',
  ico: '21874263', dic: null, vat_payer: false,
  bank_account: '670100-2225851630/6210', phone: '+420 774 256 271',
  email: 'info@motogo24.cz', web: 'www.motogo24.cz',
}

async function loadCompanyInfo(supabase: any) {
  try {
    const { data } = await supabase.from('app_settings').select('value').eq('key', 'company_info').limit(1)
    const info = data?.[0]?.value
    if (info && info.name) {
      return {
        name: info.name || COMPANY_FALLBACK.name, address: info.address || COMPANY_FALLBACK.address,
        ico: info.ico || COMPANY_FALLBACK.ico, dic: info.dic || null, vatPayer: info.vat_payer || false,
        bank: 'mBank', account: info.bank_account || COMPANY_FALLBACK.bank_account,
        phone: info.phone || COMPANY_FALLBACK.phone, email: info.email || COMPANY_FALLBACK.email,
        web: info.web || COMPANY_FALLBACK.web,
      }
    }
  } catch (e) { console.warn('Failed to load company_info:', e) }
  return { ...COMPANY_FALLBACK, vatPayer: false, bank: 'mBank', account: COMPANY_FALLBACK.bank_account }
}

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

const CORS = {
  'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { type, booking_id, order_id, send_email, extra_items, voucher_codes: explicitVoucherCodes } = await req.json()
    if (!booking_id && !order_id) return new Response(JSON.stringify({ error: 'Missing booking_id or order_id' }), { status: 400 })

    let voucher_codes: string[] | undefined = explicitVoucherCodes
    let voucherValidUntil: string | null = null
    let doorCodes: any[] = []

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const COMPANY = await loadCompanyInfo(supabase)

    const invoiceType = type || 'proforma'
    const isShop = invoiceType === 'shop_proforma' || invoiceType === 'shop_final' || (order_id && !booking_id)
    const isProforma = invoiceType === 'proforma' || invoiceType === 'shop_proforma' || invoiceType === 'advance'
    const isPaymentReceipt = invoiceType === 'payment_receipt'
    const prefix = isPaymentReceipt ? 'DP' : isProforma ? 'ZF' : 'FV'
    const year = new Date().getFullYear()

    let customer: any = {}
    let items: { description: string; qty: number; unit_price: number }[] = []
    let customerId: string | null = null

    if (isShop && order_id) {
      const { data: order, error: oErr } = await supabase
        .from('shop_orders').select('*, shop_order_items(*)').eq('id', order_id).single()
      if (oErr || !order) return new Response(JSON.stringify({ error: 'Order not found' }), { status: 404 })

      customerId = order.customer_id
      if (order.customer_id) {
        const { data: profile } = await supabase.from('profiles')
          .select('id, full_name, email, phone, street, city, zip, country, ico, dic')
          .eq('id', order.customer_id).single()
        if (profile) customer = profile
      }
      if (!customer.full_name) customer = { full_name: order.customer_name, email: order.customer_email, phone: order.customer_phone }

      for (const it of (order.shop_order_items || [])) {
        items.push({ description: it.product_name, qty: it.quantity || 1, unit_price: it.unit_price || 0 })
      }
      if (order.shipping_cost > 0) items.push({ description: 'Doprava', qty: 1, unit_price: Number(order.shipping_cost) })
      if (order.discount > 0) items.push({ description: 'Sleva', qty: 1, unit_price: -Number(order.discount) })

      if (!explicitVoucherCodes || explicitVoucherCodes.length === 0) {
        const { data: orderVouchers } = await supabase.from('vouchers').select('code, amount, valid_until').eq('order_id', order_id)
        if (orderVouchers && orderVouchers.length > 0) {
          voucher_codes = orderVouchers.map((v: any) => `${v.code} — ${fmtPrice(v.amount)} Kč, platný do ${fmtDate(v.valid_until)}`)
          voucherValidUntil = orderVouchers[0].valid_until
        }
      }
    } else {
      const { data: booking, error: bErr } = await supabase
        .from('bookings').select('*, motorcycles(model, spz), profiles(id, full_name, email, phone, street, city, zip, country, ico, dic)')
        .eq('id', booking_id).single()
      if (bErr || !booking) return new Response(JSON.stringify({ error: 'Booking not found' }), { status: 404 })

      customer = booking.profiles || {}
      customerId = customer.id || booking.user_id
      const startDate = fmtDate(booking.start_date); const endDate = fmtDate(booking.end_date)
      const days = Math.max(1, Math.ceil((new Date(booking.end_date).getTime() - new Date(booking.start_date).getTime()) / 86400000))
      const baseRental = (booking.total_price || 0) - (booking.extras_price || 0) - (booking.delivery_fee || 0) + (booking.discount_amount || 0)
      items.push({ description: `Pronájem ${booking.motorcycles?.model || 'motorky'} (${booking.motorcycles?.spz || ''}) — ${startDate} – ${endDate}`, qty: days, unit_price: Math.round(baseRental / days) })
      if (booking.extras_price && Number(booking.extras_price) > 0) items.push({ description: 'Příslušenství a výbava', qty: 1, unit_price: Number(booking.extras_price) })
      if (extra_items && Array.isArray(extra_items)) extra_items.forEach((ei: any) => items.push({ description: ei.description || 'Položka', qty: ei.qty || 1, unit_price: ei.unit_price || 0 }))
      if (booking.delivery_fee && Number(booking.delivery_fee) > 0) items.push({ description: 'Přistavení / odvoz motorky', qty: 1, unit_price: Number(booking.delivery_fee) })
      if (booking.sos_replacement && !extra_items) items.push({ description: 'Záloha na poškození motorky', qty: 1, unit_price: 30000 })
      if (booking.discount_amount && Number(booking.discount_amount) > 0) {
        items.push({ description: booking.discount_code ? `Sleva (kód: ${booking.discount_code})` : 'Sleva / voucher', qty: 1, unit_price: -Number(booking.discount_amount) })
      }
      if (isPaymentReceipt) {
        try {
          const { data: codes } = await supabase.from('branch_door_codes').select('code_type, door_code, withheld_reason').eq('booking_id', booking_id)
          if (codes && codes.length > 0) doorCodes = codes
        } catch (e) { console.warn('Failed to fetch door codes:', e) }
      }
    }

    // ── Guard: skip ZF/DP generation for zero-amount bookings (free modifications, SOS without payment) ──
    if (booking_id && !isShop && (isProforma || isPaymentReceipt)) {
      const { data: bkCheck } = await supabase.from('bookings').select('total_price').eq('id', booking_id).single()
      if (bkCheck && Number(bkCheck.total_price || 0) <= 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Booking has zero amount — ZF/DP not generated', skipped: true
        }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
    }

    // ── Dedup: prevent duplicate invoices of same type for same booking/order ──
    if (booking_id && !isShop) {
      const dedupTypes = isPaymentReceipt ? ['payment_receipt'] : isProforma ? ['advance', 'proforma'] : ['final', 'issued']
      const { data: existing } = await supabase.from('invoices').select('id, number, pdf_path')
        .eq('booking_id', booking_id).in('type', dedupTypes)
        .neq('status', 'cancelled').limit(1)
      const invoiceSource = type === 'payment_receipt' ? 'booking' : (type || 'booking')
      if (existing?.length && invoiceSource === 'booking') {
        const { data: sameSource } = await supabase.from('invoices').select('id, number, pdf_path')
          .eq('booking_id', booking_id).in('type', dedupTypes)
          .eq('source', 'booking').neq('status', 'cancelled').limit(1)
        if (sameSource?.length) {
          // Check if HTML file exists in Storage — if not, regenerate it
          let htmlExists = false
          if (sameSource[0].pdf_path) {
            try {
              const { data: blob } = await supabase.storage.from('documents').download(sameSource[0].pdf_path)
              if (blob && blob.size > 0) htmlExists = true
            } catch { /* file missing */ }
          }
          if (htmlExists) {
            return new Response(JSON.stringify({
              success: true, invoice_id: sameSource[0].id, number: sameSource[0].number, existing: true
            }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
          }
          // HTML missing — continue to regenerate for existing invoice
          console.log(`Invoice ${sameSource[0].number} exists but HTML missing — regenerating`)
        }
      }
    }

    // Generate number
    const { data: lastInv } = await supabase.from('invoices').select('number')
      .like('number', `${prefix}-${year}-%`).order('number', { ascending: false }).limit(1)
    let seq = 1
    if (lastInv?.length) { const m = lastInv[0].number.match(/-(\d+)$/); if (m) seq = parseInt(m[1], 10) + 1 }
    const number = `${prefix}-${year}-${String(seq).padStart(4, '0')}`

    // Pro shop_final: odečti DP → konečná faktura za 0 Kč
    let dpDeduction = 0; let dpNumber = ''
    const isShopFinal = invoiceType === 'shop_final'
    if (isShopFinal && order_id) {
      const { data: dpInv } = await supabase.from('invoices').select('number, total')
        .eq('order_id', order_id).eq('type', 'payment_receipt').order('created_at', { ascending: false }).limit(1)
      if (dpInv?.length) { dpDeduction = dpInv[0].total || 0; dpNumber = dpInv[0].number || '' }
      items.push({ description: `Odečet DP ${dpNumber} (již uhrazeno)`, qty: 1, unit_price: -dpDeduction })
    }

    const subtotal = items.reduce((s, it) => s + it.unit_price * it.qty, 0)
    const total = subtotal; const issueDate = new Date().toISOString().slice(0, 10)
    const dueDate = new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10)

    const invoicePayload: any = {
      number, type: invoiceType, customer_id: customerId,
      items, subtotal, tax_amount: 0, total,
      issue_date: issueDate, due_date: dueDate, status: 'issued', variable_symbol: number,
    }
    if (booking_id) invoicePayload.booking_id = booking_id
    if (order_id) invoicePayload.order_id = order_id

    const { data: invoice, error: iErr } = await supabase.from('invoices').insert(invoicePayload).select().single()
    if (iErr) return new Response(JSON.stringify({ error: iErr.message }), { status: 500 })

    const accent = isPaymentReceipt ? '#0891b2' : isProforma ? '#2563eb' : '#1a8a18'
    const title = isPaymentReceipt ? 'DAŇOVÝ DOKLAD K PŘIJATÉ PLATBĚ' : isProforma ? 'ZÁLOHOVÁ FAKTURA' : isShopFinal ? 'KONEČNÁ FAKTURA' : 'FAKTURA'
    const bookingNumber = booking_id ? booking_id.slice(-8).toUpperCase() : ''

    const html = generateInvoiceHtml({
      title, number, accent, issueDate, dueDate, total, company: COMPANY, customer, items,
      voucher_codes, voucherValidUntil, doorCodes, isProforma, isPaymentReceipt, isShopFinal, dpNumber, bookingNumber,
    })

    const blob = new Blob([html], { type: 'text/html' })
    const path = `invoices/${invoice.id}.html`
    await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'text/html' })
    await supabase.from('invoices').update({ pdf_path: path }).eq('id', invoice.id)

    if (send_email !== false && customer.email) {
      const emailSubject = `${isPaymentReceipt ? 'Doklad k přijaté platbě' : isProforma ? 'Zálohová faktura' : isShopFinal ? 'Konečná faktura' : 'Faktura'} č. ${number} — MOTO GO 24`
      const emailHtml = generateEmailHtml({
        customer, company: COMPANY, title, number, total, dueDate,
        voucher_codes, voucherValidUntil, doorCodes, isPaymentReceipt, isProforma, isShopFinal, bookingNumber,
      })
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: FROM_EMAIL, to: customer.email, subject: emailSubject, html: emailHtml }),
      })
    }

    await supabase.from('admin_audit_log').insert({ action: 'invoice_generated', details: { invoice_id: invoice.id, number, type: invoiceType, booking_id } })

    return new Response(JSON.stringify({ success: true, invoice_id: invoice.id, number }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 })
  }
})
