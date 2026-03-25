// Agent prompt system — editable system prompts, situation rules, forbidden actions
// Stored in localStorage, injected into AI system prompt per agent

const PROMPTS_KEY = 'motogo_ai_prompts'

// PRINCIP: Velín řeší 80% operací sám algoritmicky (CRUD, flow, triggery).
// Agenti NEKOPÍRUJÍ práci Velínu. Agenti = watchdogs + edge-case řešitelé:
// 1. Kontrolují konzistenci dat po operacích Velínu
// 2. Hledají anomálie a nekonzistence napříč systémem
// 3. Řeší situace které Velín neumí (zákazník volá, reklamace, nestandardní požadavek)
// 4. Spolupracují navzájem (booking agent se ptá servisního jestli je moto OK)
// 5. Eskalují na ředitele co nemohou vyřešit sami
// Importy promptů z externího souboru
import { AGENT_PROMPTS_DATA } from './aiAgentPromptsData'
export const DEFAULT_PROMPTS = AGENT_PROMPTS_DATA

// Version key — bump when defaults change significantly to force refresh
const PROMPTS_VERSION = '2026-03-25-v2'
const VERSION_KEY = 'motogo_ai_prompts_version'

export function loadAgentPrompts() {
  try {
    const savedVersion = localStorage.getItem(VERSION_KEY)
    if (savedVersion !== PROMPTS_VERSION) {
      // Defaults changed — clear old prompts, use new defaults
      localStorage.removeItem(PROMPTS_KEY)
      localStorage.setItem(VERSION_KEY, PROMPTS_VERSION)
      return { ...DEFAULT_PROMPTS }
    }
    const raw = localStorage.getItem(PROMPTS_KEY)
    if (raw) {
      // Deep merge: per-agent, default fields fill in missing but user edits preserved
      const saved = JSON.parse(raw)
      const merged = { ...DEFAULT_PROMPTS }
      for (const [id, data] of Object.entries(saved)) {
        if (merged[id]) merged[id] = { ...merged[id], ...data }
        else merged[id] = data
      }
      return merged
    }
  } catch { /* ignore */ }
  return { ...DEFAULT_PROMPTS }
}

export function saveAgentPrompts(prompts) {
  localStorage.setItem(PROMPTS_KEY, JSON.stringify(prompts))
}

export function getAgentPrompt(agentId) {
  const prompts = loadAgentPrompts()
  return prompts[agentId] || { prompt: '', situations: [], forbidden: [] }
}

export function updateAgentPrompt(agentId, data) {
  const prompts = loadAgentPrompts()
  prompts[agentId] = { ...prompts[agentId], ...data }
  saveAgentPrompts(prompts)
  return prompts
}

// Build full prompt text for injection into system prompt
export function buildAgentPromptsText(enabledAgentIds) {
  const prompts = loadAgentPrompts()
  let text = `\n\nGLOBÁLNÍ PRINCIP: Velín řeší 80% operací algoritmicky (CRUD, flow, triggery, platby). Agenti do toho NEZASAHUJÍ. Agenti = watchdogs: kontrolují konzistenci, hledají anomálie, řeší edge cases, spolupracují navzájem, eskalují na ředitele.\n\nINSTRUKCE PRO AKTIVNÍ AGENTY:`
  for (const id of enabledAgentIds) {
    const p = prompts[id]
    if (!p) continue
    text += `\n\n=== ${id.toUpperCase()} ===\n${p.prompt}`
    if (p.situations?.length > 0) {
      text += '\nSITUAČNÍ PRAVIDLA:'
      for (const s of p.situations) text += `\n- ${s}`
    }
    if (p.mustDo?.length > 0) {
      text += '\nVŽDY MUSÍ UDĚLAT:'
      for (const m of p.mustDo) text += `\n- ✅ ${m}`
    }
    if (p.forbidden?.length > 0) {
      text += '\nZAKÁZÁNO:'
      for (const f of p.forbidden) text += `\n- ❌ ${f}`
    }
  }
  return text
}
