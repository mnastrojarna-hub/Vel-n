/**
 * MotoGo24 — Edge Function: Public AI Agent (booking widget backend)
 *
 * Anonymní AI asistent pro zákazníky na motogo24.cz. Volá Anthropic Claude
 * a má read-only přístup k motorkám/pobočkám/FAQ + akce (kalkulace ceny,
 * vytvoření rezervace přes RPC create_web_booking).
 *
 * Bez JWT (anonymní). Rate-limit per IP.
 *
 * Konfigurovatelný z Velínu přes app_settings.ai_public_agent_config:
 *   { persona_name, system_prompt, situations, mustDo, forbidden, tone, max_tokens, enabled,
 *     welcome_cs, welcome_en, welcome_de }
 *
 * POST body:
 *   { messages: [{role, content}], lang?: 'cs'|'en'|'de'|... }
 *
 * Response:
 *   { reply, tool_uses?: [...], booking_url?: string }
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const ANTHROPIC_MODEL = 'claude-haiku-4-5-20251001'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

// ============================================================================
// Rate limit
// ============================================================================
const rateBuckets = new Map<string, { count: number; resetAt: number }>()
function rateLimit(key: string, limit = 20, windowMs = 60_000): boolean {
  const now = Date.now()
  const b = rateBuckets.get(key)
  if (!b || b.resetAt < now) { rateBuckets.set(key, { count: 1, resetAt: now + windowMs }); return true }
  if (b.count >= limit) return false
  b.count++; return true
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function logTraffic(toolName: string | null, statusCode: number, latencyMs: number, outcome: string, ip: string, ua: string, bookingId?: string) {
  try {
    const ipHash = await sha256Hex(ip + '|motogo24')
    await sb.from('ai_traffic_log').insert({
      source: 'widget',
      bot_name: 'motogo24-widget',
      user_agent: ua.slice(0, 500),
      path: toolName ? `widget://${toolName}` : 'widget://chat',
      endpoint: toolName,
      method: 'POST',
      ip_hash: ipHash,
      status_code: statusCode,
      latency_ms: latencyMs,
      outcome,
      booking_id: bookingId || null,
    })
  } catch { /* silent */ }
}

// ============================================================================
// Velín config loader
// ============================================================================
type WebAgentConfig = {
  persona_name?: string
  system_prompt?: string
  situations?: string[]
  mustDo?: string[]
  forbidden?: string[]
  tone?: string
  max_tokens?: number
  enabled?: boolean
  welcome_cs?: string
  welcome_en?: string
  welcome_de?: string
  knowledge_extra?: string  // freetext z Velínu, inject do promptu (sezonní akce, novinky, dočasné info...)
}

type CompanyInfo = {
  name?: string
  ico?: string
  dic?: string | null
  address?: string
  phone?: string
  email?: string
  web?: string
  bank_account?: string
}

type FleetMoto = {
  id: string
  brand: string | null
  model: string
  category: string | null
  license_required: string | null
  power_kw: number | null
  price_mon: number | null
  price_tue: number | null
  price_wed: number | null
  price_thu: number | null
  price_fri: number | null
  price_sat: number | null
  price_sun: number | null
}

async function loadConfig(): Promise<{ cfg: WebAgentConfig; company: CompanyInfo; fleet: FleetMoto[] }> {
  // Načti všechny relevantní app_settings klíče + KOMPLETNÍ aktivní flotilu paralelně.
  // company_info je zdroj pravdy o adrese / telefonu / emailu firmy (žádné hardcoded fakty).
  // Flotilu injektujeme do system promptu, aby model NIKDY nemohl halucinovat motorku,
  // kterou nemáme, ani tvrdit "nemáme" o motorce, kterou ve skutečnosti máme.
  try {
    const [cfgRes, ciRes, fleetRes] = await Promise.all([
      sb.from('app_settings').select('value').eq('key', 'ai_public_agent_config').maybeSingle(),
      sb.from('app_settings').select('value').eq('key', 'company_info').maybeSingle(),
      sb.from('motorcycles')
        .select('id, brand, model, category, license_required, power_kw, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun')
        .eq('status', 'active')
        .order('brand', { ascending: true })
        .order('model', { ascending: true }),
    ])
    return {
      cfg: (cfgRes.data?.value as WebAgentConfig) || {},
      company: (ciRes.data?.value as CompanyInfo) || {},
      fleet: (fleetRes.data as FleetMoto[]) || [],
    }
  } catch {
    return { cfg: {}, company: {}, fleet: [] }
  }
}

function formatFleetSnapshot(fleet: FleetMoto[]): string {
  if (!fleet || fleet.length === 0) {
    return `KOMPLETNÍ FLOTILA (live snapshot z DB):
- Žádné aktivní motorky v DB. NESLIBUJ ŽÁDNOU motorku — řekni zákazníkovi, že momentálně žádnou nepronajímáme, a doporuč kontakt firmy.`
  }
  const minPrice = (m: FleetMoto): number => {
    const ps = [m.price_mon, m.price_tue, m.price_wed, m.price_thu, m.price_fri, m.price_sat, m.price_sun]
      .map((p) => Number(p || 0)).filter((p) => p > 0)
    return ps.length > 0 ? Math.min(...ps) : 0
  }
  const lines = fleet.map((m, i) => {
    const name = `${m.brand || ''} ${m.model}`.trim()
    const cat = m.category || '—'
    const lic = m.license_required || '—'
    const kw = m.power_kw ? `${m.power_kw} kW` : '— kW'
    const mp = minPrice(m)
    const priceStr = mp > 0 ? `od ${mp} Kč/den` : 'cena dle dne'
    return `${i + 1}. **${name}** [id=${m.id}] — kat. ${cat}, ŘP ${lic}, ${kw}, ${priceStr}`
  })
  return `KOMPLETNÍ FLOTILA (live snapshot z DB v okamžiku tohoto requestu, ${fleet.length} aktivních motorek — JEDINÝ AUTORITATIVNÍ SEZNAM):
${lines.join('\n')}

PRAVIDLA NAD TÍMTO SEZNAMEM (BEZPODMÍNEČNÁ):
- Pokud zákazník zmíní značku/model, který NENÍ ve výše uvedeném seznamu (ani jako substring v "brand model") — řekni rovně "tuhle motorku momentálně nemáme" a nabídni ALTERNATIVU ze seznamu (stejná kategorie nebo skupina ŘP).
- Pokud zákazník zmíní značku/model, který V seznamu JE — NIKDY neřekni "nemáme". Vždy potvrď, že máme, a pokračuj přes \`search_motorcycles\` (s brand/model_query a available_on/from/to) pro ověření dostupnosti v termínu + \`calculate_price\` pro cenu.
- Pro doporučení ("co máte na A2", "něco do hor", "naked", …) volej \`search_motorcycles\` s odpovídajícími filtry — ten respektuje filtraci dostupnosti. NIKDY nevybírej z paměti modely, které tu nejsou v seznamu.
- Cenu, dostupnost a kompletní specs konkrétního kusu řeš VÝHRADNĚ přes tooly (\`calculate_price\`, \`get_availability\`, \`search_motorcycles\`). Tento seznam je orientace co existuje, ne ceník.
- Tento seznam je generován z DB při každém requestu — pokud uživatel tvrdí "měli jste tam Hondu", ale Honda v seznamu výše není, znamená to, že už ji nemáme. Reaguj profesionálně, neslibuj a nabídni alternativu.`
}

// ============================================================================
// Tools
// ============================================================================

