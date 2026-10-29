import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { encode as base64Encode } from 'https://deno.land/std@0.177.0/encoding/base64.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { requireAdminOrService, forbidden } from '../_shared/auth.ts'
import { BRAND_TAGLINE, FOLLOW_US_LABELS, pickLang, resolveTemplateForLang as resolveTemplateShared } from '../_shared/email-translate.ts'
import { EMAIL_SLUG_FALLBACKS, logGearTemplateFallback } from '../_shared/email-gear-fallback.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://www.motogo24.cz'
const FB_URL = 'https://www.facebook.com/profile.php?id=61581614672839'
const IG_URL = 'https://www.instagram.com/moto.go24/'

// =============================================================================
// i18n — šablonové maily zákazníkům (handover/damage protokoly, oznámení…)
// 1:1 mechanismus jako send-booking-email: cache v email_templates.{subject,body}
// _translations[lang] + __src_<lang> hash; non-cz se přeloží přes Anthropic a
// zacachuje. Při JAKÉMKOLI selhání → CZ (mail vždy odejde — nic se nerozbije).
// =============================================================================
const SUPPORTED_LANGS = ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk']
const DEFAULT_LANG = 'cs'
function normalizeLang(lang: string | null | undefined): string {
  if (!lang) return DEFAULT_LANG
  const l = lang.toLowerCase().trim().slice(0, 2)
  return SUPPORTED_LANGS.includes(l) ? l : DEFAULT_LANG
}

// Lokalizované texty fixního layoutu (patička / help karta / podnadpis loga).
// Hlavička / „Sledujte nás“ = sdílené BRAND_TAGLINE / FOLLOW_US_LABELS (_shared/email-translate.ts, vč. uk).
const HELP_TITLE: Record<string, string> = {
  cs: 'Máte dotaz?', en: 'Have a question?', de: 'Haben Sie eine Frage?',
  nl: 'Heeft u een vraag?', es: '¿Tienes alguna pregunta?', fr: 'Une question ?', pl: 'Masz pytanie?',
  uk: 'Маєте запитання?',
}
const HELP_TEXT: Record<string, string> = {
  cs: 'Pokud budete mít jakýkoliv dotaz, jsme vám k dispozici.',
  en: 'If you have any questions, we are here to help.',
  de: 'Bei Fragen stehen wir Ihnen gerne zur Verfügung.',
  nl: 'Heeft u vragen? We staan voor u klaar.',
  es: 'Si tienes cualquier pregunta, estamos a tu disposición.',
  fr: 'Pour toute question, nous sommes à votre disposition.',
  pl: 'W razie jakichkolwiek pytań jesteśmy do Twojej dyspozycji.',
  uk: 'Якщо у вас виникнуть запитання, ми завжди раді допомогти.',
}
// ── i18n: dynamický překlad CZ šablony — sdílený modul _shared/email-translate.ts
// (cache + __src_<lang> s verzí promptu; při selhání CZ — mail vždy odejde).
function resolveTemplateForLang(
  supabase: ReturnType<typeof createClient>,
  tpl: { slug: string; subject: string | null; body_html: string; subject_translations: Record<string, string> | null; body_translations: Record<string, string> | null },
  lang: string,
): Promise<{ subject: string; body: string }> {
  return resolveTemplateShared(supabase, tpl, lang, 'send-email')
}

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

