import { Component } from 'react'

// ─── Sdílené UI prvky pro bloky Raspberry řídicí jednotky (Samoobsluha) ─────
// Stejný vizuální jazyk jako BranchSelfService.jsx (inline styly + Tailwind utility).

// ── Typ zařízení (kiosk_devices.platform) ───────────────────────────────────
// Řídicí jednotka hlásí 'rpi' až prvním heartbeatem; hned po založení ve Velíně je platform NULL.
// Tablet (stará appka) hlásil 'android'. Proto: tablet = jen známá tabletová hodnota, vše ostatní
// (rpi / prázdné / neznámé) = řídicí jednotka (Raspberry).
const TABLET_PLATFORMS = new Set(['android', 'ios', 'flutter', 'tablet'])
const platformOf = dev => String(dev?.platform ?? '').trim().toLowerCase()
function isTabletDevice(dev) { return TABLET_PLATFORMS.has(platformOf(dev)) }
function isRpiDevice(dev) { return !!dev && !isTabletDevice(dev) }
// Popisek platformy pro UI ('' = zatím se neozvalo)
function platformLabel(dev) {
  const p = platformOf(dev)
  if (p === 'rpi') return 'Raspberry'
  if (TABLET_PLATFORMS.has(p)) return `Tablet (${p})`
  return p ? `Neznámá platforma (${p})` : ''
}

// ── Defenzivní vykreslení hodnot ze zařízení (status/report jsou JSON z jednotky — nevěřit tvaru) ──
// txt: null → '—', objekt/pole → JSON, jinak text; num: konečné číslo nebo null; arr: pole nebo []
const txt = v => (v == null ? '—' : typeof v === 'object' ? JSON.stringify(v) : String(v))
const num = v => { const n = typeof v === 'boolean' ? NaN : Number(v); return v == null || v === '' || !Number.isFinite(n) ? null : n }
const arr = v => (Array.isArray(v) ? v : [])

// Chybová hranice pro jeden blok — vadný payload ze zařízení nesmí shodit celou stránku Pobočky
class ErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { error: null } }
  static getDerivedStateFromError(error) { return { error } }
  componentDidCatch(error) { console.error('[Samoobsluha] blok selhal:', this.props.title, error) }
  render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="p-3 rounded-card text-[12px]" style={{ background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
        <div className="font-bold">{this.props.title || 'Blok'} — zobrazení selhalo (neplatná data ze zařízení).</div>
        <div className="mt-1" style={{ color: '#b45309' }}>{String(this.state.error?.message || this.state.error)}</div>
        <button type="button" onClick={() => this.setState({ error: null })}
          className="rounded-btn text-[11px] font-bold cursor-pointer border-none mt-2" style={{ padding: '4px 8px', background: '#fff', color: '#dc2626' }}>Zkusit znovu</button>
      </div>
    )
  }
}

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

export {
  RpiSection, Btn, Chip, Label, Input, Select, Checkbox, TONES, formatUptime, ageSeconds, formatAge,
  ErrorBoundary, txt, num, arr, isRpiDevice, isTabletDevice, platformLabel,
}
