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

FOTKY KONTROLEK: Zákazník ti může poslat fotky budíků / přístrojové desky motorky.
Když dostaneš fotku, pečlivě analyzuj viditelné kontrolky, varování a indikátory.
Popiš co vidíš (které kontrolky svítí, jakou mají barvu) a vysvětli co znamenají.
Pokud je na fotce špatná viditelnost, požádej o lepší fotku.

DŮLEŽITÉ: Na konci každé odpovědi přidej JSON blok v tomto formátu (na samostatném řádku):
---JSON---
{"is_rideable": true/false/null, "suggest_sos": true/false}
---END---

is_rideable: true pokud je motorka pojízdná, false pokud ne, null pokud nemáš dost info.
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.`

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { message, booking_id, conversation_history, images } = await req.json()

    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing message' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Verify JWT using service role client (avoids SUPABASE_ANON_KEY dependency)
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized: missing auth header' }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userErr } = await supabaseAdmin.auth.getUser(token)
    if (userErr || !user) {
      console.error('ai-moto-agent: auth failed', userErr?.message)
      return new Response(JSON.stringify({ error: 'Unauthorized: ' + (userErr?.message || 'invalid token') }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

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

    // Build messages — supports multimodal content (text + images)
    const apiMessages: Array<{ role: string; content: string | Array<Record<string, unknown>> }> = []
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

    // Build current user message — with images if provided
    const hasImages = Array.isArray(images) && images.length > 0
    if (hasImages) {
      const contentBlocks: Array<Record<string, unknown>> = []
      // Add images first (max 3)
      for (const img of images.slice(0, 3)) {
        if (img.base64 && img.media_type) {
          contentBlocks.push({
            type: 'image',
            source: {
              type: 'base64',
              media_type: img.media_type,
              data: img.base64,
            },
          })
        }
      }
      // Add text
      contentBlocks.push({ type: 'text', text: message })
      apiMessages.push({ role: 'user', content: contentBlocks })
    } else {
      apiMessages.push({ role: 'user', content: message })
    }

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
