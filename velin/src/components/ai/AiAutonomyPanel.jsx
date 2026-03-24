import { useState, useEffect } from 'react'
import { AGENTS, loadAgentConfig, saveAgentConfig } from '../../lib/aiAgents'
import { getMetrics, getAgentReadiness, calculateAutonomyScore, analyzeFailurePatterns, generatePromptSuggestions } from '../../lib/aiLearning'
import { loadAutonomyRules, SCHEDULES, RISK_AUTO } from '../../lib/aiAutonomy'
import Button from '../ui/Button'

export default function AiAutonomyPanel() {
  const [config, setConfig] = useState(() => loadAgentConfig())
  const [metrics, setMetrics] = useState(() => getMetrics())
  const [autonomy, setAutonomy] = useState(() => calculateAutonomyScore())
  const [selectedAgent, setSelectedAgent] = useState(null)
  const [analysis, setAnalysis] = useState(null)
  const rules = loadAutonomyRules()

  function refresh() {
    setMetrics(getMetrics())
    setAutonomy(calculateAutonomyScore())
  }

  function emergencyStop() {
    if (!confirm('NOUZOVÉ ZASTAVENÍ — všichni agenti budou vypnuti. Pokračovat?')) return
    const next = { ...config }
    for (const a of AGENTS) next[a.id] = { ...next[a.id], enabled: false, autoConfirm: false }
    saveAgentConfig(next)
    setConfig(next)
    alert('Všichni agenti zastaveni.')
  }

  function enableAll() {
    const next = { ...config }
    for (const a of AGENTS) next[a.id] = { ...next[a.id], enabled: true }
    saveAgentConfig(next)
    setConfig(next)
    refresh()
  }

  function showAnalysis(agentId) {
    setSelectedAgent(agentId)
    setAnalysis({
      failures: analyzeFailurePatterns(agentId),
      suggestions: generatePromptSuggestions(agentId),
    })
  }

  const enabledCount = AGENTS.filter(a => config[a.id]?.enabled).length

  return (
    <div>
      {/* Global status bar */}
      <div style={{
        padding: '12px 16px', borderRadius: 12, marginBottom: 12,
        background: autonomy.score >= 80 ? '#dcfce7' : autonomy.score >= 50 ? '#fef3c7' : '#fee2e2',
        border: '2px solid ' + (autonomy.score >= 80 ? '#22c55e' : autonomy.score >= 50 ? '#f59e0b' : '#ef4444'),
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div>
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
            Autonomie: {autonomy.score}% — {autonomy.level}
          </div>
          <div style={{ fontSize: 11, color: '#666' }}>
            {enabledCount}/{AGENTS.length} agentů | Cíl: 95%+ pro plný autonomní provoz
          </div>
        </div>
        <div className="flex gap-2">
          <Button onClick={enableAll} style={{ fontSize: 11, padding: '4px 10px', background: '#dcfce7', border: '1px solid #22c55e', borderRadius: 6 }}>
            Zapnout vše
          </Button>
          <Button onClick={emergencyStop} style={{ fontSize: 11, padding: '4px 10px', background: '#fee2e2', color: '#dc2626', border: '1px solid #ef4444', borderRadius: 6 }}>
            NOUZOVÉ ZASTAVENÍ
          </Button>
        </div>
      </div>

      {/* Autonomy progress bar */}
      <div style={{ marginBottom: 16 }}>
        <div style={{ height: 8, background: '#e5e7eb', borderRadius: 4, overflow: 'hidden' }}>
          <div style={{ height: '100%', width: `${autonomy.score}%`, background: autonomy.score >= 80 ? '#22c55e' : autonomy.score >= 50 ? '#f59e0b' : '#ef4444', borderRadius: 4, transition: 'width 0.5s' }} />
        </div>
        <div className="flex justify-between mt-1" style={{ fontSize: 10, color: '#999' }}>
          <span>0% Manuální</span><span>50% Asistovaný</span><span>80% Dohled</span><span>95%+ Autonomní</span>
        </div>
      </div>

      {/* Agent cards */}
      <div className="grid grid-cols-2 gap-2">
        {AGENTS.map(a => {
          const m = metrics[a.id] || { total: 0, success: 0, confidence: 0 }
          const readiness = getAgentReadiness(a.id)
          const isOn = config[a.id]?.enabled
          const rule = rules[a.id] || {}

          return (
            <div key={a.id} onClick={() => showAnalysis(a.id)} style={{
              padding: '10px 12px', borderRadius: 10, cursor: 'pointer',
              border: '2px solid ' + (isOn ? readiness.color : '#e5e7eb'),
              background: isOn ? '#fff' : '#fafafa', opacity: isOn ? 1 : 0.6,
              transition: 'border-color 0.2s',
            }}>
              <div className="flex items-center gap-2 mb-1">
                <span style={{ fontSize: 16 }}>{a.icon}</span>
                <span className="text-sm font-bold" style={{ color: '#0f1a14', flex: 1, fontSize: 11 }}>{a.name}</span>
                <span style={{
                  fontSize: 9, padding: '1px 6px', borderRadius: 8,
                  background: readiness.color + '20', color: readiness.color, fontWeight: 700,
                }}>
                  {readiness.label}
                </span>
              </div>
              {/* Progress bar */}
              <div style={{ height: 4, background: '#e5e7eb', borderRadius: 2, marginBottom: 4 }}>
                <div style={{ height: '100%', width: `${m.confidence}%`, background: readiness.color, borderRadius: 2 }} />
              </div>
              <div className="flex justify-between" style={{ fontSize: 10, color: '#999' }}>
                <span>{m.confidence}% conf.</span>
                <span>{m.total} akcí</span>
                <span>{SCHEDULES[rule.schedule]?.icon || '✋'} {RISK_AUTO[rule.autoConfirmRisk]?.label?.slice(0, 8) || 'Manuál'}</span>
              </div>
            </div>
          )
        })}
      </div>

      {/* Analysis detail */}
      {selectedAgent && analysis && (
        <div style={{ marginTop: 12, padding: 12, borderRadius: 10, background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>
              Analýza: {AGENTS.find(a => a.id === selectedAgent)?.name}
            </span>
            <button onClick={() => setSelectedAgent(null)} style={{ fontSize: 12, background: 'none', border: 'none', cursor: 'pointer', color: '#999' }}>✕</button>
          </div>

          {/* Failure patterns */}
          {analysis.failures.patterns.length > 0 && (
            <div style={{ marginBottom: 8 }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: '#dc2626', marginBottom: 4 }}>Vzorce selhání:</div>
              {analysis.failures.patterns.map((p, i) => (
                <div key={i} style={{ fontSize: 11, color: '#666', padding: '2px 0' }}>
                  {p.action}: {p.fail_count}× ({p.pct}%)
                </div>
              ))}
            </div>
          )}

          {/* Suggestions */}
          {analysis.suggestions.length > 0 && (
            <div>
              <div style={{ fontSize: 11, fontWeight: 700, color: '#2563eb', marginBottom: 4 }}>Návrhy na zlepšení:</div>
              {analysis.suggestions.map((s, i) => (
                <div key={i} style={{
                  fontSize: 11, color: '#1a2e22', padding: '4px 8px', marginBottom: 3,
                  borderRadius: 4, background: s.type === 'warning' ? '#fef3c7' : s.type === 'forbidden' ? '#fee2e2' : '#eff6ff',
                  border: '1px solid ' + (s.type === 'warning' ? '#fde68a' : s.type === 'forbidden' ? '#fecaca' : '#bfdbfe'),
                }}>
                  {s.text}
                  {s.suggestedRule && (
                    <div style={{ fontSize: 10, color: '#666', marginTop: 2 }}>
                      Navrhované pravidlo: "{s.suggestedRule}"
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}

          {analysis.failures.patterns.length === 0 && analysis.suggestions.length === 0 && (
            <div style={{ fontSize: 12, color: '#22c55e', textAlign: 'center', padding: 8 }}>
              Agent pracuje bez problémů. Žádné návrhy na úpravu.
            </div>
          )}
        </div>
      )}
    </div>
  )
}
