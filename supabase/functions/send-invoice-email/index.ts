import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { normalizeLang, helpCardLabels, invoiceEmailSnippets, type Lang } from './i18n.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://www.motogo24.cz'
const FB_URL = 'https://www.facebook.com/profile.php?id=61581614672839'
const IG_URL = 'https://www.instagram.com/moto.go24/'
const GOOGLE_REVIEW_URL_DEFAULT = 'https://g.page/MotoGo24/review'

const FOLLOW_US_LABEL: Record<string, string> = {
  cs: 'SLEDUJTE NÁS', en: 'FOLLOW US', de: 'FOLGEN SIE UNS', nl: 'VOLG ONS',
  es: 'SÍGUENOS', fr: 'SUIVEZ-NOUS', pl: 'OBSERWUJ NAS',
}

// ── i18n: doména zákazníka dle jazyka (cs → .cz, ostatní → .com) ────────────
const DOMAIN_INTL = 'https://motogo24.com'
function siteForLang(lang: string): string { return lang === 'cs' ? SITE_URL : DOMAIN_INTL }
function webLabelForLang(lang: string): string { return lang === 'cs' ? 'www.motogo24.cz' : 'motogo24.com' }
/** URL odkazy motogo24.cz → zákazníkova doména (jen non-cs; e-mail se nemění). */
function localizeBodyLinks(html: string, lang: string): string {
  if (lang === 'cs' || !html) return html
  return html.replace(/https?:\/\/(?:www\.)?motogo24\.cz/gi, DOMAIN_INTL)
}

// ── i18n: dynamický překlad CZ mailové šablony přes Anthropic API ────────────
// Velín edituje jen CZ; non-cz se přeloží přes Claude + cache do
// email_templates.{subject,body}_translations[lang] + __src_<lang> hash.
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const TRANSLATE_MODEL = 'claude-haiku-4-5-20251001'
const LANG_NAMES: Record<string, string> = {
  en: 'English', de: 'German (Deutsch)', es: 'Spanish (Español)',
  fr: 'French (Français)', nl: 'Dutch (Nederlands)', pl: 'Polish (Polski)',
}
async function sha1Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('')
}
async function translateEmailTemplate(subjectCz: string, bodyCz: string, lang: string): Promise<{ subject: string; body: string } | null> {
  if (!ANTHROPIC_API_KEY) return null
  const langName = LANG_NAMES[lang] || lang
  const system = [
    `You are a professional Czech-to-${langName} translator for MotoGo24 — a Czech motorcycle rental company.`,
    'Translate the provided JSON object with keys "subject" and "body". Output STRICTLY a valid JSON object with the same two keys and translated values.',
    'STRICT RULES:',
    `- Output language: ${langName} (${lang}). Natural, native, fluent.`,
    '- Preserve ALL HTML tags, attributes, inline styles and structure EXACTLY.',
    '- DO NOT translate or change: URLs, email addresses, phone numbers, prices, IČO, DIČ, brand names. Keep "MotoGo24" and currency "Kč" unchanged.',
    '- Keep ALL template placeholders like {{var}} EXACTLY unchanged (e.g. {{invoice_number}}, {{total}}, {{site_url}}).',
    '- Do NOT add commentary or markdown fences. Output ONLY the raw JSON object.',
  ].join('\n')
  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model: TRANSLATE_MODEL, max_tokens: 4096, system, messages: [{ role: 'user', content: JSON.stringify({ subject: subjectCz, body: bodyCz }) }] }),
    })
    if (!res.ok) { console.warn('[translateEmailTemplate] anthropic', res.status); return null }
    const data = await res.json()
    const text = (data?.content?.[0]?.text || '').trim()
    let parsed: { subject?: unknown; body?: unknown }
    try { parsed = JSON.parse(text) } catch {
      const s = text.indexOf('{'), e = text.lastIndexOf('}')
      if (s < 0 || e <= s) return null
      parsed = JSON.parse(text.slice(s, e + 1))
    }
    return {
      subject: typeof parsed.subject === 'string' ? parsed.subject : subjectCz,
      body: typeof parsed.body === 'string' ? parsed.body : bodyCz,
    }
  } catch (e) { console.warn('[translateEmailTemplate]', (e as Error).message); return null }
}
async function resolveTemplateForLang(
  supabase: any,
  tpl: { slug: string; subject: string | null; body_html: string; subject_translations: any; body_translations: any },
  lang: string,
): Promise<{ subject: string; body: string }> {
  const subjCz = tpl.subject || ''
  const bodyCz = tpl.body_html
  if (lang === 'cs') return { subject: subjCz, body: bodyCz }
  const subjT = (tpl.subject_translations as Record<string, string>) || {}
  const bodyT = (tpl.body_translations as Record<string, string>) || {}
  const srcHash = await sha1Hex(`${subjCz} ${bodyCz}`)
  const fresh = bodyT['__src_' + lang] === srcHash && typeof bodyT[lang] === 'string' && !!bodyT[lang]
  if (fresh) return { subject: (typeof subjT[lang] === 'string' && subjT[lang]) ? subjT[lang] : subjCz, body: bodyT[lang] }
  const tr = await translateEmailTemplate(subjCz, bodyCz, lang)
  if (!tr) return { subject: subjCz, body: bodyCz }
  try {
    const newSubjT = { ...subjT, [lang]: tr.subject, ['__src_' + lang]: srcHash }
    const newBodyT = { ...bodyT, [lang]: tr.body, ['__src_' + lang]: srcHash }
    await supabase.from('email_templates').update({ subject_translations: newSubjT, body_translations: newBodyT }).eq('slug', tpl.slug)
  } catch { /* ignore */ }
  return tr
}

