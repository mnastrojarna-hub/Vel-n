import { useState, useRef } from 'react'
import { getAllScenarios } from '../../lib/aiTrainingScenarios'
import { runScenario, runAllScenarios, cleanupSimData, getTrainingState, resetTrainingState } from '../../lib/aiTrainingEngine'
import { calculateAutonomyScore, getAgentReadiness } from '../../lib/aiLearning'
import { AGENTS } from '../../lib/aiAgents'
import Button from '../ui/Button'

export default function AiTrainingPanel() {
  const scenarios = getAllScenarios()
  const [running, setRunning] = useState(false)
  const [progress, setProgress] = useState(null)
  const [results, setResults] = useState([])
  const [log, setLog] = useState([])
  const [state] = useState(() => getTrainingState())
  const [cleaning, setCleaning] = useState(false)
  const stopRef = useRef(false)

  const autonomy = calculateAutonomyScore()

  function addLog(text) {
    setLog(l => [...l.slice(-50), { text, time: new Date().toLocaleTimeString('cs-CZ') }])
  }

  async function handleRunAll() {
    setRunning(true); stopRef.current = false; setResults([]); setLog([])
    addLog('Spouštím kompletní trénink — všechny scénáře')
    try {
      const res = await runAllScenarios(scenarios, (p) => {
        setProgress(p)
        if (p.phase === 'scenario_start') addLog(`▶ ${p.scenario.icon} ${p.scenario.name}`)
        if (p.phase === 'step_done') addLog(`  ${p.result.success ? '✓' : '✗'} Krok ${p.step + 1}/${p.total}`)
        if (p.phase === 'scenario_done') addLog(`  = ${p.result.passed}/${p.result.total} úspěšných`)
      })
      setResults(res)
      addLog(`Trénink dokončen: ${res.reduce((a, r) => a + r.passed, 0)}/${res.reduce((a, r) => a + r.total, 0)} kroků`)
    } catch (e) { addLog(`Chyba: ${e.message}`) }
    setRunning(false); setProgress(null)
  }

  async function handleRunOne(scenario) {
    setRunning(true); setLog([])
    addLog(`▶ ${scenario.icon} ${scenario.name}`)
    try {
      const res = await runScenario(scenario, (p) => {
        setProgress(p)
        if (p.phase === 'step_done') addLog(`  ${p.result.success ? '✓' : '✗'} Krok ${p.step + 1}/${p.total}`)
      })
      setResults([res])
      addLog(`Hotovo: ${res.passed}/${res.total}`)
    } catch (e) { addLog(`Chyba: ${e.message}`) }
    setRunning(false); setProgress(null)
  }

  async function handleCleanup() {
    setCleaning(true); addLog('Mažu testovací data...')
    const res = await cleanupSimData()
    addLog(res.success ? 'Testovací data smazána' : `Chyba: ${res.error}`)
    setCleaning(false)
  }

  const totalPassed = results.reduce((a, r) => a + r.passed, 0)
  const totalSteps = results.reduce((a, r) => a + r.total, 0)

  return (
    <div>
      {/* Status bar */}
      <div style={{ padding: '10px 14px', borderRadius: 10, marginBottom: 10,
        background: autonomy.score >= 80 ? '#dcfce7' : '#fef3c7',
        border: '1px solid ' + (autonomy.score >= 80 ? '#22c55e' : '#f59e0b') }}>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>
              Trénink agentů — Autonomie: {autonomy.score}%
            </div>
            <div style={{ fontSize: 11, color: '#666' }}>
              {scenarios.length} scénářů | Simulace reálných zákaznických procesů
            </div>
          </div>
          <div className="flex gap-2">
            <Button green onClick={handleRunAll} disabled={running} style={{ fontSize: 12, padding: '6px 14px' }}>
              {running ? `Běží... ${progress?.phase === 'running' ? `(${progress.step + 1}/${progress.total})` : ''}` : 'Spustit vše'}
            </Button>
            <Button onClick={handleCleanup} disabled={cleaning || running} style={{
              fontSize: 11, padding: '4px 10px', background: '#fee2e2', border: '1px solid #fca5a5', borderRadius: 6 }}>
              {cleaning ? '...' : 'Smazat test data'}
            </Button>
          </div>
        </div>
      </div>

      {/* Results summary */}
      {results.length > 0 && (
        <div style={{ padding: 10, borderRadius: 8, background: '#f0fdf4', border: '1px solid #bbf7d0', marginBottom: 10, fontSize: 12 }}>
          Výsledek: <strong>{totalPassed}/{totalSteps}</strong> kroků úspěšných ({totalSteps > 0 ? Math.round(totalPassed / totalSteps * 100) : 0}%)
        </div>
      )}

      {/* Scenarios grid */}
      <div className="grid grid-cols-3 gap-2 mb-3">
        {scenarios.map(s => {
          const st = state[s.id]
          return (
            <div key={s.id} style={{
              padding: '10px 12px', borderRadius: 10,
              border: '1px solid ' + (st?.runs ? '#22c55e' : '#d4e8e0'),
              background: st?.runs ? '#f0fdf4' : '#fff',
            }}>
              <div className="flex items-center gap-2 mb-1">
                <span style={{ fontSize: 16 }}>{s.icon}</span>
                <span className="text-sm font-bold" style={{ color: '#0f1a14', flex: 1, fontSize: 11 }}>{s.name}</span>
              </div>
              <div style={{ fontSize: 10, color: '#666', marginBottom: 4 }}>
                Agenti: {s.agents.join(', ')}
              </div>
              {st?.runs && (
                <div style={{ fontSize: 10, color: '#22c55e' }}>
                  {st.runs}× běh | {st.totalPassed}/{st.totalSteps} OK
                </div>
              )}
              <Button onClick={() => handleRunOne(s)} disabled={running} style={{
                marginTop: 4, fontSize: 10, padding: '3px 8px', width: '100%',
                background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6 }}>
                {running && progress?.scenarioId === s.id ? '...' : 'Spustit'}
              </Button>
            </div>
          )
        })}
      </div>

      {/* Agent readiness after training */}
      <div style={{ marginBottom: 10 }}>
        <div style={{ fontSize: 11, fontWeight: 700, color: '#0f1a14', marginBottom: 4 }}>Stav agentů po tréninku:</div>
        <div className="flex flex-wrap gap-1">
          {AGENTS.map(a => {
            const r = getAgentReadiness(a.id)
            return (
              <span key={a.id} style={{
                fontSize: 10, padding: '2px 8px', borderRadius: 8,
                background: r.color + '20', color: r.color, fontWeight: 600,
              }}>
                {a.icon} {r.label}
              </span>
            )
          })}
        </div>
      </div>

      {/* Live log */}
      {log.length > 0 && (
        <div style={{
          maxHeight: 200, overflow: 'auto', padding: 10, borderRadius: 8,
          background: '#1a2e22', color: '#74FB71', fontSize: 11, fontFamily: 'monospace', lineHeight: 1.6,
        }}>
          {log.map((l, i) => (
            <div key={i}><span style={{ color: '#666' }}>{l.time}</span> {l.text}</div>
          ))}
        </div>
      )}

      {/* Reset button */}
      <div className="mt-3 flex justify-end">
        <button onClick={() => { resetTrainingState(); window.location.reload() }}
          style={{ fontSize: 10, color: '#999', background: 'none', border: 'none', cursor: 'pointer', textDecoration: 'underline' }}>
          Reset statistik tréninku
        </button>
      </div>
    </div>
  )
}
