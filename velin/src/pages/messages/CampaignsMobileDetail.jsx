import Modal from '../../components/ui/Modal'
import { useMediaQuery } from '../../hooks/useIsMobile'
import { CampaignStatusPill, SendProgress, STATUS_ACTIONS } from './CampaignsMobileList'
import { breakable } from './MobileCard'

// Detail kampaně na telefonu/tabletu: stejný obsah i akce jako na desktopu,
// statistiky v dlaždicích, log příjemců jako seznam řádků, akce v liště dole.
const SECTION = { fontSize: 12, color: '#1a2e22', marginBottom: 6 }
const LOG_STATUS = {
  sent: { label: 'Odesláno', color: '#2563eb', bg: '#dbeafe' },
  delivered: { label: 'Doručeno', color: '#1a8a18', bg: '#dcfce7' },
  failed: { label: 'Selhalo', color: '#dc2626', bg: '#fee2e2' },
}

function Tile({ label, value, color }) {
  return (
    <div className="rounded-card" style={{ padding: '10px 8px', background: '#f8fcfa', border: '1px solid #d4e8e0', minWidth: 0, textAlign: 'center' }}>
      <div className="font-black" style={{ fontSize: 22, lineHeight: 1.1, color }}>{value}</div>
      <div className="font-extrabold uppercase tracking-wide" style={{ fontSize: 11, color: '#1a2e22', marginTop: 4, overflowWrap: 'anywhere' }}>{label}</div>
    </div>
  )
}

