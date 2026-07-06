import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { renderEmail, normalizeLang, helpCardLabels, renderDoorCodesReleasedBlock, renderDocsRequiredBlock, type Lang } from './i18n.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const PDFSHIFT_API_KEY = Deno.env.get('PDFSHIFT_API_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://www.motogo24.cz'
const PUBLIC_QR_TARGET = 'https://www.motogo24.cz'
const FB_URL = 'https://www.facebook.com/profile.php?id=61581614672839'
const IG_URL = 'https://www.instagram.com/moto.go24/'
// Funkční odkazy na recenze/profily používané v mailech (Google / Facebook / Instagram).
// Slouží jako fallback, když nejsou nastavené v app_settings.
// Google: oficiální odkaz na formulář recenze z Google Business Profile (Požádat o recenzi).
const GOOGLE_REVIEW_URL_DEFAULT = 'https://g.page/r/CUmeYvk-sNf6EBM/review'
const FACEBOOK_REVIEW_URL_DEFAULT = 'https://www.facebook.com/people/MotoGo24/61581614672839/?sk=reviews'
const INSTAGRAM_REVIEW_URL_DEFAULT = 'https://www.instagram.com/moto.go24/'
const FIRMY_REVIEW_URL_DEFAULT = 'https://www.firmy.cz/detail/14009052-motogo24-mezna.html'

// ── i18n: doména zákazníka dle jazyka ───────────────────────────────────────
// Stejný vzor jako process-payment/stripe-customer.ts a generate-document:
// cs → motogo24.cz, ostatní podporované jazyky → motogo24.com.
// Asset obrázky (logo, sociální ikony) zůstávají na .cz — jsou hostované tam.
const DOMAIN_INTL = 'https://motogo24.com'
/** Plná URL domény zákazníka (pro odkazy / QR). cs → SITE_URL (.cz). */
function siteForLang(lang: string): string {
  return lang === 'cs' ? SITE_URL : DOMAIN_INTL
}
/** Webový label bez protokolu do patičky. */
function webLabelForLang(lang: string): string {
  return lang === 'cs' ? 'motogo24.cz' : 'motogo24.com'
}
/** Přepiš URL odkazy na motogo24.cz → zákazníkovu doménu (jen non-cs).
 *  Mění POUZE `http(s)://(www.)motogo24.cz...` v TĚLE mailu — e-mail
 *  `info@motogo24.cz` (mailto / text) se nemění. Asset obrázky (logo,
 *  ikony) jsou jen ve `wrapInBrandedLayout`, kam se tato fce neaplikuje. */
function localizeBodyLinks(html: string, lang: string): string {
  if (lang === 'cs' || !html) return html
  return html.replace(/https?:\/\/(?:www\.)?motogo24\.cz/gi, DOMAIN_INTL)
}

// ── i18n: dynamický překlad CZ mailové šablony přes Anthropic API ────────────
// Velín edituje jen CZ (subject + body_html). Pro non-cz zákazníka se CZ šablona
// přeloží přes Claude (haiku) a výsledek se zacachuje zpět do
// email_templates.{subject,body}_translations[lang] + per-lang hash zdroje
// (__src_<lang>) pro invalidaci, když admin CZ text změní. Zachová HTML i {{vary}}.
const TRANSLATE_MODEL = 'claude-haiku-4-5-20251001'
const LANG_NAMES: Record<string, string> = {
  en: 'English', de: 'German (Deutsch)', es: 'Spanish (Español)',
  fr: 'French (Français)', nl: 'Dutch (Nederlands)', pl: 'Polish (Polski)',
}

/** SHA-1 hex zdroje (detekce změny CZ šablony → invalidace cache). */
async function sha1Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('')
}

/** Přeloží subject+body RAW mailové šablony z CZ do cílového jazyka přes Anthropic.
 *  Překládá PŘED substitucí proměnných → cache je nezávislá na konkrétní rezervaci.
 *  Vrací {subject, body} nebo null při chybě (caller pak nechá CZ — mail aspoň odejde). */
