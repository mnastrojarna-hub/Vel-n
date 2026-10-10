// Stav dokladů zákazníka pro dotykové karty (mobil/tablet < 1024 px) — seznam rezervací
// (BookingsListMobile) a Odjezdy a návraty (PickupsReturns). Logika je stejná jako
// components/DocsStatusPills.jsx (desktop beze změny), ale:
//  - písmo 11 px místo 10 px (jako ostatní štítky na kartě),
//  - CO chybí je přímo v pilulce („Č ✗ chybí ŘP", „📷 ½ chybí OP/pas") — title/hover
//    na dotykovém displeji nejde přečíst.
const filled = v => !!(v != null && String(v).trim() !== '')
const ID = 'OP/pas'

const pill = (label, title, color, bg) => (
  <span title={title} className="inline-flex items-center text-[11px] font-extrabold rounded-btn"
    style={{ padding: '3px 7px', background: bg, color, whiteSpace: 'nowrap', lineHeight: 1.25 }}>{label}</span>
)

export default function DocsPillsTouch({ profile, scan, requireLicense = true }) {
  const p = profile || {}
  const s = scan || { license: false, id: false, passport: false }
  const idNum = filled(p.id_number)
  const licNum = filled(p.license_number)
  const numbersOk = requireLicense ? (idNum && licNum) : idNum
  const licScan = s.license || filled(p.license_verified_at)
  const idScan = s.id || s.passport || filled(p.id_verified_at) || filled(p.passport_verified_at)
  const scanOk = requireLicense ? (licScan && idScan) : idScan
  const scanPartial = !scanOk && (licScan || idScan)
  // ŘP se u dětské motorky (N) nevyžaduje → v textu „chybí" ho neuvádíme
  const missing = (idOk, licOk) => [!idOk && ID, requireLicense && !licOk && 'ŘP'].filter(Boolean).join(' + ')
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      {numbersOk
        ? pill('Č ✓', requireLicense ? 'Čísla dokladů vyplněna (doklad totožnosti + ŘP)' : 'Číslo dokladu totožnosti vyplněno (dětská motorka — ŘP netřeba)', '#166534', '#dcfce7')
        : pill(`Č ✗ chybí ${missing(idNum, licNum)}`, 'Chybí čísla dokladů v profilu zákazníka', '#b91c1c', '#fee2e2')}
      {scanOk
        ? pill('📷 ✓', 'Doklady naskenované (fotka nebo OCR sken)', '#166534', '#dcfce7')
        : pill(`📷 ${scanPartial ? '½' : '✗'} chybí ${missing(idScan, licScan)}`, scanPartial ? 'Naskenován jen jeden doklad' : 'Doklady nenaskenované',
          scanPartial ? '#b45309' : '#b91c1c', scanPartial ? '#fef3c7' : '#fee2e2')}
    </span>
  )
}
