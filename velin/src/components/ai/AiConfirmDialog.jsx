import { RISK_LEVELS, getAgentForTool } from '../../lib/aiAgents'
import Button from '../ui/Button'

export default function AiConfirmDialog({ actions, onConfirm, onReject, onEdit }) {
  if (!actions || actions.length === 0) return null

  const riskOrder = { high: 0, medium: 1, low: 2 }
  const sorted = [...actions].sort((a, b) => (riskOrder[a.risk] || 2) - (riskOrder[b.risk] || 2))
  const maxRisk = sorted[0]?.risk || 'low'
  const riskInfo = RISK_LEVELS[maxRisk] || RISK_LEVELS.low

  return (
    <div style={{
      position: 'fixed', inset: 0, zIndex: 9999,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(4px)',
    }}>
      <div style={{
        background: '#fff', borderRadius: 16, maxWidth: 560, width: '90%',
        maxHeight: '80vh', overflow: 'auto', boxShadow: '0 20px 60px rgba(0,0,0,0.3)',
      }}>
        {/* Header */}
        <div style={{
          padding: '16px 20px', borderBottom: '2px solid ' + riskInfo.color,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <span style={{ fontSize: 22 }}>🤖</span>
          <div>
            <div style={{ fontWeight: 800, fontSize: 15, color: '#0f1a14' }}>
              AI chce provést {actions.length} {actions.length === 1 ? 'akci' : actions.length < 5 ? 'akce' : 'akcí'}
            </div>
            <div style={{ fontSize: 12, color: riskInfo.color, fontWeight: 600 }}>
              Riziko: {riskInfo.label}
            </div>
          </div>
        </div>

        {/* Actions */}
        <div style={{ padding: '12px 20px' }}>
          {sorted.map((action, i) => {
            const agent = getAgentForTool(action.tool)
            const risk = RISK_LEVELS[action.risk] || RISK_LEVELS.low
            return (
              <div key={action.id || i} style={{
                padding: '10px 12px', marginBottom: 8, borderRadius: 10,
                border: '1px solid #d4e8e0', background: '#f8fcfa',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                  <span style={{ fontSize: 14 }}>{agent?.icon || '⚙️'}</span>
                  <span style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>
                    {agent?.name || action.tool}
                  </span>
                  <span style={{
                    fontSize: 10, padding: '1px 6px', borderRadius: 8,
                    background: risk.color + '20', color: risk.color, fontWeight: 600,
                  }}>
                    {risk.label}
                  </span>
                </div>
                <div style={{ fontSize: 13, color: '#1a2e22', lineHeight: 1.5 }}>
                  {action.summary}
                </div>
                {action.details && (
                  <div style={{
                    fontSize: 11, color: '#666', marginTop: 4,
                    fontFamily: 'monospace', background: '#f1faf7',
                    padding: '4px 8px', borderRadius: 6, maxHeight: 80, overflow: 'auto',
                  }}>
                    {typeof action.details === 'string' ? action.details : JSON.stringify(action.details, null, 1)}
                  </div>
                )}
              </div>
            )
          })}
        </div>

        {/* Footer */}
        <div style={{
          padding: '12px 20px', borderTop: '1px solid #d4e8e0',
          display: 'flex', gap: 8, justifyContent: 'flex-end',
        }}>
          <Button onClick={onReject} style={{
            background: '#fee2e2', color: '#dc2626', border: 'none',
            fontSize: 13, padding: '8px 16px', borderRadius: 8,
          }}>
            Zamítnout
          </Button>
          <Button onClick={onEdit} style={{
            background: '#fef3c7', color: '#92400e', border: 'none',
            fontSize: 13, padding: '8px 16px', borderRadius: 8,
          }}>
            Upravit zadání
          </Button>
          <Button green onClick={onConfirm} style={{
            fontSize: 13, padding: '8px 20px', borderRadius: 8,
          }}>
            Potvrdit a provést
          </Button>
        </div>
      </div>
    </div>
  )
}
