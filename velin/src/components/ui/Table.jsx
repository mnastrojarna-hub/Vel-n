export function Table({ children, className = '' }) {
  return (
    <div className={`bg-white rounded-card shadow-card overflow-hidden ${className}`}>
      <table className="w-full border-collapse">{children}</table>
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

export function TH({ children }) {
  return (
    <th
      className="text-left text-[10px] font-extrabold uppercase tracking-wide"
      style={{ padding: '10px 14px', color: '#8aab99' }}
    >
      {children}
    </th>
  )
}

export function TD({ children, bold = false, color, mono = false }) {
  return (
    <td
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
