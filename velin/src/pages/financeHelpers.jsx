import Card from '../components/ui/Card'

export function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '\u2014'}</div>
    </div>
  )
}

export function SummaryCard({ label, value, color, count }) {
  return (
    <Card>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
        {label}
        {count != null && count > 0 && (
          <span className="ml-2 inline-flex items-center justify-center rounded-full text-xs font-extrabold"
            style={{ background: color + '20', color, minWidth: 22, height: 22, padding: '0 6px' }}>{count}</span>
        )}
      </div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

export function MiniStat({ label, value, color }) {
  return (
    <div className="p-2 rounded-lg" style={{ background: '#f1faf7' }}>
      <div className="text-[9px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-sm font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

export function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}

export function TypeBadge({ type }) {
  const isRev = type === 'revenue'
  return (
    <span className="inline-block rounded-btn text-sm font-extrabold tracking-wide uppercase"
      style={{ padding: '4px 10px', background: isRev ? '#dcfce7' : '#fee2e2', color: isRev ? '#1a8a18' : '#dc2626' }}>
      {isRev ? 'Prijem' : 'Vydaj'}
    </span>
  )
}
