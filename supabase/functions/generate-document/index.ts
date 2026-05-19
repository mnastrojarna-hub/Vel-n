import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const PDFSHIFT_API_KEY = Deno.env.get('PDFSHIFT_API_KEY') || ''

/** HTML → PDF přes PDFShift API. Vrací Uint8Array nebo null při chybě / no key. */
async function htmlToPdf(html: string): Promise<Uint8Array | null> {
  if (!PDFSHIFT_API_KEY) return null
  try {
    const res = await fetch('https://api.pdfshift.io/v3/convert/pdf', {
      method: 'POST',
      headers: { 'X-API-Key': PDFSHIFT_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: html, format: 'A4', margin: '12mm', landscape: false, sandbox: false, use_print: false }),
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

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

/**
 * Sestaví seznam zapůjčeného příslušenství (velikosti) z reálné rezervace.
 * - vždy řádky pro řidiče (helma/bunda/kalhoty/boty/rukavice) podle vyplněných `*_size`
 * - pokud má spolujezdec vyplněnou aspoň jednu velikost → druhá sada řádků "(spolujezdec)"
 *   (klidně chybí boty / jen 2 velikosti — vypíše se jen to, co je objednané)
 * - u dětských motorek (`motorcycles.license_required === 'N'`) přidá "(dětská velikost)"
 * Vrací HTML tabulku pro {{accessories_block}} a textovou variantu pro {{accessories}}.
 */
function buildAccessoriesBlock(booking: any, moto: any): { html: string; text: string } {
  const isChild = String(moto?.license_required || '').toUpperCase() === 'N'
  const childSuffix = isChild ? ' (dětská velikost)' : ''
  const items = [
    { key: 'helmet', label: 'Helma' },
    { key: 'jacket', label: 'Bunda / vesta' },
    { key: 'pants', label: 'Kalhoty' },
    { key: 'boots', label: 'Boty' },
    { key: 'gloves', label: 'Rukavice' },
  ]
  const rows: string[] = []
  const textParts: string[] = []
  const td = 'padding:6px 8px;border:1px solid #ddd;text-align:left'
  const addRow = (label: string, size: string) => {
    rows.push(`<tr><td style="${td};background:#f8faf9;font-weight:600">${label}${childSuffix}</td><td style="${td}">${size}</td><td style="${td};text-align:center;width:60px">☐</td></tr>`)
    textParts.push(`${label} ${size}`)
  }
  let hasRider = false
  for (const it of items) {
    const size = booking?.[`${it.key}_size`]
    if (size) { addRow(`${it.label} (řidič)`, String(size)); hasRider = true }
  }
  let hasPassenger = false
  for (const it of items) {
    const size = booking?.[`passenger_${it.key}_size`]
    if (size) { addRow(`${it.label} (spolujezdec)`, String(size)); hasPassenger = true }
  }
  if (!hasRider && !hasPassenger) {
    return { html: '<p style="font-size:12px">Žádné zapůjčené příslušenství.</p>', text: 'Žádné' }
  }
  const th = 'padding:6px 8px;border:1px solid #ddd;text-align:left;background:#f0f7ff;font-weight:700;font-size:10px;text-transform:uppercase'
  const html = `<table class="checklist" style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="${th}">Položka</th><th style="${th}">Velikost</th><th style="${th}">Předáno</th></tr>${rows.join('')}</table>`
  return { html, text: textParts.join(', ') }
}

/** Convert number to Czech words (e.g. 7800 → "sedm tisíc osm set") */
function numberToWordsCZ(n: number): string {
  if (n === 0) return 'nula'
  const ones = ['', 'jedna', 'dvě', 'tři', 'čtyři', 'pět', 'šest', 'sedm', 'osm', 'devět']
  const teens = ['deset', 'jedenáct', 'dvanáct', 'třináct', 'čtrnáct', 'patnáct', 'šestnáct', 'sedmnáct', 'osmnáct', 'devatenáct']
  const tens = ['', 'deset', 'dvacet', 'třicet', 'čtyřicet', 'padesát', 'šedesát', 'sedmdesát', 'osmdesát', 'devadesát']
  const hundreds = ['', 'sto', 'dvě stě', 'tři sta', 'čtyři sta', 'pět set', 'šest set', 'sedm set', 'osm set', 'devět set']

  const parts: string[] = []
  const abs = Math.abs(Math.floor(n))
  if (abs >= 1000000) { const m = Math.floor(abs / 1000000); parts.push(m === 1 ? 'milion' : m < 5 ? m + ' miliony' : m + ' milionů'); }
  const thousands = Math.floor((abs % 1000000) / 1000)
  if (thousands > 0) {
    if (thousands === 1) parts.push('tisíc')
    else if (thousands < 5) parts.push(numberToWordsCZ(thousands).replace('dvě', 'dva') + ' tisíce')
    else parts.push(numberToWordsCZ(thousands).replace('dvě', 'dva') + ' tisíc')
  }
  const rest = abs % 1000
  if (rest > 0) {
    const h = Math.floor(rest / 100)
    const t = Math.floor((rest % 100) / 10)
    const o = rest % 10
    if (h > 0) parts.push(hundreds[h])
    if (rest % 100 >= 10 && rest % 100 < 20) { parts.push(teens[rest % 100 - 10]) }
    else { if (t > 0) parts.push(tens[t]); if (o > 0) parts.push(ones[o]) }
  }
  const result = parts.join(' ').trim()
  const dec = Math.round((Math.abs(n) - abs) * 100)
  if (dec > 0) return `${n < 0 ? 'mínus ' : ''}${result} korun českých a ${dec}/100`
  return `${n < 0 ? 'mínus ' : ''}${result} korun českých`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { template_slug, booking_id } = await req.json()
    if (!template_slug || !booking_id) {
      return new Response(JSON.stringify({ error: 'Missing template_slug or booking_id' }), { status: 400 })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Načtení firemních údajů z app_settings
    let companyInfo = { name: 'Bc. Petra Semorádová', address: 'Mezná 9, 393 01 Mezná', ico: '21874263', dic: '' }
    try {
      const { data: settings } = await supabase
        .from('app_settings').select('value').eq('key', 'company_info').limit(1)
      const info = settings?.[0]?.value
      if (info && info.name) {
        companyInfo = { name: info.name, address: info.address || companyInfo.address, ico: info.ico || companyInfo.ico, dic: info.dic || '' }
      }
    } catch (e) { console.warn('Failed to load company_info:', e) }

    // Load template from DB (avoid .single() — errors on 0 or 2+ rows)
    const { data: templates, error: tErr } = await supabase
      .from('document_templates')
      .select('*')
      .eq('type', template_slug)
      .eq('active', true)
      .order('version', { ascending: false })
      .limit(1)

    const template = templates?.[0] || null
    if (tErr) console.error('Template query error:', tErr.message, 'slug:', template_slug)

    if (!template) {
      console.warn('No DB template for slug:', template_slug, '— using fallback')
      const fallbackHtml = getFallbackTemplate(template_slug)
      if (!fallbackHtml) {
        return new Response(JSON.stringify({ error: `Template '${template_slug}' not found` }), { status: 404 })
      }
      // Continue with fallback
    } else {
      console.log('Loaded DB template:', template.id, template.name, 'content length:', (template.content_html || '').length)
    }

    // Load booking with relations (separate profile query to avoid FK ambiguity)
    const { data: booking, error: bErr } = await supabase
      .from('bookings')
      .select('*, motorcycles(model, spz, vin, year, brand, category, engine_cc, power_kw, color, deposit_amount, insurance_price, image_url, license_required)')
      .eq('id', booking_id).single()
    if (bErr || !booking) {
      console.error('Booking query error:', bErr?.message, 'booking_id:', booking_id)
      return new Response(JSON.stringify({ error: 'Booking not found: ' + (bErr?.message || 'no data') }), { status: 404 })
    }
    // Fetch profile separately to avoid PostgREST FK ambiguity
    let customer: Record<string, unknown> = {}
    if (booking.user_id) {
      const { data: prof } = await supabase.from('profiles')
        .select('id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry, license_group, date_of_birth, id_number, id_verified_until, license_verified_until, passport_verified_until')
        .eq('id', booking.user_id).single()
      if (prof) customer = prof
    }

    // Load booking extras
    let extrasHtml = ''
    try {
      const { data: extras } = await supabase.from('booking_extras')
        .select('name, quantity, unit_price').eq('booking_id', booking_id)
      if (extras?.length) {
        extrasHtml = extras.map((e: any) => `${e.name}${e.quantity > 1 ? ' ×' + e.quantity : ''} — ${fmtPrice(e.unit_price)} Kč`).join(', ')
      }
    } catch { /* ignore */ }

    // Load branch info
    let branchName = ''
    let branchAddress = ''
    if (booking.pickup_address) {
      branchAddress = booking.pickup_address
    } else {
      try {
        const { data: motoWithBranch } = await supabase.from('motorcycles')
          .select('branch_id, branches(name, address, city)').eq('id', booking.moto_id).single()
        if (motoWithBranch?.branches) {
          const br = motoWithBranch.branches as any
          branchName = br.name || ''
          branchAddress = [br.address, br.city].filter(Boolean).join(', ')
        }
      } catch { /* ignore */ }
    }

    const moto = booking.motorcycles || {} as any
    const accessories = buildAccessoriesBlock(booking, moto)
    // Inclusive day count — system pricing počítá start i end den (May 5 → May 6 = 2 dny).
    // Math.ceil dříve dávalo 1 den (24h diff) a smlouva nesouhlasila s cenou.
    const days = Math.max(1, Math.floor((new Date(booking.end_date).getTime() - new Date(booking.start_date).getTime()) / 86400000) + 1)
    const baseRental = (booking.total_price || 0) - (booking.extras_price || 0) - (booking.delivery_fee || 0) + (booking.discount_amount || 0)

    // Complete variable substitution map
    const vars: Record<string, string> = {
      // Customer
      customer_name: (customer.full_name as string) || '—',
      customer_email: (customer.email as string) || '',
      customer_phone: (customer.phone as string) || '',
      customer_address: [customer.street, customer.city, customer.zip, customer.country].filter(Boolean).join(', ') || '',
      customer_street: (customer.street as string) || '',
      customer_city: (customer.city as string) || '',
      customer_zip: (customer.zip as string) || '',
      customer_country: (customer.country as string) || 'Česká republika',
      customer_ico: (customer.ico as string) || '',
      customer_dic: (customer.dic as string) || '',
      customer_license: (customer.license_number as string) || '',
      customer_license_expiry: fmtDate(customer.license_expiry as string),
      customer_license_group: Array.isArray(customer.license_group) ? (customer.license_group as string[]).join(', ') : (customer.license_group as string) || '',
      customer_dob: fmtDate(customer.date_of_birth as string),
      customer_id_number: (customer.id_number as string) || '',
      // Platnost OP (z Mindee OCR `id_verified_until`) — pokud nebyl OP naskenován,
      // zůstane prázdné a zákazník platnost potvrzuje při převzetí motorky na pobočce.
      customer_id_expiry: fmtDate((customer.id_verified_until || customer.passport_verified_until) as string),
      // Motorcycle
      moto_model: moto.model || '—',
      moto_brand: moto.brand || '',
      moto_spz: moto.spz || '',
      moto_vin: moto.vin || '',
      moto_year: String(moto.year || ''),
      moto_category: moto.category || '',
      moto_engine: moto.engine_cc ? `${moto.engine_cc} ccm` : '',
      moto_power: moto.power_kw ? `${moto.power_kw} kW` : '',
      moto_color: moto.color || '',
      // Booking
      start_date: fmtDate(booking.start_date),
      end_date: fmtDate(booking.end_date),
      pickup_time: booking.pickup_time || '',
      days: String(days),
      total_price: fmtPrice(booking.total_price || 0),
      daily_rate: fmtPrice(days > 0 ? Math.round(baseRental / days) : 0),
      rental_price: fmtPrice(baseRental),
      extras_price: fmtPrice(booking.extras_price || 0),
      extras_list: extrasHtml || 'Žádné',
      delivery_fee: fmtPrice(booking.delivery_fee || 0),
      discount_amount: fmtPrice(booking.discount_amount || 0),
      discount_code: booking.discount_code || '',
      deposit: fmtPrice(moto.deposit_amount || booking.deposit || 0),
      insurance: fmtPrice(moto.insurance_price || 0),
      insurance_type: booking.insurance_type || 'Základní',
      // Pickup / Return
      pickup_method: booking.pickup_method === 'delivery' ? 'Přistavení' : 'Na pobočce',
      pickup_address: booking.pickup_address || branchAddress || '',
      return_method: booking.return_method === 'delivery' ? 'Odvoz' : 'Na pobočce',
      return_address: booking.return_address || branchAddress || '',
      branch_name: branchName,
      branch_address: branchAddress,
      // Booking IDs
      booking_id: booking_id.slice(-8),
      booking_number: booking_id.slice(-8).toUpperCase(),
      today: fmtDate(new Date().toISOString()),
      // Company
      company_name: companyInfo.name,
      company_address: companyInfo.address,
      company_ico: companyInfo.ico,
      company_dic: companyInfo.dic,
      company_phone: '+420 774 256 271',
      company_email: 'info@motogo24.cz',
      company_web: 'motogo24.cz',
      company_bank: 'mBank',
      company_account: '670100-2225851630/6210',
      // Time & period — start_time = pickup_time, end_time = return_time
      // (return_time je NULL pokud zákazník vrací v půjčovně, default UI 19:00)
      start_time: booking.pickup_time || '10:00',
      end_time: booking.return_time || '19:00',
      rental_period: days === 1 ? '1 den' : days < 5 ? `${days} dny` : `${days} dní`,
      // Price in words
      total_price_words: numberToWordsCZ(booking.total_price || 0),
      // Location aliases (templates may use either name)
      pickup_location: booking.pickup_address || branchAddress || '',
      return_location: booking.return_address || branchAddress || '',
      // Handover protocol — stav vozidla + automaticky vyplněné příslušenství
      mileage: String(booking.mileage_start || ''),
      technical_state: '',
      today_time: new Date().toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' }),
      accessories_block: accessories.html,
      accessories: accessories.text,
    }

    // Substitute variables in template HTML
    let htmlContent = template?.content_html || template?.html_content || getFallbackTemplate(template_slug) || ''
    for (const [key, val] of Object.entries(vars)) {
      htmlContent = htmlContent.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
    }

    // Velín RichTextEditor ukládá obsah jako fragment (<p>/<table>… bez <!DOCTYPE>).
    // PDFShift potřebuje plný HTML dokument — fakturní šablona ho generuje, ale
    // VOP/smlouvy/protokoly v DB ne, takže konverze selhávala a v mailu chodilo
    // .html místo .pdf. Pokud HTML není kompletní, obalíme ho minimální stránkou
    // se základní typografií (mirror styly z RichTextEditor preview).
    const isFullDoc = /^\s*(?:<!doctype|<html\b)/i.test(htmlContent)
    if (!isFullDoc) {
      const title = template?.name || template_slug
      htmlContent = `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>${title}</title><style>
body { margin: 0; padding: 24px; font-family: 'Segoe UI', system-ui, sans-serif; font-size: 12px; line-height: 1.6; color: #0f1a14; background: #fff; }
p { margin: 0 0 10px; }
h1 { font-size: 1.8em; font-weight: 800; margin: 14px 0 8px; }
h2 { font-size: 1.45em; font-weight: 800; margin: 12px 0 6px; }
h3 { font-size: 1.2em; font-weight: 700; margin: 10px 0 6px; }
h4 { font-size: 1.05em; font-weight: 700; margin: 8px 0 4px; }
ul, ol { padding-left: 1.4em; margin: 0 0 10px; }
li { margin: 2px 0; }
blockquote { margin: 8px 0; padding: 8px 12px; border-left: 4px solid #74FB71; background: #f1faf7; color: #1a2e22; border-radius: 4px; }
a { color: #1d4ed8; text-decoration: underline; }
img { max-width: 100%; height: auto; }
hr { border: none; border-top: 1px solid #d4e8e0; margin: 12px 0; }
table { border-collapse: collapse; }
table td, table th { border: 1px solid #d4e8e0; padding: 4px 8px; }
</style></head><body>${htmlContent}</body></html>`
    }

    // Store as PDF přes PDFShift; fallback na HTML když API key není / konverze selže.
    const docId = crypto.randomUUID()
    let path: string
    let upErr: any = null
    const pdfBytes = await htmlToPdf(htmlContent)
    if (pdfBytes) {
      path = `generated/${docId}.pdf`
      const pdfBlob = new Blob([pdfBytes], { type: 'application/pdf' })
      const r = await supabase.storage.from('documents').upload(path, pdfBlob, { upsert: true, contentType: 'application/pdf' })
      upErr = r.error
    } else {
      path = `generated/${docId}.html`
      const htmlBlob = new Blob([htmlContent], { type: 'text/html' })
      const r = await supabase.storage.from('documents').upload(path, htmlBlob, { upsert: true, contentType: 'text/html' })
      upErr = r.error
    }
    if (upErr) {
      console.error('Storage upload error:', upErr)
      // Continue — document will still be created in DB with filled_data for client-side rendering
    }

    // Insert generated_documents record
    const { error: gErr } = await supabase.from('generated_documents').insert({
      id: docId,
      template_id: template?.id || null,
      booking_id,
      customer_id: customer.id || booking.user_id,
      filled_data: vars,
      pdf_path: path,
    })
    if (gErr) {
      console.error('Insert error:', gErr)
      return new Response(JSON.stringify({ error: 'Failed to insert generated document: ' + gErr.message }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Audit log
    try {
      await supabase.from('admin_audit_log').insert({
        action: 'document_generated',
        details: { document_id: docId, template_slug, booking_id },
      })
    } catch (e) { /* ignore */ }

    return new Response(JSON.stringify({ success: true, document_id: docId, path }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 })
  }
})

function getFallbackTemplate(slug: string): string | null {
  if (slug === 'rental_contract') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Smlouva o pronájmu</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">SMLOUVA O PRONÁJMU MOTOCYKLU</h1>
  <p style="text-align:center;font-size:13px;color:#1a8a18;font-weight:700;margin:8px 0 4px">Číslo smlouvy / rezervace: {{booking_number}}</p>
  <p style="text-align:center;font-size:11px;color:#666">ze dne {{today}}</p>
  <div style="display:flex;gap:24px;margin:24px 0">
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Pronajímatel</p>
      <p style="margin:0;font-weight:700">{{company_name}}</p>
      <p style="margin:2px 0;font-size:12px">{{company_address}}</p>
      <p style="margin:2px 0;font-size:12px">IČO: {{company_ico}}{{company_dic}}</p>
    </div>
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Nájemce</p>
      <p style="margin:0;font-weight:700">{{customer_name}}</p>
      <p style="margin:2px 0;font-size:12px">{{customer_address}}</p>
      <p style="margin:2px 0;font-size:12px">Tel: {{customer_phone}} | Email: {{customer_email}}</p>
      <p style="margin:2px 0;font-size:12px">Číslo OP/pasu: <strong>{{customer_id_number}}</strong></p>
      <p style="margin:2px 0;font-size:12px">Číslo ŘP: <strong>{{customer_license}}</strong> (platnost do {{customer_license_expiry}})</p>
    </div>
  </div>
  <h3 style="font-size:13px;margin-top:24px">I. Předmět pronájmu</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;margin:8px 0">
    <tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600;width:120px">Model</td><td style="padding:4px 8px">{{moto_model}}</td></tr>
    <tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600">SPZ</td><td style="padding:4px 8px">{{moto_spz}}</td></tr>
    <tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600">VIN</td><td style="padding:4px 8px">{{moto_vin}}</td></tr>
    <tr><td style="padding:4px 8px;background:#f8faf9;font-weight:600">Rok výroby</td><td style="padding:4px 8px">{{moto_year}}</td></tr>
  </table>
  <h3 style="font-size:13px">II. Doba pronájmu</h3>
  <p style="font-size:12px">Od: <strong>{{start_date}}</strong> do: <strong>{{end_date}}</strong> ({{days}} dní)</p>
  <h3 style="font-size:13px">III. Cena</h3>
  <p style="font-size:12px">Denní sazba: <strong>{{daily_rate}} Kč</strong> | Celkem: <strong>{{total_price}} Kč</strong> vč. DPH</p>
  <div style="margin-top:40px;padding:18px;background:#ecfdf5;border:1px solid #16a34a;border-radius:8px;text-align:center;font-size:12px;color:#065f46">
    <p style="margin:0;font-weight:700;font-size:13px">Podepsáno elektronicky</p>
    <p style="margin:6px 0 0">Smlouva byla uzavřena prostřednictvím elektronických komunikací na dálku. Odesláním rezervačního formuláře a úhradou nájemného nájemce vyjádřil souhlas se zněním této smlouvy. Elektronický souhlas má stejnou právní váhu jako fyzický podpis nájemce.</p>
    <p style="margin:8px 0 0;font-size:11px;color:#166534">Pronajímatel: {{company_name}} &nbsp;·&nbsp; Nájemce: {{customer_name}}</p>
    <p style="margin:4px 0 0;font-size:11px;color:#166534">Datum: {{today}} &nbsp;·&nbsp; Smlouva č. {{booking_number}}</p>
  </div>
</div></body></html>`
  }

  if (slug === 'handover_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Předávací protokol</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px">PŘEDÁVACÍ PROTOKOL</h1>
  <p style="text-align:center;font-size:12px;color:#666">k rezervaci č. {{booking_number}} ze dne {{today}}</p>
  <table style="width:100%;border-collapse:collapse;font-size:12px;margin:20px 0">
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600;width:160px">Zákazník</td><td style="padding:6px 10px">{{customer_name}}</td></tr>
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">Motocykl</td><td style="padding:6px 10px">{{moto_model}} ({{moto_spz}})</td></tr>
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">VIN</td><td style="padding:6px 10px">{{moto_vin}}</td></tr>
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">Období</td><td style="padding:6px 10px">{{start_date}} — {{end_date}}</td></tr>
  </table>
  <h3 style="font-size:13px">Stav při předání</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;margin:8px 0;border:1px solid #ddd">
    <tr><td style="padding:8px;border:1px solid #ddd;width:50%">Stav km:</td><td style="padding:8px;border:1px solid #ddd">{{mileage}}</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Viditelné poškození:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Poznámky:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
  </table>
  <h3 style="font-size:13px">Příslušenství a výbava</h3>
  {{accessories_block}}
  <div style="margin-top:48px;display:flex;justify-content:space-between">
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Předávající</div></div>
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Přebírající — {{customer_name}}</div></div>
  </div>
</div></body></html>`
  }

  if (slug === 'vop') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Všeobecné obchodní podmínky</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px">VŠEOBECNÉ OBCHODNÍ PODMÍNKY</h1>
  <p style="text-align:center;font-size:12px;color:#666">{{company_name}} | IČO: {{company_ico}} | {{company_address}}</p>
  <p style="text-align:center;font-size:12px;color:#666">Platné od {{today}} k rezervaci č. {{booking_number}}</p>
  <h3 style="font-size:13px;margin-top:24px">1. Úvodní ustanovení</h3>
  <p style="font-size:12px">Tyto všeobecné obchodní podmínky (dále jen „VOP") upravují práva a povinnosti smluvních stran při pronájmu motocyklu provozovaném společností {{company_name}}, IČO: {{company_ico}}, se sídlem {{company_address}} (dále jen „Pronajímatel").</p>
  <h3 style="font-size:13px">2. Předmět pronájmu</h3>
  <p style="font-size:12px">Předmětem pronájmu je motocykl specifikovaný v nájemní smlouvě. Nájemce je povinen užívat motocykl výhradně k účelům stanoveným smlouvou a v souladu s platnými právními předpisy.</p>
  <h3 style="font-size:13px">3. Podmínky pronájmu</h3>
  <p style="font-size:12px">Nájemce musí být držitelem platného řidičského průkazu příslušné skupiny. Minimální věk nájemce je 21 let. Nájemce je povinen předložit platný doklad totožnosti a řidičský průkaz při převzetí motocyklu.</p>
  <h3 style="font-size:13px">4. Cena a platební podmínky</h3>
  <p style="font-size:12px">Cena pronájmu se řídí aktuálním ceníkem. Platba je splatná před převzetím motocyklu. Kauce je vratná po vrácení motocyklu v bezvadném stavu.</p>
  <h3 style="font-size:13px">5. Odpovědnost za škody</h3>
  <p style="font-size:12px">Nájemce odpovídá za veškeré škody vzniklé na motocyklu po dobu pronájmu. V případě nehody je nájemce povinen neprodleně informovat Pronajímatele a příslušné orgány.</p>
  <h3 style="font-size:13px">6. Storno podmínky</h3>
  <p style="font-size:12px">Bezplatné storno je možné do 48 hodin před začátkem pronájmu. Pozdější storno podléhá storno poplatku dle aktuálních podmínek.</p>
  <h3 style="font-size:13px">7. Závěrečná ustanovení</h3>
  <p style="font-size:12px">Tyto VOP jsou nedílnou součástí nájemní smlouvy. Pronajímatel si vyhrazuje právo na změnu VOP. Právní vztahy neupravené těmito VOP se řídí občanským zákoníkem.</p>
  <div style="margin-top:32px;padding:16px;background:#f8faf9;border-radius:8px;font-size:11px;color:#666">
    <p style="margin:0">{{company_name}} | {{company_address}} | IČO: {{company_ico}}</p>
    <p style="margin:4px 0 0">Kontakt: info@motogo24.cz | +420 774 256 271 | motogo24.cz</p>
  </div>
</div></body></html>`
  }

  if (slug === 'damage_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Protokol o zjištěném poškození</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a;font-size:12px">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:18px;border-bottom:2px solid #dc2626;padding-bottom:12px">PROTOKOL O ZJIŠTĚNÉM POŠKOZENÍ PŘI VRÁCENÍ</h1>
  <p style="text-align:center;font-size:12px;color:#666">k rezervaci č. {{booking_number}} ze dne {{today}}</p>
  <h3 style="font-size:13px;margin-top:16px">1. Identifikace smlouvy a stran</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Číslo smlouvy</td><td style="padding:6px 8px;border:1px solid #ddd">{{booking_number}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Pronajímatel</td><td style="padding:6px 8px;border:1px solid #ddd">{{company_name}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Nájemce</td><td style="padding:6px 8px;border:1px solid #ddd">{{customer_name}}</td></tr>
  </table>
  <h3 style="font-size:13px;margin-top:14px">2. Identifikace vozidla</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Značka a model</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_model}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">VIN</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_vin}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">SPZ</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_spz}}</td></tr>
  </table>
  <h3 style="font-size:13px;margin-top:14px">3. Stav motocyklu při vrácení</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Stav tachometru</td><td style="padding:6px 8px;border:1px solid #ddd">&nbsp; km</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;vertical-align:top">Celkový vizuální stav</td><td style="padding:18px 8px;border:1px solid #ddd"></td></tr>
  </table>
  <h3 style="font-size:13px;margin-top:14px">4. Zjištěná poškození / chybějící příslušenství</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px;vertical-align:top">Popis poškození motocyklu</td><td style="padding:28px 8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;vertical-align:top">Chybějící / poškozené vybavení</td><td style="padding:20px 8px;border:1px solid #ddd"></td></tr>
  </table>
  <p style="font-size:11px;color:#666;margin-top:6px">Zapůjčené příslušenství dle rezervace: {{accessories}}</p>
  <p style="font-size:12px;margin-top:12px">Příslušná fotodokumentace je přiložena k protokolu a je jeho nedílnou součástí.</p>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd;margin-top:8px">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Datum a čas vrácení</td><td style="padding:6px 8px;border:1px solid #ddd">{{today}} {{today_time}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Vystavil/a</td><td style="padding:6px 8px;border:1px solid #ddd">{{company_name}}</td></tr>
  </table>
  <div style="margin-top:48px;display:flex;justify-content:space-between">
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Podpis pronajímatele<br>{{company_name}}</div></div>
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Podpis nájemce<br>{{customer_name}}</div></div>
  </div>
  <div style="margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px">{{company_name}} · IČO: {{company_ico}} · {{company_address}} · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>`
  }

  if (slug === 'gdpr') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Souhlas se zpracováním osobních údajů</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a;font-size:12px">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:18px;border-bottom:2px solid #1a8a18;padding-bottom:12px">INFORMACE A SOUHLAS SE ZPRACOVÁNÍM OSOBNÍCH ÚDAJŮ (GDPR)</h1>
  <p style="text-align:center;font-size:12px;color:#666">{{company_name}} | IČO: {{company_ico}} | {{company_address}} | ze dne {{today}}</p>
  <h3 style="font-size:13px;margin-top:16px">1. Správce osobních údajů</h3>
  <p>Správcem osobních údajů je {{company_name}}, IČO: {{company_ico}}, se sídlem {{company_address}}, kontakt: info@motogo24.cz, +420 774 256 271.</p>
  <h3 style="font-size:13px">2. Subjekt údajů</h3>
  <p>Jméno a příjmení: <strong>{{customer_name}}</strong><br>Adresa: {{customer_address}}<br>E-mail: {{customer_email}}</p>
  <h3 style="font-size:13px">3. Rozsah a účel zpracování</h3>
  <p>Správce zpracovává identifikační a kontaktní údaje, údaje z dokladu totožnosti a řidičského průkazu a údaje o rezervaci za účelem uzavření a plnění nájemní smlouvy, vedení evidence, fakturace a plnění právních povinností.</p>
  <h3 style="font-size:13px">4. Právní základ a doba uchování</h3>
  <p>Zpracování je nezbytné pro plnění smlouvy a plnění právních povinností správce (zejm. účetní a daňové předpisy). Údaje jsou uchovávány po dobu trvání smluvního vztahu a následně po dobu stanovenou právními předpisy.</p>
  <h3 style="font-size:13px">5. Práva subjektu údajů</h3>
  <p>Subjekt údajů má právo na přístup k údajům, jejich opravu, výmaz, omezení zpracování, přenositelnost, vznesení námitky a právo podat stížnost u Úřadu pro ochranu osobních údajů.</p>
  <h3 style="font-size:13px">6. Souhlas</h3>
  <p>Svým podpisem potvrzuji, že jsem byl/a informován/a o zpracování osobních údajů v rozsahu uvedeném výše.</p>
  <div style="margin-top:48px;display:flex;justify-content:space-between">
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Za správce — {{company_name}}</div></div>
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">{{customer_name}}</div></div>
  </div>
  <div style="margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px">{{company_name}} · IČO: {{company_ico}} · {{company_address}} · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>`
  }

  return null
}
