// „Uložit změny“ v profilu zákazníka (CustomerDetail): posílají se JEN sloupce, které
// obsluha v profilu změnila proti stavu z načtení / posledního uložení. Profil se načte
// jednou při otevření zákazníka; mezitím ho mění OCR dokladů (nahrání v záložce
// Dokumenty, appka, web) i sám zákazník — plné uložení by novější hodnoty přepsalo
// starými (např. čísla a platnosti právě nahraných dokladů).
export const PROFILE_SAVE_FIELDS = [
  'full_name', 'phone', 'street', 'city', 'zip', 'country',
  'ico', 'dic', 'company_name', 'company_address',
  'date_of_birth', 'license_group', 'marketing_consent',
  'id_number', 'license_number', 'license_expiry',
  'id_verified_until', 'passport_verified_until',
  'reliability_score', 'is_blocked', 'blocked_at', 'blocked_reason',
  'consent_gdpr', 'consent_vop', 'consent_email', 'consent_sms',
  'consent_push', 'consent_data_processing', 'consent_photo',
  'consent_whatsapp', 'consent_contract',
]

// Sloupce typu DATE — smazané datum (prázdný vstup) = NULL (DB by '' odmítla)
const DATE_FIELDS = new Set(['date_of_birth', 'id_verified_until', 'passport_verified_until'])

const blank = (v) => (v === '' || v === undefined ? null : v)

export function profileChanges(current, original) {
  const out = {}
  for (const k of PROFILE_SAVE_FIELDS) {
    const v = current?.[k]
    if (JSON.stringify(blank(v)) === JSON.stringify(blank(original?.[k]))) continue
    out[k] = DATE_FIELDS.has(k) ? blank(v) : v
  }
  return out
}
