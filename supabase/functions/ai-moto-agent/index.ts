import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { TOOLS } from './tools-definitions.ts'
import { executeTool } from './tools-executor.ts'
import { loadAgentConfig, buildSystemPrompt, formatBookingContext, formatMultipleBookingsContext } from './booking-context.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_ITERATIONS = 5

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { message, booking_id, conversation_history, images } = await req.json()

    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing message' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // -- JWT auth --
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

    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // -- Load agent config from app_settings --
    const agentConfig = await loadAgentConfig(supabaseAdmin)
    const dynamicSystemPrompt = buildSystemPrompt(agentConfig)
    const maxTokens = agentConfig?.max_tokens || 2048

    // -- Build messages from conversation history --
    const apiMessages: Array<{ role: string; content: unknown }> = []

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
      for (const img of images.slice(0, 3)) {
        if (img.base64 && img.media_type) {
          contentBlocks.push({
            type: 'image',
            source: { type: 'base64', media_type: img.media_type, data: img.base64 },
          })
        }
      }
      contentBlocks.push({ type: 'text', text: message })
      apiMessages.push({ role: 'user', content: contentBlocks })
    } else {
      apiMessages.push({ role: 'user', content: message })
    }

    // -- Pre-fetch booking context --
    let bookingContext = ''
    try {
      const bookingFields = `
        id, status, payment_status, start_date, end_date, pickup_time,
        total_price, extras_price, pickup_method, return_method, pickup_address, return_address,
        mileage_start, mileage_end, notes, insurance_type,
        motorcycles(
          id, model, brand, spz, engine_type, engine_cc, power_kw, power_hp,
          weight_kg, has_abs, has_asc, features, manual_url, description,
          ideal_usage, category, fuel_tank_l, seat_height_mm, color, mileage,
          year, license_required, image_url
        )
      `

      if (booking_id) {
        const { data, error } = await supabaseAdmin
          .from('bookings')
          .select(bookingFields)
          .eq('user_id', user.id)
          .eq('id', booking_id)
          .limit(1)

        if (!error && data && data.length > 0) {
          bookingContext = formatBookingContext(data[0], null)
        }
      } else {
        const { data: allBookings, error: allErr } = await supabaseAdmin
          .from('bookings')
          .select(bookingFields)
          .eq('user_id', user.id)
          .in('status', ['active', 'confirmed', 'reserved'])
          .order('start_date', { ascending: false })
          .limit(10)

        if (!allErr && allBookings && allBookings.length > 0) {
          const activeBooking = allBookings.find(b => b.status === 'active')
          const otherBookings = allBookings.filter(b => b.status !== 'active')

          if (activeBooking) {
            bookingContext = formatBookingContext(activeBooking, otherBookings.length > 0 ? otherBookings : null)
          } else if (otherBookings.length === 1) {
            bookingContext = formatBookingContext(otherBookings[0], null)
          } else if (otherBookings.length > 1) {
            bookingContext = formatMultipleBookingsContext(otherBookings)
          }
        }
      }

      if (!bookingContext) {
        bookingContext = `\n\n## KONTEXT REZERVACE:
Zákazník nemá aktivní rezervaci nebo se nepodařilo načíst data. Při dotazech na konkrétní motorku použij nástroj get_active_booking. NIKDY si nevymýšlej, jakou motorku má zákazník.`
      }
    } catch (prefetchErr) {
      console.error('ai-moto-agent: booking prefetch error', prefetchErr)
      bookingContext = '\n\nNepodařilo se předem načíst rezervaci. Použij get_active_booking.'
    }

    const systemPrompt = dynamicSystemPrompt + bookingContext

    // -- Agentic loop --
    let finalText = ''
    for (let i = 0; i < MAX_ITERATIONS; i++) {
      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-sonnet-4-20250514',
          max_tokens: maxTokens,
          system: systemPrompt,
          tools: TOOLS,
          messages: apiMessages,
        }),
      })

      if (!response.ok) {
        const errText = await response.text()
        console.error(`Anthropic API error (iteration ${i}):`, response.status, errText)
        return new Response(JSON.stringify({ error: 'AI service error' }), {
          status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }

      const aiResult = await response.json()
      const stopReason = aiResult.stop_reason

      if (stopReason === 'end_turn') {
        const textBlocks = (aiResult.content || []).filter((c: { type: string }) => c.type === 'text')
        finalText = textBlocks.map((c: { text: string }) => c.text).join('\n')
        break
      }

      if (stopReason === 'tool_use') {
        apiMessages.push({ role: 'assistant', content: aiResult.content })

        const toolResults: Array<{ type: string; tool_use_id: string; content: string }> = []
        const toolCalls = (aiResult.content || []).filter((c: { type: string }) => c.type === 'tool_use')

        for (const toolCall of toolCalls) {
          console.log(`ai-moto-agent: tool call [${i}] ${toolCall.name}`, JSON.stringify(toolCall.input))
          const result = await executeTool(toolCall.name, toolCall.input || {}, supabaseAdmin, user.id)
          toolResults.push({
            type: 'tool_result',
            tool_use_id: toolCall.id,
            content: JSON.stringify(result),
          })
        }

        apiMessages.push({ role: 'user', content: toolResults })
        continue
      }

      const textBlocks = (aiResult.content || []).filter((c: { type: string }) => c.type === 'text')
      finalText = textBlocks.map((c: { text: string }) => c.text).join('\n') || 'Odpověď nedostupná.'
      break
    }

    if (!finalText) {
      finalText = 'Omlouvám se, nepodařilo se dokončit analýzu. Zkuste prosím znovu.'
    }

    // -- Parse ---JSON--- block from final response --
    let suggest_sos = false
    let reply = finalText

    const jsonMatch = finalText.match(/---JSON---\s*(\{[^}]+\})\s*---END---/)
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[1])
        suggest_sos = parsed.suggest_sos ?? false
      } catch { /* ignore parse errors */ }
      reply = finalText.replace(/---JSON---[\s\S]*?---END---/, '').trim()
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
