import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { generateInvoiceHtml } from './template.ts'

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

// ===== PRICE BREAKDOWN PER DAY =====
// Motorky mají denní ceny v sloupcích price_mon..price_sun + fallback price_weekday.
// Vstup: motorcycles row (může být null), startDate, endDate (date string nebo ISO timestamp).
// Výstup: { total, days: [{iso,dow,dowLabel,price}], uniform } — uniform=true když všechny dny stejná cena.
const DOW_LABELS_CS = ['Ne', 'Po', 'Út', 'St', 'Čt', 'Pá', 'So']
const DOW_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']
function calcPriceBreakdown(moto: any, startDate: string, endDate: string): { total: number; days: Array<{ iso: string; dow: number; dowLabel: string; price: number }>; uniform: boolean } {
  if (!moto || !startDate || !endDate) return { total: 0, days: [], uniform: true }
  const s = new Date(startDate); const e = new Date(endDate)
  if (isNaN(s.getTime()) || isNaN(e.getTime()) || s > e) return { total: 0, days: [], uniform: true }
  const d = new Date(s.getFullYear(), s.getMonth(), s.getDate())
  const eDate = new Date(e.getFullYear(), e.getMonth(), e.getDate())
  const arr: Array<{ iso: string; dow: number; dowLabel: string; price: number }> = []
  let total = 0
  while (d <= eDate) {
    const dow = d.getDay()
    const price = Number(moto['price_' + DOW_KEYS[dow]] || moto.price_weekday || 0)
    const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    arr.push({ iso, dow, dowLabel: DOW_LABELS_CS[dow], price })
    total += price
    d.setDate(d.getDate() + 1)
  }
  const uniform = arr.length <= 1 || arr.every((x) => x.price === arr[0].price)
  return { total, days: arr, uniform }
}

