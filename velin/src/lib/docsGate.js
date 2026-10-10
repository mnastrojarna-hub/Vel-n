import { supabase } from './supabase'
import { computeDocVerification, isChildMotoRow } from './docVerification'

// Backendový verdikt brány dokladů pro přístupové kódy — RPC `get_docs_gate_checklist`
// (jádro `_docs_gate_checklist`, migrace 20261010_docs_gate_core.sql). Je AUTORITATIVNÍ:
// podle stejné funkce DB kódy vydá / zadrží (i pojistka trg_zz_door_codes_docs_gate).
// Klientský computeDocVerification je jen záloha, když RPC selže (→ null).
export async function fetchDocsGate({ bookingId = null, userId = null } = {}) {
  try {
    const { data, error } = await supabase.rpc('get_docs_gate_checklist', { p_user_id: userId || null, p_booking_id: bookingId || null })
    if (error || !data || typeof data !== 'object' || data.error) return null
    return data
  } catch { return null }
}

// Přepíše klientský výsledek computeDocVerification verdiktem backendu (názvy polí
// zůstávají stejné, ať všichni konzumenti fungují beze změny). gate = null → klient.
export function applyDocsGate(vs, gate) {
  if (!gate) return { ...vs, source: 'client' }
  if (gate.child) return { ...vs, isChildMoto: true, allOk: true, missing: [], reason: null, source: 'backend' }
  return {
    ...vs,
    idFront: !!gate.id_front, idBack: !!gate.id_back, passportOk: !!gate.passport,
    licFront: !!gate.dl_front, licBack: !!gate.dl_back,
    hasIdentity: !!gate.identity_ok, hasLicense: !!gate.license_ok,
    hasIdCard: !!(gate.id_front && gate.id_back), hasPassport: !!gate.passport,
    ageOk: !!gate.age_ok, licenseValid: !!gate.expiry_ok, hasMotoGroup: !!gate.groups_ok,
    licenseExpiryDate: gate.license_expiry ? String(gate.license_expiry).slice(0, 10) : null,
    requiredGroups: Array.isArray(gate.required_groups) ? gate.required_groups : null,
    missing: Array.isArray(gate.missing) ? gate.missing : [],
    reason: gate.reason || null,
    allOk: gate.ok === true, isChildMoto: false, source: 'backend',
  }
}

// Verdikt pro rezervaci: backend (rezervace) → záloha klient (její motorka + termín).
export async function bookingDocsVerdict(docs, profile, booking) {
  const local = computeDocVerification(docs, profile, booking?.motorcycles || null,
    { startDate: booking?.start_date, endDate: booking?.end_date })
  // Bez rezervace i bez profilu NEvolat (RPC by bez p_user_id vrátila stav přihlášeného admina)
  const gate = booking?.id ? await fetchDocsGate({ bookingId: booking.id })
    : profile?.id ? await fetchDocsGate({ userId: profile.id }) : null
  return applyDocsGate(local, gate)
}

// Panel zákazníka: verdikt pro KAŽDOU nadcházející dospělou rezervaci (dětské doklady
// nepotřebují); bez dospělé rezervace jen podle zákazníka (dnešek, bez motorky).
// → [{ booking|null, vs }], nejhorší (první neOK) vybere worstVerdict.
export async function customerDocsVerdicts(docs, profile, bookings = []) {
  const adult = (bookings || []).filter(b => !isChildMotoRow(b.motorcycles))
  if (!adult.length) return [{ booking: null, vs: await bookingDocsVerdict(docs, profile, null) }]
  return Promise.all(adult.map(async b => ({ booking: b, vs: await bookingDocsVerdict(docs, profile, b) })))
}

export function worstVerdict(list) {
  return (list || []).find(x => !x.vs.allOk)?.vs || list?.[0]?.vs || null
}
