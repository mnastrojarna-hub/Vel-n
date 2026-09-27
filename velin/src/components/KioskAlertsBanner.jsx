import { useState } from 'react'
import { acknowledgeKioskAlert, fmtAlertTime } from '../hooks/useKioskAlerts'

// Červený blok „dveře otevřeny bez kódu“ (Dashboard = všechny pobočky, tab Samoobsluha = jedna pobočka).
// Nic nevykreslí, když není otevřený poplach. `onOpenBranch(branchId)` = odkaz na pobočku (jen na Dashboardu).
export default function KioskAlertsBanner({ alerts, onAck, onOpenBranch, compact = false }) {
  const [busy, setBusy] = useState(null)
  if (!alerts || alerts.length === 0) return null

  async function ack(a) {
    setBusy(a.id)
    const ok = await acknowledgeKioskAlert(a.id)
    setBusy(null)
    if (ok && onAck) onAck(a)
  }

  return (
    <div className="mb-5 rounded-card" role="alert"
      style={{ background: '#fee2e2', border: '2px solid #dc2626', padding: compact ? 10 : 14 }}>
      <div className="flex items-center gap-2 mb-2">
        <span className="text-xl" aria-hidden>🚨</span>
        <div className="font-black uppercase tracking-wide" style={{ color: '#b91c1c', fontSize: compact ? 13 : 15 }}>
          Samoobsluha: dveře otevřeny bez kódu ({alerts.length})
        </div>
      </div>
      <div className="space-y-1.5">
        {alerts.map(a => (
          <div key={a.id} className="flex items-center gap-2 flex-wrap rounded-btn"
            style={{ background: '#fff', padding: '6px 10px', fontSize: 13, color: '#1a2e22' }}>
            {onOpenBranch && (
              <button onClick={() => onOpenBranch(a.branch_id)} className="font-extrabold underline cursor-pointer border-none"
                style={{ background: 'none', color: '#b91c1c', padding: 0 }}>
                {a.branches?.name || 'Pobočka'}
              </button>
            )}
            <span className="font-bold">{a.title}</span>
            <span style={{ color: '#6b8c7a' }}>· {fmtAlertTime(a.created_at)}</span>
            {a.closed_at
              ? <span style={{ color: '#1a8a18' }}>· dveře znovu zavřeny {fmtAlertTime(a.closed_at)}</span>
              : <span className="font-bold" style={{ color: '#dc2626' }}>· dveře jsou stále otevřené</span>}
            <button onClick={() => ack(a)} disabled={busy === a.id}
              className="ml-auto rounded-btn text-[11px] font-extrabold uppercase cursor-pointer border-none"
              style={{ padding: '4px 10px', background: '#1a2e22', color: '#74FB71', opacity: busy === a.id ? 0.6 : 1 }}
              title="Potvrdit, že jste poplach viděli — zmizí z Velína (zůstane v logu otevření).">
              {busy === a.id ? '…' : 'Potvrdit'}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}
