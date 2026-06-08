import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { renderEmail, normalizeLang, helpCardLabels, type Lang } from './i18n.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://www.motogo24.cz'
const FB_URL = 'https://www.facebook.com/profile.php?id=61581614672839'
const IG_URL = 'https://www.instagram.com/moto.go24/'

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
// Velín edituje jen CZ; pro non-cz se šablona přeloží přes Claude a zacachuje
// zpět do email_templates.{subject,body}_translations[lang] + __src_<lang> hash.
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
    '- Keep ALL template placeholders like {{var}} EXACTLY unchanged (e.g. {{booking_number}}, {{refund_amount}}, {{site_url}}).',
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

/** Wrap body HTML in unified MotoGo24 email layout (1:1 with invoice design + screen reference) */
function wrapInBrandedLayout(bodyHtml: string, lang: Lang = 'cs'): string {
  const hc = helpCardLabels(lang)
  const custSite = siteForLang(lang)
  const webLabel = webLabelForLang(lang)
  // Vertik\u00e1ln\u00ed hlavi\u010dka 1:1 s brand logem
  const header = `<div style="background:#000000;padding:36px 24px;text-align:center">
    <img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="110" height="110" style="display:inline-block;border:0;margin-bottom:16px"/>
    <div style="color:#ffffff;font-size:32px;font-weight:900;letter-spacing:3px;line-height:1">MOTO GO 24</div>
    <div style="color:#ffffff;font-size:11px;font-weight:400;letter-spacing:6px;margin-top:8px">P\u016eJ\u010cOVNA MOTOREK</div>
  </div>`
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

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/** Download file from Supabase Storage and return as base64 */
async function downloadAsBase64(supabase: any, path: string): Promise<string | null> {
  try {
    const { data } = await supabase.storage.from('documents').download(path)
    if (!data) return null
    const bytes = new Uint8Array(await data.arrayBuffer())
    return btoa(Array.from(bytes, (b: number) => String.fromCharCode(b)).join(''))
  } catch { return null }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const reqBody = await req.json()
    let {
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
      language,  // i18n: cs/en/de/nl/es/fr/pl, default 'cs'
    } = reqBody

    // If no email provided but booking_id exists, look up from profile
    if (!customer_email && booking_id) {
      try {
        const { data: bk } = await supabase.from('bookings')
          .select('user_id, profiles(full_name, email), motorcycles(model)')
          .eq('id', booking_id).single()
        if (bk?.profiles) {
          customer_email = (bk.profiles as any).email
          if (!customer_name) customer_name = (bk.profiles as any).full_name
          if (!motorcycle) motorcycle = (bk.motorcycles as any)?.model
        }
      } catch { /* ignore */ }
    }

    if (!customer_email) {
      return new Response(JSON.stringify({ error: 'No customer email' }), {
        status: 400,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Idempotency — webhook charge.refunded může spustit retry safety-net pro
    // booking, který už storno mail dostal (cancel_booking_tracked nebo Stripe portal).
    // Pokud se mail za posledních 30 min úspěšně odeslal, druhý nepošleme.
    // Force=true v body request přepíše idempotency (admin manuální dotaz "pošli znovu").
    const force = (reqBody as any).force === true
    if (booking_id && !force) {
      try {
        const { data: existing } = await supabase.from('sent_emails')
          .select('id, sent_at, status')
          .eq('booking_id', booking_id)
          .eq('template_slug', 'booking_cancelled')
          .eq('status', 'sent')
          .gte('sent_at', new Date(Date.now() - 30 * 60 * 1000).toISOString())
          .limit(1)
        if (existing?.length) {
          await supabase.from('debug_log').insert({
            source: 'send-cancellation-email',
            action: 'idempotent_skip',
            status: 'info',
            request_data: { booking_id, existing_email_id: existing[0].id, existing_sent_at: existing[0].sent_at },
          }).then(() => {}, () => {})
          return new Response(JSON.stringify({ success: true, skipped: 'already_sent', existing_id: existing[0].id }), {
            status: 200,
            headers: { ...CORS, 'Content-Type': 'application/json' },
          })
        }
      } catch { /* non-fatal — continue to send */ }
    }

    // ── Auto Stripe refund + dobropis ──
    const attachments: { content: string; filename: string }[] = []

    if (booking_id) {
      try {
        // Load booking data for refund calculation
        const { data: booking } = await supabase.from('bookings')
          .select('start_date, end_date, total_price, payment_status, stripe_payment_intent_id, booking_source, motorcycles(model)')
          .eq('id', booking_id).single()

        if (booking) {
          if (!start_date) start_date = booking.start_date
          if (!end_date) end_date = booking.end_date
          if (!motorcycle) motorcycle = (booking.motorcycles as any)?.model || ''
          if (!source && booking.booking_source) source = booking.booking_source

          // 'refund_pending' (Čeká na vrácení) = storno zaplacené rezervace, kde Stripe
          // refund ještě nedoběhl → bereme stejně jako 'paid', ať se refund + dobropis
          // dotáhne (process-refund je idempotentní a bránu na 'refund_pending' propustí).
          const wasPaid = booking.payment_status === 'paid' || booking.payment_status === 'refund_pending'
          const alreadyRefunded = booking.payment_status === 'refunded' || booking.payment_status === 'partial_refund'

          // Vstupní diagnostika — admin vidí přesně co edge fn dostala a co je v DB.
          // Klíč k debugu storno mailu bez přílohy: payment_status + stripe_payment_intent_id + refund_amount.
          await supabase.from('debug_log').insert({
            source: 'send-cancellation-email',
            action: 'cancel_started',
            status: 'info',
            request_data: {
              booking_id,
              payment_status: booking.payment_status,
              has_stripe_pi: !!booking.stripe_payment_intent_id,
              total_price: booking.total_price,
              body_refund_amount: refund_amount,
              body_refund_percent: refund_percent,
              wasPaid,
              alreadyRefunded,
            },
          }).then(() => {}, () => {})

          // Calculate refund based on storno policy if not provided
          if ((wasPaid || alreadyRefunded) && booking.total_price > 0 && refund_percent == null) {
            const hoursUntilStart = (new Date(booking.start_date).getTime() - Date.now()) / 3600000
            if (hoursUntilStart > 7 * 24) { refund_percent = 100 }
            else if (hoursUntilStart > 48) { refund_percent = 50 }
            else { refund_percent = 0 }
            refund_amount = Math.round(booking.total_price * (refund_percent || 0) / 100)
          }

          // Process-refund je idempotentní: pro paid+nepoužitý refund udělá Stripe refund + dobropis,
          // pro already_refunded (předchozí pokus padl po Stripe kroku) jen dohraje PDF dobropis.
          // Voláme tedy bez guardu na alreadyRefunded — díky tomu se i recovery scenario doplní příloha.
          const hdrs = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`, 'apikey': SUPABASE_SERVICE_KEY }
          // process-refund si chybějící stripe_payment_intent_id umí dohledat ze
          // stripe_session_id (viz process-refund), proto ho zde už NEvyžadujeme jako
          // tvrdou podmínku — jinak by paid rezervace bez naplněného PI sloupce (web
          // rezervace, race s webhookem) refund tiše přeskočila a Stripe by o vrácení
          // vůbec nevěděl. Když PI ani session neexistují, process-refund vrátí
          // `no_stripe_payment` a níže to zalogujeme.
          const willCallRefund = (wasPaid || alreadyRefunded) && (refund_amount > 0 || alreadyRefunded)
          if (willCallRefund) {
            try {
              const refundRes = await fetch(`${SUPABASE_URL}/functions/v1/process-refund`, {
                method: 'POST', headers: hdrs,
                body: JSON.stringify({ booking_id, amount: refund_amount, reason: 'cancellation' }),
              })
              const refundData = await refundRes.json().catch(() => ({}))
              if (refundData.success) {
                console.log(`Refund OK (already=${refundData.already_refunded ? 'yes' : 'no'}, amount=${refund_amount})`)
              } else {
                console.warn('process-refund returned error:', refundData.code || refundData.error)
                await supabase.from('debug_log').insert({
                  source: 'send-cancellation-email',
                  action: 'refund_call_failed',
                  status: 'error',
                  error_message: String(refundData.code || refundData.error || 'unknown'),
                  request_data: { booking_id, refund_amount },
                  response_data: refundData,
                }).then(() => {}, () => {})
              }
            } catch (e) {
              console.warn('Auto Stripe refund failed:', e)
              await supabase.from('debug_log').insert({
                source: 'send-cancellation-email',
                action: 'refund_call_exception',
                status: 'error',
                error_message: (e as Error).message,
                request_data: { booking_id, refund_amount },
              }).then(() => {}, () => {})
            }
          }

          // Fetch the credit_note created by process-refund (source='refund') and attach it.
          // Storno podmínky:
          //   ≥ 7 dní před startem  → 100 % refund → credit_note 100 %
          //   2–7 dní před startem  → 50 % refund  → credit_note 50 %
          //   < 2 dny před startem  → 0 % refund   → ŽÁDNÝ credit_note (nic se nevrací)
          // Velín admin storno posílá `refund_percent: 100` natvrdo (ignoruje storno podmínky).
          //
          // RECOVERY: Pokud lookup najde credit_note bez pdf_path (PDFShift fail / silent error),
          // nebo soubor v Storage nestáhne, zavoláme process-refund znovu (idempotentní recovery
          // přes ensureCreditNotePdf — viz STATE_6 2026-05-08). Max 3 pokusy.
          if (refund_amount > 0) {
            let attached = false
            for (let attempt = 0; attempt < 3 && !attached; attempt++) {
              try {
                const { data: cnRows } = await supabase.from('invoices')
                  .select('id, number, pdf_path')
                  .eq('booking_id', booking_id)
                  .or('type.eq.credit_note,and(type.eq.payment_receipt,source.eq.cancellation)')
                  .neq('status', 'cancelled')
                  .order('created_at', { ascending: false }).limit(1)
                const cn = cnRows?.[0]
                if (cn?.pdf_path) {
                  const path = cn.pdf_path as string
                  const b64 = await downloadAsBase64(supabase, path)
                  if (b64) {
                    const ext = path.toLowerCase().endsWith('.pdf') ? 'pdf' : 'html'
                    attachments.push({ content: b64, filename: `Dobropis-${cn.number || 'DB'}.${ext}` })
                    attached = true
                    await supabase.from('debug_log').insert({
                      source: 'send-cancellation-email',
                      action: 'credit_note_attached',
                      status: 'ok',
                      request_data: { booking_id, attempt, invoice_id: cn.id, ext },
                    }).then(() => {}, () => {})
                    break
                  }
                }
                // Recovery — credit_note row chybí, nebo má pdf_path null, nebo download null.
                // Zavolej process-refund znovu (idempotentní, dovystaví PDF), pak retry lookup.
                if (attempt < 2) {
                  await supabase.from('debug_log').insert({
                    source: 'send-cancellation-email',
                    action: 'credit_note_recovery_attempt',
                    status: 'warning',
                    request_data: { booking_id, attempt, has_row: !!cn, has_pdf_path: !!cn?.pdf_path },
                  }).then(() => {}, () => {})
                  try {
                    await fetch(`${SUPABASE_URL}/functions/v1/process-refund`, {
                      method: 'POST', headers: hdrs,
                      body: JSON.stringify({ booking_id, amount: refund_amount, reason: 'cancellation_retry' }),
                    })
                  } catch { /* ignore — další iterace zkusí znovu */ }
                  await new Promise(r => setTimeout(r, 2500)) // PDFShift má cca 2-5s
                }
              } catch (e) { console.warn('Credit note lookup attempt', attempt, 'failed:', (e as Error).message) }
            }
            if (!attached) {
              await supabase.from('debug_log').insert({
                source: 'send-cancellation-email',
                action: 'credit_note_attach_failed',
                status: 'error',
                error_message: 'Credit note attachment missing after 3 retries — mail goes without PDF',
                request_data: { booking_id, refund_amount, refund_percent },
              }).then(() => {}, () => {})
            }
          }
        }
      } catch (e) { console.warn('Auto-refund lookup failed:', e) }
    }

    const vars: Record<string, string> = {
      customer_name: customer_name || '',
      booking_number: (booking_id || '').slice(-8).toUpperCase(),
      motorcycle: motorcycle || '',
      start_date: start_date || '',
      end_date: end_date || '',
      cancellation_reason: cancellation_reason || 'Neuvedeno',
      refund_amount: refund_amount ? Number(refund_amount).toLocaleString('cs-CZ') : '',
      refund_percent: refund_percent ? String(refund_percent) : '100',
      site_url: SITE_URL,
      refund_amount: refund_amount ? Number(refund_amount).toLocaleString('cs-CZ') : '',
      refund_percent: refund_percent ? String(refund_percent) : '',
      // {{business_card}} placeholder se v DB šabloně auto-vyčistí — brand header/footer je v wrapInBrandedLayout
    }

    // i18n \u2014 detekce jazyka z\u00e1kazn\u00edka
    let custLang: Lang = normalizeLang(language)
    if (!language && booking_id) {
      try {
        const { data: langData } = await supabase.rpc('detect_customer_language', {
          p_user_id: null, p_booking_id: booking_id, p_order_id: null,
        })
        custLang = normalizeLang(langData)
      } catch { /* ignore */ }
    }

    // {{site_url}} → doména zákazníka (.cz pro cs, .com jinak). Vars se sestavily
    // před detekcí jazyka, takže přepíšeme až teď.
    vars.site_url = siteForLang(custLang)

    // Try web-specific template first if source=web
    const slugsToTry = source === 'web'
      ? ['web_booking_cancelled', 'booking_cancelled']
      : ['booking_cancelled']

    let templateHtml = ''
    let subject = ''
    let dbAttachmentsList: string[] = []

    for (const trySlug of slugsToTry) {
      const { data: tpl } = await supabase
        .from('email_templates')
        .select('slug, name, subject, body_html, active, attachments, subject_translations, body_translations')
        .eq('slug', trySlug)
        .eq('active', true)
        .maybeSingle()

      if (tpl?.body_html) {
        // Velín = jen CZ. Non-cz → dynamický překlad přes API (cache + hash).
        const resolved = await resolveTemplateForLang(supabase, tpl as any, custLang)
        templateHtml = renderTemplate(resolved.body, vars)
        subject = renderTemplate(resolved.subject, vars)
        if (Array.isArray(tpl.attachments)) {
          dbAttachmentsList = tpl.attachments as string[]
        }
        break
      }
    }

    // Velín admin-configured attachments z email_templates.attachments — etalon ve Velíně.
    // Hardcoded refund flow výše už zkusil přiložit dobropis za určitých podmínek (wasPaid + refund_amount > 0
    // nebo 0%). Pokud admin v UI zaškrtl "Dobropis" a v mailu ještě není, dohledej cokoliv co se kvalifikuje.
    if (dbAttachmentsList.includes('Dobropis')
        && booking_id
        && !attachments.some(a => /dobropis|credit/i.test(a.filename))) {
      try {
        const { data: cn } = await supabase.from('invoices')
          .select('id, number, pdf_path, type')
          .eq('booking_id', booking_id)
          .or('type.eq.credit_note,and(type.eq.payment_receipt,source.eq.cancellation)')
          .neq('status', 'cancelled')
          .order('created_at', { ascending: false })
          .limit(1)
        if (cn?.length && cn[0].pdf_path) {
          const b64 = await downloadAsBase64(supabase, cn[0].pdf_path)
          if (b64) {
            const ext = /\.pdf$/i.test(cn[0].pdf_path) ? 'pdf' : 'html'
            attachments.push({ content: b64, filename: `Dobropis-${cn[0].number || 'DB'}.${ext}` })
          }
        }
      } catch { /* ignore */ }
    }

    // i18n hardcoded p\u0159eklady (priorita 2 \u2014 booking_cancelled je v _shared/i18n.ts)
    if (!templateHtml) {
      const i18nResult = renderEmail('booking_cancelled', custLang, vars)
      if (i18nResult) {
        subject = i18nResult.subject
        templateHtml = i18nResult.body
      }
    }

    // Legacy fallback (priorita 3 \u2014 cs only)
    if (!subject) {
      subject = `Va\u0161e rezervace \u010d. ${vars.booking_number} motocyklu u MotoGo24 byla \u00fasp\u011b\u0161n\u011b stornov\u00e1na`
    }
    if (!templateHtml) {
      templateHtml = `
        <p>Dobr\u00fd den,</p>
        <p>potvrzujeme, \u017ee va\u0161e rezervace \u010d. <strong>${vars.booking_number}</strong> motocyklu u MotoGo24 byla \u00fasp\u011b\u0161n\u011b stornov\u00e1na.</p>
        <p>Pokud jste storno nahl\u00e1sili alespo\u0148 7 dn\u00ed p\u0159ed za\u010d\u00e1tkem n\u00e1jemn\u00ed doby, vr\u00e1tili jsme v\u00e1m platbu na p\u016fvodn\u00ed kartu \u2014 pen\u00edze obvykle doraz\u00ed do 5\u20137 pracovn\u00edch dn\u016f.</p>
        <p>V p\u0159\u00edpad\u011b dotaz\u016f n\u00e1s nev\u00e1hejte kontaktovat.</p>
        <p>D\u011bkujeme a t\u011b\u0161\u00edme se, \u017ee v\u00e1s p\u0159iv\u00edt\u00e1me p\u0159i dal\u0161\u00ed p\u0159\u00edle\u017eitosti.</p>
        <p>T\u00fdm MotoGo24</p>`
    }

    templateHtml = localizeBodyLinks(templateHtml, custLang)
    const html = wrapInBrandedLayout(templateHtml, custLang)

    // Admin kopie do info@motogo24.cz v\u017edy v CZ \u2014 rerendrujeme pokud z\u00e1kazn\u00edk m\u00e1 jin\u00fd jazyk
    let adminHtml = html
    let adminSubject = subject
    if (custLang !== 'cs') {
      let csTemplateHtml = ''
      let csSubject = ''
      const csI18n = renderEmail('booking_cancelled', 'cs', vars)
      if (csI18n) { csSubject = csI18n.subject; csTemplateHtml = csI18n.body }
      if (csTemplateHtml) {
        adminHtml = wrapInBrandedLayout(csTemplateHtml, 'cs')
        adminSubject = csSubject
      }
    }

    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), {
        status: 500,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Send via Resend with Reply-To + dobropis attachment
    const emailPayload: Record<string, unknown> = {
      from: FROM_EMAIL,
      reply_to: REPLY_TO,
      to: customer_email,
      subject,
      html,
    }
    if (attachments.length > 0) {
      emailPayload.attachments = attachments
    }
    const result = await sendWithRetry(emailPayload)

    // Admin kopie do info@motogo24.cz — vždy v CZ (rerendrováno výše),
    // bez příloh. Pokud zákazník má jiný jazyk, prefix "[Kopie — zákazník XX]".
    if (result.success) {
      try {
        await sendWithRetry({
          from: FROM_EMAIL,
          to: REPLY_TO,
          subject: `[Kopie${custLang !== 'cs' ? ` — zákazník ${custLang.toUpperCase()}` : ''}] ${adminSubject}`,
          html: adminHtml,
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
