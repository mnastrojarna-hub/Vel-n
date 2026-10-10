/**
 * Pilulky stavu dokladů zákazníka — sdílené UI pro seznam rezervací
 * (booking/BookingsTable.jsx) a seznam zákazníků (Customers.jsx):
 *  „Č ✓/✗"   — vypsaná ČÍSLA dokladů v profilu (doklad totožnosti + ŘP)
 *  „📷 ✓/½/✗" — FOTKY dokladů (tabulka `documents`, skutečné soubory — marker
 *               `mindee_verified/…` bez souboru se nepočítá): ✓ = (OP líc + rub NEBO pas)
 *               + ŘP líc + rub (stejně jako brána kódů, lib/docVerification). OCR
 *               `*_verified_at` fotky nenahrazuje. Věk / platnost / skupinu pilulka neřeší.
 *
 * props:
 *  - profile      = řádek profiles (id_number, license_number)
 *  - scan         = { license, id, passport, licenseAny, idAny } z loadDocScans
 *  - requireLicense = false → ŘP se nevyžaduje (dětská motorka „N" v rezervacích)
 */
import { docSides } from '../lib/docVerification'

const filled = v => !!(v != null && String(v).trim() !== '')

const pill = (label, title, color, bg) => (
  <span title={title} className="inline-flex items-center text-[10px] font-extrabold rounded-btn"
    style={{ padding: '2px 6px', background: bg, color, whiteSpace: 'nowrap' }}>{label}</span>
)

export default function DocsStatusPills({ profile, scan, requireLicense = true }) {
  const p = profile || {}
  const s = scan || { license: false, id: false, passport: false }
  const idNum = filled(p.id_number)
  const licNum = filled(p.license_number)
  const numbersOk = requireLicense ? (idNum && licNum) : idNum
  const licScan = !!s.license
  const idScan = !!(s.id || s.passport)
  const scanOk = requireLicense ? (licScan && idScan) : idScan
  const scanPartial = !scanOk && (licScan || idScan || s.licenseAny || s.idAny)
  return (
    <div className="flex items-center gap-1">
      {/* Vypsaná čísla dokladů (reálně z profilu) */}
      {numbersOk
        ? pill('Č ✓', requireLicense ? 'Čísla dokladů vyplněna (doklad totožnosti + ŘP)' : 'Číslo dokladu totožnosti vyplněno (dětská motorka — ŘP netřeba)', '#166534', '#dcfce7')
        : pill('Č ✗', requireLicense ? `Chybí čísla dokladů: ${[!idNum && 'doklad totožnosti', !licNum && 'ŘP'].filter(Boolean).join(' + ')}` : 'Chybí číslo dokladu totožnosti', '#b91c1c', '#fee2e2')}
      {/* Sken dokladů (fotka nebo OCR ověření) */}
      {scanOk
        ? pill('📷 ✓', 'Fotky dokladů kompletní (OP líc + rub nebo pas, ŘP líc + rub)', '#166534', '#dcfce7')
        : scanPartial
          ? pill('📷 ½', `Fotky neúplné — chybí ${scanMissing(s, requireLicense)}`, '#b45309', '#fef3c7')
          : pill('📷 ✗', 'Doklady nenafocené', '#b91c1c', '#fee2e2')}
    </div>
  )
}

// Co z fotek chybí (krátce, pro title / dotykovou pilulku)
export function scanMissing(s, requireLicense = true) {
  const out = []
  if (!(s.id || s.passport)) out.push(s.idFront ? 'rub OP' : s.idBack ? 'líc OP' : 'OP/pas')
  if (requireLicense && !s.license) out.push(s.licFront ? 'rub ŘP' : s.licBack ? 'líc ŘP' : 'ŘP')
  return out.join(' + ')
}

/** Dávkové načtení fotek dokladů pro seznam uživatelů → Map<user_id, {license,id,passport,…}>.
 *  Jeden dotaz s `in` (vzor z Bookings.jsx); strany a skutečné soubory přes docSides (stejné
 *  pravidlo jako brána kódů): license = ŘP líc + rub, id = OP líc + rub, passport = pas. */
export async function loadDocScans(supabase, userIds) {
  const ids = [...new Set((userIds || []).filter(Boolean))]
  if (!ids.length) return {}
  const { data: docs } = await supabase.from('documents')
    .select('user_id, type, file_path, metadata')
    .in('user_id', ids)
    .in('type', ['drivers_license', 'license_photo', 'id_card', 'id_photo', 'passport'])
  const byUser = {}
  ;(docs || []).forEach(d => { (byUser[d.user_id] = byUser[d.user_id] || []).push(d) })
  const smap = {}
  Object.entries(byUser).forEach(([uid, list]) => {
    const v = docSides(list, uid)
    smap[uid] = {
      license: v.licFront && v.licBack, id: v.idFront && v.idBack, passport: v.passportOk,
      licFront: v.licFront, licBack: v.licBack, idFront: v.idFront, idBack: v.idBack,
      licenseAny: v.licFront || v.licBack, idAny: v.idFront || v.idBack,
    }
  })
  return smap
}