/** Wrap body HTML in unified MotoGo24 email layout (1:1 with invoice design + screen reference) */
function wrapInBrandedLayout(bodyHtml: string, lang = 'cs'): string {
  const L = SUPPORTED_LANGS.includes(lang) ? lang : 'cs'
  const header = `<div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:middle;padding-right:14px;width:52px"><img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
      <td style="vertical-align:middle">
        <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
        <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">${pickLang(BRAND_TAGLINE, L)}</div>
      </td>
    </tr></table>
  </div>`
  const helpCard = `<div style="margin:24px 32px 0;background:#0a1f15;border:2px solid #74FB71;border-radius:8px;padding:24px">
    <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">${pickLang(HELP_TITLE, L)}</div>
    <div style="color:#ffffff;font-size:13px;margin:0 0 16px">${pickLang(HELP_TEXT, L)}</div>
    <a href="mailto:info@motogo24.cz" style="display:inline-block;background:#74FB71;color:#0a1f15;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">info@motogo24.cz</a>
  </div>`
  const footer = `<div style="background:#0a1f15;padding:24px 32px;margin-top:24px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:top;padding-right:16px">
        <div style="border:1px solid #74FB71;border-radius:6px;padding:16px;color:#ffffff;font-size:12px;line-height:1.7">
          <div style="font-size:14px;font-weight:800;color:#ffffff">Motogo24</div>
          <div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">Bc. Petra Semor\u00e1dov\u00e1</div>
          <div style="color:#9ca3af">Mezn\u00e1 9, 393 01 Pelh\u0159imov</div>
          <div style="color:#9ca3af">I\u010cO: 21874263</div>
          <div><span style="color:#9ca3af">Telefon:</span> <span style="color:#74FB71">+420 774 256 271</span></div>
          <div><span style="color:#9ca3af">E-mail:</span> <span style="color:#74FB71">info@motogo24.cz</span></div>
          <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">www.motogo24.cz</span></div>
        </div>
      </td>
      <td style="vertical-align:top;width:120px;text-align:center">
        <img src="${SITE_URL}/gfx/qr-motogo24.png" alt="QR" width="110" height="110" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/>
      </td>
    </tr></table>
    <div style="text-align:center;margin-top:18px;padding-top:16px;border-top:1px solid #1f3a2c">
      <div style="color:#9ca3af;font-size:11px;letter-spacing:2px;margin-bottom:10px">${pickLang(FOLLOW_US_LABELS, L)}</div>
      <a href="${FB_URL}" style="display:inline-block;margin:0 6px;text-decoration:none" target="_blank" rel="noopener"><img src="${SITE_URL}/gfx/facebook-footer.svg" alt="Facebook" width="32" height="32" style="display:inline-block;border:0"/></a>
      <a href="${IG_URL}" style="display:inline-block;margin:0 6px;text-decoration:none" target="_blank" rel="noopener"><img src="${SITE_URL}/gfx/instagram-footer.svg" alt="Instagram" width="32" height="32" style="display:inline-block;border:0"/></a>
    </div>
  </div>`

  return `<!DOCTYPE html><html lang="${L}"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased">
  <div style="max-width:780px;margin:0 auto;background:#ffffff">
    ${header}
    <div style="padding:32px;color:#0f1a14;font-size:14px;line-height:1.7">${bodyHtml}</div>
    ${helpCard}
    ${footer}
  </div>
</body></html>`
}

type Attachment = { filename: string; content: string }

