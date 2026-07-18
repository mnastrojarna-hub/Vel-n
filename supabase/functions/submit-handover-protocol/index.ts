// submit-handover-protocol — uloží předávací protokol pro samoobslužnou pobočku.
//
// mode='customer' : zákazník (appka, tablet v pobočce) vyplnil a podepsal protokol.
// mode='auto'     : cron (service_role) — zákazník nestihl do 1 h, vyplní se „vše OK".
//
// Sestaví HTML (jen podpis nájemce — MotoGo automaticky souhlasí), vyrenderuje PDF
// přes render-pdf, uloží do bucketu `documents`, vloží `generated_documents`
// (sync trigger → `documents`, zobrazí se v appce), zamkne protokol
// (`bookings.handover_protocol_filled_at`) a odešle protokol zákazníkovi e-mailem
// (send-email, šablona handover_protocol_sent, PDF v příloze — best-effort).
// Idempotentní (druhé volání vrátí existující).

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { authClassify } from '../_shared/auth.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function esc(s: unknown): string {
  return String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))
}
function escMulti(s: unknown): string { return esc(s).replace(/\n/g, '<br>') }

const HANDOVER_CHECKS = [
  { key: 'clean', label: 'Motocykl předán čistý a v provozuschopném stavu' },
  { key: 'docs', label: 'Doklady k vozidlu (OTP, zelená karta) předány' },
  { key: 'keys', label: 'Klíče a zabezpečení předány' },
  { key: 'instructed', label: 'Nájemce poučen o obsluze a provozu' },
  { key: 'gear', label: 'Ochranná výbava předána a vyzkoušena' },
]
const EXTRA_GEAR_CHECKS = [
  { key: 'phone_holder', label: 'Držák na telefon' },
  { key: 'disc_lock', label: 'Kotoučový zámek' },
  { key: 'rain_suit', label: 'Set nepromokavé bundy a kalhot' },
  { key: 'rain_boots', label: 'Nepromoky na nohy' },
  { key: 'rain_gloves', label: 'Nepromoky na ruce' },
  { key: 'tie_net', label: 'Upínací síťka' },
  { key: 'tankbag_small', label: 'Tankvak malý' },
  { key: 'tankbag_large', label: 'Tankvak velký' },
  { key: 'reflective', label: 'Reflexní prvky' },
  { key: 'back_protector', label: 'Páteřák' },
  { key: 'chain_spray', label: 'Sprej na řetěz' },
]

interface Vars {
  booking_number: string; today: string; company_name: string; customer_name: string
  moto_model: string; moto_spz: string; moto_vin: string; rental_period: string
}

