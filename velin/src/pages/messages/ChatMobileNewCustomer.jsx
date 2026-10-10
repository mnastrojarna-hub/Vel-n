// Výběr zákazníka v modálu „Nová konverzace“ na telefonu/tabletu (≤ 1023 px).
// Nativní <select size> měl na dotyku řádky ~20 px a dlouhé „jméno (e-mail)“ se uřízlo,
// proto velké řádky pro prst; vybraný zákazník = karta se „Změnit“. Stav drží Messages (stejné hodnoty).

import { breakable } from './MobileCard'

const FIELD = { padding: '10px 12px', minHeight: 44, background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }
const WRAP = { overflowWrap: 'anywhere', minWidth: 0 }

export default function ChatMobileNewCustomer({ customers, filteredCustomers, customerId, onSelect, search, onSearch }) {
  const selected = customerId ? customers.find(c => c.id === customerId) : null

  if (selected) {
    return (
      <div className="flex items-center rounded-card" style={{ gap: 10, padding: '10px 12px', background: '#e8fee7', border: '1px solid #74FB71' }}>
        <div style={{ flex: 1, ...WRAP }}>
          <div className="font-bold" style={{ fontSize: 15, color: '#0f1a14', ...WRAP }}>{selected.full_name || 'Bez jména'}</div>
          {selected.email && <div style={{ fontSize: 13, color: '#1a2e22', marginTop: 2, ...WRAP }}>{breakable(selected.email)}</div>}
        </div>
        <button type="button" onClick={() => onSelect('')}
          className="shrink-0 rounded-btn font-bold cursor-pointer border-none"
          style={{ minHeight: 40, padding: '8px 14px', fontSize: 14, background: '#fee2e2', color: '#dc2626' }}>
          Změnit
        </button>
      </div>
    )
  }

  return (
    <>
      <input
        type="text"
        autoComplete="off"
        placeholder="Hledat zákazníka…"
        value={search}
        onChange={e => onSearch(e.target.value)}
        className="w-full rounded-btn text-sm outline-none"
        style={FIELD}
      />
      {filteredCustomers.length > 0 && (
        <div role="listbox" aria-label="Zákazník" className="rounded-card"
          style={{ marginTop: 6, border: '1px solid #d4e8e0', maxHeight: 'min(264px, 34dvh)', overflowY: 'auto', overscrollBehavior: 'contain', background: '#fff' }}>
          {filteredCustomers.map(c => (
            <button key={c.id} type="button" role="option" aria-selected={false} onClick={() => onSelect(c.id)}
              className="block w-full text-left cursor-pointer border-none"
              style={{ minHeight: 52, padding: '8px 14px', background: '#fff', borderBottom: '1px solid #f1faf7' }}>
              <span className="block font-bold" style={{ fontSize: 15, color: '#0f1a14', ...WRAP }}>{c.full_name || 'Bez jména'}</span>
              {c.email && <span className="block" style={{ fontSize: 13, color: '#1a2e22', marginTop: 1, ...WRAP }}>{breakable(c.email)}</span>}
            </button>
          ))}
        </div>
      )}
    </>
  )
}
