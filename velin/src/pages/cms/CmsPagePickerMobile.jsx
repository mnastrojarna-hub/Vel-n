import { forwardRef } from 'react'

// Texty webu — mobil + tablet (< 1024 px): místo levého sloupce se 30+ stránkami
// je nad editorem rozbalovací výběr stránky, takže editor textů má celou šířku.
// `children` = stejný seznam stránek jako na PC (počty k doplnění, Blog, FAQ).
const CmsPagePickerMobile = forwardRef(function CmsPagePickerMobile({ icon, label, sub, open, onToggle, children }, ref) {
  return (
    <div ref={ref} style={{ scrollMarginTop: 12 }}>
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        className="w-full flex items-center gap-3 cursor-pointer text-left"
        style={{ padding: '10px 14px', minHeight: 56, borderRadius: 14, background: '#1a2e22', color: '#74FB71', border: 'none' }}
      >
        <span style={{ fontSize: 22 }}>{icon}</span>
        <span className="flex-1 min-w-0">
          <span className="block text-xs font-extrabold uppercase" style={{ color: 'rgba(255,255,255,.55)', letterSpacing: 1 }}>Stránka webu</span>
          <span className="block font-extrabold truncate" style={{ fontSize: 15 }}>{label}</span>
          {sub && <span className="block text-xs truncate" style={{ color: 'rgba(255,255,255,.55)' }}>{sub}</span>}
        </span>
        <span className="shrink-0 text-xs font-extrabold uppercase rounded-btn" style={{ padding: '8px 12px', background: '#74FB71', color: '#1a2e22' }}>
          {open ? 'Zavřít ▴' : 'Změnit ▾'}
        </span>
      </button>
      {open && (
        <div className="mt-2 p-2 md:columns-2 md:gap-4" style={{ background: '#fff', borderRadius: 14, border: '1px solid #e2ece7' }}>
          {children}
        </div>
      )}
    </div>
  )
})

export default CmsPagePickerMobile
