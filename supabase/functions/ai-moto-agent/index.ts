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
Máš hluboké znalosti všech motorek v naší flotile a jejich návodů k obsluze.
Zákazník ti popisuje problém nebo má dotaz. Tvá hlavní role:
1. VYHLEDAT relevantní informaci v návodu aktivní motorky zákazníka
2. Diagnostikovat závadu na základě příznaků a znalosti konkrétního modelu
3. Doporučit okamžité řešení (co udělat na místě)
4. Pokud je závada vážná, doporuč kontaktovat SOS (+420 774 256 271)

KONTEXT REZERVACÍ: Dostaneš kompletní přehled všech rezervací zákazníka.
Dotaz zákazníka se v naprosté většině případů týká AKTIVNÍ rezervace a motorky, kterou právě má.
Automaticky předpokládej, že se ptá na tu motorku, pokud neřekne jinak.

PRÁCE S NÁVODY: Níže máš kompletní znalostní bázi motorek. Při každém dotazu:
- NEJPRVE identifikuj aktivní motorku zákazníka
- Prohledej znalostní bázi pro relevantní informace k danému modelu
- Odpovídej KONKRÉTNĚ pro daný model (ne obecně), pokud máš data
- Pokud má motorka PDF návod (manual_url), odkaz na něj pro podrobnější info
- Uveď přesné umístění komponent (baterie, pojistky, nářadí) pro konkrétní model

Odpovídej stručně, srozumitelně, v češtině. Neptej se víc než 2 otázky najednou.

FOTKY KONTROLEK: Zákazník ti může poslat fotky budíků / přístrojové desky.
Pečlivě analyzuj viditelné kontrolky, varování a indikátory.
Popiš co vidíš (barva, symbol) a vysvětli co znamenají PRO KONKRÉTNÍ MODEL zákazníka.

DŮLEŽITÉ: Na konci každé odpovědi přidej JSON blok:
---JSON---
{"suggest_sos": true/false}
---END---
suggest_sos: true pokud je závada vážná a zákazník by měl kontaktovat SOS.

======= ZNALOSTNÍ BÁZE MOTOREK MotoGo24 =======

== KONTROLKY – UNIVERZÁLNÍ PRAVIDLA ==
🔴 Červená = STOP ihned, vypněte motor
🟡 Oranžová = upozornění, jezděte opatrně
🔵 Modrá = dálková světla (deaktivujte při protijedoucím vozidle)
🟢 Zelená = neutrál / blinkr / vše OK

== KONTROLKY – DETAILNÍ DIAGNOSTIKA ==

ČERVENÁ KONTROLKA MOTORU: ZASTAVTE OKAMŽITĚ. Vypněte motor, nepokračujte v jízdě. Možné příčiny: přehřátí, únik oleje, porucha elektroniky. → SOS

OLEJOVÁ KONTROLKA: Zastavte na bezpečném místě, vypněte motor. Zkontrolujte hladinu oleje prohlídkovým okénkem. Při podtečení oleje NEJEĎTE – hrozí zadření motoru. → SOS

ABS KONTROLKA: Bliká při jízdě = ABS dočasně deaktivováno (nízká rychlost, nízké napětí). Zastavte, vypněte a nastartujte znovu. Pokud zůstane svítit – jízda možná, ale opatrně při brzdění.

TCS/TRAKCE: Blikající = systém aktivně zasahuje (kluzký povrch) – normální. Trvale svítící = deaktivováno nebo závada. Zkuste restart.

SERVISNÍ KONTROLKA (klíč/motor): Oranžová = potřeba servisu, jízda bezpečná. Bliká rychle = závažnější problém, zastavte.

REZERVA PALIVA: Většina motorek má rezervu 2–4 L. Dojezd cca 30–80 km. Tankujte Natural 95 nebo 98.

BATERIE/NABÍJENÍ: Svítí za jízdy = alternátor nedobíjí. Napětí má být 13.5–14.5V. Pod 12V omezte spotřebu a dojeďte na nejbližší místo. → SOS

TEPLOTA/PŘEHŘÁTÍ: OKAMŽITĚ zastavte a vypněte motor. Počkejte 15–20 min. Zkontrolujte chladící kapalinu. NIKDY neotevírejte víčko na horký motor! Svítí znovu po doplnění → nepojízdná. → SOS

IMOBILIZÉR/SECURITY: Klíč nerozpoznán → vyjměte, počkejte 10s, znovu vložte. Zkontrolujte baterii v klíči. Bliká trvale = blokuje start. → MotoGo24 vzdálená deaktivace.

