import { useState, useEffect, useRef } from 'react'
import { AGENTS, loadAgentConfig, saveAgentConfig } from '../../lib/aiAgents'
import { getAgentPrompt, updateAgentPrompt, DEFAULT_PROMPTS } from '../../lib/aiAgentPrompts'
import { getAgentLearningLog, getMetrics, getAgentReadiness } from '../../lib/aiLearning'
import { getLongTermMemory, addLongTermMemory, removeLongTermMemory, clearLongTermMemory } from '../../lib/aiAgentMemory'
import { loadAutonomyRules, saveAutonomyRules, SCHEDULES, RISK_AUTO } from '../../lib/aiAutonomy'
import { useIsMobile, useMediaQuery } from '../../hooks/useIsMobile'

// Sub-component: inline tag list (situations/forbidden)
function TagList({ items, onAdd, onRemove, placeholder, color, bgColor, borderColor, icon }) {
  const [val, setVal] = useState('')
  const isMobile = useIsMobile()
  return (
    <div>
      {items.map((s, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'start', gap: 4, marginBottom: 3, padding: '4px 8px', borderRadius: 6, background: bgColor, border: `1px solid ${borderColor}`, fontSize: 11, ...(isMobile ? { fontSize: 12, alignItems: 'center', padding: '2px 2px 2px 8px' } : null) }}>
          <span style={{ marginTop: 1 }}>{icon}</span>
          <span style={{ flex: 1, color, ...(isMobile ? { minWidth: 0, overflowWrap: 'anywhere' } : null) }}>{s}</span>
          <button onClick={() => onRemove(i)} style={{ background: 'none', border: 'none', color: '#999', cursor: 'pointer', fontSize: 10, lineHeight: 1, ...(isMobile ? { fontSize: 14, minWidth: 36, minHeight: 36, flexShrink: 0 } : null) }}>x</button>
        </div>
      ))}
      <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
        <input value={val} onChange={e => setVal(e.target.value)} placeholder={placeholder}
          onKeyDown={e => { if (e.key === 'Enter' && val.trim()) { onAdd(val.trim()); setVal('') } }}
          style={{ flex: 1, fontSize: 11, padding: '4px 8px', borderRadius: 6, border: '1px solid #d4e8e0', ...(isMobile ? { minWidth: 0, padding: '8px 10px' } : null) }} />
        <button onClick={() => { if (val.trim()) { onAdd(val.trim()); setVal('') } }}
          style={{ padding: '4px 10px', borderRadius: 6, border: 'none', background: bgColor, color, cursor: 'pointer', fontSize: 11, fontWeight: 700, ...(isMobile ? { fontSize: 16, minWidth: 40, minHeight: 40 } : null) }}>+</button>
      </div>
    </div>
  )
}

