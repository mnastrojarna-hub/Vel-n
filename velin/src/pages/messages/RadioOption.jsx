export default function RadioOption({ checked, onChange, label, disabled = false }) {
  return (
    <label
      className="flex items-center gap-2 cursor-pointer rounded-btn"
      style={{
        padding: '8px 14px',
        background: checked ? '#e8fee7' : '#f1faf7',
        border: checked ? '1px solid #74FB71' : '1px solid #d4e8e0',
        opacity: disabled ? 0.5 : 1,
        pointerEvents: disabled ? 'none' : 'auto',
      }}
    >
      <input type="radio" checked={checked} onChange={onChange} disabled={disabled} className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
      <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>{label}</span>
    </label>
  )
}
