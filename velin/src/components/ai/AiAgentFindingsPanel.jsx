// Agent Findings Dashboard — shows what each agent found during training
import { useState, useEffect } from 'react'
import { AGENTS } from '../../lib/aiAgents'
import { getAgentLearningLog, getMetrics } from '../../lib/aiLearning'

const SEVERITY_STYLE = {
  ok: { bg: '#dcfce7', color: '#166534', label: 'OK' },
  fail: { bg: '#fef2f2', color: '#dc2626', label: 'PROBLEM' },
  warn: { bg: '#fef3c7', color: '#92400e', label: 'POZOR' },
  info: { bg: '#eff6ff', color: '#1e40af', label: 'INFO' },
}

function classifyFinding(entry) {
  if (!entry.success) return 'fail'
  if (entry.action?.includes('alert_') || entry.action?.includes('inconsistency_')) return 'fail'
  if (entry.action?.includes('detect_') || entry.action?.includes('anomaly_')) return 'warn'
  if (entry.action?.includes('verify_') || entry.action?.includes('check_')) return 'ok'
  return 'info'
}

function getAgentFindings(agentId) {
  const log = getAgentLearningLog(agentId)
  const findings = []
  for (const entry of log) {
    const sev = classifyFinding(entry)
    if (sev === 'fail' || sev === 'warn') {
      findings.push({ ...entry, severity: sev })
    }
  }
  return findings
}

function formatFinding(entry) {
  const parts = [entry.action?.replace(/_/g, ' ')]
  const s = entry.result_summary
  if (s && s !== 'ok') parts.push(s)
  return parts.filter(Boolean).join(' — ')
}