function buildHtml(v: Vars, form: Record<string, unknown>, signature: string | null, autofilled: boolean): string {
  const checks = (form.checks || {}) as Record<string, boolean>
  const damage = (form.damage || {}) as { checked?: boolean; desc?: string }
  const accessories = (form.accessories || []) as Array<{ label?: string; size?: string; checked?: boolean }>
  const mileage = form.mileage as string | undefined
  const notes = form.notes as string | undefined

  const checkList = HANDOVER_CHECKS.map((c) => `<div style="font-size:12px;margin:5px 0">${checks[c.key] ? '☑' : '☐'} ${esc(c.label)}</div>`).join('')
  const extraList = EXTRA_GEAR_CHECKS.map((c) => `<div style="font-size:12px;margin:5px 0">${checks[c.key] ? '☑' : '☐'} ${esc(c.label)}</div>`).join('')
  const accRows = accessories.map((a) => `<tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">${esc(a.label)}</td><td style="padding:6px 8px;border:1px solid #ddd">${esc(a.size || '')}</td><td style="padding:6px 8px;border:1px solid #ddd;text-align:center;width:80px;font-size:14px">${a.checked ? '☑' : '☐'}</td></tr>`).join('')
  const accTable = accRows
    ? `<table style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd"><tr><th style="padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">Položka</th><th style="padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:left;font-size:10px;text-transform:uppercase">Velikost</th><th style="padding:6px 8px;border:1px solid #ddd;background:#f0f7ff;text-align:center;font-size:10px;text-transform:uppercase">Předáno</th></tr>${accRows}</table>`
    : '<p style="font-size:12px">Žádné zapůjčené příslušenství.</p>'
  const damageBlock = `<div style="font-size:12px;margin:5px 0">${damage.checked ? '☑' : '☐'} Poškození při předání</div>` +
    (damage.checked && damage.desc ? `<p style="font-size:12px;margin:4px 0 0;padding:8px 10px;background:#fef2f2;border:1px solid #fca5a5;border-radius:6px">${escMulti(damage.desc)}</p>` : '')

  const TD = 'padding:6px 8px;border:1px solid #ddd'
  const TDL = `${TD};background:#f8faf9;font-weight:600;width:220px`
  const row = (l: string, val: string) => `<tr><td style="${TDL}">${esc(l)}</td><td style="${TD}">${val ? escMulti(val) : '&nbsp;'}</td></tr>`
  const parties = `<h3 style="font-size:13px;margin-top:16px">Smluvní strany a vozidlo</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${row('Pronajímatel', v.company_name)}${row('Nájemce', v.customer_name)}${row('Motocykl', `${v.moto_model} (${v.moto_spz || ''})`)}${row('VIN', v.moto_vin)}${row('Období pronájmu', v.rental_period)}</table>`

  const sigCaption = autofilled
    ? 'Protokol vyplněn automaticky systémem — zákazník motocykl převzal dle rezervace a do 60 minut od zpřístupnění nenahlásil žádné závady. MotoGo24 automaticky souhlasí.'
    : ''
  const sigBlock = autofilled
    ? `<div style="margin-top:32px;padding:12px;border:1px dashed #999;border-radius:8px;font-size:11px;color:#444">${esc(sigCaption)}</div>`
    : `<div style="margin-top:40px;display:flex;justify-content:center"><div style="text-align:center;width:60%"><div style="height:96px;border:1px solid #ccc;border-radius:8px;display:flex;align-items:center;justify-content:center;background:#fff;overflow:hidden">${signature ? `<img src="${signature}" alt="podpis" style="max-width:100%;max-height:92px"/>` : ''}</div><div style="border-top:1px solid #999;margin-top:6px;padding-top:6px;font-size:11px">Podpis nájemce — ${esc(v.customer_name)}</div></div></div>`

  const signedAt = new Date().toLocaleString('cs-CZ')
  const foot = `<p style="font-size:11px;color:#666;margin-top:18px">Tento protokol byl ${autofilled ? 'vyplněn automaticky' : 'vyplněn a elektronicky podepsán nájemcem'} na samoobslužné pobočce dne ${esc(signedAt)}. Případné nesrovnalosti nahlaste neprodleně přes aplikaci nebo e-mailem na info@motogo24.cz.</p></div></body></html>`

  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Předávací protokol</title></head><body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a"><div style="max-width:780px;margin:0 auto;padding:32px"><h1 style="text-align:center;font-size:19px;border-bottom:2px solid #2563eb;padding-bottom:12px">PŘEDÁVACÍ PROTOKOL</h1><p style="text-align:center;font-size:12px;color:#666">k rezervaci č. ${esc(v.booking_number)} ze dne ${esc(v.today)}</p>` +
    parties +
    `<h3 style="font-size:13px;margin-top:14px">Stav při předání</h3><table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">${row('Stav km při předání', mileage ? `${mileage} km` : '')}</table>` +
    `<h3 style="font-size:13px;margin-top:14px">Kontrola předání</h3>${checkList}` +
    `<h3 style="font-size:13px;margin-top:14px">Příslušenství a výbava</h3>${accTable}` +
    `<h3 style="font-size:13px;margin-top:14px">Doplňkové vybavení</h3>${extraList}` +
    `<h3 style="font-size:13px;margin-top:14px">Poškození</h3>${damageBlock}` +
    (notes ? `<h3 style="font-size:13px;margin-top:14px">Poznámky</h3><p style="font-size:12px">${escMulti(notes)}</p>` : '') +
    sigBlock + foot
}

