// ===== ai-moto-agent/tools-executor.ts =====
// Tool execution logic — database queries for each tool

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { execPublicReadTool, PUBLIC_READ_TOOL_NAMES } from './public-tools.ts'
import { readManual } from '../_shared/manual-reader.ts'
import { getBundledManualText } from '../_shared/manual-texts/index.ts'

// Normalizace pro fuzzy hledání stroje: bez diakritiky, jen [a-z0-9] tokeny.
function normName(s: unknown): string {
  return String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ').trim()
}

// Kolik tokenů dotazu sedí na název stroje. „v strom" musí najít „V-strom",
// „vstrom 650" taky (squash bez mezer); krátké tokeny (v, gs, x) jen jako celá slova.
function matchScore(qTokens: string[], name: string): number {
  const padded = ` ${name} `
  const squashed = name.replace(/ /g, '')
  let sc = 0
  for (const t of qTokens) {
    if (t.length <= 2 ? padded.includes(` ${t} `) : (name.includes(t) || squashed.includes(t.replace(/ /g, '')))) sc++
  }
  return sc
}

// Sjednoceno s ai-public-agent: skládá zobrazovaný název motorky a dedupuje
// značku, pokud ji `model` v DB už obsahuje (jinak „Benelli Benelli TRK 502 X").
function motoDisplayName(brand: string | null | undefined, model: string | null | undefined): string {
  const b = (brand || '').trim()
  const m = (model || '').trim()
  if (!b) return m
  if (!m) return b
  if (m.toLowerCase().startsWith(b.toLowerCase())) return m
  return `${b} ${m}`
}

// Pokyn k práci s návodem — model má návod přečíst KOMPLETNĚ a odpovědět z něj.
// Když přesnou odpověď nenajde, NEODbývá to vyhýbavou „návod to nepopisuje", ale
// odvodí ji z příbuzné části a/nebo se zákazníka doptá a potvrdí (viz zadání).
// Samotné stažení a parsování návodu dělá sdílený ../_shared/manual-reader.ts.
const MANUAL_INSTRUCTION =
  'Toto je text návodu k TÉTO konkrétní motorce — přečti si ho CELÝ a pozorně. ' +
  'Odpověď hledej v celém návodu, ne jen podle přesných slov dotazu: kontrolky, ' +
  'symboly a funkce bývají popsané i jinými výrazy (např. „červený klíč" = ' +
  'imobilizér / bezpečnostní systém; „vykřičník v trojúhelníku" = obecná porucha). ' +
  'Když přesný pojem v návodu doslova není, odvoď odpověď z odpovídající části ' +
  '(kontrolky na palubní desce, symboly, startování, imobilizér). Pokud si ani po ' +
  'přečtení celého návodu nejsi jistý, CO PŘESNĚ zákazník vidí, NEODbývej to ' +
  'vyhýbavou odpovědí typu „návod to přímo nepopisuje" — polož mu 1–2 konkrétní ' +
  'upřesňující otázky (kterou kontrolku přesně vidí, jakou má barvu a symbol, kdy ' +
  'svítí); zda smíš požádat o fotku budíků, určuje sekce FOTKY OD ZÁKAZNÍKA. ' +
  'Když návod velí „okamžitě zastavte / vyhledejte servis", NEpřenášej to na ' +
  'zákazníka doslova — přelož to podle sekce KALIBRACE ZÁVAŽNOSTI (uklidnit, ' +
  'jednoduché řešení, nahlásit technikům; zastavení jen u skutečně kritických ' +
  'příznaků). Vymyšlené technické údaje jsou zakázané; pokud informace v návodu ' +
  'opravdu není, řekni to jasně až PO doptání a nabídni kontakt na MotoGo24.'

