import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

/** Send email with exponential backoff retry (max 3 attempts) */
async function sendWithRetry(emailData: Record<string, unknown>, maxRetries = 3): Promise<Record<string, unknown>> {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + RESEND_API_KEY,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(emailData),
      })
      if (res.ok) return await res.json()
      if (attempt === maxRetries) {
        const errBody = await res.text()
        throw new Error('Email failed after ' + maxRetries + ' attempts: ' + res.status + ' ' + errBody)
      }
    } catch (e) {
      if (attempt === maxRetries) throw e
      await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt))) // exponential backoff
    }
  }
  throw new Error('Email retry exhausted')
}

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type EmailType = 'booking_reserved' | 'booking_completed' | 'booking_modified' | 'voucher_purchased'

const SUBJECTS: Record<EmailType, (vars: Record<string, string>) => string> = {
  booking_reserved: (v) => `Potvrzení rezervace č. ${v.booking_number} — MOTO GO 24`,
  booking_completed: (v) => `Vaše jízda č. ${v.booking_number} byla dokončena — MOTO GO 24`,
  booking_modified: (v) => `Změna rezervace č. ${v.booking_number} — MOTO GO 24`,
  voucher_purchased: (v) => `Váš poukaz ${v.voucher_code || ''} — MOTO GO 24`,
}

