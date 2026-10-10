// stack = na telefonu (< 768 px) se řádky zobrazí jako karty „popisek: hodnota“
// (CSS .mg-stack v index.css, popisky doplňuje lib/stackTables.js z hlavičky);
// stack="tablet" = karty i na tabletu (< 1024 px) pro hodně široké tabulky.
// Desktop (≥ 1024 px) vykresluje tabulku beze změny.
export function Table({ children, className = '', stack = false }) {
  const tab = stack === 'tablet'
  return (
    <div className={`bg-white rounded-card shadow-card overflow-x-auto ${stack ? 'mg-stack-wrap ' : ''}${tab ? 'mg-stack-wrap-tab ' : ''}${className}`}>
      <table className={`w-full border-collapse${stack ? ' mg-stack' : ''}${tab ? ' mg-stack-tab' : ''}`}>{children}</table>
    </div>
  )
}

export function TRow({ children, header = false }) {
  return (
    <tr
      style={{
        borderBottom: '1px solid #d4e8e0',
        background: header ? '#f1faf7' : 'transparent',
      }}
    >
      {children}
    </tr>
  )
}

export function TH({ children, className = '' }) {
  return (
    <th
      className={`text-left text-sm font-extrabold uppercase tracking-wide${className ? ' ' + className : ''}`}
      style={{ padding: '10px 14px', color: '#1a2e22' }}
    >
      {children}
    </th>
  )
}

// className / label = jen pro kartové zobrazení na telefonu (mg-stack-full, mg-hide-phone, vlastní popisek).
export function TD({ children, bold = false, color, mono = false, className, label }) {
  return (
    <td
      className={className}
      data-label={label}
      style={{
        padding: '10px 14px',
        fontSize: 13,
        fontWeight: bold ? 700 : 500,
        color: color || '#0f1a14',
        fontFamily: mono ? 'monospace' : 'inherit',
      }}
    >
      {children}
    </td>
  )
}
