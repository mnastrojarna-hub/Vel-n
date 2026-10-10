import { useState } from 'react'
import SearchInput from '../../components/ui/SearchInput'
import { MobileCardList, MobileCard, MobileField, MobileActions, MobileActionButton } from './MobileCard'

// Kampaně na telefonu/tabletu (≤ 1023 px): hlavička pod sebou, skládací filtry, karty místo tabulky.
// Data i akce dodává CampaignsTab — tady je jen rozvržení.
const PILL = { fontSize: 11, padding: '2px 8px', lineHeight: '16px' }
const RED = { color: '#dc2626', bg: '#fee2e2', border: '#fecaca' }

// Akce podle stavu — stejné jako v detailu kampaně na desktopu.
export const STATUS_ACTIONS = {
  draft: { type: 'delete', label: 'Smazat' },
  sending: { type: 'stop', label: 'Zastavit' },
  scheduled: { type: 'cancel', label: 'Zrušit plán' },
}

export function CampaignStatusPill({ status, statusMap }) {
  const st = statusMap[status] || { label: status || '—', color: '#1a2e22', bg: '#f3f4f6' }
  return (
    <span className="inline-flex items-center shrink-0" style={{ gap: 4 }}>
      {status === 'sending' && <span className="animate-pulse inline-block w-2 h-2 rounded-full" style={{ background: '#b45309' }} />}
      <span className="rounded-btn font-extrabold uppercase tracking-wide" style={{ ...PILL, color: st.color, background: st.bg }}>{st.label}</span>
    </span>
  )
}

export function SendProgress({ sent, total, height = 6 }) {
  const pct = total > 0 ? Math.min(100, ((sent || 0) / total) * 100) : 0
  return (
    <div className="rounded-full" style={{ height, background: '#f3f4f6', overflow: 'hidden' }}>
      <div className="rounded-full" style={{ height: '100%', width: `${pct}%`, background: '#74FB71', transition: 'width 0.3s ease' }} />
    </div>
  )
}

export default function CampaignsMobileList({
  channel, campaigns, total, loading, error, debugMode, page, totalPages, setPage,
  filters, setFilters, statusOptions, statusMap, onReset, onCreate, onOpen, onAction, fmtDate, fmtDateTime,
}) {
  return (
    <div style={{ minWidth: 0 }}>
      <div className="mb-3">
        <div className="flex items-center" style={{ gap: 8 }}>
          <h2 className="font-extrabold uppercase tracking-wide" style={{ fontSize: 14, color: '#1a2e22' }}>Kampaně</h2>
          <span className="rounded-btn font-extrabold shrink-0" style={{ fontSize: 13, padding: '3px 10px', color: '#1a2e22', background: '#f1faf7' }}>{total}</span>
        </div>
        <button
          type="button"
          onClick={onCreate}
          className="w-full rounded-btn font-extrabold uppercase tracking-wide cursor-pointer border-none"
          style={{ marginTop: 10, minHeight: 44, padding: '10px 16px', fontSize: 14, background: '#74FB71', color: '#1a2e22', boxShadow: '0 4px 16px rgba(116,251,113,.35)' }}
        >
          + Nová kampaň
        </button>
      </div>

      <Filters filters={filters} setFilters={setFilters} statusOptions={statusOptions} onReset={onReset} />

      {debugMode && (
        <div className="mb-3 p-3 rounded-card" style={{ background: '#fffbeb', border: '1px solid #fbbf24', fontSize: 12, fontFamily: 'monospace', color: '#78350f', overflowWrap: 'anywhere' }}>
          <strong>DIAGNOSTIKA CampaignsTab ({channel})</strong><br />
          <div>campaigns: {campaigns.length} zobrazeno / {total} celkem (strana {page}/{totalPages || 1})</div>
          <div>filtry: statuses={filters.statuses?.length > 0 ? filters.statuses.join(',') : 'vše'}, search="{filters.search}"</div>
          {error && <div style={{ color: '#dc2626' }}>ERROR: {error}</div>}
        </div>
      )}

      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 14, overflowWrap: 'anywhere' }}>{error}</div>}

      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : campaigns.length === 0 ? (
        <div className="bg-white rounded-card shadow-card text-center" style={{ padding: '28px 16px' }}>
          <div style={{ fontSize: 40, marginBottom: 8 }}>📢</div>
          <div style={{ color: '#1a2e22', fontSize: 14, fontWeight: 700 }}>Zatím žádné kampaně. Vytvořte první!</div>
        </div>
      ) : (
        <>
          <MobileCardList tabletGrid>
            {campaigns.map(c => <CampaignCard key={c.id} c={c} statusMap={statusMap} onOpen={onOpen} onAction={onAction} fmtDate={fmtDate} fmtDateTime={fmtDateTime} />)}
          </MobileCardList>
          <Pager page={page} totalPages={totalPages} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}