async function translateEmailTemplate(subjectCz: string, bodyCz: string, lang: string): Promise<{ subject: string; body: string } | null> {
  if (!ANTHROPIC_API_KEY) return null
  const langName = LANG_NAMES[lang] || lang
  const system = [
    `You are a professional Czech-to-${langName} translator for MotoGo24 — a Czech motorcycle rental company.`,
    'Translate the provided JSON object with keys "subject" and "body". Output STRICTLY a valid JSON object with the same two keys and translated values.',
    'STRICT RULES:',
    `- Output language: ${langName} (${lang}). Natural, native, fluent.`,
    '- Preserve ALL HTML tags, attributes, inline styles and structure EXACTLY.',
    '- DO NOT translate or change: URLs, email addresses, phone numbers, prices, IČO, DIČ, brand names. Keep the company name "MotoGo24" unchanged. Keep currency "Kč" as is.',
    '- Keep ALL template placeholders like {{var}} EXACTLY unchanged (e.g. {{booking_number}}, {{customer_name}}, {{door_codes_block}}, {{site_url}}, {{total_price}}).',
    '- Do NOT add commentary, do NOT add markdown fences. Output ONLY the raw JSON object.',
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

/** Vyřeší subject+body DB šablony pro daný jazyk: cs → CZ originál; non-cz →
 *  čerstvý cache překlad, jinak přeloží přes API a zacachuje. Při selhání API
 *  vrátí CZ (mail vždy odejde). */
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
  if (fresh) {
    return { subject: (typeof subjT[lang] === 'string' && subjT[lang]) ? subjT[lang] : subjCz, body: bodyT[lang] }
  }
  const tr = await translateEmailTemplate(subjCz, bodyCz, lang)
  if (!tr) return { subject: subjCz, body: bodyCz } // API selhalo → CZ fallback
  // cache zpět do DB (best-effort, merge přes ostatní jazyky)
  try {
    const newSubjT = { ...subjT, [lang]: tr.subject, ['__src_' + lang]: srcHash }
    const newBodyT = { ...bodyT, [lang]: tr.body, ['__src_' + lang]: srcHash }
    await supabase.from('email_templates').update({ subject_translations: newSubjT, body_translations: newBodyT }).eq('slug', tpl.slug)
  } catch { /* ignore */ }
  return tr
}

const FOLLOW_US_LABEL: Record<string, string> = {
  cs: 'SLEDUJTE NÁS', en: 'FOLLOW US', de: 'FOLGEN SIE UNS', nl: 'VOLG ONS',
  es: 'SÍGUENOS', fr: 'SUIVEZ-NOUS', pl: 'OBSERWUJ NAS',
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

// Opraví odkazy na recenze v poděkovacím mailu. Šablona ve Velíně má odkazy
// natvrdo (Google nevyplněný `writereview?placeid=PLACE_ID` → 404, starý Facebook).
// Přepíšeme href podle viditelného textu odkazu (Google / Facebook) na správné URL
// a za Facebook doplníme stejně stylovaný odkaz na Firmy.cz. Nezávisí na {{proměnných}}.
// Idempotentní (Firmy.cz se nepřidá podruhé).
function fixReviewLinks(html: string): string {
  if (!html) return html
  let out = html
  out = out.replace(/(<a\b[^>]*\bhref=")[^"]*("[^>]*>\s*Google\s*<\/a>)/gi, `$1${GOOGLE_REVIEW_URL_DEFAULT}$2`)
  out = out.replace(/(<a\b[^>]*\bhref=")[^"]*("[^>]*>\s*Facebook\s*<\/a>)/gi, `$1${FACEBOOK_REVIEW_URL_DEFAULT}$2`)
  // Pokud má šablona odkaz na Instagram přímo v textu (recenze Instagram neumí),
  // převeď ho na Firmy.cz. Týká se jen těla review-mailu, ne patičky „Sledujte nás“.
  out = out.replace(/<a\b[^>]*>[\s\S]*?<\/a>/gi, (a) =>
    (/instagram\.com/i.test(a) || /<a\b[^>]*>\s*Instagram\s*<\/a>/i.test(a))
      ? a.replace(/href="[^"]*"/i, `href="${FIRMY_REVIEW_URL_DEFAULT}"`).replace(/>[\s\S]*?<\/a>/i, '>Firmy.cz</a>')
      : a,
  )
  if (!/firmy\.cz/i.test(out)) {
    out = out.replace(
      /<a\b[^>]*\bhref="[^"]*facebook\.com[^"]*"[^>]*>\s*Facebook\s*<\/a>/i,
      (fbAnchor) => {
        const firmyAnchor = fbAnchor
          .replace(/href="[^"]*"/i, `href="${FIRMY_REVIEW_URL_DEFAULT}"`)
          .replace(/>\s*Facebook\s*<\/a>/i, '>Firmy.cz</a>')
        return `${fbAnchor}, ${firmyAnchor}`
      },
    )
  }
  return out
}

function googleReviewBlock(lang: string, url: string): string {
  const l = REVIEW_BLOCK_LABELS[lang] || REVIEW_BLOCK_LABELS.cs
  const href = url || GOOGLE_REVIEW_URL_DEFAULT
  return `<div style="background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px;margin:24px 0;text-align:center">
  <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">${l.title}</div>
  <div style="color:#ffffff;font-size:13px;margin:0 0 16px">${l.body}</div>
  <a href="${href}" target="_blank" rel="noopener" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">${l.cta}</a>
</div>`
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

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
  // Doména zákazníka — odkazy/QR/label v patičce vedou na .cz (cs) / .com (ostatní).
  // Asset obrázky (logo, ikony) zůstávají na SITE_URL (.cz), kde jsou hostované.
  const custSite = siteForLang(lang)
  const webLabel = webLabelForLang(lang)
  // Vertik\u00e1ln\u00ed hlavi\u010dka 1:1 s brand logem (ikona velk\u00e1 naho\u0159e, text pod n\u00ed)
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
  const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=8&data=${encodeURIComponent(custSite)}`
  const footer = `<div style="background:#000000;padding:24px 32px;margin-top:24px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:top;padding-right:16px">
        <div style="border:1px solid #74FB71;border-radius:6px;padding:16px;color:#ffffff;font-size:12px;line-height:1.7">
          <div style="font-size:14px;font-weight:800;color:#ffffff">Motogo24</div>
          <div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">Bc. Petra Semor\u00e1dov\u00e1</div>
          <div style="color:#9ca3af">Mezn\u00e1 9, 393 01 Pelh\u0159imov</div>
          <div style="color:#9ca3af">I\u010cO: 21874263</div>
          <div><span style="color:#9ca3af">Telefon:</span> <span style="color:#74FB71">+420 774 256 271</span></div>
          <div><span style="color:#9ca3af">E-mail:</span> <span style="color:#74FB71">info@motogo24.cz</span></div>
          <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">${webLabel}</span></div>
        </div>
      </td>
      <td style="vertical-align:top;width:130px;text-align:center">
        <a href="${custSite}" style="text-decoration:none"><img src="${qrUrl}" alt="${webLabel}" width="120" height="120" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/></a>
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

// Slug mapping: type -> email_templates.slug (with web/app variants)
function resolveSlug(type: string, source: string): string {
  const webPrefix = source === 'web' ? 'web_' : ''
  return webPrefix + type
}

// Fallback subjects when no template found
const FALLBACK_SUBJECTS: Record<string, (vars: Record<string, string>) => string> = {
  booking_reserved: (v) => `Va\u0161e rezervace \u010d. ${v.booking_number} motocyklu u MotoGo24 je potvrzena`,
  booking_completed: (v) => `D\u011bkujeme za vyu\u017eit\u00ed slu\u017eeb MotoGo24`,
  booking_modified: (v) => {
    const pd = Number((v.price_difference || '0').toString().replace(/\s/g, '').replace(',', '.')) || 0
    if (pd > 0) return `\u00daprava rezervace \u010d. ${v.booking_number} \u2014 doplatek ${v.price_difference} K\u010d \u2014 MOTO GO 24`
    if (pd < 0) return `\u00daprava rezervace \u010d. ${v.booking_number} \u2014 vr\u00e1cen\u00ed platby \u2014 MOTO GO 24`
    return `Zm\u011bna rezervace \u010d. ${v.booking_number} \u2014 MOTO GO 24`
  },
  voucher_purchased: (v) => `V\u00e1\u0161 d\u00e1rkov\u00fd poukaz od MotoGo24`,
  booking_abandoned: (v) => `Dokon\u010dete svou rezervaci \u010d. ${v.booking_number} motocyklu u MotoGo24`,
  booking_abandoned_full: (v) => `Dokon\u010dete rezervaci \u010d. ${v.booking_number} \u2014 chyb\u00ed platba a doklady`,
  booking_missing_docs: (v) => `Nahrajte doklady k rezervaci \u010d. ${v.booking_number} \u2014 MotoGo24`,
  invoice_payment_receipt: (v) => `Platba p\u0159ijata \u2014 rezervace #${v.booking_number}, dopl\u0148te doklady \u2014 MotoGo24`,
  booking_cancelled: (v) => `Va\u0161e rezervace \u010d. ${v.booking_number} motocyklu u MotoGo24 byla \u00fasp\u011b\u0161n\u011b stornov\u00e1na`,
  sos_incident: () => `SOS \u2014 MotoGo24 je na cest\u011b`,
  door_codes: (v) => `P\u0159\u00edstupov\u00e9 k\u00f3dy k pobo\u010dce \u2014 rezervace \u010d. ${v.booking_number}`,
  shop_order_confirmed: (v) => `Objedn\u00e1vka \u010d. ${v.order_number} p\u0159ijata \u2014 MOTO GO 24`,
  shop_order_shipped: (v) => `Objedn\u00e1vka \u010d. ${v.order_number} odesl\u00e1na \u2014 MOTO GO 24`,
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

/** Vrátí příponu souboru (bez tečky, lowercase) — `.pdf` nebo `.html`. */
function fileExt(path: string | null | undefined): 'pdf' | 'html' {
  if (path && /\.pdf$/i.test(path)) return 'pdf'
  return 'html'
}

/** HTML fallback pro voucher — pokud PDF generation selže, přiložíme HTML voucher,
 *  aby v mailu nikdy nechyběl. Renderuje branded design 1:1 s ostatními maily. */
function renderVoucherHtmlFallback(code: string, amount: number, validUntil: string): string {
  const fmtPriceLocal = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })
  const fmtDateLocal = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"><title>Dárkový poukaz ${code}</title></head>
<body style="margin:0;padding:0;background:#d9dee2;font-family:-apple-system,'Segoe UI',Arial,sans-serif">
  <div style="max-width:780px;margin:24px auto;background:#000000;border:3px solid #74FB71;border-radius:16px;overflow:hidden;color:#ffffff">
    <div style="padding:32px;text-align:center;border-bottom:1px solid #1f3a2c">
      <div style="color:#ffffff;font-size:32px;font-weight:900;letter-spacing:3px">MOTO GO 24</div>
      <div style="color:#74FB71;font-size:11px;font-weight:400;letter-spacing:6px;margin-top:6px">DÁRKOVÝ POUKAZ</div>
    </div>
    <div style="padding:40px 32px;text-align:center">
      <div style="color:#9ca3af;font-size:11px;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px">Hodnota poukazu</div>
      <div style="color:#74FB71;font-size:48px;font-weight:900;line-height:1">${fmtPriceLocal(amount)} Kč</div>
    </div>
    <div style="padding:0 32px 24px;text-align:center">
      <div style="background:#1a1a1a;border:2px dashed #74FB71;border-radius:8px;padding:18px 16px;display:inline-block;min-width:280px">
        <div style="color:#9ca3af;font-size:10px;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px">Kód poukazu</div>
        <div style="color:#ffffff;font-size:28px;font-weight:900;font-family:'Courier New',monospace;letter-spacing:4px">${code}</div>
      </div>
    </div>
    <div style="padding:0 32px 32px;text-align:center;color:#9ca3af;font-size:13px;line-height:1.7">
      <div>Platnost do: <strong style="color:#ffffff">${fmtDateLocal(validUntil)}</strong></div>
      <div style="margin-top:14px">Uplatněte jednorázově při rezervaci na <a href="https://www.motogo24.cz" style="color:#74FB71;text-decoration:none">motogo24.cz</a> — kód zadejte do políčka „Slevový kód".</div>
    </div>
    <div style="padding:18px 32px;background:#0a0a0a;color:#9ca3af;font-size:11px;line-height:1.6;text-align:center">
      Bc. Petra Semorádová · IČO: 21874263 · <span style="color:#74FB71">+420 774 256 271</span> · <span style="color:#74FB71">info@motogo24.cz</span>
    </div>
  </div>
</body></html>`
}

/** HTML → PDF přes PDFShift (https://pdfshift.io) — stejný externí poskytovatel,
 *  který už generuje faktury/doklady. Headless Chrome zvládne i progresivní JPEG
 *  pozadí poukazu (to pdf-lib `embedJpg` neuměl a poukaz proto padal do HTML
 *  fallbacku se špatným vzhledem). Vrací Uint8Array nebo null při chybě / no key. */
async function htmlToPdf(html: string): Promise<Uint8Array | null> {
  if (!PDFSHIFT_API_KEY) return null
  try {
    const res = await fetch('https://api.pdfshift.io/v3/convert/pdf', {
      method: 'POST',
      headers: { 'X-API-Key': PDFSHIFT_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: html,
        margin: '0',
        landscape: false,
        sandbox: false,
        use_print: true,
      }),
    })
    if (!res.ok) {
      console.warn('[htmlToPdf] PDFShift HTTP', res.status, await res.text().catch(() => ''))
      return null
    }
    return new Uint8Array(await res.arrayBuffer())
  } catch (e) {
    console.warn('[htmlToPdf] PDFShift fetch failed:', (e as Error).message)
    return null
  }
}

/** HTML šablona vyplněného poukazu 1:1 s grafikou `gfx/darkovy-poukaz.jpg`
 *  (1400×659). Pozadí = oficiální šablona, překryv = hodnota, datum platnosti
 *  a kód na pozicích odpovídajících předtištěným políčkům. @page v mm přesně
 *  kopíruje poměr obrázku (1400/96·25.4 × 659/96·25.4) → jednostránkové PDF
 *  bez bílých okrajů a beze změny vzhledu šablony. */
function renderVoucherPdfHtml(code: string, amount: number, validUntil: string): string {
  const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 0 })
  const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
  const bgUrl = `${SITE_URL}/gfx/darkovy-poukaz.jpg`
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8">
<style>
  @page { size: 370.4mm 174.4mm; margin: 0; }
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { width:1400px; height:659px; }
  .wrap { position:relative; width:1400px; height:659px; overflow:hidden; }
  .bg { position:absolute; top:0; left:0; width:1400px; height:659px; }
  .ov { position:absolute; font-family:Arial,Helvetica,sans-serif; font-weight:800; line-height:1; white-space:nowrap; }
  .amount { left:390px; top:208px; font-size:54px; color:#27e027; }
  .date   { left:330px; top:358px; font-size:34px; color:#06250b; }
  .code   { left:330px; top:470px; font-size:40px; color:#06250b; font-family:'Courier New',Courier,monospace; letter-spacing:4px; }
</style></head>
<body>
  <div class="wrap">
    <img class="bg" src="${bgUrl}" alt="" />
    <div class="ov amount">${fmtPrice(amount)} Kč</div>
    <div class="ov date">${fmtDate(validUntil)}</div>
    <div class="ov code">${code}</div>
  </div>
</body></html>`
}

/** Generate dárkový poukaz jako PDF přes PDFShift (HTML → PDF, stejně jako faktury).
 *  Vyrenderuje oficiální šablonu poukazu s překryvem hodnoty / data / kódu a převede
 *  ji na PDF externím poskytovatelem. Při selhání (chybí klíč, síť) vyhodí —
 *  caller má HTML fallback. */
async function generateVoucherPdfAttachment(code: string, amount: number, validUntil: string): Promise<string> {
  const html = renderVoucherPdfHtml(code, amount, validUntil)
  const pdfBytes = await htmlToPdf(html)
  if (!pdfBytes) throw new Error('PDFShift voucher conversion failed (missing PDFSHIFT_API_KEY or network)')
  return btoa(Array.from(pdfBytes, (b: number) => String.fromCharCode(b)).join(''))
}

/** Upload base64 content to documents storage bucket and return path. */
async function uploadB64ToStorage(supabase: any, b64: string, path: string, contentType: string): Promise<string | null> {
  try {
    const bin = atob(b64)
    const bytes = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
    const { error } = await supabase.storage.from('documents').upload(path, bytes, { upsert: true, contentType })
    if (error) { console.warn('[uploadB64ToStorage]', path, error.message); return null }
    return path
  } catch (e) { console.warn('[uploadB64ToStorage]', path, (e as Error).message); return null }
}

/** Attachment shape returned by autoGenerateAttachments — `storage_path` umožňuje
 *  pozdější náhled/stažení ve Velínu (SentEmailsTab). Před odesláním přes Resend
 *  je nutné storage_path odstranit (Resend SDK přijímá pouze content+filename). */
type SentAttachment = { content: string; filename: string; storage_path?: string }

/** Auto-generate attachments based on email type */
async function autoGenerateAttachments(
  type: string,
  booking_id: string,
  supabase: any,
  opts: { priceDifference?: number; orderId?: string; lang?: string } = {}
): Promise<SentAttachment[]> {
  // i18n — jazyk zákazníka pro přeložené dokumenty (smlouva, VOP). Default cs.
  const docLang = opts.lang || 'cs'
  const atts: SentAttachment[] = []
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`, 'apikey': SUPABASE_SERVICE_KEY }

  // Voucher purchased (e-shop dárkový poukaz) — DP shop + HTML voucher per kód
  if (type === 'voucher_purchased' && opts.orderId) {
    try {
      // 1. DP (doklad o platbě) — shop payment_receipt
      const { data: dp } = await supabase.from('invoices')
        .select('id, number, pdf_path')
        .eq('order_id', opts.orderId)
        .eq('type', 'payment_receipt')
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(1)
      if (dp?.length && dp[0].pdf_path) {
        const b64 = await downloadAsBase64(supabase, dp[0].pdf_path)
        if (b64) atts.push({ content: b64, filename: `Doklad-platby-${dp[0].number || 'DP'}.${fileExt(dp[0].pdf_path)}`, storage_path: dp[0].pdf_path })
      } else {
        const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', order_id: opts.orderId, source: 'shop', send_email: false }),
        })
        const data = await res.json().catch(() => ({}))
        if (data.success && data.invoice_id) {
          // generate-invoice ukládá zatím .html; pokud později přejde na .pdf, fileExt to detekuje.
          const path = data.pdf_path || `invoices/${data.invoice_id}.html`
          const b64 = await downloadAsBase64(supabase, path)
          if (b64) atts.push({ content: b64, filename: `Doklad-platby-${data.number || 'DP'}.${fileExt(path)}`, storage_path: path })
        }
      }

      // 2. Voucher PDF — generujeme přes PDFShift (HTML šablona → PDF, stejný externí
      // poskytovatel jako faktury). Fallback: pokud PDF selže (chybí PDFSHIFT_API_KEY, síť),
      // přiložíme HTML voucher, aby v mailu nikdy nechyběl. Důvod selhání zalogujeme do debug_log.
      const { data: vouchers } = await supabase.from('vouchers')
        .select('code, amount, valid_until')
        .eq('order_id', opts.orderId)
      for (const v of (vouchers || []) as Array<{ code: string; amount: number; valid_until: string }>) {
        let pdfOk = false
        try {
          const b64 = await generateVoucherPdfAttachment(v.code, v.amount, v.valid_until)
          // Ulož PDF voucher do storage, aby šel později ve Velínu otevřít.
          const storagePath = await uploadB64ToStorage(supabase, b64, `vouchers/${opts.orderId}/${v.code}.pdf`, 'application/pdf')
          atts.push({ content: b64, filename: `Darkovy-poukaz-${v.code}.pdf`, storage_path: storagePath || undefined })
          pdfOk = true
        } catch (e) {
          const errMsg = (e as Error).message
          console.warn('[autoGenerateAttachments] voucher PDF failed:', errMsg)
          try {
            await supabase.from('debug_log').insert({
              source: 'send-booking-email',
              action: 'voucher_pdf_generation_failed',
              component: 'generateVoucherPdfAttachment',
              status: 'error',
              error_message: errMsg,
              request_data: { code: v.code, amount: v.amount, order_id: opts.orderId },
            })
          } catch { /* ignore */ }
        }
        if (!pdfOk) {
          // HTML voucher fallback — zaručuje, že voucher v mailu vždy je
          const html = renderVoucherHtmlFallback(v.code, v.amount, v.valid_until)
          const b64 = btoa(unescape(encodeURIComponent(html)))
          const storagePath = await uploadB64ToStorage(supabase, b64, `vouchers/${opts.orderId}/${v.code}.html`, 'text/html')
          atts.push({ content: b64, filename: `Darkovy-poukaz-${v.code}.html`, storage_path: storagePath || undefined })
        }
      }
    } catch (e) {
      console.warn('[autoGenerateAttachments] voucher_purchased failed:', (e as Error).message)
    }
    return atts
  }

  // Generic attachments volitelně vybrané v Velín UI (mimo booking_modified flow):
  // rental_contract / vop / credit_note se generují přes generate-document
  // (smlouva, VOP) nebo fetchují z invoices (dobropis).
  if (type === 'rental_contract' && booking_id) {
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST', headers,
        body: JSON.stringify({ template_slug: 'rental_contract', booking_id, language: docLang }),
      })
      const data = await res.json().catch(() => ({}))
      if (data.success && data.path) {
        const b64 = await downloadAsBase64(supabase, data.path)
        if (b64) atts.push({ content: b64, filename: `Najemni-smlouva-${booking_id.slice(-8).toUpperCase()}.${fileExt(data.path)}`, storage_path: data.path })
      }
    } catch { /* ignore */ }
    return atts
  }

  if (type === 'vop' && booking_id) {
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST', headers,
        body: JSON.stringify({ template_slug: 'vop', booking_id, language: docLang }),
      })
      const data = await res.json().catch(() => ({}))
      if (data.success && data.path) {
        const b64 = await downloadAsBase64(supabase, data.path)
        if (b64) atts.push({ content: b64, filename: `VOP-${booking_id.slice(-8).toUpperCase()}.${fileExt(data.path)}`, storage_path: data.path })
      }
    } catch { /* ignore */ }
    return atts
  }

  if (type === 'credit_note') {
    try {
      let q = supabase.from('invoices')
        .select('id, number, pdf_path')
        .eq('type', 'credit_note')
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(1)
      if (booking_id) q = q.eq('booking_id', booking_id)
      else if (opts.orderId) q = q.eq('order_id', opts.orderId)
      const { data: cn } = await q
      if (cn?.length && cn[0].pdf_path) {
        const b64 = await downloadAsBase64(supabase, cn[0].pdf_path)
        if (b64) atts.push({ content: b64, filename: `Dobropis-${cn[0].number || 'DB'}.${fileExt(cn[0].pdf_path)}`, storage_path: cn[0].pdf_path })
      }
    } catch { /* ignore */ }
    return atts
  }

  // Shop order confirmed — DP e-shop (payment_receipt with source='shop')
  if (type === 'shop_order_confirmed' && opts.orderId) {
    try {
      const { data: dp } = await supabase.from('invoices')
        .select('id, number, pdf_path')
        .eq('order_id', opts.orderId)
        .eq('type', 'payment_receipt')
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(1)
      if (dp?.length && dp[0].pdf_path) {
        const b64 = await downloadAsBase64(supabase, dp[0].pdf_path)
        if (b64) atts.push({ content: b64, filename: `Doklad-platby-${dp[0].number || 'DP'}.${fileExt(dp[0].pdf_path)}`, storage_path: dp[0].pdf_path })
      } else {
        // DP neexistuje → pokus o generování
        const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', order_id: opts.orderId, source: 'shop', send_email: false }),
        })
        const data = await res.json().catch(() => ({}))
        if (data.success && data.invoice_id) {
          const path = data.pdf_path || `invoices/${data.invoice_id}.html`
          const b64 = await downloadAsBase64(supabase, path)
          if (b64) atts.push({ content: b64, filename: `Doklad-platby-${data.number || 'DP'}.${fileExt(path)}`, storage_path: path })
        }
      }
    } catch { /* ignore */ }
    return atts
  }

  // Shop order shipped — KF e-shop (shop_final)
  if (type === 'shop_order_shipped' && opts.orderId) {
    try {
      const { data: kf } = await supabase.from('invoices')
        .select('id, number, pdf_path')
        .eq('order_id', opts.orderId)
        .eq('type', 'shop_final')
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(1)
      if (kf?.length && kf[0].pdf_path) {
        const b64 = await downloadAsBase64(supabase, kf[0].pdf_path)
        if (b64) atts.push({ content: b64, filename: `Konecna-faktura-${kf[0].number || 'KF'}.${fileExt(kf[0].pdf_path)}`, storage_path: kf[0].pdf_path })
      } else {
        // KF neexistuje → vygeneruj
        const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'shop_final', order_id: opts.orderId, send_email: false }),
        })
        const data = await res.json().catch(() => ({}))
        if (data.success && data.invoice_id) {
          const path = data.pdf_path || `invoices/${data.invoice_id}.html`
          const b64 = await downloadAsBase64(supabase, path)
          if (b64) atts.push({ content: b64, filename: `Konecna-faktura-${data.number || 'KF'}.${fileExt(path)}`, storage_path: path })
        }
      }
    } catch { /* ignore */ }
    return atts
  }

  if (!booking_id) return atts

  // Synth typy pro Velín-vybrané přílohy v booking kontextu (mimo shop):
  //   - booking_advance         → ZF (advance) per booking
  //   - booking_payment_receipt → DP (payment_receipt) per booking
  // Volány z attachmentTypeMap. Fetchnou existující fakturu, jinak vygenerují přes generate-invoice.
  if (type === 'booking_advance') {
    try {
      const { data: existing } = await supabase.from('invoices')
        .select('id, number, pdf_path')
        .eq('booking_id', booking_id)
        .eq('type', 'advance')
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(1)
      if (existing?.length && existing[0].pdf_path) {
        const b64 = await downloadAsBase64(supabase, existing[0].pdf_path)
        if (b64) atts.push({ content: b64, filename: `Zalohova-faktura-${existing[0].number || 'ZF'}.${fileExt(existing[0].pdf_path)}`, storage_path: existing[0].pdf_path })
      } else {
        const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'advance', booking_id, send_email: false }),
        })
        const data = await res.json().catch(() => ({}))
        if (data.success && data.invoice_id) {
          const path = data.pdf_path || `invoices/${data.invoice_id}.html`
          const b64 = await downloadAsBase64(supabase, path)
          if (b64) atts.push({ content: b64, filename: `Zalohova-faktura-${data.number || 'ZF'}.${fileExt(path)}`, storage_path: path })
        }
      }
    } catch { /* ignore */ }
    return atts
  }

  if (type === 'booking_payment_receipt') {
    try {
      const { data: existing } = await supabase.from('invoices')
        .select('id, number, pdf_path, source')
        .eq('booking_id', booking_id)
        .eq('type', 'payment_receipt')
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
      // Vyfiltruj DP vázané na booking (ne shop) — preferuj source='booking'/'edit'/null
      const candidate = (existing || []).find((r: any) => r.source !== 'shop') || (existing || [])[0]
      if (candidate?.pdf_path) {
        const b64 = await downloadAsBase64(supabase, candidate.pdf_path)
        if (b64) atts.push({ content: b64, filename: `Doklad-platby-${candidate.number || 'DP'}.${fileExt(candidate.pdf_path)}`, storage_path: candidate.pdf_path })
      } else {
        const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id, send_email: false }),
        })
        const data = await res.json().catch(() => ({}))
        if (data.success && data.invoice_id) {
          const path = data.pdf_path || `invoices/${data.invoice_id}.html`
          const b64 = await downloadAsBase64(supabase, path)
          if (b64) atts.push({ content: b64, filename: `Doklad-platby-${data.number || 'DP'}.${fileExt(path)}`, storage_path: path })
        }
      }
    } catch { /* ignore */ }
    return atts
  }

  if (type === 'booking_abandoned') {
    // Generate ZF (proforma) for abandoned bookings — shows what needs to be paid
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
        method: 'POST', headers,
        body: JSON.stringify({ type: 'advance', booking_id, send_email: false }),
      })
      const data = await res.json().catch(() => ({}))
      if (data.success && data.invoice_id) {
        const path = data.pdf_path || `invoices/${data.invoice_id}.html`
        const b64 = await downloadAsBase64(supabase, path)
        if (b64) atts.push({ content: b64, filename: `Zalohova-faktura-${data.number || 'ZF'}.${fileExt(path)}`, storage_path: path })
      }
    } catch { /* ignore */ }
  }

  // booking_reserved a booking_cancelled samy o sobě negenerují žádné přílohy hardcoded —
  // vše řídí Velín admin přes `email_templates.attachments` (delegát na booking_advance,
  // booking_payment_receipt, rental_contract, vop, credit_note synth typy).
  if (type === 'booking_reserved' || type === 'booking_cancelled') {
    return atts
  }

  if (type === 'booking_completed') {
    // Fetch KF (konečná faktura) from invoices table
    try {
      const { data: invoices } = await supabase.from('invoices')
        .select('id, number, pdf_path')
        .eq('booking_id', booking_id)
        .in('type', ['final'])
        .neq('status', 'cancelled')
        .order('created_at', { ascending: false })
        .limit(1)
      let kfPath = invoices?.length ? invoices[0].pdf_path : null
      let kfNumber = invoices?.length ? invoices[0].number : null
      // KF vytváří DB trigger generate_final_invoice_on_complete() bez renderu PDF
      // → pdf_path je NULL (Velín ji renderuje client-side, takže „existuje", ale do
      // mailu nešla). Dorenderuj PDF z uložených položek přes generate-invoice
      // (render_existing) a teprve pak přilož.
      if (invoices?.length && !kfPath) {
        try {
          const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
            method: 'POST', headers,
            body: JSON.stringify({ render_existing: true, type: 'final', booking_id }),
          })
          const data = await res.json().catch(() => ({}))
          if (data.success && data.pdf_path) { kfPath = data.pdf_path; kfNumber = data.number || kfNumber }
        } catch { /* ignore */ }
      }
      if (kfPath) {
        const b64 = await downloadAsBase64(supabase, kfPath)
        if (b64) atts.push({ content: b64, filename: `Konecna-faktura-${kfNumber || 'KF'}.${fileExt(kfPath)}`, storage_path: kfPath })
      }
    } catch { /* ignore */ }
  }

  if (type === 'booking_modified') {
    const priceDifference = Number(opts.priceDifference || 0)

    if (priceDifference > 0) {
      // Doplatek → POUZE rozdílový DP (source='edit'). ZF se při úpravě rezervace
      // NIKDY negeneruje ani neposílá — platba proběhla rovnou bránou, proforma
      // výzva k platbě nedává smysl a zákazníka jen mate (pravidlo 2026-06-11).
      // `price_difference` MUSÍ jít s sebou — modification_history nenese price_diff
      // (a placená výbava / webhook doplatek do historie nezapisují vůbec), takže
      // bez explicitní částky by generate-invoice rozdílový doklad skipnul a
      // v mailu by zůstal jen starý DP z původní platby.
      try {
        const dpRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id, source: 'edit', price_difference: priceDifference, send_email: false }),
        })
        const dpData = await dpRes.json().catch(() => ({}))
        if (dpData.success && dpData.invoice_id) {
          const path = dpData.pdf_path || `invoices/${dpData.invoice_id}.html`
          const b64 = await downloadAsBase64(supabase, path)
          if (b64) atts.push({ content: b64, filename: `Doklad-platby-uprava-${dpData.number || 'DP'}.${fileExt(path)}`, storage_path: path })
        }
      } catch { /* ignore */ }
    } else if (priceDifference < 0) {
      // Zkrácení → dobropis + refund se řeší přes process-refund (volá ho RPC
      // _apply_booking_changes_core / shorten_booking_with_refund), zde přiložíme
      // vystavený dobropis (credit_note source='refund') s recovery retry pro
      // případ, že PDFShift / Storage upload v process-refund tichoun selhal
      // (stejná logika jako v send-cancellation-email od 2026-05-10).
      const refundAmt = Math.abs(priceDifference)
      let attached = false
      for (let attempt = 0; attempt < 3 && !attached; attempt++) {
        try {
          const { data: cn } = await supabase.from('invoices')
            .select('id, number, pdf_path')
            .eq('booking_id', booking_id)
            .eq('type', 'credit_note')
            .neq('status', 'cancelled')
            .order('created_at', { ascending: false })
            .limit(1)
          if (cn?.length && cn[0].pdf_path) {
            const b64 = await downloadAsBase64(supabase, cn[0].pdf_path)
            if (b64) {
              atts.push({ content: b64, filename: `Dobropis-${cn[0].number || 'DB'}.${fileExt(cn[0].pdf_path)}`, storage_path: cn[0].pdf_path })
              attached = true
              break
            }
          }
          // Recovery — vystavit / dovystavit PDF dobropisu přes process-refund (idempotentní)
          if (attempt < 2) {
            try {
              await fetch(`${SUPABASE_URL}/functions/v1/process-refund`, {
                method: 'POST', headers,
                body: JSON.stringify({ booking_id, amount: refundAmt, reason: 'booking_modified_retry' }),
              })
            } catch { /* ignore */ }
            await new Promise(r => setTimeout(r, 2500))
          }
        } catch { /* ignore — další iterace */ }
      }
      if (!attached) {
        await supabase.from('debug_log').insert({
          source: 'send-booking-email',
          action: 'modified_credit_note_attach_failed',
          status: 'error',
          error_message: 'Credit note attachment missing after 3 retries (booking_modified flow)',
          request_data: { booking_id, refundAmt, priceDifference },
        }).then(() => {}, () => {})
      }
    }
    // priceDifference === 0 → žádná nová faktura, jen aktualizovaná smlouva/VOP níže

    // 3. Updated rental contract
    try {
      const cRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST', headers,
        body: JSON.stringify({ template_slug: 'rental_contract', booking_id, language: docLang }),
      })
      const cData = await cRes.json().catch(() => ({}))
      if (cData.success && cData.path) {
        const b64 = await downloadAsBase64(supabase, cData.path)
        if (b64) atts.push({ content: b64, filename: `Najemni-smlouva-${booking_id.slice(-8).toUpperCase()}.${fileExt(cData.path)}`, storage_path: cData.path })
      }
    } catch { /* ignore */ }

    // 4. VOP
    try {
      const vRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST', headers,
        body: JSON.stringify({ template_slug: 'vop', booking_id, language: docLang }),
      })
      const vData = await vRes.json().catch(() => ({}))
      if (vData.success && vData.path) {
        const b64 = await downloadAsBase64(supabase, vData.path)
        if (b64) atts.push({ content: b64, filename: `VOP-${booking_id.slice(-8).toUpperCase()}.${fileExt(vData.path)}`, storage_path: vData.path })
      }
    } catch { /* ignore */ }
  }

  return atts
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    const body = await req.json()
    const {
      type,
      booking_id,
      customer_email,
      customer_name,
      motorcycle,
      start_date,
      end_date,
      total_price,
      price_difference,
      voucher_code,
      voucher_value,
      voucher_expiry,
      order_number,
      source = 'app', // 'web' or 'app'
      resume_link,
      pay_url,
      docs_url,
      discount_code,
      google_review_url,
      facebook_review_url,
      manual_url,
      // legacy `attachments` v body se ignoruje — Velín DB šablona je etalon (viz níže)
      // i18n — language zákazníka (cs/en/de/nl/es/fr/pl), default 'cs'
      language,
      // Shop order extras
      order_id,
      shipping_cost,
      tracking_number,
      tracking_url,
      // booking_modified — přehled úprav (původní vs nové)
      original_motorcycle,
      original_start_date,
      original_end_date,
      original_total_price,
      original_pickup_method,
      original_pickup_address,
      original_return_method,
      original_return_address,
      pickup_method,
      pickup_address,
      pickup_time,
      return_method,
      return_address,
      return_time,
      original_pickup_time,
      original_return_time,
    } = body

    if (!type || !customer_email) {
      return new Response(JSON.stringify({ error: 'Missing type or customer_email' }), {
        status: 400,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // door_codes: edge fn nyní mail rendruje + posílá. Dřív byl tento type
    // blokován s tím že "jde výhradně přes SQL fn send_door_codes_email" — to ale
    // selhalo, protože SQL fn potřebovala RESEND_API_KEY v `app_settings`/`vault`,
    // což na produkci nebylo nastavené (edge fns klíč berou přes `Deno.env`).
    // Sjednoceno se zbytkem mailů — edge fn = jediný zdroj pravdy pro odeslání.
    // SQL fn `send_door_codes_email` teď volá tuhle edge fn přes pg_net.


    const vars: Record<string, string> = {
      customer_name: customer_name || '',
      booking_id: booking_id || '',
      booking_number: (booking_id || '').slice(-8).toUpperCase(),
      motorcycle: motorcycle || '',
      start_date: fmtDate(start_date),
      end_date: fmtDate(end_date),
      total_price: fmtPrice(total_price || 0),
      price_difference: price_difference ? fmtPrice(price_difference) : '',
      voucher_code: voucher_code || '',
      voucher_value: voucher_value ? fmtPrice(voucher_value) : '',
      voucher_expiry: fmtDate(voucher_expiry),
      site_url: SITE_URL,
      order_number: order_number || (booking_id || '').slice(-8).toUpperCase(),
      resume_link: resume_link || '',
      resume_qr_url: resume_link ? `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(resume_link)}` : '',
      // Nové URL pro abandoned/docs reminder maily — pay_url a docs_url se vyplňují z cron funkce
      // send_abandoned_booking_emails podle stavu rezervace (state A/B/C). Když chybí, fallback
      // na resume_link, ať se starší volání send-booking-email nerozbijí.
      pay_url: pay_url || resume_link || '',
      docs_url: docs_url || '',
      discount_code: discount_code || '',
      // Shop order
      shipping_cost: shipping_cost != null ? fmtPrice(shipping_cost) : '',
      tracking_number: tracking_number || '',
      tracking_url: tracking_url || '',
      // booking_modified — přehled úprav
      original_motorcycle:    original_motorcycle || '',
      original_start_date:    fmtDate(original_start_date),
      original_end_date:      fmtDate(original_end_date),
      original_total_price:   original_total_price != null ? fmtPrice(original_total_price) : '',
      original_pickup_method: original_pickup_method || '',
      original_pickup_address: original_pickup_address || '',
      original_return_method: original_return_method || '',
      original_return_address: original_return_address || '',
      pickup_method:          pickup_method || '',
      pickup_address:         pickup_address || '',
      return_method:          return_method || '',
      return_address:         return_address || '',
      pickup_time:            pickup_time || '',
      return_time:            return_time || '',
      original_pickup_time:   original_pickup_time || '',
      original_return_time:   original_return_time || '',
      google_review_url: google_review_url || GOOGLE_REVIEW_URL_DEFAULT,
      facebook_review_url: facebook_review_url || FACEBOOK_REVIEW_URL_DEFAULT,
      instagram_review_url: INSTAGRAM_REVIEW_URL_DEFAULT,
      manual_url: manual_url || '',
      door_code_moto: '',
      door_code_gear: '',
      door_codes_block: '',
      // {{business_card}} placeholder se v DB šabloně auto-vyčistí — brand header/footer je v wrapInBrandedLayout
    }

    // Load active door codes for this booking. Buffer raw rows — vlastní render
    // (released codes vs. „chybí doklady" CTA) proběhne až po detekci jazyka.
    let doorCodeRows: Array<{ code_type: string; door_code: string; sent_to_customer: boolean; withheld_reason: string | null; is_active: boolean }> = []
    if (booking_id) {
      try {
        const { data: codes } = await supabase
          .from('branch_door_codes')
          .select('code_type, door_code, sent_to_customer, withheld_reason, is_active')
          .eq('booking_id', booking_id)
          .eq('is_active', true)
        if (codes?.length) doorCodeRows = codes as any[]
      } catch { /* ignore */ }
    }

    // \u2500\u2500 i18n: detekce jazyka z\u00e1kazn\u00edka \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // 1) explicit `language` z payloadu (volaj\u00edc\u00ed ho v\u00ed \u2014 Velin/web/app)
    // 2) RPC detect_customer_language(user_id, booking_id, order_id) \u2014 z DB
    // 3) fallback 'cs'
    let custLang: Lang = normalizeLang(language)
    if (!language && (booking_id || order_id)) {
      try {
        const { data: langData } = await supabase.rpc('detect_customer_language', {
          p_user_id:    null,
          p_booking_id: booking_id || null,
          p_order_id:   order_id || null,
        })
        custLang = normalizeLang(langData)
      } catch { /* ignore \u2014 z\u016fstane 'cs' */ }
    }

    // \u2500\u2500 door_codes_block: released codes \u27c2 "chyb\u00ed doklady" CTA \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // \u0160ablony booking_reserved/door_codes/booking_completed maj\u00ed placeholder
    // `${v.door_codes_block || ''}`. Kdy\u017e rezervace m\u00e1 uvoln\u011bn\u00e9 k\u00f3dy, vykresl\u00ed
    // se modr\u00fd blok s \u010d\u00edsly. Kdy\u017e ne (k\u00f3dy zadr\u017een\u00e9 nebo je\u0161t\u011b negenerovan\u00e9)
    // a typ mailu je booking_reserved/door_codes, vykresl\u00ed se oran\u017eov\u00fd blok
    // s v\u00fdzvou k nahr\u00e1n\u00ed doklad\u016f + zm\u00ednkou o osobn\u00edm ov\u011b\u0159en\u00ed na pobo\u010dce.
    if (doorCodeRows.length) {
      const released = doorCodeRows.filter(c => c.sent_to_customer === true && !c.withheld_reason)
      const moto = released.find(c => c.code_type === 'motorcycle')?.door_code || ''
      const gear = released.find(c => c.code_type === 'accessories')?.door_code || ''
      vars.door_code_moto = moto
      vars.door_code_gear = gear
      if (moto || gear) {
        vars.door_codes_block = renderDoorCodesReleasedBlock(custLang, moto, gear)
      }
    }
    if (!vars.door_codes_block && booking_id && (type === 'booking_reserved' || type === 'door_codes')) {
      // K\u00f3dy nejsou uvoln\u011bn\u00e9 \u2192 ov\u011b\u0159, \u017ee rezervace skute\u010dn\u011b pot\u0159ebuje doklady.
      // 1) Kdy\u017e jsou k bookingu \u0159\u00e1dky v branch_door_codes s withheld_reason \u2192 doklady chyb\u00ed.
      // 2) Jinak ov\u011b\u0159 p\u0159es RPC check_booking_docs_status (NULL = doklady OK, jinak d\u016fvod).
      let needsDocs = doorCodeRows.some(c => !!c.withheld_reason)
      if (!needsDocs && doorCodeRows.length === 0) {
        try {
          const { data: b } = await supabase
            .from('bookings')
            .select('user_id, end_date, status')
            .eq('id', booking_id)
            .maybeSingle()
          if (b && (b.status === 'reserved' || b.status === 'active')) {
            const { data: reason } = await supabase.rpc('check_booking_docs_status', {
              p_user_id: b.user_id,
              p_end_date: b.end_date,
            })
            if (reason) needsDocs = true
          }
        } catch { /* ignore */ }
      }
      if (needsDocs) {
        const docsLink = docs_url || `${siteForLang(custLang)}/upravit-rezervaci?id=${booking_id}#doklady`
        vars.docs_url = docsLink
        vars.door_codes_block = renderDocsRequiredBlock(custLang, docsLink)
      }
    }

    // invoice_payment_receipt (web): platba přijata, ale chybí POVINNÁ čísla dokladů.
    // Zajisti odkaz na doplnění (číslo OP/ŘP + skupina + dobrovolný scan) v jazyce
    // zákazníka, i když ho caller nepředal — DB šablona ho používá přes {{docs_url}}.
    if (type === 'invoice_payment_receipt' && !vars.docs_url && booking_id) {
      vars.docs_url = docs_url || `${siteForLang(custLang)}/upravit-rezervaci?id=${booking_id}#doklady`
    }

    // i18n: {{site_url}} placeholder → doména zákazníka (.cz pro cs, .com jinak).
    // Vars se sestavily před detekcí jazyka, takže přepíšeme až teď.
    vars.site_url = siteForLang(custLang)

    // Try to load template from DB (first web-specific, then generic)
    const slug = resolveSlug(type, source)
    let templateHtml = ''
    let subject = ''

    // Try web-specific slug first if source=web, then fall back to generic
    const slugsToTry = source === 'web' ? [slug, type] : [type]

    // Capture attachments[] z DB \u0161ablony \u2014 admin Vel\u00edn konfigurace mus\u00ed b\u00fdt
    // respektov\u00e1na i pro legacy type=... cesty (booking_reserved, voucher_purchased,
    // shop_order_confirmed atd.). Bez tohoto fetch byly Vel\u00edn attachments
    // nastaven\u00ed v UI ignorov\u00e1ny a chodily jen autoGenerateAttachments hardcoded.
    let dbAttachmentsList: string[] = []

    for (const trySlug of slugsToTry) {
      const { data: tpl } = await supabase
        .from('email_templates')
        .select('slug, name, subject, body_html, active, subject_translations, body_translations, attachments')
        .eq('slug', trySlug)
        .eq('active', true)
        .maybeSingle()

      if (tpl?.body_html) {
        // Vel\u00edn = jen CZ. Pro non-cz z\u00e1kazn\u00edka p\u0159elo\u017e CZ \u0161ablonu p\u0159es API
        // (cache v {subject,body}_translations[lang] + __src_<lang> hash).
        // cs \u2192 CZ origin\u00e1l 1:1 beze zm\u011bny.
        const resolved = await resolveTemplateForLang(supabase, tpl as any, custLang)
        // U poděkovacího mailu (booking_completed / web_booking_completed) opravíme
        // odkazy na recenze (Google/Facebook) a doplníme Instagram.
        const bodySrc = trySlug.includes('completed') ? fixReviewLinks(resolved.body) : resolved.body
        templateHtml = renderTemplate(bodySrc, vars)
        subject = renderTemplate(resolved.subject, vars)
        if (Array.isArray(tpl.attachments)) {
          dbAttachmentsList = tpl.attachments as string[]
        }
        break
      }
    }

    // i18n hardcoded p\u0159eklady (priorita 2 \u2014 kdy\u017e DB \u0161ablona chyb\u00ed)
    if (!templateHtml) {
      const i18nResult = renderEmail(type, custLang, vars)
      if (i18nResult) {
        subject = i18nResult.subject
        templateHtml = i18nResult.body
      }
    }

    // If no template found anywhere, use legacy fallback subject (priorita 3 \u2014 cs only)
    if (!subject) {
      const fallbackFn = FALLBACK_SUBJECTS[type]
      subject = fallbackFn ? fallbackFn(vars) : `Ozn\u00e1men\u00ed \u2014 MOTO GO 24`
    }

    // If no template body in DB, use type-specific fallback
    if (!templateHtml) {
      if (type === 'booking_abandoned') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>velice v\u00e1m d\u011bkujeme za v\u00e1\u0161 z\u00e1jem o na\u0161i motop\u016fj\u010dovnu.</p>
<p>Vypad\u00e1 to, \u017ee jste nedokon\u010dili svou rezervaci \u010d. <strong>${vars.booking_number}</strong> motocyklu.</p>
<p>Pro snadn\u00e9 dokon\u010den\u00ed rezervace sta\u010d\u00ed kliknout na n\u00e1sleduj\u00edc\u00ed odkaz:</p>
${vars.resume_link ? `<div style="text-align:center;margin:24px 0"><a href="${vars.resume_link}" style="background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px;display:inline-block">Dokon\u010dit rezervaci</a></div>` : ''}
<p style="color:#dc2626;font-weight:700;font-style:italic">Pozor: odkaz je platn\u00fd pouze 4 hodiny. Po uplynut\u00ed t\u00e9to doby se motocykl uvoln\u00ed pro dal\u0161\u00ed z\u00e1kazn\u00edky.</p>
<p>D\u011bkujeme a t\u011b\u0161\u00edme se na v\u00e1s.</p>
<p>T\u00fdm MotoGo24</p>`
      } else if (type === 'booking_abandoned_full') {
        // State A — unpaid + chybí doklady. Dva CTA: platba + nahrání dokladů.
        templateHtml = `<p>Dobrý den,</p>
<p>vidíme, že jste rozjeli rezervaci č. <strong>${vars.booking_number}</strong> motocyklu <strong>${vars.motorcycle}</strong> na <strong>${vars.start_date} – ${vars.end_date}</strong>, ale ještě jste ji nedokončili. Chybí dvě věci:</p>
<ol><li><strong>Zaplatit</strong> přes zabezpečenou Stripe bránu</li><li><strong>Nahrát doklady</strong> (občanka/pas + řidičák) — sken přes mobil díky Mindee OCR zabere 30 vteřin</li></ol>
<p>Vraťte se prosím do rezervace a obojí dořešte — všechna vyplněná data jsou uložená.</p>
<div style="text-align:center;margin:24px 0">
  ${vars.pay_url ? `<a href="${vars.pay_url}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 22px;border-radius:25px;text-decoration:none;font-weight:800;font-size:14px;margin:4px">Pokračovat k platbě</a>` : ''}
  ${vars.docs_url ? `<a href="${vars.docs_url}" style="display:inline-block;background:#1a2e22;color:#74FB71;padding:14px 22px;border-radius:25px;text-decoration:none;font-weight:800;font-size:14px;margin:4px">Nahrát doklady</a>` : ''}
</div>
<p style="color:#dc2626;font-weight:700;font-style:italic">Bez platby a dokladů systém přístupový kód k motorce nevydá. Termín můžeme držet jen omezenou dobu.</p>
<p>Tým MotoGo24</p>`
      } else if (type === 'booking_missing_docs') {
        // State C — paid + chybí doklady. Jen docs CTA, nic dalšího.
        templateHtml = `<p>Dobrý den,</p>
<p>vaše rezervace č. <strong>${vars.booking_number}</strong> motocyklu <strong>${vars.motorcycle}</strong> na <strong>${vars.start_date} – ${vars.end_date}</strong> je zaplacená — děkujeme!</p>
<p>Aby vám dorazil <strong>přístupový kód k motorce</strong>, ještě potřebujeme naskenovat doklady (občanku/pas + řidičák). Sken přes mobil díky Mindee OCR zabere 30 vteřin.</p>
${vars.docs_url ? `<div style="text-align:center;margin:24px 0"><a href="${vars.docs_url}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">Nahrát doklady</a></div>` : ''}
<p>Bez nahraných dokladů systém kódy nevydá — a platit za něco, co si nemůžete vyzvednout, by byla škoda.</p>
<p>Tým MotoGo24</p>`
      } else if (type === 'invoice_payment_receipt') {
        // Platba přijata, ale chybí POVINNÁ čísla dokladů → jen ZF+DP + výzva
        // doplnit čísla (povinné pro smlouvu) + dobrovolný scan. NE smlouva/VOP.
        // (Fallback — reálné tělo edituje admin ve Velíně: web_invoice_payment_receipt.)
        templateHtml = `<p>Dobrý den,</p>
<p>vaše platba za rezervaci č. <strong>${vars.booking_number}</strong> motocyklu <strong>${vars.motorcycle}</strong> na <strong>${vars.start_date} – ${vars.end_date}</strong> byla úspěšně přijata — děkujeme!</p>
<p>V příloze najdete <strong>zálohovou fakturu</strong> a <strong>doklad o přijaté platbě</strong> (celkem ${vars.total_price}).</p>
<p>Ještě jeden krok: pro přípravu <strong>nájemní smlouvy</strong> prosím doplňte <strong>čísla dokladů</strong> (občanky/pasu a řidičského průkazu) a <strong>skupinu ŘP</strong> — to je povinné. Nahrání fotek dokladů je dobrovolné, ale předem odemkne přístupové kódy ke dveřím (nutné u autonomních poboček).</p>
${vars.docs_url ? `<div style="text-align:center;margin:24px 0"><a href="${vars.docs_url}" style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px">Doplnit doklady</a></div>` : ''}
<p>Nájemní smlouvu a VOP vám pošleme, jakmile budou čísla dokladů vyplněná.</p>
<p>Tým MotoGo24</p>`
      } else if (type === 'booking_reserved') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>d\u011bkujeme za va\u0161i d\u016fv\u011bru a za rezervaci \u010d. <strong>${vars.booking_number}</strong> motocyklu u MotoGo24.</p>
<p>Va\u0161e rezervace byla \u00fasp\u011b\u0161n\u011b p\u0159ijata a uhrazena.</p>
<p>Kompletn\u00ed p\u0159ehled rezervovan\u00fdch slu\u017eeb a v\u00fdbavy naleznete v p\u0159ilo\u017een\u00e9 N\u00e1jemn\u00ed smlouv\u011b a z\u00e1lohov\u00e9 faktu\u0159e.</p>
${vars.door_codes_block}
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informace k p\u0159evzet\u00ed motocyklu</h3>
<p>Pros\u00edme, pro bezprobl\u00e9mov\u00e9 p\u0159evzet\u00ed si p\u0159ipravte:</p>
<ul><li>platn\u00fd doklad toto\u017enosti (kter\u00fd jste uvedli v rezerva\u010dn\u00edm formul\u00e1\u0159i),</li><li>platn\u00fd \u0159idi\u010dsk\u00fd pr\u016fkaz.</li></ul>
<p>Na m\u00edst\u011b spole\u010dn\u011b provedeme kontrolu doklad\u016f, p\u0159ed\u00e1n\u00ed motocyklu i p\u0159\u00edpadn\u00e9 zap\u016fj\u010den\u00e9 v\u00fdbavy (kterou si budete moci vyzkou\u0161et) a podep\u00ed\u0161eme P\u0159ed\u00e1vac\u00ed protokol. V\u0161e v\u00e1m r\u00e1di vysv\u011btl\u00edme \u2013 p\u0159ed\u00e1n\u00ed je rychl\u00e9 a zabere jen p\u00e1r minut.</p>
<p>Pokud s sebou budete m\u00edt osobn\u00ed v\u011bci, kter\u00e9 nechcete br\u00e1t na cestu, m\u016f\u017eete je u n\u00e1s zdarma ulo\u017eit do uzamykateln\u00e9 sk\u0159\u00ed\u0148ky.</p>
<p>Doporu\u010dujeme, abyste se p\u0159ed j\u00edzdou sezn\u00e1mili s u\u017eivatelsk\u00fdmi informacemi k motocyklu, kter\u00e9 najdete v odkazu na na\u0161ich webov\u00fdch str\u00e1nk\u00e1ch <a href="https://www.motogo24.cz" style="color:#2563eb">motogo24.cz</a>.</p>
<p>Pokud budete m\u00edt jak\u00fdkoliv dotaz, jsme v\u00e1m k dispozici.</p>
<p>T\u011b\u0161\u00edme se na v\u00e1s a p\u0159ejeme kr\u00e1sn\u00fd z\u00e1\u017eitek z j\u00edzdy.</p>
<p>T\u00fdm MotoGo24</p>`
      } else if (type === 'booking_completed') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>d\u011bkujeme, \u017ee jste vyu\u017eili slu\u017eeb MotoGo24.</p>
<p>Proto\u017ee je pro n\u00e1s zp\u011btn\u00e1 vazba velmi d\u016fle\u017eit\u00e1, budeme r\u00e1di, pokud n\u00e1m zanech\u00e1te recenzi na <a href="${vars.google_review_url || GOOGLE_REVIEW_URL_DEFAULT}" style="display:inline-block;background:#74FB71;color:#0a1f15;font-size:12px;font-weight:700;text-decoration:none;padding:6px 14px;border-radius:14px;margin:0 4px">Google</a> nebo na <a href="${vars.facebook_review_url || FB_URL}" style="display:inline-block;background:#74FB71;color:#0a1f15;font-size:12px;font-weight:700;text-decoration:none;padding:6px 14px;border-radius:14px;margin:0 4px">Facebook</a>.</p>
<p>Pokud m\u00e1te n\u011bjak\u00e9 zaj\u00edmav\u00e9 fotografie nebo videa z va\u0161\u00ed cesty, kter\u00e9 byste s n\u00e1mi cht\u011bli sd\u00edlet, za\u0161lete n\u00e1m je, pros\u00edm, na e-mail: <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>. R\u00e1di je p\u0159\u00edpadn\u011b zve\u0159ejn\u00edme na na\u0161em webu nebo soci\u00e1ln\u00edch s\u00edt\u00edch.</p>
${vars.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">Jako mal\u00e9 pod\u011bkov\u00e1n\u00ed za poskytnutou d\u016fv\u011bru p\u0159ikl\u00e1d\u00e1me slevov\u00fd k\u00f3d <strong>200 K\u010d</strong> na va\u0161i p\u0159\u00ed\u0161t\u00ed rezervaci: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${vars.discount_code}</strong></p></div>` : ''}
<p>V p\u0159\u00edloze naleznete kone\u010dnou fakturu za va\u0161i rezervaci.</p>
${vars.door_codes_block}
<p>T\u011b\u0161\u00edme se na v\u00e1s p\u0159i dal\u0161\u00edm dobrodru\u017estv\u00ed!</p>
<p>S pozdravem,<br>T\u00fdm MotoGo24</p>`
      } else if (type === 'voucher_purchased') {
        // Voucher codes inline \u2014 parse vars.voucher_code "MGABCDEF (200 K\u010d), MGGHIJKL (300 K\u010d)"
        const codesRaw = (vars.voucher_code || '').trim()
        let codesBlock = ''
        if (codesRaw) {
          const parts = codesRaw.split(/,\s*/).filter(Boolean)
          const cards = parts.map((p: string) => {
            const m = p.match(/^([A-Z0-9]+)\s*(?:\(([^)]+)\))?/)
            const code = m?.[1] || p
            const amount = m?.[2] || ''
            return `<div style="background:#dcfce7;border:2px dashed #74FB71;border-radius:12px;padding:18px 16px;margin:0 0 12px;text-align:center">
              <div style="font-size:10px;font-weight:700;color:#166534;letter-spacing:2px;text-transform:uppercase;margin-bottom:6px">K\u00f3d poukazu</div>
              <div style="font-size:24px;font-weight:900;font-family:'Courier New',monospace;letter-spacing:3px;color:#0a1f15">${code}</div>
              ${amount ? `<div style="font-size:16px;font-weight:800;color:#166534;margin-top:6px">${amount}</div>` : ''}
              ${vars.voucher_expiry ? `<div style="font-size:11px;color:#166534;margin-top:6px">Platnost do: <strong>${vars.voucher_expiry}</strong></div>` : ''}
            </div>`
          }).join('')
          codesBlock = `<div style="margin:20px 0">${cards}</div>`
        }
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>d\u011bkujeme, \u017ee jste si pro sv\u016fj d\u00e1rek vybrali pr\u00e1v\u011b MotoGo24.</p>
<p>Va\u0161i objedn\u00e1vku \u010d. <strong>${vars.order_number}</strong> jsme \u00fasp\u011b\u0161n\u011b p\u0159ijali a platba byla zpracov\u00e1na.</p>
${codesBlock}
<p>V p\u0159\u00edloze tohoto e-mailu najdete:</p>
<ul><li>d\u00e1rkov\u00fd poukaz,</li><li>doklad o p\u0159ijet\u00ed platby za n\u00e1kup d\u00e1rkov\u00e9ho poukazu.</li></ul>
<p>Pokud jste si objednali ti\u0161t\u011bnou verzi poukazu, pr\u00e1v\u011b ji pro V\u00e1s p\u0159ipravujeme. V nejbli\u017e\u0161\u00edch dnech ji m\u016f\u017eete o\u010dek\u00e1vat ve sv\u00e9 po\u0161tovn\u00ed schr\u00e1nce.</p>
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informace k uplatn\u011bn\u00ed d\u00e1rkov\u00e9ho poukazu</h3>
<p>D\u00e1rkov\u00fd poukaz m\u00e1 platnost 3 roky od data vystaven\u00ed a je mo\u017en\u00e9 jej uplatnit na zap\u016fj\u010den\u00ed motocyklu dle vlastn\u00edho v\u00fdb\u011bru. Obdarovan\u00fd si jednodu\u0161e rezervuje term\u00edn j\u00edzdy p\u0159edem podle aktu\u00e1ln\u00ed dostupnosti motorek prost\u0159ednictv\u00edm formul\u00e1\u0159e na webov\u00fdch str\u00e1nk\u00e1ch <a href="https://www.motogo24.cz" style="color:#2563eb">motogo24.cz</a>.</p>
<p>P\u0159i rezervaci zad\u00e1 do kolonky Slevov\u00fd k\u00f3d jedine\u010dn\u00fd k\u00f3d uveden\u00fd na d\u00e1rkov\u00e9m poukazu. Jeho hodnota se automaticky ode\u010dte z ceny zap\u016fj\u010den\u00ed ji\u017e b\u011bhem rezervace. Pokud je v\u00fdsledn\u00e1 \u010d\u00e1stka vy\u0161\u0161\u00ed ne\u017e hodnota poukazu, rozd\u00edl lze pohodln\u011b uhradit online prost\u0159ednictv\u00edm platebn\u00ed br\u00e1ny.</p>
<p>D\u00e1rkov\u00e9 poukazy je mo\u017en\u00e9 kombinovat a uplatnit v\u00edce k\u00f3d\u016f sou\u010dasn\u011b. D\u00e1rkov\u00fd poukaz je nutn\u00e9 vy\u010derpat jednor\u00e1zov\u011b v r\u00e1mci jedn\u00e9 rezervace.</p>
<p>Doporu\u010dujeme rezervovat term\u00edn s dostate\u010dn\u00fdm p\u0159edstihem, zejm\u00e9na v hlavn\u00ed sez\u00f3n\u011b.</p>
<p>Kdybyste m\u011bli jak\u00fdkoliv dotaz, r\u00e1di V\u00e1m na n\u011bj odpov\u00edme.</p>
<p>D\u011bkujeme za d\u016fv\u011bru a p\u0159ejeme mnoho radosti z darovan\u00e9ho z\u00e1\u017eitku.</p>
<p>T\u00fdm MotoGo24</p>`
      } else if (type === 'door_codes') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>k va\u0161\u00ed rezervaci \u010d. <strong>${vars.booking_number}</strong> jsou nyn\u00ed k dispozici p\u0159\u00edstupov\u00e9 k\u00f3dy k pobo\u010dce.</p>
${vars.door_codes_block || `<p style="color:#dc2626">K\u00f3dy se zobraz\u00ed po ov\u011b\u0159en\u00ed doklad\u016f.</p>`}
<p>K\u00f3dy najdete tak\u00e9 v appce MotoGo24 v detailu rezervace a v sekci Zpr\u00e1vy.</p>
<p>T\u011b\u0161\u00edme se na v\u00e1s.</p>
<p>T\u00fdm MotoGo24</p>`
      } else if (type === 'sos_incident') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>p\u0159ijali jsme va\u0161e SOS hl\u00e1\u0161en\u00ed k rezervaci \u010d. <strong>${vars.booking_number}</strong>.</p>
<p><strong>Omlouv\u00e1me se za nep\u0159\u00edjemnosti a jsme na cest\u011b.</strong></p>
<p>N\u00e1\u0161 t\u00fdm se v\u00e1m ozve v nejbli\u017e\u0161\u00edch minut\u00e1ch. Pokud pot\u0159ebujete okam\u017eitou pomoc, volejte na <a href="tel:+420774256271" style="color:#2563eb;font-weight:700">+420 774 256 271</a>.</p>
<p>T\u00fdm MotoGo24</p>`
      } else if (type === 'booking_modified') {
        // Diff tabulka — řádek per pole, jen pokud se změnilo (nebo neznáme original)
        const diffRow = (label: string, oldVal: string, newVal: string): string => {
          if (!oldVal && !newVal) return ''
          const changed = oldVal && newVal && oldVal !== newVal
          return `<tr>
            <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;color:#6b7280;font-size:12px">${label}</td>
            <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;color:${changed ? '#9ca3af' : '#0f1a14'};${changed ? 'text-decoration:line-through' : ''};font-size:13px">${oldVal || '—'}</td>
            <td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;color:${changed ? '#16a34a' : '#0f1a14'};font-weight:${changed ? '700' : '400'};font-size:13px">${newVal || '—'}</td>
          </tr>`
        }
        const pickupOrig = [vars.original_pickup_method, vars.original_pickup_address].filter(Boolean).join(' — ')
        const pickupNew  = [vars.pickup_method, vars.pickup_address].filter(Boolean).join(' — ')
        const returnOrig = [vars.original_return_method, vars.original_return_address].filter(Boolean).join(' — ')
        const returnNew  = [vars.return_method, vars.return_address].filter(Boolean).join(' — ')

        const pd = Number((price_difference || 0).toString().replace(/\s/g, '').replace(',', '.')) || 0
        let priceMessage = ''
        if (pd > 0)      priceMessage = `<p>K úpravě se vztahuje <strong>doplatek ${vars.price_difference}</strong>. Po platbě dorazí doklad k přijaté platbě.</p>`
        else if (pd < 0) priceMessage = `<p>K úpravě se vztahuje <strong>vrácení ${vars.price_difference}</strong> formou dobropisu, který najdete v příloze. Refund jde zpět na původní platební kartu.</p>`

        templateHtml = `<p>Dobrý den,</p>
<p>vaše rezervace č. <strong>${vars.booking_number}</strong> byla upravena. Níže najdete kompletní přehled změn — původní hodnoty jsou přeškrtnuté, nové zvýrazněné zeleně.</p>
<table style="width:100%;border-collapse:collapse;margin:16px 0;border:1px solid #e5e7eb">
  <thead>
    <tr style="background:#f9fafb">
      <th style="padding:10px 12px;text-align:left;font-size:11px;color:#6b7280;letter-spacing:.5px;text-transform:uppercase">Údaj</th>
      <th style="padding:10px 12px;text-align:left;font-size:11px;color:#6b7280;letter-spacing:.5px;text-transform:uppercase">Původní</th>
      <th style="padding:10px 12px;text-align:left;font-size:11px;color:#6b7280;letter-spacing:.5px;text-transform:uppercase">Nové</th>
    </tr>
  </thead>
  <tbody>
    ${diffRow('Motorka',           vars.original_motorcycle,    vars.motorcycle)}
    ${diffRow('Začátek',           vars.original_start_date,    vars.start_date)}
    ${diffRow('Konec',             vars.original_end_date,      vars.end_date)}
    ${diffRow('Místo převzetí',    pickupOrig,                  pickupNew)}
    ${diffRow('Místo vrácení',     returnOrig,                  returnNew)}
    ${diffRow('Celková cena',      vars.original_total_price,   vars.total_price)}
  </tbody>
</table>
${priceMessage}
<p>V příloze najdete <strong>aktualizovanou nájemní smlouvu a VOP</strong>${pd > 0 ? ' a <strong>doklad o přijaté platbě</strong> za doplatek' : pd < 0 ? ' a <strong>dobropis</strong> na vrácenou částku' : ''}.</p>
<p>Pokud změnu neiniciovali jste vy a jde o nesrovnalost, ihned nás kontaktujte na <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>.</p>
<p>S pozdravem,<br>Tým MotoGo24</p>`
      } else if (type === 'shop_order_confirmed') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>d\u011bkujeme za va\u0161i objedn\u00e1vku v e-shopu MotoGo24. Va\u0161i platbu jsme \u00fasp\u011b\u0161n\u011b p\u0159ijali.</p>
<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">
  <tr><td style="padding:6px 0;color:#6b7280">\u010c\u00edslo objedn\u00e1vky:</td><td style="padding:6px 0;font-weight:700;color:#0f1a14">${vars.order_number}</td></tr>
  <tr><td style="padding:6px 0;color:#6b7280">Celkov\u00e1 cena:</td><td style="padding:6px 0;font-weight:700;color:#0f1a14">${vars.total_price}</td></tr>
  ${vars.shipping_cost ? `<tr><td style="padding:6px 0;color:#6b7280">Doprava:</td><td style="padding:6px 0;color:#0f1a14">${vars.shipping_cost}</td></tr>` : ''}
</table>
<p>V p\u0159\u00edloze najdete <strong>doklad o p\u0159ijat\u00e9 platb\u011b</strong>.</p>
<p>Jakmile va\u0161i objedn\u00e1vku p\u0159iprav\u00edme a p\u0159ed\u00e1me p\u0159epravci, po\u0161leme v\u00e1m e-mail s tracking \u010d\u00edslem a fin\u00e1ln\u00ed fakturou.</p>
<p>Pokud m\u00e1te jak\u00fdkoliv dotaz, jsme v\u00e1m k dispozici.</p>
<p>S pozdravem,<br>T\u00fdm MotoGo24</p>`
      } else if (type === 'shop_order_shipped') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>va\u0161e objedn\u00e1vka \u010d. <strong>${vars.order_number}</strong> byla odesl\u00e1na a brzy doraz\u00ed k v\u00e1m.</p>
${vars.tracking_number ? `<table style="width:100%;border-collapse:collapse;margin:16px 0;font-size:13px">
  <tr><td style="padding:6px 0;color:#6b7280">\u010c\u00edslo z\u00e1silky:</td><td style="padding:6px 0;font-weight:700;color:#0f1a14;font-family:monospace">${vars.tracking_number}</td></tr>
  ${vars.tracking_url ? `<tr><td style="padding:6px 0;color:#6b7280">Sledov\u00e1n\u00ed:</td><td style="padding:6px 0"><a href="${vars.tracking_url}" style="color:#2563eb">${vars.tracking_url}</a></td></tr>` : ''}
</table>` : ''}
<p>V p\u0159\u00edloze najdete <strong>kone\u010dnou fakturu</strong> za tuto objedn\u00e1vku.</p>
<p>D\u011bkujeme za n\u00e1kup u MOTO GO 24 a v\u011b\u0159\u00edme, \u017ee budete s n\u00e1kupem spokojeni.</p>
<p>S pozdravem,<br>T\u00fdm MotoGo24</p>`
      } else {
        templateHtml = `<p>Dobr\u00fd den,</p><p>toto je automatick\u00e9 ozn\u00e1men\u00ed od MotoGo24 t\u00fdkaj\u00edc\u00ed se va\u0161\u00ed rezervace \u010d. <strong>${vars.booking_number}</strong>.</p>`
      }
    }

    // Google review CTA button — appended jen pro shop expedici. Pro booking_completed
    // jsou odkazy na recenze (Google/Facebook/Instagram) už přímo v šabloně, aby se
    // Google neopakoval 2×.
    if (type === 'shop_order_shipped') {
      templateHtml = templateHtml + googleReviewBlock(custLang, vars.google_review_url)
    }

    // Zdoménuj odkazy v těle mailu na zákazníkovu doménu (jen non-cs; e-mail
    // info@motogo24.cz se nemění). Pokrývá DB šablonu, i18n překlad i CZ fallback.
    templateHtml = localizeBodyLinks(templateHtml, custLang)
    const html = wrapInBrandedLayout(templateHtml, custLang)

    // Admin kopie do info@motogo24.cz vždy v CZ (Velin admin čte v CZ).
    // Pokud zákazník dostal jiný jazyk, rerendrujeme CZ verzi pro admin kopii.
    let adminHtml = html
    let adminSubject = subject
    if (custLang !== 'cs') {
      // Re-render všeho v CZ pro admin
      let csTemplateHtml = ''
      let csSubject = ''
      // Zkusit DB CZ
      for (const trySlug of slugsToTry) {
        const { data: tpl } = await supabase
          .from('email_templates')
          .select('slug, subject, body_html, active')
          .eq('slug', trySlug)
          .eq('active', true)
          .maybeSingle()
        if (tpl?.body_html) {
          const csBodySrc = trySlug.includes('completed') ? fixReviewLinks(tpl.body_html) : tpl.body_html
          csTemplateHtml = renderTemplate(csBodySrc, vars)
          csSubject = renderTemplate(tpl.subject || '', vars)
          break
        }
      }
      if (!csTemplateHtml) {
        const i18nCs = renderEmail(type, 'cs', vars)
        if (i18nCs) { csSubject = i18nCs.subject; csTemplateHtml = i18nCs.body }
      }
      if (!csSubject) {
        const fallbackFn = FALLBACK_SUBJECTS[type]
        csSubject = fallbackFn ? fallbackFn(vars) : `Oznámení — MOTO GO 24`
      }
      if (csTemplateHtml) {
        if (type === 'shop_order_shipped') {
          csTemplateHtml = csTemplateHtml + googleReviewBlock('cs', vars.google_review_url)
        }
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

    // Pravidlo: Velín DB šablona (`email_templates.attachments`) je jediný zdroj pravdy o
    // přílohách. Caller-provided `attachments[]` (legacy webhook flow) se IGNORUJE — místo
    // toho edge fn vždy projde:
    //   1) hardcoded autoGenerate per typ (legacy logic — generuje booking-specific dokumenty)
    //   2) dbAttachmentsList přes attachmentTypeMap → autoGenerateAttachments synth typy
    // Filename dedup zachytí duplicitní přílohy mezi (1) a (2).
    let finalAttachments: SentAttachment[] = []
    const seenFilenames = new Set<string>()
    const seenPaths = new Set<string>()
    const addAttachmentUnique = (a: SentAttachment) => {
      if (!a) return
      if (seenFilenames.has(a.filename)) return
      // Dedup i přes storage_path — stejný doklad může přijít z hardcoded flow
      // i z Velín synth typu pod jiným filename (např. `Doklad-platby-uprava-DP-…`
      // z booking_modified vs `Doklad-platby-DP-…` z attachments=["DP"]).
      if (a.storage_path && seenPaths.has(a.storage_path)) return
      finalAttachments.push(a)
      seenFilenames.add(a.filename)
      if (a.storage_path) seenPaths.add(a.storage_path)
    }

    // 1) Hardcoded type-specific autoGenerate (booking_abandoned → ZF, booking_completed → KF,
    //    voucher_purchased → DP shop + voucher PDF, booking_modified → rozdílové ZF/DP + smlouva/VOP)
    const wantsAutoAtt =
      (booking_id && (
        type === 'booking_reserved' ||
        type === 'booking_abandoned' ||
        type === 'booking_completed' ||
        type === 'booking_modified' ||
        type === 'booking_cancelled'
      )) ||
      (order_id && (type === 'shop_order_confirmed' || type === 'shop_order_shipped' || type === 'voucher_purchased'))
    if (wantsAutoAtt) {
      try {
        const autoAtts = await autoGenerateAttachments(type, booking_id || '', supabase, {
          priceDifference: Number(price_difference || 0),
          orderId: order_id || undefined,
          lang: custLang,
        })
        for (const a of autoAtts) addAttachmentUnique(a)
      } catch { /* ignore */ }
    }

    // 2) Velín admin-configured přílohy z DB (dbAttachmentsList) — etalon ve Velíně.
    //    Pro booking kontext (ne shop) máme dedikované synth typy `booking_advance` (ZF)
    //    a `booking_payment_receipt` (DP) — fetchnou existující fakturu / vygenerují novou.
    //
    //    VÝJIMKA booking_modified (2026-06-11): u úpravy rezervace je finanční doklad
    //    řízený VÝHRADNĚ směrem změny ceny — ZF nechodí nikdy (platba šla rovnou bránou),
    //    DP jen při doplatku, Dobropis jen při vratce. Bez filtru synth typy přikládaly
    //    POSLEDNÍ existující ZF+DP (= doklady z původní platby) i při vratce, kde má
    //    přijít pouze dobropis. Smlouva/VOP z konfigurace zůstávají.
    if (type === 'booking_modified' && dbAttachmentsList.length > 0) {
      const pdNum = Number(price_difference || 0)
      dbAttachmentsList = dbAttachmentsList.filter((att) => {
        if (att === 'ZF' || att === 'KF') return false
        if (att === 'DP') return pdNum > 0
        if (att === 'Dobropis') return pdNum < 0
        return true
      })
    }
    if (dbAttachmentsList.length > 0 && (booking_id || order_id)) {
      const isShopCtx = !!order_id
      const attachmentTypeMap: Record<string, string> = {
        ZF:       isShopCtx ? 'shop_order_confirmed' : 'booking_advance',
        DP:       isShopCtx ? 'shop_order_confirmed' : 'booking_payment_receipt',
        KF:       isShopCtx ? 'shop_order_shipped'   : 'booking_completed',
        eshop_DP: 'shop_order_confirmed',
        eshop_KF: 'shop_order_shipped',
        Voucher:  'voucher_purchased',
        Smlouva:  'rental_contract',
        VOP:      'vop',
        Dobropis: 'credit_note',
      }
      for (const att of dbAttachmentsList) {
        const synthType = attachmentTypeMap[att]
        if (!synthType) continue
        try {
          const synth = await autoGenerateAttachments(synthType, booking_id || '', supabase, {
            priceDifference: Number(price_difference || 0),
            orderId: order_id || undefined,
            lang: custLang,
          })
          for (const a of synth) addAttachmentUnique(a)
        } catch { /* ignore */ }
      }
    }

    // Send via Resend with Reply-To: info@motogo24.cz + attachments
    const emailPayload: Record<string, unknown> = {
      from: FROM_EMAIL,
      reply_to: REPLY_TO,
      to: customer_email,
      subject,
      html,
    }
    if (finalAttachments.length > 0) {
      // Resend přijímá pouze content+filename — storage_path je interní pro Velín log
      emailPayload.attachments = finalAttachments.map((a) => ({ content: a.content, filename: a.filename }))
    }
    const result = await sendWithRetry(emailPayload)

    // Admin kopie do info@motogo24.cz — vždy v CZ (rerendrováno výše),
    // bez příloh (bandwidth save). Pokud zákazník dostal jiný jazyk, jde o
    // separátní mail (Velin admin nevidí cizojazyčnou verzi).
    if (result.success) {
      try {
        await sendWithRetry({
          from: FROM_EMAIL,
          to: REPLY_TO,
          subject: `[Kopie${custLang !== 'cs' ? ` — zákazník ${custLang.toUpperCase()}` : ''}] ${adminSubject}`,
          html: adminHtml,
        })
      } catch (e) { /* ignore */ }
    }

    // Log to message_log
    try {
      await supabase.from('message_log').insert({
        channel: 'email',
        direction: 'outbound',
        recipient_email: customer_email,
        booking_id: booking_id || null,
        template_slug: slug,
        content_preview: subject.slice(0, 160),
        body: html,
        external_id: result.provider_id || null,
        status: result.success ? 'sent' : 'failed',
        metadata: { attachments: finalAttachments.map((a) => ({ filename: a.filename, storage_path: a.storage_path || null })) },
        error_message: result.error || null,
      })
    } catch (e) { /* ignore */ }

    // Log to sent_emails — attachments_meta jsonb obsahuje názvy + storage_path příloh,
    // SentEmailsTab je čte a generuje signed URL pro náhled / stažení.
    try {
      await supabase.from('sent_emails').insert({
        template_slug: slug,
        recipient_email: customer_email,
        booking_id: booking_id || null,
        subject,
        body_html: html,
        status: result.success ? 'sent' : 'failed',
        error_message: result.error || null,
        provider_id: result.provider_id || null,
        attachments_meta: finalAttachments.map((a) => ({ filename: a.filename, storage_path: a.storage_path || null })),
      })
    } catch (e) { /* ignore */ }

    if (!result.success) {
      try {
        await supabase.from('debug_log').insert({
          source: 'send-booking-email',
          action: 'email_send_failed',
          component: 'resend',
          status: 'error',
          error_message: result.error,
          request_data: { type, customer_email, booking_id, source },
        })
      } catch (e) { /* ignore */ }

      return new Response(JSON.stringify({ error: 'Email send failed', details: result.error }), {
        status: 502,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ success: true, provider_id: result.provider_id }), {
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
