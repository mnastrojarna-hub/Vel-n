import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SYSTEM_PROMPT = `Jsi zkušený motomechanik a servisní technik. Pracuješ pro MotoGo24 — půjčovnu motorek.
Zákazník ti popisuje problém s motorkou kterou si pronajal. Pomoz mu:
1. Diagnostikovat závadu na základě příznaků
2. Rozhodnout zda je motorka pojízdná nebo ne
3. Doporučit okamžité řešení (co udělat na místě)
4. Pokud je závada vážná, doporuč kontaktovat SOS
Odpovídej stručně, srozumitelně, v češtině. Neptej se víc než 2 otázky najednou.
Pokud máš info o konkrétní motorce (model, manuál), použij je.

DŮLEŽITÉ: Na konci každé odpovědi přidej JSON blok v tomto formátu (na samostatném řádku):
---JSON---
{"is_rideable": true/false/null, "suggest_sos": true/false}
---END---

is_rideable: true pokud je motorka pojízdná, false pokud ne, null pokud nemáš dost info.
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.`

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { message, booking_id, conversation_history } = await req.json()

    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing message' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Verify JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const supabaseAnon = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: userErr } = await supabaseAnon.auth.getUser()
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // If booking_id provided, fetch moto context
    let motoContext = ''
    if (booking_id) {
      const { data: booking } = await supabaseAdmin
        .from('bookings')
        .select('moto_id, motorcycles(model, manual_url, engine_type, power_kw, power_hp, engine_cc, weight_kg, has_abs, has_asc, features, brand)')
        .eq('id', booking_id)
        .single()

      if (booking?.motorcycles) {
        const m = booking.motorcycles as Record<string, unknown>
        motoContext = `Zákazník má motorku: ${m.brand || ''} ${m.model || ''}. Motor: ${m.engine_type || ''} ${m.engine_cc || ''}cc, ${m.power_kw || ''}kW/${m.power_hp || ''}HP. Hmotnost: ${m.weight_kg || '?'}kg. ABS: ${m.has_abs ? 'ano' : 'ne'}, ASC: ${m.has_asc ? 'ano' : 'ne'}.`
        if (m.manual_url) motoContext += ` Manuál: ${m.manual_url}`
        if (m.features) motoContext += ` Výbava: ${m.features}`
      }
    }

    // Build messages
    const apiMessages: Array<{ role: string; content: string }> = []
    if (motoContext) {
      apiMessages.push({ role: 'user', content: `[Kontext motorky] ${motoContext}` })
      apiMessages.push({ role: 'assistant', content: 'Rozumím, mám informace o motorce. Jak vám mohu pomoci?' })
    }
    if (conversation_history && Array.isArray(conversation_history)) {
      for (const m of conversation_history) {
        if (m.role === 'user' || m.role === 'assistant') {
          apiMessages.push({ role: m.role, content: m.content })
        }
      }
    }
    apiMessages.push({ role: 'user', content: message })

    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: apiMessages,
      }),
    })

    if (!response.ok) {
      const errText = await response.text()
      console.error('Anthropic API error:', response.status, errText)
      return new Response(JSON.stringify({ error: 'AI service error' }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const aiResult = await response.json()
    const aiText = aiResult.content?.[0]?.text || 'Odpověď nedostupná.'

    // Parse JSON block from response
    let is_rideable: boolean | null = null
    let suggest_sos = false
    let reply = aiText

    const jsonMatch = aiText.match(/---JSON---\s*(\{[^}]+\})\s*---END---/)
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[1])
        is_rideable = parsed.is_rideable ?? null
        suggest_sos = parsed.suggest_sos ?? false
      } catch { /* ignore parse errors */ }
      reply = aiText.replace(/---JSON---[\s\S]*?---END---/, '').trim()
    }

    return new Response(JSON.stringify({ reply, is_rideable, suggest_sos }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('ai-moto-agent error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
