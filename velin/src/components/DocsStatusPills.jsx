/**
 * Pilulky stavu dokladů zákazníka — sdílené UI pro seznam rezervací
 * (booking/BookingsTable.jsx) a seznam zákazníků (Customers.jsx):
 *  „Č ✓/✗"   — vypsaná ČÍSLA dokladů v profilu (doklad totožnosti + ŘP)
 *  „📷 ✓/½/✗" — SKEN dokladů: nahraná fotka (tabulka `documents`, i bez
 *               Mindee ověření) NEBO reálný OCR sken (`*_verified_at` v profilu)
 *
 * props:
 *  - profile      = řádek profiles (id_number, license_number, *_verified_at)
 *  - scan         = { license, id, passport } z dávkového dotazu na `documents`
 *  - requireLicense = false → ŘP se nevyžaduje (dětská motorka „N" v rezervacích)
 */
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
  const licScan = s.license || filled(p.license_verified_at)
  const idScan = s.id || s.passport || filled(p.id_verified_at) || filled(p.passport_verified_at)
  const scanOk = requireLicense ? (licScan && idScan) : idScan
  const scanPartial = !scanOk && (licScan || idScan)
  return (
    <div className="flex items-center gap-1">
      {/* Vypsaná čísla dokladů (reálně z profilu) */}
      {numbersOk
        ? pill('Č ✓', requireLicense ? 'Čísla dokladů vyplněna (doklad totožnosti + ŘP)' : 'Číslo dokladu totožnosti vyplněno (dětská motorka — ŘP netřeba)', '#166534', '#dcfce7')
        : pill('Č ✗', requireLicense ? `Chybí čísla dokladů: ${[!idNum && 'doklad totožnosti', !licNum && 'ŘP'].filter(Boolean).join(' + ')}` : 'Chybí číslo dokladu totožnosti', '#b91c1c', '#fee2e2')}
      {/* Sken dokladů (fotka nebo OCR ověření) */}
      {scanOk
        ? pill('📷 ✓', 'Doklady naskenované (fotka nebo OCR sken)', '#166534', '#dcfce7')
        : scanPartial
          ? pill('📷 ½', `Naskenován jen ${licScan ? 'ŘP' : 'doklad totožnosti'} — druhý chybí`, '#b45309', '#fef3c7')
          : pill('📷 ✗', 'Doklady nenaskenované', '#b91c1c', '#fee2e2')}
    </div>
  )
}

/** Dávkové načtení skenů dokladů pro seznam uživatelů → Map<user_id, {license,id,passport}>.
 *  Jeden dotaz s `in` (vzor z Bookings.jsx); sken = jakákoli nahraná fotka bez ohledu na OCR. */
export async function loadDocScans(supabase, userIds) {
  const ids = [...new Set((userIds || []).filter(Boolean))]
  if (!ids.length) return {}
  const { data: docs } = await supabase.from('documents')
    .select('user_id, type')
    .in('user_id', ids)
    .in('type', ['drivers_license', 'license_photo', 'id_card', 'id_photo', 'passport'])
  const smap = {}
  ;(docs || []).forEach(d => {
    const cur = smap[d.user_id] || { license: false, id: false, passport: false }
    if (d.type === 'drivers_license' || d.type === 'license_photo') cur.license = true
    else if (d.type === 'id_card' || d.type === 'id_photo') cur.id = true
    else if (d.type === 'passport') cur.passport = true
    smap[d.user_id] = cur
  })
  return smap
}