const PUBLIC_TOOLS = [
  {
    name: 'search_motorcycles',
    description: 'Vyhledá motorky v MotoGo24 katalogu. Filtruj podle značky, modelu, kategorie, ŘP, výkonu, ceny nebo dostupnosti k danému datu. Když uživatel řekne "máš kawu/Kawasaki/BMW na pondělí" — ZAVOLEJ s `brand` a `available_on`, neinteroguj. Vrátí seznam s URL na detail.',
    input_schema: {
      type: 'object',
      properties: {
        brand: { type: 'string', description: 'Značka, např. "Kawasaki", "BMW", "Yamaha", "Honda", "KTM", "Husqvarna", "Ducati", "Suzuki", "Triumph". Case-insensitive substring match.' },
        model_query: { type: 'string', description: 'Volnotextový dotaz na model (např. "Z 900", "MT-09", "S 1000", "Versys"). Použij kombinovaně s brand pro přesnost.' },
        category: { type: 'string', enum: ['cestovni', 'naked', 'supermoto', 'detske'] },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'] },
        kw_min: { type: 'number' }, kw_max: { type: 'number' },
        price_max: { type: 'number', description: 'Max Kč/den' },
        available_on: { type: 'string', description: 'Datum YYYY-MM-DD — vrátí jen motorky volné v tento den. Použij při dotazech "na pondělí", "na 3. května" atp.' },
        available_from: { type: 'string', description: 'Spolu s available_to — rozsah YYYY-MM-DD pro celé období rezervace.' },
        available_to: { type: 'string' },
      },
    },
  },
  {
    name: 'get_availability',
    description: 'Zkontroluje obsazené termíny pro konkrétní motorku. Vrací seznam booked ranges. Použij PŘED kalkulací nebo rezervací.',
    input_schema: {
      type: 'object',
      properties: { moto_id: { type: 'string' } },
      required: ['moto_id'],
    },
  },
  {
    name: 'calculate_price',
    description: 'Vypočítá přesnou cenu pronájmu pro motorku a termín z reálného denního ceníku. NEVYTVÁŘÍ rezervaci.',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        promo_code: { type: 'string' },
      },
      required: ['moto_id', 'start_date', 'end_date'],
    },
  },
  {
    name: 'get_faq',
    description: 'Vyhledá v interní FAQ (CMS) podle klíčového slova (kauce, pojištění, řidičák, zahraničí, storno...). Vrací jen reálná data z administrace — pokud není v CMS, vrátí prázdno a TY pak zákazníkovi přiznáš, že to nevíš a doporučíš kontakt.',
    input_schema: {
      type: 'object',
      properties: { query: { type: 'string' } },
    },
  },
  {
    name: 'get_policies',
    description: 'Vrátí oficiální podmínky půjčovny z CMS (storno, kauce, co je v ceně, cenu přistavení, foreign travel, dokumenty pro vyzvednutí, tankování, věkové limity skupin ŘP). VŽDY zavolej, než zákazníkovi sdělíš jakékoliv konkrétní procento storno-poplatku, výši kauce, cenu přistavení nebo platnost pojištění mimo EU. Pokud tool vrátí prázdno, NEUVÁDĚJ konkrétní čísla z hlavy — řekni "tohle ti přesně neporadím, ozvi se na info@motogo24.cz".',
    input_schema: {
      type: 'object',
      properties: { topic: { type: 'string', description: 'Volitelně téma — cancellation, deposit, included, addons, delivery_pricing, foreign_travel, fuel, license_groups, documents.' } },
    },
  },
  {
    name: 'get_extras_catalog',
    description: 'Vrátí seznam příslušenství, které lze přiobjednat (boty, výbava spolujezdce, přistavení, atd.) s cenami.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'get_branches',
    description: 'Vrátí seznam poboček MotoGo24 s adresou, GPS a otevíracími hodinami.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'validate_promo_or_voucher',
    description: 'Ověří promo kód nebo voucher. Vrátí typ a hodnotu slevy. Pokud je kód neplatný, vrátí valid=false.',
    input_schema: {
      type: 'object',
      properties: { code: { type: 'string' } },
      required: ['code'],
    },
  },
  {
    name: 'create_booking_request',
    description: 'Vytvoří skutečnou rezervaci v systému (status pending) a vrátí přímý Stripe Checkout URL. VOLEJ POUZE až máš VŠECHNY povinné údaje (níže) a zákazník explicitně potvrdil souhrn (motorka, termín, cena). Po zavolání NEPIŠ URL platební brány do zprávy — systém k odpovědi automaticky doplní tlačítko "Pokračovat k platbě". Tvoje zpráva: krátké shrnutí (motorka, termín, cena) + pokyn "Klikni na tlačítko níže, otevře se zabezpečená platba (Stripe).".',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        name: { type: 'string', description: 'Celé jméno zákazníka (jméno + příjmení)' },
        email: { type: 'string' },
        phone: { type: 'string' },
        street: { type: 'string', description: 'POVINNÉ — Ulice + č.p. trvalého bydliště' },
        city: { type: 'string', description: 'POVINNÉ — Město trvalého bydliště' },
        zip: { type: 'string', description: 'POVINNÉ — PSČ' },
        country: { type: 'string', description: 'Stát, default CZ' },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'], description: 'POVINNÉ — Skupina ŘP zákazníka. "N" = bez ŘP (jen dětské motorky).' },
        license_number: { type: 'string', description: 'POVINNÉ (kromě license_group=N) — Číslo řidičského průkazu (min. 4 znaky).' },
        license_expiry: { type: 'string', description: 'POVINNÉ (kromě license_group=N) — Platnost ŘP do (YYYY-MM-DD).' },
        id_type: { type: 'string', enum: ['op', 'pas'], description: 'POVINNÉ — typ dokladu totožnosti: "op" = občanský průkaz, "pas" = cestovní pas.' },
        id_number: { type: 'string', description: 'POVINNÉ — Číslo dokladu totožnosti (OP nebo pas).' },
        password: { type: 'string', description: 'POVINNÉ — Heslo (min. 8 znaků) pro správu rezervace a přihlášení do appky MotoGo24.' },
        promo_code: { type: 'string' },
        note: { type: 'string' },
        pickup_time: { type: 'string', description: 'POVINNÉ — Čas vyzvednutí HH:MM. Pokud zákazník neřekne, default 10:00.' },
        return_time: { type: 'string', description: 'HH:MM, povinné pouze při vrácení mimo provozovnu (delivery/return-other).' },
        delivery_address: { type: 'string', description: 'Adresa přistavení mimo Mezná (např. "Vinohradská 12, 120 00 Praha 2"). Vyplň jen když zákazník POTVRDIL, že chce přistavení.' },
        return_address: { type: 'string', description: 'Adresa vrácení mimo Mezná. Vyplň jen když se liší od delivery_address, nebo když chce vrácení mimo půjčovnu.' },
        extras: {
          type: 'array',
          description: 'Přiobjednané příslušenství (boty, výbava spolujezdce, přistavení, atd.). Načti ceny přes get_extras_catalog. Položky: {name, unit_price}.',
          items: {
            type: 'object',
            properties: { name: { type: 'string' }, unit_price: { type: 'number' } },
            required: ['name', 'unit_price'],
          },
        },
        helmet_size: { type: 'string', description: 'Velikost helmy řidiče (XS-XXL). Volitelné — pokud zákazník neuvede, vybere si v půjčovně.' },
        jacket_size: { type: 'string', description: 'Velikost bundy řidiče (XS-XXL). Volitelné.' },
        pants_size: { type: 'string', description: 'Velikost kalhot řidiče (XS-XXL). Volitelné.' },
        boots_size: { type: 'string', description: 'Velikost bot řidiče (36-46). Volitelné — boty jsou jen za příplatek pro řidiče.' },
        gloves_size: { type: 'string', description: 'Velikost rukavic řidiče (XS-XXL). Volitelné.' },
        passenger_helmet_size: { type: 'string', description: 'Pokud bere spolujezdce — velikost jeho helmy.' },
        passenger_jacket_size: { type: 'string', description: 'Velikost bundy spolujezdce.' },
        passenger_boots_size: { type: 'string', description: 'Velikost bot spolujezdce.' },
        passenger_gloves_size: { type: 'string', description: 'Velikost rukavic spolujezdce.' },
      },
      required: ['moto_id', 'start_date', 'end_date', 'name', 'email', 'phone',
                 'street', 'city', 'zip', 'license_group', 'id_type', 'id_number', 'password'],
    },
  },
  {
    name: 'redirect_to_booking',
    description: 'Vygeneruje URL na rezervační formulář s předvyplněnými údaji. Použij když zákazník chce rezervaci dokončit sám na webu, nebo když chybí citlivé údaje pro create_booking_request.',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string' },
        end_date: { type: 'string' },
      },
      required: ['moto_id'],
    },
  },
]

