// Stav ověření dokladů zákazníka — jednotná logika pro celý Velín.
//
// AUTORITATIVNÍ je backend `_docs_gate_checklist` (RPC `get_docs_gate_checklist`,
// migrace 20261010_docs_gate_core.sql): DB podle něj kódy k boxu vydá / zadrží.
// Velín jeho verdikt ukazuje všude, kde o něčem rozhoduje (lib/docsGate.js →
// applyDocsGate). Tento helper je klientská KOPIE stejného pravidla — záloha při
// chybě RPC + seznamy a analytika. Při změně pravidla upravit SQL i tento soubor.
// Klient neověří existenci souboru v úložišti (backend ano) → při rozporu platí backend.
//
// Pravidlo (od 2026-10-10; dětská motorka 'N' = doklady se nevyžadují):
//   * totožnost: OP LÍC + OP RUB (dva RŮZNÉ soubory) NEBO cestovní pas (1 strana),
//   * ŘP: LÍC + RUB (dva RŮZNÉ soubory),
//   * „fotka“ = řádek documents se skutečným souborem ve složce zákazníka; marker appky
//     `mindee_verified/…` (řádek BEZ souboru) se nepočítá nikdy; strana z metadata.side,
//     záloha `_front_` / `_back_` v názvu souboru,
//   * datum narození vyplněné a k začátku pronájmu 18+,
//   * platnost ŘP (license_expiry ISO / DD.MM.YYYY; prázdná → license_verified_until)
//     vyplněná a ≥ konec pronájmu (bez rezervace ≥ dnes),
//   * skupina ŘP pokrývá motorku (motorcycles.license_groups, záloha license_required;
//     bez známé motorky stačí jakákoli skupina pro motorky / B).
//   OCR `*_verified_at` ani ručně zadané číslo dokladu fotky NENAHRAZUJÍ.
//
// computeDocVerification(docs, profile, moto, { startDate, endDate })
//   moto = řádek motorcycles { license_required, license_groups } NEBO (staré API)
//   řetězec license_required; null = motorka neznámá.

export const MOTO_LICENSE_GROUPS = ['A', 'A2', 'A1', 'AM']
// Co držená skupina pokrývá (stejná matice jako SQL _license_groups_cover)
export const LICENSE_COVERS = { A: ['A', 'A2', 'A1', 'AM'], A2: ['A2', 'A1', 'AM'], A1: ['A1', 'AM'], AM: ['AM'], B: ['B', 'AM'] }

const filled = (v) => !!(v != null && String(v).trim() !== '')
const up = (g) => String(g ?? '').trim().toUpperCase()
const pad = (n) => String(n).padStart(2, '0')

export function hasMotoLicenseGroup(licenseGroup) {
  return Array.isArray(licenseGroup) && licenseGroup.some(g => MOTO_LICENSE_GROUPS.includes(g))
}

// ── Soubory a strany ──────────────────────────────────────────────
export const isMarkerPath = (p) => String(p || '').startsWith('mindee_verified/')

export function isRealDocFile(d, userId) {
  const p = String(d?.file_path || '').trim()
  if (!p || isMarkerPath(p)) return false
  const uid = userId || d?.user_id
  return !uid || p.startsWith(`${uid}/`) || p.startsWith(`user-docs/${uid}/`)
}

export function docSide(d) {
  const s = String(d?.metadata?.side ?? d?.side ?? '').trim().toLowerCase()
  if (s) return s
  const p = String(d?.file_path || '')
  if (/_front[_.]/.test(p)) return 'front'
  if (/_back[_.]/.test(p)) return 'back'
  return null
}

const kindOf = (t) => (t === 'id_card' || t === 'id_photo') ? 'id'
  : t === 'passport' ? 'pass'
    : (t === 'drivers_license' || t === 'license_photo') ? 'dl' : null

// Strany ze skutečných souborů (parita se SQL: rub = JINÝ soubor než líc;
// samotný rub bez líce se hlásí jako „chybí líc“).
export function docSides(docs, userId) {
  const real = (Array.isArray(docs) ? docs : []).filter(d => kindOf(d?.type) && isRealDocFile(d, userId))
  const paths = (k, side) => real.filter(d => kindOf(d.type) === k && docSide(d) === side).map(d => d.file_path)
  const pair = (k) => {
    const f = paths(k, 'front'), b = paths(k, 'back')
    return { front: f.length > 0, back: f.length ? b.some(p => f.some(q => q !== p)) : b.length > 0 }
  }
  const id = pair('id'), dl = pair('dl')
  return {
    idFront: id.front, idBack: id.back, licFront: dl.front, licBack: dl.back,
    passportOk: real.some(d => kindOf(d.type) === 'pass'),
    realDocs: real,
  }
}

