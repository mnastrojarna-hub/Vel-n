import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { loadAgentConfig, getEnabledTools, getAgentCorrections, AGENTS } from '../../lib/aiAgents'
import { buildAgentPromptsText } from '../../lib/aiAgentPrompts'
import { buildAllAgentMemory } from '../../lib/aiAgentMemory'
import { recordOutcome } from '../../lib/aiLearning'
import { getAuditLog, analyzeMissingFeatures } from '../../lib/aiVelinAuditor'
import Button from '../ui/Button'
import { AppFlowView, AuditView, SuggestionsView } from './AiTestRunnerViews'

const APP_URL = 'https://motogo24.cz'
const TEST_STEPS = [
  { id: 'setup', label: 'Příprava testovacích dat', icon: '🔧', tools: ['create_test_user', 'create_test_promo'] },
  { id: 'consistency', label: 'Kontrola konzistence dat', icon: '🔍', tools: ['verify_app_consistency'] },
  { id: 'edge_fn', label: 'Kontrola Edge Functions', icon: '⚡', tools: ['check_edge_functions'] },
  { id: 'booking_flow', label: 'Test booking flow', icon: '📅', tools: ['test_booking_flow'] },
  { id: 'payment_flow', label: 'Test platební flow', icon: '💳', tools: ['test_payment_flow'] },
  { id: 'sos_flow', label: 'Test SOS flow', icon: '🚨', tools: ['test_sos_flow'] },
  { id: 'system_test', label: 'Kompletní systémový test', icon: '🔬', tools: ['run_full_system_test'] },
  { id: 'e2e_report', label: 'E2E report zákaznické app', icon: '📋', tools: ['generate_e2e_report'] },
  { id: 'cleanup', label: 'Úklid testovacích dat', icon: '🧹', tools: ['cleanup_test_data'] },
]

