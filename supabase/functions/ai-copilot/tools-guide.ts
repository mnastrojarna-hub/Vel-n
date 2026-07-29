// get_system_guide — encyklopedie + návod k obsluze celého ekosystému MotoGo24
import { KNOWLEDGE_VELIN } from './knowledge-velin.ts'
import { KNOWLEDGE_APPS } from './knowledge-apps.ts'

// deno-lint-ignore no-explicit-any
type R = Record<string, any>

const KNOWLEDGE: Record<string, string> = { ...KNOWLEDGE_VELIN, ...KNOWLEDGE_APPS }

// Odstranění diakritiky pro fulltext match
function norm(s: string): string {
  return s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
}

export function execGuide(name: string, input: R): unknown {
  if (name !== 'get_system_guide') return null
  const topic = input.topic as string | undefined
  const query = input.query as string | undefined

  if (topic && KNOWLEDGE[topic]) return { topic, content: KNOWLEDGE[topic] }

  if (query) {
    const q = norm(query)
    const words = q.split(/\s+/).filter(w => w.length > 2)
    const scored = Object.entries(KNOWLEDGE)
      .map(([key, content]) => {
        const c = norm(content) + ' ' + norm(key)
        const score = words.reduce((s, w) => s + (c.includes(w) ? 1 : 0), 0)
        return { key, content, score }
      })
      .filter(e => e.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 3)
    if (scored.length > 0) return { matched_topics: scored.map(e => ({ topic: e.key, content: e.content })) }
  }

  // Bez topicu/bez shody → obsah (TOC), ať si AI vybere
  return {
    available_topics: Object.keys(KNOWLEDGE),
    hint: 'Zavolej znovu s konkrétním topic. Témata: velin-* (sekce dashboardu), proces-* (návody krok za krokem), web-* (motogo24.cz), app-* (mobilní aplikace), integrace, architektura, domena-pojmy.',
  }
}
