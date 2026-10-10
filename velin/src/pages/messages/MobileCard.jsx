// Společné stavební prvky mobilního (≤ 1023 px) rozvržení sekce Zprávy:
// tabulky se na telefonu/tabletu vykreslují jako seznam karet. Desktop je nepoužívá.

// tabletGrid: od 768 px (tablet bez pevného menu = celá šířka) krátké karty ve dvou sloupcích,
// karta je pak sloupec a řada akcí sedí dole, takže tlačítka sousedních karet lícují. Telefon beze změny.
export function MobileCardList({ children, empty, tabletGrid = false }) {
  const items = Array.isArray(children) ? children.filter(Boolean) : children
  if (Array.isArray(items) && items.length === 0) {
    return (
      <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '24px 16px', color: '#1a2e22', fontSize: 14 }}>
        {empty || 'Nic k zobrazení'}
      </div>
    )
  }
  if (tabletGrid) return <div className="grid grid-cols-1 md:grid-cols-2 md:[&>*]:flex md:[&>*]:flex-col" style={{ gap: 10 }}>{items}</div>
  return <div className="flex flex-col" style={{ gap: 10 }}>{items}</div>
}

export function MobileCard({ children, onClick, selected = false, muted = false, style }) {
  return (
    <div
      onClick={onClick}
      className={`bg-white rounded-card shadow-card${onClick ? ' cursor-pointer' : ''}`}
      style={{
        padding: '12px 14px',
        border: selected ? '2px solid #74FB71' : '2px solid transparent',
        opacity: muted ? 0.7 : 1,
        minWidth: 0,
        ...style,
      }}
    >
      {children}
    </div>
  )
}

// Řádek karty: popisek vlevo (malý, tučný), hodnota vpravo; dlouhé hodnoty se zalamují.
export function MobileField({ label, children }) {
  return (
    <div className="flex items-start justify-between" style={{ gap: 12, fontSize: 13, color: '#1a2e22', marginTop: 4 }}>
      <span className="font-extrabold uppercase tracking-wide shrink-0" style={{ fontSize: 11, paddingTop: 2 }}>{label}</span>
      <span className="text-right" style={{ minWidth: 0, overflowWrap: 'anywhere', fontWeight: 600, color: '#0f1a14' }}>{children}</span>
    </div>
  )
}

// Řada akčních tlačítek karty — dost velká pro prst (min. 40 px).
// marginTop auto: v kartě-sloupci (tabletGrid) ji odsune ke spodnímu okraji, v běžné kartě je 0.
export function MobileActions({ children }) {
  return (
    <div style={{ marginTop: 'auto', paddingTop: 10 }}>
      <div className="flex flex-wrap" style={{ gap: 8 }} onClick={e => e.stopPropagation()}>
        {children}
      </div>
    </div>
  )
}

export function MobileActionButton({ children, onClick, color = '#1a2e22', bg = '#f1faf7', border = '#d4e8e0', disabled = false }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="rounded-btn font-extrabold cursor-pointer disabled:opacity-50"
      style={{ minHeight: 40, padding: '8px 14px', fontSize: 13, color, background: bg, border: `1px solid ${border}`, flex: '1 1 auto' }}
    >
      {children}
    </button>
  )
}

// E-mail se zalomí přednostně před „@", ne uprostřed slova (jinak overflowWrap kdekoli).
export function breakable(text) {
  if (typeof text !== 'string' || !text.includes('@')) return text
  const at = text.indexOf('@')
  return [text.slice(0, at), <wbr key="w" />, text.slice(at)]
}