/** Send email via Resend with 2 retries (exponential backoff) */
async function sendWithRetry(
  emailData: { from: string; to: string; subject: string; html: string; reply_to?: string; attachments?: Attachment[] },
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

  // Bezpečnostní gate: odesílání e-mailů (vč. raw_html) jen service_role nebo admin.
  const auth = await requireAdminOrService(req)
  if (!auth.ok) return forbidden(CORS, auth.reason)

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const body = await req.json()
    const {
      to,
      template_slug,
      template_vars = {},
      customer_id,
      booking_id,
      order_id,
      language,
      subject: subjectOverride,
      raw_html,
      raw_body,
      test = false,
      // send-broadcast/ManualSendTab compatibility fields
      channel,
      type,
      invoice_id,
      // Přílohy: buď přímo base64 ({filename, content}), nebo cesty v bucketu `documents`
      // ({filename, path}) — ty se zde stáhnou a zakódují do base64.
      attachments: inlineAttachments = [],
      attachment_paths = [],
    } = body

    // If called with type='invoice' + invoice_id, delegate to invoice logic
    if (type === 'invoice' && invoice_id) {
      return await handleInvoiceEmail(supabase, invoice_id)
    }

    // i18n: jazyk zákazníka — 1) explicit `language`, 2) RPC z DB, 3) 'cs'.
    // Týká se POUZE šablonových mailů (template_slug); raw_html/raw_body zůstávají
    // tak, jak je admin složil (default cs layout).
    let custLang = normalizeLang(language)
    if (!language && (booking_id || order_id || customer_id)) {
      try {
        const { data: langData } = await supabase.rpc('detect_customer_language', {
          p_user_id:    customer_id || null,
          p_booking_id: booking_id || null,
          p_order_id:   order_id || null,
        })
        custLang = normalizeLang(langData as string | null)
      } catch { /* ignore — zůstane 'cs' */ }
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
      // Load from email_templates table (vč. překladových cache sloupců)
      const loadTpl = (s: string) => supabase
        .from('email_templates')
        .select('slug, name, subject, body_html, active, subject_translations, body_translations')
        .eq('slug', s)
        .eq('active', true)
        .maybeSingle()
      let { data: tpl, error: tplErr } = await loadTpl(template_slug)
      let usedFallbackTpl = false
      // Náhradní šablona (2026-10-23): protokol výpůjčky výbavy (handover_protocol_gear_sent)
      // bez vlastní šablony ve Velínu → obecný handover_protocol_sent, ať mail vždy odejde
      // (submit-handover-protocol i Velín). Použití náhrady → debug_log email_template_fallback.
      const fbSlug = Object.hasOwn(EMAIL_SLUG_FALLBACKS, template_slug) ? EMAIL_SLUG_FALLBACKS[template_slug] : ''
      if ((tplErr || !tpl) && fbSlug) {
        ({ data: tpl, error: tplErr } = await loadTpl(fbSlug))
        if (tpl) {
          usedFallbackTpl = true
          await logGearTemplateFallback(supabase, 'send-email', { slug: template_slug, used: fbSlug, booking_id: booking_id || null })
        }
      }

      if (tplErr || !tpl) {
        return jsonResponse({
          success: false,
          error: `Template "${template_slug}" not found or inactive`,
        }, 404)
      }

      // Přeloží šablonu do jazyka zákazníka (cache + Anthropic, CZ fallback).
      const resolved = await resolveTemplateForLang(supabase, tpl as Parameters<typeof resolveTemplateForLang>[1], custLang)
      const renderedBody = renderTemplate(resolved.body || '', template_vars)
      subject = subjectOverride || renderTemplate(resolved.subject || '', template_vars) || `${tpl.name} — MOTO GO 24`
      html = wrapInBrandedLayout(renderedBody, custLang)
      // Náhradní šablona: log (message_log / sent_emails) dál pod VYŽÁDANÝM slugem — protokol výbavy
      // musí jít ve Velínu odlišit od motorkového (náhrada je vidět v debug_log).
      resolvedSlug = usedFallbackTpl ? template_slug : tpl.slug
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

    // Resolve attachments (inline base64 + storage paths z bucketu `documents`)
    // attachmentsMeta = {filename, storage_path} pro `sent_emails.attachments_meta`,
    // aby Velín → Dokumenty → Zaslané maily přílohy ZOBRAZIL (náhled/stažení).
    const attachments: Attachment[] = []
    const attachmentsMeta: { filename: string; storage_path: string | null }[] = []
    for (const a of (Array.isArray(inlineAttachments) ? inlineAttachments : [])) {
      if (a?.filename && a?.content) {
        attachments.push({ filename: a.filename, content: a.content })
        attachmentsMeta.push({ filename: a.filename, storage_path: a.storage_path || null })
      }
    }
    for (const a of (Array.isArray(attachment_paths) ? attachment_paths : [])) {
      if (!a?.path) continue
      const filename = a.filename || a.path.split('/').pop() || 'priloha'
      // I když se download nepovede, příloha se reálně připojuje přes path níže — zaeviduj ji.
      attachmentsMeta.push({ filename, storage_path: a.path })
      try {
        const { data: file, error: dlErr } = await supabase.storage.from('documents').download(a.path)
        if (dlErr || !file) continue
        const buf = new Uint8Array(await file.arrayBuffer())
        attachments.push({ filename, content: base64Encode(buf) })
      } catch (e) { /* příloha se nepřipojí, e-mail přesto odejde */ }
    }

    // Send via Resend
    const result = await sendWithRetry({ from: FROM_EMAIL, reply_to: REPLY_TO, to, subject, html, attachments: attachments.length ? attachments : undefined })

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

    // Also log to sent_emails (Velín → Dokumenty → Zaslané maily).
    // POZOR: sloupce MUSÍ odpovídat živé tabulce (vytvořené v dashboardu, ne migrací).
    // `recipient_id` v živé `sent_emails` NEEXISTUJE → jeho uvedení shazovalo CELÝ
    // insert (tichý catch) a mail se do „Zaslané maily" NEULOŽIL (např. booking_qr_payment).
    // send-booking-email/send-cancellation-email ho proto neuvádějí a logují korektně —
    // sjednoceno na stejný ověřený tvar sloupců.
    try {
      await supabase.from('sent_emails').insert({
        template_slug: resolvedSlug || 'manual',
        recipient_email: to,
        booking_id: booking_id || null,
        subject,
        body_html: html,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        provider_id: result.provider_id || null,
        attachments_meta: attachmentsMeta.length ? attachmentsMeta : null,
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

  // DEDUP: faktura se smí odeslat zákazníkovi JEN JEDNOU. Při dvojím spuštění
  // (StrictMode re-mount, dvojklik, retry edge/Resend) by jinak odešla 2×.
  // Pokud už za posledních 10 min existuje `sent` e-mail s tímto číslem dokladu
  // na stejnou adresu, druhé odeslání přeskočíme (idempotentní jako jinde v repu).
  try {
    const since = new Date(Date.now() - 10 * 60 * 1000).toISOString()
    const { data: dup } = await supabase
      .from('message_log')
      .select('id')
      .eq('channel', 'email')
      .eq('recipient_email', profile.email)
      .eq('status', 'sent')
      .ilike('content_preview', `%${invoice.number}%`)
      .gte('created_at', since)
      .limit(1)
    if (dup && dup.length > 0) {
      return jsonResponse({ success: true, deduped: true })
    }
  } catch (e) { /* dedup nesmí zablokovat odeslání při chybě dotazu */ }

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

  // Příloha: PDF (nebo HTML fallback) dokladu ze storage bucketu `documents`.
  // pdf_path plní Velín (renderAndStoreInvoicePdf) před voláním této funkce.
  const attachments: Attachment[] = []
  const attachmentsMeta: { filename: string; storage_path: string | null }[] = []
  if (invoice.pdf_path) {
    const ext = /\.pdf$/i.test(invoice.pdf_path as string) ? 'pdf' : 'html'
    const filename = `${invoiceLabel.replace(/ /g, '-')}-${invoice.number}.${ext}`
    attachmentsMeta.push({ filename, storage_path: invoice.pdf_path as string })
    try {
      const { data: blob } = await supabase.storage.from('documents').download(invoice.pdf_path as string)
      if (blob) {
        const bytes = new Uint8Array(await blob.arrayBuffer())
        attachments.push({ filename, content: base64Encode(bytes) })
      }
    } catch (e) { /* příloha se nepřipojí, e-mail přesto odejde */ }
  }

  const result = await sendWithRetry({ from: FROM_EMAIL, reply_to: REPLY_TO, to: profile.email, subject, html, attachments: attachments.length ? attachments : undefined })

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
    // `recipient_id` neuvádět — v živé sent_emails neexistuje (viz pozn. výše), jinak
    // by tichý catch zahodil celý insert a doklad by se neuložil do „Zaslané maily".
    await supabase.from('sent_emails').insert({
      template_slug: 'invoice',
      recipient_email: profile.email,
      booking_id: invoice.booking_id || null,
      subject,
      body_html: html,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error || null,
      provider_id: result.provider_id || null,
      attachments_meta: attachmentsMeta.length ? attachmentsMeta : null,
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