export default function AiTestRunner() {
  const [view, setView] = useState('audit')
  const [results, setResults] = useState({})
  const [running, setRunning] = useState(null)
  const [testUser, setTestUser] = useState(null)
  const [testPromo, setTestPromo] = useState(null)
  const [appFlowResults, setAppFlowResults] = useState(null)
  const [appFlowRunning, setAppFlowRunning] = useState(false)
  const [appFlowProgress, setAppFlowProgress] = useState(null)
  const [suggestions, setSuggestions] = useState([])
  const [auditLog, setAuditLog] = useState(() => getAuditLog())

  const { runAppFlowTest, exportAppFlowMarkdown } = require('../../lib/aiAppFlowTest')

  async function runAppFlow() {
    setAppFlowRunning(true)
    const results = await runAppFlowTest((p) => setAppFlowProgress(p))
    setAppFlowResults(results)
    setAppFlowRunning(false)
    setAppFlowProgress(null)
  }

  async function runStep(step) {
    setRunning(step.id)
    const config = loadAgentConfig()
    const enabledIds = AGENTS.filter(a => config[a.id]?.enabled).map(a => a.id)
    try {
      const { data } = await supabase.functions.invoke('ai-copilot', {
        body: { message: `Spusť test: ${step.label}. Zavolej nástroje: ${step.tools.join(', ')}. Výsledky prezentuj strukturovaně.`, enabled_tools: [...getEnabledTools(config), ...step.tools], agent_corrections: getAgentCorrections(config), agent_prompts: buildAgentPromptsText(enabledIds), agent_memory: buildAllAgentMemory(enabledIds) },
      })
      const result = { response: data?.response, status: 'done', timestamp: new Date().toISOString() }
      setResults(r => ({ ...r, [step.id]: result }))
      if (step.id === 'setup' && data?.response) { const emailMatch = data.response.match(/test\.ai\.tester\+[^@]+@motogo24\.cz/); const promoMatch = data.response.match(/AITEST_[A-Z0-9]+/); if (emailMatch) setTestUser(emailMatch[0]); if (promoMatch) setTestPromo(promoMatch[0]) }
      recordOutcome('tester', step.id, {}, result, true)
    } catch (e) { setResults(r => ({ ...r, [step.id]: { status: 'error', error: e.message } })); recordOutcome('tester', step.id, {}, { error: e.message }, false) }
    setRunning(null)
  }

  async function runAllE2E() { for (const step of TEST_STEPS) await runStep(step) }

  const doneCount = Object.keys(results).length
  const passCount = Object.values(results).filter(r => r.status === 'done').length

  return (
    <div>
      <div style={{ display: 'flex', gap: 4, marginBottom: 12 }}>
        {[{ id: 'appflow', label: 'App flow', icon: '📱' }, { id: 'audit', label: 'Audit velínu', icon: '🔍' }, { id: 'e2e', label: 'E2E testy', icon: '🧪' }, { id: 'log', label: 'Návrhy oprav', icon: '💡' }].map(v => (
          <button key={v.id} onClick={() => setView(v.id)} style={{ padding: '8px 14px', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 12, fontWeight: 700, background: view === v.id ? '#0f1a14' : '#f1f5f9', color: view === v.id ? '#74FB71' : '#666' }}>{v.icon} {v.label}</button>
        ))}
      </div>

      {view === 'appflow' && <AppFlowView appFlowResults={appFlowResults} appFlowRunning={appFlowRunning} appFlowProgress={appFlowProgress} runAppFlow={runAppFlow} />}
      {view === 'audit' && <AuditView auditLog={auditLog} />}

      {view === 'e2e' && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <div><div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>E2E Test Runner</div><div style={{ fontSize: 11, color: '#666' }}>{doneCount}/{TEST_STEPS.length} kroků | {passCount} úspěšných</div></div>
            <Button green onClick={runAllE2E} disabled={!!running} style={{ fontSize: 12, padding: '6px 14px' }}>{running ? 'Běží...' : 'Spustit vše'}</Button>
          </div>
          {(testUser || testPromo) && (<div style={{ padding: '8px 12px', borderRadius: 8, background: '#eff6ff', border: '1px solid #bfdbfe', marginBottom: 8, fontSize: 12 }}>{testUser && <div><strong>Test účet:</strong> {testUser}</div>}{testPromo && <div><strong>100% promo:</strong> {testPromo}</div>}<a href={APP_URL} target="_blank" rel="noopener noreferrer" style={{ color: '#2563eb', textDecoration: 'underline', fontSize: 11 }}>Otevřít MotoGo24 App</a></div>)}
          <div style={{ marginBottom: 8, padding: '8px 12px', borderRadius: 8, background: '#f8fcfa', border: '1px solid #d4e8e0' }}>
            <div style={{ fontSize: 11, fontWeight: 700, marginBottom: 4, color: '#0f1a14' }}>Manuální testy v prohlížeči:</div>
            <div className="flex flex-wrap gap-2">
              {[{ label: 'Registrace', url: `${APP_URL}/#register` }, { label: 'Přihlášení', url: `${APP_URL}/#login` }, { label: 'Reset hesla', url: `${APP_URL}/#reset` }, { label: 'Katalog', url: `${APP_URL}/#catalog` }, { label: 'Rezervace', url: `${APP_URL}/#booking` }, { label: 'E-shop', url: `${APP_URL}/#shop` }, { label: 'Profil', url: `${APP_URL}/#profile` }].map(l => (<a key={l.label} href={l.url} target="_blank" rel="noopener noreferrer" style={{ fontSize: 10, padding: '3px 8px', borderRadius: 4, background: '#fff', border: '1px solid #d4e8e0', color: '#2563eb', textDecoration: 'none' }}>{l.label}</a>))}
            </div>
          </div>
          <div className="space-y-2">
            {TEST_STEPS.map(step => { const result = results[step.id]; const isRunning = running === step.id; return (
              <div key={step.id} style={{ padding: '10px 12px', borderRadius: 10, border: '1px solid ' + (result?.status === 'done' ? '#22c55e' : result?.status === 'error' ? '#ef4444' : '#d4e8e0'), background: result?.status === 'done' ? '#f0fdf4' : result?.status === 'error' ? '#fef2f2' : '#fff' }}>
                <div className="flex items-center gap-2"><span style={{ fontSize: 14 }}>{step.icon}</span><span className="text-sm font-bold" style={{ color: '#0f1a14', flex: 1 }}>{step.label}</span>{result?.status === 'done' && <span style={{ fontSize: 12, color: '#22c55e' }}>OK</span>}{result?.status === 'error' && <span style={{ fontSize: 12, color: '#ef4444' }}>X</span>}<Button onClick={() => runStep(step)} disabled={!!running} style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, background: '#f1faf7', border: '1px solid #d4e8e0' }}>{isRunning ? '...' : 'Spustit'}</Button></div>
                {result?.response && <div style={{ marginTop: 6, fontSize: 11, color: '#1a2e22', lineHeight: 1.5, maxHeight: 150, overflow: 'auto', whiteSpace: 'pre-wrap', background: '#f8fcfa', padding: 8, borderRadius: 6 }}>{result.response}</div>}
                {result?.error && <div style={{ marginTop: 4, fontSize: 11, color: '#dc2626' }}>Chyba: {result.error}</div>}
              </div>
            ) })}
          </div>
        </div>
      )}

      {view === 'log' && <SuggestionsView auditLog={auditLog} suggestions={suggestions} />}
    </div>
  )
}