export default function CampaignsMobileDetail({ detail, channelLabel, statusMap, logs, logsLoading, onClose, onAction, fmtDateTime }) {
  // Odsazení okna Modal: p-4 na telefonu, sm:p-7 od 640 px — lišta akcí ho přetahuje až k okraji.
  const pad = useMediaQuery('(min-width: 640px)') ? 28 : 16
  const action = STATUS_ACTIONS[detail.status]
  const sent = detail.sent_count ?? 0
  const totalR = detail.total_recipients ?? 0
  const pct = totalR > 0 ? Math.min(100, Math.round((sent / totalR) * 100)) : 0
  const vars = detail.template_vars && Object.keys(detail.template_vars).length > 0 ? Object.entries(detail.template_vars) : null

  return (
    <Modal open title="Detail kampaně" onClose={onClose} wide>
      <div style={{ minWidth: 0 }}>
        <div className="font-extrabold" style={{ fontSize: 17, lineHeight: 1.3, color: '#0f1a14', overflowWrap: 'anywhere' }}>{detail.name}</div>
        <div className="flex flex-wrap items-center" style={{ gap: 6, marginTop: 6, marginBottom: 14 }}>
          <CampaignStatusPill status={detail.status} statusMap={statusMap} />
          <span className="rounded-btn font-extrabold uppercase tracking-wide" style={{ fontSize: 11, padding: '2px 8px', lineHeight: '16px', color: '#2563eb', background: '#dbeafe' }}>{channelLabel}</span>
        </div>

        {/* Statistiky */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 8, marginBottom: 14 }}>
          <Tile label="Příjemci" value={detail.total_recipients ?? 0} color="#1a2e22" />
          <Tile label="Odesláno" value={detail.sent_count ?? 0} color="#1a8a18" />
          <Tile label="Selhalo" value={detail.failed_count ?? 0} color="#dc2626" />
        </div>

        {/* Průběh odesílání */}
        <div style={{ marginBottom: 16 }}>
          <div className="flex items-baseline justify-between" style={{ gap: 8, marginBottom: 6 }}>
            <span className="font-extrabold uppercase tracking-wide" style={{ fontSize: 12, color: '#1a2e22' }}>Průběh odesílání</span>
            <span className="font-bold" style={{ fontSize: 14, color: '#1a2e22', whiteSpace: 'nowrap' }}>{sent} / {totalR} · {pct} %</span>
          </div>
          <SendProgress sent={detail.sent_count} total={detail.total_recipients} height={10} />
        </div>

        {detail.message_templates && (
          <div style={{ marginBottom: 14 }}>
            <div className="font-extrabold uppercase tracking-wide" style={SECTION}>Šablona</div>
            <div className="rounded-card" style={{ padding: 12, background: '#f8fcfa', border: '1px solid #d4e8e0', fontSize: 14, lineHeight: 1.45, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', maxHeight: 200, overflow: 'auto', color: '#0f1a14' }}>
              {detail.message_templates.body_template || '—'}
            </div>
          </div>
        )}

        {vars && (
          <div style={{ marginBottom: 14 }}>
            <div className="font-extrabold uppercase tracking-wide" style={SECTION}>Proměnné</div>
            <div className="rounded-card" style={{ padding: '6px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
              {vars.map(([key, val], i) => (
                <div key={key} style={{ padding: '6px 0', borderTop: i ? '1px solid #d4e8e0' : 'none', minWidth: 0 }}>
                  <div className="font-mono font-bold" style={{ fontSize: 12, color: '#1a2e22', overflowWrap: 'anywhere' }}>{key}</div>
                  <div style={{ fontSize: 14, color: '#0f1a14', overflowWrap: 'anywhere' }}>{String(val)}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Log zpráv */}
        <div style={{ marginBottom: 8 }}>
          <div className="font-extrabold uppercase tracking-wide" style={SECTION}>Log zpráv</div>
          {logsLoading ? (
            <div className="flex justify-center py-4"><div className="animate-spin rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>
          ) : logs.length === 0 ? (
            <div className="text-center py-4" style={{ color: '#6b7280', fontSize: 14 }}>Žádné záznamy</div>
          ) : (
            <>
              <div className="rounded-card" style={{ border: '1px solid #d4e8e0', overflow: 'hidden' }}>
                {logs.map((log, i) => {
                  const st = LOG_STATUS[log.status] || { label: log.status || '—', color: '#6b7280', bg: '#f3f4f6' }
                  return (
                    <div key={log.id} className="flex items-center justify-between" style={{ gap: 10, padding: '9px 12px', borderTop: i ? '1px solid #d4e8e0' : 'none', minWidth: 0 }}>
                      <div style={{ minWidth: 0 }}>
                        <div className="font-bold" style={{ fontSize: 14, color: '#0f1a14', overflowWrap: 'anywhere' }}>{breakable(log.recipient_email || log.recipient_phone || '—')}</div>
                        <div className="font-mono" style={{ fontSize: 12, color: '#6b7280', marginTop: 1 }}>{fmtDateTime(log.created_at)}</div>
                      </div>
                      <span className="rounded-btn font-extrabold uppercase tracking-wide shrink-0" style={{ fontSize: 11, padding: '2px 8px', lineHeight: '16px', color: st.color, background: st.bg }}>{st.label}</span>
                    </div>
                  )
                })}
              </div>
              {logs.length >= 20 && (
                <div className="text-center mt-2">
                  <span className="text-sm font-bold cursor-pointer" style={{ color: '#2563eb' }}>Zobrazit vše →</span>
                </div>
              )}
            </>
          )}
        </div>

        {/* Akce — lišta přilepená ke spodní hraně okna */}
        <div
          style={{
            position: 'sticky', bottom: -pad, zIndex: 1, margin: `0 -${pad}px -${pad}px`, padding: `12px ${pad}px ${pad}px`, background: '#fff', borderTop: '1px solid #e5e7eb',
            display: 'grid', gridTemplateColumns: action ? 'minmax(0, 1fr) minmax(0, 1fr)' : 'minmax(0, 1fr)', gap: 10,
          }}
        >
          {action && (
            <button type="button" onClick={() => onAction({ type: action.type, id: detail.id, name: detail.name })}
              className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer border-none"
              style={{ minHeight: 44, fontSize: 14, background: '#dc2626', color: '#fff', boxShadow: '0 4px 16px rgba(220,38,38,.25)' }}>
              {action.label}
            </button>
          )}
          <button type="button" onClick={onClose} className="rounded-btn font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ minHeight: 44, fontSize: 14, background: '#e2f5ec', color: '#0f1a14', border: '1px solid #b6dccb' }}>
            Zavřít
          </button>
        </div>
      </div>
    </Modal>
  )
}