async function execPublicTool(name: string, args: Record<string, unknown>): Promise<unknown> {
  switch (name) {
    case 'search_motorcycles': {
      let q = sb.from('motorcycles').select('id, model, brand, category, power_kw, license_required, color, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, ideal_usage')
        .eq('status', 'active').order('model')
      if (args.category) q = q.ilike('category', `%${args.category}%`)
      if (args.license_group) q = q.eq('license_required', args.license_group)
      if (args.kw_min) q = q.gte('power_kw', Number(args.kw_min))
      if (args.kw_max) q = q.lte('power_kw', Number(args.kw_max))
      if (args.brand) q = q.ilike('brand', `%${String(args.brand)}%`)
      if (args.model_query) q = q.ilike('model', `%${String(args.model_query)}%`)
      const { data } = await q
      let result = data || []
      if (args.price_max) {
        const maxP = Number(args.price_max)
        result = result.filter((m: Record<string, unknown>) => {
          const ps = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
            .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)
          return ps.length > 0 && Math.min(...ps) <= maxP
        })
      }

      // Filtr dostupnosti — buď konkrétní den (available_on) nebo rozsah (available_from/to)
      const availFrom = args.available_on ? String(args.available_on) : (args.available_from ? String(args.available_from) : null)
      const availTo = args.available_on ? String(args.available_on) : (args.available_to ? String(args.available_to) : null)
      if (availFrom && availTo) {
        const checks = await Promise.all(result.map(async (m: Record<string, unknown>) => {
          const { data: booked } = await sb.rpc('get_moto_booked_dates', { p_moto_id: m.id })
          const ranges = (booked || []) as Array<{ start_date: string; end_date: string }>
          const conflict = ranges.some((r) => !(availTo < r.start_date || availFrom > r.end_date))
          return { moto: m, free: !conflict }
        }))
        result = checks.filter((c) => c.free).map((c) => c.moto as Record<string, unknown>)
      }

      const minPriceFor = (m: Record<string, unknown>): number => {
        const ps = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
          .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)
        return ps.length > 0 ? Math.min(...ps) : 0
      }

      return {
        count: result.length,
        availability_window: availFrom ? { from: availFrom, to: availTo } : null,
        motorcycles: result.slice(0, 8).map((m: Record<string, unknown>) => ({
          id: m.id,
          name: `${m.brand || ''} ${m.model}`.trim(),
          brand: m.brand,
          category: m.category,
          power_kw: m.power_kw,
          license: m.license_required,
          min_price_kc: minPriceFor(m),
          ideal_usage: m.ideal_usage,
          url: `https://motogo24.cz/katalog/${m.id}`,
        })),
      }
    }
    case 'get_availability': {
      const { data } = await sb.rpc('get_moto_booked_dates', { p_moto_id: args.moto_id })
      return { booked: data || [] }
    }
    case 'calculate_price': {
      const { moto_id, start_date, end_date, promo_code } = args
      const { data: moto } = await sb.from('motorcycles')
        .select('model, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun')
        .eq('id', moto_id).maybeSingle()
      if (!moto) return { error: 'Motorka nenalezena' }
      const days = ['sun','mon','tue','wed','thu','fri','sat']
      const start = new Date(String(start_date)), end = new Date(String(end_date))
      if (isNaN(start.getTime()) || isNaN(end.getTime())) return { error: 'Neplatné datum' }
      if (end < start) return { error: 'Konec musí být po začátku' }

      const motoRow = moto as Record<string, unknown>
      let total = 0, count = 0
      const missingDays: string[] = []
      const d = new Date(start)
      while (d <= end) {
        const dn = days[d.getDay()]
        const raw = motoRow['price_' + dn]
        const price = raw == null ? null : Number(raw)
        if (price == null || !isFinite(price) || price <= 0) {
          missingDays.push(d.toISOString().slice(0, 10))
        } else {
          total += price
        }
        count++
        d.setDate(d.getDate() + 1)
      }
      // Cena pro motorku není kompletní — radši nic nevrať než ohlásit nesprávně nízkou cenu.
      if (missingDays.length > 0) {
        return {
          error: 'Ceník této motorky pro některé dny chybí v DB — nemůžu zaručit přesnou cenu. Doporuč zákazníkovi rezervaci dokončit ve formuláři, kde se cena spočítá konzervativně.',
          missing_price_days: missingDays,
        }
      }
      let discount = 0
      let promoApplied: { type: string; value: number } | null = null
      if (promo_code) {
        const { data: pr } = await sb.rpc('validate_promo_code', { code: promo_code })
        if (pr && (pr as Record<string, unknown>).valid) {
          const p = pr as Record<string, unknown>
          const v = Number(p.value)
          if (p.type === 'percent') discount = Math.round(total * v / 100)
          else discount = v
          promoApplied = { type: String(p.type), value: v }
        }
      }
      return {
        days: count,
        rental_total: total,
        promo_discount: discount,
        promo_applied: promoApplied,
        grand_total: total - discount,
        currency: 'CZK',
        // Důležitá výhrada: agentu přímo říkáme, co cena NEzahrnuje — ať to zmíní zákazníkovi, ne aby
        // tvrdil "celková cena XY Kč" a zákazník byl pak překvapený extras nebo dopravou.
        note_excludes: 'Cena nezahrnuje příplatky za přistavení mimo Mezná, výbavu spolujezdce, boty pro řidiče, GPS, top case ani jiné extras — ty se připočítají v rezervačním formuláři dle výběru.',
      }
    }
    case 'get_faq': {
      // Jediný zdroj pravdy: CMS klíč app_settings.site.faq (admin edituje z Velínu → CMS → Web texts → FAQ).
      // Struktura: { categories: { <key>: { label, items: [{q, a}] } } }.
      // ŽÁDNÝ hardcoded fallback s konkrétními tvrzeními — když je CMS prázdné, vracíme prázdno
      // a agent musí přiznat, že na to neodpoví, místo aby halucinoval policies z hlavy.
      const stripHtml = (s: string) => String(s || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
      const faqs: Array<{ q: string; a: string; cat?: string }> = []
      try {
        const { data: cms } = await sb.from('app_settings').select('value').eq('key', 'site.faq').maybeSingle()
        const cats = (cms?.value as Record<string, unknown>)?.categories as Record<string, { label?: string; items?: Array<{ q?: string; a?: string }> }> | undefined
        if (cats && typeof cats === 'object') {
          for (const [catKey, cat] of Object.entries(cats)) {
            for (const it of (cat.items || [])) {
              if (it.q && it.a) faqs.push({ q: stripHtml(it.q), a: stripHtml(it.a), cat: cat.label || catKey })
            }
          }
        }
      } catch { /* CMS nedostupný — vrátíme prázdno a agent to korektně přizná */ }

      if (faqs.length === 0) {
        return {
          source: 'empty',
          count: 0,
          faqs: [],
          notice: 'FAQ v CMS není naplněna. NESDÍLEJ konkrétní policies z hlavy. Doporuč zákazníkovi kontakt info@motogo24.cz / +420 774 256 271, nebo zavolej tool get_policies a získej oficiální podmínky odtud. NIKDY si neimprovizuj cenu kauce, % storno-poplatku ani podmínky pojištění.',
        }
      }

      const query = String(args.query || '').toLowerCase().trim()
      const matched = query
        ? faqs.filter((f) => (f.q + ' ' + f.a + ' ' + (f.cat || '')).toLowerCase().includes(query))
        : faqs
      return { source: 'cms', count: matched.length, faqs: matched.slice(0, 8) }
    }
    case 'get_policies': {
      // Oficiální podmínky půjčovny z CMS klíče app_settings.site.policies. Admin si tam vyplňuje
      // strukturovaný JSON ve Velínu. Pokud je klíč prázdný, vracíme prázdno + explicitní pokyn agentovi.
      try {
        const { data: cms } = await sb.from('app_settings').select('value').eq('key', 'site.policies').maybeSingle()
        const policies = (cms?.value as Record<string, unknown>) || {}
        if (!policies || Object.keys(policies).length === 0) {
          return {
            source: 'empty',
            policies: {},
            notice: 'Policies v CMS nejsou nastavené. NESDÍLEJ z hlavy konkrétní procenta storna, výši kauce, cenu přistavení, pojištění mimo EU ani věkové limity skupin ŘP, které nejsou v české vyhlášce. Místo toho přiznej, že přesná čísla najde zákazník v textu smlouvy / VOP, nebo doporuč info@motogo24.cz / +420 774 256 271.',
          }
        }
        const topic = String((args as Record<string, unknown>).topic || '').toLowerCase().trim()
        if (topic && policies[topic] !== undefined) {
          return { source: 'cms', topic, value: policies[topic] }
        }
        return { source: 'cms', policies }
      } catch (e) {
        return { error: `Nepodařilo se načíst policies: ${(e as Error).message}` }
      }
    }
    case 'get_extras_catalog': {
      const { data } = await sb.from('extras_catalog')
        .select('id, name, description, price, unit, category, is_active')
        .eq('is_active', true).order('sort_order', { ascending: true }).order('name')
      return { extras: (data || []).map((e: Record<string, unknown>) => ({
        id: e.id, name: e.name, price_kc: e.price, unit: e.unit || 'ks', category: e.category, description: e.description,
      })) }
    }
    case 'get_branches': {
      const { data } = await sb.from('branches')
        .select('id, name, address, city, zip, lat, lng, phone, is_open, type, notes')
        .order('name')
      return { branches: (data || []).map((b: Record<string, unknown>) => ({
        id: b.id, name: b.name, address: `${b.address || ''}, ${b.zip || ''} ${b.city || ''}`.trim(),
        lat: b.lat, lng: b.lng, phone: b.phone, is_open_nonstop: !!b.is_open, type: b.type, notes: b.notes,
      })) }
    }
    case 'validate_promo_or_voucher': {
      const code = String(args.code || '').trim()
      if (!code) return { valid: false, error: 'Prázdný kód' }
      const { data: promo } = await sb.rpc('validate_promo_code', { code })
      if (promo && (promo as Record<string, unknown>).valid) {
        return { valid: true, kind: 'promo', ...(promo as Record<string, unknown>) }
      }
      const { data: vch } = await sb.rpc('validate_voucher_code', { p_code: code })
      if (vch && (vch as Record<string, unknown>).valid) {
        return { valid: true, kind: 'voucher', ...(vch as Record<string, unknown>) }
      }
      return { valid: false, error: 'Kód není platný nebo už byl použit.' }
    }
    case 'create_booking_request': {
      const a = args as Record<string, string>
      // Sanity: dnešní datum nebo budoucnost
      const today = new Date(); today.setHours(0,0,0,0)
      const start = new Date(a.start_date)
      if (isNaN(start.getTime()) || start < today) {
        return { error: 'Neplatné datum začátku — musí být dnes nebo později.' }
      }
      // Validate availability
      const { data: booked } = await sb.rpc('get_moto_booked_dates', { p_moto_id: a.moto_id })
      const bookedArr = Array.isArray(booked) ? booked : []
      const startMs = start.getTime()
      const endMs = new Date(a.end_date).getTime()
      for (const b of bookedArr as Array<Record<string, unknown>>) {
        if (b.status === 'cancelled' || b.status === 'completed' || b.status === 'rejected') continue
        const bs = new Date(String(b.start_date)).getTime()
        const be = new Date(String(b.end_date)).getTime()
        if (startMs <= be && endMs >= bs) {
          return { error: 'Termín je obsazený. Vyber jiný termín.' }
        }
      }
      const ax = args as Record<string, unknown>
      const extrasArr = Array.isArray(ax.extras) ? (ax.extras as Array<Record<string, unknown>>) : []
      const { data, error } = await sb.rpc('create_web_booking', {
        p_moto_id: a.moto_id,
        p_start_date: a.start_date,
        p_end_date: a.end_date,
        p_name: a.name,
        p_email: a.email,
        p_phone: a.phone,
        p_street: a.street || null,
        p_city: a.city || null,
        p_zip: a.zip || null,
        p_country: a.country || 'CZ',
        p_note: a.note || 'Rezervace z AI asistenta',
        p_pickup_time: a.pickup_time || '10:00',
        p_delivery_address: a.delivery_address || null,
        p_return_address: a.return_address || null,
        p_extras: extrasArr,
        p_discount_amount: 0,
        p_discount_code: null,
        p_promo_code: a.promo_code || null,
        p_voucher_id: null,
        p_license_group: a.license_group || null,
        p_password: null,
        p_helmet_size: a.helmet_size || null,
        p_jacket_size: a.jacket_size || null,
        p_pants_size: a.pants_size || null,
        p_boots_size: a.boots_size || null,
        p_gloves_size: a.gloves_size || null,
        p_passenger_helmet_size: a.passenger_helmet_size || null,
        p_passenger_jacket_size: a.passenger_jacket_size || null,
        p_passenger_gloves_size: a.passenger_gloves_size || null,
        p_passenger_boots_size: a.passenger_boots_size || null,
        p_return_time: a.return_time || null,
      })
      if (error) {
        return { error: `Rezervaci se nepodařilo vytvořit: ${error.message}` }
      }
      const result = data as Record<string, unknown>
      const bookingId = String(result?.booking_id || '')
      const userId = String(result?.user_id || '')
      const amount = Number(result?.amount || 0)

      // Doplnit do profilu údaje, které create_web_booking nezapisuje (license/ID).
      // Tohle pokrývá full data collection AI agentem (jinak by webová rezervace
      // forma musela být dovyplněna ručně).
      try {
        if (userId) {
          const profileUpdate: Record<string, unknown> = {}
          if (a.id_number) profileUpdate.id_number = a.id_number
          if (a.license_number) profileUpdate.license_number = a.license_number
          if (a.license_expiry) profileUpdate.license_expiry = a.license_expiry
          if (a.license_group) profileUpdate.license_group = [a.license_group]
          if (Object.keys(profileUpdate).length > 0) {
            await sb.from('profiles').update(profileUpdate).eq('id', userId)
          }
        }
      } catch { /* non-blocking */ }

      // Nastavit heslo zákazníka (pro správu rezervace a přihlášení do appky).
      try {
        if (a.password && bookingId) {
          await sb.rpc('set_web_booking_password', { p_booking_id: bookingId, p_password: a.password })
        }
      } catch { /* non-blocking */ }
      // Hned zkusíme získat reálný Stripe Checkout URL přes process-payment.
      // Když selže (např. amount <= 0), fallback na resume URL.
      let paymentUrl = `https://motogo24.cz/rezervace/dokoncit?id=${bookingId}`
      try {
        const ppResp = await fetch(`${SUPABASE_URL}/functions/v1/process-payment`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
            'apikey': SUPABASE_SERVICE_KEY,
          },
          body: JSON.stringify({ source: 'web', booking_id: bookingId }),
        })
        if (ppResp.ok) {
          const pp = await ppResp.json() as Record<string, unknown>
          if (pp.checkout_url) paymentUrl = String(pp.checkout_url)
        }
      } catch { /* fallback paymentUrl */ }
      return {
        success: true,
        booking_id: bookingId,
        amount_kc: amount,
        is_new_user: !!result?.is_new_user,
        payment_url: paymentUrl,
        message: 'Rezervace vytvořena. NEPIŠ URL platební brány do textu — systém k tvé odpovědi automaticky doplní tlačítko "Pokračovat k platbě" s plným odkazem (URL Stripe obsahuje povinný #fragment, který se při kopírování často poškodí). Tvoje odpověď: krátké shrnutí (motorka, termín, celková cena) + věta "Klikni na tlačítko níže, otevře se zabezpečená platba (Stripe). Po zaplacení dorazí email s potvrzením a přístupovými kódy."',
      }
    }
    case 'redirect_to_booking': {
      const params = new URLSearchParams()
      if (args.moto_id) params.set('moto', String(args.moto_id))
      if (args.start_date) params.set('start', String(args.start_date))
      if (args.end_date) params.set('end', String(args.end_date))
      return {
        url: `https://motogo24.cz/rezervace?${params}`,
        instruction: 'Pošli uživateli tento odkaz s pozváním k dokončení rezervace na webu.',
      }
    }
    default:
      return { error: `Unknown tool: ${name}` }
  }
}