export default function AiAgentFindingsPanel() {
  const [selectedAgent, setSelectedAgent] = useState('all')
  const [showOk, setShowOk] = useState(false)
  const metrics = getMetrics()

  // Build findings for all agents
  const allFindings = []
  for (const a of AGENTS) {
    const log = getAgentLearningLog(a.id)
    for (const entry of log) {
      const sev = classifyFinding(entry)
      allFindings.push({ ...entry, agentId: a.id, severity: sev })
    }
  }

  // Filter
  let filtered = allFindings
  if (selectedAgent !== 'all') filtered = filtered.filter(f => f.agentId === selectedAgent)
  if (!showOk) filtered = filtered.filter(f => f.severity !== 'ok' && f.severity !== 'info')
  filtered.sort((a, b) => {
    const sevOrder = { fail: 0, warn: 1, info: 2, ok: 3 }
    return (sevOrder[a.severity] || 9) - (sevOrder[b.severity] || 9)
  })

  // Summary per agent
  const agentSummary = {}
  for (const a of AGENTS) {
    const findings = getAgentFindings(a.id)
    const m = metrics[a.id]
    agentSummary[a.id] = {
      problems: findings.filter(f => f.severity === 'fail').length,
      warnings: findings.filter(f => f.severity === 'warn').length,
      total: m?.total || 0,
      confidence: m?.confidence || 0,
    }
  }

  const totalProblems = Object.values(agentSummary).reduce((s, a) => s + a.problems, 0)
  const totalWarnings = Object.values(agentSummary).reduce((s, a) => s + a.warnings, 0)

  return (
    <div>
      {/* Summary bar */}
      <div style={{
        padding: '12px 16px', borderRadius: 12, marginBottom: 12,
        background: totalProblems > 0 ? '#fef2f2' : totalWarnings > 0 ? '#fef3c7' : '#dcfce7',
        border: `2px solid ${totalProblems > 0 ? '#ef4444' : totalWarnings > 0 ? '#f59e0b' : '#22c55e'}`,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div>
          <div style={{ fontWeight: 800, fontSize: 14, color: '#0f1a14' }}>
            {totalProblems} problemu | {totalWarnings} varovani | {allFindings.length} celkem kontrol
          </div>
          <div style={{ fontSize: 11, color: '#666' }}>
            Nalezy z posledniho treninku vsech {AGENTS.length} agentu
          </div>
        </div>
        <label style={{ fontSize: 11, display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
          <input type="checkbox" checked={showOk} onChange={e => setShowOk(e.target.checked)} />
          Ukazat i OK
        </label>
      </div>

      {/* Agent filter */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 10, flexWrap: 'wrap' }}>
        <button onClick={() => setSelectedAgent('all')} style={{
          padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: selectedAgent === 'all' ? 700 : 400,
          border: selectedAgent === 'all' ? '2px solid #0f1a14' : '1px solid #e5e7eb',
          background: selectedAgent === 'all' ? '#0f1a14' : '#fff', color: selectedAgent === 'all' ? '#74FB71' : '#666', cursor: 'pointer',
        }}>Vsichni ({totalProblems + totalWarnings})</button>
        {AGENTS.map(a => {
          const s = agentSummary[a.id]
          const hasIssues = s.problems > 0 || s.warnings > 0
          return (
            <button key={a.id} onClick={() => setSelectedAgent(a.id)} style={{
              padding: '4px 8px', borderRadius: 6, fontSize: 11, cursor: 'pointer',
              fontWeight: selectedAgent === a.id ? 700 : 400,
              border: selectedAgent === a.id ? '2px solid #0f1a14' : `1px solid ${hasIssues ? '#fecaca' : '#e5e7eb'}`,
              background: selectedAgent === a.id ? '#0f1a14' : hasIssues ? '#fef2f2' : '#fff',
              color: selectedAgent === a.id ? '#74FB71' : hasIssues ? '#dc2626' : '#666',
            }}>{a.icon} {s.problems > 0 ? s.problems : s.warnings > 0 ? s.warnings : 'ok'}</button>
          )
        })}
      </div>

      {/* Agent summary cards */}
      {selectedAgent === 'all' && (
        <div className="grid grid-cols-3 gap-2" style={{ marginBottom: 12 }}>
          {AGENTS.map(a => {
            const s = agentSummary[a.id]
            return (
              <div key={a.id} onClick={() => setSelectedAgent(a.id)}
                style={{
                  padding: '8px 10px', borderRadius: 8, cursor: 'pointer',
                  border: `1px solid ${s.problems ? '#fecaca' : s.warnings ? '#fde68a' : '#d4e8e0'}`,
                  background: s.problems ? '#fef2f2' : s.warnings ? '#fef3c7' : '#f8fcfa',
                }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginBottom: 2 }}>
                  <span style={{ fontSize: 14 }}>{a.icon}</span>
                  <span style={{ fontWeight: 700, fontSize: 11, color: '#0f1a14', flex: 1 }}>{a.name}</span>
                </div>
                <div style={{ fontSize: 10, color: '#666' }}>
                  {s.total} kontrol | {s.confidence}% conf
                </div>
                {s.problems > 0 && <div style={{ fontSize: 10, color: '#dc2626', fontWeight: 700 }}>{s.problems} problemu</div>}
                {s.warnings > 0 && <div style={{ fontSize: 10, color: '#92400e', fontWeight: 700 }}>{s.warnings} varovani</div>}
                {!s.problems && !s.warnings && s.total > 0 && <div style={{ fontSize: 10, color: '#22c55e' }}>Vse OK</div>}
                {!s.total && <div style={{ fontSize: 10, color: '#999' }}>Netrenovan</div>}
              </div>
            )
          })}
        </div>
      )}

      {/* Findings list */}
      <div style={{ maxHeight: 500, overflow: 'auto' }}>
        {filtered.length === 0 && (
          <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
            {showOk ? 'Zadne zaznamy. Spustte trenink.' : 'Zadne problemy nalezeny. Prepnete "Ukazat i OK" pro vsechny kontroly.'}
          </div>
        )}
        {filtered.map((f, i) => {
          const agent = AGENTS.find(a => a.id === f.agentId)
          const sev = SEVERITY_STYLE[f.severity] || SEVERITY_STYLE.info
          return (
            <div key={i} style={{
              display: 'flex', gap: 8, padding: '6px 10px', marginBottom: 2,
              borderRadius: 6, fontSize: 11, background: sev.bg,
              border: `1px solid ${sev.color}22`,
            }}>
              <span style={{
                fontSize: 9, padding: '1px 5px', borderRadius: 4, fontWeight: 700,
                background: sev.color, color: '#fff', minWidth: 50, textAlign: 'center', alignSelf: 'start', marginTop: 1,
              }}>{sev.label}</span>
              <span style={{ fontSize: 14 }}>{agent?.icon}</span>
              <div style={{ flex: 1 }}>
                <span style={{ fontWeight: 600, color: '#0f1a14' }}>{formatFinding(f)}</span>
                {f.timestamp && (
                  <span style={{ fontSize: 9, color: '#999', marginLeft: 8 }}>
                    {new Date(f.timestamp).toLocaleString('cs-CZ', { hour: '2-digit', minute: '2-digit' })}
                  </span>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
