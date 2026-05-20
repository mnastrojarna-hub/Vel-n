// Stav ověření dokladů zákazníka — jednotná logika pro celý Velín.
//
// POZOR: Musí odpovídat backendu (`auto_generate_door_codes`, `release_my_door_codes`,
// `check_booking_docs_status`, `get_web_booking_confirmation.docs_status`).
//
// Doklad je OVĚŘENÝ (kódy k boxu lze uvolnit), pokud platí ALESPOŇ JEDNA z možností:
//   1) je nahraná fotka (documents.type id_card/id_photo/passport, resp. drivers_license/license_photo)
//   2) proběhl reálný Mindee OCR sken → profiles.{id,license,passport}_verified_at je vyplněné
//
// POUHÉ ručně zadané číslo dokladu (profiles.id_number / license_number) BEZ fotky i BEZ
// verified_at se NEPOČÍTÁ za ověřené — typicky když zákazník (nebo test) jen vyplní čísla
// ve formuláři a doklad nikdy nenaskenuje. Web `_rezPersistDocs` ukládá číslo bez verified_at,
// `_rezApplyOcrResult` (skutečné OCR) verified_at nastaví — to je rozhodující rozdíl.
//
// Volitelný `motoLicenseRequired` (z `motorcycles.license_required`):
//   - 'N' = dětská motorka → ŘP se vůbec nepožaduje, allOk počítá jen s totožností
//     (backend trigger `auto_generate_door_codes` u dětských kódy uvolní bez ŘP)
//   - jinak (A/A2/A1/AM/B...) klasická logika ŘP + OP/pas + skupina A/A2/A1/AM

export const MOTO_LICENSE_GROUPS = ['A', 'A2', 'A1', 'AM']

const filled = (v) => !!(v != null && String(v).trim() !== '')

export function hasMotoLicenseGroup(licenseGroup) {
  return Array.isArray(licenseGroup) && licenseGroup.some(g => MOTO_LICENSE_GROUPS.includes(g))
}

export function computeDocVerification(verificationDocs, profile, motoLicenseRequired) {
  const docs = Array.isArray(verificationDocs) ? verificationDocs : []
  const licensePhotos = docs.filter(d => d.type === 'drivers_license' || d.type === 'license_photo')
  const idCardPhotos = docs.filter(d => d.type === 'id_card' || d.type === 'id_photo')
  const passportPhotos = docs.filter(d => d.type === 'passport')

  const licenseNumberFilled = filled(profile?.license_number)
  const idNumberFilled = filled(profile?.id_number)

  const hasLicensePhoto = licensePhotos.length > 0
  const hasIdPhoto = idCardPhotos.length > 0
  const hasPassportPhoto = passportPhotos.length > 0

  // Skutečné OCR ověření = timestamp z Mindee scanu (web/app). Ručně psané číslo ho nemá.
  const licenseOcrVerified = filled(profile?.license_verified_at)
  const idOcrVerified = filled(profile?.id_verified_at) || filled(profile?.passport_verified_at)

  // ŘP / OP ověřen fotkou NEBO reálným OCR (verified_at). Holé číslo nestačí.
  const hasLicense = hasLicensePhoto || licenseOcrVerified
  const hasIdentity = hasIdPhoto || hasPassportPhoto || idOcrVerified

  // Číslo zadané jen ručně ve formuláři — bez fotky i bez OCR ⇒ NEOVĚŘENO
  const licenseTypedOnly = licenseNumberFilled && !hasLicensePhoto && !licenseOcrVerified
  const identityTypedOnly = idNumberFilled && !hasIdPhoto && !hasPassportPhoto && !idOcrVerified

  // Doklad ověřen reálným OCR, ale bez nahrané fotky — pro hlášku „fotka je volitelná"
  const licenseDataOnly = !hasLicensePhoto && licenseOcrVerified
  const identityDataOnly = !hasIdPhoto && !hasPassportPhoto && idOcrVerified

  const licenseValid = profile?.license_expiry ? new Date(profile.license_expiry) > new Date() : false
  const licenseGroupFilled = Array.isArray(profile?.license_group) && profile.license_group.length > 0
  const hasMotoGroup = licenseGroupFilled && hasMotoLicenseGroup(profile?.license_group)

  const isChildMoto = String(motoLicenseRequired || '').toUpperCase() === 'N'

  // U dětské motorky stačí ověřená totožnost — žádný ŘP, žádná skupina
  const allOk = isChildMoto
    ? hasIdentity
    : (hasLicense && hasIdentity && licenseValid && licenseGroupFilled && hasMotoGroup)

  return {
    licensePhotos, idCardPhotos, passportPhotos,
    hasLicensePhoto, hasIdPhoto, hasPassportPhoto,
    licenseNumberFilled, idNumberFilled,
    licenseOcrVerified, idOcrVerified,
    licenseTypedOnly, identityTypedOnly,
    licenseDataOnly, identityDataOnly,
    hasLicense, hasIdCard: hasIdPhoto, hasPassport: hasPassportPhoto, hasIdentity,
    licenseValid, licenseGroupFilled, hasMotoGroup, allOk,
    isChildMoto,
  }
}
