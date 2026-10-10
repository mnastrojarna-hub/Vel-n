import { useIsMobile } from '../../hooks/useIsMobile'
import { sanitizeHtml } from '../../lib/sanitize'

// Telefon/tablet (< 1024 px): sanitizeHtml (DOMPurify bez WHOLE_DOCUMENT) zahodí <head><style>
// šablony faktury i s jejími @media (max-width:600px) pravidly → 2sloupcové tabulky
// (Dodavatel | Odběratel, Fakturační údaje | Platba) zůstaly v desktop rozvržení a sloupec
// PLATBA přečníval z úzkého boxu náhledu. Zrcadlíme ta pravidla z lib/invoiceTemplate.js
// jako container query nad boxem náhledu (≤ 600 px = telefon na výšku) — stejně jako
// dobropis v iframe. Při úpravě mobilních pravidel šablony uprav i tento blok.
// Desktop (≥ 1024 px) vykresluje beze změny: žádný <style>, žádný container.
const MOBILE_CSS = `
@container invprev (max-width: 600px) {
  [data-inv-preview] .inv-2col{border-spacing:0 10px !important}
  [data-inv-preview] .inv-2col > tbody > tr > td,
  [data-inv-preview] .inv-2col > tbody > tr{display:block !important;width:100% !important;box-sizing:border-box}
  [data-inv-preview] .inv-header-grid > tbody > tr > td,
  [data-inv-preview] .inv-header-grid > tbody > tr{display:block !important;width:100% !important;text-align:left !important}
  [data-inv-preview] .inv-header-grid td[style*="text-align:right"]{text-align:left !important;margin-top:10px}
  [data-inv-preview] .inv-summary-row > tbody > tr > td:first-child{display:none !important}
  [data-inv-preview] .inv-summary-row > tbody > tr > td{display:block !important;width:100% !important}
  [data-inv-preview] .inv-items-table th,
  [data-inv-preview] .inv-items-table td{font-size:11px !important;padding:8px 8px !important}
  [data-inv-preview] .inv-footer-grid > tbody > tr > td,
  [data-inv-preview] .inv-footer-grid > tbody > tr{display:block !important;width:100% !important;padding:0 0 10px !important}
}`

export default function InvoicePreviewHtml({ html }) {
  const isMobile = useIsMobile()
  return (
    <>
      {isMobile && <style>{MOBILE_CSS}</style>}
      <div className="rounded-card" data-inv-preview={isMobile ? '' : undefined}
        style={{ border: '1px solid #d4e8e0', maxHeight: 420, overflow: 'auto', background: '#fff', ...(isMobile ? { container: 'invprev / inline-size' } : null) }}
        dangerouslySetInnerHTML={{ __html: sanitizeHtml(html) }} />
    </>
  )
}
