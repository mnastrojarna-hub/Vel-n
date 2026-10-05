// submit-handover-protocol — uloží předávací protokol pro samoobslužnou pobočku.
//
// mode='customer' : zákazník podepsal v appce (vlastní JWT; service_role/admin projde také).
// mode='kiosk'    : zákazník podepsal prstem na displeji pobočky — request nese jen anon
//                   apikey, auth = device_id + device_token (RPC kiosk_device_branch) a
//                   rezervace musí mít na téže pobočce VYDANÝ kód k motorce.
// mode='auto'     : ZRUŠENO 2026-09-25 (automatické vyplnění po 1 h) → 403.
//
// Tok: auth → rezervace → idempotence (already_filled) → stav (wrong_status/too_early;
// too_early i před `release_at` — sleva za vyzvednutí od 12:00, odpověď nese release_at)
// → propis výbavy do bookings (změněná velikost; NEpřevzatá položka = odebrání z rezervace,
// sloupec → NULL; z kiosku i výbava převzatá NAVÍC — `gear_add`; ceny/booking_extras beze změny)
// → HTML → PDF přes render-pdf (fallback HTML)
// → bucket `documents` → ATOMICKÝ CLAIM handover_protocol_filled_at (UPDATE … WHERE
// filled_at IS NULL; 0 řádků = podepsáno souběžně jinde → already_filled + úklid souboru)
// → generated_documents (sync trigger → `documents`, appka) → stav km do bookings.mileage_start
// (km vyplňuje systém — _handover_pickup_km, u kiosku hodnota jednotky; form.mileage
// z appky se ignoruje) → e-mail (best-effort). Soubor se ukládá PŘED claimem: claim spouští
// trg_handover_signed_notify_kiosk (kiosk otevře kóji) — po něm zbývá jen INSERT řádku;
// když selže, claim se vrátí (jen ten náš), sirotek v bucketu se smaže a vrací se 500.
//
// Odpověď stabilně {success, already_filled?, doc_id?, email_sent?, error?}:
// 4xx = trvalá chyba (kiosk už neopakuje), 5xx/síť = dočasná (kiosk opakuje z fronty).
// Kiosk mapuje 404 jako dočasné („edge nenasazená“) → chybějící rezervace vrací 410.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { authClassify } from '../_shared/auth.ts'
import { buildHtml, normalizeMotoEquipment, type Signer, type Vars } from './html.ts'
import { bookingGearItems, normalizeAccessories, resolveGearUpdates } from './gear.ts'
import {
  CORS, fail, fmtDate, json, parseSignedAt, positiveKm, pragueDay, removeDocument, resolvePickupKm, SIG_MAX_APP,
  SIG_MAX_KIOSK, SIG_RE, signatureBytes, storeDocument, UUID_RE,
} from './util.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

