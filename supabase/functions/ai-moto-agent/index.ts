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

const SYSTEM_PROMPT = `Jsi zkušený motomechanik a servisní technik MotoGo24 — půjčovny motorek.
Zákazník ti popisuje problém nebo má dotaz. Pomoz mu:
1. Diagnostikovat závadu na základě příznaků
2. Doporučit okamžité řešení (co udělat na místě)
3. Pokud je závada vážná, doporuč kontaktovat SOS
4. Odpovědět na jakýkoli technický dotaz k motorce

KONTEXT REZERVACÍ: Dostaneš kompletní přehled všech rezervací zákazníka (aktivní, nadcházející i historické).
Dotaz zákazníka se v naprosté většině případů týká AKTIVNÍ rezervace a motorky, kterou právě má.
Pokud má zákazník aktivní rezervaci, automaticky předpokládej, že se ptá na tu motorku, pokud neřekne jinak.

NÁVODY K OBSLUZE: Dostaneš seznam všech dostupných návodů k motorkám z naší flotily.
Když se zákazník ptá na něco co je v návodu (kontrolky, ovládání, funkce), využij informace z kontextu.
Pokud má motorka manual_url, můžeš zákazníka odkázat na konkrétní návod.

Odpovídej stručně, srozumitelně, v češtině. Neptej se víc než 2 otázky najednou.
Pokud máš info o konkrétní motorce (model, manuál, specifikace), vždy je využij v odpovědi.

FOTKY KONTROLEK: Zákazník ti může poslat fotky budíků / přístrojové desky motorky.
Když dostaneš fotku, pečlivě analyzuj viditelné kontrolky, varování a indikátory.
Popiš co vidíš (které kontrolky svítí, jakou mají barvu) a vysvětli co znamenají.
Pokud je na fotce špatná viditelnost, požádej o lepší fotku.

DŮLEŽITÉ: Na konci každé odpovědi přidej JSON blok v tomto formátu (na samostatném řádku):
---JSON---
{"suggest_sos": true/false}
---END---

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

    // Fetch ALL user reservations (active, upcoming, historical)
    let reservationsContext = ''
    let activeBookingMoto = ''
    const { data: allBookings } = await supabaseAdmin
      .from('bookings')
      .select('id, status, payment_status, start_date, end_date, total_price, extras_price, pickup_method, return_method, mileage_start, mileage_end, notes, booking_source, motorcycles(id, model, brand, engine_type, engine_cc, power_kw, power_hp, weight_kg, has_abs, has_asc, features, manual_url, description, ideal_usage, category, fuel_tank_l, seat_height_mm, color, mileage)')
      .eq('user_id', user.id)
      .order('start_date', { ascending: false })
      .limit(20)

    if (allBookings && allBookings.length > 0) {
      const now = new Date()
      const today = now.toISOString().split('T')[0]
      const parts: string[] = []

      for (const b of allBookings) {
        const m = b.motorcycles as Record<string, unknown> | null
        const mName = m ? `${m.brand || ''} ${m.model || ''}`.trim() : 'neznámá'
        const statusMap: Record<string, string> = { active: 'AKTIVNÍ', reserved: 'Nadcházející', completed: 'Dokončená', cancelled: 'Zrušená', pending: 'Čeká na platbu' }
        const label = statusMap[b.status] || b.status

        let line = `[${label}] ${mName} | ${b.start_date?.split('T')[0] || '?'} – ${b.end_date?.split('T')[0] || '?'}`
        if (b.mileage_start) line += ` | Nájezd: ${b.mileage_start}${b.mileage_end ? '→' + b.mileage_end : ''} km`
        parts.push(line)

        // Identify active booking moto for detailed context
        if ((b.status === 'active' || (b.status === 'reserved' && b.start_date?.split('T')[0] <= today)) && m) {
          activeBookingMoto = `AKTIVNÍ MOTORKA zákazníka: ${m.brand || ''} ${m.model || ''}. Motor: ${m.engine_type || ''} ${m.engine_cc || ''}cc, ${m.power_kw || ''}kW/${m.power_hp || ''}HP. Hmotnost: ${m.weight_kg || '?'}kg. ABS: ${m.has_abs ? 'ano' : 'ne'}, ASC: ${m.has_asc ? 'ano' : 'ne'}. Nádrž: ${m.fuel_tank_l || '?'}L. Výška sedla: ${m.seat_height_mm || '?'}mm.`
          if (m.features) activeBookingMoto += ` Výbava: ${m.features}`
          if (m.description) activeBookingMoto += ` Popis: ${m.description}`
          if (m.manual_url) activeBookingMoto += ` Návod: ${m.manual_url}`
          if (m.mileage) activeBookingMoto += ` Aktuální nájezd: ${m.mileage} km`
        }
      }

      reservationsContext = `\n\nREZERVACE ZÁKAZNÍKA (${allBookings.length}):\n${parts.join('\n')}`
    }

    // If specific booking_id provided, ensure we have that moto's details
    if (booking_id && !activeBookingMoto) {
      const { data: booking } = await supabaseAdmin
        .from('bookings')
        .select('moto_id, motorcycles(model, manual_url, engine_type, power_kw, power_hp, engine_cc, weight_kg, has_abs, has_asc, features, brand, description, fuel_tank_l, seat_height_mm, color, mileage, category, ideal_usage)')
        .eq('id', booking_id)
        .single()

      if (booking?.motorcycles) {
        const m = booking.motorcycles as Record<string, unknown>
        activeBookingMoto = `AKTIVNÍ MOTORKA zákazníka: ${m.brand || ''} ${m.model || ''}. Motor: ${m.engine_type || ''} ${m.engine_cc || ''}cc, ${m.power_kw || ''}kW/${m.power_hp || ''}HP. Hmotnost: ${m.weight_kg || '?'}kg. ABS: ${m.has_abs ? 'ano' : 'ne'}, ASC: ${m.has_asc ? 'ano' : 'ne'}. Nádrž: ${m.fuel_tank_l || '?'}L.`
        if (m.features) activeBookingMoto += ` Výbava: ${m.features}`
        if (m.description) activeBookingMoto += ` Popis: ${m.description}`
        if (m.manual_url) activeBookingMoto += ` Návod: ${m.manual_url}`
        if (m.mileage) activeBookingMoto += ` Aktuální nájezd: ${m.mileage} km`
      }
    }

    // Fetch ALL motorcycle manuals from fleet
    let manualsContext = ''
    const { data: allMotos } = await supabaseAdmin
      .from('motorcycles')
      .select('model, brand, manual_url, engine_type, engine_cc, power_kw, has_abs, has_asc, features, description, category, fuel_tank_l, seat_height_mm')
      .eq('status', 'active')
      .order('model')

    if (allMotos && allMotos.length > 0) {
      const manualLines: string[] = []
      for (const m of allMotos) {
        let line = `${m.brand || ''} ${m.model || ''}: ${m.engine_type || ''} ${m.engine_cc || ''}cc, ${m.power_kw || ''}kW, ABS:${m.has_abs ? 'ano' : 'ne'}, ASC:${m.has_asc ? 'ano' : 'ne'}`
        if (m.features) line += `, Výbava: ${m.features}`
        if (m.manual_url) line += ` | Návod: ${m.manual_url}`
        manualLines.push(line)
      }
      manualsContext = `\n\nDOSTUPNÉ MOTORKY A NÁVODY (${allMotos.length}):\n${manualLines.join('\n')}`
    }

    // Build messages — supports multimodal content (text + images)
    const apiMessages: Array<{ role: string; content: string | Array<Record<string, unknown>> }> = []
    const fullContext = [activeBookingMoto, reservationsContext, manualsContext].filter(Boolean).join('\n')
    if (fullContext) {
      apiMessages.push({ role: 'user', content: `[Kontext zákazníka]\n${fullContext}` })
      apiMessages.push({ role: 'assistant', content: 'Rozumím, mám kompletní přehled o vašich rezervacích a motorce. Jak vám mohu pomoci?' })
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
        max_tokens: 2048,
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
    let suggest_sos = false
    let reply = aiText

    const jsonMatch = aiText.match(/---JSON---\s*(\{[^}]+\})\s*---END---/)
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[1])
        suggest_sos = parsed.suggest_sos ?? false
      } catch { /* ignore parse errors */ }
      reply = aiText.replace(/---JSON---[\s\S]*?---END---/, '').trim()
    }

    return new Response(JSON.stringify({ reply, suggest_sos }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('ai-moto-agent error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
