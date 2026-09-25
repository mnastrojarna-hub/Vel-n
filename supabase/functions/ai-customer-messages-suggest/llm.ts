// ===== ai-customer-messages-suggest/llm.ts =====
// Tool-use smyčka nad Anthropic API — stejný model, adaptivní myšlení, retry a
// wall-clock strop jako ai-public-agent; nástroje viz admin-tools.ts.

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { AGENT_TOOLS, executeAgentTool } from './admin-tools.ts'

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
export const ANTHROPIC_MODEL = 'claude-sonnet-4-6'
const MAX_ITERS = 8

export interface AgentResult { reply: string; confidence: 'low' | 'medium' | 'high'; admin_note: string | null; tools: string[] }

async function callAnthropic(body: Record<string, unknown>, deadline: number): Promise<Record<string, unknown>> {
  let lastErr = ''
  for (let attempt = 0; attempt < 3; attempt++) {
    if (Date.now() > deadline) break
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 60_000)
    try {
      const resp = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify(body), signal: ctrl.signal,
      })
      clearTimeout(timer)
      if (resp.ok) return await resp.json()
      lastErr = `Anthropic ${resp.status}: ${(await resp.text()).slice(0, 200)}`
      if (resp.status < 500 && resp.status !== 429) break
    } catch (e) {
      clearTimeout(timer)
      lastErr = `fetch_failed: ${(e as Error).message}`
    }
    await new Promise((r) => setTimeout(r, 400 * (attempt + 1) ** 2))
  }
  throw new Error(lastErr || 'Anthropic: vypršel časový limit')
}

function parseResult(text: string): Omit<AgentResult, 'tools'> {
  const m = text.match(/\{[\s\S]*\}/)
  if (m) {
    try {
      const p = JSON.parse(m[0])
      const reply = String(p.reply || '').trim()
      if (reply) {
        return {
          reply,
          confidence: ['low', 'medium', 'high'].includes(p.confidence) ? p.confidence : 'medium',
          admin_note: p.admin_note ? String(p.admin_note).slice(0, 800) : null,
        }
      }
    } catch { /* fallback níže */ }
  }
  // Model vrátil prostý text místo JSON — použij ho, ale označ k prověření.
  const reply = text.replace(/```(json)?/g, '').trim()
  if (!reply) throw new Error('AI vrátila prázdnou odpověď')
  return { reply, confidence: 'low', admin_note: 'Výstup nebyl ve formátu JSON — zkontroluj text návrhu.' }
}

export async function runAgent(
  sb: SupabaseClient, system: unknown, task: string, customerId: string | null, maxTokensCfg?: number,
): Promise<AgentResult> {
  if (!ANTHROPIC_API_KEY) throw new Error('ANTHROPIC_API_KEY not configured')
  const deadline = Date.now() + 130_000
  // Config panel má historicky max_tokens 600 (Haiku bez myšlení) — s myšlením a nástroji je to málo.
  let maxTokens = Math.min(Math.max(Number(maxTokensCfg) || 0, 4000), 16000)
  const messages: Array<{ role: string; content: unknown }> = [{ role: 'user', content: task }]
  const tools: string[] = []
  for (let i = 0; i < MAX_ITERS; i++) {
    if (Date.now() > deadline) throw new Error('Návrh trval příliš dlouho (časový limit) — zkus to znovu.')
    const lastIter = i === MAX_ITERS - 1
    const data = await callAnthropic({
      model: ANTHROPIC_MODEL, max_tokens: maxTokens,
      thinking: { type: 'adaptive' }, output_config: { effort: 'medium' },
      system, tools: AGENT_TOOLS, messages,
      ...(lastIter ? { tool_choice: { type: 'none' } } : {}),
    }, deadline) as { content: Array<Record<string, unknown>>; stop_reason: string }

    if (data.stop_reason === 'max_tokens' && maxTokens < 16000) { maxTokens = 16000; continue }
    if (data.stop_reason === 'tool_use') {
      messages.push({ role: 'assistant', content: data.content })
      const results = []
      for (const tb of data.content.filter((b) => b.type === 'tool_use')) {
        tools.push(String(tb.name))
        const r = await executeAgentTool(sb, String(tb.name), (tb.input as Record<string, unknown>) || {}, customerId, 'cs')
        results.push({ type: 'tool_result', tool_use_id: tb.id, content: JSON.stringify(r).slice(0, 60_000) })
      }
      messages.push({ role: 'user', content: results })
      continue
    }
    const text = data.content.filter((b) => b.type === 'text').map((b) => String(b.text)).join('\n').trim()
    return { ...parseResult(text), tools }
  }
  throw new Error('AI nedokončila návrh (příliš mnoho kroků)')
}
