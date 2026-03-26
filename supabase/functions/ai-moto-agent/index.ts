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

const FALLBACK_SYSTEM_PROMPT = `Jsi AI servisní technik MotoGo24 — půjčovny motorek.

## KRITICKÁ PRAVIDLA (NIKDY neporušuj):
1. NIKDY si nevymýšlej informace. NIKDY nehalucinuj názvy motorek, parametry ani postupy.
2. Pracuj VÝHRADNĚ s daty, která máš v kontextu nebo získáš přes nástroje.
3. Pokud nemáš dostatek dat, řekni to přímo: "Nemám k dispozici přesné informace o..."
4. NIKDY neuváděj jinou motorku než tu, kterou má zákazník v rezervaci (viz KONTEXT REZERVACE níže).

## DIAGNOSTICKÝ POSTUP (VŽDY dodržuj):
Než dáš radu, MUSÍŠ mít 100% jasno o čem zákazník mluví. Postupuj takto:
1. **Upřesni problém** — ptej se na detaily dokud nemáš jasný obraz:
   - Které konkrétní světlo/díl/funkce nefunguje?
   - Kdy to začalo? (za jízdy, po startu, náhle, postupně?)
   - Svítí nějaké kontrolky na palubní desce? Které?
   - Slyší nějaký zvuk? Cítí nějaký zápach?
2. **Požádej o fotku** — pokud zákazník neposlal fotku, VŽDY požádej: "Můžete mi poslat fotku problému / palubní desky / kontrolek?"
3. **Teprve potom raď** — až máš dostatek informací, dej konkrétní radu pro daný model.

NIKDY nedávej dlouhý seznam možných příčin na vágní popis. Místo toho se PTEJ.

Příklad ŠPATNĚ: "Nefunguje mi světlo" → dlouhý výpis všech možných příčin
Příklad SPRÁVNĚ: "Nefunguje mi světlo" → "Rozumím. Abych vám mohl pomoci, potřebuji vědět:
1) Které světlo přesně? (přední, zadní, blinkr, brzdové, kontrolky?)
2) Nefunguje úplně, nebo bliká/svítí slabě?
3) Můžete mi poslat fotku palubní desky?"

## Co umíš:
- Diagnostika závad na základě popisu nebo fotek
- Rady k obsluze a funkcím konkrétní motorky zákazníka
- Informace o rezervaci zákazníka
- Obecné rady pro jízdu a bezpečnost

## Formát odpovědi:
Na konci každé odpovědi přidej JSON blok:
---JSON---
{"suggest_sos": true/false}
---END---
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.

Odpovídej v češtině, stručně a konkrétně pro daný model motorky.`

const TONE_MAP: Record<string, string> = {
  friendly: 'Komunikuj přátelsky a neformálně, buď vlídný a vstřícný.',
  professional: 'Komunikuj profesionálně a formálně, buď věcný a stručný.',
  concise: 'Odpovídej maximálně stručně — krátké, jasné věty bez zbytečností.',
  detailed: 'Poskytuj podrobná vysvětlení s kontextem a pozadím problému.',
}

interface AgentConfig {
  persona_name?: string
  system_prompt?: string
  situations?: string[]
  forbidden?: string[]
  mustDo?: string[]
  tone?: string
  max_tokens?: number
  enabled?: boolean
}

async function loadAgentConfig(supabaseAdmin: SupabaseClient): Promise<AgentConfig | null> {
  try {
    const { data, error } = await supabaseAdmin
      .from('app_settings')
      .select('value')
      .eq('key', 'ai_moto_agent_config')
      .single()

    if (error || !data?.value) return null
    return data.value as AgentConfig
  } catch {
    return null
  }
}

function buildSystemPrompt(config: AgentConfig | null): string {
  if (!config || !config.enabled) return FALLBACK_SYSTEM_PROMPT

  let prompt = ''

  // Persona header
  if (config.persona_name) {
    prompt += `Jsi ${config.persona_name} pro MotoGo24 — půjčovnu motorek.\n\n`
  }

  // Main system prompt from admin
  if (config.system_prompt) {
    prompt += config.system_prompt
  } else {
    prompt += FALLBACK_SYSTEM_PROMPT
  }

  // Tone
  if (config.tone && TONE_MAP[config.tone]) {
    prompt += `\n\n## TÓN KOMUNIKACE:\n${TONE_MAP[config.tone]}`
  }

  // Situation rules
  if (config.situations && config.situations.length > 0) {
    prompt += '\n\n## SITUAČNÍ PRAVIDLA:'
    for (const s of config.situations) prompt += `\n- ${s}`
  }

  // Must do
  if (config.mustDo && config.mustDo.length > 0) {
    prompt += '\n\n## VŽDY MUSÍ UDĚLAT:'
    for (const m of config.mustDo) prompt += `\n- ✅ ${m}`
  }

  // Forbidden
  if (config.forbidden && config.forbidden.length > 0) {
    prompt += '\n\n## ZAKÁZÁNO:'
    for (const f of config.forbidden) prompt += `\n- ❌ ${f}`
  }

  // Always append critical safety rules & response format
  prompt += `

## KRITICKÁ BEZPEČNOSTNÍ PRAVIDLA (platí vždy):
1. NIKDY si nevymýšlej informace — pracuj výhradně s reálnými daty.
2. NIKDY neuváděj jinou motorku než tu z rezervace zákazníka.
3. Pokud nemáš dostatek dat, řekni to přímo.

## Formát odpovědi:
Na konci každé odpovědi přidej JSON blok:
---JSON---
{"suggest_sos": true/false}
---END---
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.

Odpovídej v češtině.`

  return prompt
}

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
      // Priority: status='active' first, then confirmed/reserved
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
        .in('status', ['active', 'confirmed', 'reserved'])
        .order('start_date', { ascending: false })
        .limit(10)

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Zákazník nemá žádnou aktivní ani nadcházející rezervaci.' }
      // Prioritize active booking
      const active = data.find(b => b.status === 'active')
      if (active) return active
      // If multiple non-active, return all so AI can ask
      if (data.length > 1) return { multiple_bookings: data, message: 'Zákazník má více rezervací. Zeptej se, o kterou motorku jde.' }
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

