import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz'
const REPLY_TO = 'info@motogo24.cz'
const SITE_URL = Deno.env.get('SITE_URL') || 'https://motogo24.cz'
const PUBLIC_QR_TARGET = 'https://motogo24.cz'

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
function wrapInBrandedLayout(bodyHtml: string): string {
  const header = `<div style="background:#000000;padding:28px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
      <td style="vertical-align:middle;padding-right:16px;width:64px"><img src="${SITE_URL}/gfx/logo-icon.png" alt="MotoGo24" width="64" height="64" style="display:block;border:0"/></td>
      <td style="vertical-align:middle">
        <div style="color:#ffffff;font-size:24px;font-weight:900;letter-spacing:2px;line-height:1">MOTO GO 24</div>
        <div style="color:#ffffff;font-size:10px;font-weight:400;letter-spacing:4px;margin-top:6px">P\u016eJ\u010cOVNA MOTOREK</div>
      </td>
    </tr></table>
  </div>`
  const helpCard = `<div style="margin:24px 32px 0;background:#000000;border:2px solid #74FB71;border-radius:8px;padding:24px">
    <div style="color:#74FB71;font-size:18px;font-weight:800;margin:0 0 8px">M\u00e1te dotaz?</div>
    <div style="color:#ffffff;font-size:13px;margin:0 0 16px">Pokud budete m\u00edt jak\u00fdkoliv dotaz, jsme v\u00e1m k dispozici.</div>
    <a href="mailto:info@motogo24.cz" style="display:inline-block;background:#74FB71;color:#000000;font-size:13px;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:24px">info@motogo24.cz</a>
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
          <div><span style="color:#9ca3af">Web:</span> <span style="color:#74FB71">motogo24.cz</span></div>
        </div>
      </td>
      <td style="vertical-align:top;width:120px;text-align:center">
        <a href="${PUBLIC_QR_TARGET}" style="text-decoration:none"><img src="https://api.qrserver.com/v1/create-qr-code/?size=220x220&amp;margin=8&amp;data=${encodeURIComponent(PUBLIC_QR_TARGET)}" alt="motogo24.cz" width="110" height="110" style="display:block;background:#ffffff;padding:6px;border-radius:4px"/></a>
      </td>
    </tr></table>
  </div>`

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="UTF-8"></head>
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
  booking_cancelled: (v) => `Va\u0161e rezervace \u010d. ${v.booking_number} motocyklu u MotoGo24 byla \u00fasp\u011b\u0161n\u011b stornov\u00e1na`,
  sos_incident: () => `SOS \u2014 MotoGo24 je na cest\u011b`,
  door_codes: (v) => `P\u0159\u00edstupov\u00e9 k\u00f3dy k pobo\u010dce \u2014 rezervace \u010d. ${v.booking_number}`,
  shop_order_confirmed: (v) => `Objedn\u00e1vka \u010d. ${v.order_number} p\u0159ijata \u2014 MOTO GO 24`,
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

/** Auto-generate attachments based on email type */
async function autoGenerateAttachments(
  type: string,
  booking_id: string,
  supabase: any,
  opts: { priceDifference?: number; orderId?: string } = {}
): Promise<{ content: string; filename: string }[]> {
  const atts: { content: string; filename: string }[] = []
  const headers = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`, 'apikey': SUPABASE_SERVICE_KEY }

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
        if (b64) atts.push({ content: b64, filename: `Doklad-platby-${dp[0].number || 'DP'}.html` })
      } else {
        // DP neexistuje → pokus o generování
        const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', order_id: opts.orderId, source: 'shop', send_email: false }),
        })
        const data = await res.json().catch(() => ({}))
        if (data.success && data.invoice_id) {
          const b64 = await downloadAsBase64(supabase, `invoices/${data.invoice_id}.html`)
          if (b64) atts.push({ content: b64, filename: `Doklad-platby-${data.number || 'DP'}.html` })
        }
      }
    } catch { /* ignore */ }
    return atts
  }

  if (!booking_id) return atts

  if (type === 'booking_abandoned') {
    // Generate ZF (proforma) for abandoned bookings — shows what needs to be paid
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
        method: 'POST', headers,
        body: JSON.stringify({ type: 'advance', booking_id, send_email: false }),
      })
      const data = await res.json().catch(() => ({}))
      if (data.success && data.invoice_id) {
        const b64 = await downloadAsBase64(supabase, `invoices/${data.invoice_id}.html`)
        if (b64) atts.push({ content: b64, filename: `Zalohova-faktura-${data.number || 'ZF'}.html` })
      }
    } catch { /* ignore */ }
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
      if (invoices?.length && invoices[0].pdf_path) {
        const b64 = await downloadAsBase64(supabase, invoices[0].pdf_path)
        if (b64) atts.push({ content: b64, filename: `Konecna-faktura-${invoices[0].number || 'KF'}.html` })
      }
    } catch { /* ignore */ }
  }

  if (type === 'booking_modified') {
    const priceDifference = Number(opts.priceDifference || 0)

    if (priceDifference > 0) {
      // Prodloužení / navýšení ceny → nová rozdílová ZF + DP (source='edit')
      try {
        const zfRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'advance', booking_id, source: 'edit', send_email: false }),
        })
        const zfData = await zfRes.json().catch(() => ({}))
        if (zfData.success && zfData.invoice_id) {
          const b64 = await downloadAsBase64(supabase, `invoices/${zfData.invoice_id}.html`)
          if (b64) atts.push({ content: b64, filename: `Zalohova-faktura-uprava-${zfData.number || 'ZF'}.html` })
        }
      } catch { /* ignore */ }

      try {
        const dpRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-invoice`, {
          method: 'POST', headers,
          body: JSON.stringify({ type: 'payment_receipt', booking_id, source: 'edit', send_email: false }),
        })
        const dpData = await dpRes.json().catch(() => ({}))
        if (dpData.success && dpData.invoice_id) {
          const b64 = await downloadAsBase64(supabase, `invoices/${dpData.invoice_id}.html`)
          if (b64) atts.push({ content: b64, filename: `Doklad-platby-uprava-${dpData.number || 'DP'}.html` })
        }
      } catch { /* ignore */ }
    } else if (priceDifference < 0) {
      // Zkrácení → dobropis + refund se řeší přes process-refund (volá ho velin modal),
      // zde pouze přiložíme již vystavený dobropis (credit_note s source='refund') pokud existuje.
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
          if (b64) atts.push({ content: b64, filename: `Dobropis-${cn[0].number || 'DB'}.html` })
        }
      } catch { /* ignore */ }
    }
    // priceDifference === 0 → žádná nová faktura, jen aktualizovaná smlouva/VOP níže

    // 3. Updated rental contract
    try {
      const cRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST', headers,
        body: JSON.stringify({ template_slug: 'rental_contract', booking_id }),
      })
      const cData = await cRes.json().catch(() => ({}))
      if (cData.success && cData.path) {
        const b64 = await downloadAsBase64(supabase, cData.path)
        if (b64) atts.push({ content: b64, filename: `Najemni-smlouva-${booking_id.slice(-8).toUpperCase()}.html` })
      }
    } catch { /* ignore */ }

    // 4. VOP
    try {
      const vRes = await fetch(`${SUPABASE_URL}/functions/v1/generate-document`, {
        method: 'POST', headers,
        body: JSON.stringify({ template_slug: 'vop', booking_id }),
      })
      const vData = await vRes.json().catch(() => ({}))
      if (vData.success && vData.path) {
        const b64 = await downloadAsBase64(supabase, vData.path)
        if (b64) atts.push({ content: b64, filename: `VOP-${booking_id.slice(-8).toUpperCase()}.html` })
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
      attachments,
      // Shop order extras
      order_id,
      shipping_cost,
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
      return_method,
      return_address,
    } = body

    if (!type || !customer_email) {
      return new Response(JSON.stringify({ error: 'Missing type or customer_email' }), {
        status: 400,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const vars: Record<string, string> = {
      customer_name: customer_name || '',
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
      google_review_url: google_review_url || '',
      facebook_review_url: facebook_review_url || '',
      manual_url: manual_url || '',
      door_code_moto: '',
      door_code_gear: '',
      door_codes_block: '',
      // {{business_card}} placeholder se v DB šabloně auto-vyčistí — brand header/footer je v wrapInBrandedLayout
    }

    // Load active door codes for this booking (if released to customer)
    if (booking_id) {
      try {
        const { data: codes } = await supabase
          .from('branch_door_codes')
          .select('code_type, door_code, sent_to_customer, withheld_reason, is_active')
          .eq('booking_id', booking_id)
          .eq('is_active', true)
        if (codes?.length) {
          const released = codes.filter((c: any) => c.sent_to_customer === true && !c.withheld_reason)
          const moto = released.find((c: any) => c.code_type === 'motorcycle')?.door_code || ''
          const gear = released.find((c: any) => c.code_type === 'accessories')?.door_code || ''
          vars.door_code_moto = moto
          vars.door_code_gear = gear
          if (moto || gear) {
            vars.door_codes_block = `
<div style="background:#e0f2fe;border-radius:12px;padding:16px 20px;margin:20px 0;border:1px solid #7dd3fc">
  <h3 style="margin:0 0 12px 0;color:#0c4a6e;font-size:15px">Přístupové kódy k pobočce</h3>
  <p style="margin:4px 0;font-size:14px;font-weight:700;font-family:'Courier New',monospace;color:#0c4a6e">Kód k motorce: <span style="font-size:18px;letter-spacing:3px;color:#0369a1">${moto || '—'}</span></p>
  <p style="margin:4px 0;font-size:14px;font-weight:700;font-family:'Courier New',monospace;color:#0c4a6e">Kód k příslušenství: <span style="font-size:18px;letter-spacing:3px;color:#0369a1">${gear || '—'}</span></p>
  <p style="margin:8px 0 0 0;font-size:12px;color:#075985">Kódy jsou platné po dobu trvání pronájmu.</p>
</div>`
          }
        }
      } catch { /* ignore */ }
    }

    // Try to load template from DB (first web-specific, then generic)
    const slug = resolveSlug(type, source)
    let templateHtml = ''
    let subject = ''

    // Try web-specific slug first if source=web, then fall back to generic
    const slugsToTry = source === 'web' ? [slug, type] : [type]

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

    // If no template found in DB, use fallback subject
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
<p>Doporu\u010dujeme, abyste se p\u0159ed j\u00edzdou sezn\u00e1mili s u\u017eivatelsk\u00fdmi informacemi k motocyklu, kter\u00e9 najdete v odkazu na na\u0161ich webov\u00fdch str\u00e1nk\u00e1ch <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.</p>
<p>Pokud budete m\u00edt jak\u00fdkoliv dotaz, jsme v\u00e1m k dispozici.</p>
<p>T\u011b\u0161\u00edme se na v\u00e1s a p\u0159ejeme kr\u00e1sn\u00fd z\u00e1\u017eitek z j\u00edzdy.</p>
<p>T\u00fdm MotoGo24</p>`
      } else if (type === 'booking_completed') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>d\u011bkujeme, \u017ee jste vyu\u017eili slu\u017eeb MotoGo24.</p>
<p>Proto\u017ee je pro n\u00e1s zp\u011btn\u00e1 vazba velmi d\u016fle\u017eit\u00e1, budeme r\u00e1di, pokud n\u00e1m zanech\u00e1te recenzi na <a href="${vars.google_review_url || '#'}" style="color:#2563eb">Googlu</a> nebo na <a href="${vars.facebook_review_url || '#'}" style="color:#2563eb">Facebooku</a>.</p>
<p>Pokud m\u00e1te n\u011bjak\u00e9 zaj\u00edmav\u00e9 fotografie nebo videa z va\u0161\u00ed cesty, kter\u00e9 byste s n\u00e1mi cht\u011bli sd\u00edlet, za\u0161lete n\u00e1m je, pros\u00edm, na e-mail: <a href="mailto:info@motogo24.cz" style="color:#2563eb">info@motogo24.cz</a>. R\u00e1di je p\u0159\u00edpadn\u011b zve\u0159ejn\u00edme na na\u0161em webu nebo soci\u00e1ln\u00edch s\u00edt\u00edch.</p>
${vars.discount_code ? `<div style="background:#dcfce7;border-radius:12px;padding:16px;margin:20px 0;border:1px solid #86efac"><p style="margin:0;font-size:14px;color:#166534">Jako mal\u00e9 pod\u011bkov\u00e1n\u00ed za poskytnutou d\u016fv\u011bru p\u0159ikl\u00e1d\u00e1me slevov\u00fd k\u00f3d <strong>200 K\u010d</strong> na va\u0161i p\u0159\u00ed\u0161t\u00ed rezervaci: <strong style="font-family:monospace;font-size:16px;letter-spacing:2px">${vars.discount_code}</strong></p></div>` : ''}
<p>V p\u0159\u00edloze naleznete kone\u010dnou fakturu za va\u0161i rezervaci.</p>
${vars.door_codes_block}
<p>T\u011b\u0161\u00edme se na v\u00e1s p\u0159i dal\u0161\u00edm dobrodru\u017estv\u00ed!</p>
<p>S pozdravem,<br>T\u00fdm MotoGo24</p>`
      } else if (type === 'voucher_purchased') {
        templateHtml = `<p>Dobr\u00fd den,</p>
<p>d\u011bkujeme, \u017ee jste si pro sv\u016fj d\u00e1rek vybrali pr\u00e1v\u011b MotoGo24.</p>
<p>Va\u0161i objedn\u00e1vku \u010d. <strong>${vars.order_number}</strong> jsme \u00fasp\u011b\u0161n\u011b p\u0159ijali a platba byla zpracov\u00e1na.</p>
<p>V p\u0159\u00edloze tohoto e-mailu najdete:</p>
<ul><li>d\u00e1rkov\u00fd poukaz,</li><li>doklad o p\u0159ijet\u00ed platby za n\u00e1kup d\u00e1rkov\u00e9ho poukazu.</li></ul>
<p>Pokud jste si objednali ti\u0161t\u011bnou verzi poukazu, pr\u00e1v\u011b ji pro V\u00e1s p\u0159ipravujeme. V nejbli\u017e\u0161\u00edch dnech ji m\u016f\u017eete o\u010dek\u00e1vat ve sv\u00e9 po\u0161tovn\u00ed schr\u00e1nce.</p>
<h3 style="color:#1a2e22;font-size:15px;margin-top:24px">Informace k uplatn\u011bn\u00ed d\u00e1rkov\u00e9ho poukazu</h3>
<p>D\u00e1rkov\u00fd poukaz m\u00e1 platnost 3 roky od data vystaven\u00ed a je mo\u017en\u00e9 jej uplatnit na zap\u016fj\u010den\u00ed motocyklu dle vlastn\u00edho v\u00fdb\u011bru. Obdarovan\u00fd si jednodu\u0161e rezervuje term\u00edn j\u00edzdy p\u0159edem podle aktu\u00e1ln\u00ed dostupnosti motorek prost\u0159ednictv\u00edm formul\u00e1\u0159e na webov\u00fdch str\u00e1nk\u00e1ch <a href="https://motogo24.cz" style="color:#2563eb">motogo24.cz</a>.</p>
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
        if (pd > 0)      priceMessage = `<p>K úpravě se vztahuje <strong>doplatek ${vars.price_difference}</strong>. Po platbě dorazí daňový doklad.</p>`
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
<p>V příloze najdete <strong>aktualizovanou nájemní smlouvu, VOP</strong> a všechny <strong>nové daňové doklady</strong> (zálohová faktura, doklad o platbě, případně dobropis).</p>
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
      } else {
        templateHtml = `<p>Dobr\u00fd den,</p><p>toto je automatick\u00e9 ozn\u00e1men\u00ed od MotoGo24 t\u00fdkaj\u00edc\u00ed se va\u0161\u00ed rezervace \u010d. <strong>${vars.booking_number}</strong>.</p>`
      }
    }

    const html = wrapInBrandedLayout(templateHtml)

    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), {
        status: 500,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Auto-generate attachments per type
    let finalAttachments = attachments && Array.isArray(attachments) ? [...attachments] : []
    const wantsAutoAtt =
      (booking_id && (type === 'booking_abandoned' || type === 'booking_completed' || type === 'booking_modified')) ||
      (order_id && type === 'shop_order_confirmed')
    if (wantsAutoAtt) {
      try {
        const autoAtts = await autoGenerateAttachments(type, booking_id || '', supabase, {
          priceDifference: Number(price_difference || 0),
          orderId: order_id || undefined,
        })
        finalAttachments = [...finalAttachments, ...autoAtts]
      } catch { /* ignore */ }
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
      emailPayload.attachments = finalAttachments
    }
    const result = await sendWithRetry(emailPayload)

    // Also send copy to info@motogo24.cz (without attachments to save bandwidth)
    if (result.success) {
      try {
        await sendWithRetry({
          from: FROM_EMAIL,
          to: REPLY_TO,
          subject: `[Kopie] ${subject}`,
          html,
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
        error_message: result.error || null,
      })
    } catch (e) { /* ignore */ }

    // Log to sent_emails
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