// ============================================================================
// System prompt builder
// ============================================================================

function buildCompanyBrain(company: CompanyInfo): string {
  // Minimální orientační znalost. Všechna business pravidla (storno, kauce, ceny přistavení,
  // foreign-travel pojištění, tankování-policy, co je v ceně) jsou výhradně v CMS přes get_policies
  // a get_faq. Statické zde zůstává jen: identita firmy (z app_settings.company_info), technický
  // stav systému (jak funguje platba a doklady) a obecná zákonná fakta (skupiny ŘP).
  const addr = company.address || 'Mezná 9, 393 01 Pelhřimov'
  const phone = company.phone || '+420 774 256 271'
  const email = company.email || 'info@motogo24.cz'
  const web = company.web || 'https://motogo24.cz'
  const ico = company.ico ? `, IČO ${company.ico}` : ''
  const name = company.name || 'MotoGo24'
  return `
ORIENTAČNÍ ZNALOST O FIRMĚ (všechna ostatní fakta výhradně z tools — motorcycles, branches, extras_catalog, get_faq, get_policies):

— FIREMNÍ ÚDAJE (z app_settings.company_info, jediný autoritativní zdroj) —
* Provozovatel: ${name}${ico}.
* Adresa: ${addr}.
* Telefon: ${phone}. Email: ${email}. Web: ${web}.
* Otevírací doba, GPS, typ pobočky, poznámky → VŽDY \`get_branches\`. Nikdy z hlavy.

— TECHNICKÝ STAV SYSTÉMU (statický, nemění se) —
* Vyzvednutí přes přístupový kód, který přijde SMS / emailem až po: a) zaplacení, b) nahrání dokladů (občanka/pas + řidičák, OCR ověřuje Mindee). Bez splnění obojího kód systém nepustí — to je technický stav DB, ne business pravidlo.
* Platba: Stripe Checkout (Visa, Mastercard, Amex, Apple Pay, Google Pay), LIVE mode, online.

— SKUPINY ŘP (obecné zákonné limity ČR; konkrétní podmínky půjčovny → get_policies) —
* AM (od 15) — pomalé skútry, neprovozujeme.
* A1 (od 16) — do 11 kW a 125 ccm.
* A2 (od 18) — do 35 kW.
* A (od 24, nebo 20+ s 2 roky A2) — bez omezení výkonu.
* B — opravňuje k A1 v ČR po 3 letech držení.
* N — bez ŘP (dětské motorky, ručí zákonný zástupce).

— CO MUSÍŠ NAČÍST PŘES TOOLS (NIKDY z paměti) —
* Aktuální flotila → \`search_motorcycles\`.
* Cena pronájmu pro termín → \`calculate_price\` (ten výslovně NEzahrnuje extras a dopravu — TY to musíš zákazníkovi sdělit).
* Příslušenství s cenami (boty, výbava spolujezdce, top case, GPS, přistavení) → \`get_extras_catalog\`.
* Pobočky, GPS, otevírací doba → \`get_branches\`.
* Storno-poplatky, výše kauce, ceny přistavení mimo Mezná, foreign-travel, dokumenty, tankování-policy, věkové limity půjčovny → \`get_policies\`. Pokud tool vrátí prázdno, NEIMPROVIZUJ čísla — řekni "tohle ti přesně neporadím, najdeš to ve smlouvě / VOP nebo zavolej ${phone}".
* FAQ → \`get_faq\`.
* Promo / vouchery → \`validate_promo_or_voucher\`.

— ZÁKAZ HALUCINACE FLOTILY —
* Autoritativní seznam motorek MÁŠ injektovaný výše v sekci „KOMPLETNÍ FLOTILA (live snapshot z DB…)". To, co tam NENÍ, u nás NEEXISTUJE. To, co tam JE, u nás máme — bez ohledu na to, co si „pamatuješ" z trénovacích dat.
* Konkrétní značku + model jmenuj jen pokud je v injektovaném snapshotu nebo ti ho zrovna vrátil \`search_motorcycles\`. Žádné „typicky", „třeba", „mohli bychom mít".
* Pro výběr / doporučení (kategorie, ŘP, výkon, cena, dostupnost v termínu) VŽDY volej \`search_motorcycles\` s odpovídajícími filtry. Doporučuj POUZE motorky vrácené tímto toolem — i když máš snapshot, dostupnost v termínu řeší jen tool.
* Pokud snapshot obsahuje 0 položek, neslibuj žádnou motorku a doporuč kontakt firmy.
`
}

