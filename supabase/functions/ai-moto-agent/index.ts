import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_ITERATIONS = 5

const SYSTEM_PROMPT = `Jsi AI servisní technik MotoGo24 — půjčovny motorek.

## KRITICKÁ PRAVIDLA (NIKDY neporušuj):
1. NIKDY si nevymýšlej informace. NIKDY nehalucinuj názvy motorek, parametry ani postupy.
2. Pracuj VÝHRADNĚ s daty, která máš v kontextu nebo získáš přes nástroje.
3. Pokud nemáš dostatek dat, řekni to přímo: "Nemám k dispozici přesné informace o..." nebo "Na 100% to nemohu potvrdit, ale mohlo by to být..."
4. Pokud si nejsi jistý, nabídni obecnou radu a dodej: "Pro přesnou diagnostiku kontaktujte naši SOS linku: +420 774 256 271"
5. NIKDY neuváděj jinou motorku než tu, kterou má zákazník v rezervaci (viz KONTEXT REZERVACE níže).

## Co umíš:
- Diagnostika závad na základě popisu nebo fotek
- Rady k obsluze a funkcím konkrétní motorky
- Informace o rezervaci zákazníka
- Obecné rady pro jízdu a bezpečnost

## Formát odpovědi:
Na konci každé odpovědi přidej JSON blok:
---JSON---
{"suggest_sos": true/false}
---END---
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.

Odpovídej v češtině, stručně a konkrétně pro daný model motorky.`

// ─── Tool definitions (Anthropic tool_use format) ───

