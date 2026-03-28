import { UNAVAILABLE_REASONS } from './motoActionConstants'

export function StatusBtn({ color, bg, onClick, disabled, title, desc }) {
  return (
    <button onClick={onClick} disabled={disabled} className="p-3 rounded-lg text-left cursor-pointer"
      style={{ background: bg, border: `2px solid ${color}`, opacity: disabled ? 0.5 : 1 }}>
      <div className="text-sm font-extrabold mb-1" style={{ color }}>{title}</div>
      <div className="text-sm" style={{ color: '#1a2e22' }}>{desc}</div>
    </button>
  )
}

export function UnavailableReasonPicker({ reason, setReason, customReason, setCustomReason, unavailableUntil, setUnavailableUntil }) {
  return (
    <div className="mt-4">
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Důvod dočasného vyřazení</label>
      <div className="flex flex-wrap gap-2">
        {UNAVAILABLE_REASONS.map(r => (
          <button key={r.value} onClick={() => setReason(r.value)} className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '6px 12px', border: 'none', background: reason === r.value ? '#7c3aed' : '#f1faf7', color: reason === r.value ? '#fff' : '#1a2e22' }}>
            {r.label}
          </button>
        ))}
      </div>
      {reason === 'other' && <input value={customReason} onChange={e => setCustomReason(e.target.value)} placeholder="Zadejte důvod…"
        className="w-full mt-2 rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />}
      {reason && (
        <div className="mt-3">
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Nedostupná do</label>
          <input type="datetime-local" value={unavailableUntil} onChange={e => setUnavailableUntil(e.target.value)}
            min={new Date().toISOString().slice(0, 16)} className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#ede9fe', border: '1px solid #c4b5fd' }} />
          <div className="text-sm mt-1" style={{ color: '#7c3aed' }}>
            {unavailableUntil
              ? `Auto-návrat ${new Date(unavailableUntil).toLocaleString('cs-CZ')}`
              : (() => { const now = new Date(); const maxYear = now.getMonth() <= 1 ? now.getFullYear() : now.getFullYear() + 1; return `Bez data = max do 28. 2. ${maxYear} (pak nutno rozhodnout: aktivovat nebo vyřadit)` })()
            }
          </div>
        </div>
      )}
    </div>
  )
}