const MOTO_KNOWLEDGE_TIPS = `
JAK MLUVÍ MOTORKÁŘI (používej slang přirozeně, když ti zákazník tyká a je v pohodě):
- "káva" = café racer, "céra" = sportovní litr, "naháč" = naked, "endo" = enduro, "supec" = supermoto, "tourák" = sport-tourer / cestovka.
- "japonáš" = japonská čtyřválcová litrovka. "kawec/kavec" = Kawasaki. "ducati / ducka" = Ducati. "ktm-ko" = KTM. "bavorák" = BMW.
- "vrhnout to do zatáčky", "kolínko ven", "stoupák" (wheelie), "vyhasit motor" = stupně volnosti motorkáře. Rozumíš tomu, ale neopaprouj to umělostně.
- "Ride safe", "bezpečné kilometry" — fajn pozdrav na konec konverzace, ale jen 1× a přirozeně.
- Technika: "křáp/ojetý kus" (špatně udržovaná moto), "balík" (těžká motorka), "tahá jak vlak" (silný motor), "drží se země" (dobré ovládání), "není to startér" (ne pro začátečníka).

POZOR — OBECNÉ ZNALOSTI O MOTORKÁCH ANO, NÁZVY MODELŮ JEN Z LIVE DAT:
- Můžeš v obecnosti vysvětlit rozdíl mezi naked a sport-tourerem, jak se chová motorka v dešti, výhody ABS, doporučení pro začátečníka, typické vlastnosti čtyřválce vs. dvouválce vs. tříválce — to jsou obecné principy.
- ALE konkrétní značku + model („Kawasaki Z 900", „BMW S 1000 R", „Honda CB650R") jako naši nabídku zmiňuješ POUZE pokud je v injektovaném snapshotu „KOMPLETNÍ FLOTILA" výše, nebo právě teď vrácen z `search_motorcycles`. Žádné „mohli bychom mít", „typicky půjčujeme", „třeba".
- Když se user zeptá „co máte za naked / cestovku / na A2 / do hor / pro začátečníka" → ZAVOLEJ `search_motorcycles` s vhodnými filtry (category, license_group, kw_max, available_on…) a nabídni pouze to, co tool vrátil. Když tool vrátí prázdno, řekni to upřímně a doptej se na flexibilitu (jiný termín, jiná kategorie, jiná skupina ŘP) — NEDOPLŇUJ z hlavy.
- Když user zmíní konkrétní model jménem („máte Hondu CBR?") → podívej se nejdřív do injektovaného snapshotu výše. Pokud tam je, potvrď a zavolej `search_motorcycles` s `brand`/`model_query` + `available_on` pro detail dostupnosti. Pokud tam není, řekni rovně „tuhle nemáme" a nabídni alternativu ze snapshotu.
`