function buildHtml(type: EmailType, vars: Record<string, string>): string {
  const header = `<div style="background:#1a2e22;padding:28px 32px;text-align:center"><h1 style="margin:0;color:#74FB71;font-size:22px;font-weight:900">MOTO GO 24</h1></div>`
  const footer = `<div style="background:#f9fafb;padding:16px 32px;text-align:center;border-top:1px solid #e5e7eb"><p style="color:#9ca3af;font-size:11px;margin:0">MOTO GO 24 — Pronájem motorek po celé ČR</p></div>`

  const bookingTable = `
    <div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0">
      <table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">
        <tr><td style="padding:4px 0;font-weight:700">Motorka:</td><td>${vars.motorcycle}</td></tr>
        <tr><td style="padding:4px 0;font-weight:700">Termín:</td><td>${vars.start_date} — ${vars.end_date}</td></tr>
        <tr><td style="padding:4px 0;font-weight:700">Celkem:</td><td style="font-weight:700;color:#1a8a18">${vars.total_price} Kč</td></tr>
      </table>
    </div>`

  let body = ''
  if (type === 'booking_reserved') {
    body = `
      <h2 style="color:#1a8a18;font-size:18px;margin-top:0">Vaše rezervace je potvrzena!</h2>
      <p style="color:#374151;line-height:1.6">Dobrý den${vars.customer_name ? ` ${vars.customer_name}` : ''},</p>
      <p style="color:#374151;line-height:1.6">Vaše rezervace č. <strong>${vars.booking_number}</strong> byla úspěšně potvrzena.</p>
      ${bookingTable}
      <p style="color:#374151;line-height:1.6">Motorku si vyzvednete v den začátku rezervace. Nezapomeňte s sebou přinést platný řidičský průkaz.</p>
      <div style="text-align:center;margin:28px 0">
        <a href="${SITE_URL}/moje-rezervace" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 36px;border-radius:12px;text-decoration:none;font-weight:800;font-size:15px;box-shadow:0 4px 16px rgba(116,251,113,.35)">Zobrazit rezervaci</a>
      </div>`
  } else if (type === 'booking_completed') {
    body = `
      <h2 style="color:#1a8a18;font-size:18px;margin-top:0">Děkujeme za jízdu!</h2>
      <p style="color:#374151;line-height:1.6">Dobrý den${vars.customer_name ? ` ${vars.customer_name}` : ''},</p>
      <p style="color:#374151;line-height:1.6">Vaše rezervace č. <strong>${vars.booking_number}</strong> byla úspěšně dokončena.</p>
      ${bookingTable}
      <p style="color:#374151;line-height:1.6">Doufáme, že jste si jízdu užili! Konečnou fakturu naleznete v aplikaci.</p>
      <div style="text-align:center;margin:28px 0">
        <a href="${SITE_URL}/moje-rezervace" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 36px;border-radius:12px;text-decoration:none;font-weight:800;font-size:15px;box-shadow:0 4px 16px rgba(116,251,113,.35)">Zobrazit historii</a>
      </div>`
  } else if (type === 'booking_modified') {
    body = `
      <h2 style="color:#2563eb;font-size:18px;margin-top:0">Vaše rezervace byla upravena</h2>
      <p style="color:#374151;line-height:1.6">Dobrý den${vars.customer_name ? ` ${vars.customer_name}` : ''},</p>
      <p style="color:#374151;line-height:1.6">Vaše rezervace č. <strong>${vars.booking_number}</strong> byla upravena. Nové údaje:</p>
      ${bookingTable}
      ${vars.price_difference ? `<p style="color:#374151;line-height:1.6">Rozdíl v ceně: <strong>${vars.price_difference} Kč</strong></p>` : ''}
      <div style="text-align:center;margin:28px 0">
        <a href="${SITE_URL}/moje-rezervace" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 36px;border-radius:12px;text-decoration:none;font-weight:800;font-size:15px;box-shadow:0 4px 16px rgba(116,251,113,.35)">Zobrazit rezervaci</a>
      </div>`
  } else if (type === 'voucher_purchased') {
    body = `
      <h2 style="color:#1a8a18;font-size:18px;margin-top:0">Váš poukaz je připraven!</h2>
      <p style="color:#374151;line-height:1.6">Dobrý den${vars.customer_name ? ` ${vars.customer_name}` : ''},</p>
      <p style="color:#374151;line-height:1.6">Děkujeme za zakoupení poukazu. Váš kód:</p>
      <div style="text-align:center;margin:20px 0;padding:20px;background:#dcfce7;border-radius:12px">
        <span style="font-size:28px;font-weight:900;letter-spacing:4px;color:#1a8a18">${vars.voucher_code || ''}</span>
      </div>
      <p style="color:#374151;line-height:1.6">Hodnota: <strong>${vars.voucher_value || ''} Kč</strong> | Platnost do: <strong>${vars.voucher_expiry || ''}</strong></p>`
  }

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f7f5;padding:32px">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08)">
    ${header}
    <div style="padding:32px">${body}
      <p style="color:#6b7280;font-size:13px;line-height:1.5">Máte dotaz? Napište nám na <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
    </div>
    ${footer}
  </div>
</body></html>`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const body = await req.json()
    const { type, booking_id, customer_email, customer_name, motorcycle, start_date, end_date, total_price, price_difference, voucher_code, voucher_value, voucher_expiry } = body

    if (!type || !customer_email) {
      return new Response(JSON.stringify({ error: 'Missing type or customer_email' }), { status: 400 })
    }

    const vars: Record<string, string> = {
      customer_name: customer_name || '',
      booking_number: (booking_id || '').slice(0, 8).toUpperCase(),
      motorcycle: motorcycle || '',
      start_date: fmtDate(start_date),
      end_date: fmtDate(end_date),
      total_price: fmtPrice(total_price || 0),
      price_difference: price_difference ? fmtPrice(price_difference) : '',
      voucher_code: voucher_code || '',
      voucher_value: voucher_value ? fmtPrice(voucher_value) : '',
      voucher_expiry: fmtDate(voucher_expiry),
    }

    const emailType = type as EmailType
    const subject = SUBJECTS[emailType]?.(vars) || `Oznámení — MOTO GO 24`
    const html = buildHtml(emailType, vars)

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    try {
      await sendWithRetry({ from: FROM_EMAIL, to: customer_email, subject, html })
    } catch (emailErr) {
      console.error('Email send failed after retries:', emailErr)
      // Log failure to debug_log
      await supabase.from('debug_log').insert({
        source: 'send-booking-email',
        action: 'email_send_failed',
        component: 'resend',
        status: 'error',
        error_message: (emailErr as Error).message,
        request_data: { type, customer_email, booking_id },
      }).catch(() => {})
      return new Response(JSON.stringify({ error: 'Email send failed', details: (emailErr as Error).message }), { status: 500 })
    }

    // Log email
    await supabase.from('email_log').insert({
      template_slug: type,
      recipient: customer_email,
      subject,
      status: 'sent',
      booking_id: booking_id || null,
    }).catch(() => {}) // email_log may not exist yet

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 })
  }
})