export async function executeTool(
  toolName: string,
  input: Record<string, unknown>,
  supabaseAdmin: SupabaseClient,
  userId: string,
  lang = 'cs',
): Promise<unknown> {
  // Informační tooly převzaté z veřejného agenta (search/cena/FAQ/policies/…)
  if (PUBLIC_READ_TOOL_NAMES.has(toolName)) {
    const res = await execPublicReadTool(toolName, input, supabaseAdmin, lang)
    if (res !== undefined) return res
  }

  switch (toolName) {
    case 'get_active_booking': {
      const { data, error } = await supabaseAdmin
        .from('bookings')
        .select(`
          id, status, payment_status, start_date, end_date, pickup_time,
          total_price, extras_price, pickup_method, return_method,
          mileage_start, mileage_end, notes, booking_source,
          motorcycles!moto_id(
            id, model, brand, spz, engine_type, engine_cc, power_kw, power_hp,
            weight_kg, has_abs, has_asc, features, manual_url, manual_external_url, description,
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
      const active = data.find(b => b.status === 'active')
      if (active) return active
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
          motorcycles!moto_id(id, model, brand, category, engine_cc)
        `)
        .eq('user_id', userId)
        .order('start_date', { ascending: false })
        .limit(limit)

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Zákazník nemá žádné rezervace.' }
      return data
    }

    case 'get_motorcycle_manual': {
      // Nejdřív najdi motorku, pak PŘEČTI její návod (PDF/web) — stejně jako
      // veřejný agent. `query` = co v návodu hledáš (tlak v pneu, druh oleje,
      // kontrolky, startování, režim jízdy, pojistky…); bez query vrátí (zkrácený)
      // celý text. Když návod chybí, vrátí specifikace motorky + upozornění.
      const MOTO_COLS = 'id, brand, model, year, category, engine_type, engine_cc, power_kw, power_hp, has_abs, has_asc, fuel_tank_l, seat_height_mm, weight_kg, features, manual_url, manual_external_url'
      const motoIdArg = input.motorcycle_id || input.moto_id // alias: public agent/page_context používají moto_id
      let moto: Record<string, unknown> | null = null

      if (motoIdArg) {
        const { data, error } = await supabaseAdmin.from('motorcycles').select(MOTO_COLS).eq('id', motoIdArg).limit(1)
        if (error) return { error: error.message }
        moto = (data?.[0] as Record<string, unknown>) || null
      } else if (input.brand || input.model) {
        // FUZZY hledání přes celou flotilu. Dřívější `ilike '%model%'` selhal na
        // interpunkci: zákazník napsal „v strom", DB má „Suzuki DL 650 V-strom"
        // → „Motorka nenalezena" → agent návod vůbec nečetl (reálný případ 26. 7.).
        const { data: all, error } = await supabaseAdmin.from('motorcycles').select(MOTO_COLS).limit(200)
        if (error) return { error: error.message }
        const qTokens = normName(`${input.brand || ''} ${input.model || ''}`).split(' ').filter(Boolean)
        const scored = ((all || []) as Array<Record<string, unknown>>)
          .map((m) => ({ m, sc: matchScore(qTokens, normName(`${m.brand} ${m.model} ${m.year || ''}`)) }))
          .filter((x) => x.sc > 0)
          .sort((a, b) => b.sc - a.sc)
        if (scored.length === 0) {
          return {
            message: 'Motorka nenalezena ve flotile MotoGo24.',
            fleet: ((all || []) as Array<Record<string, unknown>>).map((m) => motoDisplayName(m.brand as string, m.model as string)),
            instruction: 'Tohle je KOMPLETNÍ flotila. Zeptej se zákazníka, který z těchto strojů má — nenabízej varianty, které v seznamu nejsou.',
          }
        }
        // Víc strojů se stejným nejlepším skóre → nech agenta doptat se.
        const top = scored.filter((x) => x.sc === scored[0].sc)
        if (top.length > 1) {
          return {
            multiple_matches: top.map((x) => ({ id: x.m.id, name: motoDisplayName(x.m.brand as string, x.m.model as string) })),
            message: 'Popisu odpovídá víc strojů z flotily. Zeptej se zákazníka, který z nich má, a zavolej tool znovu s motorcycle_id.',
          }
        }
        moto = scored[0].m
      } else {
        return { error: 'Musíš zadat motorcycle_id nebo brand+model.' }
      }

      if (!moto) return { message: 'Motorka nenalezena.' }
      const query = typeof input.query === 'string' ? input.query.trim() : ''
      const manual = await readManual({
        modelName: motoDisplayName(moto.brand as string, moto.model as string),
        pdfUrl: moto.manual_url as string, extUrl: moto.manual_external_url as string,
        query, instruction: MANUAL_INSTRUCTION,
        cachedText: await getBundledManualText(moto.id as string) || undefined,
      })

      // Specs jsou NADŘAZENÉ (kW, ccm, ABS, hmotnost, výška sedla) — vracíme je
      // vždy spolu s návodem, aby agent mohl odpovědět i bez parsování PDF.
      return {
        specs: {
          model: motoDisplayName(moto.brand as string, moto.model as string),
          year: moto.year, category: moto.category,
          engine: `${moto.engine_type || '?'} ${moto.engine_cc || '?'}cc`,
          power: `${moto.power_kw || '?'}kW / ${moto.power_hp || '?'}hp`,
          has_abs: moto.has_abs, has_asc: moto.has_asc,
          fuel_tank_l: moto.fuel_tank_l, seat_height_mm: moto.seat_height_mm,
          weight_kg: moto.weight_kg, features: moto.features,
        },
        manual,
      }
    }

    case 'search_troubleshooting': {
      // Sanitizace: čárka/závorky/hvězdička v dotazu rozbíjejí syntaxi PostgREST .or()
      // filtru („brzda, kontrolka (žlutá)" → chyba → falešné prázdno). Nahradíme mezerou.
      const searchQuery = String(input.query || '').replace(/[,()*%]/g, ' ').replace(/\s+/g, ' ').trim()

      const { data: kbData, error: kbError } = await supabaseAdmin
        .from('motorcycle_knowledge_base')
        .select('*')
        .or(`title.ilike.%${searchQuery}%,content.ilike.%${searchQuery}%`)
        .limit(5)

      if (!kbError && kbData && kbData.length > 0) {
        return kbData
      }

      return {
        message: 'Tabulka motorcycle_knowledge_base neexistuje nebo neobsahuje relevantní data. Použij obecné diagnostické znalosti.',
        general_tips: {
          red_light: 'Červená kontrolka = STOP, vypněte motor. Možné příčiny: přehřátí, únik oleje, porucha elektroniky. -> SOS',
          oil_light: 'Zastavte, vypněte motor. Zkontrolujte hladinu oleje. Při podtečení NEJEĎTE. -> SOS',
          abs_light: 'Bliká = ABS dočasně deaktivováno. Zkuste restart. Trvale svítí = opatrně brzdění.',
          temperature: 'OKAMŽITĚ zastavte. Počkejte 15-20 min. NIKDY neotevírejte víčko na horký motor. -> SOS',
          wont_start: '1) Spojka stisknutá, 2) Neutrál, 3) Kill switch=RUN, 4) Stojan zasunutý, 5) Choke u karburátorů.',
          flat_tire: 'Snižte rychlost, nebrzděte prudce, zastavte u krajnice. NEJEĎTE dál. -> SOS',
          oil_leak: 'ZASTAVTE OKAMŽITĚ, vypněte motor. -> SOS',
          battery_low: 'Pod 12V omezte spotřebu. Jumpstart: + na +, - na kostru. -> SOS',
          fuel_reserve: 'Rezerva 2-4 L, dojezd cca 30-80 km. Tankujte Natural 95/98.',
          rain_riding: 'Rain mód, snížená rychlost, zvětšené rozestupy, pozor na kanály a listy.',
          emergency_contact: 'MotoGo24: +420 774 256 271 (24/7), info@motogo24.cz',
        },
      }
    }

    case 'get_fleet_overview': {
      // Ceny: reálný ceník je per den v týdnu (price_mon..sun) — dřívější price_weekday/
      // price_weekend jsou zastaralé sloupce a neodpovídaly skutečné ceně. Vracíme jen
      // orientační min_price_kc + pokyn použít calculate_price pro přesnou cenu termínu.
      const { data, error } = await supabaseAdmin
        .from('motorcycles')
        .select('id, brand, model, category, engine_cc, engine_type, power_kw, power_hp, has_abs, has_asc, license_required, seat_height_mm, weight_kg, fuel_tank_l, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, image_url')
        .eq('status', 'active')
        .order('brand')

      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Žádné aktivní motorky ve flotile.' }
      const DAY_KEYS = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
      return {
        notice: 'Ceník je dle dne v týdnu — min_price_kc je jen NEJLEVNĚJŠÍ den pro orientaci. Přesnou cenu pro konkrétní termín VŽDY spočítej přes calculate_price, nikdy ji neodvozuj z min_price_kc.',
        motorcycles: (data as Array<Record<string, unknown>>).map((m) => {
          const ps = DAY_KEYS.map((k) => Number(m[k] || 0)).filter((v) => v > 0)
          return {
            id: m.id, name: motoDisplayName(m.brand as string, m.model as string),
            brand: m.brand, model: m.model, category: m.category,
            engine_cc: m.engine_cc, engine_type: m.engine_type,
            power_kw: m.power_kw, power_hp: m.power_hp,
            has_abs: m.has_abs, has_asc: m.has_asc,
            license: m.license_required, seat_height_mm: m.seat_height_mm,
            weight_kg: m.weight_kg, fuel_tank_l: m.fuel_tank_l,
            min_price_kc: ps.length ? Math.min(...ps) : null,
            image_url: m.image_url,
          }
        }),
      }
    }

    default:
      return { error: `Neznámý nástroj: ${toolName}` }
  }
}
