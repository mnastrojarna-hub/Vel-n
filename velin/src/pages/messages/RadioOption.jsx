// touch = rozvržení pro telefon/tablet: vyšší cíl pro prst a roztažení do šířky řádku (desktop beze změny)
export default function RadioOption({ checked, onChange, label, disabled = false, touch = false }) {
  return (
    <label
      className="flex items-center gap-2 cursor-pointer rounded-btn"
      style={{
        padding: '8px 14px',
        background: checked ? '#e8fee7' : '#f1faf7',
        border: checked ? '1px solid #74FB71' : '1px solid #d4e8e0',
        opacity: disabled ? 0.5 : 1,
        pointerEvents: disabled ? 'none' : 'auto',
        ...(touch ? { minHeight: 44, padding: '10px 14px', flex: '1 1 auto', justifyContent: 'center' } : null),
      }}
    >
      <input type="radio" checked={checked} onChange={onChange} disabled={disabled} className="accent-[#1a8a18]" style={touch ? { width: 18, height: 18, flexShrink: 0 } : { width: 14, height: 14 }} />
      <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{label}</span>
    </label>
  )
}
