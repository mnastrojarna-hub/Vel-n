export function InfoRow({ label, value }) {
  return (
    <div className="flex items-center gap-2 mb-1">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22', minWidth: 65 }}>{label}</span>
      <span className="text-sm font-medium" style={{ color: '#0f1a14' }}>{value || '—'}</span>
    </div>
  )
}

export function SumRow({ label, value, color }) {
  if (!value) return null
  return (
    <div className="flex gap-2 py-[3px]" style={{ borderBottom: '1px solid #f1faf7', fontSize: 12 }}>
      <span className="font-bold" style={{ color: '#1a2e22', minWidth: 160, flexShrink: 0 }}>{label}</span>
      <span className="font-medium" style={{ color: color || '#0f1a14' }}>{value}</span>
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
