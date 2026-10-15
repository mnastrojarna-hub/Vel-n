// Sdílené prvky záložky Profil v detailu zákazníka (CustomerProfileTab + karta
// dokladů CustomerProfileDocs) — barvy, datum, nadpis sekce, pole a údaj.

export const C = {
  dark: '#1a2e22', text: '#0f1a14', muted: '#6b7280', faint: '#b6c2bb',
  g100: '#f1faf7', g200: '#d4e8e0', green: '#74FB71', gdk: '#1a8a18', red: '#dc2626',
}

export function fmtDate(d) {
  if (!d) return null
  const x = new Date(d)
  if (isNaN(x.getTime())) return null
  return x.toLocaleDateString('cs-CZ')
}

export function SectionTitle({ children, right }) {
  return (
    <div className="flex items-center justify-between mb-3.5">
      <h3 className="flex items-center gap-2 text-xs font-extrabold uppercase tracking-widest" style={{ color: C.dark }}>
        <span style={{ width: 3, height: 14, borderRadius: 2, background: C.green, display: 'inline-block' }} />
        {children}
      </h3>
      {right}
    </div>
  )
}

export function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <label className="block">
      <span className="block text-[11px] font-bold uppercase tracking-wide mb-1" style={{ color: C.muted }}>{label}</span>
      <input
        type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled}
        className="w-full rounded-lg text-sm outline-none transition focus:border-[#86e3a3]"
        style={{ padding: '8px 11px', background: disabled ? '#f7faf9' : '#fff', border: `1px solid ${C.g200}`, color: disabled ? C.muted : C.text }}
      />
    </label>
  )
}

export function Info({ label, value }) {
  return (
    <div>
      <div className="text-[11px] font-bold uppercase tracking-wide mb-0.5" style={{ color: C.muted }}>{label}</div>
      <div className="text-sm font-semibold" style={{ color: value ? C.text : C.faint }}>{value || '—'}</div>
    </div>
  )
}
