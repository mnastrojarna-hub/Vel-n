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
 *     user_id:        string (uuid),         // POVINNÉ — vlastník dokladu
 *     booking_id:     string (uuid)|null,    // volitelné — vazba na rezervaci
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
 *   4xx { success: false, error }
 *
 * Bezpečnost:
 *   - Žádný token check (anonymous flow z webu) — místo toho ověříme, že
 *     `user_id` skutečně existuje v `auth.users` a fotku uložíme pod cestu
 *     `<user_id>/...`, takže útočník bez znalosti UUID nemůže nikam zapsat
 *     cizímu zákazníkovi smysluplně. Validace velikosti a MIME zabrání zneužití.
 *   - Maximální velikost obrázku: 8 MB (cca 11 MB base64).
 *   - Pokud `booking_id` neodpovídá `user_id` v `bookings.user_id`, fn vrátí 403.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_BYTES = 8 * 1024 * 1024 // 8 MB raw
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

  const userId = String(body?.user_id || '').trim()
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

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId)) {
    return jsonRes({ success: false, error: 'Invalid user_id' }, 400)
  }
  const meta = DOC_TYPE_MAP[docTypeRaw]
  if (!meta) return jsonRes({ success: false, error: 'Invalid doc_type (id|dl|passport)' }, 400)
  if (!imageB64Raw) return jsonRes({ success: false, error: 'Missing image_base64' }, 400)

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

  // Ověř, že uživatel existuje (zabrání zápisu pod náhodné UUID)
  try {
    const { data: prof, error: profErr } = await sb.from('profiles').select('id').eq('id', userId).maybeSingle()
    if (profErr || !prof) {
      return jsonRes({ success: false, error: 'User not found' }, 404)
    }
  } catch {
    return jsonRes({ success: false, error: 'User check failed' }, 500)
  }

  // Pokud klient poslal booking_id, ověř, že patří tomuto user_id
  if (bookingId) {
    try {
      const { data: bk } = await sb.from('bookings').select('id, user_id').eq('id', bookingId).maybeSingle()
      if (!bk || bk.user_id !== userId) {
        return jsonRes({ success: false, error: 'Booking does not match user' }, 403)
      }
    } catch {
      return jsonRes({ success: false, error: 'Booking check failed' }, 500)
    }
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
  // metadata sloupec — pokud ještě neexistuje (migrace nedoběhla), dělá se fallback bez něj
  const rowWithMeta = {
    ...row,
    metadata: {
      source: 'web',
      mindee_status: mindeeStatus,
      ocr_fields: ocrFields,
      captured_at: new Date().toISOString(),
      side: docSide, // 'front' | 'back' | null (pas)
    },
  }

  let docId: string | null = null
  let ins = await sb.from('documents').insert(rowWithMeta).select('id').single()
  if (ins.error && /metadata/i.test(ins.error.message || '')) {
    const ins2 = await sb.from('documents').insert(row).select('id').single()
    if (ins2.error) {
      console.error('[save-verification-document] insert failed (no metadata):', ins2.error.message)
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
  // proto nastavujeme i *_verified_at (uvolní přístupové kódy ke dveřím).
  if (ocrFields) {
    const dateRe = /^\d{4}-\d{2}-\d{2}$/
    const f = ocrFields as Record<string, unknown>
    const idNum = typeof f.idNumber === 'string' ? f.idNumber.trim() : ''
    const licNum = typeof f.licenseNumber === 'string' ? f.licenseNumber.trim() : ''
    const licExp = typeof f.licenseExpiry === 'string' ? f.licenseExpiry.trim() : ''
    const dob = typeof f.dob === 'string' ? f.dob.trim() : ''
    const nowIso = new Date().toISOString()
    const upd: Record<string, unknown> = {}

    if (meta.dbType === 'id_card' && idNum) { upd.id_number = idNum; upd.id_verified_at = nowIso }
    if (meta.dbType === 'passport' && idNum) { upd.id_number = idNum; upd.passport_verified_at = nowIso }
    if (meta.dbType === 'drivers_license') {
      if (licNum) { upd.license_number = licNum; upd.license_verified_at = nowIso }
      if (dateRe.test(licExp)) upd.license_expiry = licExp
    }
    if (dateRe.test(dob)) upd.date_of_birth = dob

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