function CampaignCard({ c, statusMap, onOpen, onAction, fmtDate, fmtDateTime }) {
  const action = STATUS_ACTIONS[c.status]
  const totalR = c.total_recipients
  return (
    <MobileCard onClick={() => onOpen(c)}>
      <div className="flex items-start justify-between" style={{ gap: 8 }}>
        <div className="font-extrabold" style={{ fontSize: 15, lineHeight: 1.35, color: '#0f1a14', minWidth: 0, overflowWrap: 'anywhere' }}>
          {c.name || '—'}
        </div>
        <span style={{ marginTop: 1 }}><CampaignStatusPill status={c.status} statusMap={statusMap} /></span>
      </div>
      {c.message_templates?.name && (
        <div style={{ fontSize: 13, color: '#1a2e22', marginTop: 2, overflowWrap: 'anywhere' }}>📄 {c.message_templates.name}</div>
      )}

      <div className="flex items-baseline justify-between" style={{ gap: 8, marginTop: 10, fontSize: 13, color: '#1a2e22' }}>
        <span>
          <span className="font-extrabold" style={{ fontSize: 14, color: '#0f1a14' }}>{c.sent_count ?? '—'}</span>
          {' / '}{totalR ?? '—'} odesláno
        </span>
        {c.failed_count > 0 && <span className="font-bold" style={{ color: '#dc2626' }}>{c.failed_count} selhalo</span>}
      </div>
      <div style={{ marginTop: 6 }}><SendProgress sent={c.sent_count} total={totalR} /></div>

      <div style={{ marginTop: 6 }}>
        {c.scheduled_at && <MobileField label="Plán. odeslání">{fmtDateTime(c.scheduled_at)}</MobileField>}
        <MobileField label="Vytvořeno">{fmtDate(c.created_at)}</MobileField>
      </div>

      <MobileActions>
        <MobileActionButton onClick={() => onOpen(c)}>Detail ›</MobileActionButton>
        {action && (
          <MobileActionButton onClick={() => onAction({ type: action.type, id: c.id, name: c.name })} color={RED.color} bg={RED.bg} border={RED.border}>
            {action.label}
          </MobileActionButton>
        )}
      </MobileActions>
    </MobileCard>
  )
}

// Hledání + tlačítko „Filtry" se skládacím panelem stavů (Reset jako na desktopu).
function Filters({ filters, setFilters, statusOptions, onReset }) {
  const [open, setOpen] = useState(false)
  const statuses = filters.statuses || []
  const active = statuses.length
  const toggle = val => setFilters(f => {
    const cur = f.statuses || []
    return { ...f, statuses: cur.includes(val) ? cur.filter(v => v !== val) : [...cur, val] }
  })

  return (
    <div className="mb-3">
      <div className="flex items-center" style={{ gap: 8 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <SearchInput fullWidth value={filters.search} onChange={v => setFilters(f => ({ ...f, search: v }))} placeholder="Hledat kampaň…" />
        </div>
        <button
          type="button"
          onClick={() => setOpen(o => !o)}
          aria-expanded={open}
          className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer shrink-0 flex items-center"
          style={{
            minHeight: 42, padding: '8px 12px', fontSize: 13, gap: 6, color: '#1a2e22',
            background: open || active > 0 ? '#e8fee7' : '#f1faf7', border: `1px solid ${active > 0 ? '#74FB71' : '#d4e8e0'}`,
          }}
        >
          Filtry
          {active > 0 && (
            <span className="font-extrabold" style={{ background: '#74FB71', color: '#0f1a14', borderRadius: 50, minWidth: 20, height: 20, fontSize: 12, lineHeight: '20px', textAlign: 'center', padding: '0 5px' }}>{active}</span>
          )}
          <span aria-hidden style={{ fontSize: 10 }}>{open ? '▲' : '▼'}</span>
        </button>
      </div>

      {open && (
        <div className="bg-white rounded-card shadow-card" style={{ padding: 14, marginTop: 10 }}>
          <div className="font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#1a2e22', marginBottom: 6 }}>Status</div>
          <div className="flex flex-wrap" style={{ gap: 8 }}>
            {statusOptions.map(o => {
              const on = statuses.includes(o.value)
              return (
                <label key={o.value} className="flex items-center cursor-pointer rounded-btn"
                  style={{ minHeight: 40, padding: '6px 12px', gap: 8, background: on ? '#74FB71' : '#f1faf7', border: `1px solid ${on ? '#74FB71' : '#d4e8e0'}` }}>
                  <input type="checkbox" checked={on} onChange={() => toggle(o.value)} className="accent-[#1a8a18]" style={{ width: 18, height: 18 }} />
                  <span className="font-bold" style={{ fontSize: 14, color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
                </label>
              )
            })}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', gap: 10, marginTop: 16 }}>
            <button type="button" onClick={onReset} className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer"
              style={{ minHeight: 44, fontSize: 13, background: '#fee2e2', border: '1px solid #fca5a5', color: '#dc2626' }}>
              Reset
            </button>
            <button type="button" onClick={() => setOpen(false)} className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer"
              style={{ minHeight: 44, fontSize: 13, background: '#74FB71', border: '1px solid #74FB71', color: '#0f1a14' }}>
              Hotovo
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

// Stránkování pro prst: šipky 44 px + výběr libovolné strany (nativní picker).
function Pager({ page, totalPages, onPageChange }) {
  if (totalPages <= 1) return null
  const btn = disabled => ({ width: 48, minHeight: 44, fontSize: 18, background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22', opacity: disabled ? 0.35 : 1 })
  return (
    <div className="flex items-center" style={{ gap: 8, marginTop: 14 }}>
      <button type="button" aria-label="Předchozí strana" disabled={page <= 1} onClick={() => onPageChange(page - 1)}
        className="rounded-btn font-extrabold cursor-pointer shrink-0 disabled:cursor-not-allowed" style={btn(page <= 1)}>←</button>
      <select value={page} onChange={e => onPageChange(Number(e.target.value))} aria-label="Strana"
        className="rounded-btn font-extrabold cursor-pointer outline-none"
        style={{ flex: 1, minWidth: 0, minHeight: 44, padding: '8px 12px', textAlign: 'center', textAlignLast: 'center', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        {Array.from({ length: totalPages }, (_, i) => <option key={i + 1} value={i + 1}>Strana {i + 1} z {totalPages}</option>)}
      </select>
      <button type="button" aria-label="Další strana" disabled={page >= totalPages} onClick={() => onPageChange(page + 1)}
        className="rounded-btn font-extrabold cursor-pointer shrink-0 disabled:cursor-not-allowed" style={btn(page >= totalPages)}>→</button>
    </div>
  )
}
