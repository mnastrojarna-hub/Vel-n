import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

/** Replace {{var}} placeholders; unknown vars → empty string */
function renderTemplate(template: string, vars: Record<string, string>): string {
  if (!template) return ''
  let result = template
  for (const [key, val] of Object.entries(vars)) {
    result = result.replaceAll(`{{${key}}}`, val || '')
  }
  result = result.replace(/\{\{[^}]+\}\}/g, '')
  return result
}

/** Wrap body HTML in unified MotoGo24 email layout (1:1 with invoice design) */
function wrapInBrandedLayout(bodyHtml: string): string {
  const header = `<div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:middle;padding-right:14px;width:52px"><img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
      <td style="vertical-align:middle">
        <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
        <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">PŮJČOVNA MOTOREK</div>
      </td>
    </tr></table>
  </div>`
  const footer = `<div style="background:#0a1f15;padding:14px 32px;color:#ffffff;font-size:11px;line-height:1.6">
    <strong style="color:#ffffff">Bc. Petra Semorádová</strong>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>Mezná 9, 393 01 Mezná
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>IČO: 21874263
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">+420 774 256 271</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">info@motogo24.cz</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">www.motogo24.cz</span>
  </div>`

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased">
  <div style="max-width:780px;margin:0 auto;background:#ffffff">
    ${header}
    <div style="padding:32px;color:#0f1a14;font-size:14px;line-height:1.7">${bodyHtml}</div>
    ${footer}
  </div>
</body></html>`
}

/** Send email via Resend with 2 retries (exponential backoff) */
async function sendWithRetry(
  emailData: { from: string; to: string; subject: string; html: string },
): Promise<{ success: boolean; provider_id?: string; error?: string }> {
  for (let attempt = 1; attempt <= 2; attempt++) {
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
      const errBody = await res.text()
      if (attempt === 2) {
        return { success: false, error: `Resend ${res.status}: ${errBody}` }
      }
    } catch (e) {
      if (attempt === 2) {
        return { success: false, error: `Resend fetch error: ${(e as Error).message}` }
      }
    }
    await new Promise(r => setTimeout(r, 1000 * attempt))
  }
  return { success: false, error: 'Resend retry exhausted' }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const body = await req.json()
    const {
      to,
      template_slug,
      template_vars = {},
      customer_id,
      booking_id,
      subject: subjectOverride,
      raw_html,
      raw_body,
      test = false,
      // send-broadcast/ManualSendTab compatibility fields
      channel,
      type,
      invoice_id,
    } = body

    // If called with type='invoice' + invoice_id, delegate to invoice logic
    if (type === 'invoice' && invoice_id) {
      return await handleInvoiceEmail(supabase, invoice_id)
    }

    // Resolve email content
    let html = ''
    let subject = subjectOverride || ''
    let resolvedSlug = template_slug || null
    let isMarketing = false

    if (raw_html) {
      // Direct HTML — use as-is (already formatted from Velín)
      html = raw_html
      if (!subject) subject = 'Oznámení — MOTO GO 24'
    } else if (raw_body) {
      // Plain text from ManualSendTab — convert newlines, wrap in branded layout
      const bodyHtml = raw_body.replace(/\n/g, '<br>')
      html = wrapInBrandedLayout(bodyHtml)
      if (!subject) subject = 'Zpráva od MOTO GO 24'
      isMarketing = true
    } else if (template_slug) {
      // Load from email_templates table
      const { data: tpl, error: tplErr } = await supabase
        .from('email_templates')
        .select('slug, name, subject, body_html, active')
        .eq('slug', template_slug)
        .eq('active', true)
        .maybeSingle()

      if (tplErr || !tpl) {
        return jsonResponse({
          success: false,
          error: `Template "${template_slug}" not found or inactive`,
        }, 404)
      }

      const renderedBody = renderTemplate(tpl.body_html || '', template_vars)
      subject = subjectOverride || renderTemplate(tpl.subject || '', template_vars) || `${tpl.name} — MOTO GO 24`
      html = wrapInBrandedLayout(renderedBody)
      resolvedSlug = tpl.slug
    } else {
      return jsonResponse({ success: false, error: 'Must provide raw_html, raw_body, or template_slug' }, 400)
    }

    // Test mode — return preview without sending
    if (test) {
      return jsonResponse({
        success: true,
        preview_html: html,
        subject,
        test: true,
      })
    }

    // Validate recipient
    if (!to) {
      return jsonResponse({ success: false, error: 'Missing "to" email address' }, 400)
    }

    if (!RESEND_API_KEY) {
      return jsonResponse({ success: false, error: 'RESEND_API_KEY not configured' }, 500)
    }

    // Send via Resend
    const result = await sendWithRetry({ from: FROM_EMAIL, reply_to: REPLY_TO, to, subject, html })

    // Log to message_log (channel=email)
    try {
      await supabase.from('message_log').insert({
        channel: 'email',
        direction: 'outbound',
        recipient_email: to,
        customer_id: customer_id || null,
        booking_id: booking_id || null,
        template_slug: resolvedSlug,
        content_preview: subject.slice(0, 160),
        body: html,
        external_id: result.provider_id || null,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        is_marketing: isMarketing,
        template_vars: Object.keys(template_vars).length > 0 ? template_vars : null,
      })
    } catch (e) { /* ignore logging errors */ }

    // Also log to sent_emails for backwards compatibility
    try {
      await supabase.from('sent_emails').insert({
        template_slug: resolvedSlug || 'manual',
        recipient_email: to,
        recipient_id: customer_id || null,
        booking_id: booking_id || null,
        subject,
        body_html: html,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        provider_id: result.provider_id || null,
      })
    } catch (e) { /* ignore logging errors */ }

    if (!result.success) {
      try {
        await supabase.from('debug_log').insert({
          source: 'send-email',
          action: 'resend_send_failed',
          component: 'edge-function',
          status: 'error',
          error_message: result.error,
          request_data: { to, template_slug, booking_id },
        })
      } catch (e) { /* ignore */ }

      return jsonResponse({ success: false, error: result.error }, 502)
    }

    return jsonResponse({
      success: true,
      provider_id: result.provider_id,
    })
  } catch (err) {
    console.error('send-email error:', err)

    try {
      await supabase.from('debug_log').insert({
        source: 'send-email',
        action: 'unhandled_error',
        component: 'edge-function',
        status: 'error',
        error_message: (err as Error).message,
      })
    } catch (e) { /* ignore */ }

    return jsonResponse({ error: (err as Error).message }, 500)
  }
})

/**
 * Handle type='invoice' calls from InvoiceCreateModal / InvoicesTab.
 * Loads invoice + customer from DB, builds email, sends via Resend.
 */
async function handleInvoiceEmail(
  supabase: ReturnType<typeof createClient>,
  invoiceId: string,
): Promise<Response> {
  // Load invoice with customer profile
  const { data: invoice, error: invErr } = await supabase
    .from('invoices')
    .select('id, number, type, total, issue_date, due_date, status, variable_symbol, customer_id, booking_id, items, pdf_path, profiles(full_name, email)')
    .eq('id', invoiceId)
    .maybeSingle()

  if (invErr || !invoice) {
    return jsonResponse({ success: false, error: 'Invoice not found' }, 404)
  }

  const profile = invoice.profiles as { full_name?: string; email?: string } | null
  if (!profile?.email) {
    return jsonResponse({ success: false, error: 'Customer has no email address' }, 400)
  }

  const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
  const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })

  const typeLabels: Record<string, string> = {
    advance: 'Zálohová faktura',
    final: 'Konečná faktura',
    proforma: 'Proforma faktura',
    issued: 'Faktura vydaná',
    payment_receipt: 'Doklad o platbě',
    shop_final: 'Faktura — e-shop',
    shop_proforma: 'Proforma — e-shop',
  }

  const invoiceLabel = typeLabels[invoice.type] || 'Faktura'
  const subject = `${invoiceLabel} č. ${invoice.number} — MOTO GO 24`

  const bodyHtml = `
    <h2 style="color:#1a8a18;font-size:18px;margin-top:0">${invoiceLabel}</h2>
    <p style="color:#374151;line-height:1.6">Dobrý den${profile.full_name ? ` ${profile.full_name}` : ''},</p>
    <p style="color:#374151;line-height:1.6">zasíláme Vám ${invoiceLabel.toLowerCase()} č. <strong>${invoice.number}</strong>.</p>
    <div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0">
      <table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">
        <tr><td style="padding:4px 0;font-weight:700">Číslo:</td><td>${invoice.number}</td></tr>
        <tr><td style="padding:4px 0;font-weight:700">Datum vystavení:</td><td>${fmtDate(invoice.issue_date)}</td></tr>
        <tr><td style="padding:4px 0;font-weight:700">Splatnost:</td><td>${fmtDate(invoice.due_date)}</td></tr>
        ${invoice.variable_symbol ? `<tr><td style="padding:4px 0;font-weight:700">VS:</td><td>${invoice.variable_symbol}</td></tr>` : ''}
        <tr><td style="padding:4px 0;font-weight:700">Celkem:</td><td style="font-weight:700;color:#1a8a18">${fmtPrice(invoice.total)} Kč</td></tr>
      </table>
    </div>
    <p style="color:#374151;line-height:1.6">Fakturu naleznete také ve své aplikaci MOTO GO 24.</p>`

  const html = wrapInBrandedLayout(bodyHtml)

  if (!RESEND_API_KEY) {
    return jsonResponse({ success: false, error: 'RESEND_API_KEY not configured' }, 500)
  }

  const result = await sendWithRetry({ from: FROM_EMAIL, reply_to: REPLY_TO, to: profile.email, subject, html })

  // Log
  try {
    await supabase.from('message_log').insert({
      channel: 'email',
      direction: 'outbound',
      recipient_email: profile.email,
      customer_id: invoice.customer_id || null,
      booking_id: invoice.booking_id || null,
      template_slug: 'invoice',
      content_preview: subject.slice(0, 160),
      body: html,
      external_id: result.provider_id || null,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error || null,
      is_marketing: false,
    })
  } catch (e) { /* ignore */ }

  try {
    await supabase.from('sent_emails').insert({
      template_slug: 'invoice',
      recipient_email: profile.email,
      recipient_id: invoice.customer_id || null,
      booking_id: invoice.booking_id || null,
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
        source: 'send-email',
        action: 'invoice_email_failed',
        component: 'edge-function',
        status: 'error',
        error_message: result.error,
        request_data: { invoice_id: invoiceId },
      })
    } catch (e) { /* ignore */ }
    return jsonResponse({ success: false, error: result.error }, 502)
  }

  // Update invoice status to 'sent' if currently 'issued' or 'draft'
  if (['issued', 'draft'].includes(invoice.status)) {
    try {
      await supabase.from('invoices')
        .update({ status: 'sent' })
        .eq('id', invoiceId)
    } catch (e) { /* ignore */ }
  }

  return jsonResponse({ success: true, provider_id: result.provider_id })
}
