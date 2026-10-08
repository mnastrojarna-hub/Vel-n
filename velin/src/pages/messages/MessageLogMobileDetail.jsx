import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { MobileField } from './MobileCard'

// Detail zprávy z logu pro telefon/tablet — údaje pod sebou, nic nesmí rozšířit dialog.
export default function MessageLogMobileDetail({ detail, channelLabel, statusMap, recipientOf, formatDate, onClose }) {
  if (!detail) return null
  const st = statusMap[detail.status] || { label: detail.status || '—', color: '#1a2e22', bg: '#f3f4f6' }
  const sectionTitle = 'text-sm font-extrabold uppercase tracking-wide mb-1'

  return (
    <Modal open title={`${channelLabel} zpráva`} onClose={onClose} wide>
      <div className="space-y-3" style={{ minWidth: 0 }}>
        <div className="rounded-card" style={{ padding: '6px 12px 10px', background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
          <MobileField label="Příjemce">{recipientOf(detail)}</MobileField>
          <MobileField label="Čas">{formatDate(detail.created_at)}</MobileField>
          <MobileField label="Status">
            <span className="inline-block rounded-btn font-extrabold uppercase tracking-wide" style={{ fontSize: 11, padding: '3px 8px', color: st.color, background: st.bg }}>
              {st.label}
            </span>
          </MobileField>
          {detail.template_slug && <MobileField label="Šablona">{detail.template_slug}</MobileField>}
          {detail.cost_amount != null && <MobileField label="Cena">{detail.cost_amount} Kč</MobileField>}
          {detail.is_marketing && (
            <MobileField label="Typ">
              <span className="inline-block rounded-btn font-extrabold uppercase tracking-wide" style={{ fontSize: 11, padding: '3px 8px', color: '#7c3aed', background: '#ede9fe' }}>
                Marketing
              </span>
            </MobileField>
          )}
        </div>

        {detail.error_message && (
          <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 14, overflowWrap: 'anywhere' }}>
            <span className="font-bold">Chyba:</span> {detail.error_message}
          </div>
        )}

        <div>
          <div className={sectionTitle} style={{ color: '#1a2e22' }}>Obsah zprávy</div>
          <div className="rounded-card" style={{ padding: 12, background: '#f8fcfa', border: '1px solid #d4e8e0', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', fontSize: 14, lineHeight: 1.5, color: '#0f1a14', maxHeight: '45vh', overflow: 'auto' }}>
            {detail.content_preview || detail.content_full || '—'}
          </div>
        </div>

        {detail.metadata && (
          <div>
            <div className={sectionTitle} style={{ color: '#1a2e22' }}>Metadata</div>
            <pre className="rounded-card" style={{ padding: 10, margin: 0, background: '#f1faf7', border: '1px solid #d4e8e0', fontSize: 12, maxHeight: 200, overflow: 'auto', color: '#1a2e22', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
              {JSON.stringify(detail.metadata, null, 2)}
            </pre>
          </div>
        )}
      </div>

      <Button onClick={onClose} className="w-full justify-center" style={{ marginTop: 16, minHeight: 44 }}>Zavřít</Button>
    </Modal>
  )
}
