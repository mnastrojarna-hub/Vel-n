import { fmtAlertTime } from '../hooks/useKioskAlerts'

// Mobilní (≤ 1023 px) seznam poboček: karta místo 9sloupcové tabulky (telefon 1 sloupec, tablet 2).
// Stejná data i akce jako řádek tabulky v Branches.jsx; desktop tuto komponentu nepoužívá.

const BTN = 'rounded-btn text-[13px] font-bold cursor-pointer border-none min-h-[40px]'

export default function BranchesListMobile({ branches, filtered, stats, bookingStats, alertsByBranch, onOpen, onToggleOpen, onEdit, onToggleActive, onDelete }) {
  if (filtered.length === 0) {
    return branches.length > 0 ? (
      <div className="bg-white rounded-card shadow-card text-sm text-center" style={{ padding: 20, color: '#1a2e22' }}>
        Žádné pobočky neodpovídají filtru
      </div>
    ) : null
  }
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
      {filtered.map(b => {
        const alerts = alertsByBranch[b.id] || []
        const st = stats[b.id] || {}
        const bk = bookingStats[b.id] || 0
        return (
          <div key={b.id} onClick={() => onOpen(b)}
            className="rounded-card shadow-card cursor-pointer flex flex-col gap-2"
            style={{ padding: 14, background: alerts.length > 0 ? '#fee2e2' : '#fff', opacity: b.active === false ? 0.6 : 1 }}>
            <div className="flex items-start gap-2">
              <div className="min-w-0 flex-1">
                <div className="font-extrabold" style={{ fontSize: 15, color: '#0f1a14', overflowWrap: 'anywhere' }}>{b.name}</div>
                <div className="text-[13px]" style={{ color: '#4a6357' }}>
                  <span className="font-mono font-bold">{b.branch_code || '—'}</span>{b.city ? ` · ${b.city}` : ''}
                </div>
              </div>
              <button onClick={e => { e.stopPropagation(); onToggleOpen(b) }}
                className="shrink-0 rounded-btn text-[11px] font-extrabold tracking-wide uppercase cursor-pointer min-h-[36px]"
                style={{ padding: '4px 12px', background: b.is_open ? '#dcfce7' : '#fff', color: b.is_open ? '#1a8a18' : '#dc2626', border: `1px solid ${b.is_open ? '#bbf7d0' : '#fca5a5'}` }}>
                {b.is_open ? 'Otevřená' : 'Zavřená'}
              </button>
            </div>

            {alerts.length > 0 && (
              <div className="rounded-lg text-[12px]" style={{ padding: '8px 10px', background: '#dc2626', color: '#fff' }}>
                <div className="font-extrabold uppercase">🚨 Dveře otevřeny bez kódu{alerts.length > 1 ? ` ×${alerts.length}` : ''}</div>
                {alerts.map(a => (
                  <div key={a.id}>{a.title} · {fmtAlertTime(a.created_at)}{a.closed_at ? ' (dveře znovu zavřeny)' : ' (dveře stále otevřené)'}</div>
                ))}
                <div style={{ opacity: 0.85 }}>Otevřete detail → Samoobsluha a poplach potvrďte.</div>
              </div>
            )}

            {(b.address || b.phone) && (
              <div className="text-[13px]" style={{ color: '#1a2e22' }}>
                {b.address && <div>{b.address}</div>}
                {b.phone && <div className="font-mono">{b.phone}</div>}
              </div>
            )}

            <div className="flex flex-wrap gap-x-4 gap-y-1 text-[13px]" style={{ color: '#1a2e22' }}>
              <span>
                Motorky: <b style={{ color: '#1a8a18' }}>{st.active || 0}</b> / {st.total || 0}
                {st.maintenance > 0 && <span className="text-[12px] ml-1" style={{ color: '#b45309' }}>({st.maintenance} servis)</span>}
              </span>
              <span>Rezervace: <b style={{ color: bk > 0 ? '#8b5cf6' : '#1a2e22' }}>{bk}</b></span>
            </div>

            <div className="flex flex-wrap gap-2 pt-1" onClick={e => e.stopPropagation()}>
              <button onClick={() => onEdit(b)} className={BTN} style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb' }}>Upravit</button>
              <button onClick={() => onToggleActive(b)} className={BTN}
                style={{ padding: '6px 14px', background: b.active === false ? '#dcfce7' : '#fef3c7', color: b.active === false ? '#1a8a18' : '#b45309' }}>
                {b.active === false ? 'Aktivovat' : 'Deaktivovat'}
              </button>
              <button onClick={() => onDelete(b)} className={BTN} style={{ padding: '6px 14px', background: '#fff', color: '#dc2626', boxShadow: 'inset 0 0 0 1px #fca5a5' }}>Smazat</button>
            </div>
          </div>
        )
      })}
    </div>
  )
}
