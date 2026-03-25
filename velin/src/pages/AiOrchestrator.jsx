import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { AGENTS, loadAgentConfig, getEnabledTools, getAgentCorrections } from '../lib/aiAgents'
import { loadAutonomyRules, saveAutonomyRules, SCHEDULES, RISK_AUTO } from '../lib/aiAutonomy'
import Button from '../components/ui/Button'
import AiConfirmDialog from '../components/ai/AiConfirmDialog'
import AiAutonomyPanel from '../components/ai/AiAutonomyPanel'
import AiTestRunner from '../components/ai/AiTestRunner'
import AiTrainingPanel from '../components/ai/AiTrainingPanel'
import AiAgentSettingsPanel from '../components/ai/AiAgentSettingsPanel'
import AiAgentFindingsPanel from '../components/ai/AiAgentFindingsPanel'

export default function AiOrchestrator() {
  const [briefing, setBriefing] = useState(null)
  const [priorities, setPriorities] = useState(null)
  const [health, setHealth] = useState(null)
  const [testResults, setTestResults] = useState(null)
  const [loading, setLoading] = useState('')
  const [rules, setRules] = useState(() => loadAutonomyRules())
  const [pending, setPending] = useState(null)
  const [tab, setTab] = useState('findings')

  const config = loadAgentConfig()
  const enabledAgents = AGENTS.filter(a => config[a.id]?.enabled)

  async function callTool(toolName, input = {}) {
    setLoading(toolName)
    try {
      const { data } = await supabase.functions.invoke('ai-copilot', {
        body: {
          message: `Zavolej nástroj ${toolName} a výsledky prezentuj strukturovaně v češtině. Pokud jsou problémy, navrhni řešení.`,
          enabled_tools: [...getEnabledTools(config), 'generate_daily_briefing', 'check_agent_health', 'get_priority_queue', 'test_booking_flow', 'test_payment_flow', 'test_sos_flow', 'run_full_system_test'],
          agent_corrections: getAgentCorrections(config),
        },
      })
      return data
    } catch (e) { return { response: `Chyba: ${e.message}` } }
    finally { setLoading('') }
  }

  async function runBriefing() {
    const data = await callTool('generate_daily_briefing')
    setBriefing(data)
  }

  async function runPriorities() {
    const data = await callTool('get_priority_queue')
    setPriorities(data)
  }

  async function runHealth() {
    const data = await callTool('check_agent_health')
    setHealth(data)
  }

  async function runTest() {
    const data = await callTool('run_full_system_test')
    setTestResults(data)
  }

  function updateRule(agentId, field, value) {
    const next = { ...rules, [agentId]: { ...rules[agentId], [field]: value } }
    setRules(next)
    saveAutonomyRules(next)
  }

  const tabs = [
    { id: 'findings', label: 'Nalezy agentu', icon: '🔎' },
    { id: 'agents', label: 'Nastaveni', icon: '⚙️' },
    { id: 'briefing', label: 'Briefing', icon: '📋' },
    { id: 'priorities', label: 'Priority', icon: '🔥' },
    { id: 'health', label: 'Zdraví agentů', icon: '💚' },
    { id: 'autonomy', label: 'Autonomie', icon: '🤖' },
    { id: 'training', label: 'Trénink', icon: '🏋️' },
    { id: 'tester', label: 'Systémový test', icon: '🧪' },
    { id: 'learning', label: 'Učení & Autonomie', icon: '🎓' },
  ]

  return (
    <>
      {pending && <AiConfirmDialog actions={pending} onConfirm={() => setPending(null)} onReject={() => setPending(null)} onEdit={() => setPending(null)} />}
      <div className="mb-4">
        <h1 className="text-lg font-extrabold" style={{ color: '#0f1a14' }}>
          👔 AI Orchestrátor — Ředitel firmy
        </h1>
        <p className="text-sm" style={{ color: '#666' }}>
          {enabledAgents.length} agentů aktivních | Centrální řízení a monitoring
        </p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-4" style={{ borderBottom: '2px solid #d4e8e0', paddingBottom: 2 }}>
        {tabs.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)} style={{
            padding: '8px 14px', fontSize: 13, fontWeight: tab === t.id ? 800 : 500, borderRadius: '8px 8px 0 0',
            border: 'none', cursor: 'pointer', background: tab === t.id ? '#fff' : 'transparent',
            color: tab === t.id ? '#0f1a14' : '#666', borderBottom: tab === t.id ? '2px solid #74FB71' : 'none',
          }}>
            {t.icon} {t.label}
          </button>
        ))}
      </div>

      {/* Findings Tab */}
      {tab === 'findings' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <AiAgentFindingsPanel />
        </div>
      )}

      {/* Agent Settings Tab */}
      {tab === 'agents' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <AiAgentSettingsPanel />
        </div>
      )}

      {/* Briefing Tab */}
      {tab === 'briefing' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>Denní briefing — {new Date().toLocaleDateString('cs-CZ')}</span>
            <Button green onClick={runBriefing} disabled={!!loading} style={{ fontSize: 12, padding: '6px 14px' }}>
              {loading === 'generate_daily_briefing' ? 'Generuji...' : 'Vygenerovat briefing'}
            </Button>
          </div>
          {briefing ? (
            <div className="text-sm" style={{ lineHeight: 1.7, color: '#1a2e22', whiteSpace: 'pre-wrap' }}>
              {briefing.response || JSON.stringify(briefing, null, 2)}
            </div>
          ) : (
            <div className="text-sm" style={{ color: '#999', textAlign: 'center', padding: 40 }}>
              Klikněte na "Vygenerovat briefing" pro denní přehled celé firmy
            </div>
          )}
        </div>
      )}

      {/* Priorities Tab */}
      {tab === 'priorities' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>Fronta priorit</span>
            <Button green onClick={runPriorities} disabled={!!loading} style={{ fontSize: 12, padding: '6px 14px' }}>
              {loading ? 'Načítám...' : 'Načíst priority'}
            </Button>
          </div>
          {priorities ? (
            <div className="text-sm" style={{ lineHeight: 1.7, color: '#1a2e22', whiteSpace: 'pre-wrap' }}>
              {priorities.response || JSON.stringify(priorities, null, 2)}
            </div>
          ) : (
            <div className="text-sm" style={{ color: '#999', textAlign: 'center', padding: 40 }}>
              Klikněte pro zobrazení prioritních úkolů vyžadujících pozornost
            </div>
          )}
        </div>
      )}

      {/* Health Tab */}
      {tab === 'health' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>Zdraví AI agentů</span>
            <Button green onClick={runHealth} disabled={!!loading} style={{ fontSize: 12, padding: '6px 14px' }}>
              {loading ? 'Kontroluji...' : 'Zkontrolovat'}
            </Button>
          </div>
          <div className="grid grid-cols-3 gap-3">
            {enabledAgents.map(a => (
              <div key={a.id} style={{ padding: 10, borderRadius: 10, border: '1px solid #d4e8e0', background: '#f8fcfa' }}>
                <div className="flex items-center gap-2 mb-1">
                  <span>{a.icon}</span>
                  <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{a.name}</span>
                </div>
                <div className="text-sm" style={{ color: '#666' }}>
                  Plán: {SCHEDULES[rules[a.id]?.schedule || 'manual']?.label || 'Manuální'}
                </div>
                <div className="text-sm" style={{ color: config[a.id]?.enabled ? '#22c55e' : '#ef4444' }}>
                  {config[a.id]?.enabled ? 'Aktivní' : 'Vypnutý'}
                </div>
              </div>
            ))}
          </div>
          {health && (
            <div className="mt-3 text-sm" style={{ lineHeight: 1.7, color: '#1a2e22', whiteSpace: 'pre-wrap' }}>
              {health.response || JSON.stringify(health, null, 2)}
            </div>
          )}
        </div>
      )}

      {/* Autonomy Tab */}
      {tab === 'autonomy' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <div className="text-sm font-bold mb-3" style={{ color: '#0f1a14' }}>Pravidla autonomie pro každého agenta</div>
          <div className="space-y-2">
            {AGENTS.filter(a => config[a.id]?.enabled).map(a => {
              const r = rules[a.id] || {}
              return (
                <div key={a.id} style={{ padding: '10px 12px', borderRadius: 10, border: '1px solid #d4e8e0' }}>
                  <div className="flex items-center gap-2 mb-2">
                    <span>{a.icon}</span>
                    <span className="text-sm font-bold" style={{ color: '#0f1a14', flex: 1 }}>{a.name}</span>
                  </div>
                  <div className="flex gap-3 flex-wrap">
                    <label className="text-sm" style={{ color: '#666' }}>
                      Plán:
                      <select value={r.schedule || 'manual'} onChange={e => updateRule(a.id, 'schedule', e.target.value)}
                        style={{ marginLeft: 4, fontSize: 12, padding: '2px 6px', borderRadius: 4, border: '1px solid #d4e8e0' }}>
                        {Object.entries(SCHEDULES).map(([k, v]) => <option key={k} value={k}>{v.icon} {v.label}</option>)}
                      </select>
                    </label>
                    <label className="text-sm" style={{ color: '#666' }}>
                      Auto-confirm:
                      <select value={r.autoConfirmRisk || 'none'} onChange={e => updateRule(a.id, 'autoConfirmRisk', e.target.value)}
                        style={{ marginLeft: 4, fontSize: 12, padding: '2px 6px', borderRadius: 4, border: '1px solid #d4e8e0' }}>
                        {Object.entries(RISK_AUTO).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                      </select>
                    </label>
                  </div>
                  {r.autoTasks && (
                    <div className="mt-1 text-sm" style={{ color: '#999', fontSize: 11 }}>
                      Auto-úkoly: {r.autoTasks.join(', ')}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* Training Tab — simulator */}
      {tab === 'training' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <AiTrainingPanel />
        </div>
      )}

      {/* Tester Tab — full E2E test runner */}
      {tab === 'tester' && (
        <div className="rounded-card bg-white p-4 shadow-card">
          <AiTestRunner />
        </div>
      )}

      {/* Learning & Autonomy Tab */}
      {tab === 'learning' && <AiAutonomyPanel />}
    </>
  )
}
