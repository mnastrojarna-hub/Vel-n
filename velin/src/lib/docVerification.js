// Stav ověření dokladů zákazníka — jednotná logika pro celý Velín.
//
// POZOR: Musí odpovídat backendu (`auto_generate_door_codes`, `release_my_door_codes`,
// `check_booking_docs_status`, `get_web_booking_confirmation.docs_status`). Doklad se
// počítá za ověřený, pokud platí ALESPOŇ JEDNA z možností:
//   1) je nahraná fotka (documents.type id_card/id_photo/passport, resp. drivers_license/license_photo)
//   2) je v profilu uložené číslo dokladu z Mindee OCR (profiles.id_number, resp. profiles.license_number)
// Web rezervace ukládá id_number/license_number do profilu i bez nahrání fotek, takže
// zákazník už doklady znovu nahrávat nemusí — Velín to musí ukazovat stejně.

export const MOTO_LICENSE_GROUPS = ['A', 'A2', 'A1', 'AM']

const filled = (v) => !!(v != null && String(v).trim() !== '')

export function hasMotoLicenseGroup(licenseGroup) {
  return Array.isArray(licenseGroup) && licenseGroup.some(g => MOTO_LICENSE_GROUPS.includes(g))
}

export function computeDocVerification(verificationDocs, profile) {
  const docs = Array.isArray(verificationDocs) ? verificationDocs : []
  const licensePhotos = docs.filter(d => d.type === 'drivers_license' || d.type === 'license_photo')
  const idCardPhotos = docs.filter(d => d.type === 'id_card' || d.type === 'id_photo')
  const passportPhotos = docs.filter(d => d.type === 'passport')

  const licenseNumberFilled = filled(profile?.license_number)
  const idNumberFilled = filled(profile?.id_number)

  const hasLicensePhoto = licensePhotos.length > 0
  const hasIdPhoto = idCardPhotos.length > 0
  const hasPassportPhoto = passportPhotos.length > 0

  // ŘP / OP ověřen fotkou NEBO uloženým číslem z OCR
  const hasLicense = hasLicensePhoto || licenseNumberFilled
  const hasIdentity = hasIdPhoto || hasPassportPhoto || idNumberFilled

  // Doklad ověřen jen přes OCR data (bez nahrané fotky)
  const licenseDataOnly = !hasLicensePhoto && licenseNumberFilled
  const identityDataOnly = !hasIdPhoto && !hasPassportPhoto && idNumberFilled

  const licenseValid = profile?.license_expiry ? new Date(profile.license_expiry) > new Date() : false
  const licenseGroupFilled = Array.isArray(profile?.license_group) && profile.license_group.length > 0
  const hasMotoGroup = licenseGroupFilled && hasMotoLicenseGroup(profile?.license_group)

  const allOk = hasLicense && hasIdentity && licenseValid && licenseGroupFilled && hasMotoGroup

  return {
    licensePhotos, idCardPhotos, passportPhotos,
    hasLicensePhoto, hasIdPhoto, hasPassportPhoto,
    licenseNumberFilled, idNumberFilled,
    licenseDataOnly, identityDataOnly,
    hasLicense, hasIdCard: hasIdPhoto, hasPassport: hasPassportPhoto, hasIdentity,
    licenseValid, licenseGroupFilled, hasMotoGroup, allOk,
  }
}
