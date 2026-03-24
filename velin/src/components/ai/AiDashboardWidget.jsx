import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { AGENTS, loadAgentConfig, getEnabledTools, getAgentCorrections } from '../../lib/aiAgents'
import { buildAgentPromptsText } from '../../lib/aiAgentPrompts'
import { buildAllAgentMemory } from '../../lib/aiAgentMemory'

export default function AiDashboardWidget() {
  const [result, setResult] = useState(null)
  const [loading, setLoading] = useState(false)

  async function runBriefing() {
    setLoading(true)
    try {
      const config = loadAgentConfig()
      const enabledIds = AGENTS.filter(a => config[a.id]?.enabled).map(a => a.id)
      const { data } = await supabase.functions.invoke('ai-copilot', {
        body: {
          message: 'Stručný přehled dne v 5 bodech: aktivní rezervace, tržby, SOS, servisy, priority. Max 200 slov.',
          enabled_tools: getEnabledTools(config),
          agent_corrections: getAgentCorrections(config),
          agent_prompts: buildAgentPromptsText(enabledIds),
          agent_memory: buildAllAgentMemory(enabledIds),
        },
      })
      setResult(data?.response || 'Nedostupné')
    } catch (e) {
      setResult(`Chyba: ${e.message}`)
    } finally { setLoading(false) }
  }

  const config = loadAgentConfig()
  const enabledCount = AGENTS.filter(a => config[a.id]?.enabled).length

  return (
    <div className="rounded-card bg-white shadow-card" style={{ padding: 16 }}>
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span style={{ fontSize: 20 }}>🤖</span>
          <div>
            <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>AI Copilot</div>
            <div style={{ fontSize: 11, color: '#666' }}>{enabledCount} agentů | 97 nástrojů | Ctrl+K</div>
          </div>
        </div>
        <button onClick={runBriefing} disabled={loading} style={{
          padding: '6px 12px', borderRadius: 8, border: 'none', cursor: 'pointer',
          background: loading ? '#d1d5db' : '#74FB71', color: '#1a2e22',
          fontSize: 12, fontWeight: 700,
        }}>
          {loading ? 'Generuji...' : 'Denní přehled'}
        </button>
      </div>

      {/* Agent status strip */}
      <div className="flex flex-wrap gap-1 mb-2">
        {AGENTS.filter(a => config[a.id]?.enabled).map(a => (
          <span key={a.id} title={a.name} style={{
            display: 'inline-flex', alignItems: 'center', gap: 2,
            padding: '2px 6px', borderRadius: 6, fontSize: 10,
            background: '#f1faf7', border: '1px solid #d4e8e0',
          }}>
            {a.icon} <span style={{ color: '#666' }}>{a.name.split(' ')[0]}</span>
          </span>
        ))}
      </div>

      {/* Result */}
      {result && (
        <div style={{
          padding: 10, borderRadius: 8, background: '#f8fcfa',
          border: '1px solid #d4e8e0', fontSize: 12, lineHeight: 1.6,
          color: '#1a2e22', maxHeight: 200, overflow: 'auto', whiteSpace: 'pre-wrap',
        }}>
          {result}
        </div>
      )}

      {!result && !loading && (
        <div style={{ fontSize: 11, color: '#999', textAlign: 'center', padding: 8 }}>
          Klikněte "Denní přehled" nebo použijte Ctrl+K pro AI asistenta
        </div>
      )}
    </div>
  )
}
