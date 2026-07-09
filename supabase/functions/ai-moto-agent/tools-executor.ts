// ===== ai-moto-agent/tools-executor.ts =====
// Tool execution logic — database queries for each tool

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { execPublicReadTool, PUBLIC_READ_TOOL_NAMES } from './public-tools.ts'

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
const MANUAL_INSTRUCTION =
  'Toto je text návodu k TÉTO konkrétní motorce — přečti si ho CELÝ a pozorně. ' +
  'Odpověď hledej v celém návodu, ne jen podle přesných slov dotazu: kontrolky, ' +
  'symboly a funkce bývají popsané i jinými výrazy (např. „červený klíč" = ' +
  'imobilizér / bezpečnostní systém; „vykřičník v trojúhelníku" = obecná porucha). ' +
  'Když přesný pojem v návodu doslova není, odvoď odpověď z odpovídající části ' +
  '(kontrolky na palubní desce, symboly, startování, imobilizér). Pokud si ani po ' +
  'přečtení celého návodu nejsi jistý, CO PŘESNĚ zákazník vidí, NEODbývej to ' +
  'vyhýbavou odpovědí typu „návod to přímo nepopisuje" — polož mu 1–2 konkrétní ' +
  'upřesňující otázky a požádej o fotku palubní desky / kontrolky, a teprve pak ' +
  'odpověz. Vymyšlené technické údaje jsou zakázané; pokud informace v návodu ' +
  'opravdu není, řekni to jasně až PO doptání a nabídni kontakt na MotoGo24.'

function stripHtml(html: string): string {
  return String(html || '')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#3[49];/g, "'")
    .replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()
}

/**
 * Přečte návod konkrétní motorky — stejná logika jako `get_motorcycle_manual`
 * v ai-public-agent. PDF (`manual_url`, public bucket `media`) má přednost před
 * externím odkazem (`manual_external_url`). Z PDF vytáhne text přes `unpdf`
 * (serverless pdf.js), z webové stránky stripne HTML. Při `query` vrátí jen
 * relevantní pasáže (návody bývají dlouhé a celý text zbytečně žere tokeny).
 */