// Stavy, ve kterých lze podepsat. Kiosk navíc `completed`: podpis pořízený na
// displeji během výpadku sítě dorazí z trvalé fronty třeba až po nočním
// auto_complete_expired_bookings (deaktivuje kódy) — 4xx by ho na jednotce trvale
// zahodil (§0: podpis se NIKDY neztratí). Dokument je datován kioskovým signed_at.
const OK_STATUS_APP = ['reserved', 'active']
const OK_STATUS_KIOSK = [...OK_STATUS_APP, 'completed']
// Tolerance posunu hodin jednotky u hradla „výdej až od 12:00“ (kiosk ho vynucuje sám).
const KIOSK_CLOCK_SKEW_MS = 5 * 60_000

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return fail('method_not_allowed', 405)

  const admin = createClient(SUPABASE_URL, SERVICE_KEY)
  try {
    const body = await req.json().catch(() => null) as Record<string, unknown> | null
    if (!body || typeof body !== 'object') return fail('bad_request', 400)
    const bookingId = String(body.booking_id || '')
    const modeRaw = String(body.mode || 'customer')
    if (!bookingId) return fail('missing_booking_id', 400)
    if (modeRaw === 'auto') return fail('forbidden', 403, { reason: 'auto_mode_removed' })
    const mode: 'customer' | 'kiosk' = modeRaw === 'kiosk' ? 'kiosk' : 'customer'
    const now = new Date()

    // ── Auth ───────────────────────────────────────────────────────────────
    // Kiosk se vyhodnocuje PŘED kontrolou JWT — request nese jen anon apikey.
    let deviceId = ''
    let branchId = ''
    let who: { kind: 'service' | 'admin' | 'user' | 'none'; userId?: string } = { kind: 'none' }
    if (mode === 'kiosk') {
      deviceId = String(body.device_id || '')
      const token = String(body.device_token || '')
      if (!UUID_RE.test(deviceId) || !UUID_RE.test(token)) return fail('unauthorized', 401)
      const { data: br, error: aErr } = await admin.rpc('kiosk_device_branch', { p_device_id: deviceId, p_device_token: token, p_touch: false })
      if (aErr) return fail('auth_error', 500, { detail: aErr.message })
      if (!br) return fail('unauthorized', 401)
      branchId = String(br)
    } else {
      who = await authClassify(req)
      if (who.kind === 'none') return fail('unauthenticated', 401)
    }

    // ── Rezervace + vozidlo + pobočka (service role, obejde RLS) ───────────
    const { data: booking, error: bErr } = await admin
      .from('bookings')
      .select('*, motorcycles!moto_id(model, spz, vin, mileage, tracking_unit, branch_id, branches(type))')
      .eq('id', bookingId)
      .maybeSingle()
    if (bErr) return fail('db_error', 500, { detail: bErr.message })
    // Kiosk: smazaná rezervace (úklid testů, Velín) = TRVALÁ chyba → 410; 404 by
    // jednotka brala jako dočasné a položku posílala z fronty každých 30 s navěky.
    if (!booking) return fail('not_found', mode === 'kiosk' ? 410 : 404)
    const moto = (booking.motorcycles || {}) as Record<string, unknown>

    if (mode === 'customer' && who.kind === 'user' && booking.user_id !== who.userId) return fail('forbidden', 403)

    // Idempotence — podepsáno (kdekoli) = hotovo. U kiosku PŘED kontrolou kódu: položka
    // z fronty po výpadku sítě nesmí skončit „forbidden" jen proto, že kód mezitím zanikl.
    if (booking.handover_protocol_filled_at) return json({ success: true, already_filled: true })

    if (mode === 'kiosk') {
      // Kiosk smí podepsat jen rezervaci, které pobočka zařízení VYDALA kód k motorce.
      // Bez `is_active`: kód mohl mezitím zaniknout (regenerace, completed) — podpis
      // z fronty musí projít; vydání (sent_to_customer) je identita, ne platnost.
      const { data: code, error: cErr } = await admin
        .from('branch_door_codes').select('id')
        .eq('booking_id', bookingId).eq('code_type', 'motorcycle').eq('branch_id', branchId)
        .eq('sent_to_customer', true)
        .limit(1).maybeSingle()
      if (cErr) return fail('auth_error', 500, { detail: cErr.message })
      if (!code) return fail('forbidden', 403)
    }

    const okStatus = mode === 'kiosk' ? OK_STATUS_KIOSK : OK_STATUS_APP
    if (!okStatus.includes(String(booking.status))) return fail('wrong_status', 400, { status: booking.status })
    const branchType = ((moto.branches || {}) as Record<string, unknown>).type
    if (branchType !== 'samoobslužná') return fail('not_self_service', 400)
    // Appka: ne dřív než v den převzetí (kiosk protokol ukáže jen s platným kódem).
    if (mode === 'customer' && !booking.handover_protocol_started_at && pragueDay(new Date(booking.start_date)) > pragueDay(now)) {
      return fail('too_early', 400)
    }
    // Sleva za vyzvednutí od 12:00 (2026-10-01h): kiosk takovou rezervaci vydá
    // až od 12:00 Prahy v den začátku → ani protokol nejde podepsat dřív
    // (zdroj pravdy `_kiosk_release_at`, stejně jako get_handover_protocol_state).
    // Kiosk se NEodmítá: hradlo vynucuje sám a podpis z jeho fronty dokládá
    // předání, které už proběhlo — 4xx by ho trvale zahodil (§0); jen log.
    // Chyba RPC (např. SQL ještě nenasazené) = bez hradla, jen log.
    const { data: relRaw, error: relErr } = await admin.rpc('_kiosk_release_at', { p_booking_id: bookingId })
    if (relErr) console.warn('[handover] _kiosk_release_at:', relErr.message)
    const releaseAt = !relErr && relRaw ? new Date(String(relRaw)) : null
    if (releaseAt && !Number.isNaN(releaseAt.getTime())) {
      if (mode === 'kiosk') {
        if (parseSignedAt(body.signed_at, now).getTime() + KIOSK_CLOCK_SKEW_MS < releaseAt.getTime()) {
          console.warn('[handover] kiosk signature before release_at', bookingId, body.signed_at)
          try {
            await admin.from('debug_log').insert({ source: 'submit-handover-protocol', action: 'handover_kiosk_before_release',
              status: 'warning', request_data: { booking_id: bookingId, signed_at: body.signed_at ?? null, release_at: releaseAt.toISOString() } })
          } catch { /* jen log */ }
        }
      } else if (now.getTime() < releaseAt.getTime()) {
        return fail('too_early', 400, { release_at: releaseAt.toISOString() })
      }
    }

    // ── Podpis (limit = dekódované bajty PNG, stejně jako kiosk) ───────────
    const signature = typeof body.signature === 'string' ? body.signature.trim() : ''
    if (!signature) return fail('missing_signature', 400)
    if (signatureBytes(signature) > (mode === 'kiosk' ? SIG_MAX_KIOSK : SIG_MAX_APP)) return fail('signature_too_large', 413)
    if (!SIG_RE.test(signature)) return fail('invalid_signature', 400)
    const signer: Signer = mode === 'kiosk'
      ? { by: 'kiosk', deviceId, signedAt: parseSignedAt(body.signed_at, now) }
      : { by: 'app', signedAt: now }

    // ── Formulář (kiosk: chybějící části doplní edge) ──────────────────────
    const form: Record<string, unknown> = body.form && typeof body.form === 'object' ? { ...(body.form as Record<string, unknown>) } : {}
    let accessories = normalizeAccessories(form.accessories, mode === 'kiosk')
    // Výbava motorky (2026-09-28): kiosk i appka (zrcadlo kiosku) ji posílají
    // (předem zaškrtnutá, zákazník odškrtne chybějící); starší build JEDNOTKY bez
    // pole → vše předáno, starší build APPKY bez pole → sekce v dokumentu není.
    // Při poslané skupině html.ts vynechá kotoučový zámek a reflexní prvky ze
    // „Doplňkového vybavení" (jsou ve skupině — dokument se nezdvojí ani neodporuje).
    const motoEquipment = normalizeMotoEquipment(form.moto_equipment, mode === 'kiosk' ? true : null)
    if (motoEquipment) form.moto_equipment = motoEquipment
    else delete form.moto_equipment
    if (mode === 'kiosk') {
      if (!Array.isArray(form.accessories)) accessories = bookingGearItems(booking)
      form.checks = { clean: true, docs: true, keys: true, instructed: true, gear: accessories.some((a) => a.checked), ...((form.checks && typeof form.checks === 'object') ? form.checks as Record<string, unknown> : {}) }
      if (!form.damage || typeof form.damage !== 'object') form.damage = { checked: false, desc: '' }
      if (typeof form.notes !== 'string') form.notes = ''
    }
    form.accessories = accessories // stejná reference: resolveGearUpdates níže položky mutuje (`removed`) → buildHtml je vidí
    // Odebrání nepřevzaté položky z rezervace jen od klienta, který sémantiku zná (opt-in):
    // kiosk ≥ 1.2.4 (starší jednotky posílají vždy checked:true), appka s `form.gear_remove: true`
    // (starší buildy appky mají checkbox bez vysvětlení → jejich ☐ zůstává jen v dokumentu jako dřív).
    const allowRemove = mode === 'kiosk' || form.gear_remove === true
    // Výbava převzatá NAVÍC (2026-10-05): jen kiosk ≥ 1.2.5 (`form.gear_add`) a jen rezervace s přístupem do šatny
    // (výbava už vyzvednutá, nebo vydaný kód šatny) — u rezervace bez šatny by přidání velikosti vydalo nový kód
    // šatny uprostřed převzetí (trg_sync_locker_code). Chyba dotazu = bez přidání (dokument ji ukáže jako „navíc“).
    let allowAdd = false
    if (mode === 'kiosk' && form.gear_add === true
        && accessories.some((a) => a.checked && a.field && !String(booking[a.field] ?? '').trim())) {
      if (booking.gear_collected_at) allowAdd = true
      else {
        try {
          // jen AKTIVNÍ kód šatny této pobočky — zadržený/deaktivovaný kód by přidáním velikosti znovu ožil
          // (trg_sync_locker_code: kód + zpráva + e-mail uprostřed převzetí)
          const { data: acc } = await admin.from('branch_door_codes').select('id')
            .eq('booking_id', bookingId).eq('code_type', 'accessories').eq('sent_to_customer', true)
            .eq('is_active', true).eq('branch_id', branchId).limit(1).maybeSingle()
          allowAdd = !!acc
        } catch (_) { allowAdd = false }
      }
    }

    // ── Stav km při předání = VŽDY systém (zadání majitele 2026-09-29) ─────
    // Zákazník km nezadává: platí poslední stav z vrácení předchozím zákazníkem
    // (kiosk), z přesunu ve Velínu nebo z korekce. Appka: form.mileage se IGNORUJE
    // (4.0.7/4.0.8 mají ještě volné pole) → vždy DB _handover_pickup_km. Kiosk:
    // hodnota jednotky, je-li to kladné celé číslo — v její offline frontě může
    // ještě čekat neodeslaný stav vrácení předchozího zákazníka (a vrácení téže
    // rezervace může dorazit dřív než podpis převzetí); jinak totéž RPC.
    let pickupKm = mode === 'kiosk' ? positiveKm(form.mileage) : null
    if (pickupKm == null) pickupKm = await resolvePickupKm(admin, bookingId, moto.mileage)
    const mileageUnit: 'km' | 'mh' = moto.tracking_unit === 'mh' ? 'mh' : 'km'
    form.mileage = pickupKm != null ? String(pickupKm) : ''
    form.mileage_unit = mileageUnit

    // ── Zákazník ───────────────────────────────────────────────────────────
    let customer: Record<string, unknown> = {}
    if (booking.user_id) {
      const { data: prof } = await admin.from('profiles').select('id, full_name, email').eq('id', booking.user_id).maybeSingle()
      if (prof) customer = prof
    }
    const bn = String(bookingId).slice(-8).toUpperCase()
    const vars: Vars = {
      booking_number: bn,
      today: now.toLocaleDateString('cs-CZ', { timeZone: 'Europe/Prague' }),
      company_name: 'Bc. Petra Semorádová, MotoGo24',
      customer_name: (customer.full_name as string) || (customer.email as string) || '—',
      moto_model: (moto.model as string) || '—',
      moto_spz: (moto.spz as string) || '',
      moto_vin: (moto.vin as string) || '',
      rental_period: `${fmtDate(booking.start_date)} — ${fmtDate(booking.end_date)}`,
      // 00:01 = stará samoobsluha „bez času“ → řádek se nevypíše
      pickup_time: booking.pickup_time && !String(booking.pickup_time).startsWith('00:01')
        ? `${fmtDate(booking.start_date)} ${String(booking.pickup_time).slice(0, 5)}` : '',
    }

    // ── Výbava → bookings (PŘED claimem; vlastní záznam historie, trigger
    // track_booking_content_changes pak vlastní „system“ záznam nepřidá): změněná
    // velikost převzaté položky; NEpřevzatá položka = odebrání z rezervace (NULL,
    // `removed` pro dokument). Ceny / booking_extras se NEMĚNÍ (rozhodnutí majitele
    // čeká — vratku řeší Velín ručně).
    try {
      const { updates, changes } = await resolveGearUpdates(admin, booking, accessories, allowRemove, allowAdd,
        mode === 'kiosk' && form.gear_add === true)
      if (Object.keys(updates).length) {
        const entry = { at: now.toISOString(), auto: true, source: 'protocol', signed_by: signer.by, ...(deviceId ? { device_id: deviceId } : {}), gear_changes: changes }
        const hist = Array.isArray(booking.modification_history) ? booking.modification_history : []
        const { error: uErr } = await admin.from('bookings').update({ ...updates, modification_history: [...hist, entry] })
          .eq('id', bookingId).is('handover_protocol_filled_at', null)
        if (uErr) throw uErr
      }
    } catch (e) { // propis výbavy je best-effort, podpis neshodí; neodebráno → bez poznámky v dokumentu, ale dohledatelné
      for (const a of accessories) delete a.removed
      const msg = (e as Error)?.message ?? String(e)
      console.warn('[handover] gear update failed', bookingId, msg)
      try {
        await admin.from('debug_log').insert({ source: 'submit-handover-protocol', action: 'handover_gear_update_failed', status: 'error',
          error_message: msg, request_data: { booking_id: bookingId, signed_by: signer.by, allow_remove: allowRemove, allow_add: allowAdd,
            accessories: accessories.map(({ field, checked, size }) => ({ field, checked, size })) } })
      } catch { /* jen log */ }
    }

    // ── Dokument do bucketu PŘED claimem (viz hlavička) ────────────────────
    const html = buildHtml(vars, form, signature, signer)
    const docId = crypto.randomUUID()
    let pdfPath = ''
    try { pdfPath = await storeDocument(admin, bookingId, docId, html) } catch (e) {
      return fail('storage_failed', 500, { detail: (e as Error).message })
    }

    // ── ATOMICKÝ CLAIM ─────────────────────────────────────────────────────
    const claimedAt = now.toISOString()
    const { data: claimed, error: clErr } = await admin.from('bookings')
      .update({ handover_protocol_filled_at: claimedAt, handover_protocol_autofilled: false })
      .eq('id', bookingId).is('handover_protocol_filled_at', null).select('id')
    if (clErr) { await removeDocument(admin, pdfPath); return fail('claim_failed', 500, { detail: clErr.message }) }
    if (!claimed?.length) { await removeDocument(admin, pdfPath); return json({ success: true, already_filled: true }) }

    // ── Řádek dokumentu (sync trigger → `documents`, appka) ────────────────
    const filled = {
      ...vars,
      _signed_html: html,
      _doc_name: 'Předávací protokol (elektronický)',
      _doc_type: 'handover_protocol',
      _electronic: true,
      _autofilled: false,
      _self_service: true,
      _signed_at: signer.signedAt.toISOString(),
      _signed_by: signer.by,
      ...(deviceId ? { _device_id: deviceId } : {}),
      _mileage: pickupKm,
      _mileage_unit: mileageUnit,
    }
    const { error: gErr } = await admin.from('generated_documents').insert({
      id: docId, template_id: null, booking_id: bookingId, customer_id: booking.user_id, filled_data: filled, pdf_path: pdfPath,
    })
    if (gErr) {
      await removeDocument(admin, pdfPath)
      // Pojistka generated_documents_handover_once: protokol už existuje (jiný podpis) → claim platí, hotovo.
      if (gErr.code === '23505') return json({ success: true, already_filled: true })
      // Vrátit JEN náš claim (podpis se neztratí — klient zopakuje).
      try {
        await admin.from('bookings').update({ handover_protocol_filled_at: null })
          .eq('id', bookingId).eq('handover_protocol_filled_at', claimedAt)
      } catch (_) { /* best-effort */ }
      return fail('insert_failed', 500, { detail: gErr.message })
    }

    // Systémový stav km z protokolu (pickupKm výše) → bookings.mileage_start (trigger
    // trg_booking_mileage_to_moto bumpne motorcycles.mileage = GREATEST). Jen když
    // roste; best-effort.
    try {
      if (pickupKm != null && (!booking.mileage_start || pickupKm > Number(booking.mileage_start))) {
        await admin.from('bookings').update({ mileage_start: pickupKm }).eq('id', bookingId)
      }
    } catch (_) { /* nikdy neshodí protokol */ }

    // Protokol zákazníkovi e-mailem (best-effort; v appce ho má přes sync do `documents`).
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

    return json({ success: true, already_filled: false, doc_id: docId, email_sent: emailSent })
  } catch (e) {
    return fail('internal', 500, { detail: (e as Error).message })
  }
})
