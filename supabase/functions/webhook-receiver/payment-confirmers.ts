// ===== webhook-receiver/payment-confirmers.ts =====
// Payment confirmation functions for booking, shop, SOS + financial event ingestion

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SITE_URL = Deno.env.get('SITE_URL') || 'https://www.motogo24.cz'

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
  <div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:top;padding-right:16px">
        <div style="border:1px solid #74FB71;border-radius:6px;padding:16px;color:#ffffff;font-size:12px;line-height:1.7">
          <div style="font-size:14px;font-weight:800;color:#ffffff">Motogo24</div>
          <div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">Bc. Petra Semorádová</div>
          <div style="color:#9ca3af">Mezná 9, 393 01 Pelhřimov</div>
          <div style="color:#9ca3af">IČO: 21874263</div>
          <div><span style="color:#9ca3af">Telefon:</span> <span style="color:#74FB71">+420 774 256 271</span></div>
          <div><span style="color:#9ca3af">E-mail:</span> <span style="color:#74FB71">info@motogo24.cz</span></div>
          <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">www.motogo24.cz</span></div>
        </div>
      </td>
      <td style="vertical-align:top;width:120px;text-align:center">
        <img src="${SITE_URL}/gfx/qr-motogo24.png" alt="QR" width="110" height="110" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/>
      </td>
    </tr></table>
  </div>
