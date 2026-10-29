// generate-document — dokument k rezervaci ze šablony document_templates (rental_contract, vop,
// handover_protocol, damage_protocol, gdpr) → PDF (PDFShift, fallback HTML) → bucket `documents`
// → generated_documents (+ přemazání starších verzí téhož typu).
//
// Audit 2026-10-10:
//  - EDGE-DOC-18: volat smí jen service_role, účet Velína, nebo vlastník rezervace (jen v jazyce
//    rezervace) — dřív stačil anon klíč + UUID rezervace;
//  - EDGE-DOC-05: bez `language` se jazyk určí na serveru (detect_customer_language), dřív 'cs' →
//    Velín přepisoval cizojazyčnou smlouvu/VOP zákazníka českou; explicitní 'cs' = česká kopie;
//  - EDGE-DOC-01/02/08: překlad jen ČERSTVÝ (translation.ts); jinak závazný český text + upozornění
//    a překlad se vyžádá na pozadí — žádný synchronní strojový překlad;
//  - EDGE-DOC-09: hodnoty {{proměnných}} v jazyce textu dokumentu (labels.ts, vars.ts);
//  - EDGE-DOC-15: VOP / smlouva / GDPR bez DB šablony → 503 + debug_log (žádné vymyšlené podmínky).

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { authClassify } from '../_shared/auth.ts'
import { parseDocLang } from '../_shared/doc-i18n.ts'
import { getFallbackTemplate } from './fallback.ts'
import { htmlToPdf, wrapDocument } from './render.ts'
import { applyNotice, enqueueRetranslation, type Mode, pickContent, setHtmlLang } from './translation.ts'
import { buildVars } from './vars.ts'
import { buildGearVars, GEAR_CONTRACT_SLUG, isGearDoc, loadGearPriceRows, resolveDocSlug } from './gear-vars.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ALL_ADMIN_ROLES = ['superadmin', 'manager', 'operator', 'viewer', 'admin']
// Právní dokumenty: bez platné DB šablony se NEgenerují (EDGE-DOC-15).
const LEGAL_SLUGS = new Set(['vop', 'rental_contract', 'gdpr', GEAR_CONTRACT_SLUG])

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