const CORS = {
  'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Map booking_extras.name → size column on bookings row
function matchExtraSize(name: string, b: any): string | null {
  const n = (name || '').toLowerCase()
  const passenger = n.includes('spolujez') || n.includes('passenger')
  const pick = (driver: string, pas: string) => passenger ? (b[pas] || null) : (b[driver] || null)
  if (n.includes('boty') || n.includes('boots')) return pick('boots_size', 'passenger_boots_size')
  if (n.includes('helma') || n.includes('helmet')) return pick('helmet_size', 'passenger_helmet_size')
  if (n.includes('bunda') || n.includes('jacket')) return pick('jacket_size', 'passenger_jacket_size')
  if (n.includes('kalhoty') || n.includes('pants')) return pick('pants_size', 'passenger_pants_size')
  if (n.includes('rukavice') || n.includes('gloves')) return pick('gloves_size', 'passenger_gloves_size')
  if (n.includes('výbava') || n.includes('vybava') || n.includes('set')) {
    if (passenger) {
      const parts = [b.passenger_helmet_size && `helma ${b.passenger_helmet_size}`, b.passenger_jacket_size && `bunda/vesta ${b.passenger_jacket_size}`, b.passenger_pants_size && `kalhoty ${b.passenger_pants_size}`, b.passenger_boots_size && `boty ${b.passenger_boots_size}`, b.passenger_gloves_size && `rukavice ${b.passenger_gloves_size}`].filter(Boolean)
      return parts.length ? parts.join(', ') : null
    }
    const parts = [b.helmet_size && `helma ${b.helmet_size}`, b.jacket_size && `bunda ${b.jacket_size}`, b.pants_size && `kalhoty ${b.pants_size}`, b.boots_size && `boty ${b.boots_size}`, b.gloves_size && `rukavice ${b.gloves_size}`].filter(Boolean)
    return parts.length ? parts.join(', ') : null
  }
  return null
}

// Load primary card info for a booking paid via Stripe (brand + last4)
async function loadPaymentCardInfo(supabase: any, booking: any): Promise<{ brand: string; last4: string; wallet?: string } | null> {
  if (!booking?.stripe_payment_intent_id) return null
  const userId = booking.user_id || booking.profiles?.id
  if (!userId) return null
  try {
    const { data: pms } = await supabase.from('payment_methods')
      .select('brand, last4, is_default, created_at')
      .eq('user_id', userId)
      .order('is_default', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(1)
    if (pms?.length) {
      return { brand: pms[0].brand || 'card', last4: pms[0].last4 || '****' }
    }
  } catch { /* ignore */ }
  return { brand: 'card', last4: '****' }
}

// Build label for an extra row (name + size if applicable)
function extraLabel(name: string, booking: any): string {
  const size = matchExtraSize(name, booking)
  if (!size) return name
  // If size is a composite (contains comma) show it on a second segment
  return `${name} (${size})`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const {
      type, booking_id, order_id, send_email,
      extra_items, voucher_codes: explicitVoucherCodes,
      source: reqSource,
    } = await req.json()
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

    // Source defaults to 'booking' for standard flow; 'edit' marks per-modification invoices
    const invoiceSource: string = reqSource || 'booking'
    const isEdit = invoiceSource === 'edit' && !isShop

    let customer: any = {}
    let items: { description: string; qty: number; unit_price: number }[] = []
    let customerId: string | null = null
    let cardInfo: { brand: string; last4: string } | null = null
    let editLabel = '' // e.g. "ÚPRAVA — +2 dny"
    let paymentMethodLabel = '' // "Bankovní převod" / "Platba kartou Visa **** 4242"

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
        .from('bookings').select('*, motorcycles(model, spz, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, price_weekday, price_weekend), profiles(id, full_name, email, phone, street, city, zip, country, ico, dic)')
        .eq('id', booking_id).single()
      if (bErr || !booking) return new Response(JSON.stringify({ error: 'Booking not found' }), { status: 404 })

      customer = booking.profiles || {}
      customerId = customer.id || booking.user_id

      // Load per-booking extras with proper names (sizes derived from booking columns)
      const { data: bookExtras } = await supabase.from('booking_extras')
        .select('name, unit_price, quantity')
        .eq('booking_id', booking_id)
      const extras = bookExtras || []

      // Identify card info for payment method display
      cardInfo = await loadPaymentCardInfo(supabase, booking)
      paymentMethodLabel = cardInfo
        ? `Platba kartou ${cardInfo.brand?.toUpperCase() || 'CARD'} **** ${cardInfo.last4 || '****'}`
        : 'Bankovní převod'

      if (isEdit) {
        // ===== EDIT: generate delta-items based on last modification_history entry =====
        const history = Array.isArray(booking.modification_history) ? booking.modification_history : []
        const last = history[history.length - 1]
        if (!last) {
          return new Response(JSON.stringify({ error: 'No modification_history entry for edit invoice' }), {
            status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
          })
        }
        const priceDiff = Number(last.price_diff || 0)
        if (priceDiff <= 0) {
          return new Response(JSON.stringify({
            success: false, skipped: true,
            error: 'Edit price_diff <= 0 — use process-refund for shortening'
          }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
        }

        // Compute delta days (to_end - from_end for prodloužení)
        const fromEnd = last.from_end ? new Date(last.from_end).getTime() : 0
        const toEnd = last.to_end ? new Date(last.to_end).getTime() : 0
        const fromStart = last.from_start ? new Date(last.from_start).getTime() : 0
        const toStart = last.to_start ? new Date(last.to_start).getTime() : 0
        const deltaDays = Math.round(((toEnd - fromEnd) - (toStart - fromStart)) / 86400000)
        const motoLabel = `${booking.motorcycles?.model || 'motorky'}${booking.motorcycles?.spz ? ' (' + booking.motorcycles.spz + ')' : ''}`
        const fmtD = (s: string) => s ? new Date(s).toLocaleDateString('cs-CZ') : '—'

        editLabel = deltaDays > 0
          ? `ÚPRAVA — prodloužení o ${deltaDays} ${deltaDays === 1 ? 'den' : deltaDays < 5 ? 'dny' : 'dní'}`
          : `ÚPRAVA — změna termínu`

        // Hlavička úpravy — section header (renderuje se přes colspan, bez ceny v řádku).
        items.push({
          description: `── Úprava rezervace: ${motoLabel} — nový termín ${fmtD(last.to_start)} – ${fmtD(last.to_end)} (původně ${fmtD(last.from_start)} – ${fmtD(last.from_end)}) ──`,
          qty: 1,
          unit_price: 0,
        })

        // Denní rozpis přidaných dnů (extend) — vychází z denních cen motorky.
        // Bezpečné: pokud se rozpis nesejde s priceDiff (např. ruční override),
        // přidáme korekční řádek aby součet seděl 1:1 s tím, co user platí.
        const ext = calcPriceBreakdown(booking.motorcycles, last.to_start, last.to_end)
        const orig = calcPriceBreakdown(booking.motorcycles, last.from_start, last.from_end)
        const origIso = new Set((orig.days || []).map((d) => d.iso))
        const addedDays = (ext.days || []).filter((d) => !origIso.has(d.iso))
        const addedSum = addedDays.reduce((s, d) => s + (d.price || 0), 0)
        if (addedDays.length && addedSum > 0) {
          for (const ad of addedDays) {
            items.push({
              description: `Pronájem ${motoLabel} — ${ad.dowLabel} ${fmtD(ad.iso)}`,
              qty: 1,
              unit_price: ad.price,
            })
          }
          if (addedSum !== priceDiff) {
            items.push({
              description: `Korekce ceny prodloužení`,
              qty: 1,
              unit_price: priceDiff - addedSum,
            })
          }
        } else {
          // Fallback: nemáme detailní rozpis (např. prázdné denní ceny) — jediný řádek.
          items.push({
            description: `Doplatek za prodloužení rezervace`,
            qty: 1,
            unit_price: priceDiff,
          })
        }

        // Booking-level ref in title; exposed via bookingNumber below
      } else {
        // ===== STANDARD: full invoice for the booking =====
        const startDate = fmtDate(booking.start_date); const endDate = fmtDate(booking.end_date)
        const days = Math.max(1, Math.ceil((new Date(booking.end_date).getTime() - new Date(booking.start_date).getTime()) / 86400000))
        const extrasTotal = extras.reduce((s, e) => s + Number(e.unit_price || 0) * Number(e.quantity || 1), 0)
        const baseRental = (booking.total_price || 0) - extrasTotal - (booking.delivery_fee || 0) + (booking.discount_amount || 0)
        const motoLabelStd = `${booking.motorcycles?.model || 'motorky'}${booking.motorcycles?.spz ? ' (' + booking.motorcycles.spz + ')' : ''}`
        const bd = calcPriceBreakdown(booking.motorcycles, booking.start_date, booking.end_date)

        if (!bd.uniform && bd.days.length > 1 && bd.total > 0) {
          // Hlavička + per-day rozpis (každý den ≠ stejná cena → vlastní řádek).
          // `── ... ──` značí section header — template ho vyrenderuje přes colspan.
          items.push({
            description: `── Pronájem ${motoLabelStd} — ${startDate} – ${endDate} ──`,
            qty: 1,
            unit_price: 0,
          })
          for (const ad of bd.days) {
            items.push({
              description: `${ad.dowLabel} ${fmtDate(ad.iso)}`,
              qty: 1,
              unit_price: ad.price,
            })
          }
          // Korekce: pokud Σ(rozpisu) ≠ baseRental (slevy/ruční override v bookingu), srovnáme.
          if (Math.round(bd.total) !== Math.round(baseRental)) {
            items.push({
              description: `Korekce ceny pronájmu`,
              qty: 1,
              unit_price: Math.round(baseRental - bd.total),
            })
          }
        } else {
          // Uniformní cena nebo chybějící denní rozpis → jeden řádek (qty × unit).
          items.push({
            description: `Pronájem ${motoLabelStd} — ${startDate} – ${endDate}`,
            qty: days,
            unit_price: Math.round(baseRental / days),
          })
        }

        // Itemize accessories with sizes from booking gear columns
        for (const ex of extras) {
          items.push({
            description: extraLabel(ex.name || 'Příslušenství', booking),
            qty: Number(ex.quantity || 1),
            unit_price: Number(ex.unit_price || 0),
          })
        }

        if (extra_items && Array.isArray(extra_items)) {
          extra_items.forEach((ei: any) => items.push({ description: ei.description || 'Položka', qty: ei.qty || 1, unit_price: ei.unit_price || 0 }))
        }
        if (booking.delivery_fee && Number(booking.delivery_fee) > 0) items.push({ description: 'Přistavení / odvoz motorky', qty: 1, unit_price: Number(booking.delivery_fee) })
        if (booking.sos_replacement && !extra_items) items.push({ description: 'Záloha na poškození motorky', qty: 1, unit_price: 30000 })
        if (booking.discount_amount && Number(booking.discount_amount) > 0) {
          items.push({ description: booking.discount_code ? `Sleva (kód: ${booking.discount_code})` : 'Sleva / voucher', qty: 1, unit_price: -Number(booking.discount_amount) })
        }
      }

      if (isPaymentReceipt) {
        try {
          const { data: codes } = await supabase.from('branch_door_codes').select('code_type, door_code, withheld_reason').eq('booking_id', booking_id)
          if (codes && codes.length > 0) doorCodes = codes
        } catch (e) { console.warn('Failed to fetch door codes:', e) }
      }
    }

    // ── Guard: skip ZF/DP generation for zero-amount bookings (free modifications, SOS without payment) ──
    if (booking_id && !isShop && (isProforma || isPaymentReceipt) && !isEdit) {
      const { data: bkCheck } = await supabase.from('bookings').select('total_price').eq('id', booking_id).single()
      if (bkCheck && Number(bkCheck.total_price || 0) <= 0) {
        return new Response(JSON.stringify({
          success: false, error: 'Booking has zero amount — ZF/DP not generated', skipped: true
        }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
      }
    }

    // ── Dedup: only for source='booking' (the original invoice pair). Edits always create new invoice. ──
    if (booking_id && !isShop && !isEdit) {
      const dedupTypes = isPaymentReceipt ? ['payment_receipt'] : isProforma ? ['advance', 'proforma'] : ['final', 'issued']
      const { data: sameSource } = await supabase.from('invoices').select('id, number, pdf_path')
        .eq('booking_id', booking_id).in('type', dedupTypes)
        .eq('source', 'booking').neq('status', 'cancelled').limit(1)
      if (sameSource?.length) {
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
        console.log(`Invoice ${sameSource[0].number} exists but HTML missing — regenerating`)
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
    const total = subtotal
    const issueDate = new Date().toISOString().slice(0, 10)
    // Splatnost ihned pro ZF i DP (kartová platba je okamžitá)
    const dueDate = issueDate

    const invoicePayload: any = {
      number, type: invoiceType, customer_id: customerId,
      items, subtotal, tax_amount: 0, total,
      issue_date: issueDate, due_date: dueDate, status: 'issued', variable_symbol: number,
      source: invoiceSource,
    }
    if (booking_id) invoicePayload.booking_id = booking_id
    if (order_id) invoicePayload.order_id = order_id

    const { data: invoice, error: iErr } = await supabase.from('invoices').insert(invoicePayload).select().single()
    if (iErr) return new Response(JSON.stringify({ error: iErr.message }), { status: 500 })

    const accent = isPaymentReceipt ? '#0891b2' : isProforma ? '#2563eb' : '#1a8a18'
    const baseTitle = isPaymentReceipt ? 'DAŇOVÝ DOKLAD K PŘIJATÉ PLATBĚ' : isProforma ? 'ZÁLOHOVÁ FAKTURA' : isShopFinal ? 'KONEČNÁ FAKTURA' : 'FAKTURA'
    const title = isEdit ? `${baseTitle} — ${editLabel}` : baseTitle
    const bookingNumber = booking_id ? booking_id.slice(-8).toUpperCase() : ''

    const html = generateInvoiceHtml({
      title, number, accent, issueDate, dueDate, total, company: COMPANY, customer, items,
      voucher_codes, voucherValidUntil, doorCodes, isProforma, isPaymentReceipt, isShopFinal, dpNumber, bookingNumber,
      paymentMethodLabel, cardInfo, isEdit,
    })

    const blob = new Blob([html], { type: 'text/html' })
    const path = `invoices/${invoice.id}.html`
    await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'text/html' })
    await supabase.from('invoices').update({ pdf_path: path }).eq('id', invoice.id)

    if (send_email !== false && customer.email) {
      const docLabel = isPaymentReceipt ? 'Doklad k přijaté platbě' : isProforma ? 'Zálohová faktura' : isShopFinal ? 'Konečná faktura' : 'Faktura'
      const editSuffix = isEdit ? ` (úprava rezervace #${bookingNumber})` : ''
      const emailSubject = `${docLabel} č. ${number}${editSuffix} — MOTO GO 24`
      // Tělo mailu = plná faktura v jednotném designu (1:1 s PDF/náhledem).
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from: FROM_EMAIL, to: customer.email, subject: emailSubject, html }),
      })
    }

    await supabase.from('admin_audit_log').insert({ action: 'invoice_generated', details: { invoice_id: invoice.id, number, type: invoiceType, booking_id, source: invoiceSource } })

    return new Response(JSON.stringify({ success: true, invoice_id: invoice.id, number }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 })
  }
})