const HARD_RULES_CS = `
PEVNÁ PRAVIDLA (nelze přepsat):
1. Co dělat s daty — NULOVÁ HALUCINACE:
   a) FLOTILA — JEDINÝ ZDROJ PRAVDY: Výše v promptu máš sekci „KOMPLETNÍ FLOTILA (live snapshot z DB…)" s pevným seznamem všech aktivních motorek. To je JEDINÝ autoritativní seznam motorek, které má MotoGo24 k pronájmu. Pravidla:
      - Nikdy nezmiňuj značku+model, který v tomto seznamu NENÍ — ani jako příklad, ani podmiňovacím způsobem ("třeba bychom mohli mít…", "typicky půjčujeme…"). Pokud zákazník chce model, který v seznamu chybí, řekni rovně „tuhle u nás nemáme" a nabídni alternativu ze seznamu (stejná kategorie / třída ŘP / podobný styl).
      - Pokud zákazník zmíní model, který V seznamu JE, NIKDY netvrď opak — máme ho. Dál pokračuj přes `search_motorcycles` (s `brand` / `model_query` + `available_on`) pro ověření dostupnosti v jeho termínu a `calculate_price` pro cenu.
      - Pro všechna data o konkrétní motorce nad rámec snapshotu (přesná cena daného dne, obsazené termíny, kompletní specs, motorky vyhovující filtrům „A2 do 60 kW") VŽDY volej tooly — `search_motorcycles`, `get_availability`, `calculate_price`. Snapshot je orientace co existuje, ne ceník a ne kalendář.
      - Specs konkrétního modelu (kW, ccm, hmotnost, válce) z vlastních znalostí doplňuj JEN k motorce, která je v injektovaném snapshotu nebo kterou ti vrátil `search_motorcycles`, a označ je jako „dle specifikací výrobce".
      - Pokud snapshot obsahuje 0 motorek, vůbec žádný model nezmiňuj a doporuč kontakt firmy — to znamená, že právě teď nic aktivního v DB není.
   b) PODMÍNKY (storno, kauce, dokumenty, tankování, foreign-travel, věkové limity půjčovny, ceny přistavení): VŽDY z `get_policies` nebo `get_faq`. Když tool vrátí prázdno (source='empty'), NIKDY si neimprovizuj konkrétní procenta, výši kauce, ceny nebo data. Místo toho přiznej "tohle ti přesně neporadím" a doporuč kontakt firmy. Tvrzení typu „bez kauce", „storno 7 dní zdarma", „v ceně havarijní pojištění" smí padnout JEN pokud to právě vrátil tool, nebo pokud to zákazník našel sám na webu.
   c) CENA REZERVACE: VŽDY `calculate_price`. Pokud tool vrátí `error` (např. chybí ceník dne), NEHÁDEJ — řekni zákazníkovi, že kalkulaci dokončí formulář v rezervaci, ať otevře `redirect_to_booking`. Cena z toolu NEzahrnuje extras a dopravu — explicitně to zákazníkovi sděl, ať není překvapený.
   d) POBOČKY (adresa, GPS, otevírací doba, kontakt na pobočku): VŽDY z `get_branches` nebo `app_settings.company_info` (vidíš v promptu). Nikdy ze své paměti.
   e) OBECNÉ ZNALOSTI o motorkách (rozdíl mezi naked a sport-tourer, jak se chová motorka v dešti, výhody ABS, motorkářská kultura) — z vlastních znalostí v obecné rovině, ALE bez konkrétních značek+modelů jako „naše nabídka" a bez konkrétních politik půjčovny.
   f) KDYŽ SI NEJSI JISTÝ — radši se DOPTEJ, nebo zavolej tool. NIKDY nemlč, neimprovizuj, ani neodkazuj automaticky na telefon — telefon až jako poslední možnost po vyčerpání toolů.

2. Komunikační styl — ZRCADLI uživatele:
   - Tyká → tykej. Vyká → vykej. Neformální slang ("ahoj", "týpku") → uvolnit. Formální ("dobrý den") → držet zdvořile.
   - Krátká zpráva → krátká odpověď. Když user napíše dlouze a chce detail → můžeš víc.
   - Žádné AI-fráze typu "jako AI asistent…", "rád pomohu", "určitě, samozřejmě, samozřejmě". Mluv jako prodavač/poradce v půjčovně, ne jako chatbot.

3. Nikdy neodbývej zákazníka odkazem na telefon/email. Telefon a email uveď JEN když:
   - Zákazník výslovně chce mluvit s člověkem.
   - Jde o SOS situaci (nehoda, porucha v jízdě, krize).
   - Chce řešit reklamaci nebo právní záležitost.
   Jinak: doptej se, nabídni alternativu, použij tooly. AI od toho je, aby řešilo věci.

4. Když tool vrátí prázdný seznam:
   - Neříkej "nemáme nic". Místo toho NABÍDNI ALTERNATIVU: jiná skupina ŘP (A2 → A pokud má 24+ let, A → A2 detune), jiná kategorie, blízký termín, podobný model. Nebo se doptej co je důležitější (cena? styl? výkon?).

5. Před kalkulací ceny VŽDY zavolej get_availability (ať vidíš, jestli je termín volný).

6. POVINNÝ CHECKLIST PŘED create_booking_request — postupně se doptej na vše, co chybí, a NEVYNECHEJ ANI JEDEN BOD. Pokud něco ještě nemáš, NEVOL nástroj. Jdi po blocích, ne všechno najednou (max. 2-3 položky na zprávu, ať to nezahltí). Pořadí:
   a) MOTORKA + TERMÍN: moto_id, start_date, end_date (z konverzace + search_motorcycles + get_availability).
   b) KONTAKT: celé jméno (jméno + příjmení), email, telefon (mobilní +420… nebo mezinárodní).
   c) ADRESA TRVALÉHO BYDLIŠTĚ: ulice + č.p., město, PSČ. (Stát default CZ — doptej se jen pokud je zjevně cizinec.)
   d) ŘIDIČSKÝ PRŮKAZ: skupina (A2 / A / B / A1 / N), číslo ŘP a platnost ŘP do (DD.MM.RRRR). Skupina N = bez ŘP, jen dětské motorky — pak číslo a platnost ŘP nepotřebuješ.
   e) DOKLAD TOTOŽNOSTI: typ (občanka nebo cestovní pas) + číslo dokladu.
   f) HESLO pro správu rezervace a přihlášení do appky (min. 8 znaků). Ujisti zákazníka, že heslo nikdo z týmu nevidí.
   g) VYZVEDNUTÍ: čas (HH:MM) — defaultně 10:00, doptej se. Místo: standardně Mezná 9, Pelhřimov; pokud chce přistavení, zeptej se na adresu (ulice + město + PSČ) a čas. Přistavení je placená služba — orientačně 1000 Kč + 40 Kč/km, přesné účtování probíhá v rezervačním formuláři / smlouvě.
   h) VRÁCENÍ: pokud chce vrátit jinde než v Mezné, doptej se na adresu a čas vrácení. Jinak vrácení v Mezné, čas si zvolí sám (24/7 přístup).
   i) SPOLUJEZDEC: zeptej se, jestli pojede s někým. Pokud ano, výbava spolujezdce je za příplatek — nabídni get_extras_catalog a doptej se na velikosti (helma, bunda, rukavice, boty).
   j) VÝBAVA ŘIDIČE: helma / bunda / kalhoty / rukavice jsou v ceně, velikost si vybere v půjčovně — neptej se, pokud se zákazník nezeptá nebo chce upřesnit. Boty řidič za příplatek (290 Kč/den) — nabídni a doptej se na velikost (36-46), pokud chce.
   k) EXTRAS: zeptej se, jestli chce ještě něco z get_extras_catalog (přistavení, top case, GPS, ...).
   l) PROMO/VOUCHER: pokud zákazník zmíní kód, ověř přes validate_promo_or_voucher.
   m) SOUHRN A POTVRZENÍ: před voláním create_booking_request VŽDY shrň motorku, termín, vyzvednutí/vrácení, výbavu navíc, celkovou cenu — a počkej na explicitní "ano / rezervuj / potvrzuju". Až pak vol nástroj.

7. PO create_booking_request:
   - NIKDY nepiš URL Stripe Checkout do textu odpovědi. Systém k tvé odpovědi automaticky doplní tlačítko "Pokračovat k platbě →" (s tím správným URL).
   - Tvá odpověď: krátké shrnutí (motorka, termín, celková cena) + věta typu "Rezervaci jsem vytvořil. Klikni na tlačítko níže — otevře se zabezpečená platba (Stripe). Po zaplacení ti přijde email s potvrzením a přístupovými kódy k motorce."
   - Pokud máš heslo, ujisti zákazníka, že přístup do appky/správy rezervace je nastaven.

8. Datum a rok ber VŽDY z hlavičky "DNES JE …" výše. "Tento víkend / pondělí" si spočítej z toho.

9. Drž odpověď úměrnou dotazu. Krátká otázka → 1-3 věty. Dlouhá technická → můžeš víc, ale bez výplní.

10. Bez markdown tabulek a emoji. Tučné (**text**) jen na názvy modelů. Odkazy piš výhradně ve formátu [text](https://...) — uveď CELOU URL včetně případného #fragmentu, nikdy ji nezkracuj.

11. JSI OBCHODNÍK A KAMARÁD, NE TAZATEL:
    - Když user řekne "máš kawu na pondělí?" — NEPLATÍ "jakou kategorii?". ROVNOU zavolej search_motorcycles s parametry brand="Kawasaki" a available_on="2026-04-27" (datum dopočítej z dnešního). Pak ukaž 1-3 dostupné kusy z výsledku s cenou/dnem a dej short CTA "kterou ti rezervuju?". Pokud tool vrátí 0 kusů, řekni rovně „v pondělí žádnou Kawasaki volnou nemám" a nabídni alternativu (jiná značka z výsledku jiného search_motorcycles, nebo jiný den) — NEVYMÝŠLEJ konkrétní model, který tam nebyl.
    - Když user napíše "něco do hor" / "na výlet po Evropě" / "začínám" — ZAVOLEJ search_motorcycles (category/license_group/kw rozsah) a doporuč 2-3 stroje POUZE z toho, co tool vrátí. Nikdy nedoporučuj konkrétní model jen z hlavy.
    - Vždy posuň konverzaci o krok blíž k rezervaci. Jedna proaktivní nabídka / jedna otázka navíc, nikdy víc otázek najednou.
    - Když je víc rovnocenných možností (z toolu), vyber 2 nej (jednu cenovou, jednu prémiovou) a pojmenuj rozdíl.

12. JAZYKOVÁ KÁZEŇ:
    - Drž JEDEN jazyk celou odpověď. Nikdy nemíchej (žádné "máme plusieurs modelů" ani "let's check dostupnost").
    - Když si nejsi jistý slovem v cílovém jazyce, použij opisy v tom samém jazyce, ne anglicismus.

13. KONTEXT STRÁNKY (page_context):
    - Když je v systémovém promptu blok "KONTEXT AKTUÁLNÍ STRÁNKY", zákazník stojí na konkrétní stránce webu (motorka, blog, FAQ, ...).
    - Demonstrativa "tuhle / tenhle / tu / to / tady" BEZ upřesnění modelu = vždy odkazuje na entitu z page_context (typicky moto_id).
    - "Rezervuj mi tuhle motorku" → použij moto_id z page_context, doptej se na termín a pokračuj checklistem (bod 6). NEPTEJ se "kterou motorku".
    - "Kolik stojí" / "je volná" / "co umí" → tooly (calculate_price, get_availability, search_motorcycles) volej s moto_id z page_context.
    - Když user explicitně přepne ("ne tuhle, ukaž mi A2"), kontext stránky ignoruj a řiď se zprávou.
    - U stránek typu blog_detail / faq / jak_pujcit používej h1 + označený text + tooly (get_faq, get_policies, get_branches) — odpovídej k tématu, ne obecně.

14. NEVYMÝŠLEJ FORMÁTY:
    - Nepoužívej "(45.123, 12.345)" pseudo-citace. GPS, telefon, ceny — vždy z toolů (get_branches pro GPS, get_extras_catalog/calculate_price pro ceny) nebo z bloku „FIREMNÍ ÚDAJE" výše.
    - Když tool selže nebo vrátí prázdno, řekni to lidsky a nabídni další krok ("Tahle Kawa je v pondělí blokovaná, mám ti najít jinou na ten samý den, nebo ti tuhle hodím na úterý?").
`

