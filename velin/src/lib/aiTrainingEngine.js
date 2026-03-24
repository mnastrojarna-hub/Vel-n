// AI Training Engine — runs scenarios step by step, records agent outcomes
import { supabase } from './supabase'
import { loadAgentConfig, getEnabledTools, getAgentCorrections, AGENTS, getAgentForTool } from './aiAgents'
import { buildAgentPromptsText } from './aiAgentPrompts'
import { buildAllAgentMemory } from './aiAgentMemory'
import { recordOutcome } from './aiLearning'

const STORAGE_KEY = 'motogo_ai_training_state'

export function getTrainingState() {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {} } catch { return {} }
}

function saveState(state) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
}

// Run a single step — calls AI Copilot, records outcome for target agent
async function runStep(step, scenarioId, stepIndex) {
  const config = loadAgentConfig()
  const enabledIds = AGENTS.filter(a => config[a.id]?.enabled).map(a => a.id)

  try {
    const { data, error } = await supabase.functions.invoke('ai-copilot', {
      body: {
        message: step.msg,
        enabled_tools: getEnabledTools(config),
        agent_corrections: getAgentCorrections(config),
        agent_prompts: buildAgentPromptsText(enabledIds),
        agent_memory: buildAllAgentMemory(enabledIds),
      },
    })

    if (error) throw error
    if (data?.error_code === 'overloaded') throw new Error('AI overloaded')

    const success = !!(data?.response && !data?.response.includes('Chyba') && !data?.response.includes('nedostupn'))

    // Record outcome for the target agent
    recordOutcome(step.agent, step.tool || scenarioId, { scenario: scenarioId, step: stepIndex }, {
      summary: data?.response?.slice(0, 200) || 'ok',
    }, success)

    // Also record for any other agents whose tools were used
    if (data?.tool_calls) {
      for (const tc of data.tool_calls) {
        const agent = getAgentForTool(tc.name)
        if (agent && agent.id !== step.agent) {
          recordOutcome(agent.id, tc.name, { scenario: scenarioId }, { summary: 'ok' }, tc.success !== false)
        }
      }
    }

    return { success, response: data?.response?.slice(0, 300), step: stepIndex }
  } catch (e) {
    recordOutcome(step.agent, step.tool || scenarioId, { scenario: scenarioId, step: stepIndex }, { error: e.message }, false)
    return { success: false, error: e.message, step: stepIndex }
  }
}

// Run entire scenario — step by step with callbacks
export async function runScenario(scenario, onProgress) {
  const steps = scenario.generate()
  const results = []

  for (let i = 0; i < steps.length; i++) {
    onProgress?.({ phase: 'running', scenarioId: scenario.id, step: i, total: steps.length, msg: steps[i].msg })
    const result = await runStep(steps[i], scenario.id, i)
    results.push(result)
    onProgress?.({ phase: 'step_done', scenarioId: scenario.id, step: i, total: steps.length, result })

    // Small delay between steps to avoid rate limiting
    if (i < steps.length - 1) await new Promise(r => setTimeout(r, 2000))
  }

  const passed = results.filter(r => r.success).length
  const state = getTrainingState()
  if (!state[scenario.id]) state[scenario.id] = { runs: 0, totalPassed: 0, totalSteps: 0 }
  state[scenario.id].runs++
  state[scenario.id].totalPassed += passed
  state[scenario.id].totalSteps += steps.length
  state[scenario.id].lastRun = new Date().toISOString()
  saveState(state)

  return { scenarioId: scenario.id, results, passed, total: steps.length }
}

// Run ALL scenarios sequentially
export async function runAllScenarios(scenarios, onProgress) {
  const allResults = []
  for (let i = 0; i < scenarios.length; i++) {
    onProgress?.({ phase: 'scenario_start', index: i, total: scenarios.length, scenario: scenarios[i] })
    const result = await runScenario(scenarios[i], onProgress)
    allResults.push(result)
    onProgress?.({ phase: 'scenario_done', index: i, total: scenarios.length, result })
    if (i < scenarios.length - 1) await new Promise(r => setTimeout(r, 3000))
  }
  return allResults
}

// Cleanup all test data created by simulator
export async function cleanupSimData() {
  try {
    const { data } = await supabase.functions.invoke('ai-copilot', {
      body: {
        message: 'Smaž všechna testovací data: uživatele s emailem test.sim.*, promo kódy SIMTEST*, a související rezervace. Použij cleanup_test_data.',
        enabled_tools: ['cleanup_test_data'],
      },
    })
    return { success: true, response: data?.response }
  } catch (e) {
    return { success: false, error: e.message }
  }
}

// Reset training state
export function resetTrainingState() {
  localStorage.removeItem(STORAGE_KEY)
}
