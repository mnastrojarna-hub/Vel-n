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
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })

/** Replace {{var}} placeholders */
function renderTemplate(template: string, vars: Record<string, string>): string {
  if (!template) return ''
  let result = template
  for (const [key, val] of Object.entries(vars)) {
    result = result.replaceAll(`{{${key}}}`, val || '')
  }
  return result.replace(/\{\{[^}]+\}\}/g, '')
}

/** Wrap body HTML in unified MotoGo24 email layout (1:1 with invoice design) */
function wrapInBrandedLayout(bodyHtml: string): string {
  const header = `<div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:middle;padding-right:14px;width:52px"><img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
      <td style="vertical-align:middle">
        <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
        <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">P\u016eJ\u010cOVNA MOTOREK</div>
      </td>
    </tr></table>
  </div>`
  const footer = `<div style="background:#0a1f15;padding:14px 32px;color:#ffffff;font-size:11px;line-height:1.6">
    <strong style="color:#ffffff">Bc. Petra Semor\u00e1dov\u00e1</strong>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>Mezn\u00e1 9, 393 01 Mezn\u00e1
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>I\u010cO: 21874263
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

async function sendWithRetry(emailData: Record<string, unknown>): Promise<{ success: boolean; provider_id?: string; error?: string }> {
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer ' + RESEND_API_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify(emailData),
      })
      if (res.ok) { const data = await res.json(); return { success: true, provider_id: data.id } }
      const errBody = await res.text()
      if (attempt === 2) return { success: false, error: `Resend ${res.status}: ${errBody}` }
    } catch (e) { if (attempt === 2) return { success: false, error: (e as Error).message } }
    await new Promise(r => setTimeout(r, 1000 * attempt))
  }
  return { success: false, error: 'Resend retry exhausted' }
}

/** Map invoice type to email_templates slug */
const TYPE_TO_SLUG: Record<string, string> = {
  advance: 'invoice_advance',
  proforma: 'invoice_advance',
  payment_receipt: 'invoice_payment_receipt',
  final: 'invoice_final',
  issued: 'invoice_final',
  shop_final: 'invoice_shop_final',
  shop_proforma: 'invoice_advance',
}

const TYPE_LABELS: Record<string, string> = {
  advance: 'Z\u00e1lohov\u00e1 faktura',
  final: 'Kone\u010dn\u00e1 faktura',
  proforma: 'Proforma faktura',
  issued: 'Faktura vydan\u00e1',
  payment_receipt: 'Doklad o platb\u011b',
  shop_final: 'Faktura \u2014 e-shop',
  shop_proforma: 'Proforma \u2014 e-shop',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const { invoice_id, html_content, customer_email, customer_name, invoice_number } = await req.json()

    if (!invoice_id) return jsonResponse({ success: false, error: 'Missing invoice_id' }, 400)

    // If InvoicePreviewModal passed html_content directly, use it as-is when it's a full invoice document
    if (html_content && customer_email) {
      const subject = `Faktura \u010d. ${invoice_number || '\u2014'} \u2014 MOTO GO 24`
      const isFullDoc = /^\s*<!DOCTYPE/i.test(html_content) || /<html[\s>]/i.test(html_content)
      const html = isFullDoc ? html_content : wrapInBrandedLayout(html_content)
      if (!RESEND_API_KEY) return jsonResponse({ success: false, error: 'RESEND_API_KEY not configured' }, 500)
      const result = await sendWithRetry({ from: FROM_EMAIL, reply_to: REPLY_TO, to: customer_email, subject, html })
      try { await supabase.from('sent_emails').insert({ template_slug: 'invoice', recipient_email: customer_email, subject, body_html: html, status: result.success ? 'sent' : 'failed', error_message: result.error || null, provider_id: result.provider_id || null }) } catch {}
      try { await supabase.from('message_log').insert({ channel: 'email', direction: 'outbound', recipient_email: customer_email, template_slug: 'invoice', content_preview: subject.slice(0, 160), body: html, external_id: result.provider_id || null, status: result.success ? 'sent' : 'failed', error_message: result.error || null, is_marketing: false }) } catch {}
      if (!result.success) return jsonResponse({ success: false, error: result.error }, 502)
      return jsonResponse({ success: true, provider_id: result.provider_id })
    }

    // Load invoice from DB
    const { data: invoice, error: invErr } = await supabase
      .from('invoices')
      .select('id, number, type, total, issue_date, due_date, status, variable_symbol, customer_id, booking_id, pdf_path, profiles(full_name, email)')
      .eq('id', invoice_id).maybeSingle()

    if (invErr || !invoice) return jsonResponse({ success: false, error: 'Invoice not found' }, 404)

    const profile = invoice.profiles as { full_name?: string; email?: string } | null
    const recipientEmail = customer_email || profile?.email
    const recipientName = customer_name || profile?.full_name
    if (!recipientEmail) return jsonResponse({ success: false, error: 'No customer email available' }, 400)

    const invoiceLabel = TYPE_LABELS[invoice.type] || 'Faktura'
    const templateSlug = TYPE_TO_SLUG[invoice.type] || 'invoice_final'

    // Template variables
    const vars: Record<string, string> = {
      customer_name: recipientName || '',
      invoice_number: invoice.number || '',
      invoice_type: invoiceLabel,
      total: fmtPrice(invoice.total),
      issue_date: fmtDate(invoice.issue_date),
      due_date: fmtDate(invoice.due_date),
      variable_symbol: invoice.variable_symbol || invoice.number || '',
    }

    // Try to load template from DB
    let templateHtml = ''
    let subject = ''

    const { data: tpl } = await supabase
      .from('email_templates')
      .select('subject, body_html, active')
      .eq('slug', templateSlug)
      .eq('active', true)
      .maybeSingle()

    if (tpl?.body_html) {
      templateHtml = renderTemplate(tpl.body_html, vars)
      subject = renderTemplate(tpl.subject || '', vars)
    }

    // Fallback subject
    if (!subject) {
      subject = `${invoiceLabel} \u010d. ${invoice.number} \u2014 MOTO GO 24`
    }

    // Fallback body
    if (!templateHtml) {
      templateHtml = `<p>Dobr\u00fd den${recipientName ? ' ' + recipientName : ''},</p>
<p>zas\u00edl\u00e1me V\u00e1m ${invoiceLabel.toLowerCase()} \u010d. <strong>${invoice.number}</strong>.</p>
<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0">
  <table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">
    <tr><td style="padding:4px 0;font-weight:700">\u010c\u00edslo:</td><td>${invoice.number}</td></tr>
    <tr><td style="padding:4px 0;font-weight:700">Datum vystaven\u00ed:</td><td>${fmtDate(invoice.issue_date)}</td></tr>
    <tr><td style="padding:4px 0;font-weight:700">Splatnost:</td><td>${fmtDate(invoice.due_date)}</td></tr>
    ${invoice.variable_symbol ? `<tr><td style="padding:4px 0;font-weight:700">VS:</td><td>${invoice.variable_symbol}</td></tr>` : ''}
    <tr><td style="padding:4px 0;font-weight:700">Celkem:</td><td style="font-weight:700;color:#1a8a18">${fmtPrice(invoice.total)} K\u010d</td></tr>
  </table>
</div>
<p>Fakturu naleznete v p\u0159\u00edloze tohoto emailu a tak\u00e9 ve sv\u00e9 aplikaci MOTO GO 24.</p>
<p>T\u00fdm MotoGo24</p>`
    }

    if (!RESEND_API_KEY) return jsonResponse({ success: false, error: 'RESEND_API_KEY not configured' }, 500)

    // Prefer the full unified-design invoice HTML from Storage as the email body (1:1 with PDF/screen).
    // Fallback to DB email_template + branded wrapper when the file is missing.
    let html = ''
    const attachments: { content: string; filename: string }[] = []
    if (invoice.pdf_path) {
      try {
        const { data: blob } = await supabase.storage.from('documents').download(invoice.pdf_path)
        if (blob) {
          const bytes = new Uint8Array(await blob.arrayBuffer())
          const text = new TextDecoder('utf-8').decode(bytes)
          if (text && /<html[\s>]/i.test(text)) html = text
          const b64 = btoa(Array.from(bytes, (b: number) => String.fromCharCode(b)).join(''))
          attachments.push({ content: b64, filename: `${invoiceLabel.replace(/ /g, '-')}-${invoice.number}.html` })
        }
      } catch { /* ignore */ }
    }
    if (!html) html = wrapInBrandedLayout(templateHtml)

    const emailPayload: Record<string, unknown> = { from: FROM_EMAIL, reply_to: REPLY_TO, to: recipientEmail, subject, html }
    if (attachments.length > 0) emailPayload.attachments = attachments
    const result = await sendWithRetry(emailPayload)

    // Send copy to info@
    if (result.success) {
      try { await sendWithRetry({ from: FROM_EMAIL, to: REPLY_TO, subject: `[Kopie] ${subject}`, html }) } catch {}
    }

    // Log
    try { await supabase.from('message_log').insert({ channel: 'email', direction: 'outbound', recipient_email: recipientEmail, customer_id: invoice.customer_id || null, booking_id: invoice.booking_id || null, template_slug: templateSlug, content_preview: subject.slice(0, 160), body: html, external_id: result.provider_id || null, status: result.success ? 'sent' : 'failed', error_message: result.error || null, is_marketing: false }) } catch {}
    try { await supabase.from('sent_emails').insert({ template_slug: templateSlug, recipient_email: recipientEmail, recipient_id: invoice.customer_id || null, booking_id: invoice.booking_id || null, subject, body_html: html, status: result.success ? 'sent' : 'failed', error_message: result.error || null, provider_id: result.provider_id || null }) } catch {}

    if (!result.success) {
      try { await supabase.from('debug_log').insert({ source: 'send-invoice-email', action: 'invoice_email_failed', component: 'edge-function', status: 'error', error_message: result.error, request_data: { invoice_id } }) } catch {}
      return jsonResponse({ success: false, error: result.error }, 502)
    }

    // Update invoice status
    if (['issued', 'draft'].includes(invoice.status)) {
      try { await supabase.from('invoices').update({ status: 'sent' }).eq('id', invoice_id) } catch {}
    }

    return jsonResponse({ success: true, provider_id: result.provider_id })
  } catch (err) {
    console.error('send-invoice-email error:', err)
    try { await supabase.from('debug_log').insert({ source: 'send-invoice-email', action: 'unhandled_error', component: 'edge-function', status: 'error', error_message: (err as Error).message }) } catch {}
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
