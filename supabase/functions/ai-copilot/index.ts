import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { filterToolsByEnabled } from './tools-def.ts'
import { executeTool, isWriteTool } from './tools-exec.ts'
import { TOOL_RISK } from './tools-def-write.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

// Build system prompt with agent corrections
function buildSystemPrompt(corrections?: Record<string, string[]>) {
  let prompt = `Jsi AI Copilot pro Velín — superadmin dashboard půjčovny motorek MotoGo24. Máš 100% přehled o CELÉM ekosystému: Velín, web motogo24.cz, mobilní aplikace (Android+iOS), backend Supabase.
Firma: Bc. Petra Semorádová, IČO: 21874263, Mezná 9, 393 01. Kontakt: +420 774 256 271, info@motogo24.cz

Máš k dispozici nástroje pro ČTENÍ i ZÁPIS dat. VŽDY si nejdřív sáhni pro data než odpovíš.

ŽELEZNÉ PRAVIDLO — NIKDY neříkej „k tomu nemám přístup / to nevím / to neumím spočítat":
- Když neexistuje specializovaný nástroj, použij query_table (umí číst KAŽDOU tabulku v DB s filtry i počty řádků).
- Na otázky „jak funguje / jak se ovládá / kde najdu / co umí appka nebo web" VŽDY použij get_system_guide (encyklopedie + návod k obsluze celého systému). Jsi zároveň manuál Velína, webu i aplikace.
- Když výpočet nejde udělat nástrojem, stáhni si surová data přes query_table a spočítej to sám.

WRITE NÁSTROJE — DŮLEŽITÉ:
- Při volání WRITE nástroje vrátí PREVIEW (status:"preview") s popisem co se změní
- VŽDY zahrň do odpovědi sekci [PENDING_ACTIONS] s JSON polem akcí ke schválení
- Uživatel musí potvrdit před provedením
- Formát: [PENDING_ACTIONS]{"actions":[{"tool":"nazev","input":{...},"summary":"popis"}]}[/PENDING_ACTIONS]

PROVOZNÍ OBLASTI (vše pokrýváš):
Rezervace, Flotila, Pobočky (vč. samoobslužných kiosků), SOS, Zákazníci, Sklady, Logistika výbavy, Finance a účetnictví (faktury, finanční události, DPH, Flexi), E-shop, Vouchery a promo (vč. Slevomat), Servis, Zprávy a kampaně, Dokumenty, CMS, Trasy, Věrnostní program, Audit, Státní správa, Zaměstnanci, Analýza (návštěvnost, funnely, AI konverzace, aplikace, km).

KLÍČOVÁ DOMÉNOVÁ PRAVIDLA (dodržuj v číslech!):
- Obrat z rezervací = ZAPLACENÉ (payment_status ∈ paid/partial_refund/refund_pending/refunded) + nestornované + is_test=false. NE jen „completed"!
- Testovací data (bookings.is_test, profiles.is_test_account) VŽDY vyřazuj z analýz.
- Faktury: zaplacení se pozná dle TYPU dokladu (payment_receipt/final/shop_final; credit_note=záporný refund), NE dle statusu. ZF (advance/proforma) = jen výzva k platbě.
- Storno tabulka: ≥7 dní 100 %, 2–7 dní 50 %, <2 dny 0 % refund.
- Věrnostní sleva 1–20 % platí JEN pro rezervace z aplikace.
- Sloupce faktur: issue_date (ne issued_at); shop_orders.total (ne total_amount); promo_codes.value+active.
- Souhlasy (marketing_consent...), zdroj registrace a blokace zákazníků vrací get_customers (vč. agregací přes všechny). „Kolik zákazníků má appku" → get_app_stats.customers_with_app (instalace + app rezervace + registrace přes app; web se nepočítá). Vazba zákazník↔rezervace: bookings.user_id (get_bookings_detail vrací customer, query_table umí filtrovat).

Při analýze VŽDY: rozlišuj reálná data vs odhad, upozorni na předběžnost, uváděj confidence level.

NAVIGACE:
- Zprávy uživatele mohou začínat [Kontext: stránka "X"] — to značí odkud se ptá
- Pokud je vhodné přejít na jinou stránku, přidej do odpovědi [NAV:/cesta] (např. [NAV:/flotila/uuid])
- Dostupné cesty: /, /flotila, /flotila/:id, /rezervace, /rezervace/:id, /zakaznici, /zakaznici/:id, /finance, /dokumenty, /pobocky, /logistika, /trasy, /servis, /zpravy, /cms, /analyza, /slevove-kody, /e-shop, /statni-sprava, /sos, /zamestnanci, /sklady, /sklady/:id, /orchestrator, /ai-copilot

Odpovídej v češtině, stručně, s konkrétními čísly.`

  if (corrections && Object.keys(corrections).length > 0) {
    prompt += '\n\nKOREKCE OD ADMINISTRÁTORA:'
    for (const [agent, corrs] of Object.entries(corrections)) {
      prompt += `\n[${agent}]: ${corrs.join('; ')}`
    }
  }
  return prompt
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const body = await req.json()
    const { message, conversation_id, conversation_history, mode, actions, enabled_tools, agent_corrections, agent_prompts, agent_memory } = body

    if (!ANTHROPIC_API_KEY) return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)

    // JWT auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return jsonResponse({ error: 'Unauthorized' }, 401)
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userErr } = await supabaseAdmin.auth.getUser(token)
    if (userErr || !user) return jsonResponse({ error: 'Unauthorized' }, 401)
    // User-scoped klient pro RPC s is_admin() guardem (auth.uid() musí být admin, ne NULL ze service role)
    const supabaseUser = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } })

    // MODE: EXECUTE — confirm and run pending actions
    if (mode === 'execute' && Array.isArray(actions)) {
      const results = []
      for (const action of actions) {
        const result = await executeTool(action.tool, action.input, supabaseAdmin, false, supabaseUser)
        results.push({ tool: action.tool, result, success: !(result as Record<string, unknown>)?.error })
      }
      // Log to ai_actions
      try {
        await supabaseAdmin.from('ai_actions').insert(results.map(r => ({
          admin_id: user.id, tool: r.tool, input: actions.find((a: Record<string, unknown>) => a.tool === r.tool)?.input,
          result: r.result, success: r.success, created_at: new Date().toISOString(),
        })))
      } catch { /* ignore logging errors */ }
      return jsonResponse({ executed_actions: results, response: `Provedeno ${results.filter(r => r.success).length}/${results.length} akcí.` })
    }

    // MODE: CHAT — normal AI conversation
    if (!message || typeof message !== 'string') return jsonResponse({ error: 'Missing message' }, 400)

    // Load conversation history
    // deno-lint-ignore no-explicit-any
    let convMsgs: Array<{ role: string; content: string }> = []
    if (conversation_history && Array.isArray(conversation_history)) {
      convMsgs = conversation_history.filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant').map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
    } else if (conversation_id) {
      const { data: conv } = await supabaseAdmin.from('ai_conversations').select('messages').eq('id', conversation_id).single()
      if (conv?.messages && Array.isArray(conv.messages)) {
        convMsgs = conv.messages.filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant').map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
      }
    }

    // deno-lint-ignore no-explicit-any
    const rawMsgs: Array<{ role: string; content: any }> = []
    for (const m of convMsgs) rawMsgs.push({ role: m.role, content: m.content })
    rawMsgs.push({ role: 'user', content: message })
    const apiMessages = rawMsgs[0]?.role !== 'user' ? [{ role: 'user', content: '(kontext)' }, ...rawMsgs] : [...rawMsgs]

    // Filter tools by enabled agents
    const tools = filterToolsByEnabled(enabled_tools)
    let systemPrompt = buildSystemPrompt(agent_corrections)
    // Inject agent-specific prompts and memory from frontend
    if (agent_prompts && typeof agent_prompts === 'string') systemPrompt += agent_prompts
    if (agent_memory && typeof agent_memory === 'string') systemPrompt += agent_memory

    // Agentic loop
    const MAX_ITER = 15, TIMEOUT = 60000, t0 = Date.now()
    const pendingActions: Array<Record<string, unknown>> = []

    for (let i = 0; i < MAX_ITER; i++) {
      if (Date.now() - t0 > TIMEOUT) return jsonResponse({ response: 'Zpracování trvá příliš dlouho. Zkuste jednodušší dotaz.' })

      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
        body: JSON.stringify({ model: 'claude-sonnet-4-6', max_tokens: 4096, system: systemPrompt, messages: apiMessages, tools }),
      })

      if (!res.ok) {
        const err = await res.text()
        console.error('Anthropic error:', res.status, err)
        if (res.status === 429 && i === 0) { await new Promise(r => setTimeout(r, 2000)); continue }
        if (res.status === 529 || res.status === 503) return jsonResponse({ response: 'AI služba je přetížená.', error_code: 'overloaded' })
        return jsonResponse({ error: 'AI service error' }, 502)
      }

      const ai = await res.json()

      if (ai.stop_reason === 'end_turn') {
        // deno-lint-ignore no-explicit-any
        const text = (ai.content || []).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('\n') || ''
        // Parse pending actions from response
        const match = text.match(/\[PENDING_ACTIONS\]([\s\S]*?)\[\/PENDING_ACTIONS\]/)
        let parsedActions: Array<Record<string, unknown>> = []
        if (match) {
          try {
            const parsed = JSON.parse(match[1])
            parsedActions = (parsed.actions || []).map((a: Record<string, unknown>) => ({
              ...a, id: crypto.randomUUID(), risk: TOOL_RISK[a.tool as string] || 'medium',
            }))
          } catch { /* ignore parse errors */ }
        }
        // Combine with any actions collected during tool use
        const allPending = [...pendingActions, ...parsedActions]
        const cleanText = text.replace(/\[PENDING_ACTIONS\][\s\S]*?\[\/PENDING_ACTIONS\]/g, '').trim()
        return jsonResponse({ response: cleanText || 'Odpověď nedostupná.', pending_actions: allPending.length > 0 ? allPending : undefined })
      }

      if (ai.stop_reason === 'tool_use') {
        apiMessages.push({ role: 'assistant', content: ai.content })
        // deno-lint-ignore no-explicit-any
        const results: Array<Record<string, unknown>> = []
        // deno-lint-ignore no-explicit-any
        for (const tc of ai.content.filter((b: any) => b.type === 'tool_use')) {
          // Write tools: dry run (preview only)
          const isDry = isWriteTool(tc.name)
          const data = await executeTool(tc.name, tc.input || {}, supabaseAdmin, isDry, supabaseUser)
          // If preview, collect as pending action
          if (isDry && (data as Record<string, unknown>)?.status === 'preview') {
            pendingActions.push({
              id: crypto.randomUUID(), tool: tc.name, input: tc.input || {},
              summary: (data as Record<string, unknown>).summary || tc.name,
              risk: TOOL_RISK[tc.name] || 'medium',
              details: data,
            })
          }
          results.push({ type: 'tool_result', tool_use_id: tc.id, content: JSON.stringify(data) })
        }
        apiMessages.push({ role: 'user', content: results })
        continue
      }

      break
    }

    return jsonResponse({ response: 'Dotaz je příliš složitý. Zkuste ho zjednodušit.' })
  } catch (err) {
    console.error('ai-copilot error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
