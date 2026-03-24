import { useState } from 'react'
import { AGENTS, loadAgentConfig, saveAgentConfig } from '../../lib/aiAgents'

export default function AiAgentPanel({ config, onChange, onConfigAgent }) {
  const [editingId, setEditingId] = useState(null)
  const [corrText, setCorrText] = useState('')

  function toggle(agentId) {
    const next = { ...config, [agentId]: { ...config[agentId], enabled: !config[agentId]?.enabled } }
    saveAgentConfig(next)
    onChange(next)
  }

  function toggleAutoConfirm(agentId) {
    const cur = config[agentId] || {}
    const next = { ...config, [agentId]: { ...cur, autoConfirm: !cur.autoConfirm } }
    saveAgentConfig(next)
    onChange(next)
  }

  function addCorrection(agentId) {
    if (!corrText.trim()) return
    const cur = config[agentId] || {}
    const corrs = [...(cur.corrections || []), corrText.trim()]
    const next = { ...config, [agentId]: { ...cur, corrections: corrs } }
    saveAgentConfig(next)
    onChange(next)
    setCorrText('')
    setEditingId(null)
  }

  function removeCorrection(agentId, idx) {
    const cur = config[agentId] || {}
    const corrs = (cur.corrections || []).filter((_, i) => i !== idx)
    const next = { ...config, [agentId]: { ...cur, corrections: corrs } }
    saveAgentConfig(next)
    onChange(next)
  }

  const enabled = AGENTS.filter(a => config[a.id]?.enabled)
  const disabled = AGENTS.filter(a => !config[a.id]?.enabled)

  return (
    <div style={{ padding: 12 }}>
      <div style={{ fontSize: 13, fontWeight: 800, color: '#0f1a14', marginBottom: 8 }}>
        AI Agenti ({enabled.length}/{AGENTS.length} aktivních)
      </div>

      {[...enabled, ...disabled].map(agent => {
        const cfg = config[agent.id] || {}
        const isOn = cfg.enabled
        const corrs = cfg.corrections || []

        return (
          <div key={agent.id} style={{
            padding: '8px 10px', marginBottom: 6, borderRadius: 10,
            border: '1px solid ' + (isOn ? '#74FB71' : '#e5e7eb'),
            background: isOn ? '#f1faf7' : '#fafafa',
            opacity: isOn ? 1 : 0.7,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ fontSize: 16 }}>{agent.icon}</span>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12, fontWeight: 700, color: '#0f1a14' }}>{agent.name}</div>
                <div style={{ fontSize: 11, color: '#666' }}>{agent.desc}</div>
              </div>
              <button
                onClick={() => toggle(agent.id)}
                style={{
                  width: 36, height: 20, borderRadius: 10, border: 'none', cursor: 'pointer',
                  background: isOn ? '#74FB71' : '#d1d5db', position: 'relative', transition: 'background 0.2s',
                }}
              >
                <span style={{
                  width: 16, height: 16, borderRadius: '50%', background: '#fff',
                  position: 'absolute', top: 2, transition: 'left 0.2s',
                  left: isOn ? 18 : 2, boxShadow: '0 1px 3px rgba(0,0,0,0.2)',
                }} />
              </button>
            </div>

            {isOn && (
              <div style={{ marginTop: 6, paddingLeft: 28 }}>
                {/* Config button */}
                {onConfigAgent && (
                  <button onClick={() => onConfigAgent(agent.id)} style={{
                    fontSize: 11, color: '#2563eb', background: '#eff6ff', border: '1px solid #bfdbfe',
                    borderRadius: 4, padding: '2px 8px', cursor: 'pointer', marginBottom: 4, display: 'block',
                  }}>
                    📝 Zadání + Paměť
                  </button>
                )}
                {/* Auto-confirm toggle */}
                <label style={{ fontSize: 11, color: '#666', display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
                  <input type="checkbox" checked={cfg.autoConfirm || false} onChange={() => toggleAutoConfirm(agent.id)} style={{ width: 12, height: 12 }} />
                  Auto-potvrzení (bez dialogu)
                </label>

                {/* Corrections */}
                {corrs.length > 0 && (
                  <div style={{ marginTop: 4 }}>
                    {corrs.map((c, i) => (
                      <div key={i} style={{
                        fontSize: 11, color: '#92400e', background: '#fef3c7',
                        padding: '2px 6px', borderRadius: 4, marginBottom: 2,
                        display: 'flex', alignItems: 'center', gap: 4,
                      }}>
                        <span style={{ flex: 1 }}>{c}</span>
                        <button onClick={() => removeCorrection(agent.id, i)} style={{
                          background: 'none', border: 'none', color: '#dc2626',
                          cursor: 'pointer', fontSize: 10, padding: 0,
                        }}>✕</button>
                      </div>
                    ))}
                  </div>
                )}

                {/* Add correction */}
                {editingId === agent.id ? (
                  <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
                    <input
                      value={corrText}
                      onChange={e => setCorrText(e.target.value)}
                      placeholder="Instrukce pro agenta..."
                      onKeyDown={e => e.key === 'Enter' && addCorrection(agent.id)}
                      style={{ flex: 1, fontSize: 11, padding: '3px 6px', borderRadius: 4, border: '1px solid #d4e8e0' }}
                      autoFocus
                    />
                    <button onClick={() => addCorrection(agent.id)} style={{
                      fontSize: 11, padding: '3px 8px', borderRadius: 4,
                      background: '#74FB71', border: 'none', cursor: 'pointer',
                    }}>+</button>
                    <button onClick={() => { setEditingId(null); setCorrText('') }} style={{
                      fontSize: 11, padding: '3px 6px', borderRadius: 4,
                      background: '#e5e7eb', border: 'none', cursor: 'pointer',
                    }}>✕</button>
                  </div>
                ) : (
                  <button onClick={() => setEditingId(agent.id)} style={{
                    fontSize: 11, color: '#2563eb', background: 'none',
                    border: 'none', cursor: 'pointer', padding: 0, marginTop: 4,
                  }}>
                    + Přidat korekci
                  </button>
                )}
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