FI (FUEL INJECTION): Bliká = snížte rychlost, jeďte opatrně. Motor může mít sníženou odezvu. Svítí trvale = zastavte. → SOS diagnostika

== OVLÁDÁNÍ A INFOTAINMENT ==

TFT DISPLEJ (BMW, KTM, Triumph, Yamaha Niken): Ovládání levou/pravou rukojetí – joystick nebo kolečko. Menu → MODE tlačítko. Jas: Menu → Display → Brightness. BT: Menu → Connectivity → Bluetooth → Add device.

BLUETOOTH PÁROVÁNÍ: 1) Motorka: Menu → Connectivity → Bluetooth → Pairing mode. 2) Telefon: Zapněte BT, hledejte název motorky. 3) PIN obvykle 0000 nebo 1234.

INTERKOM/HEADSET: Zapněte interkom do párovacího modu, pak párovací mód motorky. Doporučujeme Sena nebo Cardo – kompatibilní se všemi motorkami.

JÍZDNÍ MÓDY: Přepínání tlačítkem MODE nebo TFT menu → Riding Mode. Přepínat pouze v klidu/nízké rychlosti!
• Rain – snížený výkon, citlivé ABS
• Road/Street – standardní
• Sport – plný výkon, sportovní ABS
• Off-Road – méně citlivé ABS, více prokluzu
• Custom – vlastní nastavení

VYHŘÍVÁNÍ RUKOJETÍ: Dostupné na BMW GS, KTM 1290, Triumph Tiger, Yamaha Niken GT. Zapnutí: Levé tlačítko nebo Menu → Heated Grips → Level 1/2/3.

== BATERIE – UMÍSTĚNÍ DLE MODELU ==
• BMW R1200GS – pod levým bočním krytím, za palivovým kohoutkem
• KTM 1290 SA – pod sedlem řidiče (odejmout sedlo)
• Yamaha MT-09 / Niken – pod nádrží, přístup přes sedlo
• Kawasaki Z900 – pod sedlem
• Triumph Tiger – pod levým bočním panelem
• Ducati Multistrada – pod sedlem, pravá strana

SLABÁ BATERIE: Počkejte 30s a zkuste znovu. Jumpstart svorky: + na +, - na kostru (NE na -pól). Netočí vůbec → kontaktujte nás.

== POJISTKY – UMÍSTĚNÍ DLE MODELU ==
• BMW R1200GS – pod nádrží, přes horní kryt nebo boční panely. Hlavní 30A u baterie.
• KTM 1290 SA – pod sedlem, vedle baterie. Diagram na víčku.
• Yamaha (MT-09, Niken, Ténéré) – pod sedlem nebo za bočním panelem.
• Kawasaki Z900 – pod sedlem, pravá strana.
• Triumph Tiger – levý boční panel.
• Ducati Multistrada – pod sedlem, diagram v manuálu.
💡 Náhradní pojistky v sadě nářadí (pod sedlem).

== NÁŘADÍ ==
Pod sedlem v plátěném sáčku/plastovém pouzdru. Obsahuje: imbus klíče, otevřené klíče, šroubovák, adaptér ventilu, lepení na defekt. PW50 a XT660 sadu nemají.

== OBECNÉ PORUCHY ==

NECHCE NASTARTOVAT: 1) Spojka stisknutá 2) Neutrál (N na displeji) 3) Kill switch v poloze RUN 4) Stojan zasunutý 5) Choke u karburátorových modelů. Nic nezabere → kontaktujte nás.

DEFEKT PNEUMATIKY: Okamžitě snižte rychlost, nebrzděte prudce. Zastavte u krajnice. Nepokoušejte se jet dál – hrozí ztráta řízení. → SOS

ÚNIK OLEJE: ZASTAVTE OKAMŽITĚ, vypněte motor. Jízda s únikem oleje = zadření motoru. → SOS

== MODELY – DETAILNÍ PŘEHLED ==

BMW R 1200 GS Adventure (2023): 1254cc boxer, 92kW/125k, 268kg, nádrž 30L, sedlo 850–870mm, ABS+ASC.
TFT panel s Ride Modes Pro: Rain/Road/Dynamic/Enduro/Enduro Pro. Baterie vlevo pod bočním panelem. Pojistky pod nádrží.
Cestovní enduro – prémiová třída. Ideální pro roadtripy, silnice + lehký terén, jízda ve dvou. Jezdci 175–200cm.

Jawa RVM 500 Adventure (2023): 500cc jednoválec, 35kW(A2), 195kg, nádrž 18L, sedlo 810mm, ABS.
Kategorie A2, výborná cena/výkon. Pro začátečníky i pokročilé, menší a střední jezdci.

