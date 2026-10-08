import ServiceBook from './ServiceBook'

/* ═══ SERVIS TAB v detailu motorky = servisní knížka (sdílená se Servis → Servisní knížka) ═══ */
export default function ServiceTab({ motoId, logAudit }) {
  return <ServiceBook motoId={motoId} logAudit={logAudit} />
}
