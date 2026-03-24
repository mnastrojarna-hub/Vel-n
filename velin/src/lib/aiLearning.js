// AI Self-Learning Engine — agents learn from outcomes
// Tracks: success/fail patterns, confidence scores, auto-prompt improvement

const LEARNING_KEY = 'motogo_ai_learning_'
const METRICS_KEY = 'motogo_ai_metrics'

// --- OUTCOME TRACKING ---

export function recordOutcome(agentId, action, input, result, success, feedback = null) {
  const log = getAgentLearningLog(agentId)
  log.push({
    action,
    input_summary: typeof input === 'object' ? Object.keys(input).join(',') : String(input).slice(0, 100),
    success,
    feedback,
    result_summary: result?.summary || result?.error || 'ok',
    timestamp: new Date().toISOString(),
  })
  // Keep last 200 outcomes per agent
  if (log.length > 200) log.splice(0, log.length - 200)
  localStorage.setItem(LEARNING_KEY + agentId, JSON.stringify(log))
  // Update metrics
  updateMetrics(agentId, success)
  return log
}

export function getAgentLearningLog(agentId) {
  try {
    const raw = localStorage.getItem(LEARNING_KEY + agentId)
    return raw ? JSON.parse(raw) : []
  } catch { return [] }
}

// --- METRICS ---

export function getMetrics() {
  try {
    const raw = localStorage.getItem(METRICS_KEY)
    return raw ? JSON.parse(raw) : {}
  } catch { return {} }
}

function updateMetrics(agentId, success) {
  const metrics = getMetrics()
  if (!metrics[agentId]) metrics[agentId] = { total: 0, success: 0, fail: 0, streak: 0, bestStreak: 0, lastUpdate: null, confidence: 0.5 }
  const m = metrics[agentId]
  m.total++
  if (success) {
    m.success++
    m.streak++
    if (m.streak > m.bestStreak) m.bestStreak = m.streak
  } else {
    m.fail++
    m.streak = 0
  }
  m.lastUpdate = new Date().toISOString()
  // Confidence: weighted moving average (recent outcomes matter more)
  const rate = m.total > 0 ? m.success / m.total : 0.5
  m.confidence = Math.round(rate * 1000) / 10 // percentage
  metrics[agentId] = m
  localStorage.setItem(METRICS_KEY, JSON.stringify(metrics))
}

export function getAgentConfidence(agentId) {
  const metrics = getMetrics()
  return metrics[agentId]?.confidence || 50
}

export function getAgentReadiness(agentId) {
  const m = getMetrics()[agentId]
  if (!m || m.total < 10) return { level: 'learning', label: 'Učí se', color: '#f59e0b', minActions: 10 - (m?.total || 0) }
  if (m.confidence >= 95) return { level: 'autonomous', label: 'Autonomní', color: '#22c55e', minActions: 0 }
  if (m.confidence >= 80) return { level: 'supervised', label: 'Pod dohledem', color: '#3b82f6', minActions: 0 }
  if (m.confidence >= 60) return { level: 'assisted', label: 'Asistovaný', color: '#f59e0b', minActions: 0 }
  return { level: 'manual', label: 'Manuální', color: '#ef4444', minActions: 0 }
}

// --- PATTERN ANALYSIS ---

export function analyzeFailurePatterns(agentId) {
  const log = getAgentLearningLog(agentId)
  const failures = log.filter(l => !l.success)
  if (failures.length === 0) return { patterns: [], suggestions: [] }
  // Group by action
  const byAction = {}
  for (const f of failures) {
    byAction[f.action] = (byAction[f.action] || 0) + 1
  }
  const patterns = Object.entries(byAction)
    .sort((a, b) => b[1] - a[1])
    .map(([action, count]) => ({ action, fail_count: count, pct: Math.round(count / failures.length * 100) }))

  // Generate suggestions
  const suggestions = []
  for (const p of patterns) {
    if (p.fail_count >= 3) suggestions.push(`Agent selhává na "${p.action}" (${p.fail_count}×) — přidejte situační pravidlo`)
    if (p.pct > 50) suggestions.push(`Více než 50% selhání je na "${p.action}" — zvažte zakázání nebo úpravu promptu`)
  }

  // Recent trend
  const recent = log.slice(-20)
  const recentFails = recent.filter(l => !l.success).length
  if (recentFails > 10) suggestions.push('Vysoký počet nedávných selhání — agent potřebuje kalibraci')

  return { patterns, suggestions, total_failures: failures.length, total_actions: log.length }
}

// --- AUTO-PROMPT SUGGESTIONS ---

export function generatePromptSuggestions(agentId) {
  const log = getAgentLearningLog(agentId)
  const analysis = analyzeFailurePatterns(agentId)
  const suggestions = []

  // Check if agent has enough data
  if (log.length < 5) {
    suggestions.push({ type: 'info', text: `Agent potřebuje více dat (${log.length}/5 akcí). Spusťte testy.` })
    return suggestions
  }

  // Success rate suggestions
  const m = getMetrics()[agentId]
  if (m?.confidence < 60) {
    suggestions.push({ type: 'warning', text: `Nízká úspěšnost (${m.confidence}%). Revidujte prompt a situační pravidla.` })
  }

  // Pattern-based suggestions
  for (const p of analysis.patterns) {
    if (p.fail_count >= 2) {
      const failedLogs = log.filter(l => !l.success && l.action === p.action)
      const feedbacks = failedLogs.map(l => l.feedback).filter(Boolean)
      suggestions.push({
        type: 'situation',
        text: `Přidat pravidlo pro "${p.action}" — ${p.fail_count}× selhání`,
        feedbacks,
        suggestedRule: `Při akci "${p.action}": zkontroluj vstupní data a ověř oprávnění před provedením`,
      })
    }
  }

  // Check for missing forbidden rules
  if (log.some(l => l.feedback?.includes('neměl') || l.feedback?.includes('zakáz'))) {
    suggestions.push({ type: 'forbidden', text: 'Zpětná vazba naznačuje chybějící zákaz — přidejte do "Zakázáno"' })
  }

  return suggestions
}

// --- AUTONOMY READINESS SCORE ---

export function calculateAutonomyScore() {
  const metrics = getMetrics()
  const agents = Object.keys(metrics)
  if (agents.length === 0) return { score: 0, level: 'Začátek', agents: {} }

  let totalConf = 0, count = 0
  const agentScores = {}
  for (const [id, m] of Object.entries(metrics)) {
    const readiness = getAgentReadiness(id)
    agentScores[id] = { confidence: m.confidence, readiness: readiness.level, total_actions: m.total }
    totalConf += m.confidence
    count++
  }
  const avgScore = count > 0 ? Math.round(totalConf / count) : 0

  let level = 'Začátek'
  if (avgScore >= 95) level = 'Plně autonomní'
  else if (avgScore >= 80) level = 'Vysoká autonomie'
  else if (avgScore >= 60) level = 'Střední autonomie'
  else if (avgScore >= 40) level = 'Nízká autonomie'
  else level = 'Učení'

  return { score: avgScore, level, agents: agentScores, total_agents: count }
}