async function readMotorcycleManual(
  moto: Record<string, unknown>,
  query: string,
): Promise<Record<string, unknown>> {
  const mName = motoDisplayName(moto.brand as string, moto.model as string)
  const pdfUrl = String(moto.manual_url || '').trim()
  const extUrl = String(moto.manual_external_url || '').trim()
  const sourceUrl = pdfUrl || extUrl

  if (!sourceUrl) {
    return {
      found: false, model: mName,
      notice: `K motorce ${mName} není v systému nahraný návod ani externí odkaz. NEVYMÝŠLEJ si technické údaje (tlak v pneu, druh oleje, kontrolky, postup startování apod.) — řekni, že návod k téhle motorce nemáš k dispozici, a doporuč kontakt na MotoGo24 (+420 774 256 271).`,
    }
  }

  // Vysoký strop — návod posíláme modelu CELÝ (běžný manuál se do kontextu
  // Sonnetu pohodlně vejde). Windowing zapneme jen u opravdu dlouhých návodů.
  const MAX = 60000
  let text = ''
  let sourceType = pdfUrl ? 'pdf' : 'web'
  try {
    const resp = await fetch(sourceUrl, { headers: { 'User-Agent': 'MotoGo24-AI/1.0 (+https://www.motogo24.cz)' } })
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    const ctype = (resp.headers.get('content-type') || '').toLowerCase()
    const looksPdf = !!pdfUrl || ctype.includes('pdf') || /\.pdf(\?|#|$)/i.test(sourceUrl)
    if (looksPdf) {
      sourceType = 'pdf'
      const buf = new Uint8Array(await resp.arrayBuffer())
      // Dynamický import — unpdf načteme jen když opravdu parsujeme PDF (šetří cold-start).
      const { extractText, getDocumentProxy } = await import('https://esm.sh/unpdf@0.12.1')
      const pdf = await getDocumentProxy(buf)
      const res = await extractText(pdf, { mergePages: true }) as { text?: string }
      text = String(res.text || '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()
    } else {
      sourceType = 'web'
      text = stripHtml(await resp.text())
    }
  } catch (e) {
    return {
      found: true, model: mName, source_type: sourceType, url: sourceUrl, fetch_failed: true,
      notice: `Návod k ${mName} se nepodařilo strojově otevřít (${(e as Error).message}). Pošli zákazníkovi přímý odkaz na návod (${sourceUrl}), ať si detail najde sám. NEVYMÝŠLEJ si obsah návodu.`,
    }
  }

  if (!text || text.length < 30) {
    return {
      found: true, model: mName, source_type: sourceType, url: sourceUrl,
      notice: `Z návodu k ${mName} se nepodařilo vytáhnout čitelný text (nejspíš skenované PDF bez textové vrstvy). Pošli zákazníkovi přímý odkaz na návod (${sourceUrl}) a ať si detail najde sám. NEVYMÝŠLEJ obsah.`,
    }
  }

  // Delší návod, než se vejde do stropu → zúžíme na širší relevantní pasáže
  // kolem klíčových slov (ať model neztratí kontext), jinak posíláme CELÝ text.
  if (query && text.length > MAX) {
    const lc = text.toLowerCase()
    const terms = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 3)
    const hits: number[] = []
    for (const term of terms) {
      let from = 0
      for (;;) {
        const i = lc.indexOf(term, from)
        if (i < 0 || hits.length > 60) break
        hits.push(i); from = i + term.length
      }
    }
    if (hits.length > 0) {
      hits.sort((a, b) => a - b)
      const win: Array<[number, number]> = []
      for (const i of hits) {
        const s = Math.max(0, i - 1500), e = Math.min(text.length, i + 1500)
        const last = win[win.length - 1]
        if (last && s <= last[1]) last[1] = Math.max(last[1], e)
        else win.push([s, e])
      }
      let excerpt = win.map(([s, e]) => (s > 0 ? '…' : '') + text.slice(s, e).trim() + (e < text.length ? '…' : '')).join('\n\n———\n\n')
      if (excerpt.length > MAX) excerpt = excerpt.slice(0, MAX) + '…'
      return {
        found: true, model: mName, source_type: sourceType, url: sourceUrl, mode: 'excerpts', query,
        total_chars: text.length, text: excerpt,
        instruction: MANUAL_INSTRUCTION,
      }
    }
  }
  const full = text.length > MAX ? text.slice(0, MAX) + `\n…[zkráceno kvůli délce — celý návod: ${sourceUrl}]` : text
  return {
    found: true, model: mName, source_type: sourceType, url: sourceUrl, mode: 'full',
    query: query || undefined, total_chars: text.length, text: full,
    instruction: MANUAL_INSTRUCTION,
  }
}

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
      let q = supabaseAdmin.from('motorcycles')
        .select('id, brand, model, year, category, engine_type, engine_cc, power_kw, power_hp, has_abs, has_asc, fuel_tank_l, seat_height_mm, weight_kg, features, manual_url, manual_external_url')

      if (input.motorcycle_id) {
        q = q.eq('id', input.motorcycle_id)
      } else if (input.brand || input.model) {
        if (input.brand) q = q.ilike('brand', `%${input.brand}%`)
        if (input.model) q = q.ilike('model', `%${input.model}%`)
      } else {
        return { error: 'Musíš zadat motorcycle_id nebo brand+model.' }
      }

      const { data, error } = await q.limit(1)
      if (error) return { error: error.message }
      if (!data || data.length === 0) return { message: 'Motorka nenalezena.' }

      const moto = data[0] as Record<string, unknown>
      const query = typeof input.query === 'string' ? input.query.trim() : ''
      const manual = await readMotorcycleManual(moto, query)

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
      const searchQuery = (input.query as string) || ''

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