const REVIEW_BLOCK_LABELS: Record<string, { title: string; body: string; cta: string }> = {
  cs: { title: 'Pomohlo by nám vaše hodnocení', body: 'Pokud jste byli spokojeni, prosíme zanechte nám recenzi na Googlu — pomáháte tím dalším motorkářům.', cta: '⭐ Ohodnotit na Google' },
  en: { title: 'Your review would help us', body: 'If you were happy with our service, please leave us a review on Google — it helps fellow riders.', cta: '⭐ Review on Google' },
  de: { title: 'Ihre Bewertung würde uns helfen', body: 'Wenn Sie zufrieden waren, hinterlassen Sie uns bitte eine Google-Bewertung — Sie helfen damit anderen Bikern.', cta: '⭐ Auf Google bewerten' },
  nl: { title: 'Je review helpt ons enorm', body: 'Was je tevreden? Laat dan een review achter op Google — je helpt andere motorrijders.', cta: '⭐ Beoordeel op Google' },
  es: { title: 'Tu reseña nos ayudaría mucho', body: 'Si quedaste satisfecho, déjanos una reseña en Google — ayudas a otros moteros.', cta: '⭐ Reseña en Google' },
  fr: { title: 'Votre avis nous aiderait', body: 'Si vous étiez satisfait, laissez-nous un avis sur Google — vous aidez d\'autres motards.', cta: '⭐ Avis sur Google' },
  pl: { title: 'Twoja recenzja by nam pomogła', body: 'Jeśli byłeś zadowolony, zostaw nam recenzję w Google — pomożesz innym motocyklistom.', cta: '⭐ Oceń w Google' },
}

function googleReviewBlock(lang: string, url?: string): string {
  const l = REVIEW_BLOCK_LABELS[lang] || REVIEW_BLOCK_LABELS.cs
  const href = url || GOOGLE_REVIEW_URL_DEFAULT
  return `<div style="background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px;margin:24px 0;text-align:center">
  <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">${l.title}</div>
  <div style="color:#ffffff;font-size:13px;margin:0 0 16px">${l.body}</div>
  <a href="${href}" target="_blank" rel="noopener" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">${l.cta}</a>
</div>`
}

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

