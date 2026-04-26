// ===== webhook-receiver/payment-confirmers.ts =====
// Payment confirmation functions for booking, shop, SOS + financial event ingestion

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

/** Download file from Supabase Storage and return as base64 */
async function downloadAsBase64(supabase: ReturnType<typeof createClient>, path: string): Promise<string | null> {
  try {
    const { data } = await supabase.storage.from('documents').download(path)
    if (!data) return null
    const bytes = new Uint8Array(await data.arrayBuffer())
    return btoa(Array.from(bytes, (b: number) => String.fromCharCode(b)).join(''))
  } catch { return null }
}

/** Generate a styled HTML gift voucher document */
function generateVoucherHtml(code: string, amount: number, validUntil: string, buyerName: string): string {
  const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
  const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Dárkový poukaz ${code}</title></head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#d9dee2;color:#0f1a14">
<div style="max-width:780px;margin:0 auto;background:#ffffff">
  <div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:middle;padding-right:14px;width:52px"><img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
      <td style="vertical-align:middle">
        <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
        <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">PŮJČOVNA MOTOREK</div>
      </td>
    </tr></table>
  </div>
  <div style="padding:40px;text-align:center">
    <h2 style="margin:0 0 8px;font-size:20px;font-weight:800;color:#0a1f15;text-transform:uppercase;letter-spacing:2px">Dárkový poukaz</h2>
    <p style="margin:0 0 24px;font-size:13px;color:#6b7280">na pronájem motocyklu dle vlastního výběru</p>
    <div style="background:#dcfce7;border:2px solid #86efac;border-radius:16px;padding:24px;margin:0 0 24px">
      <p style="margin:0 0 4px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:2px;color:#166534">Hodnota poukazu</p>
      <p style="margin:0;font-size:36px;font-weight:900;color:#166534">${fmtPrice(amount)} Kč</p>
    </div>
    <div style="background:#f8faf9;border:2px dashed #74FB71;border-radius:12px;padding:20px;margin:0 0 24px">
      <p style="margin:0 0 6px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:2px;color:#6b7280">Kód poukazu</p>
      <p style="margin:0;font-size:28px;font-weight:900;font-family:'Courier New',monospace;letter-spacing:4px;color:#0a1f15">${code}</p>
    </div>
    <table style="width:100%;border-collapse:collapse;font-size:12px;color:#374151;margin-bottom:20px">
      <tr><td style="padding:6px 0;text-align:left;font-weight:600">Vystaveno pro:</td><td style="padding:6px 0;text-align:right">${buyerName || '—'}</td></tr>
      <tr><td style="padding:6px 0;text-align:left;font-weight:600">Platnost do:</td><td style="padding:6px 0;text-align:right;font-weight:700;color:#166534">${fmtDate(validUntil)}</td></tr>
    </table>
    <div style="background:#f8faf9;border-radius:8px;padding:14px;text-align:left;font-size:11px;color:#374151;line-height:1.6">
      <p style="margin:0 0 6px;font-weight:700;text-transform:uppercase;font-size:10px;color:#6b7280;letter-spacing:1px">Jak uplatnit poukaz</p>
      <p style="margin:0">Rezervujte si termín na <a href="https://www.motogo24.cz" style="color:#2563eb">www.motogo24.cz</a> a při rezervaci zadejte kód <strong>${code}</strong> do kolonky Slevový kód. Hodnota poukazu se automaticky odečte z ceny.</p>
    </div>
  </div>
  <div style="background:#0a1f15;padding:14px 32px;color:#ffffff;font-size:11px;line-height:1.6">
    <strong style="color:#ffffff">Bc. Petra Semorádová</strong>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>Mezná 9, 393 01 Mezná
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>IČO: 21874263
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">+420 774 256 271</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">info@motogo24.cz</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">www.motogo24.cz</span>
  </div>
</div></body></html>`
}

/** Confirm booking payment via existing RPC */
export async function confirmBookingPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    // ── Dedup: skip if already processed (Stripe sends both checkout.session.completed + payment_intent.succeeded) ──
    const { data: existingBooking } = await supabase.from('bookings')
      .select('payment_status').eq('id', bookingId).single()
    if (existingBooking?.payment_status === 'paid') {
      console.log(`[confirmBookingPayment] Booking ${bookingId} already paid — skipping duplicate`)
      // Still save Stripe IDs if missing
      if (stripePaymentIntentId) {
        try { await supabase.from('bookings').update({ stripe_payment_intent_id: stripePaymentIntentId, stripe_session_id: transactionId }).eq('id', bookingId).is('stripe_payment_intent_id', null) } catch {}
      }
      return
    }

    const { data, error } = await supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: 'card',
    })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_booking_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { booking_id: bookingId, transaction_id: transactionId },
        response_data: data,
        error_message: error?.message || null,
      })
    } catch (e) { /* ignore */ }

    if (error) {
      console.error('confirm_payment RPC failed:', error.message)
      const { data: bk } = await supabase.from('bookings')
        .select('start_date')
        .eq('id', bookingId)
        .single()
      const today = new Date().toISOString().slice(0, 10)
      const startDate = bk?.start_date || today
      const isToday = startDate <= today
      await supabase.from('bookings')
        .update({
          payment_status: 'paid',
          payment_method: 'card',
          status: isToday ? 'active' : 'reserved',
          ...(isToday
            ? { picked_up_at: new Date().toISOString() }
            : { confirmed_at: new Date().toISOString() }),
        })
        .eq('id', bookingId)
    }

    // Save Stripe IDs for future refunds
    if (stripePaymentIntentId) {
      try {
        await supabase.from('bookings')
          .update({
            stripe_payment_intent_id: stripePaymentIntentId,
            stripe_session_id: transactionId,
          })
          .eq('id', bookingId)
      } catch (e) { /* ignore */ }
    }

    // Auto-generate documents + send confirmation email with attachments (best-effort)
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

      // Collect document paths for email attachments
      const attachmentFiles: { path: string; filename: string }[] = []

      // 1. Generate ZF (zálohová faktura) — send_email:false, bude jako příloha
      const { data: existingZf } = await supabase.from('invoices')
        .select('id').eq('booking_id', bookingId)
        .in('type', ['advance', 'proforma']).limit(1)
      if (!existingZf?.length) {
        try {
          const zfRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
            method: 'POST', headers,
            body: JSON.stringify({ type: 'advance', booking_id: bookingId, send_email: false }),
          })
          const zfData = await zfRes.json().catch(() => ({}))
          if (zfData.success && zfData.invoice_id) {
            attachmentFiles.push({ path: `invoices/${zfData.invoice_id}.html`, filename: `Zalohova-faktura-${zfData.number || 'ZF'}.html` })
          }
        } catch (e) { /* ignore */ }
      }

      // 2. Generate DP (doklad platby) — send_email:false, bude jako příloha
      try {
        const dpRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id: bookingId, send_email: false }),
        })
        const dpData = await dpRes.json().catch(() => ({}))
        if (dpData.success && dpData.invoice_id) {
          attachmentFiles.push({ path: `invoices/${dpData.invoice_id}.html`, filename: `Doklad-platby-${dpData.number || 'DP'}.html` })
        }
      } catch (e) { /* ignore */ }

      // 3. Generate smlouva (nájemní smlouva)
      try {
        const contractRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
          method: 'POST', headers,
          body: JSON.stringify({ template_slug: 'rental_contract', booking_id: bookingId }),
        })
        const contractData = await contractRes.json().catch(() => ({}))
        if (contractData.success && contractData.path) {
          attachmentFiles.push({ path: contractData.path, filename: `Najemni-smlouva-${bookingId.slice(-8).toUpperCase()}.html` })
        }
      } catch (e) { /* ignore */ }

      // 4. Generate VOP
      try {
        const vopRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
          method: 'POST', headers,
          body: JSON.stringify({ template_slug: 'vop', booking_id: bookingId }),
        })
        const vopData = await vopRes.json().catch(() => ({}))
        if (vopData.success && vopData.path) {
          attachmentFiles.push({ path: vopData.path, filename: `VOP-${bookingId.slice(-8).toUpperCase()}.html` })
        }
      } catch (e) { /* ignore */ }

      // 5. Download all generated documents from storage and encode as base64
      const attachments: { content: string; filename: string }[] = []
      for (const att of attachmentFiles) {
        try {
          const { data: blob } = await supabase.storage.from('documents').download(att.path)
          if (blob) {
            const bytes = new Uint8Array(await blob.arrayBuffer())
            const base64 = Array.from(bytes, (b: number) => String.fromCharCode(b)).join('')
            attachments.push({ content: btoa(base64), filename: att.filename })
          }
        } catch (e) { /* ignore individual file download failures */ }
      }

      // 6. Send booking confirmation email with all documents attached
      const { data: booking } = await supabase.from('bookings')
        .select('booking_source, user_id, moto_id, start_date, end_date, total_price, motorcycles(model, manual_url), profiles(full_name, email)')
        .eq('id', bookingId).single()

      if (booking?.profiles?.email) {
        const source = booking.booking_source || 'app'
        const moto = booking.motorcycles as { model?: string; manual_url?: string } | null
        const profile = booking.profiles as { full_name?: string; email?: string }

        try {
          await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
            method: 'POST', headers,
            body: JSON.stringify({
              type: 'booking_reserved',
              booking_id: bookingId,
              customer_email: profile.email,
              customer_name: profile.full_name || '',
              motorcycle: moto?.model || '',
              start_date: booking.start_date,
              end_date: booking.end_date,
              total_price: booking.total_price,
              source: source,
              manual_url: moto?.manual_url || '',
              attachments,
            }),
          })
        } catch (e) { /* ignore */ }
      }
    } catch (e) { /* doc gen is best-effort */ }
  } catch (err) {
    console.error('confirmBookingPayment error:', err)
  }
}

/** Confirm SOS replacement booking payment */
export async function confirmSosPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  incidentId: string | undefined,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    // Dedup: skip if already paid
    const { data: existingSos } = await supabase.from('bookings')
      .select('payment_status').eq('id', bookingId).single()
    if (existingSos?.payment_status === 'paid') {
      console.log(`[confirmSosPayment] Booking ${bookingId} already paid — skipping duplicate`)
      if (stripePaymentIntentId) {
        try { await supabase.from('bookings').update({ stripe_payment_intent_id: stripePaymentIntentId, stripe_session_id: transactionId }).eq('id', bookingId).is('stripe_payment_intent_id', null) } catch {}
      }
      return
    }

    const updateData: Record<string, any> = {
      payment_status: 'paid',
      payment_method: 'card',
      status: 'active',
      confirmed_at: new Date().toISOString(),
      picked_up_at: new Date().toISOString(),
    }
    if (stripePaymentIntentId) {
      updateData.stripe_payment_intent_id = stripePaymentIntentId
      updateData.stripe_session_id = transactionId
    }
    const { error } = await supabase.from('bookings')
      .update(updateData)
      .eq('id', bookingId)

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_sos_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { booking_id: bookingId, incident_id: incidentId, transaction_id: transactionId },
        error_message: error?.message || null,
      })
    } catch (e) { /* ignore */ }

    if (error) {
      console.error('SOS booking update failed:', error.message)
    }

    // Auto-generate documents + send SOS confirmation email
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }
      const sosAttachments: { content: string; filename: string }[] = []

      // 1. Generate ZF
      try {
        const zfRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'advance', booking_id: bookingId, send_email: false }),
        })
        const zfData = await zfRes.json().catch(() => ({}))
        if (zfData.success && zfData.invoice_id) {
          const b64 = await downloadAsBase64(supabase, `invoices/${zfData.invoice_id}.html`)
          if (b64) sosAttachments.push({ content: b64, filename: `Zalohova-faktura-${zfData.number || 'ZF'}.html` })
        }
      } catch { /* ignore */ }

      // 2. Generate DP
      try {
        const dpRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id: bookingId, send_email: false }),
        })
        const dpData = await dpRes.json().catch(() => ({}))
        if (dpData.success && dpData.invoice_id) {
          const b64 = await downloadAsBase64(supabase, `invoices/${dpData.invoice_id}.html`)
          if (b64) sosAttachments.push({ content: b64, filename: `Doklad-platby-${dpData.number || 'DP'}.html` })
        }
      } catch { /* ignore */ }

      // 3. Send SOS booking confirmation email
      const { data: booking } = await supabase.from('bookings')
        .select('booking_source, start_date, end_date, total_price, motorcycles(model), profiles(full_name, email)')
        .eq('id', bookingId).single()

      if (booking?.profiles?.email) {
        const profile = booking.profiles as { full_name?: string; email?: string }
        const moto = booking.motorcycles as { model?: string } | null
        try {
          await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
            method: 'POST', headers,
            body: JSON.stringify({
              type: 'booking_reserved',
              booking_id: bookingId,
              customer_email: profile.email,
              customer_name: profile.full_name || '',
              motorcycle: moto?.model || '',
              start_date: booking.start_date,
              end_date: booking.end_date,
              total_price: booking.total_price,
              source: booking.booking_source || 'app',
              attachments: sosAttachments,
            }),
          })
        } catch { /* ignore */ }
      }
    } catch (e) { console.warn('[confirmSosPayment] doc gen failed:', e) }
  } catch (err) {
    console.error('confirmSosPayment error:', err)
  }
}

/** Confirm shop payment via existing RPC */
export async function confirmShopPayment(
  supabase: ReturnType<typeof createClient>,
  orderId: string,
  transactionId: string,
  stripePaymentIntentId?: string | null
) {
  try {
    // Dedup: skip if already paid
    const { data: existingOrder } = await supabase.from('shop_orders')
      .select('payment_status').eq('id', orderId).single()
    if (existingOrder?.payment_status === 'paid') {
      console.log(`[confirmShopPayment] Order ${orderId} already paid — skipping duplicate`)
      if (stripePaymentIntentId) {
        try { await supabase.from('shop_orders').update({ stripe_payment_intent_id: stripePaymentIntentId, stripe_session_id: transactionId }).eq('id', orderId).is('stripe_payment_intent_id', null) } catch {}
      }
      return
    }

    const { data, error } = await supabase.rpc('confirm_shop_payment', {
      p_order_id: orderId,
      p_method: 'card',
    })

    try {
      await supabase.from('debug_log').insert({
        source: 'webhook-receiver',
        action: 'confirm_shop_payment',
        component: 'stripe',
        status: error ? 'error' : 'ok',
        request_data: { order_id: orderId, transaction_id: transactionId },
        response_data: data,
        error_message: error?.message || null,
      })
    } catch (e) { /* ignore */ }

    if (error) {
      console.error('confirm_shop_payment RPC failed:', error.message)
      await supabase.from('shop_orders')
        .update({ payment_status: 'paid', payment_method: 'card' })
        .eq('id', orderId)
    }

    if (stripePaymentIntentId) {
      try {
        await supabase.from('shop_orders')
          .update({
            stripe_payment_intent_id: stripePaymentIntentId,
            stripe_session_id: transactionId,
          })
          .eq('id', orderId)
      } catch (e) { /* ignore */ }
    }

    // --- Auto-generate ALL documents + send complete email after shop payment ---
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }
      const shopAttachments: { content: string; filename: string }[] = []

      // 1. Fetch existing ZF (generated by process-payment before Stripe checkout)
      try {
        const { data: zfInv } = await supabase.from('invoices')
          .select('id, number, pdf_path')
          .eq('order_id', orderId)
          .in('type', ['advance', 'proforma', 'shop_proforma'])
          .neq('status', 'cancelled')
          .order('created_at', { ascending: false }).limit(1)
        if (zfInv?.length && zfInv[0].pdf_path) {
          const b64 = await downloadAsBase64(supabase, zfInv[0].pdf_path)
          if (b64) shopAttachments.push({ content: b64, filename: `Zalohova-faktura-${zfInv[0].number || 'ZF'}.html` })
        }
      } catch { /* ignore */ }

      // 2. Generate DP (payment receipt) — send_email:false
      try {
        const dpRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', order_id: orderId, send_email: false }),
        })
        const dpData = await dpRes.json().catch(() => ({}))
        if (dpData.success && dpData.invoice_id) {
          const b64 = await downloadAsBase64(supabase, `invoices/${dpData.invoice_id}.html`)
          if (b64) shopAttachments.push({ content: b64, filename: `Doklad-platby-${dpData.number || 'DP'}.html` })
        }
      } catch (e) { console.warn('[confirmShopPayment] DP generation failed:', e) }

      // 3. Fetch order + generated voucher codes (created by auto_process_voucher_order trigger)
      const { data: order } = await supabase.from('shop_orders')
        .select('customer_name, customer_email, customer_phone, order_number, status, total_amount, notes')
        .eq('id', orderId).single()

      const { data: vouchers } = await supabase.from('vouchers')
        .select('code, amount, valid_until')
        .eq('order_id', orderId)

      // 4. Generate voucher HTML documents (gift card images)
      if (vouchers && vouchers.length > 0) {
        for (const v of vouchers) {
          try {
            const voucherHtml = generateVoucherHtml(
              v.code, v.amount, v.valid_until, order?.customer_name || ''
            )
            const b64 = btoa(unescape(encodeURIComponent(voucherHtml)))
            shopAttachments.push({ content: b64, filename: `Darkovy-poukaz-${v.code}.html` })
          } catch { /* ignore */ }
        }
      }

      // 5. For electronic vouchers (status='delivered'): fetch FV (generated by trigger)
      const isElectronic = order?.status === 'delivered'
      if (isElectronic) {
        // Generate FV via edge function (trigger only inserts DB row, not HTML)
        try {
          const fvRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
            method: 'POST', headers,
            body: JSON.stringify({ type: 'shop_final', order_id: orderId, send_email: false }),
          })
          const fvData = await fvRes.json().catch(() => ({}))
          if (fvData.success && fvData.invoice_id) {
            const b64 = await downloadAsBase64(supabase, `invoices/${fvData.invoice_id}.html`)
            if (b64) shopAttachments.push({ content: b64, filename: `Konecna-faktura-${fvData.number || 'FV'}.html` })
          }
        } catch { /* ignore */ }
      }

      // 6. Send email with ALL attachments
      if (order?.customer_email) {
        const orderNum = order.order_number || orderId.slice(-8).toUpperCase()

        if (vouchers && vouchers.length > 0) {
          // Voucher order — send voucher_purchased email
          const firstVoucher = vouchers[0]
          const allCodes = vouchers.map((v: { code: string; amount: number }) => `${v.code} (${v.amount} Kč)`).join(', ')
          try {
            await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
              method: 'POST', headers,
              body: JSON.stringify({
                type: 'voucher_purchased',
                customer_email: order.customer_email,
                customer_name: order.customer_name || '',
                voucher_code: allCodes,
                voucher_value: String(firstVoucher.amount),
                voucher_expiry: firstVoucher.valid_until,
                order_number: orderNum,
                source: 'web',
                attachments: shopAttachments,
              }),
            })
          } catch (e) { console.warn('[confirmShopPayment] voucher email failed:', e) }
        } else {
          // Non-voucher shop order — send order confirmation with ZF+DP
          try {
            await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
              method: 'POST', headers,
              body: JSON.stringify({
                type: 'voucher_purchased',
                customer_email: order.customer_email,
                customer_name: order.customer_name || '',
                order_number: orderNum,
                total_price: order.total_amount,
                source: 'web',
                attachments: shopAttachments,
              }),
            })
          } catch (e) { console.warn('[confirmShopPayment] shop email failed:', e) }
        }
      }

    } catch (e) { console.warn('[confirmShopPayment] post-payment processing failed:', e) }
  } catch (err) {
    console.error('confirmShopPayment error:', err)
  }
}

/** Idempotent insert into financial_events */
export async function ingestFinancialEvent(
  supabase: ReturnType<typeof createClient>,
  eventData: {
    event_type: string
    source: string
    amount_czk: number
    vat_rate: number
    duzp: string
    linked_entity_type: string | null
    linked_entity_id: string | null
    confidence_score: number
    status: string
    metadata: Record<string, any>
  }
) {
  try {
    const stripeId = eventData.metadata.stripe_payment_intent_id
      || eventData.metadata.stripe_charge_id
      || eventData.metadata.stripe_payout_id

    if (stripeId) {
      const idempotencyKey = eventData.metadata.stripe_payment_intent_id
        ? 'stripe_payment_intent_id'
        : eventData.metadata.stripe_charge_id
          ? 'stripe_charge_id'
          : 'stripe_payout_id'

      const { data: existing } = await supabase
        .from('financial_events')
        .select('id')
        .eq(`metadata->>${idempotencyKey}`, stripeId)
        .maybeSingle()

      if (existing) {
        console.log(`Financial event already exists for ${idempotencyKey}=${stripeId}, skipping`)
        return
      }
    }

    const { error } = await supabase.from('financial_events').insert(eventData)

    if (error) {
      console.error('Failed to insert financial_event:', error.message)
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver',
          action: 'financial_event_insert_failed',
          component: 'stripe',
          status: 'error',
          request_data: eventData,
          error_message: error.message,
        })
      } catch (e) { /* ignore */ }
    }
  } catch (err) {
    console.error('ingestFinancialEvent error:', err)
  }
}
