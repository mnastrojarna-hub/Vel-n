import { useState, useRef } from 'react'
import { runAgentTraining, runAllTraining, cleanupAllTestData, getAgentVolumeStatus, resetTrainingState, AGENT_VOLUMES } from '../../lib/aiTrainingEngine'
import { TRAINING_PROGRAMS } from '../../lib/aiTrainingScenariosExtra'
import { calculateAutonomyScore, getAgentReadiness } from '../../lib/aiLearning'
import { SOS_TYPES } from '../../lib/aiTrainingScenarios'
import Button from '../ui/Button'

const AGENT_ICONS = { bookings: '📅', fleet: '🏍️', customers: '👥', finance: '💰', service: '🔧', sos: '🚨', eshop: '🛒', edge: '⚠️' }

export default function AiTrainingPanel() {
  const [running, setRunning] = useState(null) // null or agentId or 'all'
  const [progress, setProgress] = useState(null)
  const [log, setLog] = useState([])
  const [volumes, setVolumes] = useState(() => getAgentVolumeStatus())
  const [cleaning, setCleaning] = useState(false)
  const autonomy = calculateAutonomyScore()

  function addLog(text, type = 'info') {
    setLog(l => [...l.slice(-80), { text, type, time: new Date().toLocaleTimeString('cs-CZ') }])
  }

  async function handleRunAgent(agentId) {
    setRunning(agentId); setLog([])
    const label = TRAINING_PROGRAMS[agentId]?.label || agentId
    addLog(`▶ Spouštím trénink: ${label}`)

    try {
      const result = await runAgentTraining(agentId, (p) => {
        setProgress(p)
        if (p.phase === 'step') addLog(`  ${p.action}`, 'step')
        if (p.phase === 'done') addLog(`✓ Hotovo: ${p.passed}/${p.total} úspěšných (${p.failed} chyb)`, p.failed ? 'warn' : 'ok')
      })
      setVolumes(getAgentVolumeStatus())
      addLog(`= ${result.passed}/${result.total} za ${Math.round(result.durationMs / 1000)}s`, 'ok')
    } catch (e) { addLog(`✗ Chyba: ${e.message}`, 'error') }
    setRunning(null); setProgress(null)
  }

  async function handleRunAll() {
    setRunning('all'); setLog([])
    addLog('▶▶ Spouštím kompletní trénink všech agentů')

    try {
      const results = await runAllTraining((p) => {
        setProgress(p)
        if (p.phase === 'agent_start') addLog(`\n▶ ${AGENT_ICONS[p.agentId] || ''} ${TRAINING_PROGRAMS[p.agentId]?.label || p.agentId}`, 'header')
        if (p.phase === 'step') addLog(`  ${p.action}`, 'step')
        if (p.phase === 'agent_done') {
          const r = p.result
          addLog(`  ✓ ${r.passed}/${r.total} OK (${Math.round(r.durationMs / 1000)}s)`, r.failed ? 'warn' : 'ok')
        }
      })
      setVolumes(getAgentVolumeStatus())
      const tp = results.reduce((a, r) => a + r.passed, 0)
      const tt = results.reduce((a, r) => a + r.total, 0)
      addLog(`\n══ CELKEM: ${tp}/${tt} úspěšných akcí ══`, 'ok')
    } catch (e) { addLog(`✗ Chyba: ${e.message}`, 'error') }
    setRunning(null); setProgress(null)
  }

  async function handleCleanup() {
    setCleaning(true); addLog('Mažu testovací data...')
    try {
      const res = await cleanupAllTestData()
      addLog(`Smazáno: ${res.join(', ')}`, 'ok')
    } catch (e) { addLog(`Chyba: ${e.message}`, 'error') }
    setCleaning(false)
  }

  const allTrained = Object.values(volumes).every(v => v.trained)
  const totalPct = Object.values(volumes).length > 0
    ? Math.round(Object.values(volumes).reduce((a, v) => a + v.pct, 0) / Object.values(volumes).length)
    : 0

  return (
    <div>
      {/* Header */}
      <div style={{ padding: '12px 16px', borderRadius: 10, marginBottom: 12,
        background: allTrained ? '#dcfce7' : totalPct > 50 ? '#fef3c7' : '#fef2f2',
        border: '1px solid ' + (allTrained ? '#22c55e' : totalPct > 50 ? '#f59e0b' : '#fca5a5') }}>
        <div className="flex items-center justify-between">
          <div>
            <div className="font-extrabold" style={{ color: '#0f1a14', fontSize: 14 }}>
              Trénink agentů — {totalPct}% | Autonomie: {autonomy.score}%
            </div>
            <div style={{ fontSize: 11, color: '#666' }}>
              Simulátor prochází reálné zákaznické procesy v motogo-app (Supabase API)
            </div>
          </div>
          <div className="flex gap-2">
            <Button green onClick={handleRunAll} disabled={!!running} style={{ fontSize: 12, padding: '6px 14px' }}>
              {running === 'all' ? `Běží... (${progress?.agentId || ''})` : 'Trénovat vše'}
            </Button>
            <Button onClick={handleCleanup} disabled={cleaning || !!running} style={{
              fontSize: 11, padding: '4px 10px', background: '#fee2e2', border: '1px solid #fca5a5', borderRadius: 6 }}>
              {cleaning ? '...' : 'Smazat test data'}
            </Button>
          </div>
        </div>
      </div>

      {/* Per-agent volume cards */}
      <div className="grid grid-cols-2 gap-2 mb-3">
        {Object.entries(TRAINING_PROGRAMS).map(([id, prog]) => {
          const vol = volumes[id] || { min: 10, current: 0, pct: 0, trained: false, runs: 0 }
          const readiness = id !== 'edge' ? getAgentReadiness(id) : null
          const isRunning = running === id

          return (
            <div key={id} style={{
              padding: '10px 12px', borderRadius: 10,
              border: '1px solid ' + (vol.trained ? '#22c55e' : vol.pct > 0 ? '#f59e0b' : '#d4e8e0'),
              background: vol.trained ? '#f0fdf4' : '#fff',
              opacity: isRunning ? 1 : 0.95,
            }}>
              <div className="flex items-center justify-between mb-1">
                <span className="font-bold" style={{ fontSize: 12, color: '#0f1a14' }}>
                  {prog.label}
                </span>
                {readiness && (
                  <span style={{ fontSize: 9, padding: '1px 6px', borderRadius: 6,
                    background: readiness.color + '20', color: readiness.color, fontWeight: 600 }}>
                    {readiness.label}
                  </span>
                )}
              </div>

              {/* Progress bar */}
              <div style={{ height: 6, borderRadius: 3, background: '#e5e7eb', marginBottom: 4 }}>
                <div style={{
                  height: '100%', borderRadius: 3, width: `${vol.pct}%`,
                  background: vol.trained ? '#22c55e' : vol.pct > 50 ? '#f59e0b' : '#ef4444',
                  transition: 'width 0.5s',
                }} />
              </div>

              <div className="flex items-center justify-between">
                <span style={{ fontSize: 10, color: '#666' }}>
                  {vol.current}/{vol.min || '?'} akcí ({vol.pct}%) {vol.runs > 0 ? `| ${vol.runs}× běh` : ''}
                </span>
                <Button onClick={() => handleRunAgent(id)} disabled={!!running} style={{
                  fontSize: 10, padding: '2px 8px', background: '#f1faf7', border: '1px solid #d4e8e0', borderRadius: 6 }}>
                  {isRunning ? '...' : 'Spustit'}
                </Button>
              </div>

              {vol.lastRun && (
                <div style={{ fontSize: 9, color: '#999', marginTop: 2 }}>
                  Poslední: {new Date(vol.lastRun).toLocaleString('cs-CZ')}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* SOS detail — shows 5× each type */}
      <div style={{ marginBottom: 10, padding: 10, borderRadius: 8, background: '#fef3c7', border: '1px solid #fde68a' }}>
        <div style={{ fontSize: 11, fontWeight: 700, marginBottom: 4 }}>SOS trénink — 5 incidentů na typ:</div>
        <div className="flex flex-wrap gap-1">
          {SOS_TYPES.map(s => (
            <span key={s.type} style={{ fontSize: 10, padding: '2px 8px', borderRadius: 6,
              background: '#fff', border: '1px solid #fde68a' }}>
              {s.label} (5×)
            </span>
          ))}
        </div>
        <div style={{ fontSize: 10, color: '#92400e', marginTop: 4 }}>
          Každý SOS potřebuje: zákazník + rezervace + aktivní výpůjčka + incident + vyřešení
          {' '}= 25 kompletních SOS scénářů + úměrné rezervace a servisní zakázky
        </div>
      </div>

      {/* Live log */}
      {log.length > 0 && (
        <div style={{
          maxHeight: 250, overflow: 'auto', padding: 10, borderRadius: 8,
          background: '#1a2e22', color: '#74FB71', fontSize: 11,
          fontFamily: 'monospace', lineHeight: 1.6,
        }}>
          {log.map((l, i) => (
            <div key={i} style={{
              color: l.type === 'error' ? '#f87171' : l.type === 'warn' ? '#fbbf24'
                : l.type === 'ok' ? '#4ade80' : l.type === 'header' ? '#60a5fa' : '#74FB71'
            }}>
              <span style={{ color: '#555' }}>{l.time}</span> {l.text}
            </div>
          ))}
        </div>
      )}

      {/* Akce */}
      <div className="mt-3 flex justify-between items-center gap-3">
        <div style={{ fontSize: 10, color: '#999' }}>
          Data se vytváří reálně v Supabase (is_test=true).
        </div>
        <div className="flex gap-2">
          <button onClick={async () => { setCleaning(true); await cleanupAllTestData(); setCleaning(false); addLog('Testovací data smazána', 'ok') }}
            disabled={cleaning}
            style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #d4e8e0', background: '#f8fcfa', cursor: 'pointer', color: '#666' }}>
            {cleaning ? 'Mažu...' : 'Smazat test data z DB'}
          </button>
          <button onClick={() => { resetTrainingState(); window.location.reload() }}
            style={{ fontSize: 11, padding: '4px 10px', borderRadius: 6, border: '1px solid #fecaca', background: '#fef2f2', cursor: 'pointer', color: '#dc2626', fontWeight: 700 }}>
            Smazat naučená data
          </button>
        </div>
      </div>
    </div>
  )
}
