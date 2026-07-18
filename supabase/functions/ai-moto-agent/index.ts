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
    const { message, booking_id, conversation_history, images, lang } = await req.json()
    const userLang = (typeof lang === 'string' && lang.trim()) ? lang.trim().slice(0, 5) : 'cs'

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
    let maxTokens = agentConfig?.max_tokens || 2048

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
        motorcycles!moto_id(
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
      // Retry až 3× na 429/5xx/timeout/síťovou chybu (stejná pojistka jako ai-public-agent) —
      // dřív jediný transientní výpadek Anthropic shodil celý request na 502 a chat v appce umřel.
      let response: Response | null = null
      let lastErr = ''
      for (let attempt = 0; attempt < 3; attempt++) {
        const ctrl = new AbortController()
        const timer = setTimeout(() => ctrl.abort(), 45_000) // per-call timeout
        try {
          response = await fetch('https://api.anthropic.com/v1/messages', {
            method: 'POST',
            headers: {
              'x-api-key': ANTHROPIC_API_KEY,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: JSON.stringify({
              model: 'claude-sonnet-4-6',
              max_tokens: maxTokens,
              system: systemPrompt,
              tools: TOOLS,
              messages: apiMessages,
            }),
            signal: ctrl.signal,
          })
        } catch (e) {
          response = null
          lastErr = `fetch_failed: ${(e as Error).message}`
          clearTimeout(timer)
          await new Promise((r) => setTimeout(r, 300 * (attempt + 1) ** 2))
          continue
        }
        clearTimeout(timer)
        if (response.ok) break
        lastErr = await response.text()
        if (response.status >= 500 || response.status === 429) {
          await new Promise((r) => setTimeout(r, 300 * (attempt + 1) ** 2))
          continue
        }
        break
      }

      if (!response || !response.ok) {
        // Po vyčerpání pokusů vrať slušnou odpověď místo 502 — konverzace v appce zůstane živá
        // a historie se neztratí; zákazník nemusí nic opakovat, stačí napsat „pokračuj".
        console.error(`Anthropic API failed (iteration ${i}):`, response?.status || 'no-resp', String(lastErr).slice(0, 300))
        return new Response(JSON.stringify({
          reply: 'Omlouvám se, odpověď mi teď trvala moc dlouho. Napište prosím jen „pokračuj" — celou konverzaci si pamatuji a navážu, nemusíte nic opakovat.',
          suggest_sos: false,
        }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
      }

      const aiResult = await response.json()
      const stopReason = aiResult.stop_reason

      // Odpověď uříznutá limitem tokenů → jednou zopakuj s maximálním stropem, ať zákazník
      // nedostane radu useknutou uprostřed věty.
      if (stopReason === 'max_tokens' && maxTokens < 8000) {
        maxTokens = 8000
        continue
      }

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
          const result = await executeTool(toolCall.name, toolCall.input || {}, supabaseAdmin, user.id, userLang)
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

    // -- Log konverzace do ai_customer_conversations (Velín → Analýza → AI konverzace) --
    // Appka posílá celou historii při každé zprávě: prázdná historie = nová
    // konverzace (INSERT), jinak se přepíše poslední konverzace uživatele.
    try {
      const MSG_CAP = 8000
      const historyMsgs = (Array.isArray(conversation_history) ? conversation_history : [])
        .filter((m: { role?: string; content?: unknown }) =>
          (m?.role === 'user' || m?.role === 'assistant') && typeof m?.content === 'string')
        .map((m: { role: string; content: string }) => ({
          role: m.role,
          content: m.content.slice(0, MSG_CAP),
        }))
      const userContent = hasImages ? `[${images.length}× foto] ${message}` : message
      const fullMessages = [
        ...historyMsgs,
        { role: 'user', content: String(userContent).slice(0, MSG_CAP) },
        { role: 'assistant', content: reply.slice(0, MSG_CAP) },
      ]

      let updatedId: string | null = null
      if (historyMsgs.length > 0) {
        const { data: last } = await supabaseAdmin
          .from('ai_customer_conversations')
          .select('id')
          .eq('user_id', user.id)
          .order('updated_at', { ascending: false })
          .limit(1)
          .maybeSingle()
        if (last) {
          const { error: updErr } = await supabaseAdmin
            .from('ai_customer_conversations')
            .update({ messages: fullMessages, ...(booking_id ? { booking_id } : {}) })
            .eq('id', last.id)
          if (!updErr) updatedId = last.id
        }
      }
      if (!updatedId) {
        await supabaseAdmin.from('ai_customer_conversations').insert({
          user_id: user.id,
          title: String(message).slice(0, 80),
          messages: fullMessages,
          booking_id: booking_id || null,
        })
      }
    } catch (logErr) {
      console.error('ai-moto-agent: conversation log error', logErr)
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
