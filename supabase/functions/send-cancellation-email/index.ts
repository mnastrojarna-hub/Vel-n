import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

/** Send email with exponential backoff retry (max 3 attempts) */
async function sendWithRetry(emailData: Record<string, unknown>, maxRetries = 3): Promise<{ success: boolean; provider_id?: string; error?: string }> {
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
      if (res.ok) {
        const data = await res.json()
        return { success: true, provider_id: data.id }
      }
      if (attempt === maxRetries) {
        const errBody = await res.text()
        return { success: false, error: `Resend ${res.status}: ${errBody}` }
      }
    } catch (e) {
      if (attempt === maxRetries) return { success: false, error: (e as Error).message }
    }
    await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt)))
  }
  return { success: false, error: 'Resend retry exhausted' }
}

/** Replace {{var}} placeholders; unknown vars -> empty string */
function renderTemplate(template: string, vars: Record<string, string>): string {
  if (!template) return ''
  let result = template
  for (const [key, val] of Object.entries(vars)) {
    result = result.replaceAll(`{{${key}}}`, val || '')
  }
  result = result.replace(/\{\{[^}]+\}\}/g, '')
  return result
}

/** MotoGo24 business card HTML for email footer */
function getBusinessCard(): string {
  return `
  <div style="border-top:2px solid #74FB71;margin-top:32px;padding-top:20px">
    <table style="width:100%;border-collapse:collapse" cellpadding="0" cellspacing="0">
      <tr>
        <td style="vertical-align:top;width:50%;padding-right:16px">
          <img src="${SITE_URL}/gfx/logo-icon.svg" alt="MotoGo24" width="60" height="60" style="display:block;margin-bottom:8px" />
          <div style="font-family:Montserrat,'Arial Black',sans-serif;font-weight:800;font-size:16px;color:#1a2e22;letter-spacing:2px">MOTO GO 24</div>
          <div style="font-family:Montserrat,Arial,sans-serif;font-size:10px;color:#6b7280;letter-spacing:3px;margin-top:2px">P\u016eJ\u010cOVNA MOTOREK</div>
          <img src="${SITE_URL}/gfx/qr-motogo24.png" alt="QR" width="80" height="80" style="display:block;margin-top:12px" />
        </td>
        <td style="vertical-align:top;width:50%;border-left:2px solid #74FB71;padding-left:16px">
          <table style="border-collapse:collapse;font-size:13px;color:#374151;line-height:2" cellpadding="0" cellspacing="0">
            <tr><td style="padding-right:8px;vertical-align:middle">\u260E</td><td>+420 774 256 271</td></tr>
            <tr><td style="padding-right:8px;vertical-align:middle">\u2709</td><td><a href="mailto:info@motogo24.cz" style="color:#2563eb;text-decoration:none">info@motogo24.cz</a></td></tr>
            <tr><td style="padding-right:8px;vertical-align:middle">\ud83d\udcf7</td><td><a href="https://instagram.com/moto.go24" style="color:#2563eb;text-decoration:none">moto.go24</a></td></tr>
            <tr><td style="padding-right:8px;vertical-align:middle">\ud83d\udc4d</td><td><a href="https://facebook.com/MotoGo24" style="color:#2563eb;text-decoration:none">MotoGo24</a></td></tr>
          </table>
        </td>
      </tr>
    </table>
  </div>`
}