const TOOLS = [
  {
    name: 'get_active_booking',
    description: 'Vrátí aktivní nebo nadcházející rezervaci zákazníka s kompletními detaily motorky. Volej jako první krok při každém dotazu, abys zjistil jakou motorku zákazník právě má.',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
  {
    name: 'get_booking_history',
    description: 'Vrátí všechny rezervace zákazníka (aktivní, dokončené, zrušené). Užitečné když se zákazník ptá na předchozí pronájmy.',
    input_schema: {
      type: 'object' as const,
      properties: {
        limit: {
          type: 'number',
          description: 'Maximální počet rezervací (default 10)',
        },
      },
      required: [],
    },
  },
  {
    name: 'get_motorcycle_manual',
    description: 'Vrátí kompletní specifikace a návod motorky — motor, výkon, ABS, funkce, manual_url atd. Volej když potřebuješ detailní info o konkrétní motorce.',
    input_schema: {
      type: 'object' as const,
      properties: {
        motorcycle_id: {
          type: 'string',
          description: 'UUID motorky (z výsledku get_active_booking)',
        },
        brand: {
          type: 'string',
          description: 'Značka motorky (alternativa k motorcycle_id)',
        },
        model: {
          type: 'string',
          description: 'Model motorky (alternativa k motorcycle_id)',
        },
      },
      required: [],
    },
  },
  {
    name: 'search_troubleshooting',
    description: 'Hledá v troubleshooting databázi — diagnostika závad, kontrolky, postup při poruše. Volej když zákazník popisuje problém nebo se ptá na kontrolku.',
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'Popis problému nebo hledaný výraz (česky)',
        },
        motorcycle_id: {
          type: 'string',
          description: 'UUID motorky pro filtraci výsledků (volitelné)',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'get_fleet_overview',
    description: 'Vrátí přehled všech dostupných motorek ve flotile — značka, model, kategorie, objem motoru, ABS. Volej když se zákazník ptá na nabídku nebo srovnání.',
    input_schema: {
      type: 'object' as const,
      properties: {},
      required: [],
    },
  },
]

// ─── Tool execution ───

async function executeTool(
  toolName: string,
  input: Record<string, unknown>,
  supabaseAdmin: SupabaseClient,
  userId: string,
): Promise<unknown> {
  switch (toolName) {
    case 'get_active_booking': {
      const { data, error } = await supabaseAdmin
        .from('bookings')
        .select(`
          id, status, payment_status, start_date, end_date, pickup_time,
          total_price, extras_price, pickup_method, return_method,
          mileage_start, mileage_end, notes, booking_source,
          motorcycles(
            id, model, brand, spz, engine_type, engine_cc, power_kw, power_hp,
            weight_kg, has_abs, has_asc, features, manual_url, description,
            ideal_usage, category, fuel_tank_l, seat_height_mm, color, mileage,
            year, license_required, image_url
          )
        `)
        .eq('user_id', userId)
        .in('status', ['active', 'reserved'])
        .order('start_date', { ascending: false })
        .limit(1)

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Zákazník nemá žádnou aktivní ani nadcházející rezervaci.' }
      return data[0]
    }

    case 'get_booking_history': {
      const limit = typeof input.limit === 'number' ? input.limit : 10
      const { data, error } = await supabaseAdmin
        .from('bookings')
        .select(`
          id, status, payment_status, start_date, end_date, total_price,
          pickup_method, return_method, mileage_start, mileage_end, rating,
          motorcycles(id, model, brand, category, engine_cc)
        `)
        .eq('user_id', userId)
        .order('start_date', { ascending: false })
        .limit(limit)

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Zákazník nemá žádné rezervace.' }
      return data
    }

    case 'get_motorcycle_manual': {
      let query = supabaseAdmin.from('motorcycles').select('*')

      if (input.motorcycle_id) {
        query = query.eq('id', input.motorcycle_id)
      } else if (input.brand || input.model) {
        if (input.brand) query = query.ilike('brand', `%${input.brand}%`)
        if (input.model) query = query.ilike('model', `%${input.model}%`)
      } else {
        return { error: 'Musíš zadat motorcycle_id nebo brand+model.' }
      }

      const { data, error } = await query.limit(1)
      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Motorka nenalezena.' }
      return data[0]
    }

    case 'search_troubleshooting': {
      const searchQuery = (input.query as string) || ''

      // Try motorcycle_knowledge_base table first
      const { data: kbData, error: kbError } = await supabaseAdmin
        .from('motorcycle_knowledge_base')
        .select('*')
        .or(`title.ilike.%${searchQuery}%,content.ilike.%${searchQuery}%`)
        .limit(5)

      if (!kbError && kbData && kbData.length > 0) {
        return kbData
      }

      // Fallback: general troubleshooting knowledge
      return {
        message: 'Tabulka motorcycle_knowledge_base neexistuje nebo neobsahuje relevantní data. Použij obecné diagnostické znalosti.',
        general_tips: {
          red_light: 'Červená kontrolka = STOP, vypněte motor. Možné příčiny: přehřátí, únik oleje, porucha elektroniky. → SOS',
          oil_light: 'Zastavte, vypněte motor. Zkontrolujte hladinu oleje. Při podtečení NEJEĎTE. → SOS',
          abs_light: 'Bliká = ABS dočasně deaktivováno. Zkuste restart. Trvale svítí = opatrně brzdění.',
          temperature: 'OKAMŽITĚ zastavte. Počkejte 15-20 min. NIKDY neotevírejte víčko na horký motor. → SOS',
          wont_start: '1) Spojka stisknutá, 2) Neutrál, 3) Kill switch=RUN, 4) Stojan zasunutý, 5) Choke u karburátorů.',
          flat_tire: 'Snižte rychlost, nebrzděte prudce, zastavte u krajnice. NEJEĎTE dál. → SOS',
          oil_leak: 'ZASTAVTE OKAMŽITĚ, vypněte motor. → SOS',
          battery_low: 'Pod 12V omezte spotřebu. Jumpstart: + na +, - na kostru. → SOS',
          fuel_reserve: 'Rezerva 2-4 L, dojezd cca 30-80 km. Tankujte Natural 95/98.',
          rain_riding: 'Rain mód, snížená rychlost, zvětšené rozestupy, pozor na kanály a listy.',
          emergency_contact: 'MotoGo24: +420 774 256 271 (24/7), info@motogo24.cz',
        },
      }
    }

    case 'get_fleet_overview': {
      const { data, error } = await supabaseAdmin
        .from('motorcycles')
        .select('id, brand, model, category, engine_cc, engine_type, power_kw, power_hp, has_abs, has_asc, license_required, seat_height_mm, weight_kg, fuel_tank_l, price_weekday, price_weekend, image_url')
        .eq('status', 'active')
        .order('brand')

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Žádné aktivní motorky ve flotile.' }
      return data
    }

    default:
      return { error: `Neznámý nástroj: ${toolName}` }
  }
}

// ─── Main handler ───

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { message, booking_id, conversation_history, images } = await req.json()

    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing message' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // ─── JWT auth ───
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

    // ─── Build messages from conversation history ───
    const apiMessages: Array<{ role: string; content: unknown }> = []

    // Inject full conversation history from frontend
    if (conversation_history && Array.isArray(conversation_history)) {
      for (const m of conversation_history) {
        if (m.role === 'user' || m.role === 'assistant') {
          apiMessages.push({ role: m.role, content: m.content })
        }
      }
    }

    // Build current user message — with images if provided (multimodal support)
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

    // ─── Pre-fetch booking context (inject directly into system prompt) ───
    let bookingContext = ''
    try {
      // Try specific booking_id first, then fall back to latest active/reserved
      let bookingQuery = supabaseAdmin
        .from('bookings')
        .select(`
          id, status, payment_status, start_date, end_date, pickup_time,
          total_price, extras_price, pickup_method, return_method, pickup_address, return_address,
          mileage_start, mileage_end, notes, insurance_type,
          motorcycles(
            id, model, brand, spz, engine_type, engine_cc, power_kw, power_hp,
            weight_kg, has_abs, has_asc, features, manual_url, description,
            ideal_usage, category, fuel_tank_l, seat_height_mm, color, mileage,
            year, license_required, image_url
          )
        `)
        .eq('user_id', user.id)

      if (booking_id) {
        bookingQuery = bookingQuery.eq('id', booking_id)
      } else {
        bookingQuery = bookingQuery.in('status', ['active', 'reserved']).order('start_date', { ascending: false })
      }

      const { data: bookingData, error: bookingErr } = await bookingQuery.limit(1)

      if (!bookingErr && bookingData && bookingData.length > 0) {
        const b = bookingData[0]
        const m = b.motorcycles as Record<string, unknown> | null
        if (m) {
          bookingContext = `\n\n## KONTEXT REZERVACE (reálná data z DB — toto je PRAVDA):
- Rezervace #${(b.id as string).substring(0, 8).toUpperCase()}
- Stav: ${b.status}
- Motorka: ${m.brand || '?'} ${m.model || '?'}
- SPZ: ${m.spz || '?'}
- Kategorie: ${m.category || '?'}
- Motor: ${m.engine_type || '?'} ${m.engine_cc || '?'}cc, ${m.power_kw || '?'}kW / ${m.power_hp || '?'}hp
- Hmotnost: ${m.weight_kg || '?'}kg
- ABS: ${m.has_abs ? 'ANO' : 'NE'}, ASC: ${m.has_asc ? 'ANO' : 'NE'}
- Nádrž: ${m.fuel_tank_l || '?'}L, Výška sedla: ${m.seat_height_mm || '?'}mm
- Barva: ${m.color || '?'}, Rok: ${m.year || '?'}
- Popis: ${m.description || 'N/A'}
- Ideální použití: ${m.ideal_usage || 'N/A'}
- Funkce: ${m.features || 'N/A'}
- Návod: ${m.manual_url || 'N/A'}
- Nájezd: ${m.mileage || '?'}km
- Období: ${b.start_date} – ${b.end_date}
- Vyzvednutí: ${b.pickup_method || '?'} ${b.pickup_address ? '(' + b.pickup_address + ')' : ''}
- Vrácení: ${b.return_method || '?'} ${b.return_address ? '(' + b.return_address + ')' : ''}
- Pojištění: ${b.insurance_type || 'N/A'}

DŮLEŽITÉ: Zákazník má motorku "${m.brand} ${m.model}". Veškeré odpovědi MUSÍ být pro tento konkrétní model. NIKDY nezmiňuj jinou motorku.`
        } else {
          bookingContext = `\n\n## KONTEXT REZERVACE:
Zákazník má rezervaci #${(b.id as string).substring(0, 8).toUpperCase()} (stav: ${b.status}), ale detaily motorky se nepodařilo načíst. Použij nástroj get_active_booking pro zjištění detailů.`
        }
      } else {
        bookingContext = `\n\n## KONTEXT REZERVACE:
Zákazník nemá aktivní rezervaci nebo se nepodařilo načíst data. Při dotazech na konkrétní motorku použij nástroj get_active_booking. NIKDY si nevymýšlej, jakou motorku má zákazník.`
      }
    } catch (prefetchErr) {
      console.error('ai-moto-agent: booking prefetch error', prefetchErr)
      bookingContext = '\n\nNepodařilo se předem načíst rezervaci. Použij get_active_booking.'
    }

    const systemPrompt = SYSTEM_PROMPT + bookingContext

    // ─── Agentic loop ───
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
          max_tokens: 2048,
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

      // If end_turn — extract final text and break
      if (stopReason === 'end_turn') {
        const textBlocks = (aiResult.content || []).filter((c: { type: string }) => c.type === 'text')
        finalText = textBlocks.map((c: { text: string }) => c.text).join('\n')
        break
      }

      // If tool_use — execute tools and continue loop
      if (stopReason === 'tool_use') {
        // Push assistant response (contains tool_use blocks) into messages
        apiMessages.push({ role: 'assistant', content: aiResult.content })

        // Execute each tool call and collect results
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

        // Push tool results as user message
        apiMessages.push({ role: 'user', content: toolResults })
        continue
      }

      // Unexpected stop reason — extract whatever text we have
      const textBlocks = (aiResult.content || []).filter((c: { type: string }) => c.type === 'text')
      finalText = textBlocks.map((c: { text: string }) => c.text).join('\n') || 'Odpověď nedostupná.'
      break
    }

    if (!finalText) {
      finalText = 'Omlouvám se, nepodařilo se dokončit analýzu. Zkuste prosím znovu.'
    }

    // ─── Parse ---JSON--- block from final response ───
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