const TONE_DESC: Record<string, string> = {
  concise: 'TÓN: Maximálně stručný — 1-3 věty na odpověď, bez výplní.',
  friendly: 'TÓN: Přátelský, neformální, vlídný.',
  professional: 'TÓN: Formální, věcný, profesionální.',
  detailed: 'TÓN: Podrobný — vysvětluj kontext a souvislosti.',
}

// ============================================================================
// Page context (kde uživatel zrovna je na webu)
// ============================================================================
type PageContext = {
  url?: string
  path?: string
  type?: string  // home, moto_detail, katalog, shop, shop_detail, blog, blog_detail, faq, kontakt, ...
  title?: string
  h1?: string
  moto_id?: string | null
  slug?: string | null
  selection?: string  // text, který má uživatel označený v okně
  extra?: Record<string, unknown> | null  // co stránka sama vystaví (window.MOTOGO_PAGE_CTX)
}

function trimStr(v: unknown, max: number): string {
  if (typeof v !== 'string') return ''
  return v.replace(/\s+/g, ' ').trim().slice(0, max)
}

function formatPageContext(ctx: PageContext | null | undefined): string {
  if (!ctx || typeof ctx !== 'object') return ''
  const url = trimStr(ctx.url, 300)
  const path = trimStr(ctx.path, 200)
  const type = trimStr(ctx.type, 40) || 'other'
  const title = trimStr(ctx.title, 200)
  const h1 = trimStr(ctx.h1, 200)
  const motoId = trimStr(ctx.moto_id, 100)
  const slug = trimStr(ctx.slug, 200)
  const selection = trimStr(ctx.selection, 500)
  const lines: string[] = []
  lines.push('KONTEXT AKTUÁLNÍ STRÁNKY (kde se uživatel právě teď dívá):')
  if (url) lines.push(`- URL: ${url}`)
  if (path) lines.push(`- Path: ${path}`)
  if (type) lines.push(`- Typ stránky: ${type}`)
  if (title) lines.push(`- <title>: ${title}`)
  if (h1) lines.push(`- <h1>: ${h1}`)
  if (motoId) lines.push(`- moto_id: ${motoId}  ← UŽIVATEL PROHLÍŽÍ TUTO MOTORKU`)
  if (slug) lines.push(`- slug: ${slug}`)
  if (selection) lines.push(`- Označený text: "${selection}"`)
  if (ctx.extra && typeof ctx.extra === 'object') {
    try {
      const raw = JSON.stringify(ctx.extra).slice(0, 1500)
      if (raw && raw !== '{}') lines.push(`- Extra (z window.MOTOGO_PAGE_CTX): ${raw}`)
    } catch { /* ignore */ }
  }
  lines.push('')
  lines.push('JAK TO POUŽÍT:')
  lines.push('- Když user řekne "rezervuj mi tuhle/tuto motorku", "kolik stojí", "je volná na X", "tahle se mi líbí" — bez upřesnění modelu — VŽDYCKY použij moto_id výše. NEPTEJ se "kterou motorku?".')
  lines.push('- Když user řekne "co tu čtu / vysvětli mi to / jak je to s tímhle" — drž se obsahu této stránky (typ + h1 + označený text) a odpověz konkrétně, ne obecně.')
  lines.push('- Když je type=blog_detail / faq / jak_pujcit / pujcovna a user se ptá obecně, vycházej z aktuálního obsahu stránky a doplň relevantní fakta přes get_faq / get_policies (NIKDY z hlavy).')
  lines.push('- Pokud kontext stránky koliduje s něčím v konverzaci (např. user otevřel jinou motorku), zmiň to a doptej se: "vidím že koukáš na X, mluvíme o tomhle nebo o té předtím?".')
  lines.push('- Kontext je read-only; když user explicitně řekne "ne tuhle, jinou", přepni se a použij to, co řekl.')
  return lines.join('\n')
}

