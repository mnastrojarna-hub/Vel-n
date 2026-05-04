export function InfoRow({ label, value, accent }) {
  const v = value === 0 || value === '0' ? value : (value || '—')
  return (
    <div className="flex items-baseline gap-3 py-[3px]" style={{ borderBottom: '1px solid #e8f1ec' }}>
      <span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#4a5a52', minWidth: 95, flexShrink: 0 }}>{label}</span>
      <span className="text-sm font-semibold" style={{ color: accent || '#0f1a14' }}>{v}</span>
    </div>
  )
}

export function SumRow({ label, value, color, strong }) {
  if (value === undefined || value === null || value === '') return null
  return (
    <div className="flex gap-3 py-[4px]" style={{ borderBottom: '1px solid #eef4f0', fontSize: 13 }}>
      <span className="font-bold" style={{ color: '#4a5a52', minWidth: 165, flexShrink: 0 }}>{label}</span>
      <span className={strong ? 'font-extrabold' : 'font-semibold'} style={{ color: color || '#0f1a14' }}>{value}</span>
    </div>
  )
}

export function SectionHeading({ children, color = '#1a2e22', className = '' }) {
  return (
    <div className={`text-sm font-extrabold uppercase tracking-wider mt-4 mb-2 pb-1 ${className}`}
      style={{ color, borderBottom: `2px solid ${color}22` }}>
      {children}
    </div>
  )
}

export function SmallActionBtn({ children, onClick, color, bg }) {
  return (
    <button onClick={onClick} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
      style={{ padding: '3px 8px', background: bg, color, border: 'none' }}>{children}</button>
  )
}

export function FieldInput({ label, type = 'text', value, onChange }) {
  let displayValue = value || ''
  if (type === 'date' && value && value.length > 10) {
    displayValue = new Date(value).toLocaleDateString('sv-SE')
  }
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={displayValue} onChange={e => onChange(e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
    </div>
  )
}
