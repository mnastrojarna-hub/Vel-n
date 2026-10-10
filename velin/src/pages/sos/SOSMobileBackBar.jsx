// Telefon/tablet (< 1024 px): detail incidentu zabírá celou šířku místo seznamu —
// nahoře přilepená lišta s výrazným „Zpět“ (vrací na seznam na původní pozici).
// Na desktopu se nevykresluje (lg:hidden), rozvržení vedle sebe zůstává beze změny.
// Záporné top = odsazení hlavního scroll kontejneru Layoutu (p-3 / md:p-6), aby lišta lícovala s horní hranou.
const BACK_BTN = {
  height: 44,
  padding: '0 16px 0 10px',
  borderRadius: 999,
  background: '#fff',
  border: '1px solid #d4e8e0',
  color: '#1a2e22',
  fontSize: 15,
  fontWeight: 800,
  cursor: 'pointer',
  display: 'inline-flex',
  alignItems: 'center',
  gap: 4,
  boxShadow: '0 2px 10px rgba(15,26,20,.08)',
}

export default function SOSMobileBackBar({ onBack, title }) {
  return (
    <div className="lg:hidden sticky -top-3 md:-top-6 z-10 flex items-center gap-2 mb-3 -mt-1 py-2" style={{ background: '#dff0ec' }}>
      <button type="button" aria-label="Zpět na seznam incidentů" onClick={onBack} style={BACK_BTN}>
        <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
          <path d="M15 18l-6-6 6-6" />
        </svg>
        Zpět
      </button>
      {title && (
        <span className="truncate text-sm font-extrabold" style={{ color: '#0f1a14', minWidth: 0 }}>{title}</span>
      )}
    </div>
  )
}