// Texty chybějících dokladů — STEJNÉ jako backend `missing[]`
export function identityMissing(v) {
  if (v.passportOk || (v.idFront && v.idBack)) return null
  return (!v.idFront && !v.idBack) ? 'Chybí OP (líc a rub) nebo pas' : !v.idBack ? 'Chybí rub OP' : 'Chybí líc OP'
}
export function licenseMissing(v) {
  if (v.licFront && v.licBack) return null
  return (!v.licFront && !v.licBack) ? 'Chybí ŘP (líc a rub)' : !v.licBack ? 'Chybí rub ŘP' : 'Chybí líc ŘP'
}

// ── Data ──────────────────────────────────────────────────────────
function ymd(y, m, d) {
  const dt = new Date(Date.UTC(+y, +m - 1, +d))
  if (dt.getUTCFullYear() !== +y || dt.getUTCMonth() !== +m - 1 || dt.getUTCDate() !== +d) return null
  return `${y}-${pad(m)}-${pad(d)}`
}

// Den v Praze 'YYYY-MM-DD' (bookings.start_date/end_date → den jako SQL AT TIME ZONE)
export function pragueDate(v) {
  if (!v) return null
  const s = String(v)
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s
  const d = new Date(s)
  if (isNaN(d)) return null
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit' })
    .formatToParts(d).map(x => [x.type, x.value]))
  return `${p.year}-${p.month}-${p.day}`
}

// Platnost ŘP: rozhoduje údaj zákazníka (ISO / DD.MM.YYYY), OCR jen když je prázdný
export function parseLicenseExpiry(profile) {
  const cust = String(profile?.license_expiry ?? '').trim()
  if (!cust) {
    const m = String(profile?.license_verified_until ?? '').match(/^(\d{4})-(\d{2})-(\d{2})/)
    return m ? ymd(m[1], m[2], m[3]) : null
  }
  let m = cust.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (m) return ymd(m[1], m[2], m[3])
  if (/^\d{1,2}\.\s*\d{1,2}\.\s*\d{4}$/.test(cust)) {
    m = cust.replace(/\s/g, '').match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/)
    if (m) return ymd(m[3], m[2], m[1])
  }
  return null
}

export const fmtYmd = (s) => s ? `${s.slice(8, 10)}.${s.slice(5, 7)}.${s.slice(0, 4)}` : ''

// 18+ k referenčnímu dni (29. 2. + 18 let = 28. 2. jako PostgreSQL interval)
function adultAt(dob, ref) {
  const m = String(dob || '').match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m || !ref) return false
  const y = +m[1] + 18
  let d = +m[3]
  if (+m[2] === 2 && d === 29 && !ymd(y, 2, 29)) d = 28
  return `${y}-${m[2]}-${pad(d)}` <= ref
}

// ── Skupiny ŘP ────────────────────────────────────────────────────
const asMoto = (moto) => (moto == null || moto === '') ? null
  : (typeof moto === 'string' ? { license_required: moto } : moto)

export function motoRequiredGroups(moto) {
  const m = asMoto(moto)
  if (!m) return null
  const arr = Array.isArray(m.license_groups) && m.license_groups.length ? m.license_groups : [m.license_required || 'A']
  return arr.map(up)
}

export function isChildMotoRow(moto) {
  const m = asMoto(moto)
  if (!m) return false
  return up(m.license_required) === 'N' || (Array.isArray(m.license_groups) && m.license_groups.some(g => up(g) === 'N'))
}

export function groupsCover(held, required) {
  const h = (Array.isArray(held) ? held : []).map(up)
  return (required || []).some(r => h.some(g => (LICENSE_COVERS[g] || [g]).includes(up(r))))
}