/** Wrap body HTML in branded MotoGo24 email layout with vizitka */
function wrapInBrandedLayout(bodyHtml: string): string {
  const header = `<div style="background:#1a2e22;padding:28px 32px;text-align:center"><h1 style="margin:0;color:#74FB71;font-size:22px;font-weight:900;letter-spacing:2px">MOTO GO 24</h1></div>`
  const footer = `<div style="background:#f9fafb;padding:16px 32px;text-align:center;border-top:1px solid #e5e7eb">
    <p style="color:#9ca3af;font-size:11px;margin:0">MOTO GO 24 \u2014 Pron\u00e1jem motorek po cel\u00e9 \u010cR</p>
  </div>`

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f7f5;padding:32px">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08)">
    ${header}
    <div style="padding:32px">
      <div style="color:#374151;font-size:14px;line-height:1.7">${bodyHtml}</div>
      ${getBusinessCard()}
    </div>
    ${footer}
  </div>
</body></html>`
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const {
      booking_id,
      customer_email,
      customer_name,
      motorcycle,
      start_date,
      end_date,
      cancellation_reason,
      cancelled_by_source,
      refund_amount,
      refund_percent,
      source = 'app',
    } = await req.json()

    if (!customer_email) {
      return new Response(JSON.stringify({ error: 'No customer email' }), {
        status: 400,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const vars: Record<string, string> = {
      customer_name: customer_name || '',
      booking_number: (booking_id || '').slice(0, 8).toUpperCase(),
      motorcycle: motorcycle || '',
      start_date: start_date || '',
      end_date: end_date || '',
      cancellation_reason: cancellation_reason || 'Neuvedeno',
      refund_amount: refund_amount ? Number(refund_amount).toLocaleString('cs-CZ') : '',
      refund_percent: refund_percent ? String(refund_percent) : '100',
      site_url: SITE_URL,
      business_card: getBusinessCard(),
    }

    // Try web-specific template first if source=web
    const slugsToTry = source === 'web'
      ? ['web_booking_cancelled', 'booking_cancelled']
      : ['booking_cancelled']

    let templateHtml = ''
    let subject = ''

    for (const trySlug of slugsToTry) {
      const { data: tpl } = await supabase
        .from('email_templates')
        .select('slug, name, subject, body_html, active')
        .eq('slug', trySlug)
        .eq('active', true)
        .maybeSingle()

      if (tpl?.body_html) {
        templateHtml = renderTemplate(tpl.body_html, vars)
        subject = renderTemplate(tpl.subject || '', vars)
        break
      }
    }

    // Fallback subject
    if (!subject) {
      subject = `Va\u0161e rezervace \u010d. ${vars.booking_number} motocyklu u MotoGo24 byla \u00fasp\u011b\u0161n\u011b stornov\u00e1na`
    }

    // Fallback body if no DB template
    if (!templateHtml) {
      templateHtml = `
        <p>Dobr\u00fd den,</p>
        <p>potvrzujeme, \u017ee va\u0161e rezervace \u010d. <strong>${vars.booking_number}</strong> motocyklu u MotoGo24 byla \u00fasp\u011b\u0161n\u011b stornov\u00e1na.</p>
        <p>Pokud jste storno nahl\u00e1sili alespo\u0148 7 dn\u00ed p\u0159ed za\u010d\u00e1tkem n\u00e1jemn\u00ed doby, bude v\u00e1m z\u00e1loha vr\u00e1cena do 30 dn\u00ed.</p>
        <p>V p\u0159\u00edpad\u011b dotaz\u016f n\u00e1s nev\u00e1hejte kontaktovat.</p>
        <p>D\u011bkujeme a t\u011b\u0161\u00edme se, \u017ee v\u00e1s p\u0159iv\u00edt\u00e1me p\u0159i dal\u0161\u00ed p\u0159\u00edle\u017eitosti.</p>
        <p>T\u00fdm MotoGo24</p>`
    }

    const html = wrapInBrandedLayout(templateHtml)

    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), {
        status: 500,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Send via Resend with Reply-To
    const result = await sendWithRetry({
      from: FROM_EMAIL,
      reply_to: REPLY_TO,
      to: customer_email,
      subject,
      html,
    })

    // Send copy to info@
    if (result.success) {
      try {
        await sendWithRetry({
          from: FROM_EMAIL,
          to: REPLY_TO,
          subject: `[Kopie] ${subject}`,
          html,
        })
      } catch (e) { /* ignore copy send */ }
    }

    // Mark booking as notified
    if (booking_id) {
      await supabase.from('bookings').update({ cancellation_notified: true }).eq('id', booking_id)
    }

    // Log to message_log
    try {
      await supabase.from('message_log').insert({
        channel: 'email',
        direction: 'outbound',
        recipient_email: customer_email,
        booking_id: booking_id || null,
        template_slug: 'booking_cancelled',
        content_preview: subject.slice(0, 160),
        body: html,
        external_id: result.provider_id || null,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
      })
    } catch (e) { /* ignore */ }

    // Log to sent_emails
    try {
      await supabase.from('sent_emails').insert({
        template_slug: 'booking_cancelled',
        recipient_email: customer_email,
        booking_id: booking_id || null,
        subject,
        body_html: html,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        provider_id: result.provider_id || null,
      })
    } catch (e) { /* ignore */ }

    if (!result.success) {
      try {
        await supabase.from('debug_log').insert({
          source: 'send-cancellation-email',
          action: 'email_send_failed',
          component: 'resend',
          status: 'error',
          error_message: result.error,
          request_data: { booking_id, customer_email },
        })
      } catch (e) { /* ignore */ }
      return new Response(JSON.stringify({ error: 'Email send failed', details: result.error }), {
        status: 502,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