function fmtDate(d: string | null): string {
  if (!d) return ''
  try { return new Date(d).toLocaleDateString('cs-CZ') } catch { return d }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  const admin = createClient(SUPABASE_URL, SERVICE_KEY)
  try {
    const body = await req.json()
    const bookingId = body.booking_id as string
    const mode = (body.mode as string) === 'auto' ? 'auto' : 'customer'
    if (!bookingId) return json({ success: false, error: 'missing_booking_id' }, 400)

    // Auth: auto = jen service_role; customer = přihlášený majitel rezervace.
    const who = await authClassify(req)
    if (mode === 'auto' && who.kind !== 'service') return json({ success: false, error: 'forbidden' }, 403)
    if (mode === 'customer' && who.kind === 'none') return json({ success: false, error: 'unauthenticated' }, 401)

    // Načtení rezervace + vozidlo + pobočka (service role, obejde RLS).
    const { data: booking, error: bErr } = await admin
      .from('bookings')
      .select('*, motorcycles!moto_id(model, spz, vin, branch_id, branches(type))')
      .eq('id', bookingId)
      .maybeSingle()
    if (bErr || !booking) return json({ success: false, error: 'not_found' }, 404)

    if (mode === 'customer' && who.kind === 'user' && booking.user_id !== who.userId) {
      return json({ success: false, error: 'forbidden' }, 403)
    }

    // Idempotence — protokol už existuje.
    if (booking.handover_protocol_filled_at) {
      return json({ success: true, already_filled: true, autofilled: booking.handover_protocol_autofilled })
    }

    const moto = (booking.motorcycles || {}) as Record<string, unknown>
    const branchType = ((moto.branches || {}) as Record<string, unknown>).type
    if (branchType !== 'samoobslužná') return json({ success: false, error: 'not_self_service' }, 400)

    // Zákazník
    let customer: Record<string, unknown> = {}
    if (booking.user_id) {
      const { data: prof } = await admin.from('profiles').select('id, full_name, email').eq('id', booking.user_id).maybeSingle()
      if (prof) customer = prof
    }

    const bn = String(bookingId).slice(-8).toUpperCase()
    const vars: Vars = {
      booking_number: bn,
      today: new Date().toLocaleDateString('cs-CZ'),
      company_name: 'Bc. Petra Semorádová, MotoGo24',
      customer_name: (customer.full_name as string) || '—',
      moto_model: (moto.model as string) || '—',
      moto_spz: (moto.spz as string) || '',
      moto_vin: (moto.vin as string) || '',
      rental_period: `${fmtDate(booking.start_date)} — ${fmtDate(booking.end_date)}`,
    }

    let form: Record<string, unknown>
    let signature: string | null = null
    const autofilled = mode === 'auto'
    if (autofilled) {
      const checks: Record<string, boolean> = {}
      HANDOVER_CHECKS.forEach((c) => { checks[c.key] = true })
      form = {
        checks,
        damage: { checked: false, desc: '' },
        notes: 'Protokol vyplněn automaticky — zákazník převzal motocykl dle rezervace a do 60 minut nenahlásil žádné závady. Vše v pořádku.',
        accessories: [],
        mileage: '',
      }
    } else {
      form = (body.form || {}) as Record<string, unknown>
      signature = (body.signature as string) || null
      if (!signature) return json({ success: false, error: 'missing_signature' }, 400)
    }

    const html = buildHtml(vars, form, signature, autofilled)
    const docId = crypto.randomUUID()

    // Render PDF přes render-pdf (fallback: ulož HTML).
    let pdfPath = `generated/${bookingId}/handover-${docId}.pdf`
    let stored = false
    try {
      const rp = await fetch(`${SUPABASE_URL}/functions/v1/render-pdf`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}` },
        body: JSON.stringify({ html }),
      })
      if (rp.ok && rp.headers.get('content-type')?.includes('application/pdf')) {
        const bytes = new Uint8Array(await rp.arrayBuffer())
        const up = await admin.storage.from('documents').upload(pdfPath, bytes, { upsert: true, contentType: 'application/pdf' })
        if (!up.error) stored = true
      }
    } catch (_) { /* fallback níže */ }
    if (!stored) {
      pdfPath = `generated/${bookingId}/handover-${docId}.html`
      const up = await admin.storage.from('documents').upload(pdfPath, new Blob([html], { type: 'text/html' }), { upsert: true, contentType: 'text/html' })
      if (up.error) pdfPath = `generated/${docId}.html` // poslední fallback (cesta v generated_documents)
    }

    const filled = {
      ...vars,
      _signed_html: html,
      _doc_name: 'Předávací protokol (elektronický)',
      _doc_type: 'handover_protocol',
      _electronic: true,
      _autofilled: autofilled,
      _self_service: true,
      _signed_at: new Date().toISOString(),
    }
    const { error: gErr } = await admin.from('generated_documents').insert({
      id: docId, template_id: null, booking_id: bookingId, customer_id: booking.user_id, filled_data: filled, pdf_path: pdfPath,
    })
    if (gErr) return json({ success: false, error: 'insert_failed', detail: gErr.message }, 500)

    // Zamknout protokol.
    await admin.from('bookings').update({
      handover_protocol_filled_at: new Date().toISOString(),
      handover_protocol_autofilled: autofilled,
    }).eq('id', bookingId)

    // Propsat stav km z protokolu do dat (jen reálné odečty, ne auto-fill).
    // Samostatný UPDATE jen sloupce mileage_start → spustí trigger
    // trg_booking_mileage_to_moto, který bumpne motorcycles.mileage = GREATEST(...).
    // Idempotentní (zapíše jen když roste), EXCEPTION-safe (neshodí protokol).
    try {
      const rawMileage = (form.mileage as string | undefined) ?? ''
      const km = parseInt(String(rawMileage).replace(/[^\d]/g, ''), 10)
      if (!autofilled && Number.isFinite(km) && km > 0 &&
          (!booking.mileage_start || km > Number(booking.mileage_start))) {
        await admin.from('bookings').update({ mileage_start: km }).eq('id', bookingId)
      }
    } catch (_) { /* propsání km je best-effort, nikdy neshodí protokol */ }

    // Protokol zákazníkovi e-mailem (best-effort — v appce ho už má přes sync
    // do `documents`, mailem chodí navíc s PDF přílohou; selhání protokol neshodí).
    let emailSent = false
    const custEmail = (customer.email as string) || ''
    if (custEmail) {
      try {
        const filename = `Predavaci_protokol_${bn}.${pdfPath.endsWith('.html') ? 'html' : 'pdf'}`
        const er = await fetch(`${SUPABASE_URL}/functions/v1/send-email`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE_KEY}` },
          body: JSON.stringify({
            to: custEmail,
            template_slug: 'handover_protocol_sent',
            template_vars: {
              customer_name: vars.customer_name,
              moto: `${vars.moto_model}${vars.moto_spz ? ` (${vars.moto_spz})` : ''}`,
              moto_model: vars.moto_model,
              rental_period: vars.rental_period,
              booking_number: bn,
              doc_name: 'Předávací protokol',
            },
            customer_id: booking.user_id || null,
            booking_id: bookingId,
            attachment_paths: [{ filename, path: pdfPath }],
          }),
        })
        const ej = await er.json().catch(() => null)
        emailSent = !!(er.ok && ej && ej.success !== false)
      } catch (_) { /* mail je best-effort */ }
    }

    return json({ success: true, doc_id: docId, autofilled, email_sent: emailSent })
  } catch (e) {
    return json({ success: false, error: (e as Error).message }, 500)
  }
})