function buildSystemPrompt(lang: string, cfg: WebAgentConfig, company: CompanyInfo, fleet: FleetMoto[], pageCtx?: PageContext | null): string {
  // Jazyk je adaptivní — model VŽDY odpovídá ve stejném jazyce, jakým píše uživatel.
  // `lang` je jen hint z prohlížeče (UI jazyk webu) pro úvodní zprávu.
  const langHint = (lang || 'cs').slice(0, 2)
  const langInstr = `JAZYK: Detekuj jazyk POSLEDNÍ uživatelské zprávy a odpovídej VÝHRADNĚ ve stejném jazyce. Pokud uživatel přepne jazyk uprostřed konverzace, přepni s ním. Hint UI jazyka: ${langHint}. Tento hint použij jen pro 1. zprávu, dál se řiď textem uživatele. Žádné překlady ani dvojjazyčné odpovědi — vyber jeden jazyk a v něm odpověz.`

  // Today header (Europe/Prague)
  const now = new Date()
  const fmt = new Intl.DateTimeFormat('cs-CZ', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    timeZone: 'Europe/Prague',
  })
  const fmtIso = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit',
  })
  const todayHuman = fmt.format(now)
  const todayIso = fmtIso.format(now)

  const persona = cfg.persona_name || 'Rezervační asistent MotoGo24'
  const userPrompt = (cfg.system_prompt || '').trim()
  const tone = TONE_DESC[cfg.tone || 'concise'] || TONE_DESC.concise

  let parts: string[] = []
  const companyAddr = company.address || 'Mezná 9, 393 01 Pelhřimov'
  const companyName = company.name || 'MotoGo24'
  parts.push(`DNES JE ${todayHuman} (ISO ${todayIso}, časová zóna Europe/Prague). Tento údaj je zdroj pravdy o aktuálním datu — vždy ho použij místo vlastních odhadů.`)
  parts.push(`Jsi ${persona}. Pracuješ v půjčovně motorek ${companyName} (${companyAddr}, ČR).`)
  // Live snapshot kompletní flotily — injektujeme co nejvýš, aby model měl
  // autoritativní seznam motorek v kontextu od první odpovědi a NIKDY nemohl
  // halucinovat model, který nemáme, nebo tvrdit "nemáme" o modelu, který máme.
  parts.push(formatFleetSnapshot(fleet))
  // Kontext aktuální stránky — vyšší priorita než obecný brain,
  // protože uživatel mluví typicky o tom, na co se právě dívá.
  const pageCtxStr = formatPageContext(pageCtx)
  if (pageCtxStr) parts.push(pageCtxStr)
  if (userPrompt) parts.push(userPrompt)
  parts.push(tone)

  if (cfg.situations && cfg.situations.length > 0) {
    parts.push('SITUAČNÍ PRAVIDLA:\n' + cfg.situations.map((s) => `- ${s}`).join('\n'))
  }
  if (cfg.mustDo && cfg.mustDo.length > 0) {
    parts.push('VŽDY MUSÍ UDĚLAT:\n' + cfg.mustDo.map((s) => `- ${s}`).join('\n'))
  }
  if (cfg.forbidden && cfg.forbidden.length > 0) {
    parts.push('ZAKÁZÁNO:\n' + cfg.forbidden.map((s) => `- ${s}`).join('\n'))
  }
  parts.push(HARD_RULES_CS)
  parts.push(buildCompanyBrain(company))
  parts.push(MOTO_KNOWLEDGE_TIPS)
  if (cfg.knowledge_extra && cfg.knowledge_extra.trim()) {
    parts.push('AKTUÁLNÍ ZNALOSTI Z VELÍNU (sezonní akce, novinky, ad-hoc info — vyšší priorita než ostatní brain, pokud kolidují):\n' + cfg.knowledge_extra.trim())
  }
  const ctPhone = company.phone || '+420 774 256 271'
  const ctEmail = company.email || 'info@motogo24.cz'
  const ctWeb = company.web || 'https://motogo24.cz'
  parts.push(`KONTAKTY (DAVAT JEN NA VYZADANI ČLOVĚKA / SOS / PRÁVO): telefon ${ctPhone}, email ${ctEmail}, web ${ctWeb}.`)
  parts.push(langInstr)

  return parts.join('\n\n')
}

// ============================================================================
// Anthropic loop
// ============================================================================

async function runClaudeLoop(
  messages: Array<{ role: string; content: unknown }>,
  systemPrompt: string,
  maxTokens: number,
  maxIters = 6,
): Promise<{ reply: string; toolUses: Array<{ name: string; input: Record<string, unknown>; result: unknown }> }> {
  const toolUses: Array<{ name: string; input: Record<string, unknown>; result: unknown }> = []
  let iter = 0
  const apiMessages: Array<{ role: string; content: unknown }> = [...messages]

  while (iter < maxIters) {
    iter++
    // Retry až 3× na 429/5xx — Anthropic občas vrátí transientní chybu (overloaded_error apod.)
    let resp: Response | null = null
    let lastErr = ''
    for (let attempt = 0; attempt < 3; attempt++) {
      resp = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: ANTHROPIC_MODEL,
          max_tokens: maxTokens,
          system: systemPrompt,
          tools: PUBLIC_TOOLS,
          messages: apiMessages,
        }),
      })
      if (resp.ok) break
      lastErr = await resp.text()
      if (resp.status >= 500 || resp.status === 429) {
        // exponential backoff 300ms, 800ms
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1) ** 2))
        continue
      }
      break
    }
    if (!resp || !resp.ok) {
      throw new Error(`Anthropic API ${resp?.status || '?'}: ${lastErr}`)
    }
    const data = await resp.json() as { content: Array<Record<string, unknown>>; stop_reason: string }

    if (data.stop_reason === 'tool_use') {
      const toolBlocks = data.content.filter((b) => b.type === 'tool_use')
      apiMessages.push({ role: 'assistant', content: data.content })
      const toolResults: Array<Record<string, unknown>> = []
      for (const tb of toolBlocks) {
        const result = await execPublicTool(String(tb.name), tb.input as Record<string, unknown>)
        toolUses.push({ name: String(tb.name), input: tb.input as Record<string, unknown>, result })
        toolResults.push({
          type: 'tool_result', tool_use_id: tb.id,
          content: JSON.stringify(result),
        })
      }
      apiMessages.push({ role: 'user', content: toolResults })
      continue
    }

    const textBlocks = data.content.filter((b) => b.type === 'text')
    const reply = textBlocks.map((b) => String(b.text)).join('\n').trim()
    return { reply, toolUses }
  }
  return { reply: 'Hm, zacyklil jsem se. Zkus to prosím přeformulovat — co přesně potřebuješ?', toolUses }
}

// ============================================================================
// Server
// ============================================================================

serve(async (req) => {
  const startedAt = Date.now()
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Only POST' }), { status: 405, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown'
  const ua = req.headers.get('user-agent') || ''

  if (!rateLimit(`ip:${ip}`, 20, 60_000)) {
    return new Response(JSON.stringify({ error: 'Rate limit exceeded. Try again in a minute.' }), {
      status: 429, headers: { ...CORS, 'Content-Type': 'application/json', 'Retry-After': '60' },
    })
  }

  try {
    const body = await req.json()
    const messages = body.messages as Array<{ role: string; content: string }> | undefined
    const lang = (body.lang as string) || 'cs'

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: 'Missing messages' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }
    const recent = messages.slice(-20).filter((m) => m.role === 'user' || m.role === 'assistant')

    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: 'AI agent je dočasně nedostupný (chybí klíč). Zkus to za chvíli, nebo napiš dotaz formulářem na webu.' }), {
        status: 503, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const { cfg, company, fleet } = await loadConfig()
    if (cfg.enabled === false) {
      const offPhone = company.phone || '+420 774 256 271'
      const offEmail = company.email || 'info@motogo24.cz'
      return new Response(JSON.stringify({
        reply: `Asistent je momentálně vypnutý. Zavolejte prosím ${offPhone} nebo napište na ${offEmail}.`,
      }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    // page_context z widgetu — kde uživatel zrovna je (URL, typ stránky, moto_id, ...)
    const pageCtx = (body.page_context && typeof body.page_context === 'object')
      ? body.page_context as PageContext
      : null

    const systemPrompt = buildSystemPrompt(lang, cfg, company, fleet, pageCtx)
    const maxTokens = Math.min(Math.max(Number(cfg.max_tokens) || 800, 256), 4096)
    const { reply, toolUses } = await runClaudeLoop(recent, systemPrompt, maxTokens)

    const latency = Date.now() - startedAt
    let bookingCreated: string | undefined
    let bookingUrl: string | undefined
    for (const tu of toolUses) {
      const outcome = tu.name === 'create_booking_request' && (tu.result as Record<string, unknown>)?.success
        ? 'booking_created'
        : tu.name === 'redirect_to_booking' ? 'quote' : 'view'
      if (tu.name === 'create_booking_request') {
        const r = tu.result as Record<string, unknown>
        if (r?.success) {
          bookingCreated = String(r.booking_id || '')
          bookingUrl = String(r.payment_url || '')
        }
      }
      void logTraffic(tu.name, 200, latency, outcome, ip, ua, bookingCreated)
    }
    void logTraffic(null, 200, latency, bookingCreated ? 'booking_created' : 'view', ip, ua, bookingCreated)

    return new Response(JSON.stringify({ reply, tool_uses: toolUses, booking_url: bookingUrl }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    void logTraffic(null, 500, Date.now() - startedAt, 'error', ip, ua)
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
