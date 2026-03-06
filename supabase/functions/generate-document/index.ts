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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { template_slug, booking_id } = await req.json()
    if (!template_slug || !booking_id) {
      return new Response(JSON.stringify({ error: 'Missing template_slug or booking_id' }), { status: 400 })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Load template
    const { data: template, error: tErr } = await supabase
      .from('document_templates')
      .select('*')
      .eq('type', template_slug)
      .eq('status', 'active')
      .order('version', { ascending: false })
      .limit(1).single()

    if (tErr || !template) {
      // If no template in DB, use built-in fallback
      const fallbackHtml = getFallbackTemplate(template_slug)
      if (!fallbackHtml) {
        return new Response(JSON.stringify({ error: `Template '${template_slug}' not found` }), { status: 404 })
      }
      // Continue with fallback
    }

    // Load booking with relations
    const { data: booking, error: bErr } = await supabase
      .from('bookings')
      .select('*, motorcycles(model, spz, vin, year), profiles(id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry)')
      .eq('id', booking_id).single()
    if (bErr || !booking) return new Response(JSON.stringify({ error: 'Booking not found' }), { status: 404 })

    const customer = booking.profiles || {}
    const moto = booking.motorcycles || {}
    const days = Math.max(1, Math.ceil((new Date(booking.end_date).getTime() - new Date(booking.start_date).getTime()) / 86400000))

    // Variable substitution map
    const vars: Record<string, string> = {
      customer_name: customer.full_name || '—',
      customer_email: customer.email || '',
      customer_phone: customer.phone || '',
      customer_address: [customer.street, customer.city, customer.zip, customer.country].filter(Boolean).join(', ') || '',
      customer_ico: customer.ico || '',
      customer_dic: customer.dic || '',
      customer_license: customer.license_number || '',
      customer_license_expiry: fmtDate(customer.license_expiry),
      moto_model: moto.model || '—',
      moto_spz: moto.spz || '',
      moto_vin: moto.vin || '',
      moto_year: String(moto.year || ''),
      start_date: fmtDate(booking.start_date),
      end_date: fmtDate(booking.end_date),
      days: String(days),
      total_price: fmtPrice(booking.total_price || 0),
      daily_rate: fmtPrice(Math.round((booking.total_price || 0) / days)),
      booking_id: booking_id.slice(0, 8),
      booking_number: booking_id.slice(0, 8).toUpperCase(),
      today: fmtDate(new Date().toISOString()),
      company_name: 'MotoGo24 s.r.o.',
      company_address: 'Mezná 9, 393 01 Pelhřimov',
      company_ico: '12345678',
      company_dic: 'CZ12345678',
    }

    // Substitute variables in template HTML
    let htmlContent = template?.html_content || getFallbackTemplate(template_slug) || ''
    for (const [key, val] of Object.entries(vars)) {
      htmlContent = htmlContent.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
    }

    // Store HTML as file
    const docId = crypto.randomUUID()
    const blob = new Blob([htmlContent], { type: 'text/html' })
    const path = `generated/${docId}.html`
    const { error: upErr } = await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'text/html' })
    if (upErr) console.error('Storage upload error:', upErr)

    // Insert generated_documents record
    const { error: gErr } = await supabase.from('generated_documents').insert({
      id: docId,
      template_id: template?.id || null,
      booking_id,
      customer_id: customer.id || booking.user_id,
      filled_data: vars,
      pdf_path: path,
    })
    if (gErr) console.error('Insert error:', gErr)

    // Audit log
    await supabase.from('admin_audit_log').insert({
      action: 'document_generated',
      details: { document_id: docId, template_slug, booking_id },
    })

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
  <p style="text-align:center;font-size:12px;color:#666">č. {{booking_number}} ze dne {{today}}</p>
  <div style="display:flex;gap:24px;margin:24px 0">
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Pronajímatel</p>
      <p style="margin:0;font-weight:700">{{company_name}}</p>
      <p style="margin:2px 0;font-size:12px">{{company_address}}</p>
      <p style="margin:2px 0;font-size:12px">IČO: {{company_ico}} | DIČ: {{company_dic}}</p>
    </div>
    <div style="flex:1;padding:14px;background:#f8faf9;border-radius:8px">
      <p style="margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888">Nájemce</p>
      <p style="margin:0;font-weight:700">{{customer_name}}</p>
      <p style="margin:2px 0;font-size:12px">{{customer_address}}</p>
      <p style="margin:2px 0;font-size:12px">Tel: {{customer_phone}} | Email: {{customer_email}}</p>
      <p style="margin:2px 0;font-size:12px">ŘP: {{customer_license}} (platnost do {{customer_license_expiry}})</p>
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
  <div style="margin-top:48px;display:flex;justify-content:space-between">
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Pronajímatel</div></div>
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Nájemce — {{customer_name}}</div></div>
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

  return null
}
