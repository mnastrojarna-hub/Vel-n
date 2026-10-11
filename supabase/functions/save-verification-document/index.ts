/**
 * MotoGo24 — Edge Function: save-verification-document
 *
 * Robustní uložení fotky verifikačního dokladu (OP / pas / ŘP) z webu motogo24.*.
 * Volá se z rezervačního flow (motogo-web-php) **vždy** — ať už Mindee OCR uspěl
 * nebo selhal. Cíl: zákazník nikdy nesmí přijít o nahranou fotku jen kvůli tomu,
 * že jeho client-side Supabase session nebyla obnovena nebo storage RLS nedovolil
 * přímý upload.
 *
 * Edge fn běží pod **service_role**, takže obejde RLS pro `storage.objects`
 * i pro `public.documents` a má jistotu, že záznam vznikne.
 *
 * POST /functions/v1/save-verification-document
 * Body:
 *   {
 *     user_id:        string (uuid),         // vlastník dokladu (povinné, není-li booking_id)
 *     booking_id:     string (uuid)|null,    // vazba na rezervaci; u hosta bez session = oprávnění
 *     doc_type:       'id' | 'dl' | 'passport',  // klient používá id/dl, pas pošle 'id' s passport=true (zde mapujeme)
 *     image_base64:   string,                // POVINNÉ — JPEG base64 (s nebo bez data: prefixu)
 *     mindee_status:  'ok' | 'failed',       // proběhl Mindee OCR úspěšně?
 *     ocr_fields:     object|null,           // extrahovaná pole z Mindee (jen když ok)
 *     mime?:          string,                // default 'image/jpeg'
 *     doc_side?:      'front' | 'back' | null, // 2026-05-08: strana dokladu pro OP a ŘP.
 *                                              // Pas má jen jednu stranu — nepouŽívat. Uloží se do metadata.side.
 *   }
 *
 * Odpověď:
 *   200 { success: true, document_id, file_path }
 *   4xx { success: false, error }   (401 auth_required / 403 forbidden — bez detailu)
 *
 * Bezpečnost (2026-10-11 — dřív žádná kontrola volajícího, stačilo cizí UUID):
 *   - Volajícího ověří `resolveDocCaller` (_shared/auth.ts): service_role,
 *     aktivní admin (Velín), přihlášený zákazník sám za sebe (appka, web s JWT),
 *     host bez session jen s booking_id ŽIVÉ rezervace (pending/reserved/active,
 *     konec dle Prahy ≥ dnes) → cíl = vlastník rezervace. verify_jwt zůstává false.
 *   - Zápis jde VŽDY pod ověřeného vlastníka (`<owner>/...`, documents, profil).
 *   - „User not found" (404) jen pro admin/service; jinak obecné 403 (bez orákula).
 *   - Nositel odkazu (via booking) nepřepíše čísla dokladů ověřená PŘED založením
 *     té rezervace (vlastníkova stará data); skeny v rámci rezervace přepisuje.
 *   - Max. 8 MB obrázek; base64 nad 12 MB znaků se odmítne ještě před dekódováním.
 *   - metadata.via / uploaded_by = audit, kdo doklad nahrál.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { resolveDocCaller } from '../_shared/auth.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_BYTES = 8 * 1024 * 1024 // 8 MB raw
const MAX_B64_CHARS = 12_000_000  // ochrana před dekódováním (8 MB ≈ 10,7 M znaků base64)
const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])

const DOC_TYPE_MAP: Record<string, { dbType: string; ext: string; label: string }> = {
  id: { dbType: 'id_card', ext: 'jpg', label: 'Doklad totožnosti' },
  passport: { dbType: 'passport', ext: 'jpg', label: 'Cestovní pas' },
  dl: { dbType: 'drivers_license', ext: 'jpg', label: 'Řidičský průkaz' },
}

function jsonRes(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return jsonRes({ success: false, error: 'Method not allowed' }, 405)

  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    return jsonRes({ success: false, error: 'Service not configured' }, 500)
  }

  let body: any
  try { body = await req.json() }
  catch { return jsonRes({ success: false, error: 'Invalid JSON' }, 400) }

  const userIdRaw = String(body?.user_id || '').trim()
  const bookingId = body?.booking_id ? String(body.booking_id).trim() : null
  const docTypeRaw = String(body?.doc_type || 'id').trim().toLowerCase()
  const imageB64Raw = String(body?.image_base64 || '')
  const mindeeStatus = body?.mindee_status === 'ok' ? 'ok' : 'failed'
  const ocrFields = (mindeeStatus === 'ok' && body?.ocr_fields && typeof body.ocr_fields === 'object') ? body.ocr_fields : null
  const mime = ALLOWED_MIME.has(body?.mime) ? body.mime : 'image/jpeg'
  // Strana dokladu (líc/rub) — povinné pro OP a ŘP, ignorováno pro pas.
  // Uloží se do `documents.metadata.side` (jsonb) — bez DB schema migrace.
  const docSideRaw = body?.doc_side != null ? String(body.doc_side).trim().toLowerCase() : null
  const docSide: 'front' | 'back' | null =
    docSideRaw === 'front' || docSideRaw === 'back' ? docSideRaw : null

  if (!userIdRaw && !bookingId) return jsonRes({ success: false, error: 'Missing user_id' }, 400)
  if (userIdRaw && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userIdRaw)) {
    return jsonRes({ success: false, error: 'Invalid user_id' }, 400)
  }
  const meta = DOC_TYPE_MAP[docTypeRaw]
  if (!meta) return jsonRes({ success: false, error: 'Invalid doc_type (id|dl|passport)' }, 400)
  if (!imageB64Raw) return jsonRes({ success: false, error: 'Missing image_base64' }, 400)
  if (imageB64Raw.length > MAX_B64_CHARS) return jsonRes({ success: false, error: 'Image too large (>8MB)' }, 413)

  // Kdo volá a za koho (2026-10-11) — PŘED dekódováním a jakýmkoli zápisem
  const who = await resolveDocCaller(req, userIdRaw || null, bookingId)
  if (!who.ok) return jsonRes({ success: false, error: who.reason }, who.status)
  const userId = who.userId as string
  const privileged = who.via === 'admin' || who.via === 'service'

  // Strip data: prefix
  const cleanB64 = imageB64Raw.includes(',') ? imageB64Raw.split(',')[1] : imageB64Raw

  let bytes: Uint8Array
  try { bytes = Uint8Array.from(atob(cleanB64), (c) => c.charCodeAt(0)) }
  catch { return jsonRes({ success: false, error: 'Invalid base64' }, 400) }

  if (bytes.byteLength === 0) return jsonRes({ success: false, error: 'Empty image' }, 400)
  if (bytes.byteLength > MAX_BYTES) return jsonRes({ success: false, error: 'Image too large (>8MB)' }, 413)

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // Ověř, že profil existuje (404 jen pro admin/service — jinak bez orákula).
  // Vazbu booking_id ↔ vlastník už ověřil resolveDocCaller.
  try {
    const { data: prof, error: profErr } = await sb.from('profiles').select('id').eq('id', userId).maybeSingle()
    if (profErr || !prof) {
      return privileged
        ? jsonRes({ success: false, error: 'User not found' }, 404)
        : jsonRes({ success: false, error: 'forbidden' }, 403)
    }
  } catch {
    return jsonRes({ success: false, error: 'User check failed' }, 500)
  }

  // Cesta v bucketu: <user_id>/<dbType>[_<side>]_<timestamp>.<ext>
  const ext = mime === 'application/pdf' ? 'pdf' : (mime === 'image/png' ? 'png' : (mime === 'image/webp' ? 'webp' : 'jpg'))
  const sideSuffix = docSide ? `_${docSide}` : ''
  const filePath = `${userId}/${meta.dbType}${sideSuffix}_${Date.now()}.${ext}`

  // Upload do storage (service_role obejde RLS)
  const { error: upErr } = await sb.storage.from('documents').upload(filePath, bytes, {
    contentType: mime, upsert: false,
  })
  if (upErr) {
    console.error('[save-verification-document] storage upload failed:', upErr.message)
    return jsonRes({ success: false, error: 'Storage upload failed: ' + upErr.message }, 500)
  }

  // Insert do tabulky documents
  const row: Record<string, unknown> = {
    user_id: userId,
    booking_id: bookingId,
    type: meta.dbType,
    file_path: filePath,
    file_name: filePath.split('/').pop(),
    name: `${meta.label}${docSide ? (docSide === 'front' ? ' — líc' : ' — rub') : ''} (web ${mindeeStatus === 'ok' ? 'sken' : '— manuální'})`,
  }
  // metadata — při chybě zápisu (např. neuložitelná OCR pole) se zkusí znovu
  // jen se základní metadatou: strana (líc/rub) a zdroj nesmí chybět, jinak
  // řádek nesplní bránu dokladů pro vydání kódů (2026-10-10)
  const rowWithMeta = {
    ...row,
    metadata: {
      source: 'web',
      mindee_status: mindeeStatus,
      ocr_fields: ocrFields,
      captured_at: new Date().toISOString(),
      side: docSide, // 'front' | 'back' | null (pas)
      via: who.via, uploaded_by: who.callerId, // audit (2026-10-11)
    },
  }

  let docId: string | null = null
  let ins = await sb.from('documents').insert(rowWithMeta).select('id').single()
  if (ins.error && /metadata/i.test(ins.error.message || '')) {
    const rowMinMeta = {
      ...row,
      metadata: { source: 'web', mindee_status: mindeeStatus, captured_at: new Date().toISOString(), side: docSide, via: who.via, uploaded_by: who.callerId },
    }
    const ins2 = await sb.from('documents').insert(rowMinMeta).select('id').single()
    if (ins2.error) {
      console.error('[save-verification-document] insert failed (minimal metadata):', ins2.error.message)
      // i tak fotka v storage je — vrátíme částečný success
      return jsonRes({ success: true, document_id: null, file_path: filePath, warn: 'documents row insert failed' })
    }
    docId = (ins2.data as any)?.id || null
  } else if (ins.error) {
    console.error('[save-verification-document] insert failed:', ins.error.message)
    return jsonRes({ success: true, document_id: null, file_path: filePath, warn: 'documents row insert failed: ' + ins.error.message })
  } else {
    docId = (ins.data as any)?.id || null
  }

  // Zápis OCR polí do profilu (service_role → obchází RLS). KLÍČOVÉ pro mobil:
  // nepřihlášený nový web zákazník nemůže psát do profilu napřímo (RLS), takže
  // naskenovaná čísla se dosud ztrácela. Zde je zapíšeme serverově. Jen při
  // úspěšném OCR (mindeeStatus==='ok' → ocrFields != null). Reálné OCR = ověření,
  // proto nastavujeme i *_verified_at (od 2026-10-10 samo kódy NEvydá — brána
  // dokladů chce skutečné fotky OP líc+rub / pas a ŘP líc+rub, viz check_booking_docs_status).
  if (ocrFields) {
    const dateRe = /^\d{4}-\d{2}-\d{2}$/
    const f = ocrFields as Record<string, unknown>
    // čísla jen znaky dokladu (jako set_web_booking_docs, 2026-10-11) — ocr_fields
    // posílá klient, do profilu (→ web value="…", smlouvy) nesmí projít HTML
    const docNo = (v: unknown) => typeof v === 'string' ? v.replace(/[^0-9A-Za-zÀ-žА-яЁёЇїІіЄєҐґ /.-]/g, '').trim().slice(0, 30) : ''
    const idNum = docNo(f.idNumber)
    const licNum = docNo(f.licenseNumber)
    const licExp = typeof f.licenseExpiry === 'string' ? f.licenseExpiry.trim() : ''
    const dob = typeof f.dob === 'string' ? f.dob.trim() : ''
    const nowIso = new Date().toISOString()
    const upd: Record<string, unknown> = {}

    // Stav profilu (dřív jen license_expiry). Nositel odkazu (via booking, ne
    // vlastník/admin) nepřepíše číslo ověřené PŘED založením této rezervace —
    // stejně jako set_web_booking_docs (2026-10-11); nenačtený profil = chránit.
    let cur: Record<string, unknown> | null = null
    try {
      const { data } = await sb.from('profiles')
        .select('license_expiry, date_of_birth, id_verified_at, passport_verified_at, license_verified_at').eq('id', userId).maybeSingle()
      cur = (data as Record<string, unknown> | null) ?? null
    } catch { cur = null }
    const bkCreated = who.booking?.created_at ? Date.parse(who.booking.created_at) : NaN
    const keptBefore = (k: string) => who.via === 'booking' &&
      (!cur || isNaN(bkCreated) || (!!cur[k] && Date.parse(String(cur[k])) < bkCreated))
    const keepId = keptBefore('id_verified_at') || keptBefore('passport_verified_at')
    const keepLic = keptBefore('license_verified_at')

    if (meta.dbType === 'id_card' && idNum && !keepId) { upd.id_number = idNum; upd.id_verified_at = nowIso }
    if (meta.dbType === 'passport' && idNum && !keepId) { upd.id_number = idNum; upd.passport_verified_at = nowIso }
    if (meta.dbType === 'drivers_license') {
      if (licNum && !keepLic) { upd.license_number = licNum; upd.license_verified_at = nowIso }
      if (dateRe.test(licExp) && !keepLic) {
        // PLATNOST ŘP ROZHODUJE ZÁKAZNÍK (2026-09-20): `license_expiry` je jeho
        // údaj z registrace / profilu a sken ho NEPŘEPISUJE — špatně přečtený
        // rok jinak držel přístupové kódy s hláškou „ŘP propadlý". Doplní se
        // jen do prázdného pole; `license_verified_until` = hodnota z OCR
        // (záznam pro úřady, tiskne se do smlouvy) se ukládá vždy.
        upd.license_verified_until = licExp
        // profil se nenačetl → raději nepřepisovat
        const curExp = cur ? String(cur.license_expiry ?? '').trim() : 'x'
        if (!curExp) upd.license_expiry = licExp
      }
    }
    // Datum narození nositel odkazu nevidí (get_web_booking_resume) → jen doplní
    // prázdné; přepíše jen u účtu, který tato rezervace právě založila (jako
    // set_web_booking_docs, 2026-10-11). Nenačtený profil = nepřepisovat.
    if (dateRe.test(dob)) {
      let dobOk = who.via !== 'booking' || (!!cur && !cur.date_of_birth)
      if (!dobOk && cur && who.bookingId) {
        try {
          const { data: fresh } = await sb.rpc('_web_booking_created_account', { p_booking_id: who.bookingId })
          dobOk = fresh === true
        } catch { dobOk = false }
      }
      if (dobOk) upd.date_of_birth = dob
    }

    if (Object.keys(upd).length) {
      try {
        const { error: pErr } = await sb.from('profiles').update(upd).eq('id', userId)
        if (pErr) console.error('[save-verification-document] profile update failed:', pErr.message)
      } catch (e) {
        console.error('[save-verification-document] profile update exception:', e)
      }
    }
  }

  return jsonRes({ success: true, document_id: docId, file_path: filePath })
})
