// Doklady zákazníka v Profilu (Velín → Zákazník → Profil → Doklady a oprávnění):
// počet fotek po dokladech + „Odebrat doklad“ (např. propadlý starý OP vedle nového
// pasu). Odebrání = fotky v bucketu `documents` + řádky `documents` daného dokladu
// + údaje dokladu v profilu. Brána kódů k boxu (backend `_docs_gate_checklist`)
// počítá jen existující fotky, změnu profilu zachytí `trg_release_codes_on_profile_verify`;
// kódy, které už zákazník dostal, zůstávají. Oprávnění: RLS `documents_admin` (ALL),
// bucket `documents_admin_all`, admin UPDATE profilu — bez SQL změny.
import { supabase } from './supabase'
import { isMarkerPath } from './docVerification'

// clear = sloupce profilu patřící jen tomuto dokladu (při odebrání → NULL).
// `id_number` je JEDNO pole pro OP i pas (tiskne se do smlouvy) → u OP / pasu novou
// hodnotu volí obsluha (návrh suggestIdNumber). Skupiny ŘP (license_group) zůstávají.
export const DOC_KINDS = {
  id: { label: 'Občanský průkaz', types: ['id_card', 'id_photo'], clear: ['id_verified_at', 'id_verified_until'] },
  passport: { label: 'Cestovní pas', types: ['passport'], clear: ['passport_verified_at', 'passport_verified_until'] },
  dl: {
    label: 'Řidičský průkaz', types: ['drivers_license', 'license_photo'],
    clear: ['license_number', 'license_expiry', 'license_verified_at', 'license_verified_until'],
  },
}
const ALL_TYPES = Object.values(DOC_KINDS).flatMap(k => k.types)

export const kindOfDoc = (d) => Object.keys(DOC_KINDS).find(k => DOC_KINDS[k].types.includes(d?.type)) || null

// Ověřovací doklady zákazníka (nejnovější první)
export async function loadVerificationDocs(userId) {
  const { data, error } = await supabase.from('documents')
    .select('id, type, file_path, name, metadata, created_at')
    .eq('user_id', userId).in('type', ALL_TYPES)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data || []
}

// Číslo dokladu přečtené OCR (metadata.ocr_fields ukládá Velín a web; appka ne)
export function ocrDocNumber(d) {
  const v = d?.metadata?.ocr_fields?.idNumber
  return typeof v === 'string' && v.trim() ? v.trim() : null
}
const normNo = (v) => String(v ?? '').toUpperCase().replace(/\s+/g, '')

// Návrh profiles.id_number po odebrání OP / pasu: nezbude-li žádný doklad totožnosti
// → smazat; jinak ponechat stávající číslo, pokud podle OCR nepatří odebíranému
// dokladu; jinak číslo zbývajícího dokladu z OCR (neznámé → smazat).
export function suggestIdNumber(current, removedDocs, otherDocs, otherVerified) {
  const cur = String(current ?? '').trim()
  if (!otherDocs.length && !otherVerified) return ''
  const removedNos = new Set(removedDocs.map(ocrDocNumber).filter(Boolean).map(normNo))
  if (cur && !removedNos.has(normNo(cur))) return cur
  return otherDocs.map(ocrDocNumber).find(Boolean) || ''
}

// Odebere doklad (seznam fotek se čte znovu těsně před smazáním). Soubor maže jen
// skutečný (ne marker `mindee_verified/…`) a jen když na něj neukazuje ponechaný řádek
// jiného dokladu. Selže-li úložiště, nic dalšího se nemaže (fotka dokladu nesmí zůstat
// bez záznamu). `idNumber` = nové číslo dokladu (OP / pas), `before` = profil (audit).
export async function removeCustomerDoc({ userId, kind, idNumber, before = {} }) {
  const k = DOC_KINDS[kind]
  if (!k || !userId) throw new Error('Neznámý doklad')
  const all = await loadVerificationDocs(userId)
  const own = all.filter(d => k.types.includes(d.type))
  const keptPaths = new Set(all.filter(d => !k.types.includes(d.type)).map(d => d.file_path))
  const paths = [...new Set(own.map(d => d.file_path).filter(p => p && !isMarkerPath(p) && !keptPaths.has(p)))]
  if (paths.length) {
    const { error } = await supabase.storage.from('documents').remove(paths)
    if (error) throw new Error(`Smazání fotek z úložiště selhalo: ${error.message}`)
  }
  if (own.length) {
    // .select() — DELETE bez oprávnění by jinak „proběhl“ bez chyby a bez efektu
    const { data, error } = await supabase.from('documents').delete().in('id', own.map(d => d.id)).select('id')
    if (error || (data || []).length !== own.length) {
      throw new Error(`Smazání záznamů dokladu selhalo: ${error?.message || 'záznamy se nesmazaly'}`)
    }
  }
  const patch = Object.fromEntries(k.clear.map(c => [c, null]))
  if (kind !== 'dl') patch.id_number = String(idNumber ?? '').trim() || null
  const { error } = await supabase.from('profiles').update(patch).eq('id', userId)
  if (error) {
    throw new Error(own.length
      ? `Fotky dokladu jsou smazané, ale úprava profilu selhala: ${error.message} — zkuste odebrání znovu.`
      : `Úprava profilu selhala: ${error.message}`)
  }
  try {
    const { data: { user } } = await supabase.auth.getUser()
    await supabase.from('admin_audit_log').insert({
      admin_id: user?.id, action: 'customer_document_removed', entity_type: 'profiles', entity_id: userId,
      old_data: { kind, photos: own.length, ...Object.fromEntries(Object.keys(patch).map(c => [c, before[c] ?? null])) },
      new_data: { kind, ...patch },
    })
  } catch { /* audit nesmí shodit hotové odebrání */ }
  return { patch, photos: own.length }
}