// ─── Booking context formatters ───

function formatBookingContext(b: Record<string, unknown>, otherBookings: Array<Record<string, unknown>> | null): string {
  const m = b.motorcycles as Record<string, unknown> | null
  if (!m) {
    return `\n\n## KONTEXT REZERVACE:
Zákazník má rezervaci #${(b.id as string).substring(0, 8).toUpperCase()} (stav: ${b.status}), ale detaily motorky se nepodařilo načíst. Použij nástroj get_active_booking pro zjištění detailů.`
  }

  let ctx = `\n\n## KONTEXT REZERVACE (reálná data z DB — toto je PRAVDA):
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

DŮLEŽITÉ: Zákazník má AKTIVNÍ motorku "${m.brand} ${m.model}". Veškeré odpovědi MUSÍ být pro tento konkrétní model. NIKDY nezmiňuj jinou motorku.`

  if (otherBookings && otherBookings.length > 0) {
    ctx += `\n\nZákazník má také nadcházející rezervace:`
    for (const ob of otherBookings) {
      const om = ob.motorcycles as Record<string, unknown> | null
      ctx += `\n- #${(ob.id as string).substring(0, 8).toUpperCase()}: ${om ? (om.brand + ' ' + om.model) : '?'} (${ob.status}, ${ob.start_date} – ${ob.end_date})`
    }
    ctx += `\nAle tyto rezervace NEJSOU aktivní — odpovídej pouze o aktuálně aktivní motorce.`
  }

  return ctx
}

function formatMultipleBookingsContext(bookings: Array<Record<string, unknown>>): string {
  let ctx = `\n\n## KONTEXT REZERVACE — VÍCE REZERVACÍ:
Zákazník má více rezervací, žádná zatím nemá stav "active". MUSÍŠ se nejdříve ZEPTAT, o kterou motorku/rezervaci jde:\n`
  for (const b of bookings) {
    const m = b.motorcycles as Record<string, unknown> | null
    ctx += `- #${(b.id as string).substring(0, 8).toUpperCase()}: ${m ? (m.brand + ' ' + m.model) : '?'} (${b.status}, ${b.start_date} – ${b.end_date})\n`
  }
  ctx += `\nDŮLEŽITÉ: NIKDY nepředpokládej, o kterou motorku jde. Vždy se ZEPTEJ: "Vidím, že máte více rezervací: [seznam]. O kterou motorku se jedná?"`
  return ctx
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

    // ─── Load agent config from app_settings ───
    const agentConfig = await loadAgentConfig(supabaseAdmin)
    const dynamicSystemPrompt = buildSystemPrompt(agentConfig)
    const maxTokens = agentConfig?.max_tokens || 2048

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
        // Specific booking requested
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
        // Fetch ALL active/reserved/confirmed bookings to find the right one
        const { data: allBookings, error: allErr } = await supabaseAdmin
          .from('bookings')
          .select(bookingFields)
          .eq('user_id', user.id)
          .in('status', ['active', 'confirmed', 'reserved'])
          .order('start_date', { ascending: false })
          .limit(10)

        if (!allErr && allBookings && allBookings.length > 0) {
          const now = new Date()
          // Prioritize: 1) status='active', 2) confirmed/reserved where start <= now <= end
          const activeBooking = allBookings.find(b => b.status === 'active')
          const otherBookings = allBookings.filter(b => b.status !== 'active')

          if (activeBooking) {
            bookingContext = formatBookingContext(activeBooking, otherBookings.length > 0 ? otherBookings : null)
          } else if (otherBookings.length === 1) {
            bookingContext = formatBookingContext(otherBookings[0], null)
          } else if (otherBookings.length > 1) {
            // Multiple non-active bookings — list all, let AI ask
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