// Sub-component: single agent settings card
function AgentSettingsCard({ agent, config, rules, onConfigChange, onRulesChange }) {
  const [expanded, setExpanded] = useState(false)
  const [prompt, setPrompt] = useState(() => getAgentPrompt(agent.id))
  const [editingPrompt, setEditingPrompt] = useState(false)
  const [memory, setMemory] = useState(() => getLongTermMemory(agent.id))
  const [newMem, setNewMem] = useState('')
  const [saved, setSaved] = useState(false)
  const readiness = getAgentReadiness(agent.id)
  const metrics = getMetrics()[agent.id] || { total: 0, success: 0, fail: 0, confidence: 0 }
  const isEnabled = config[agent.id]?.enabled
  const rule = rules[agent.id] || {}
  // Mobil/tablet: větší přepínač a ovládací prvky (dotyk), desktop beze změny.
  // Telefon: stav (připravenost, conf., akce) pod popisem — název a popis mají celou šířku.
  const isMobile = useIsMobile()
  const isPhone = useMediaQuery('(max-width: 767px)')
  const mob = (o) => (isMobile ? o : null)
  const readinessBadge = (
    <span style={{
      fontSize: isMobile ? 10 : 9, padding: '1px 6px', borderRadius: 8,
      background: readiness.color + '20', color: readiness.color, fontWeight: 700,
    }}>{readiness.label}</span>
  )
  const statsText = <>{metrics.confidence}% | {metrics.total} akcí</>

  function save(data) {
    const next = { ...prompt, ...data }
    setPrompt(next)
    updateAgentPrompt(agent.id, next)
    setSaved(true); setTimeout(() => setSaved(false), 1200)
  }

  function toggleEnabled() {
    const next = { ...config, [agent.id]: { ...config[agent.id], enabled: !isEnabled } }
    saveAgentConfig(next)
    onConfigChange(next)
  }

  function updateRule(field, value) {
    const next = { ...rules, [agent.id]: { ...rules[agent.id], [field]: value } }
    saveAutonomyRules(next)
    onRulesChange(next)
  }

  return (
    <div style={{
      borderRadius: 10, border: `2px solid ${isEnabled ? readiness.color : '#e5e7eb'}`,
      background: isEnabled ? '#fff' : '#fafafa', opacity: isEnabled ? 1 : 0.5,
      marginBottom: 8, overflow: 'hidden',
    }}>
      {/* Header — always visible */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px', cursor: 'pointer' }}
        onClick={() => setExpanded(!expanded)}>
        <span style={{ fontSize: 18 }}>{agent.icon}</span>
        <div style={{ flex: 1, ...mob({ minWidth: 0 }) }}>
          <div style={{ fontWeight: 800, fontSize: 13, color: '#0f1a14' }}>{agent.name}</div>
          <div style={{ fontSize: isMobile ? 11 : 10, color: '#666' }}>{agent.desc}</div>
          {isPhone && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap', marginTop: 4 }}>
              {readinessBadge}<span style={{ fontSize: 11, color: '#999' }}>{statsText}</span>
            </div>
          )}
        </div>
        {/* Quick stats */}
        {!isPhone && (
        <div style={{ textAlign: 'right', minWidth: 80, ...mob({ minWidth: 0, flexShrink: 0 }) }}>
          {readinessBadge}
          <div style={{ fontSize: isMobile ? 11 : 10, color: '#999', marginTop: 2 }}>
            {statsText}
          </div>
        </div>
        )}
        {/* Toggle */}
        <button onClick={e => { e.stopPropagation(); toggleEnabled() }} style={{
          width: 36, height: 20, borderRadius: 10, border: 'none', cursor: 'pointer',
          background: isEnabled ? '#22c55e' : '#d1d5db', position: 'relative', transition: 'background 0.2s',
          ...mob({ width: 48, height: 28, borderRadius: 14, flexShrink: 0 }),
        }}>
          <span style={{
            position: 'absolute', top: isMobile ? 3 : 2, left: isEnabled ? (isMobile ? 23 : 18) : (isMobile ? 3 : 2), width: isMobile ? 22 : 16, height: isMobile ? 22 : 16,
            borderRadius: '50%', background: '#fff', transition: 'left 0.2s', boxShadow: '0 1px 3px rgba(0,0,0,0.2)',
          }} />
        </button>
        <span style={{ fontSize: 14, color: '#999', transform: expanded ? 'rotate(180deg)' : '', transition: 'transform 0.2s' }}>
          v
        </span>
      </div>

      {/* Expanded content */}
      {expanded && (
        <div style={{ borderTop: '1px solid #d4e8e0', padding: 12 }}>
          {saved && <div style={{ fontSize: 10, color: '#22c55e', fontWeight: 600, marginBottom: 4 }}>Ulozeno</div>}

          {/* Autonomy settings row */}
          <div style={{ display: 'flex', gap: 12, marginBottom: 10, flexWrap: 'wrap' }}>
            <label style={{ fontSize: 11, color: '#666' }}>
              Plan:
              <select value={rule.schedule || 'manual'} onChange={e => updateRule('schedule', e.target.value)}
                style={{ marginLeft: 4, fontSize: 11, padding: '2px 6px', borderRadius: 4, border: '1px solid #d4e8e0', ...mob({ padding: '6px 8px', maxWidth: '100%' }) }}>
                {Object.entries(SCHEDULES).map(([k, v]) => <option key={k} value={k}>{v.icon} {v.label}</option>)}
              </select>
            </label>
            <label style={{ fontSize: 11, color: '#666' }}>
              Auto-confirm:
              <select value={rule.autoConfirmRisk || 'none'} onChange={e => updateRule('autoConfirmRisk', e.target.value)}
                style={{ marginLeft: 4, fontSize: 11, padding: '2px 6px', borderRadius: 4, border: '1px solid #d4e8e0', ...mob({ padding: '6px 8px', maxWidth: '100%' }) }}>
                {Object.entries(RISK_AUTO).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
              </select>
            </label>
          </div>

          {/* System prompt */}
          <div style={{ marginBottom: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14' }}>Systemovy prompt (zadani)</span>
              <button onClick={() => setEditingPrompt(!editingPrompt)} style={{ fontSize: 10, color: '#2563eb', background: 'none', border: 'none', cursor: 'pointer', ...mob({ fontSize: 13, minHeight: 36, padding: '0 4px 0 12px' }) }}>
                {editingPrompt ? 'Hotovo' : 'Upravit'}
              </button>
            </div>
            {editingPrompt ? (
              <textarea value={prompt.prompt || ''} onChange={e => setPrompt({ ...prompt, prompt: e.target.value })}
                onBlur={() => save({ prompt: prompt.prompt })}
                style={{ width: '100%', minHeight: 80, fontSize: 11, padding: 8, borderRadius: 6, border: '1px solid #d4e8e0', resize: 'vertical', fontFamily: 'inherit', lineHeight: 1.5 }} />
            ) : (
              <div style={{ fontSize: 11, color: '#444', padding: '6px 8px', borderRadius: 6, background: '#f8fcfa', border: '1px solid #d4e8e0', lineHeight: 1.5, maxHeight: 60, overflow: 'hidden' }}>
                {prompt.prompt || 'Zadani neni nastaveno'}
              </div>
            )}
          </div>

          {/* Situations */}
          <div style={{ marginBottom: 10 }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14', marginBottom: 4 }}>
              Situacni pravidla ({(prompt.situations || []).length})
            </div>
            <TagList
              items={prompt.situations || []}
              onAdd={s => save({ situations: [...(prompt.situations || []), s] })}
              onRemove={i => save({ situations: (prompt.situations || []).filter((_, j) => j !== i) })}
              placeholder="Kdyz nastane X, udelej Y..."
              color="#1a5c2e" bgColor="#dcfce7" borderColor="#bbf7d0" icon="O"
            />
          </div>

          {/* Forbidden */}
          <div style={{ marginBottom: 10 }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: '#dc2626', marginBottom: 4 }}>
              Zakazano ({(prompt.forbidden || []).length})
            </div>
            <TagList
              items={prompt.forbidden || []}
              onAdd={f => save({ forbidden: [...(prompt.forbidden || []), f] })}
              onRemove={i => save({ forbidden: (prompt.forbidden || []).filter((_, j) => j !== i) })}
              placeholder="Nikdy nedelej X..."
              color="#dc2626" bgColor="#fef2f2" borderColor="#fecaca" icon="X"
            />
          </div>

          {/* Must always do */}
          <div style={{ marginBottom: 10 }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: '#2563eb', marginBottom: 4 }}>
              Vzdy musi udelat ({(prompt.mustDo || []).length})
            </div>
            <TagList
              items={prompt.mustDo || []}
              onAdd={m => save({ mustDo: [...(prompt.mustDo || []), m] })}
              onRemove={i => save({ mustDo: (prompt.mustDo || []).filter((_, j) => j !== i) })}
              placeholder="Vzdy pri X udelej Y..."
              color="#1e40af" bgColor="#eff6ff" borderColor="#bfdbfe" icon="!"
            />
          </div>

          {/* Long-term memory */}
          <div>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14' }}>Pamet ({memory.length})</span>
              {memory.length > 0 && (
                <button onClick={() => { clearLongTermMemory(agent.id); setMemory([]) }}
                  style={{ fontSize: 10, color: '#dc2626', background: 'none', border: 'none', cursor: 'pointer', ...mob({ fontSize: 13, minHeight: 36, padding: '0 4px 0 12px' }) }}>Smazat vse</button>
              )}
            </div>
            {memory.slice(-5).map((m, i) => (
              <div key={i} style={{ display: 'flex', gap: 4, marginBottom: 2, fontSize: 10, color: '#666', padding: '2px 6px', borderRadius: 4, background: '#f8fcfa', ...mob({ fontSize: 12, alignItems: 'center' }) }}>
                <span style={{ flex: 1, ...mob({ minWidth: 0, overflowWrap: 'anywhere' }) }}>{m.text}</span>
                <button onClick={() => setMemory(removeLongTermMemory(agent.id, memory.length - 5 + i))}
                  style={{ background: 'none', border: 'none', color: '#999', cursor: 'pointer', fontSize: 9, ...mob({ fontSize: 14, minWidth: 36, minHeight: 36, flexShrink: 0 }) }}>x</button>
              </div>
            ))}
            <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
              <input value={newMem} onChange={e => setNewMem(e.target.value)} placeholder="Zapamatuj si..."
                onKeyDown={e => { if (e.key === 'Enter' && newMem.trim()) { setMemory(addLongTermMemory(agent.id, newMem.trim())); setNewMem('') } }}
                style={{ flex: 1, fontSize: 11, padding: '4px 8px', borderRadius: 6, border: '1px solid #d4e8e0', ...mob({ minWidth: 0, padding: '8px 10px' }) }} />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// Main component: Agent Settings Panel
export default function AiAgentSettingsPanel() {
  const [config, setConfig] = useState(() => loadAgentConfig())
  const [rules, setRules] = useState(() => loadAutonomyRules())
  const [view, setView] = useState('settings') // settings | log
  const [logAgent, setLogAgent] = useState('all')
  const [logFilter, setLogFilter] = useState('all') // all | fail | success
  const [logSearch, setLogSearch] = useState('')

  // Build combined diagnostic log from all agents
  function getDiagnosticLog() {
    const allLogs = []
    const agentIds = logAgent === 'all' ? AGENTS.map(a => a.id) : [logAgent]
    for (const id of agentIds) {
      const log = getAgentLearningLog(id)
      for (const entry of log) {
        allLogs.push({ ...entry, agentId: id })
      }
    }
    // Sort by timestamp descending
    allLogs.sort((a, b) => (b.timestamp || '').localeCompare(a.timestamp || ''))
    // Filter
    let filtered = allLogs
    if (logFilter === 'fail') filtered = filtered.filter(e => !e.success)
    if (logFilter === 'success') filtered = filtered.filter(e => e.success)
    if (logSearch) {
      const q = logSearch.toLowerCase()
      filtered = filtered.filter(e =>
        (e.action || '').toLowerCase().includes(q) ||
        (e.result_summary || '').toLowerCase().includes(q) ||
        (e.agentId || '').toLowerCase().includes(q) ||
        (e.input_summary || '').toLowerCase().includes(q)
      )
    }
    return filtered
  }

  const diagLog = view === 'log' ? getDiagnosticLog() : []
  const isMobile = useIsMobile()
  const mob = (o) => (isMobile ? o : null)

  return (
    <div>
      {/* View toggle */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 12, ...mob({ flexWrap: 'wrap' }) }}>
        <button onClick={() => setView('settings')} style={{
          padding: '8px 16px', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 12, fontWeight: 700,
          background: view === 'settings' ? '#0f1a14' : '#f1f5f9', color: view === 'settings' ? '#74FB71' : '#666',
          ...mob({ minHeight: 40, flex: '1 1 auto' }),
        }}>Nastaveni agentu</button>
        <button onClick={() => setView('log')} style={{
          padding: '8px 16px', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 12, fontWeight: 700,
          background: view === 'log' ? '#0f1a14' : '#f1f5f9', color: view === 'log' ? '#74FB71' : '#666',
          ...mob({ minHeight: 40, flex: '1 1 auto' }),
        }}>Diagnosticky log</button>
      </div>

      {/* SETTINGS VIEW */}
      {view === 'settings' && (
        <div>
          <div style={{ fontSize: 11, color: '#666', marginBottom: 8 }}>
            Kliknete na agenta pro rozkliknuti nastaveni. Kazdy agent ma: systemovy prompt, situacni pravidla, zakazane akce, povinne akce a pamet.
          </div>
          {AGENTS.map(a => (
            <AgentSettingsCard
              key={a.id}
              agent={a}
              config={config}
              rules={rules}
              onConfigChange={setConfig}
              onRulesChange={setRules}
            />
          ))}
        </div>
      )}

      {/* DIAGNOSTIC LOG VIEW */}
      {view === 'log' && (
        <div>
          {/* Filters */}
          <div style={{ display: 'flex', gap: 8, marginBottom: 10, flexWrap: 'wrap', alignItems: 'center' }}>
            <select value={logAgent} onChange={e => setLogAgent(e.target.value)}
              style={{ fontSize: 11, padding: '4px 8px', borderRadius: 6, border: '1px solid #d4e8e0', ...mob({ padding: '8px 10px', maxWidth: '100%', flex: '1 1 140px' }) }}>
              <option value="all">Vsichni agenti</option>
              {AGENTS.map(a => <option key={a.id} value={a.id}>{a.icon} {a.name}</option>)}
            </select>
            <select value={logFilter} onChange={e => setLogFilter(e.target.value)}
              style={{ fontSize: 11, padding: '4px 8px', borderRadius: 6, border: '1px solid #d4e8e0', ...mob({ padding: '8px 10px', maxWidth: '100%', flex: '1 1 140px' }) }}>
              <option value="all">Vse</option>
              <option value="fail">Jen chyby</option>
              <option value="success">Jen uspech</option>
            </select>
            <input value={logSearch} onChange={e => setLogSearch(e.target.value)} placeholder="Hledat v logu..."
              style={{ flex: 1, minWidth: 120, fontSize: 11, padding: '4px 8px', borderRadius: 6, border: '1px solid #d4e8e0', ...mob({ padding: '8px 10px', flex: '1 1 100%' }) }} />
            <span style={{ fontSize: 10, color: '#999' }}>{diagLog.length} zaznamu</span>
          </div>

          {/* Log entries */}
          <div style={{ maxHeight: isMobile ? 'none' : 600, overflow: 'auto' }}>
            {diagLog.length === 0 && (
              <div style={{ textAlign: 'center', padding: 30, color: '#999', fontSize: 12 }}>
                Žádné záznamy. Spusťte trénink nebo použijte agenty pro generování dat.
              </div>
            )}
            {diagLog.slice(0, 200).map((entry, i) => {
              const agent = AGENTS.find(a => a.id === entry.agentId)
              return (
                <div key={i} style={{
                  display: 'flex', gap: 8, padding: '6px 10px', marginBottom: 2,
                  borderRadius: 6, fontSize: 11, ...mob({ fontSize: 12, gap: 6 }),
                  background: entry.success ? '#f8fcfa' : '#fef2f2',
                  border: `1px solid ${entry.success ? '#d4e8e0' : '#fecaca'}`,
                }}>
                  {/* Status */}
                  <span style={{ fontSize: 14, lineHeight: 1 }}>{entry.success ? 'V' : 'X'}</span>
                  {/* Agent */}
                  <span style={{ minWidth: 22, fontSize: 14 }}>{agent?.icon || '?'}</span>
                  {/* Content */}
                  <div style={{ flex: 1, ...mob({ minWidth: 0, overflowWrap: 'anywhere' }) }}>
                    <div style={{ fontWeight: 600, color: '#0f1a14' }}>
                      <span style={{ color: '#666', fontWeight: 400 }}>[{entry.agentId}]</span> {entry.action}
                    </div>
                    {entry.result_summary && entry.result_summary !== 'ok' && (
                      <div style={{ color: entry.success ? '#666' : '#dc2626', fontSize: isMobile ? 11 : 10, marginTop: 1 }}>
                        {entry.result_summary}
                      </div>
                    )}
                    {entry.input_summary && (
                      <div style={{ color: '#999', fontSize: isMobile ? 11 : 10 }}>
                        Input: {entry.input_summary}
                      </div>
                    )}
                    {entry.feedback && (
                      <div style={{ color: '#7c3aed', fontSize: isMobile ? 11 : 10, fontStyle: 'italic' }}>
                        Feedback: {entry.feedback}
                      </div>
                    )}
                  </div>
                  {/* Timestamp */}
                  <div style={{ fontSize: isMobile ? 11 : 9, color: '#999', minWidth: 60, textAlign: 'right', whiteSpace: 'nowrap' }}>
                    {entry.timestamp ? new Date(entry.timestamp).toLocaleString('cs-CZ', { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'numeric' }) : ''}
                  </div>
                </div>
              )
            })}
            {diagLog.length > 200 && (
              <div style={{ textAlign: 'center', padding: 8, color: '#999', fontSize: 10 }}>
                Zobrazeno 200 z {diagLog.length} zaznamu
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