</div></body></html>`
}

/** Confirm booking payment via existing RPC.
 *  `suppressMail=true` (doplatková extension platba): potvrď platbu + ulož PI,
 *  ale NIKDY neposílej booking_reserved mail — booking po předchozí vratkové
 *  úpravě je `partial_refund`, confirm_payment ho přepne zpět na `paid` s
 *  was_already_paid=false a bez tohoto flagu by zákazník dostal druhý
 *  „rezervace potvrzena" mail. Správný mail (web_/booking_modified) posílá
 *  trigger trg_send_booking_modified_email po aplikaci změny. */
export async function confirmBookingPayment(
  supabase: ReturnType<typeof createClient>,
  bookingId: string,
  transactionId: string,
  stripePaymentIntentId?: string | null,
  suppressMail = false
) {
  try {
    // ── ATOMIC dedup: confirm_payment RPC interně dělá UPDATE WHERE payment_status != 'paid'
    //    RETURNING — jen JEDNA paralelní Stripe webhook session získá was_already_paid=false,
    //    druhý event (checkout.session.completed vs payment_intent.succeeded přicházejí <1 s
    //    od sebe) dostane was_already_paid=true a okamžitě skipne mail/dokumenty/door codes.
    //    Stará SELECT-then-RPC dedup byla race-prone (oba SELECTy viděly 'unpaid' před UPDATE).
    const { data, error } = await supabase.rpc('confirm_payment', {
      p_booking_id: bookingId,
      p_method: 'card',
    })

    const wasAlreadyPaid = !!(data as Record<string, unknown> | null)?.was_already_paid
    if (wasAlreadyPaid) {
      console.log(`[confirmBookingPayment] Booking ${bookingId} already paid — duplicate Stripe event, skipping mail/docs`)
      if (stripePaymentIntentId) {
        try { await supabase.from('bookings').update({ stripe_payment_intent_id: stripePaymentIntentId, stripe_session_id: transactionId }).eq('id', bookingId).is('stripe_payment_intent_id', null) } catch {}
      }
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'confirm_booking_payment_duplicate_skip',
          component: 'stripe', status: 'ok',
          request_data: { booking_id: bookingId, transaction_id: transactionId },
        })
      } catch { /* ignore */ }
      return
    }

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

    // Doplatková extension platba → mail booking_reserved se neposílá (viz docblock).
    if (suppressMail) {
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'confirm_booking_payment_extension_no_mail',
          component: 'stripe', status: 'ok',
          request_data: { booking_id: bookingId, transaction_id: transactionId },
        })
      } catch { /* ignore */ }
      return
    }

    // Auto-generate documents + send confirmation email with attachments (best-effort)
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

      // Přílohy mailu (ZF, DP, smlouva, VOP) — řídí Velín DB šablona `email_templates.attachments`
      // (etalon). send-booking-email si je vyzvedne / vygeneruje sám přes autoGenerateAttachments
      // synth typy. webhook-receiver už nepředgeneruje dokumenty, aby nevznikla duplicita
      // s odlišnými filename a aby admin v UI viděl JEDINOU pravdu o tom, co se posílá.
      const { data: booking } = await supabase.from('bookings')
        .select('booking_source, user_id, moto_id, start_date, end_date, total_price, motorcycles!moto_id(model, manual_url), profiles(full_name, email)')
        .eq('id', bookingId).single()

      const profile = (booking?.profiles ?? null) as { full_name?: string; email?: string } | null
      if (profile?.email) {
        const source = booking.booking_source || 'app'
        const moto = booking.motorcycles as { model?: string; manual_url?: string } | null

        // NOVÝ FLOW (WEB, platba PŘED doklady): rozhodni podle stavu dokladů při platbě.
        //  • Doklady OK (přihlášený zákazník s ověřenými doklady) → pošli KOMPLETNÍ
        //    `web_booking_reserved` (ZF+DP+VOP+Smlouva+kódy) jako dřív.
        //  • Doklady chybí (nový zákazník) → jen potvrzení platby `invoice_payment_receipt`
        //    (ZF+DP); Smlouva+VOP+kódy dorazí po naskenování dokladů (reserved cron).
        // APP: vždy `booking_reserved` (beze změny). Bez tohoto rozhodnutí by se smlouva
        // buď generovala s prázdnými čísly (nový), nebo by přihlášený nedostal komplet.
        let mailType = 'booking_reserved'
        if (source === 'web') {
          let docsOk = false
          try {
            const { data: ds } = await supabase.rpc('check_booking_docs_status', {
              p_user_id: booking.user_id,
              p_end_date: String(booking.end_date || '').slice(0, 10),
              p_moto_id: booking.moto_id,
            })
            docsOk = (ds === null || ds === undefined)
          } catch { docsOk = false }
          mailType = docsOk ? 'booking_reserved' : 'invoice_payment_receipt'
        }
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/send-booking-email`, {
            method: 'POST', headers,
            body: JSON.stringify({
              type: mailType,
              booking_id: bookingId,
              customer_email: profile.email,
              customer_name: profile.full_name || '',
              motorcycle: moto?.model || '',
              start_date: booking.start_date,
              end_date: booking.end_date,
              total_price: booking.total_price,
              source: source,
              manual_url: moto?.manual_url || '',
            }),
          })
          try {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver',
              action: resp.ok ? 'payment_receipt_mail_sent' : 'payment_receipt_mail_http_error',
              component: 'send-booking-email',
              status: resp.ok ? 'ok' : 'error',
              request_data: { booking_id: bookingId, source, http_status: resp.status },
              error_message: resp.ok ? null : (await resp.text().catch(() => `HTTP ${resp.status}`)),
            })
          } catch { /* ignore */ }
        } catch (e) {
          try {
            await supabase.from('debug_log').insert({
              source: 'webhook-receiver', action: 'payment_receipt_mail_failed',
              component: 'send-booking-email', status: 'error',
              request_data: { booking_id: bookingId },
              error_message: (e as Error).message,
            })
          } catch { /* ignore */ }
        }
      } else {
        try {
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'payment_receipt_mail_no_email',
            component: 'send-booking-email', status: 'warning',
            request_data: { booking_id: bookingId },
          })
        } catch { /* ignore */ }
      }
    } catch (e) {
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'payment_receipt_mail_outer_exception',
          component: 'send-booking-email', status: 'error',
          request_data: { booking_id: bookingId },
          error_message: (e as Error).message,
        })
      } catch { /* ignore */ }
    }
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
    // ATOMIC dedup: UPDATE WHERE payment_status != 'paid' RETURNING — jen JEDNA Stripe
    // webhook session projde, druhý paralelní event získá prázdný result a skipne.
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
    const { data: updatedRows, error } = await supabase.from('bookings')
      .update(updateData)
      .eq('id', bookingId)
      .neq('payment_status', 'paid')
      .select('id')

    const wasAlreadyPaid = !error && Array.isArray(updatedRows) && updatedRows.length === 0
    if (wasAlreadyPaid) {
      console.log(`[confirmSosPayment] Booking ${bookingId} already paid — duplicate Stripe event, skipping mail/docs`)
      if (stripePaymentIntentId) {
        try { await supabase.from('bookings').update({ stripe_payment_intent_id: stripePaymentIntentId, stripe_session_id: transactionId }).eq('id', bookingId).is('stripe_payment_intent_id', null) } catch {}
      }
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'confirm_sos_payment_duplicate_skip',
          component: 'stripe', status: 'ok',
          request_data: { booking_id: bookingId, incident_id: incidentId, transaction_id: transactionId },
        })
      } catch { /* ignore */ }
      return
    }

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

    // SOS booking confirmation email — Velín DB šablona řídí přílohy přes attachments[].
    // send-booking-email si je vyzvedne / vygeneruje sám.
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

      const { data: booking } = await supabase.from('bookings')
        .select('booking_source, start_date, end_date, total_price, motorcycles!moto_id(model), profiles(full_name, email)')
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
            }),
          })
        } catch { /* ignore */ }
      }
    } catch (e) { console.warn('[confirmSosPayment] mail send failed:', e) }
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
    // RPC vrací { success, was_already_paid, ... }. ATOMIC dedup:
    // UPDATE WHERE payment_status != 'paid' RETURNING — jen JEDNA Stripe webhook
    // session získá flag "was_already_paid=false". Druhý event (paralelní) dostane
    // was_already_paid=true a okamžitě skipne — žádné race condition na mailu.
    const { data, error } = await supabase.rpc('confirm_shop_payment', {
      p_order_id: orderId,
      p_method: 'card',
    })

    const wasAlreadyPaid = !!(data as Record<string, unknown> | null)?.was_already_paid
    if (wasAlreadyPaid) {
      console.log(`[confirmShopPayment] Order ${orderId} already paid — duplicate Stripe event, skipping mail/docs`)
      if (stripePaymentIntentId) {
        try { await supabase.from('shop_orders').update({ stripe_payment_intent_id: stripePaymentIntentId, stripe_session_id: transactionId }).eq('id', orderId).is('stripe_payment_intent_id', null) } catch {}
      }
      try {
        await supabase.from('debug_log').insert({
          source: 'webhook-receiver', action: 'confirm_shop_payment_duplicate_skip',
          component: 'stripe', status: 'ok',
          request_data: { order_id: orderId, transaction_id: transactionId },
        })
      } catch { /* ignore */ }
      return
    }

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
      // Direct UPDATE — trigger auto_process_voucher_order should still fire BEFORE UPDATE
      // because OLD.payment_status='pending' a NEW.payment_status='paid'.
      const { error: directErr } = await supabase.from('shop_orders')
        .update({ payment_status: 'paid', payment_method: 'card', confirmed_at: new Date().toISOString() })
        .eq('id', orderId)
      if (directErr) {
        console.error('[confirmShopPayment] direct update fallback failed:', directErr.message)
        try {
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'confirm_shop_payment_fallback_failed',
            component: 'stripe', status: 'error',
            request_data: { order_id: orderId, transaction_id: transactionId },
            error_message: directErr.message,
          })
        } catch { /* ignore */ }
      }
    }

    // Verify trigger ran — if vouchers should exist but don't, kick the trigger manually
    try {
      const { data: post } = await supabase.from('shop_orders')
        .select('id, status, payment_status, customer_email, customer_name, order_number')
        .eq('id', orderId).single()
      const { data: items } = await supabase.from('shop_order_items')
        .select('product_name').eq('order_id', orderId)
      const hasVoucherItem = (items || []).some((it: { product_name?: string }) =>
        /voucher|poukaz/i.test(String(it.product_name || ''))
      )
      const { data: existingVouchers } = await supabase.from('vouchers')
        .select('id').eq('order_id', orderId).limit(1)
      if (hasVoucherItem && (!existingVouchers || existingVouchers.length === 0) && post?.payment_status === 'paid') {
        // Trigger se z nějakého důvodu nespustil. Spustíme regen RPC manuálně.
        await supabase.rpc('regen_voucher_for_order', { p_order_id: orderId })
        try {
          await supabase.from('debug_log').insert({
            source: 'webhook-receiver', action: 'regen_voucher_for_order_called',
            component: 'stripe', status: 'ok',
            request_data: { order_id: orderId, post_status: post?.status },
          })
        } catch { /* ignore */ }
      }
    } catch (e) {
      console.warn('[confirmShopPayment] post-confirm voucher verify failed:', e)
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

    // --- Send post-payment email ---
    // Pro voucher objednávky pošleme JEN voucher_purchased mail (s DP + HTML voucher přílohami,
    // které si send-booking-email vygeneruje sám přes autoGenerateAttachments).
    // shop_order_confirmed mail pro jiné e-shop produkty řeší DB trigger trg_shop_order_confirmed_email
    // (skipuje voucher objednávky), tady ho neduplikujeme.
    try {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
      const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}`, 'apikey': SERVICE_KEY }

      const { data: order } = await supabase.from('shop_orders')
        .select('customer_name, customer_email, order_number, status, total, notes')
        .eq('id', orderId).single()

      const { data: vouchers } = await supabase.from('vouchers')
        .select('code, amount, valid_until')
        .eq('order_id', orderId)

      // FV (shop_final) pro elektronický voucher se vygeneruje přes generate-invoice
      // ale email-bound je pro něj voucher_purchased (ne shop_order_shipped) — FV slouží
      // jen jako účetní doklad ve Velínu.
      if (order?.status === 'delivered') {
        try {
          await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
            method: 'POST', headers,
            body: JSON.stringify({ type: 'shop_final', order_id: orderId, send_email: false }),
          })
        } catch { /* ignore */ }
      }

      // Voucher objednávka → voucher_purchased mail (bez ručního skládání příloh — edge fn si je vygeneruje).
      // Dedup je řešen atomic přes was_already_paid flag z RPC výše — sem dorazíme jen
      // pro PRVNÍ webhook event, druhý je skipnut na začátku confirmShopPayment.
      if (order?.customer_email && vouchers && vouchers.length > 0) {
        const orderNum = order.order_number || orderId.slice(-8).toUpperCase()
        const firstVoucher = vouchers[0] as { code: string; amount: number; valid_until: string }
        const allCodes = vouchers
          .map((v: { code: string; amount: number }) => `${v.code} (${v.amount} Kč)`)
          .join(', ')
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
              order_id: orderId,
              source: 'web',
            }),
          })
        } catch (e) { console.warn('[confirmShopPayment] voucher email failed:', e) }
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
    // stripe_refund_id má přednost: na jednom charge může být VÍC vratek
    // (částečná úprava + pozdější storno) — dedup přes stripe_charge_id druhou
    // a další vratku tiše zahodil (incident #DDC5A69D: vratka 1 143 Kč chyběla
    // ve financial_events). Refund eventy nesou stripe_refund_id od 2026-08-12.
    const stripeId = eventData.metadata.stripe_refund_id
      || eventData.metadata.stripe_payment_intent_id
      || eventData.metadata.stripe_charge_id
      || eventData.metadata.stripe_payout_id

    if (stripeId) {
      const idempotencyKey = eventData.metadata.stripe_refund_id
        ? 'stripe_refund_id'
        : eventData.metadata.stripe_payment_intent_id
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