// ── Verdikt ───────────────────────────────────────────────────────
export function computeDocVerification(verificationDocs, profile, moto = null, { startDate = null, endDate = null } = {}) {
  const docs = Array.isArray(verificationDocs) ? verificationDocs : []
  const licensePhotos = docs.filter(d => d.type === 'drivers_license' || d.type === 'license_photo')
  const idCardPhotos = docs.filter(d => d.type === 'id_card' || d.type === 'id_photo')
  const passportPhotos = docs.filter(d => d.type === 'passport')

  const sides = docSides(docs, profile?.id)
  const { idFront, idBack, licFront, licBack, passportOk } = sides
  const real = sides.realDocs
  const hasLicensePhoto = real.some(d => kindOf(d.type) === 'dl')
  const hasIdPhoto = real.some(d => kindOf(d.type) === 'id')
  const hasPassportPhoto = passportOk

  const licenseNumberFilled = filled(profile?.license_number)
  const idNumberFilled = filled(profile?.id_number)
  // Proběhlé OCR (Mindee) — jen informace, doklad bez fotek NEOVĚŘÍ
  const licenseOcrVerified = filled(profile?.license_verified_at)
  const idOcrVerified = filled(profile?.id_verified_at) || filled(profile?.passport_verified_at)

  const hasLicense = licFront && licBack
  const hasIdentity = passportOk || (idFront && idBack)
  const licenseTypedOnly = licenseNumberFilled && !hasLicensePhoto && !licenseOcrVerified
  const identityTypedOnly = idNumberFilled && !hasIdPhoto && !hasPassportPhoto && !idOcrVerified
  // Číslo přečtené OCR, ale bez fotky (už NESTAČÍ — texty to musí říct)
  const licenseDataOnly = !hasLicensePhoto && licenseOcrVerified
  const identityDataOnly = !hasIdPhoto && !hasPassportPhoto && idOcrVerified

  const today = pragueDate(new Date())
  const ref = pragueDate(startDate) || today
  const end = pragueDate(endDate) || ref
  const dateOfBirth = profile?.date_of_birth ? String(profile.date_of_birth).slice(0, 10) : null
  const ageOk = adultAt(dateOfBirth, ref)
  const licenseExpiryDate = parseLicenseExpiry(profile)
  const licenseValid = !!licenseExpiryDate && licenseExpiryDate >= end

  const heldGroups = Array.isArray(profile?.license_group) ? profile.license_group : []
  const licenseGroupFilled = heldGroups.length > 0
  const requiredGroups = motoRequiredGroups(moto)
  const hasMotoGroup = groupsCover(heldGroups, requiredGroups || ['AM', 'B'])
  const isChildMoto = isChildMotoRow(moto)

  const missing = []
  if (!isChildMoto) {
    const idMiss = identityMissing(sides)
    const licMiss = licenseMissing(sides)
    if (idMiss) missing.push(idMiss)
    if (licMiss) missing.push(licMiss)
    if (!dateOfBirth) missing.push('Chybí datum narození')
    else if (!ageOk) missing.push('Zákazníkovi není 18 let')
    if (!licenseExpiryDate) missing.push('Chybí platnost ŘP')
    else if (!licenseValid) missing.push(`ŘP propadlý ${fmtYmd(licenseExpiryDate)}`)
    if (!hasMotoGroup) {
      missing.push(licenseGroupFilled ? `Skupina ŘP nestačí (potřeba ${(requiredGroups || ['A']).join('/')})` : 'Chybí skupina ŘP')
    }
  }
  // Dětská motorka: doklady se nevyžadují (parita s backendem)
  const allOk = isChildMoto || missing.length === 0

  return {
    licensePhotos, idCardPhotos, passportPhotos,
    hasLicensePhoto, hasIdPhoto, hasPassportPhoto,
    idFront, idBack, licFront, licBack, passportOk,
    licenseNumberFilled, idNumberFilled,
    licenseOcrVerified, idOcrVerified,
    licenseTypedOnly, identityTypedOnly,
    licenseDataOnly, identityDataOnly,
    hasLicense, hasIdCard: idFront && idBack, hasPassport: passportOk, hasIdentity,
    dateOfBirth, ageOk, licenseExpiryDate, licenseValid,
    licenseGroupFilled, requiredGroups, hasMotoGroup,
    missing, reason: missing.length ? missing.join('; ') : null,
    allOk, isChildMoto, source: 'client',
  }
}
