// Přepínač pobočky pro Rezervace (seznam, kalendář, odjezdy a návraty) — „Všechny pobočky“ nebo jedna pobočka.
// Pobočka rezervace = pobočka její motorky (motorcycles.branch_id); bookings.branch_id appka ani web nevyplňují.

/** Krátký název pobočky bez značky („MotoGo24 Brno Velké Němčice“ → „Brno Velké Němčice“). */
export function shortBranchName(name) {
  return String(name || '').replace(/^\s*moto\s*go\s*24\s*/i, '').trim() || String(name || '')
}

/** Pobočka rezervace: motorka (aktuální umístění), jinak bookings.branch_id. */
export function bookingBranchId(b) {
  return b?.motorcycles?.branch_id || b?.branch_id || null
}

export default function BranchChips({ branches, value, onChange }) {
  if (!branches || branches.length < 2) return null
  const chip = (id, label) => {
    const on = (value || '') === id
    return (
      <button key={id || 'all'} onClick={() => onChange(id)}
        className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
        style={{ padding: '6px 12px', border: '1px solid #d4e8e0', background: on ? '#74FB71' : '#f1faf7', color: '#1a2e22',
          boxShadow: on ? '0 4px 14px rgba(116,251,113,.35)' : 'none' }}>
        {label}
      </button>
    )
  }
  return (
    <div className="flex items-center gap-2 flex-wrap mb-4">
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#6b8c7a' }}>Pobočka:</span>
      {chip('', 'Všechny pobočky')}
      {branches.map(b => chip(b.id, shortBranchName(b.name)))}
    </div>
  )
}