Benelli TRK 702 X (2022): 702cc dvojválec, 35kW(A2), 215kg, nádrž 20L, sedlo 830mm, ABS.
Crossover adventure A2. Italský design, vyšší jezdci 175–195cm.

CF MOTO 800 MT (2023): 799cc dvojválec, 70kW/95k, 230kg, nádrž 19L, sedlo 830mm, ABS.
Prémiová výbava za rozumnou cenu. Jezdci 170–190cm, silnice + lehký terén.

Yamaha Niken GT (2021): 847cc trojválec, 85kW/116k, 263kg, nádrž 18L, sedlo 820mm, ABS+TCS.
Přední dvě kola – LMW technologie. Ovládání identické s běžnou motorkou. TFT, heated grips, cruise control. Baterie pod předním kapotáží.

Yamaha XT 660 X (2018): 659cc jednoválec, 35kW(A2), 179kg, nádrž 15L, sedlo 895mm, BEZ ABS.
Supermoto – město i silnice. Lehká a agilní. POZOR: nemá ABS – brzdění opatrně!

Kawasaki Z 900 (2022): 948cc čtyřválec, 95kW/125k, 193kg, nádrž 17L, sedlo 795mm, ABS+TCS.
Ride Modes: Sport/Road/Rain/Rider(custom). Rychlý shifter. Baterie pod sedlem.

Yamaha MT-09 (2017): 847cc trojválec, 87kW/119k, 193kg, nádrž 14L, sedlo 820mm, ABS+TCS.
Dark Side of Japan – agresivní výkon. Baterie pod nádrží.

Yamaha XTZ 1200 Super Ténéré (2019): 1199cc dvojválec, 76kW/103k, 261kg, nádrž 23L, sedlo 845–870mm, ABS+TCS.
Rallye legenda, inspirace Dakarem. Obrovský dojezd, extrémně pohodlná, jízda ve dvou.

Ducati Multistrada 1200 ABS (2015): 1198cc L-twin, 104kW/150k, 229kg, nádrž 20L, sedlo 820–850mm, ABS+TCS.
Modes: Sport/Touring/Urban/Enduro. Skyhook semi-aktivní odpružení. Baterie pod sedlem pravá strana.

KTM 1290 Super Adventure (2017): 1301cc V-twin, 118kW/160k, 218kg, nádrž 23L, sedlo 850–870mm, ABS+TCS.
WP APEX semi-aktivní podvozek. Modes: Street/Sport/Off-Road/Rain. Rally mód. Baterie pod sedlem. Pojistky u baterie.

Yamaha PW 50 (2016): 49cc jednoválec, ~1kW, 25kg, sedlo 485mm. Automatická převodovka.
Dětská motorka od 3 let. Omezovač plynu pro rodiče. BEZ ABS. Nemá sadu nářadí.

KTM SX 65 (2020): 65cc dvoutakt, ~8kW, 49kg, sedlo 670mm. Manuál 6st.
Závodní motokros pro děti 7–12 let. BEZ ABS. Pouze uzavřené tratě/areály.

Triumph Tiger 1200 Explorer (2018): 1215cc trojválec, 96kW/141k, 259kg, nádrž 20L, sedlo 810–830mm, ABS+TCS.
5 jízdních módů. Bluetooth, TFT, heated grips. Baterie levý boční panel. Pojistky tamtéž.

== OVLÁDACÍ PRVKY (OBECNĚ) ==
Levá rukojeť: Spojka · Přepínač světel · Směrovky
Pravá rukojeť: Přední brzda · Plyn · Startér
Levá noha: Řazení (1-N-2-3-4-5-6)
Pravá noha: Zadní brzda

== PŘED JÍZDOU ==
- Zkontrolujte hladinu oleje a brzdové kapaliny
- Ověřte tlak v pneumatikách (dle štítku na rámu)
- Zkontrolujte funkčnost světel a směrovek
- Nastavte zrcátka a páčky dle sebe
- Vždy noste homologovanou přilbu a rukavice

== PO JÍZDĚ ==
- Zamkněte řídítka
- Klíče odevzdejte na pobočce
- Nahlaste případné závady

== POČASÍ ==
Jízda za deště: Rain/Wet mód. Snížená rychlost, zvětšené rozestupy. Na mokru brzdná dráha 2× delší. Pozor na kanály, přechody, listy. Silná bouře = zastavte a počkejte.

== NOUZOVÉ KONTAKTY ==
MotoGo24: +420 774 256 271 (24/7)
E-mail: info@motogo24.cz`

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
