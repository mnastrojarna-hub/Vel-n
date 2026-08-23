import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { TOOLS } from './tools-definitions.ts'
import { executeTool } from './tools-executor.ts'
import { loadAgentConfig, buildSystemPrompt, buildDateHeader, formatBookingContext, formatMultipleBookingsContext } from './booking-context.ts'

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
    const { message, booking_id, conversation_history, images, lang, conversation_id, supports_images } = await req.json()
    // conversation_id (volitelné, UUID): appka jím může adresovat KONKRÉTNÍ vlákno logu.
    // Bez něj platí dosavadní heuristika „update poslední konverzace uživatele" — ta se
    // ale při dvou souběžných konverzacích slévá; appka by měla id začít posílat.
    const convId = (typeof conversation_id === 'string' && /^[0-9a-f-]{8,40}$/i.test(conversation_id)) ? conversation_id : null
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
    // Vypnutí agenta z Velína musí agenta REÁLNĚ vypnout (dřív jen shodilo custom prompt
    // na fallback a Anthropic se volal dál — nešlo ho provozně utnout).
    if (agentConfig?.enabled === false) {
      return new Response(JSON.stringify({
        reply: 'AI asistent je momentálně vypnutý. Ozvěte se nám prosím na +420 774 256 271 nebo info@motogo24.cz — v nouzi použijte SOS tlačítko v aplikaci.',
        suggest_sos: false,
      }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
    }
    const dynamicSystemPrompt = buildSystemPrompt(agentConfig)
    let maxTokens = Math.min(Math.max(Number(agentConfig?.max_tokens) || 2048, 1024), 8000)

    // -- Build messages from conversation history --
    const apiMessages: Array<{ role: string; content: unknown }> = []

    if (conversation_history && Array.isArray(conversation_history)) {
      // Pojistky proti nákladům/přetečení kontextu (stejně jako ai-public-agent): jen validní
      // role, per-zpráva 8000 znaků, celkem ~240k znaků a max 400 zpráv — zahazují se NEJSTARŠÍ.
      const MAX_MSGS = 400, PER_MSG = 8000, TOTAL = 240_000
      let hist = (conversation_history as Array<{ role?: string; content?: unknown }>)
        .filter((m) => (m?.role === 'user' || m?.role === 'assistant') && typeof m?.content === 'string' && (m.content as string).trim() !== '')
        .map((m) => ({ role: String(m.role), content: (m.content as string).length > PER_MSG ? (m.content as string).slice(0, PER_MSG) : (m.content as string) }))
      if (hist.length > MAX_MSGS) hist = hist.slice(-MAX_MSGS)
      let totalChars = hist.reduce((n, m) => n + m.content.length, 0)
      while (hist.length > 1 && totalChars > TOTAL) { totalChars -= hist[0].content.length; hist.shift() }
      while (hist.length && hist[0].role !== 'user') hist.shift()
      for (const m of hist) apiMessages.push({ role: m.role, content: m.content })
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
          weight_kg, has_abs, has_asc, features, manual_url, manual_external_url, description,
          ideal_usage, category, fuel_tank_l, seat_height_mm, color, mileage,
          year, license_required, image_url
        )
      `

      if (booking_id) {
        // Appka volí booking_id heuristikou „nejnovější zaplacená active/reserved dle
        // start_date" — když má zákazník AKTIVNÍ pronájem a k tomu pozdější budoucí
        // rezervaci, přišlo id té BUDOUCÍ a agent diagnostikoval úplně jinou motorku
        // (reálný případ 26. 7. 2026: zákazník jel na V-Stromu, kontext tvrdil Tiger).
        // Servisní agent proto VŽDY preferuje aktivní pronájem; pinovaná rezervace
        // se použije, jen když žádný aktivní není, a ostatní se vypíšou jako další.
        const [pinnedRes, listRes] = await Promise.all([
          supabaseAdmin.from('bookings').select(bookingFields)
            .eq('user_id', user.id).eq('id', booking_id).limit(1),
          supabaseAdmin.from('bookings').select(bookingFields)
            .eq('user_id', user.id).in('status', ['active', 'confirmed', 'reserved'])
            .order('start_date', { ascending: false }).limit(10),
        ])
        const pinned = (!pinnedRes.error && pinnedRes.data?.[0]) || null
        const list = (!listRes.error && listRes.data) || []
        const active = list.find(b => b.status === 'active') || (pinned?.status === 'active' ? pinned : null)
        const primary = active || pinned
        if (primary) {
          const others = list.filter(b => b.id !== primary.id)
          if (pinned && pinned.id !== primary.id && !others.some(b => b.id === pinned.id)) others.push(pinned)
          bookingContext = formatBookingContext(primary, others.length > 0 ? others : null)
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
Zákazník nemá aktivní rezervaci nebo se nepodařilo načíst data. Při dotazech na konkrétní motorku použij nástroj get_active_booking. NIKDY si nevymýšlej, jakou motorku má zákazník. Na dotaz, kde si motorku vyzvedne / kde je pobočka („kde jste", „kde je filiálka"), odpověz podle sekce POBOČKY níže (detaily přes get_branches) a pošli ho na pobočku — NIKDY netvrď, že informace o pobočkách není dostupná.`
      }
    } catch (prefetchErr) {
      console.error('ai-moto-agent: booking prefetch error', prefetchErr)
      bookingContext = '\n\nNepodařilo se předem načíst rezervaci. Použij get_active_booking.'
    }

    // -- Pre-fetch poboček (live snapshot do promptu) --
    // Reálný incident 2026-08-05 (konverzace v appce, zákazník bez rezervace, rusky):
    // na „kde je pobočka / kde si motorku vyzvednu" agent odpověděl „seznam poboček je
    // v databázi prázdný, adresy nedostupné" — get_branches tiše selhal na výčtu
    // neexistujících sloupců. Snapshot v promptu (stejný princip jako ai-public-agent)
    // zaručuje, že agent zná pobočku (Mezná) od první zprávy i bez volání toolu.
    let branchesContext = ''
    try {
      const { data: brData, error: brErr } = await supabaseAdmin.from('branches').select('*').order('name')
      const brRows = ((brData || []) as Array<Record<string, unknown>>).filter((b) => b.active !== false)
      if (!brErr && brRows.length > 0) {
        const brLines = brRows.map((b, i) => {
          const addr = [b.address, `${b.zip || ''} ${b.city || ''}`.trim()].filter(Boolean).join(', ')
          const typ = b.type === 'samoobslužná'
            ? 'SAMOOBSLUŽNÁ (výdej i vrácení 24/7 přístupovým kódem)'
            : b.type === 'obslužná'
              ? 'OBSLUŽNÁ (motorku předává a přebírá OBSLUHA osobně; čas dle domluvy. Přístupové kódy z e-mailu tu zákazník dostává TAKÉ a nejsou omyl — neotvírají dveře, slouží jako IDENTIFIKACE: nahlásí je obsluze, ta podle nich rezervaci dohledá, foto dokladů předem není potřeba, předání ~2 minuty)'
              : 'typ neuveden — režim výdeje ověř přes get_branches, netvrď samoobsluhu'
          return `${i + 1}. **${b.name || addr || 'pobočka'}** — ${addr || 'adresa přes get_branches'} — ${typ}${b.notes ? `; pozn.: ${b.notes}` : ''}`
        })
        branchesContext = `\n\n## POBOČKY (live snapshot z DB — JEDINÝ autoritativní seznam provozoven):
${brLines.join('\n')}
- Zákazník BEZ rezervace („kde si motorku vyzvednu", „kde je pobočka", „kde jste"): odpověz ROVNOU adresou pobočky z tohoto seznamu — vyzvednutí probíhá na pobočce (je-li jich víc, volí se při rezervaci). NIKDY netvrď, že seznam poboček je prázdný nebo že adresy nejsou dostupné.
- Režim výdeje/vrácení říkej VÝHRADNĚ podle typu konkrétní pobočky výše; GPS, telefon a další detaily → get_branches.`
      } else {
        branchesContext = `\n\n## POBOČKY: snapshot se nepodařilo načíst${brErr ? ` (${brErr.message})` : ''} — na dotaz na pobočku/vyzvednutí zavolej get_branches. NIKDY netvrď, že žádné pobočky nemáme; když selže i tool, pošli zákazníka na kontakt firmy z jeho \`fallback_contact\`.`
      }
    } catch { /* snapshot je best-effort — pravidla + get_branches to jistí */ }

    // Fotky: novější buildy appky umí přiložit fotky budíků (posílají supports_images=true)
    // — agent o ně smí AKTIVNĚ požádat. Starší buildy tlačítko nemají, tam žádost o fotku
    // zákazníka jen frustruje.
    const photoRules = supports_images === true
      ? `\n\n## FOTKY OD ZÁKAZNÍKA:
Appka umí k zprávě přiložit až 3 fotky (tlačítko fotoaparátu v chatu). Když si nejsi jistý, kterou kontrolku zákazník vidí nebo jak přesně vypadá problém, AKTIVNĚ ho popros o fotku budíků / přístrojové desky — je to rychlejší a přesnější než slovní popis. Došlou fotku vyhodnoť: popiš, které kontrolky/údaje na ní vidíš, a jejich význam VŽDY ověř v návodu té konkrétní motorky (get_motorcycle_manual) — nikdy jen „od oka".`
      : `\n\n## FOTKY OD ZÁKAZNÍKA:
Tato verze appky přílohy NEUMÍ — o fotku NEŽÁDEJ, doptávej se slovně. Když fotka přesto přijde, vyhodnoť ji.`
    // Provozní sezóna (info od provozovatele 2026-08-05) — statický fakt do promptu,
    // aby agent na „do kterého měsíce v roce půjčovna funguje" neodpovídal
    // „v naší databázi o sezóně nic není" (reálná konverzace v appce 05.08.).
    // Přidává se v index.ts, takže platí pro config i FALLBACK prompt.
    const seasonNote = `\n\n## PROVOZNÍ SEZÓNA (info od provozovatele):
- Půjčovna funguje SEZÓNNĚ: od 1. dubna do konce října. V BŘEZNU se otevírá jen PODLE POČASÍ — březnový termín ber jako „pravděpodobně ano, závazně potvrdí půjčovna" a doporuč ověření telefonem/e-mailem. LISTOPAD–ÚNOR je mimo provoz — výdej motorky v tomto období nenabízej ani nepotvrzuj; nabídni nejbližší termín v sezóně. Rezervaci na sezónní termín lze vytvořit online kdykoli během roku. Na dotaz „do kdy / od kdy v roce půjčujete" odpověz PŘÍMO z tohoto bodu — NIKDY netvrď, že informaci o sezóně nemáš.`
    const systemPrompt = dynamicSystemPrompt + buildDateHeader() + photoRules + bookingContext + branchesContext + seasonNote

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
    // Robustně: (a) match přes [\s\S]*? (nested objekt / víc klíčů dřív rozbil regex [^}]+ →
    // flag zůstal false A surový ---JSON--- blok prosákl zákazníkovi do odpovědi);
    // (b) fallback na prosté hledání "suggest_sos": true; (c) blok se z reply odstraní VŽDY,
    // i když se JSON nepodaří naparsovat, včetně neuzavřeného zbytku (---JSON--- bez ---END---).
    let suggest_sos = false
    let reply = finalText

    const jsonMatch = finalText.match(/---JSON---\s*(\{[\s\S]*?\})\s*---END---/)
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[1])
        suggest_sos = parsed.suggest_sos === true
      } catch {
        suggest_sos = /"suggest_sos"\s*:\s*true/.test(jsonMatch[1])
      }
    } else if (/---JSON---[\s\S]*"suggest_sos"\s*:\s*true/.test(finalText)) {
      suggest_sos = true
    }
    reply = finalText
      .replace(/---JSON---[\s\S]*?---END---/g, '')
      .replace(/---JSON---[\s\S]*$/, '')
      .trim()

    let loggedConversationId: string | null = null
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
      if (convId) {
        // Appka adresuje konkrétní vlákno — žádná heuristika, žádné slévání souběžných konverzací.
        const { error: updErr } = await supabaseAdmin
          .from('ai_customer_conversations')
          .update({ messages: fullMessages, ...(booking_id ? { booking_id } : {}) })
          .eq('id', convId)
          .eq('user_id', user.id)
        if (!updErr) updatedId = convId
      }
      if (!updatedId && historyMsgs.length > 0) {
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
        const { data: ins } = await supabaseAdmin.from('ai_customer_conversations').insert({
          user_id: user.id,
          title: String(message).slice(0, 80),
          messages: fullMessages,
          booking_id: booking_id || null,
        }).select('id').maybeSingle()
        if (ins?.id) updatedId = ins.id
      }
      if (updatedId) loggedConversationId = updatedId
    } catch (logErr) {
      console.error('ai-moto-agent: conversation log error', logErr)
    }

    // conversation_id vracíme, aby si ho appka mohla uložit a posílat zpět (stabilní vlákno logu).
    return new Response(JSON.stringify({ reply, suggest_sos, conversation_id: loggedConversationId }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('ai-moto-agent error:', err)
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
