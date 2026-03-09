import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'

const COMPANY = {
  name: 'Bc. Petra Semorádová',
  address: 'Mezná 9, 393 01 Mezná',
  ico: '21874263',
  dic: null,
  vatPayer: false,
  bank: 'mBank',
  account: '670100-2225851630/6210',
  phone: '+420 774 256 271',
  email: 'info@motogo24.cz',
  web: 'www.motogo24.cz',
}

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { type, booking_id, order_id, send_email, extra_items, voucher_codes } = await req.json()
    if (!booking_id && !order_id) return new Response(JSON.stringify({ error: 'Missing booking_id or order_id' }), { status: 400 })

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const invoiceType = type || 'proforma'
    const isShop = invoiceType === 'shop_proforma' || invoiceType === 'shop_final'
    const isProforma = invoiceType === 'proforma' || invoiceType === 'shop_proforma'
    const prefix = isProforma ? 'ZF' : 'FV'
    const year = new Date().getFullYear()

    let customer: any = {}
    let items: { description: string; qty: number; unit_price: number }[] = []
    let customerId: string | null = null

    if (isShop && order_id) {
      // ===== SHOP ORDER =====
      const { data: order, error: oErr } = await supabase
        .from('shop_orders')
        .select('*, shop_order_items(*)')
        .eq('id', order_id).single()
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
      if (order.shipping_cost > 0) {
        items.push({ description: 'Doprava', qty: 1, unit_price: Number(order.shipping_cost) })
      }
      if (order.discount > 0) {
        items.push({ description: 'Sleva', qty: 1, unit_price: -Number(order.discount) })
      }
    } else {
      // ===== BOOKING =====
      const { data: booking, error: bErr } = await supabase
        .from('bookings')
        .select('*, motorcycles(model, spz), profiles(id, full_name, email, phone, street, city, zip, country, ico, dic)')
        .eq('id', booking_id).single()
      if (bErr || !booking) return new Response(JSON.stringify({ error: 'Booking not found' }), { status: 404 })

      customer = booking.profiles || {}
      customerId = customer.id || booking.user_id

      const startDate = fmtDate(booking.start_date)
      const endDate = fmtDate(booking.end_date)
      const days = Math.max(1, Math.ceil((new Date(booking.end_date).getTime() - new Date(booking.start_date).getTime()) / 86400000))
      const dailyRate = Math.round((booking.total_price || 0) / days)
      items.push({ description: `Pronájem ${booking.motorcycles?.model || 'motorky'} (${booking.motorcycles?.spz || ''}) — ${startDate} – ${endDate}`, qty: days, unit_price: dailyRate })

      if (booking.extras) {
        try {
          const extras = typeof booking.extras === 'string' ? JSON.parse(booking.extras) : booking.extras
          if (Array.isArray(extras)) {
            extras.forEach((e: any) => items.push({ description: e.name || e, qty: 1, unit_price: e.price || 0 }))
          }
        } catch {}
      }
      if (extra_items && Array.isArray(extra_items)) {
        extra_items.forEach((ei: any) => items.push({ description: ei.description || 'Položka', qty: ei.qty || 1, unit_price: ei.unit_price || 0 }))
      }
      if (booking.sos_replacement && !extra_items) {
        items.push({ description: 'Záloha na poškození motorky', qty: 1, unit_price: 30000 })
      }

      // Voucher / discount deduction
      if (booking.discount_amount && Number(booking.discount_amount) > 0) {
        const discLabel = booking.discount_code ? `Sleva (kód: ${booking.discount_code})` : 'Sleva / voucher'
        items.push({ description: discLabel, qty: 1, unit_price: -Number(booking.discount_amount) })
      }
    }

    // Generate number
    const { data: lastInv } = await supabase
      .from('invoices').select('number')
      .like('number', `${prefix}-${year}-%`)
      .order('number', { ascending: false }).limit(1)
    let seq = 1
    if (lastInv?.length) {
      const m = lastInv[0].number.match(/-(\d+)$/)
      if (m) seq = parseInt(m[1], 10) + 1
    }
    const number = `${prefix}-${year}-${String(seq).padStart(4, '0')}`

    // Neplátce DPH — žádná daň
    const subtotal = items.reduce((s, it) => s + it.unit_price * it.qty, 0)
    const taxAmount = 0
    const total = subtotal
    const issueDate = new Date().toISOString().slice(0, 10)
    const dueDate = new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10)

    // Insert invoice
    const invoicePayload: any = {
      number, type: invoiceType,
      customer_id: customerId,
      items, subtotal, tax_amount: taxAmount, total,
      issue_date: issueDate, due_date: dueDate,
      status: 'issued', variable_symbol: number,
    }
    if (booking_id) invoicePayload.booking_id = booking_id
    if (order_id) invoicePayload.order_id = order_id

    const { data: invoice, error: iErr } = await supabase
      .from('invoices').insert(invoicePayload).select().single()
    if (iErr) return new Response(JSON.stringify({ error: iErr.message }), { status: 500 })

    // Generate HTML
    const itemsHtml = items.map((it, i) => `
      <tr>
        <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px">${i + 1}</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px">${it.description}</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:center">${it.qty}</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right">${fmtPrice(it.unit_price)} Kč</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right;font-weight:600">${fmtPrice(it.unit_price * it.qty)} Kč</td>
      </tr>`).join('')

    const accent = isProforma ? '#2563eb' : '#1a8a18'
    const title = isProforma ? 'ZÁLOHOVÁ FAKTURA' : 'FAKTURA'
    const customerIcoLine = customer.ico ? `<p style="margin:2px 0;font-size:11px">IČO: ${customer.ico}${customer.dic ? ' | DIČ: ' + customer.dic : ''}</p>` : ''

    const html = `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>${title} ${number}</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',Helvetica,Arial,sans-serif;color:#1a1a1a;background:#fff">
<div style="max-width:780px;margin:0 auto;padding:32px 28px">
  <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:24px;border-bottom:3px solid ${accent};padding-bottom:16px">
    <div><h1 style="margin:0;font-size:22px;font-weight:800;color:${accent}">${title}</h1></div>
    <div style="text-align:right">
      <p style="margin:0;font-size:13px;font-weight:700">Číslo: ${number}</p>
      <p style="margin:2px 0;font-size:11px;color:#666">Vystaveno: ${fmtDate(issueDate)}</p>
      <p style="margin:2px 0;font-size:11px;color:#666">Splatnost: ${fmtDate(dueDate)}</p>
    </div>
  </div>
  <div style="display:flex;gap:24px;margin-bottom:24px">
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Dodavatel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${COMPANY.name}</p>
      <p style="margin:2px 0;font-size:11px">${COMPANY.address}</p>
      <p style="margin:2px 0;font-size:11px">IČO: ${COMPANY.ico}</p>
      <p style="margin:2px 0;font-size:11px;color:#888">Neplátce DPH</p>
    </div>
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Odběratel</p>
      <p style="margin:0;font-size:13px;font-weight:700">${customer.full_name || '—'}</p>
      <p style="margin:2px 0;font-size:11px">${[customer.street, customer.city, customer.zip, customer.country].filter(Boolean).join(', ') || ''}</p>
      ${customerIcoLine}
      <p style="margin:2px 0;font-size:11px">${customer.email || ''}</p>
    </div>
  </div>
  <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
    <thead><tr style="background:${accent}">
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:left">#</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:left">Popis</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:center">Ks</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:right">Cena/ks</th>
      <th style="padding:8px 10px;color:#fff;font-size:10px;text-align:right">Celkem</th>
    </tr></thead>
    <tbody>${itemsHtml}</tbody>
  </table>
  <div style="display:flex;justify-content:flex-end;margin-bottom:24px">
    <table style="border-collapse:collapse;min-width:280px">
      <tr style="border-top:2px solid ${accent}"><td style="padding:8px 12px;font-size:15px;font-weight:800;color:${accent}">Celkem</td><td style="padding:8px 12px;font-size:15px;font-weight:800;text-align:right;color:${accent}">${fmtPrice(total)} Kč</td></tr>
      <tr><td colspan="2" style="padding:2px 12px;font-size:10px;color:#888">Cena je konečná — dodavatel není plátce DPH</td></tr>
    </table>
  </div>
  <div style="padding:14px;background:#f8faf9;border-radius:8px;margin-bottom:16px">
    <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Platební údaje</p>
    <div style="font-size:12px"><span style="color:#888">Banka:</span> ${COMPANY.bank} | <span style="color:#888">Č. účtu:</span> ${COMPANY.account} | <span style="color:#888">VS:</span> ${number}</div>
  </div>
  ${voucher_codes && voucher_codes.length > 0 ? `
  <div style="padding:14px;background:#dcfce7;border-radius:8px;margin-bottom:16px;border:1px solid #86efac">
    <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:1px;color:#166534">Kódy dárkových poukazů</p>
    ${voucher_codes.map((c: string) => `<p style="margin:2px 0;font-size:14px;font-weight:700;font-family:monospace;color:#166534">${c}</p>`).join('')}
    <p style="margin:6px 0 0;font-size:10px;color:#4a6357">Kódy uplatníte při rezervaci motorky na motogo24.cz nebo v mobilní aplikaci MotoGo24.</p>
  </div>` : ''}
  ${isProforma ? '<div style="padding:10px 14px;background:#dbeafe;border-radius:8px;font-size:11px;color:#1e40af">Tento doklad není daňovým dokladem. Po přijetí platby Vám bude vystavena konečná faktura.</div>' : ''}
</div></body></html>`

    // Store HTML in storage
    const blob = new Blob([html], { type: 'text/html' })
    const path = `invoices/${invoice.id}.html`
    await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'text/html' })
    await supabase.from('invoices').update({ pdf_path: path }).eq('id', invoice.id)

    // Send email with invoice if requested and customer has email
    if (send_email !== false && customer.email) {
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: FROM_EMAIL, to: customer.email,
          subject: `${isProforma ? 'Zálohová faktura' : 'Faktura'} č. ${number} — MOTO GO 24`,
          html: `<div style="font-family:sans-serif;padding:24px">
            <h2 style="color:#1a2e22">Dobrý den${customer.full_name ? ` ${customer.full_name}` : ''},</h2>
            <p>V příloze zasíláme ${isProforma ? 'zálohovou fakturu' : 'fakturu'} č. <strong>${number}</strong> na částku <strong>${fmtPrice(total)} Kč</strong>.</p>
            <p>Splatnost: <strong>${fmtDate(dueDate)}</strong></p>
            <p>Variabilní symbol: <strong>${number}</strong></p>
            ${voucher_codes && voucher_codes.length > 0 ? `<div style="padding:12px;background:#dcfce7;border-radius:8px;margin:12px 0"><p style="margin:0 0 4px;font-size:11px;font-weight:700;color:#166534">Kódy dárkových poukazů:</p>${voucher_codes.map((c: string) => `<p style="margin:2px 0;font-size:16px;font-weight:700;font-family:monospace;color:#166534">${c}</p>`).join('')}</div>` : ''}
            <hr style="border:1px solid #e5e7eb">
            <p style="font-size:12px;color:#888">${COMPANY.name} | ${COMPANY.email}</p>
          </div>`,
        }),
      })
    }

    // Audit log
    await supabase.from('admin_audit_log').insert({
      action: 'invoice_generated',
      details: { invoice_id: invoice.id, number, type: invoiceType, booking_id },
    })

    return new Response(JSON.stringify({ success: true, invoice_id: invoice.id, number }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 })
  }
})