// Doména zákazníka: cs → motogo24.cz, ostatní jazyky → motogo24.com (jako process-payment).
const DOMAIN_INTL = 'https://motogo24.com'
const webLabelForLang = (lang: string) => lang === 'cs' ? 'motogo24.cz' : 'motogo24.com'
/** URL `http(s)://(www.)motogo24.cz…` → zákazníkova doména (jen non-cs; e-mail info@motogo24.cz se nemění). */
function localizeDocLinks(html: string, lang: string): string {
  if (lang === 'cs' || !html) return html
  return html.replace(/https?:\/\/(?:www\.)?motogo24\.cz/gi, DOMAIN_INTL)
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { template_slug: reqSlug, booking_id, language } = await req.json()
    if (!reqSlug || !booking_id) return json({ error: 'Missing template_slug or booking_id' }, 400)

    const who = await authClassify(req, { adminRoles: ALL_ADMIN_ROLES })
    if (who.kind === 'none') return json({ error: 'unauthorized' }, 401)

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    // Výpůjčka JEN výbavy (2026-10-23): smlouva = gear_rental_contract, nikdy motorková (gear-vars.ts).
    const template_slug: string = await resolveDocSlug(supabase, String(reqSlug), booking_id)
    const logDebug = async (action: string, status: string, data: Record<string, unknown>, err?: string) => {
      try {
        await supabase.from('debug_log').insert({ source: 'generate-document', action, component: 'edge-function', status, request_data: data, error_message: err || null })
      } catch { /* jen log */ }
    }

    // Firemní údaje z app_settings
    let companyInfo = { name: 'Bc. Petra Semorádová', address: 'Mezná 9, 393 01 Pelhřimov', ico: '21874263', dic: '' }
    try {
      const { data: settings } = await supabase.from('app_settings').select('value').eq('key', 'company_info').limit(1)
      const info = settings?.[0]?.value
      if (info && info.name) companyInfo = { name: info.name, address: info.address || companyInfo.address, ico: info.ico || companyInfo.ico, dic: info.dic || '' }
    } catch (e) { console.warn('Failed to load company_info:', e) }

    // Šablona z DB (bez .single() — chyba při 0 / 2+ řádcích); select('*') nese i translation_src, pokud existuje.
    const { data: templates, error: tErr } = await supabase.from('document_templates').select('*')
      .eq('type', template_slug).eq('active', true).order('version', { ascending: false }).limit(1)
    const template = templates?.[0] || null
    if (tErr) console.error('Template query error:', tErr.message, 'slug:', template_slug)
    const hasDbContent = !!(template && String(template.content_html || template.html_content || '').trim())
    if (!hasDbContent && !getFallbackTemplate(template_slug)) {
      const legal = LEGAL_SLUGS.has(template_slug)
      await logDebug('doc_template_missing', 'error', { template_slug, booking_id, template_id: template?.id || null }, tErr?.message)
      return json({ error: legal ? `Template '${template_slug}' unavailable` : `Template '${template_slug}' not found` }, legal ? 503 : 404)
    }

    // Rezervace + motorka (profil zvlášť — FK nejednoznačnost PostgREST)
    const { data: booking, error: bErr } = await supabase.from('bookings')
      .select('*, motorcycles!moto_id(model, spz, vin, year, brand, category, engine_cc, power_kw, color, deposit_amount, insurance_price, image_url, license_required)')
      .eq('id', booking_id).single()
    if (bErr || !booking) {
      console.error('Booking query error:', bErr?.message, 'booking_id:', booking_id)
      return json({ error: 'Booking not found: ' + (bErr?.message || 'no data') }, 404)
    }
    if (who.kind === 'user' && booking.user_id !== who.userId) return json({ error: 'forbidden' }, 403)

    // Jazyk: explicitní (service / Velín) > jazyk zákazníka z DB > cs. Zákazník jen ve svém jazyce.
    const explicit = who.kind === 'user' ? null : parseDocLang(language)
    let lang = explicit || 'cs'
    if (!explicit) {
      try {
        const { data: dl } = await supabase.rpc('detect_customer_language', { p_user_id: booking.user_id || null, p_booking_id: booking_id, p_order_id: null })
        lang = parseDocLang(dl) || 'cs'
      } catch { /* cs */ }
    }

    let customer: Record<string, unknown> = {}
    if (booking.user_id) {
      const { data: prof } = await supabase.from('profiles')
        .select('id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry, license_group, date_of_birth, id_number, id_verified_until, license_verified_until, passport_verified_until')
        .eq('id', booking.user_id).single()
      if (prof) customer = prof
    }

    let extras: Array<{ name: string; quantity: number; unit_price: number }> = []
    try {
      const { data } = await supabase.from('booking_extras').select('name, quantity, unit_price').eq('booking_id', booking_id)
      if (Array.isArray(data)) extras = data
    } catch { /* ignore */ }

    // Pobočka REZERVACE (bookings.branch_id, jinak pobočka motorky); samoobsluha řídí časy smlouvy.
    let branchName = '', branchAddress = '', branchSelfService = false
    try {
      let brId = (booking.branch_id as string | null) || null
      if (!brId) {
        const { data: motoBr } = await supabase.from('motorcycles').select('branch_id').eq('id', booking.moto_id).single()
        brId = motoBr?.branch_id || null
      }
      const { data: br } = brId ? await supabase.from('branches').select('name, address, city, type').eq('id', brId).maybeSingle() : { data: null }
      if (br) {
        branchSelfService = br.type === 'samoobslužná'
        if (!booking.pickup_address) { branchName = br.name || ''; branchAddress = [br.address, br.city].filter(Boolean).join(', ') }
      }
    } catch { /* ignore */ }
    if (booking.pickup_address) branchAddress = booking.pickup_address
    // Časy (2026-10-01): samoobsluha s převzetím na pobočce od 12:00 se slevou za pozdní vyzvednutí,
    // jinak 00:01; vrácení na pobočce 24:00. Převzetí na pobočce = ne delivery a adresa prázdná (jako SQL).
    const pickupAtBranch = booking.pickup_method !== 'delivery' && !String(booking.pickup_address || '').trim()
    const returnAtBranch = booking.return_method !== 'delivery' && !String(booking.return_address || '').trim()
    const storedPickup = String(booking.pickup_time || '').startsWith('00:01') ? '' : (booking.pickup_time || '')
    const latePickupGranted = Number(booking.late_pickup_discount_amount || 0) > 0
    const startTime = branchSelfService && pickupAtBranch ? (latePickupGranted ? '12:00' : '00:01') : (storedPickup || '10:00')
    const endTime = branchSelfService && returnAtBranch ? '24:00' : (booking.return_time || '24:00')

    // Jazyková verze: čerstvý překlad, jinak závazná čeština (+ upozornění, překlad na pozadí).
    let baseContent: string, docTitle: string, docLang: string, mode: Mode
    if (hasDbContent) {
      const p = await pickContent(template, template_slug, lang)
      baseContent = p.content; docTitle = p.title; docLang = p.docLang; mode = p.mode
    } else {
      baseContent = getFallbackTemplate(template_slug) || ''; docTitle = template?.name || template_slug; docLang = 'cs'
      mode = lang === 'cs' ? 'cs' : 'cs_binding'
      await logDebug('doc_template_fallback', 'warning', { template_slug, booking_id }, tErr?.message)
    }
    // Překlad sdíleného právního textu (placený) vyžádá jen service_role / Velín, nikdy zákazník (EDGE-DOC-18).
    const retranslating = mode === 'cs_binding' && hasDbContent && who.kind !== 'user' ? enqueueRetranslation(template, lang) : false

    const vars = buildVars({
      booking, bookingId: booking_id, customer, moto: booking.motorcycles || {}, extras, branchName, branchAddress,
      pickupTime: branchSelfService && pickupAtBranch ? (storedPickup || '00:01') : storedPickup,
      startTime, endTime, company: companyInfo, webLabel: webLabelForLang(lang), docLang,
    })
    // gear: {{gear_items_table}}, {{gear_period}}, {{gear_days}}… + výbava bez „(řidič)“ (gear-vars.ts)
    if (isGearDoc(booking)) Object.assign(vars, buildGearVars(booking, docLang, await loadGearPriceRows(supabase)))

    let htmlContent = baseContent
    for (const [key, val] of Object.entries(vars)) htmlContent = htmlContent.replace(new RegExp(`\\{\\{${key}\\}\\}`, 'g'), val)
    htmlContent = localizeDocLinks(htmlContent, lang)
    if (mode === 'cs_binding') htmlContent = applyNotice(htmlContent, lang)
    if (mode === 'fresh') htmlContent = setHtmlLang(htmlContent, lang)
    htmlContent = wrapDocument(htmlContent, docTitle, docLang)

    // PDF přes PDFShift; fallback HTML (klíč chybí / konverze selže).
    const docId = crypto.randomUUID()
    let path: string
    let upErr: unknown = null
    const pdfBytes = await htmlToPdf(htmlContent)
    if (pdfBytes) {
      path = `generated/${docId}.pdf`
      upErr = (await supabase.storage.from('documents').upload(path, new Blob([pdfBytes], { type: 'application/pdf' }), { upsert: true, contentType: 'application/pdf' })).error
    } else {
      path = `generated/${docId}.html`
      upErr = (await supabase.storage.from('documents').upload(path, new Blob([htmlContent], { type: 'text/html' }), { upsert: true, contentType: 'text/html' })).error
    }
    if (upErr) console.error('Storage upload error:', upErr) // záznam vznikne i tak (filled_data pro render v klientovi)

    // Přemazání starších verzí téhož typu (booking_id + template_id; fallback bez template_id se nepřemazává).
    let oldDocs: Array<{ id: string; pdf_path: string | null }> = []
    if (template?.id) {
      try {
        const { data: prev } = await supabase.from('generated_documents').select('id, pdf_path').eq('booking_id', booking_id).eq('template_id', template.id)
        if (Array.isArray(prev)) oldDocs = prev
      } catch { /* ignore */ }
    }

    const { error: gErr } = await supabase.from('generated_documents').insert({
      id: docId, template_id: template?.id || null, booking_id, customer_id: customer.id || booking.user_id,
      // _lang = jazyk zákazníka, _doc_lang = jazyk textu, _translation = fresh | cs_binding | cs (Velín / appka)
      filled_data: { ...vars, _lang: lang, _doc_lang: docLang, _translation: mode }, pdf_path: path,
    })
    if (gErr) {
      console.error('Insert error:', gErr)
      return json({ error: 'Failed to insert generated document: ' + gErr.message }, 500)
    }

    // Synchronizovaný `documents` řádek → nový soubor; staré verze (řádky + soubory) pryč.
    if (oldDocs.length) {
      const s = String(template_slug || '').toLowerCase()
      const vDocType = s.includes('contract') ? 'contract' : s.includes('protocol') ? 'protocol' : s === 'vop' ? 'vop' : 'contract'
      try { await supabase.from('documents').update({ file_path: path }).eq('booking_id', booking_id).eq('type', vDocType) } catch { /* ignore */ }
      const oldFiles = oldDocs.map((d) => d.pdf_path).filter((p): p is string => !!p && p !== path)
      try { await supabase.from('generated_documents').delete().in('id', oldDocs.map((d) => d.id)) } catch { /* ignore */ }
      if (oldFiles.length) { try { await supabase.storage.from('documents').remove(oldFiles) } catch { /* ignore */ } }
    }

    try {
      await supabase.from('admin_audit_log').insert({
        action: 'document_generated',
        new_data: { document_id: docId, template_slug, booking_id, language: lang, translation: mode, retranslating },
      })
    } catch { /* ignore */ }

    return json({ success: true, document_id: docId, path, language: lang, translation: mode })
  } catch (err) {
    console.error('Error:', err)
    return json({ error: (err as Error).message }, 500)
  }
})
