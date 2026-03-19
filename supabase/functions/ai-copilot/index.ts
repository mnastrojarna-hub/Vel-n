import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { TOOLS_DEFINITION } from './tools-def.ts'
import { executeTool } from './tools-exec.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

// ---------------------------------------------------------------------------
// SYSTEM PROMPT
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `Jsi AI Copilot pro Velín — superadmin dashboard půjčovny motorek MotoGo24.
Firma: Bc. Petra Semorádová, IČO: 21874263, Mezná 9, 393 01. Kontakt: +420 774 256 271, info@motogo24.cz

Máš k dispozici 31 nástrojů pro přístup ke KOMPLETNÍ databázi v reálném čase. VŽDY si nejdřív sáhni pro data přes nástroj než odpovíš — nehádej, nevymýšlej. Můžeš volat více nástrojů najednou (parallel tool use).

PROVOZNÍ OBLASTI:
- Rezervace (aktivní, nadcházející, historické, storna, platby)
- Flotila motorek (stav, nájezd, servisy, STK, pojistky, ceník po dnech)
- Pobočky (detail: motorky s kojemi, příslušenství s velikostmi, přístupové kódy, aktivní rezervace)
- SOS incidenty (detail s timeline a workflow)
- Zákazníci (profily, historie, dokumenty, recenze)
- Sklady (položky, zásoby, pohyby příjem/výdej/korekce, dodavatelé)
- Finance (tržby, faktury vydané/přijaté, platby)
- E-shop (objednávky, produkty)
- Vouchery a promo kódy
- Servis a údržba (plány, objednávky)
- Zprávy a komunikace se zákazníky
- Dokumenty (smlouvy, šablony, vygenerované, odeslané e-maily)
- CMS (feature flagy, proměnné, app nastavení)
- Audit log (kdo co kdy udělal)
- Státní správa (STK termíny, pojistky celé flotily)
- Denní statistiky a trendy

ANALYTICKÉ SCHOPNOSTI (Fleet Intelligence):
- Výkon poboček (obrat, obsazenost, trend, profit/motorku)
- Výkon motorek (ranking, avg Kč/den, brand performance score)
- Poptávka kategorií (adventure vs naked vs A2...)
- Optimální složení flotily (8 slotů, scoring)
- Segmentace zákazníků (VIP/regular/occasional/inactive)
- PREDIKCE: prognóza tržeb a obsazenosti na základě historických dat a sezónních vzorců

Při analýze VŽDY:
- Rozlišuj 📊 reálná data vs 📐 benchmark/odhad
- Pokud < 3 měsíce dat, upozorni na předběžnost závěrů
- Predikce označuj confidence level (high/medium/low)
- Používej FLEET_CALC konstanty: marketing 15%, servis dle kategorie

Odpovídej v češtině, stručně, s konkrétními čísly. Pokud data nemáš, řekni to.`

// ---------------------------------------------------------------------------
// SERVE HANDLER
// ---------------------------------------------------------------------------

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    // 1. Parse body
    const body = await req.json()
    const message = body?.message
    const conversation_id = body?.conversation_id
    const conversation_history = body?.conversation_history

    if (!message || typeof message !== 'string') {
      return jsonResponse({ error: 'Missing message' }, 400)
    }

    if (!ANTHROPIC_API_KEY) {
      return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)
    }

    // 2. JWT auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ error: 'Unauthorized: missing auth header' }, 401)
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userErr } = await supabaseAdmin.auth.getUser(token)
    if (userErr || !user) {
      console.error('ai-copilot: auth failed', userErr?.message)
      return jsonResponse({ error: 'Unauthorized: ' + (userErr?.message || 'invalid token') }, 401)
    }

    console.log('ai-copilot: authenticated user', user.id)

    // 3. Load conversation history z ai_conversations (CELÁ, ne jen 10)
    let conversationMessages: Array<{ role: string; content: string }> = []

    if (conversation_history && Array.isArray(conversation_history)) {
      // Prefer client-supplied history if provided
      conversationMessages = conversation_history
        .filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant')
        .map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
    } else if (conversation_id) {
      const { data: conv } = await supabaseAdmin
        .from('ai_conversations')
        .select('messages')
        .eq('id', conversation_id)
        .single()
      if (conv?.messages && Array.isArray(conv.messages)) {
        // Load ALL messages — no limit
        conversationMessages = conv.messages
          .filter((m: { role: string }) => m.role === 'user' || m.role === 'assistant')
          .map((m: { role: string; content: string }) => ({ role: m.role, content: m.content }))
      }
    }

    // Build messages array
    // deno-lint-ignore no-explicit-any
    const rawMessages: Array<{role: string; content: string | Array<Record<string, unknown>>}> = []

    if (conversationMessages.length > 0) {
      for (const m of conversationMessages) {
        rawMessages.push({ role: m.role, content: m.content })
      }
    }
    rawMessages.push({ role: 'user', content: message })

    // deno-lint-ignore no-explicit-any
    const apiMessages: Array<any> = rawMessages[0]?.role !== 'user'
      ? [{ role: 'user' as const, content: '(kontext)' }, ...rawMessages]
      : [...rawMessages]

    console.log('ai-copilot: messages count:', apiMessages.length)

    // 4. Agentic loop
    const MAX_ITER = 8
    const TIMEOUT = 25000
    const t0 = Date.now()

    for (let i = 0; i < MAX_ITER; i++) {
      if (Date.now() - t0 > TIMEOUT) {
        console.warn('ai-copilot: timeout after', i, 'iterations')
        return jsonResponse({ response: 'Zpracování trvá příliš dlouho. Zkuste jednodušší dotaz.' })
      }

      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-sonnet-4-20250514',
          max_tokens: 4096,
          system: SYSTEM_PROMPT,
          messages: apiMessages,
          tools: TOOLS_DEFINITION,
        }),
      })

      if (!res.ok) {
        const err = await res.text()
        console.error('Anthropic error:', res.status, err)
        if (res.status === 429 && i === 0) { await new Promise(r => setTimeout(r, 2000)); continue }
        if (res.status === 529 || res.status === 503) {
          return jsonResponse({ response: 'AI služba je přetížená. Zkuste za minutu.', error_code: 'overloaded' })
        }
        return jsonResponse({ error: 'AI service error', status: res.status }, 502)
      }

      const ai = await res.json()

      if (ai.stop_reason === 'end_turn') {
        // deno-lint-ignore no-explicit-any
        const text = (ai.content || []).filter((b: any) => b.type === 'text').map((b: any) => b.text).join('\n') || 'Odpověď nedostupná.'
        console.log(`ai-copilot: done in ${i + 1} iters, ${Date.now() - t0}ms`)
        return jsonResponse({ response: text })
      }

      if (ai.stop_reason === 'tool_use') {
        apiMessages.push({ role: 'assistant', content: ai.content })
        const results: Array<Record<string, unknown>> = []
        // deno-lint-ignore no-explicit-any
        for (const tc of ai.content.filter((b: any) => b.type === 'tool_use')) {
          const data = await executeTool(tc.name, tc.input || {}, supabaseAdmin)
          results.push({ type: 'tool_result', tool_use_id: tc.id, content: JSON.stringify(data) })
        }
        apiMessages.push({ role: 'user', content: results })
        continue
      }

      console.warn('ai-copilot: unexpected stop_reason:', ai.stop_reason)
      break
    }

    return jsonResponse({ response: 'Dotaz je příliš složitý. Zkuste ho zjednodušit.' })

  } catch (err) {
    console.error('ai-copilot error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
