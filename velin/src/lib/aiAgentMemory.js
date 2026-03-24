// Agent memory system — flash (session) + long-term (persistent) per agent
// Flash: sessionStorage (cleared on tab close)
// Long-term: localStorage (persists forever until manually cleared)

const FLASH_KEY = 'motogo_ai_flash_'
const LONGTERM_KEY = 'motogo_ai_memory_'

// --- FLASH MEMORY (krátkodobá, aktuální session) ---

export function getFlashMemory(agentId) {
  try {
    const raw = sessionStorage.getItem(FLASH_KEY + agentId)
    return raw ? JSON.parse(raw) : []
  } catch { return [] }
}

export function addFlashMemory(agentId, entry) {
  const mem = getFlashMemory(agentId)
  mem.push({
    text: entry,
    timestamp: new Date().toISOString(),
    type: 'auto',
  })
  // Keep max 50 entries
  if (mem.length > 50) mem.shift()
  sessionStorage.setItem(FLASH_KEY + agentId, JSON.stringify(mem))
  return mem
}

export function clearFlashMemory(agentId) {
  sessionStorage.removeItem(FLASH_KEY + agentId)
}

// --- LONG-TERM MEMORY (trvalá, naučené věci) ---

export function getLongTermMemory(agentId) {
  try {
    const raw = localStorage.getItem(LONGTERM_KEY + agentId)
    return raw ? JSON.parse(raw) : []
  } catch { return [] }
}

export function addLongTermMemory(agentId, entry, category = 'general') {
  const mem = getLongTermMemory(agentId)
  mem.push({
    text: entry,
    category,
    timestamp: new Date().toISOString(),
    source: 'manual',
  })
  localStorage.setItem(LONGTERM_KEY + agentId, JSON.stringify(mem))
  return mem
}

export function removeLongTermMemory(agentId, index) {
  const mem = getLongTermMemory(agentId)
  mem.splice(index, 1)
  localStorage.setItem(LONGTERM_KEY + agentId, JSON.stringify(mem))
  return mem
}

export function clearLongTermMemory(agentId) {
  localStorage.removeItem(LONGTERM_KEY + agentId)
}

// Categories for long-term memory
export const MEMORY_CATEGORIES = {
  general: { label: 'Obecné', icon: '📝' },
  customer_pref: { label: 'Preference zákazníků', icon: '👤' },
  learned: { label: 'Naučené', icon: '🧠' },
  decision: { label: 'Rozhodnutí', icon: '⚖️' },
  warning: { label: 'Varování', icon: '⚠️' },
  process: { label: 'Procesy', icon: '🔄' },
}

// Build memory context for system prompt injection
export function buildMemoryContext(agentId) {
  const flash = getFlashMemory(agentId)
  const longTerm = getLongTermMemory(agentId)

  let text = ''

  if (longTerm.length > 0) {
    text += '\n\nDLOUHODOBÁ PAMĚŤ (vždy respektuj):'
    for (const m of longTerm) {
      text += `\n- [${m.category || 'general'}] ${m.text}`
    }
  }

  if (flash.length > 0) {
    // Only last 10 flash entries for context
    const recent = flash.slice(-10)
    text += '\n\nAKTUÁLNÍ KONTEXT (flash paměť):'
    for (const m of recent) {
      text += `\n- ${m.text}`
    }
  }

  return text
}

// Build combined memory for ALL enabled agents
export function buildAllAgentMemory(enabledAgentIds) {
  let text = ''
  for (const id of enabledAgentIds) {
    const ctx = buildMemoryContext(id)
    if (ctx) text += `\n[${id}]${ctx}`
  }
  return text
}

// Auto-extract learnings from AI response (called after each response)
export function autoExtractFlash(agentId, response) {
  if (!response) return
  // Extract key facts the AI mentioned
  const patterns = [
    /zákazník (.+?) (preferuje|chce|požaduje|zmínil)/gi,
    /motorka (.+?) (má problém|potřebuje|je v)/gi,
    /DŮLEŽITÉ: (.+)/gi,
    /ZAPAMATUJ SI: (.+)/gi,
  ]
  for (const pattern of patterns) {
    const matches = response.matchAll(pattern)
    for (const match of matches) {
      addFlashMemory(agentId, match[0].slice(0, 200))
    }
  }
}
