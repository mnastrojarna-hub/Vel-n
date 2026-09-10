// ─── Sdílené UI prvky pro bloky Raspberry řídicí jednotky (Samoobsluha) ─────
// Stejný vizuální jazyk jako BranchSelfService.jsx (inline styly + Tailwind utility).

const TONES = {
  dark: { background: '#1a2e22', color: '#74FB71' },
  blue: { background: '#dbeafe', color: '#2563eb' },
  green: { background: '#dcfce7', color: '#1a8a18' },
  red: { background: '#fee2e2', color: '#dc2626' },
  amber: { background: '#fef3c7', color: '#b45309' },
  gray: { background: '#eef6f2', color: '#1a2e22' },
}

function RpiSection({ title, hint, children, action }) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2 gap-2 flex-wrap">
        <div>
          <div className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{title}</div>
          {hint && <div className="text-[12px]" style={{ color: '#6b8c7a' }}>{hint}</div>}
        </div>
        {action}
      </div>
      {children}
    </div>
  )
}

function Btn({ children, tone = 'gray', onClick, disabled, title, small, style }) {
  const t = TONES[tone] || TONES.gray
  return (
    <button type="button" onClick={onClick} disabled={disabled} title={title}
      className={`rounded-btn font-bold cursor-pointer border-none ${small ? 'text-[11px]' : 'text-[12px]'}`}
      style={{ padding: small ? '4px 8px' : '5px 10px', ...t, opacity: disabled ? 0.45 : 1, ...style }}>
      {children}
    </button>
  )
}

function Chip({ children, tone = 'gray', title }) {
  const t = TONES[tone] || TONES.gray
  return (
    <span title={title} className="inline-block rounded-btn text-[9px] font-extrabold uppercase"
      style={{ padding: '2px 6px', ...t, whiteSpace: 'nowrap' }}>
      {children}
    </span>
  )
}

function Label({ children }) {
  return <span className="text-[11px] font-bold" style={{ color: '#6b8c7a' }}>{children}</span>
}

const inputStyle = (invalid, warn) => ({
  padding: '6px 8px',
  background: invalid ? '#fee2e2' : '#f1faf7',
  border: `1px solid ${invalid ? '#dc2626' : warn ? '#f59e0b' : '#d4e8e0'}`,
  color: '#0f1a14',
})

// Textové / číselné pole s popiskem (řízené, hodnota se drží v rodiči)
function Input({ label, value, onChange, type = 'text', width, placeholder, invalid, warn, title, min, step }) {
  return (
    <label className="flex flex-col gap-0.5" style={{ width }} title={title}>
      {label && <Label>{label}</Label>}
      <input type={type} value={value ?? ''} placeholder={placeholder} min={min} step={step}
        onChange={e => onChange(e.target.value)}
        className="rounded-btn text-sm outline-none" style={inputStyle(invalid, warn)} />
    </label>
  )
}

function Select({ label, value, onChange, options, width, invalid, warn, title }) {
  return (
    <label className="flex flex-col gap-0.5" style={{ width }} title={title}>
      {label && <Label>{label}</Label>}
      <select value={value ?? ''} onChange={e => onChange(e.target.value)}
        className="rounded-btn text-sm outline-none" style={{ ...inputStyle(invalid, warn), background: invalid ? '#fee2e2' : '#fff' }}>
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </label>
  )
}

function Checkbox({ label, checked, onChange, title }) {
  return (
    <label className="flex items-center gap-1.5 text-sm cursor-pointer" style={{ color: '#1a2e22' }} title={title}>
      <input type="checkbox" checked={!!checked} onChange={e => onChange(e.target.checked)} />
      <span className="text-[12px] font-bold">{label}</span>
    </label>
  )
}

// Formát doby běhu (sekundy → „2 d 3 h 5 min“)
function formatUptime(s) {
  const n = Number(s)
  if (!Number.isFinite(n) || n < 0) return '—'
  const d = Math.floor(n / 86400), h = Math.floor((n % 86400) / 3600), m = Math.floor((n % 3600) / 60)
  if (d > 0) return `${d} d ${h} h`
  if (h > 0) return `${h} h ${m} min`
  return `${m} min`
}

// Stáří časové značky v sekundách (null = neznámé)
function ageSeconds(ts, now) {
  if (!ts) return null
  const t = new Date(ts).getTime()
  if (!Number.isFinite(t)) return null
  return Math.max(0, Math.round((now - t) / 1000))
}

function formatAge(sec) {
  if (sec == null) return 'nikdy'
  if (sec < 60) return `před ${sec} s`
  if (sec < 3600) return `před ${Math.round(sec / 60)} min`
  return `před ${Math.round(sec / 3600)} h`
}

export { RpiSection, Btn, Chip, Label, Input, Select, Checkbox, TONES, formatUptime, ageSeconds, formatAge }
