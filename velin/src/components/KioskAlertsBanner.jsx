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
          // mobil/tablet (< lg): řádek se láme do více řádků → menší zaoblení místo „pilulky“
          <div key={a.id} className="flex items-center gap-2 flex-wrap lg:rounded-btn max-lg:rounded-xl"
            style={{ background: '#fff', padding: '6px 10px', fontSize: 13, color: '#1a2e22' }}>
            {/* desktop: obal neexistuje (contents); mobil/tablet: text se zalamuje vlevo, „Potvrdit“ zůstává vpravo */}
            <div className="lg:contents max-lg:flex-1 max-lg:min-w-0 max-lg:flex max-lg:flex-wrap max-lg:items-center max-lg:gap-x-2 max-lg:gap-y-0.5">
              {onOpenBranch && (
                <button onClick={() => onOpenBranch(a.branch_id)} className="font-extrabold underline cursor-pointer border-none p-0 max-lg:py-1.5"
                  style={{ background: 'none', color: '#b91c1c' }}>
                  {a.branches?.name || 'Pobočka'}
                </button>
              )}
              <span className="font-bold">{a.title}</span>
              <span style={{ color: '#6b8c7a' }}>· {fmtAlertTime(a.created_at)}</span>
              {a.closed_at
                ? <span style={{ color: '#1a8a18' }}>· dveře znovu zavřeny {fmtAlertTime(a.closed_at)}</span>
                : <span className="font-bold" style={{ color: '#dc2626' }}>· dveře jsou stále otevřené</span>}
            </div>
            <button onClick={() => ack(a)} disabled={busy === a.id}
              className="ml-auto rounded-btn text-[11px] font-extrabold uppercase cursor-pointer border-none px-2.5 py-1 max-lg:px-4 max-lg:min-h-[36px] max-lg:shrink-0"
              style={{ background: '#1a2e22', color: '#74FB71', opacity: busy === a.id ? 0.6 : 1 }}
              title="Potvrdit, že jste poplach viděli — zmizí z Velína (zůstane v logu otevření).">
              {busy === a.id ? '…' : 'Potvrdit'}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}
