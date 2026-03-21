import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'

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

/** Wrap body HTML in branded MotoGo24 email layout */
function wrapInBrandedLayout(bodyHtml: string): string {
  const header = `<div style="background:#1a2e22;padding:28px 32px;text-align:center"><h1 style="margin:0;color:#74FB71;font-size:22px;font-weight:900">MOTO GO 24</h1></div>`
  const footer = `<div style="background:#f9fafb;padding:16px 32px;text-align:center;border-top:1px solid #e5e7eb">
    <p style="color:#9ca3af;font-size:11px;margin:0 0 8px 0">MOTO GO 24 — Pronájem motorek po celé ČR</p>
    <p style="color:#9ca3af;font-size:13px;margin:0">Máte dotaz? Napište nám na <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a></p>
  </div>`

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f4f7f5;padding:32px">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08)">
    ${header}
    <div style="padding:32px">
      <div style="color:#374151;font-size:14px;line-height:1.7">${bodyHtml}</div>
    </div>
    ${footer}
  </div>
</body></html>`
}

/** Send email via Resend with 2 retries */
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

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const {
      invoice_id,
      html_content,
      customer_email,
      customer_name,
      invoice_number,
    } = await req.json()

    if (!invoice_id) {
      return jsonResponse({ success: false, error: 'Missing invoice_id' }, 400)
    }

    // If InvoicePreviewModal passed html_content directly, use it
    if (html_content && customer_email) {
      const subject = `Faktura č. ${invoice_number || '—'} — MOTO GO 24`
      const html = wrapInBrandedLayout(html_content)

      if (!RESEND_API_KEY) {
        return jsonResponse({ success: false, error: 'RESEND_API_KEY not configured' }, 500)
      }

      const result = await sendWithRetry({ from: FROM_EMAIL, to: customer_email, subject, html })

      await supabase.from('sent_emails').insert({
        template_slug: 'invoice',
        recipient_email: customer_email,
        subject,
        body_html: html,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        provider_id: result.provider_id || null,
      }).catch(() => {})

      await supabase.from('message_log').insert({
        channel: 'email',
        direction: 'outbound',
        recipient_email: customer_email,
        template_slug: 'invoice',
        content_preview: subject.slice(0, 160),
        body: html,
        external_id: result.provider_id || null,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        is_marketing: false,
      }).catch(() => {})

      if (!result.success) {
        return jsonResponse({ success: false, error: result.error }, 502)
      }
      return jsonResponse({ success: true, provider_id: result.provider_id })
    }

    // Otherwise, load invoice from DB and build email
    const { data: invoice, error: invErr } = await supabase
      .from('invoices')
      .select('id, number, type, total, issue_date, due_date, status, variable_symbol, customer_id, booking_id, profiles(full_name, email)')
      .eq('id', invoice_id)
      .maybeSingle()

    if (invErr || !invoice) {
      return jsonResponse({ success: false, error: 'Invoice not found' }, 404)
    }

    const profile = invoice.profiles as { full_name?: string; email?: string } | null
    const recipientEmail = customer_email || profile?.email
    const recipientName = customer_name || profile?.full_name

    if (!recipientEmail) {
      return jsonResponse({ success: false, error: 'No customer email available' }, 400)
    }

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
      <p style="color:#374151;line-height:1.6">Dobrý den${recipientName ? ` ${recipientName}` : ''},</p>
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

    const result = await sendWithRetry({ from: FROM_EMAIL, to: recipientEmail, subject, html })

    // Log to both tables
    await supabase.from('message_log').insert({
      channel: 'email',
      direction: 'outbound',
      recipient_email: recipientEmail,
      customer_id: invoice.customer_id || null,
      booking_id: invoice.booking_id || null,
      template_slug: 'invoice',
      content_preview: subject.slice(0, 160),
      body: html,
      external_id: result.provider_id || null,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error || null,
      is_marketing: false,
    }).catch(() => {})

    await supabase.from('sent_emails').insert({
      template_slug: 'invoice',
      recipient_email: recipientEmail,
      recipient_id: invoice.customer_id || null,
      booking_id: invoice.booking_id || null,
      subject,
      body_html: html,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error || null,
      provider_id: result.provider_id || null,
    }).catch(() => {})

    if (!result.success) {
      await supabase.from('debug_log').insert({
        source: 'send-invoice-email',
        action: 'invoice_email_failed',
        component: 'edge-function',
        status: 'error',
        error_message: result.error,
        request_data: { invoice_id },
      }).catch(() => {})
      return jsonResponse({ success: false, error: result.error }, 502)
    }

    // Update invoice status
    if (['issued', 'draft'].includes(invoice.status)) {
      await supabase.from('invoices')
        .update({ status: 'sent' })
        .eq('id', invoice_id)
        .catch(() => {})
    }

    return jsonResponse({ success: true, provider_id: result.provider_id })
  } catch (err) {
    console.error('send-invoice-email error:', err)

    await supabase.from('debug_log').insert({
      source: 'send-invoice-email',
      action: 'unhandled_error',
      component: 'edge-function',
      status: 'error',
      error_message: (err as Error).message,
    }).catch(() => {})

    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
