import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const fmtDate = (d: string) => d ? new Date(d).toLocaleDateString('cs-CZ') : '—'
const fmtPrice = (n: number) => (n || 0).toLocaleString('cs-CZ', { minimumFractionDigits: 2 })

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
      .select('*, motorcycles(model, spz, vin, year, brand, category, engine_cc, power_kw, color, deposit_amount, insurance_price, image_url)')
      .eq('id', booking_id).single()
    if (bErr || !booking) {
      console.error('Booking query error:', bErr?.message, 'booking_id:', booking_id)
      return new Response(JSON.stringify({ error: 'Booking not found: ' + (bErr?.message || 'no data') }), { status: 404 })
    }
    // Fetch profile separately to avoid PostgREST FK ambiguity
    let customer: Record<string, unknown> = {}
    if (booking.user_id) {
      const { data: prof } = await supabase.from('profiles')
        .select('id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry, license_group, date_of_birth, id_number')
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
    }

    // Substitute variables in template HTML
    let htmlContent = template?.content_html || template?.html_content || getFallbackTemplate(template_slug) || ''
    for (const [key, val] of Object.entries(vars)) {
      htmlContent = htmlContent.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
    }

    // Store HTML as file
    const docId = crypto.randomUUID()
    const blob = new Blob([htmlContent], { type: 'text/html' })
    const path = `generated/${docId}.html`
    const { error: upErr } = await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'text/html' })
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
    <tr><td style="padding:8px;border:1px solid #ddd;width:50%">Stav km:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Stav paliva:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Viditelné poškození:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Příslušenství:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Poznámky:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
  </table>
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

  return null
}
