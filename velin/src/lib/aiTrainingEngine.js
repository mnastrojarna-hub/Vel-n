// AI Training Engine — runs per-agent training, records outcomes
import { recordOutcome } from './aiLearning'
import { trainBookingsAgent, trainSosAgent, trainServiceAgent } from './aiTrainingScenarios'
import { trainFleetAgent, trainCustomersAgent, trainFinanceAgent, trainEshopAgent, trainEdgeCases, trainHrAgent, trainAnalyticsAgent, trainGovernmentAgent, trainCmsAgent, trainTesterAgent, trainOrchestratorAgent, TRAINING_PROGRAMS } from './aiTrainingScenariosExtra'
import { AGENT_VOLUMES } from './aiTrainingScenarios'
import { cleanupTestData } from './aiTrainingHelpers'

const STATE_KEY = 'motogo_ai_training_state'

// Training function registry
const TRAINERS = {
  bookings: trainBookingsAgent,
  sos: trainSosAgent,
  service: trainServiceAgent,
  fleet: trainFleetAgent,
  customers: trainCustomersAgent,
  finance: trainFinanceAgent,
  eshop: trainEshopAgent,
  hr: trainHrAgent,
  analytics: trainAnalyticsAgent,
  government: trainGovernmentAgent,
  cms: trainCmsAgent,
  tester: trainTesterAgent,
  orchestrator: trainOrchestratorAgent,
  edge: trainEdgeCases,
}

export function getTrainingState() {
  try { return JSON.parse(localStorage.getItem(STATE_KEY)) || {} } catch { return {} }
}

function saveState(state) {
  localStorage.setItem(STATE_KEY, JSON.stringify(state))
}

// Run training for a SINGLE agent
export async function runAgentTraining(agentId, onProgress) {
  const trainer = TRAINERS[agentId]
  if (!trainer) return { agentId, error: 'Neznámý agent', results: [] }

  const startTime = Date.now()
  onProgress?.({ phase: 'start', agentId })

  const results = await trainer((step) => {
    onProgress?.({ phase: 'step', agentId, ...step })
  })

  // Record outcomes for each result
  let passed = 0, failed = 0
  for (const r of results) {
    const success = r.ok !== false
    if (success) passed++; else failed++
    recordOutcome(
      r.agent || agentId,
      r.action || 'unknown',
      { training: true, agentId },
      { summary: r.error || 'ok' },
      success
    )
  }

  // Update training state
  const state = getTrainingState()
  if (!state[agentId]) state[agentId] = { runs: 0, totalPassed: 0, totalFailed: 0, totalSteps: 0 }
  state[agentId].runs++
  state[agentId].totalPassed += passed
  state[agentId].totalFailed += failed
  state[agentId].totalSteps += results.length
  state[agentId].lastRun = new Date().toISOString()
  state[agentId].durationMs = Date.now() - startTime
  saveState(state)

  onProgress?.({ phase: 'done', agentId, passed, failed, total: results.length })
  return { agentId, results, passed, failed, total: results.length, durationMs: Date.now() - startTime }
}

// Run ALL agent trainings sequentially
export async function runAllTraining(onProgress) {
  // Cleanup old test data (DB) to avoid overlaps, but keep learned data
  onProgress?.({ phase: 'cleanup', agentId: 'system' })
  try { await cleanupTestData() } catch (e) { console.warn('[training] cleanup failed:', e) }

  const agentOrder = ['customers', 'fleet', 'bookings', 'finance', 'sos', 'service', 'eshop', 'hr', 'analytics', 'government', 'cms', 'tester', 'orchestrator', 'edge']
  const allResults = []

  for (let i = 0; i < agentOrder.length; i++) {
    const agentId = agentOrder[i]
    onProgress?.({ phase: 'agent_start', agentId, index: i, total: agentOrder.length })

    const result = await runAgentTraining(agentId, (step) => {
      onProgress?.({ ...step, globalIndex: i, globalTotal: agentOrder.length })
    })
    allResults.push(result)

    onProgress?.({ phase: 'agent_done', agentId, index: i, total: agentOrder.length, result })

    // Pause between agents
    if (i < agentOrder.length - 1) await new Promise(r => setTimeout(r, 1000))
  }

  return allResults
}

// Get volume status per agent
export function getAgentVolumeStatus() {
  const state = getTrainingState()
  const status = {}
  for (const [agentId, vol] of Object.entries(AGENT_VOLUMES)) {
    const s = state[agentId]
    status[agentId] = {
      ...vol,
      current: s?.totalPassed || 0,
      runs: s?.runs || 0,
      pct: s ? Math.min(100, Math.round((s.totalPassed / vol.min) * 100)) : 0,
      trained: s ? s.totalPassed >= vol.min : false,
      lastRun: s?.lastRun,
    }
  }
  return status
}

// Cleanup
export async function cleanupAllTestData() {
  return await cleanupTestData()
}

// Reset ALL learned data — training state + learning logs + metrics + memory
export function resetTrainingState() {
  // Training state
  localStorage.removeItem(STATE_KEY)
  // Metrics (confidence, success rates)
  localStorage.removeItem('motogo_ai_metrics')
  // Learning logs + long-term memory per agent
  const agentIds = ['bookings', 'sos', 'service', 'fleet', 'customers', 'finance', 'eshop', 'edge', 'hr', 'analytics', 'cms', 'government', 'tester', 'orchestrator']
  for (const id of agentIds) {
    localStorage.removeItem('motogo_ai_learning_' + id)
    localStorage.removeItem('motogo_ai_memory_' + id)
    sessionStorage.removeItem('motogo_ai_flash_' + id)
  }
}

export { TRAINING_PROGRAMS, AGENT_VOLUMES }