/** Wrap body HTML in unified MotoGo24 email layout (1:1 with invoice design + screen reference) */
function wrapInBrandedLayout(bodyHtml: string, lang: Lang = 'cs'): string {
  const hc = helpCardLabels(lang)
  const custSite = siteForLang(lang)
  const webLabel = webLabelForLang(lang)
  // Vertikální hlavička 1:1 s brand logem (sjednoceno se send-booking-email)
  const headerNew = `<div style="background:#000000;padding:36px 24px;text-align:center">
    <img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="110" height="110" style="display:inline-block;border:0;margin-bottom:16px"/>
    <div style="color:#ffffff;font-size:32px;font-weight:900;letter-spacing:3px;line-height:1">MOTO GO 24</div>
    <div style="color:#ffffff;font-size:11px;font-weight:400;letter-spacing:6px;margin-top:8px">PŮJČOVNA MOTOREK</div>
  </div>`
  const header = headerNew
  const helpCard = `<div style="margin:24px 32px 0;background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px">
    <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">${hc.title}</div>
    <div style="color:#ffffff;font-size:13px;margin:0 0 16px">${hc.body}</div>
    <a href="mailto:info@motogo24.cz" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">${hc.cta}</a>
  </div>`
  const footer = `<div style="background:#000000;padding:24px 32px;margin-top:24px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:top;padding-right:16px">
        <div style="border:1px solid #74FB71;border-radius:6px;padding:16px;color:#ffffff;font-size:12px;line-height:1.7">
          <div style="font-size:14px;font-weight:800;color:#ffffff">Motogo24</div>
          <div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">Bc. Petra Semor\u00e1dov\u00e1</div>
          <div style="color:#9ca3af">Mezn\u00e1 9, 393 01 Mezn\u00e1</div>
          <div style="color:#9ca3af">I\u010cO: 21874263</div>
          <div><span style="color:#9ca3af">Telefon:</span> <span style="color:#74FB71">+420 774 256 271</span></div>
          <div><span style="color:#9ca3af">E-mail:</span> <span style="color:#74FB71">info@motogo24.cz</span></div>
          <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">${webLabel}</span></div>
        </div>
      </td>
      <td style="vertical-align:top;width:130px;text-align:center">
        <a href="${custSite}" style="text-decoration:none"><img src="https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=8&data=${encodeURIComponent(custSite)}" alt="${webLabel}" width="120" height="120" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/></a>
        <div style="color:#9ca3af;font-size:10px;margin-top:6px">${webLabel}</div>
      </td>
    </tr></table>
    <div style="text-align:center;margin-top:18px;padding-top:16px;border-top:1px solid #1f3a2c">
      <div style="color:#9ca3af;font-size:11px;letter-spacing:2px;margin-bottom:10px">${FOLLOW_US_LABEL[lang] || FOLLOW_US_LABEL.cs}</div>
      <a href="${FB_URL}" style="display:inline-block;margin:0 6px;text-decoration:none" target="_blank" rel="noopener"><img src="${SITE_URL}/gfx/facebook-footer.svg" alt="Facebook" width="32" height="32" style="display:inline-block;border:0"/></a>
      <a href="${IG_URL}" style="display:inline-block;margin:0 6px;text-decoration:none" target="_blank" rel="noopener"><img src="${SITE_URL}/gfx/instagram-footer.svg" alt="Instagram" width="32" height="32" style="display:inline-block;border:0"/></a>
    </div>
  </div>`

  return `<!DOCTYPE html><html lang="${lang}"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased">
  <div style="max-width:780px;margin:0 auto;background:#ffffff">
    ${header}
    <div style="padding:32px;color:#0f1a14;font-size:14px;line-height:1.7">${bodyHtml}</div>
    ${helpCard}
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
    const { invoice_id, html_content, customer_email, customer_name, invoice_number, language } = await req.json()
    const custLang: Lang = normalizeLang(language)

    if (!invoice_id) return jsonResponse({ success: false, error: 'Missing invoice_id' }, 400)

    // If InvoicePreviewModal passed html_content directly, use it as-is when it's a full invoice document
    if (html_content && customer_email) {
      const snip = invoiceEmailSnippets('issued', custLang, { invoice_number: invoice_number || '\u2014' })
      const subject = snip.subject
      const isFullDoc = /^\s*<!DOCTYPE/i.test(html_content) || /<html[\s>]/i.test(html_content)
      const html = isFullDoc ? html_content : wrapInBrandedLayout(html_content, custLang)
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
      .select('slug, subject, body_html, active, subject_translations, body_translations')
      .eq('slug', templateSlug)
      .eq('active', true)
      .maybeSingle()

    if (tpl?.body_html) {
      // Velín = jen CZ. Non-cz → dynamický překlad přes API (cache + hash).
      const resolved = await resolveTemplateForLang(supabase, tpl as any, custLang)
      templateHtml = renderTemplate(resolved.body, vars)
      subject = renderTemplate(resolved.subject, vars)
    }

    // i18n snippets pro subject + intro/closing/labels
    const snip = invoiceEmailSnippets(invoice.type || 'issued', custLang, { invoice_number: invoice.number || '' })

    // Fallback subject (i18n)
    if (!subject) {
      subject = snip.subject
    }

    // Fallback body (i18n) \u2014 tabulka popisk\u016f v jazyce z\u00e1kazn\u00edka, \u010d\u00edsla/data neutral
    if (!templateHtml) {
      templateHtml = `<p>${snip.intro}</p>
<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0">
  <table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">
    <tr><td style="padding:4px 0;font-weight:700">${snip.tableLabels.num}</td><td>${invoice.number}</td></tr>
    <tr><td style="padding:4px 0;font-weight:700">${snip.tableLabels.issue}</td><td>${fmtDate(invoice.issue_date)}</td></tr>
    <tr><td style="padding:4px 0;font-weight:700">${snip.tableLabels.due}</td><td>${fmtDate(invoice.due_date)}</td></tr>
    ${invoice.variable_symbol ? `<tr><td style="padding:4px 0;font-weight:700">${snip.tableLabels.vs}</td><td>${invoice.variable_symbol}</td></tr>` : ''}
    <tr><td style="padding:4px 0;font-weight:700">${snip.tableLabels.total}</td><td style="font-weight:700;color:#1a8a18">${fmtPrice(invoice.total)} K\u010d</td></tr>
  </table>
</div>
<p>${snip.outro}</p>
<p>${snip.closing}</p>`
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
          // Detekuj formát podle přípony (přechodné období: může být .pdf nebo .html)
          const isPdf = /\.pdf$/i.test(invoice.pdf_path)
          if (!isPdf) {
            const text = new TextDecoder('utf-8').decode(bytes)
            if (text && /<html[\s>]/i.test(text)) html = text
          }
          const b64 = btoa(Array.from(bytes, (b: number) => String.fromCharCode(b)).join(''))
          const ext = isPdf ? 'pdf' : 'html'
          attachments.push({ content: b64, filename: `${invoiceLabel.replace(/ /g, '-')}-${invoice.number}.${ext}` })
        }
      } catch { /* ignore */ }
    }
    // Pro KF z e-shopu (shop_final) přidej Google review CTA tlačítko
    if (invoice.type === 'shop_final') {
      templateHtml = templateHtml + googleReviewBlock(custLang)
    }
    if (!html) html = wrapInBrandedLayout(localizeBodyLinks(templateHtml, custLang), custLang)

    // Admin kopie do info@motogo24.cz vždy v CZ — rerendrujeme CZ verzi
    let adminHtml = html
    let adminSubject = subject
    if (custLang !== 'cs') {
      const csSnip = invoiceEmailSnippets(invoice.type || 'issued', 'cs', { invoice_number: invoice.number || '' })
      const csBody = `<p>${csSnip.intro}</p>
<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0">
  <table style="width:100%;border-collapse:collapse;font-size:14px;color:#374151">
    <tr><td style="padding:4px 0;font-weight:700">${csSnip.tableLabels.num}</td><td>${invoice.number}</td></tr>
    <tr><td style="padding:4px 0;font-weight:700">${csSnip.tableLabels.issue}</td><td>${fmtDate(invoice.issue_date)}</td></tr>
    <tr><td style="padding:4px 0;font-weight:700">${csSnip.tableLabels.due}</td><td>${fmtDate(invoice.due_date)}</td></tr>
    ${invoice.variable_symbol ? `<tr><td style="padding:4px 0;font-weight:700">${csSnip.tableLabels.vs}</td><td>${invoice.variable_symbol}</td></tr>` : ''}
    <tr><td style="padding:4px 0;font-weight:700">${csSnip.tableLabels.total}</td><td style="font-weight:700;color:#1a8a18">${fmtPrice(invoice.total)} Kč</td></tr>
  </table>
</div>
<p>${csSnip.outro}</p>
<p>${csSnip.closing}</p>`
      const csBodyWithReview = invoice.type === 'shop_final' ? csBody + googleReviewBlock('cs') : csBody
      adminHtml = wrapInBrandedLayout(csBodyWithReview, 'cs')
      adminSubject = csSnip.subject
    }

    const emailPayload: Record<string, unknown> = { from: FROM_EMAIL, reply_to: REPLY_TO, to: recipientEmail, subject, html }
    if (attachments.length > 0) emailPayload.attachments = attachments
    const result = await sendWithRetry(emailPayload)

    // Send copy to info@
    if (result.success) {
      try { await sendWithRetry({ from: FROM_EMAIL, to: REPLY_TO, subject: `[Kopie${custLang !== 'cs' ? ` — zákazník ${custLang.toUpperCase()}` : ''}] ${adminSubject}`, html: adminHtml }) } catch {}
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
