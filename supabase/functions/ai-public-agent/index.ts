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
import { readManual } from '../_shared/manual-reader.ts'
import { getBundledManualText } from '../_shared/manual-texts/index.ts'
import { type CompanyInfo, type FleetMoto, type BranchRow, motoDisplayName, formatFleetSnapshot, formatBranchesSnapshot } from '../_shared/agent-knowledge/snapshots.ts'
import { loadKnowledgeBase, stripHtmlToText } from '../_shared/agent-knowledge/knowledge-base.ts'
import { buildCompanyBrain, MOTO_KNOWLEDGE_TIPS } from '../_shared/agent-knowledge/company-brain.ts'
import { HARD_RULES_CS } from '../_shared/agent-knowledge/hard-rules.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const ANTHROPIC_MODEL = 'claude-sonnet-4-6'
// Adaptivní myšlení (Sonnet 4.6) — model si sám určí, kdy a kolik přemýšlet. Zapnuto kvůli
// kvalitě odpovědí (lepší dodržování pravidel promptu, volání toolů před odpovědí, žádné
// protiřečení). Interleaved thinking se zapne automaticky, beta hlavička není potřeba.
const ANTHROPIC_THINKING = { type: 'adaptive' } as const

// Pokyn k práci s návodem — model má návod přečíst KOMPLETNĚ a odpovědět z něj.
// Když přesnou odpověď nenajde, NEODbývá to vyhýbavou „návod to nepopisuje", ale
// odvodí ji z příbuzné části a/nebo se zákazníka doptá a potvrdí.
const MANUAL_INSTRUCTION =
  'Toto je text návodu k TÉTO konkrétní motorce — přečti si ho CELÝ a pozorně. ' +
  'Odpověď hledej v celém návodu, ne jen podle přesných slov dotazu: kontrolky, ' +
  'symboly a funkce bývají popsané i jinými výrazy (např. „červený klíč" = ' +
  'imobilizér / bezpečnostní systém; „vykřičník v trojúhelníku" = obecná porucha). ' +
  'Když přesný pojem v návodu doslova není, odvoď odpověď z odpovídající části ' +
  '(kontrolky na palubní desce, symboly, startování, imobilizér). Pokud si ani po ' +
  'přečtení celého návodu nejsi jistý, CO PŘESNĚ zákazník vidí, NEODbývej to ' +
  'vyhýbavou odpovědí typu „návod to přímo nepopisuje" — polož mu 1–2 konkrétní ' +
  'upřesňující otázky; zda smíš požádat o fotku palubní desky, určuje sekce ' +
  'FOTKY OD ZÁKAZNÍKA. Když návod velí „okamžitě zastavte / vyhledejte servis", ' +
  'NEpřenášej to na zákazníka doslova — přelož to podle pravidla KALIBRACE ' +
  'ZÁVAŽNOSTI (uklidnit, jednoduché řešení, nahlásit na kontakt firmy = zákazník ' +
  'je krytý; zastavení jen u skutečně kritických příznaků). Vymyšlené technické ' +
  'údaje jsou zakázané; pokud informace v návodu opravdu není, řekni to jasně ' +
  'až PO doptání a nabídni kontakt na MotoGo24.'

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

// Uloží celou konverzaci do `ai_public_conversations` pro pozdější analýzu ve Velínu
// (Analýza → AI konverzace). Jeden řádek per session_id (upsert), aktualizuje se messages,
// last_activity_at, message_count, outcome a případné booking_id po vytvoření rezervace.
async function persistConversation(
  sessionId: string,
  messages: Array<{ role: string; content: string }>,
  lang: string,
  pageCtx: PageContext | null | undefined,
  ip: string,
  ua: string,
  outcome: string,
  bookingId?: string,
) {
  if (!sessionId) return
  try {
    const ipHash = await sha256Hex(ip + '|motogo24')
    const cleanMessages = messages
      .filter((m) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
      .map((m) => ({ role: m.role, content: String(m.content).slice(0, 8000) }))
    const row: Record<string, unknown> = {
      session_id: sessionId,
      lang: (lang || '').slice(0, 5) || null,
      page_context: pageCtx || null,
      messages: cleanMessages,
      message_count: cleanMessages.length,
      ip_hash: ipHash,
      user_agent: ua.slice(0, 500),
      outcome,
      last_activity_at: new Date().toISOString(),
    }
    if (bookingId) row.booking_id = bookingId
    await sb.from('ai_public_conversations')
      .upsert(row, { onConflict: 'session_id' })
  } catch { /* silent — konverzace se neztratí, jen ji nepoužijeme k analýze */ }
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


async function loadConfig(): Promise<{ cfg: WebAgentConfig; company: CompanyInfo; fleet: FleetMoto[]; branches: BranchRow[] }> {
  // Načti všechny relevantní app_settings klíče + KOMPLETNÍ flotilu paralelně.
  // company_info je zdroj pravdy o adrese / telefonu / emailu firmy (žádné hardcoded fakty).
  // Flotilu injektujeme do system promptu, aby model NIKDY nemohl halucinovat motorku,
  // kterou nemáme, ani tvrdit "nemáme" o motorce, kterou ve skutečnosti máme.
  // Kromě aktivních strojů se načítají i maintenance/unavailable (v servisu / dočasně mimo
  // nabídku) — jsou pořád součástí flotily a agent je NESMÍ popírat. Reálný incident: tool
  // správně řekl „choppery máme, jsou v servisu", ale snapshot je neobsahoval a pravidlo
  // „co v seznamu není, neexistuje" agenta dotlačilo k falešné omluvě, že je nemáme.
  // `retired` (vyřazené/prodané) se neinjektují — ty už flotila opravdu nemá.
  // Pobočky se injektují také — reálný incident 2026-08-03: prompt tvrdil paušálně
  // „výdej je samoobslužný a nonstop", ale Mezná je v DB type='obslužná' (předává obsluha).
  // Režim výdeje/vrácení proto NIKDY nesmí být v promptu natvrdo — bere se z tohoto snapshotu.
  try {
    const [cfgRes, ciRes, fleetRes, brRes] = await Promise.all([
      sb.from('app_settings').select('value').eq('key', 'ai_public_agent_config').maybeSingle(),
      sb.from('app_settings').select('value').eq('key', 'company_info').maybeSingle(),
      sb.from('motorcycles')
        // branches!branch_id (2026-09-20): bez pobočky u KONKRÉTNÍHO stroje nešlo splnit
        // pravidlo „režim výdeje urči podle typu té pobočky" — agent při více pobočkách hádal.
        .select('id, brand, model, category, license_required, status, power_kw, engine_cc, weight_kg, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, branch_id, branches!branch_id(name, type, is_open)')
        .in('status', ['active', 'maintenance', 'unavailable'])
        .order('brand', { ascending: true })
        .order('model', { ascending: true }),
      // select('*') SCHVÁLNĚ — výčet sloupců se zip/opening_hours (v DB `branches`
      // neexistují) shodil celý select (PostgREST 42703) → snapshot tvrdil „žádná
      // pobočka v DB" a get_branches (stejná chyba) to nezachránil. Reálný incident
      // 2026-08-05: agent zákazníkovi tvrdil, že seznam poboček je prázdný.
      sb.from('branches').select('*').order('name'),
    ])
    return {
      cfg: (cfgRes.data?.value as WebAgentConfig) || {},
      company: (ciRes.data?.value as CompanyInfo) || {},
      // Kus na TRVALE zavřené pobočce (is_open=false) agent nenabízí — pobočka
      // se zákazníkovi nezobrazuje a rezervovat tam nelze nic (DB `branch_is_closed`).
      fleet: (((fleetRes.data || []) as Array<Record<string, unknown>>)
        .filter((m) => (m.branches as Record<string, unknown> | null)?.is_open !== false) as unknown as FleetMoto[]),
      branches: (((brRes.data || []) as Array<Record<string, unknown>>)
        // Trvale zavřená pobočka (is_open=false) se zákazníkovi NENABÍZÍ — nelze
        // na ni nic zarezervovat v žádném termínu (DB `branch_is_closed`).
        .filter((b) => b.active !== false && b.is_open !== false) as unknown as BranchRow[]),
    }
  } catch {
    return { cfg: {}, company: {}, fleet: [], branches: [] }
  }
}



// ============================================================================
// Tools
// ============================================================================

const PUBLIC_TOOLS = [
  {
    name: 'search_motorcycles',
    description: 'Vyhledá motorky v MotoGo24 katalogu. Filtruj podle značky, modelu, kategorie, ŘP, výkonu, ceny nebo dostupnosti k danému datu. Když uživatel řekne "máš kawu/Kawasaki/BMW na pondělí" — ZAVOLEJ s `brand` a `available_on`, neinteroguj. **KOMPLETNÍ SPECS V ODPOVĚDI** (totožné s tím, co web zobrazuje na detailu motorky `/katalog/<id>`): id, name, brand, model, year, category, engine_cc (objem ccm), engine_type, power_kw, power_hp, torque_nm (točivý moment), weight_kg, seat_height_mm (výška sedla), top_speed_kmh (max. rychlost), fuel_tank_l (objem nádrže), fuel_consumption_l100km (spotřeba), fuel_type (Natural 95...), transmission (převodovka — text), drivetrain (chain/shaft/belt = řetěz/kardan/řemen), brake_type, has_abs, has_asc, seats_count (1 nebo 2), license (povinný ŘP), color, min_rental_days, max_rental_days, min_price_kc, ideal_usage (k čemu se hodí), description, features, suitable_for (komu je motorka vhodná), image_url, url (odkaz na detail). **Pro porovnání motorek (větší/menší/silnější/lehčí/dražší) používej VÝHRADNĚ tyto fieldy** — engine_cc, power_kw, weight_kg, seat_height_mm — nikdy ne modelové číslo v názvu. **Když je field null/prázdný**, v DB to chybí — NEIMPROVIZUJ, řekni „to v datech nemám" nebo „mrkni na detail [link]". **CENY V ODPOVĚDI:** `min_price_kc` = NEJLEVNĚJŠÍ den v týdnu pro orientaci; používej JEN když zákazník neuvedl termín. Pokud je v requestu `available_on` (jeden den) NEBO `available_from` + `available_to` (rozsah), result obsahuje navíc `requested_price_total_kc` (přesná cena za poptávaný termín), `requested_per_day` (rozpis po dnech) a u jednodenního dotazu `requested_price_kc_for_day` + `requested_weekday`. **TY POUŽIJ TUHLE PŘESNOU CENU**, ne `min_price_kc`. Když customer dostane „od 3367 Kč" místo „v neděli 3 667 Kč", je to pro něj matoucí a poškozující.',
    input_schema: {
      type: 'object',
      properties: {
        brand: { type: 'string', description: 'Značka, např. "Kawasaki", "BMW", "Yamaha", "Honda", "KTM", "Husqvarna", "Ducati", "Suzuki", "Triumph". Case-insensitive substring match.' },
        model_query: { type: 'string', description: 'Volnotextový dotaz na model (např. "Z 900", "MT-09", "S 1000", "Versys"). Použij kombinovaně s brand pro přesnost.' },
        category: { type: 'string', enum: ['cestovni', 'naked', 'supermoto', 'detske', 'scootery', 'sportovni', 'chopper', 'ostatni'], description: 'Kategorie dle DB. Skútry = "scootery". Sportovní stroje = "sportovni", choppery = "chopper", nezařazené (např. vozík) = "ostatni".' },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'], description: 'Skupina ŘP zákazníka. Vyšší skupina zahrnuje nižší (A→A2/A1/AM). "B" = běžný autořidičák — tool pro něj vrací i stroje A1 s automatickou převodovkou (typicky skútr 125), které v ČR držitel B smí řídit; u takového kusu vrátí `license_note`, kterou zákazníkovi sděl. "N" = bez ŘP — stroje, na které řidičské oprávnění NENÍ potřeba: dětské motorky I terénní stroje (pitbike/cross) pro dospělé; jezdí se s nimi výhradně mimo veřejné komunikace. Na dotaz „bez řidičáku / do terénu / na pole / pitbike" zavolej s license_group="N".' },
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
    description: 'Zkontroluje obsazené termíny pro konkrétní motorku. Vrací `today` (dnešní datum), `booked` (rezervace), `service_blocks` (plánované servisní odstávky s rozsahem `from`–`to` a příznakem `in_progress`) a `in_service_today`. Servisní blok blokuje motorku JEN ve svém rozsahu datumů — budoucí plánovaný servis NEZNAMENÁ, že je motorka v servisu teď. Použij PŘED kalkulací nebo rezervací a VŽDY, než o motorce tvrdíš, že je/bude v servisu.',
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
      properties: { topic: { type: 'string', description: 'Volitelně téma — cancellation, deposit, included, addons, delivery_pricing, foreign_travel, fuel, license_groups, documents, mileage, complaints, invoicing, late_return.' } },
    },
  },
  {
    name: 'get_legal_document',
    description: 'Vrátí PŘESNÉ aktuální znění oficiálních smluvních a právních dokumentů půjčovny ze šablon a webu: Všeobecné obchodní podmínky (VOP), nájemní/zápůjční smlouvu, předávací protokol, GDPR / zpracování osobních údajů a další dokumenty zveřejněné na webu. POUŽIJ VŽDY, když se zákazník ptá na konkrétní smluvní/právní detail, který není v get_policies/get_faq — např. jak se vyčísluje škoda a spoluúčast, odpovědnost za poškození, reklamace, zpracování osobních údajů, storno ujednání ve smlouvě, sankce. Bez parametru `document` vrátí seznam dostupných dokumentů (klíče + názvy); s `document` vrátí plné znění; s `query` vrátí relevantní úryvky. Cituj a parafrázuj VÝHRADNĚ to, co tool vrátí — nikdy si smluvní detail nedomýšlej. Když tool dokument/odpověď nenajde, přiznej to a odkaž na kontakt.',
    input_schema: {
      type: 'object',
      properties: {
        document: { type: 'string', description: 'Klíč dokumentu — `vop`, `rental_contract`, `handover_protocol`, `gdpr`, nebo slug webového dokumentu. Vynech pro seznam dostupných dokumentů.' },
        query: { type: 'string', description: 'Volitelně klíčová slova (např. "vyčíslení škody spoluúčast") — tool vrátí jen relevantní úseky textu místo celého dokumentu.' },
      },
    },
  },
  {
    name: 'get_motorcycle_manual',
    description: 'Otevře a přečte NÁVOD / uživatelskou příručku konkrétní motorky (nahrané PDF ze storage, nebo externí odkaz na stránku výrobce) a vrátí z něj text. POUŽIJ na technické „super-detaily", které NEJSOU v základních specs z `search_motorcycles` / snapshotu flotily: tlak v pneumatikách, druh a množství oleje, servisní intervaly, význam kontrolek na palubce, jak nastartovat / přepnout jízdní režim, pojistky, kapaliny, utahovací momenty, výbava v sadě nářadí apod. HIERARCHIE ZDROJŮ: základní parametry (kW, ccm, hmotnost, výška sedla, ABS, kategorie, ŘP) ber VŽDY z dat motorky (specs jsou nadřazené); návod slouží jen pro hlubší detaily, které ve specs nejsou. Když je `has_manual=true` u motorky ze `search_motorcycles`, návod existuje — zavolej tenhle tool s jejím `moto_id`. Vždy předej `query` (klíčová slova dotazu, např. "tlak pneumatiky zadní", "olej výměna množství", "kontrolka oranžová"), ať dostaneš relevantní úryvky. Cituj a parafrázuj VÝHRADNĚ to, co tool vrátí — nikdy si technický údaj z návodu nedomýšlej. Když návod není k dispozici nebo z něj nejde vytáhnout text, tool to oznámí — pak zákazníkovi rovnou řekni, že přesný údaj v návodu nemáš, a nabídni přímý odkaz na návod / kontakt.',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string', description: 'UUID motorky (z page_context, ze `search_motorcycles` nebo ze snapshotu flotily).' },
        query: { type: 'string', description: 'Klíčová slova technického dotazu — tool podle nich vrátí relevantní pasáže návodu místo celého textu.' },
      },
      required: ['moto_id'],
    },
  },
  {
    name: 'get_extras_catalog',
    description: 'Vrátí seznam příslušenství, které lze přiobjednat (top case, GPS, přistavení, atd.) s cenami + ceník výbavy/oblečení v `gear_pricing` (helma, bunda, kalhoty, rukavice, boty, kukla — pro řidiče i spolujezdce, vč. toho co je v ceně a co za příplatek).',
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
    description: 'Vytvoří skutečnou rezervaci v systému (status pending) a spustí platbu. NOVÝ FLOW (platba PŘED doklady): čísla dokladů (OP/pas, ŘP) ANI jejich fotky se v chatu vůbec NESBÍRAJÍ — zákazník je doplní až PO zaplacení přímo v rezervaci na webu / v appce. NIKDY tedy nevyžaduj číslo OP, číslo ŘP, platnost ŘP ani sken/foto dokladu; s doklady zákazníka v chatu NEOTRAVUJ. ABSOLUTNÍ PODMÍNKY VOLÁNÍ (musí být splněny VŠECHNY): (1) máš vyplněna VŠECHNA povinná pole bez výjimky (moto_id, start_date, end_date, name, email, phone, street, city, zip, date_of_birth, password); (1b) máš consent_vop=true a consent_gdpr=true, protože zákazník v chatu VÝSLOVNĚ odsouhlasil VOP a zpracování osobních údajů (GDPR) — bez obou souhlasů tool NIKDY nevol (na webu jsou to povinné checkboxy, tady je nahrazuje výslovné „souhlasím"); (2) v poslední uživatelské zprávě je EXPLICITNÍ potvrzení rezervace ("ano / rezervuj / potvrzuju / pošli platbu") jako reakce na tvůj kompletní souhrn (motorka, termín, vyzvednutí/vrácení, extras, cena) VČETNĚ potvrzení souhlasů; (3) ŽÁDNÉ pole nesmí být odhadnuté nebo "doplněné z hlavy" — pokud zákazník údaj neřekl, doptej se a tool nevol. PLATEBNÍ METODA: parametr `payment_method` — "card" = online kartou (Stripe, okamžité potvrzení, default), "qr" = QR kód / bankovní převod (zákazník dostane číslo účtu + VS + QR, splatnost 4 h, potvrzení ruční po připsání). Zeptej se zákazníka, kterou chce, PŘED voláním. Po zavolání s "card" NEPIŠ URL platební brány do zprávy — systém automaticky doplní tlačítko "Pokračovat k platbě". Po zavolání s "qr" tool vrátí platební údaje (účet, IBAN, VS, částka) — ty je přehledně zopakuj v textu a řekni, že stejné údaje + QR kód dostal i e-mailem.',
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
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'], description: 'VOLITELNÉ — Skupina ŘP zákazníka, pokud ji z konverzace znáš (pomáhá při výběru motorky). "N" = bez ŘP (dětské motorky a terénní stroje — jen mimo veřejné komunikace). NENÍ povinná pro vytvoření rezervace — zákazník ji spolu s čísly dokladů doplní až po platbě.' },
        payment_method: { type: 'string', enum: ['card', 'qr'], description: 'Zvolená platební metoda: "card" = online kartou (Stripe, okamžité potvrzení; default když neuvedeno), "qr" = QR kód / bankovní převod (číslo účtu + VS, splatnost 4 h, potvrzení ruční). Zeptej se zákazníka PŘED voláním, kterou preferuje.' },
        password: { type: 'string', description: 'POVINNÉ — Heslo (min. 8 znaků) pro správu rezervace a přihlášení do appky MotoGo24.' },
        date_of_birth: { type: 'string', description: 'POVINNÉ — Datum narození zákazníka ve formátu YYYY-MM-DD. Web ho vyžaduje; nájemce (držitel smlouvy) musí být 18+.' },
        consent_vop: { type: 'boolean', description: 'POVINNÉ — nastav true JEN když zákazník v chatu VÝSLOVNĚ potvrdil souhlas s Všeobecnými obchodními podmínkami (VOP) a nájemní smlouvou. Jinak tool nevol a souhlas si nejdřív vyžádej.' },
        consent_gdpr: { type: 'boolean', description: 'POVINNÉ — nastav true JEN když zákazník VÝSLOVNĚ potvrdil souhlas se zpracováním osobních údajů (GDPR). Jinak tool nevol.' },
        marketing_consent: { type: 'boolean', description: 'VOLITELNÉ — souhlas s marketingem (newsletter/akce). true jen když zákazník souhlasil, jinak false. Nevynucuj.' },
        consent_photo: { type: 'boolean', description: 'VOLITELNÉ — souhlas s fotografováním dokladů (potřebné k ověření identity). Default true; nastav false jen když zákazník výslovně odmítne.' },
        promo_code: { type: 'string' },
        note: { type: 'string' },
        pickup_time: { type: 'string', description: 'POVINNÉ — Čas vyzvednutí HH:MM (u všech poboček — řídí slevu za pozdní vyzvednutí). Pokud zákazník neřekne, default 10:00.' },
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
        passenger_pants_size: { type: 'string', description: 'Velikost kalhot spolujezdce.' },
        passenger_boots_size: { type: 'string', description: 'Velikost bot spolujezdce.' },
        passenger_gloves_size: { type: 'string', description: 'Velikost rukavic spolujezdce.' },
      },
      required: ['moto_id', 'start_date', 'end_date', 'name', 'email', 'phone',
                 'street', 'city', 'zip', 'date_of_birth', 'password',
                 'consent_vop', 'consent_gdpr'],
    },
  },
  {
    name: 'find_my_booking',
    description: 'Načte stav existující rezervace pro úpravu. VOLEJ JAKO PRVNÍ KROK kdykoli zákazník chce upravit existující rezervaci. DVĚ ÚROVNĚ (viz bod 18): LIGHT = předáš JEN `booking_id` (bez kontaktu a hesla) → server vrátí stav BEZ osobních údajů; používej jako default start, dokud nevíš, že změna něco stojí. FULL = předáš `booking_id` + `contact` + `password_last4` → plné ověření, vyžádej ho teprve když server u změny vrátí `full_verification_required` (změna za peníze). Když vrátí error verification_failed nebo password_check_unavailable, pokračuj podle bodu 18 — NIKDY se nesnaž ověření obejít.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string', description: 'UUID rezervace, typicky z potvrzovacího emailu zákazníka.' },
        contact: { type: 'string', description: 'VOLITELNÉ — vyplň až ve FULL ověření (změna za peníze). Email NEBO telefon, na který přišlo potvrzení (email = obsahuje @, jinak CZ telefon 9 číslic).' },
        password_last4: { type: 'string', description: 'VOLITELNÉ — vyplň až ve FULL ověření (změna za peníze). POSLEDNÍ 4 znaky hesla (string). NIKDY si je nevymýšlej. U LIGHT (jen číslo rezervace) nech prázdné — server vrátí stav bez PII.' },
      },
      required: ['booking_id'],
    },
  },
  {
    name: 'lookup_my_bookings',
    description: 'READ-ONLY ověření rezervací zákazníka podle E-MAILU NEBO TELEFONU — BEZ HESLA. Použij VŽDY, když zákazník chce ověřit stav rezervace a NEMÁ číslo `#XXXXXXXX`, ale dá e-mail nebo telefon, na který rezervoval (typicky „nemám číslo, ale mail je …", „už mi přišla rezervace", „je to zaplacené?"). Vrací `bookings[]`: booking_number (`#XXXXXXXX`), booking_id (plné UUID pro další tooly), status (pending/reserved/active/completed/cancelled), payment_status (unpaid/paid/partial_refund/refund_pending/refunded), booking_source (web/app), start_date, end_date, total_price, moto_name, pickup_method, created_at, confirmed_at, abandoned_email_sent + reserved_email_sent (bool) a `emails` = přehled reálně odeslaných mailů (template_slug, subject, status, sent_at). NEOBSAHUJE citlivá data (číslo dokladu, ŘP, heslo, celé bydliště). SLOUŽÍ JEN KE ČTENÍ — úprava rezervace za peníze dál vyžaduje heslo (find_my_booking FULL + apply_booking_change). Ověření zaplacení: podívej se na `payment_status` a jestli je mezi `emails` slug `booking_reserved`/`web_booking_reserved` (chodí AŽ po platbě) vs. jen `booking_abandoned` (Nedokončená rezervace = NEzaplaceno). NIKDY netvrď stav rezervace bez zavolání tohoto toolu nebo find_my_booking.',
    input_schema: {
      type: 'object',
      properties: {
        contact: { type: 'string', description: 'E-mail (obsahuje @) NEBO telefon (CZ = 9 číslic, +420 prefix OK), na který zákazník rezervoval.' },
      },
      required: ['contact'],
    },
  },
  {
    name: 'get_booking_emails',
    description: 'READ-ONLY — vrátí, které e-maily reálně odešly k DANÉ rezervaci a kdy (BEZ HESLA). Vstup: číslo rezervace `#XXXXXXXX`, plné UUID, nebo odkaz „Upravit rezervaci". Vrací status, payment_status a `emails[]` (template_slug, subject, status, sent_at) od nejnovějšího. POUŽIJ k ověření tvrzení „přišel mi mail / je zaplaceno" a k určení FÁZE (viz mapa mailů, bod 28): `invoice_payment_receipt`/`web_invoice_payment_receipt` = ZAPLACENO (doklad o platbě); `web_booking_reserved`/`booking_reserved` = potvrzení rezervace AŽ po doplnění dokladů (kompletní); `booking_abandoned`/`web_booking_abandoned` = NEzaplaceno (čeká na platbu); `booking_qr_payment` = zvolen QR/převod, ČEKÁ na připsání (ještě NEzaplaceno); `booking_missing_docs` = zaplaceno, ale chybí doklady. NIKDY netvrď, co odešlo nebo že je zaplaceno, bez zavolání tohoto toolu nebo lookup_my_bookings/find_my_booking.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string', description: 'Číslo rezervace `#XXXXXXXX`, plné UUID, nebo odkaz „Upravit rezervaci".' },
      },
      required: ['booking_id'],
    },
  },
  {
    name: 'get_booking_readiness',
    description: 'READ-ONLY — připravenost rezervace k VYZVEDNUTÍ (bez hesla, JEN STAV, NIKDY samotné kódy ani čísla dokladů). Vstup: číslo rezervace `#XXXXXXXX` nebo plné UUID. POUŽIJ na dotazy „jak se dostanu k motorce", „nepřišly mi přístupové kódy", „ověřili jste mi doklady", „co mi ještě chybí před vyzvednutím". Vrací: `docs_ok` (bool), `docs_missing_reason` (text nebo null — např. „Chybí ŘP"), `codes_issued` (bool = kódy aktivní A odeslané), `codes_active`, `codes_sent`, `codes_withheld_reason` (typicky „Chybí doklady…"), `status`, `payment_status`. Logika k vysvětlení zákazníkovi: kódy se vydají, až je (a) zaplaceno a (b) nahrané doklady; když `docs_ok=false`, řekni KONKRÉTNĚ co chybí a naveď na nahrání (Mindee/QR, bod 29). NIKDY netvrď, že kódy dorazily/nedorazily ani že doklady jsou OK, bez zavolání tohoto toolu.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string', description: 'Číslo rezervace `#XXXXXXXX`, plné UUID, nebo odkaz „Upravit rezervaci".' },
      },
      required: ['booking_id'],
    },
  },
  {
    name: 'get_order_status',
    description: 'READ-ONLY — stav E-SHOP objednávky nebo POUKAZU (voucheru) podle e-mailu NEBO čísla objednávky (bez hesla, PII-minimal). POUŽIJ na „kde mám objednávku/zboží", „dorazí mi to", „nedorazil mi poukaz/voucher". Vrací `orders[]` (order_number, status [new/confirmed/processing/shipped/delivered/cancelled/returned/refunded], payment_status, total, tracking_number, created_at) a `vouchers[]` (code_masked [jen první 2 znaky + ****, NIKDY celý kód], status [active/redeemed/expired/cancelled], amount, valid_until, source). NEvrací celé číslo voucheru ani adresu. Pro tracking/zboží použij `tracking_number`. NIKDY netvrď stav objednávky bez zavolání tohoto toolu.',
    input_schema: {
      type: 'object',
      properties: {
        contact: { type: 'string', description: 'E-mail (obsahuje @) NEBO číslo objednávky (např. „OBJ-2026-0007"), případně kód voucheru.' },
      },
      required: ['contact'],
    },
  },
  {
    name: 'preview_booking_change',
    description: 'Spočítá NÁHLED ceny / refundu / doplatku po požadované změně rezervace BEZ jejího provedení (dry-run). Použij PŘED apply_booking_change, ať můžeš zákazníkovi ukázat přesný breakdown a získat potvrzení. Identita se ověřuje stejně jako u find_my_booking — agent nepředává žádné odhadnuté údaje. Volej s jedním nebo více parametrů změny (start_date, end_date, moto_id, pickup/return method+address+fee). Tool vrátí breakdown {dates_diff, moto_diff, pickup_fee_diff, return_fee_diff, storno_pct} + payment_required + refund_amount + net_diff.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string' },
        contact: { type: 'string', description: 'Email nebo telefon (totožně jako u find_my_booking).' },
        password_last4: { type: 'string' },
        new_start_date: { type: 'string', description: 'YYYY-MM-DD nebo nech prázdné pokud beze změny.' },
        new_end_date: { type: 'string', description: 'YYYY-MM-DD nebo nech prázdné pokud beze změny.' },
        new_moto_id: { type: 'string', description: 'UUID nové motorky pokud chce vyměnit, jinak prázdné.' },
        new_pickup_method: { type: 'string', description: 'self / delivery — pokud mění způsob vyzvednutí.' },
        new_pickup_address: { type: 'string' },
        new_pickup_fee: { type: 'number', description: 'Kč za přistavení k zákazníkovi (pokud delivery). 0 pokud self.' },
        new_return_method: { type: 'string', description: 'self / delivery — pokud mění způsob vrácení.' },
        new_return_address: { type: 'string' },
        new_return_fee: { type: 'number', description: 'Kč za vyzvednutí od zákazníka (pokud delivery). 0 pokud self.' },
      },
      required: ['booking_id'],
    },
  },
  {
    name: 'apply_booking_change',
    description: 'PROVEDE změnu rezervace. VOLEJ JEN: (a) po preview_booking_change, (b) když zákazník v poslední zprávě EXPLICITNĚ potvrdil souhrn změny ("ano / uprav / potvrzuju") VČETNĚ refundu nebo doplatku, který jsi mu ukázal, (c) když změna nevyžaduje doplatek (payment_required=false v preview) — pokud doplatek vyžaduje, NEZAVOLEJ tento tool, místo toho zákazníka pošli na web Moje rezervace, kde proběhne Stripe Checkout pro doplatek (limit anonymního agenta). Po úspěšném zavolání tool vrátí success + new_total + případnou refund_amount, kterou systém odešle Stripe refundem na původní kartu. Limit: max 3 reálné změny / den / rezervaci.',
    input_schema: {
      type: 'object',
      properties: {
        booking_id: { type: 'string' },
        contact: { type: 'string' },
        password_last4: { type: 'string' },
        new_start_date: { type: 'string' },
        new_end_date: { type: 'string' },
        new_moto_id: { type: 'string' },
        new_pickup_method: { type: 'string' },
        new_pickup_address: { type: 'string' },
        new_pickup_fee: { type: 'number' },
        new_return_method: { type: 'string' },
        new_return_address: { type: 'string' },
        new_return_fee: { type: 'number' },
        reason: { type: 'string', description: 'Krátký důvod změny (např. "kratší pobyt", "jiný den", "změna adresy").' },
      },
      required: ['booking_id'],
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

// Normalizuje „číslo rezervace" od zákazníka na plné UUID. Zákazník v potvrzovacím
// mailu (i v jeho předmětu) vidí KRÁTKOU referenci `#XXXXXXXX` = POSLEDNÍCH 8 znaků UUID
// (booking_number = id.slice(-8).toUpperCase()), NE první blok. Plné UUID je jen v odkazu
// „Upravit rezervaci" (?id=…). Přijmeme proto obojí: plné UUID (i bez pomlček / z celého
// odkazu) bereme rovnou; 8znakovou hex referenci přeložíme přes RPC resolve_booking_ref.
async function resolveBookingRef(raw: unknown): Promise<{ id?: string; error?: string }> {
  const s = String(raw ?? '').trim()
  if (!s) return { error: 'missing_inputs' }
  // plné UUID kdekoli ve vstupu (klidně celý ?id=… odkaz) → ber rovnou, bez DB
  const m = s.match(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/)
  if (m) return { id: m[0].toLowerCase() }
  const { data, error } = await sb.rpc('resolve_booking_ref', { p_ref: s })
  if (error) return { error: error.message }
  const d = (data || {}) as { success?: boolean; booking_id?: string; error?: string }
  if (d.success && d.booking_id) return { id: d.booking_id }
  return { error: d.error || 'not_found' }
}

async function execPublicTool(name: string, args: Record<string, unknown>, lang: string = 'cs'): Promise<unknown> {
  switch (name) {
    case 'search_motorcycles': {
      let q = sb.from('motorcycles').select('id, model, brand, year, category, engine_cc, engine_type, power_kw, power_hp, torque_nm, weight_kg, seat_height_mm, top_speed_kmh, fuel_tank_l, fuel_consumption_l100km, fuel_type, transmission, drivetrain, brake_type, has_abs, has_asc, seats_count, license_required, color, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, ideal_usage, description, features, suitable_for, min_rental_days, max_rental_days, image_url, manual_url, manual_external_url, branch_id, branches!branch_id(name, address, city, type, phone, is_open)')
        .eq('status', 'active').order('model')
      if (args.category) q = q.ilike('category', `%${args.category}%`)
      // ŘP je hierarchické: kdo má vyšší skupinu, smí legálně řídit i nižší
      // (AM < A1 < A2 < A). Zákazníkovi s „A" proto nabídneme i A2/A1/AM stroje
      // (často vhodnější — např. návrat do sedla), ne jen přesně „A". N ponecháme
      // přesně. „B" (autořidičák): vlastní B/AM stroje + A1 s AUTOMATICKOU převodovkou
      // (typicky skútr 125) — ty v ČR držitel B řídit smí (viz pravidla ŘP v promptu);
      // manuální A1 se pro B odfiltruje níže v JS. Výkonový strop řeší kw_max výše.
      const RIDEABLE: Record<string, string[]> = {
        A: ['A', 'A2', 'A1', 'AM'],
        A2: ['A2', 'A1', 'AM'],
        A1: ['A1', 'AM'],
        AM: ['AM'],
        B: ['B', 'AM', 'A1'],
      }
      const licGroup = args.license_group ? String(args.license_group) : ''
      const licAllowed = licGroup ? (RIDEABLE[licGroup] || [licGroup]) : null
      if (licAllowed) q = q.in('license_required', licAllowed)
      if (args.kw_min) q = q.gte('power_kw', Number(args.kw_min))
      if (args.kw_max) q = q.lte('power_kw', Number(args.kw_max))
      if (args.brand) q = q.ilike('brand', `%${String(args.brand)}%`)
      if (args.model_query) q = q.ilike('model', `%${String(args.model_query)}%`)
      const { data } = await q
      let result = data || []
      // Kus na TRVALE zavřené pobočce (is_open=false) se nenabízí — pobočku
      // zákazník nevidí a rezervovat tam nelze nic (DB `branch_is_closed`).
      result = result.filter((m: Record<string, unknown>) =>
        (m.branches as Record<string, unknown> | null)?.is_open !== false)
      // Skupina B: z přibraných A1 strojů nech jen ty s automatickou převodovkou (skútry) —
      // jen ty smí držitel B v ČR řídit. Manuální A1 pro B nenabízíme.
      const isAutomatic = (m: Record<string, unknown>) =>
        /scoot/i.test(String(m.category || '')) || /automat|cvt|bezstup/i.test(`${m.transmission || ''} ${m.engine_type || ''}`)
      if (licGroup === 'B') {
        result = result.filter((m: Record<string, unknown>) => m.license_required !== 'A1' || isAutomatic(m))
      }
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
      // Jména strojů, které filtrům vyhověly, ale v termínu jsou OBSAZENÉ — agent pak umí říct
      // „máme, ale v tom termínu je obsazený" místo nepravdivého „nemáme". Kolize se SERVISNÍM
      // blokem se hlásí zvlášť VČETNĚ datumů from–to: plánovaný servis blokuje jen svůj rozsah
      // a agent nesmí tvrdit „je v servisu", když tam stroj v požadovaný den reálně není.
      let bookedInWindow: string[] = []
      const serviceInWindow: Array<{ name: string; service_from: string; service_to: string }> = []
      if (availFrom && availTo) {
        const checks = await Promise.all(result.map(async (m: Record<string, unknown>) => {
          const { data: booked } = await sb.rpc('get_moto_booked_dates', { p_moto_id: m.id })
          const ranges = (booked || []) as Array<{ start_date: string; end_date: string; status?: string }>
          const conflicts = ranges.filter((r) => !(availTo < r.start_date || availFrom > r.end_date))
          return { moto: m, conflicts }
        }))
        for (const c of checks) {
          if (c.conflicts.length === 0) continue
          const name = motoDisplayName((c.moto as Record<string, unknown>).brand as string | null, (c.moto as Record<string, unknown>).model as string | null)
          const svc = c.conflicts.find((r) => r.status === 'service')
          if (svc && c.conflicts.every((r) => r.status === 'service')) {
            serviceInWindow.push({ name, service_from: svc.start_date, service_to: svc.end_date })
          } else {
            bookedInWindow.push(name)
          }
        }
        result = checks.filter((c) => c.conflicts.length === 0).map((c) => c.moto as Record<string, unknown>)
      }

      // Nic nevyhovělo, ale hledala se konkrétní kategorie/značka/model → zjisti, jestli takový
      // stroj ve flotile EXISTUJE, jen právě není v nabídce (status maintenance/unavailable). Agent
      // pak řekne „máme, ale momentálně je v servisu" místo nepravdivého „nemáme vůbec".
      // POZOR: `retired` sem NESMÍ — vyřazený stroj už ve flotile NENÍ (prodaný/odepsaný); hlásit ho
      // jako „v servisu" je dezinformace (reálný incident: agent sliboval choppery, které firma nemá).
      let outOfService: Array<Record<string, unknown>> = []
      if (result.length === 0 && bookedInWindow.length === 0 && serviceInWindow.length === 0 && (args.category || args.brand || args.model_query)) {
        let q2 = sb.from('motorcycles').select('brand, model, status, category, license_required').in('status', ['maintenance', 'unavailable'])
        if (args.category) q2 = q2.ilike('category', `%${args.category}%`)
        if (args.brand) q2 = q2.ilike('brand', `%${String(args.brand)}%`)
        if (args.model_query) q2 = q2.ilike('model', `%${String(args.model_query)}%`)
        if (licAllowed) q2 = q2.in('license_required', licAllowed)
        const { data: d2 } = await q2
        outOfService = ((d2 || []) as Array<Record<string, unknown>>)
          .filter((m) => licGroup !== 'B' || m.license_required !== 'A1' || isAutomatic(m))
          .map((m) => ({
            name: motoDisplayName(m.brand as string | null, m.model as string | null),
            status: m.status,
            status_note: m.status === 'maintenance' ? 'právě v servisu (aktuální stav)' : 'dočasně mimo nabídku',
            category: m.category, license: m.license_required,
          }))
      }

      const minPriceFor = (m: Record<string, unknown>): number => {
        const ps = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
          .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)
        return ps.length > 0 ? Math.min(...ps) : 0
      }

      const dayKeys = ['sun','mon','tue','wed','thu','fri','sat']
      const dayLabels = ['neděle','pondělí','úterý','středa','čtvrtek','pátek','sobota']
      // Když je dotaz vázaný na termín (konkrétní den nebo rozsah), spočítáme PŘESNOU cenu pro ten termín
      // — agent NESMÍ použít „od X Kč/den" když má zákazník v dotazu konkrétní datum.
      const priceForRange = (m: Record<string, unknown>, fromIso: string, toIso: string): { total: number; days: Array<{ date: string; weekday: string; price_kc: number }>; missing_days: string[] } => {
        const start = new Date(fromIso), end = new Date(toIso)
        const days: Array<{ date: string; weekday: string; price_kc: number }> = []
        const missing: string[] = []
        let total = 0
        if (isNaN(start.getTime()) || isNaN(end.getTime()) || end < start) return { total: 0, days, missing_days: [fromIso] }
        const d = new Date(start)
        while (d <= end) {
          const dn = dayKeys[d.getDay()]
          const raw = (m as Record<string, unknown>)['price_' + dn]
          const price = raw == null ? null : Number(raw)
          const iso = d.toISOString().slice(0, 10)
          if (price == null || !isFinite(price) || price <= 0) {
            missing.push(iso)
          } else {
            total += price
            days.push({ date: iso, weekday: dayLabels[d.getDay()], price_kc: price })
          }
          d.setDate(d.getDate() + 1)
        }
        return { total, days, missing_days: missing }
      }

      return {
        count: result.length,
        availability_window: availFrom ? { from: availFrom, to: availTo } : null,
        // Stroje vyhovující filtrům, ale OBSAZENÉ v požadovaném termínu (jen když nic volného nezbylo).
        booked_in_window: (result.length === 0 && bookedInWindow.length > 0) ? bookedInWindow : undefined,
        // Stroje blokované v POŽADOVANÉM termínu plánovaným servisem — s datumy from–to.
        service_in_window: (result.length === 0 && serviceInWindow.length > 0) ? serviceInWindow : undefined,
        // Stroje, které ve flotile existují, ale nejsou právě v nabídce (servis/mimo provoz).
        out_of_service_matches: outOfService.length > 0 ? outOfService : undefined,
        notice: result.length === 0
          ? (bookedInWindow.length > 0
            ? 'Stroje v `booked_in_window` MÁME a filtrům vyhovují, ale v požadovaném termínu jsou OBSAZENÉ. Řekni to zákazníkovi přesně takto a nabídni jiný termín (get_availability ukáže obsazené rozsahy). NIKDY netvrď, že takový stroj nemáme.'
            : (serviceInWindow.length > 0
              ? 'Stroje v `service_in_window` MÁME, ale v POŽADOVANÉM termínu mají plánovaný servis (rozsah `service_from`–`service_to`). Řekni to zákazníkovi S TĚMITO DATUMY („v termínu od–do má plánovaný servis") a nabídni termín mimo tento rozsah nebo alternativu. Mimo uvedený rozsah je stroj normálně dostupný — NIKDY netvrď, že „je v servisu" teď, když servis teprve proběhne v budoucnu.'
              : (outOfService.length > 0
                ? 'Stroje v `out_of_service_matches` ve flotile EXISTUJÍ, ale právě NEJSOU v nabídce — použij přesně důvod ze `status_note` každého stroje („právě v servisu" vs. „dočasně mimo nabídku") a nabídni alternativu nebo pozdější termín. NIKDY netvrď, že takový stroj vůbec nemáme. Stroje mimo tento seznam a mimo aktivní flotilu NEEXISTUJÍ — žádné jiné modely si nedomýšlej.'
                : undefined)))
          : undefined,
        motorcycles: result.slice(0, 20).map((m: Record<string, unknown>) => {
          const base: Record<string, unknown> = {
            id: m.id,
            name: motoDisplayName(m.brand as string | null, m.model as string | null),
            brand: m.brand,
            model: m.model,
            year: m.year,
            category: m.category,
            // Motor + výkon
            engine_cc: m.engine_cc,
            engine_type: m.engine_type,
            power_kw: m.power_kw,
            power_hp: m.power_hp,
            torque_nm: m.torque_nm,
            // Geometrie / hmotnost
            weight_kg: m.weight_kg,
            seat_height_mm: m.seat_height_mm,
            // Provoz
            top_speed_kmh: m.top_speed_kmh,
            fuel_tank_l: m.fuel_tank_l,
            fuel_consumption_l100km: m.fuel_consumption_l100km,
            fuel_type: m.fuel_type,
            transmission: m.transmission,
            drivetrain: m.drivetrain,
            brake_type: m.brake_type,
            has_abs: m.has_abs,
            has_asc: m.has_asc,
            seats_count: m.seats_count,
            // Pronájem
            license: m.license_required,
            color: m.color,
            min_rental_days: m.min_rental_days,
            max_rental_days: m.max_rental_days,
            min_price_kc: minPriceFor(m),
            // Návod k motorce existuje? (PDF má přednost před externím odkazem.) Když true, pro
            // technické super-detaily nad rámec těchto specs zavolej `get_motorcycle_manual` s moto_id.
            has_manual: !!(String(m.manual_url || '').trim() || String(m.manual_external_url || '').trim()),
            // Popisy (pokud zákazník chce „k čemu se hodí")
            ideal_usage: m.ideal_usage,
            description: typeof m.description === 'string' ? String(m.description).slice(0, 500) : null,
            features: m.features,
            suitable_for: typeof m.suitable_for === 'string' ? String(m.suitable_for).slice(0, 500) : null,
            image_url: m.image_url,
            url: `https://www.motogo24.cz/katalog/${m.id}`,
          }
          if (licGroup === 'B' && m.license_required === 'A1') {
            base.license_note = 'Stroj skupiny A1 s automatickou převodovkou — v ČR ho smí řídit i držitel ŘP B (dle zákonných podmínek délky držení ŘP). Zákazníkovi to výslovně řekni a podmínky ať si ověří dle svého ŘP.'
          }
          // Pokud je v dotazu konkrétní termín, doplň PŘESNOU cenu pro ten termín — agent ji použije
          // místo min_price_kc. min_price_kc je jen orientační (nejlevnější den v týdnu) a NESMÍ se
          // prezentovat zákazníkovi, který se ptá na konkrétní den.
          if (availFrom && availTo) {
            const pr = priceForRange(m, availFrom, availTo)
            if (pr.missing_days.length === 0 && pr.days.length > 0) {
              base.requested_window = { from: availFrom, to: availTo, days: pr.days.length }
              base.requested_price_total_kc = pr.total
              base.requested_per_day = pr.days
              if (pr.days.length === 1) {
                base.requested_price_kc_for_day = pr.days[0].price_kc
                base.requested_weekday = pr.days[0].weekday
              }
            } else if (pr.missing_days.length > 0) {
              base.requested_price_unknown = true
              base.requested_missing_days = pr.missing_days
            }
          }
          return base
        }),
      }
    }
    case 'get_availability': {
      const { data } = await sb.rpc('get_moto_booked_dates', { p_moto_id: args.moto_id })
      const rows = (data || []) as Array<{ start_date: string; end_date: string; status?: string; created_at?: string }>
      // Servisní bloky se oddělují od rezervací a posuzují se PODLE DATUMŮ vůči dnešku
      // (Europe/Prague). Plánovaný servis (např. zimní) blokuje VÝHRADNĚ svůj rozsah —
      // agent NESMÍ tvrdit „motorka je v servisu", když tam dnes / v požadovaný den není.
      const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
      const serviceRows = rows.filter((r) => r.status === 'service')
      const bookedRows = rows.filter((r) => r.status !== 'service')
      const inServiceToday = serviceRows.some((r) => r.start_date <= today && today <= r.end_date)
      return {
        today,
        booked: bookedRows,
        service_blocks: serviceRows.map((r) => ({ from: r.start_date, to: r.end_date, in_progress: r.start_date <= today && today <= r.end_date })),
        in_service_today: inServiceToday,
        notice: serviceRows.length > 0
          ? 'PRÁCE S DATUMY (POVINNÉ): servisní blok v `service_blocks` blokuje motorku VÝHRADNĚ v rozsahu `from`–`to` — mimo něj je motorka normálně dostupná. „Motorka je v servisu" smíš říct JEN když `in_service_today`=true (dotaz na dnešek), nebo když zákazníkem požadovaný den spadá DO rozsahu bloku. Budoucí plánovaný servis (např. zimní) NIKDY nepopisuj jako „je v servisu" — správně: „od <from> do <to> má plánovaný servis, do té doby je normálně k dispozici".'
          : undefined,
      }
    }
    case 'calculate_price': {
      const { moto_id, start_date, end_date, promo_code } = args
      const { data: moto } = await sb.from('motorcycles')
        .select('model, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, min_rental_days, max_rental_days')
        .eq('id', moto_id).maybeSingle()
      if (!moto) return { error: 'Motorka nenalezena' }
      const days = ['sun','mon','tue','wed','thu','fri','sat']
      const start = new Date(String(start_date)), end = new Date(String(end_date))
      if (isNaN(start.getTime()) || isNaN(end.getTime())) return { error: 'Neplatné datum' }
      if (end < start) return { error: 'Konec musí být po začátku' }

      const motoRow = moto as Record<string, unknown>
      const dayLabelsCs = ['neděle', 'pondělí', 'úterý', 'středa', 'čtvrtek', 'pátek', 'sobota']
      let total = 0, count = 0
      const missingDays: string[] = []
      const breakdown: Array<{ date: string; weekday: string; price_kc: number }> = []
      const d = new Date(start)
      while (d <= end) {
        const dn = days[d.getDay()]
        const raw = motoRow['price_' + dn]
        const price = raw == null ? null : Number(raw)
        const iso = d.toISOString().slice(0, 10)
        const weekday = dayLabelsCs[d.getDay()]
        if (price == null || !isFinite(price) || price <= 0) {
          missingDays.push(iso)
        } else {
          total += price
          breakdown.push({ date: iso, weekday, price_kc: price })
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
      // Vynucení min/max délky pronájmu z dat motorky (dřív hlídal jen text promptu — tool
      // spočítal cenu i pro délku mimo limity a agent ji sebejistě odprezentoval).
      const minDays = Number(motoRow.min_rental_days || 0)
      const maxDays = Number(motoRow.max_rental_days || 0)
      if (minDays > 0 && count < minDays) {
        return { error: `Tato motorka má minimální délku pronájmu ${minDays} ${minDays === 1 ? 'den' : minDays < 5 ? 'dny' : 'dní'} — požadovaný termín má jen ${count}. Nabídni zákazníkovi prodloužení termínu, nebo jinou motorku bez tohoto limitu.`, min_rental_days: minDays, requested_days: count }
      }
      if (maxDays > 0 && count > maxDays) {
        return { error: `Tato motorka má maximální délku pronájmu ${maxDays} dní — požadovaný termín má ${count}. Nabídni zkrácení termínu nebo jinou motorku.`, max_rental_days: maxDays, requested_days: count }
      }
      let discount = 0
      let promoApplied: { type: string; value: number; kind?: string } | null = null
      if (promo_code) {
        const { data: pr } = await sb.rpc('validate_promo_code', { p_code: promo_code })
        if (pr && (pr as Record<string, unknown>).valid) {
          const p = pr as Record<string, unknown>
          const v = Number(p.value)
          if (p.type === 'percent') discount = Math.round(total * v / 100)
          else discount = v
          promoApplied = { type: String(p.type), value: v, kind: 'promo' }
        } else {
          // Není to promo kód — zkus VOUCHER (dárkový poukaz), stejně jako validate_promo_or_voucher.
          // Dřív kalkulace vouchery ignorovala → agent voucher „ověřil", ale do ceny nezapočítal.
          const { data: vch } = await sb.rpc('validate_voucher_code', { p_code: promo_code })
          if (vch && (vch as Record<string, unknown>).valid) {
            const p = vch as Record<string, unknown>
            const v = Number(p.amount ?? p.value ?? 0)
            if (v > 0) {
              discount = Math.min(v, total)
              promoApplied = { type: 'amount', value: v, kind: 'voucher' }
            }
          }
        }
      }
      return {
        days: count,
        per_day_breakdown: breakdown,
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
      // Jediný zdroj pravdy: tabulka `faq_items` (admin edituje z Velínu → CMS → Texty webu → Časté dotazy;
      // stejný zdroj, který čte i veřejný web motogo24.cz). Čteme JEN published=true řádky a řadíme stejně
      // jako web (category_key, sort_order). Pro cizí jazyk bereme přeloženou verzi z `translations[lang]`
      // (tvar { <lang>: { question, answer, category_label } }), jinak český originál — shoda s web `localized()`.
      // ŽÁDNÝ hardcoded fallback s konkrétními tvrzeními — když je FAQ prázdná, vracíme prázdno
      // a agent musí přiznat, že na to neodpoví, místo aby halucinoval policies z hlavy.
      const stripHtml = (s: string) => String(s || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
      const L = (lang || 'cs').slice(0, 2)
      const faqs: Array<{ q: string; a: string; cat?: string }> = []
      try {
        const { data: rows } = await sb.from('faq_items')
          .select('category_key, category_label, question, answer, translations, sort_order')
          .eq('published', true)
          .order('category_key', { ascending: true })
          .order('sort_order', { ascending: true })
        for (const r of (rows || []) as Record<string, unknown>[]) {
          const tr = (r.translations as Record<string, { question?: string; answer?: string; category_label?: string }> | null)?.[L] || {}
          const q = (L !== 'cs' && tr.question) ? tr.question : String(r.question || '')
          const a = (L !== 'cs' && tr.answer) ? tr.answer : String(r.answer || '')
          const cat = (L !== 'cs' && tr.category_label) ? tr.category_label : String(r.category_label || r.category_key || '')
          if (q && a) faqs.push({ q: stripHtml(q), a: stripHtml(a), cat: cat || undefined })
        }
      } catch { /* DB nedostupná — vrátíme prázdno a agent to korektně přizná */ }

      if (faqs.length === 0) {
        return {
          source: 'empty',
          count: 0,
          faqs: [],
          notice: 'FAQ v CMS není naplněna. NESDÍLEJ konkrétní policies z hlavy. Doporuč zákazníkovi kontakt firmy (telefon/e-mail viz sekce KONTAKTY v promptu — neber jiné), nebo zavolej tool get_policies a získej oficiální podmínky odtud. NIKDY si neimprovizuj cenu kauce, % storno-poplatku ani podmínky pojištění.',
        }
      }

      // Párování dotazu je tolerantní: bez diakritiky + po SLOVECH (ne celý dotaz jako jeden
      // podřetězec). Dřív `includes(celý_dotaz)` selhalo, jakmile agent poslal víceslovný dotaz
      // („skupina B Niken“ není souvislý podřetězec) → falešné „FAQ to nezmiňuje“. Teď stačí shoda
      // jednotlivých slov; když token-shoda nic nenajde, vrátíme pár prvních FAQ (agent není slepý).
      const stripDia = (s: string) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '')
      const norm = (s: string) => stripDia(String(s || '').toLowerCase())
      const rawQuery = String(args.query || '').trim()
      let matched = faqs
      if (rawQuery) {
        const qNorm = norm(rawQuery)
        // Min. délka tokenu 2 (ne 3): klíčové zkratky „ŘP"→„rp", „OP", „km", „EU" jsou dvouznakové
        // a s limitem 3 se vůbec nematchovaly → dotazy na doklady/limity km padaly do irelevantního
        // fallbacku. Jednoznakové tokeny (předložky) dál zahazujeme.
        const tokens = qNorm.split(/[^a-z0-9]+/).filter((t) => t.length >= 2)
        const scored = faqs
          .map((f) => {
            const hay = norm(f.q + ' ' + f.a + ' ' + (f.cat || ''))
            let score = 0
            if (qNorm && hay.includes(qNorm)) score += 5 // celý dotaz jako podřetězec = silná shoda
            for (const t of tokens) if (hay.includes(t)) score += 1
            return { f, score }
          })
          .filter((x) => x.score > 0)
          .sort((a, b) => b.score - a.score)
        matched = scored.length > 0 ? scored.map((x) => x.f) : faqs
      }
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
            notice: 'Policies v CMS nejsou nastavené. NESDÍLEJ z hlavy konkrétní procenta storna, výši kauce, cenu přistavení, pojištění mimo EU ani věkové limity skupin ŘP, které nejsou v české vyhlášce. Místo toho přiznej, že přesná čísla najde zákazník v textu smlouvy / VOP, nebo doporuč kontakt firmy (telefon/e-mail viz sekce KONTAKTY v promptu).',
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
    case 'get_legal_document': {
      // Skutečné znění smluvních/právních dokumentů ze šablon (document_templates: vop, rental_contract,
      // handover_protocol, gdpr) + webových dokumentů (custom_documents). sb běží pod service_role → čteme
      // bez ohledu na RLS. Agent z toho VÝHRADNĚ cituje/parafrázuje, nic si nedomýšlí. Pro cizí jazyk
      // bere přeloženou verzi (content_translations / translations[lang]), jinak český originál.
      try {
        const want = typeof args.document === 'string' ? String(args.document).trim().toLowerCase() : ''
        const query = typeof args.query === 'string' ? String(args.query).trim() : ''
        const L = (lang || 'cs').slice(0, 2)
        const MAX = 12000

        const stripHtml = (html: string): string => String(html || '')
          .replace(/<style[\s\S]*?<\/style>/gi, ' ')
          .replace(/<script[\s\S]*?<\/script>/gi, ' ')
          .replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n')
          .replace(/<br\s*\/?>/gi, '\n')
          .replace(/<[^>]+>/g, ' ')
          .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#3[49];/g, "'")
          .replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()

        const { data: tpls } = await sb.from('document_templates')
          .select('type, name, content_html, content_translations, name_translations')
          .eq('active', true).order('version', { ascending: false })
        const { data: customs } = await sb.from('custom_documents')
          .select('slug, title, content_html, kind, pdf_path, translations')
          .eq('active', true).eq('show_on_web', true).order('sort_order', { ascending: true })

        type Doc = { key: string; title: string; text: string; kind: string; url?: string }
        const docs: Doc[] = []
        const seen = new Set<string>()
        for (const t of (tpls || []) as Record<string, unknown>[]) {
          const key = String(t.type || '')
          if (!key || seen.has(key)) continue // jen nejvyšší aktivní verze (order desc)
          seen.add(key)
          const ct = (t.content_translations as Record<string, string> | null)?.[L]
          const nt = (t.name_translations as Record<string, string> | null)?.[L]
          const html = (L !== 'cs' && ct) ? ct : String(t.content_html || '')
          docs.push({ key, title: String((L !== 'cs' && nt) || t.name || key), text: stripHtml(html), kind: 'html' })
        }
        for (const c of (customs || []) as Record<string, unknown>[]) {
          const key = String(c.slug || '')
          if (!key || seen.has(key)) continue
          seen.add(key)
          const tr = (c.translations as Record<string, { title?: string; content_html?: string }> | null)?.[L] || {}
          const html = (L !== 'cs' && tr.content_html) ? tr.content_html : String(c.content_html || '')
          docs.push({
            key,
            title: String((L !== 'cs' && tr.title) || c.title || key),
            text: stripHtml(html),
            kind: String(c.kind || 'html'),
            url: (c.pdf_path as string) || `https://www.motogo24.cz/dokumenty/${key}`,
          })
        }

        if (docs.length === 0) {
          return {
            source: 'empty', documents: [],
            notice: 'V systému nejsou publikované žádné smluvní dokumenty. NEPŘEBÍREJ smluvní detaily z hlavy — řekni, že přesné znění zákazník dostane ve smlouvě/VOP před vyzvednutím, nebo odkaž na kontakt firmy (telefon/e-mail viz sekce KONTAKTY v promptu).',
          }
        }

        if (!want) {
          return {
            source: 'documents',
            available: docs.map((d) => ({ key: d.key, title: d.title, kind: d.kind, has_text: d.text.length > 0, url: d.url })),
            hint: 'Zavolej znovu s parametrem `document` = jeden z těchto `key` (a volitelně `query`), ať dostaneš znění. Cituj jen to, co tool vrátí.',
          }
        }

        const match = docs.find((d) => d.key.toLowerCase() === want)
          || docs.find((d) => d.key.toLowerCase().includes(want) || d.title.toLowerCase().includes(want))
        if (!match) {
          return { source: 'documents', error: `Dokument "${want}" nenalezen.`, available: docs.map((d) => ({ key: d.key, title: d.title })) }
        }
        if (!match.text) {
          return {
            source: 'documents', key: match.key, title: match.title, kind: match.kind, url: match.url,
            notice: 'Tento dokument je na webu jen jako PDF — strojový text k citaci nemám. Odkaž zákazníka na uvedenou URL nebo na kontakt.',
          }
        }

        if (query) {
          const text = match.text
          const lc = text.toLowerCase()
          const terms = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 3)
          const hits: number[] = []
          for (const term of terms) {
            let from = 0
            for (;;) {
              const i = lc.indexOf(term, from)
              if (i < 0 || hits.length > 40) break
              hits.push(i); from = i + term.length
            }
          }
          if (hits.length > 0) {
            hits.sort((a, b) => a - b)
            const win: Array<[number, number]> = []
            for (const i of hits) {
              const s = Math.max(0, i - 400), e = Math.min(text.length, i + 400)
              const last = win[win.length - 1]
              if (last && s <= last[1]) last[1] = Math.max(last[1], e)
              else win.push([s, e])
            }
            let excerpt = win.map(([s, e]) => (s > 0 ? '…' : '') + text.slice(s, e).trim() + (e < text.length ? '…' : '')).join('\n\n———\n\n')
            if (excerpt.length > MAX) excerpt = excerpt.slice(0, MAX) + '…'
            return {
              source: 'documents', key: match.key, title: match.title, mode: 'excerpts', query, text: excerpt,
              instruction: 'Odpověz výhradně z tohoto znění. Pokud konkrétní odpověď v úryvcích NENÍ, přiznej to a odkaž zákazníka na plný text dokumentu / kontakt — nedomýšlej.',
            }
          }
          // query nic nenašlo → vrať plný (zkrácený) text, ať rozhodne model
        }
        const full = match.text.length > MAX ? match.text.slice(0, MAX) + '\n…[zkráceno — plné znění na webu]' : match.text
        return {
          source: 'documents', key: match.key, title: match.title, kind: match.kind, url: match.url, mode: 'full', text: full,
          instruction: 'Cituj a parafrázuj VÝHRADNĚ z tohoto znění. Co tu výslovně není, si nedomýšlej — přiznej, že to dokument neuvádí, a odkaž na kontakt.',
        }
      } catch (e) {
        return { error: `Nepodařilo se načíst dokumenty: ${(e as Error).message}` }
      }
    }
    case 'get_motorcycle_manual': {
      // Přečte návod konkrétní motorky. PDF (manual_url, public bucket `media`) má přednost před
      // externím odkazem (manual_external_url). Z PDF vytáhneme text přes `unpdf` (serverless pdf.js),
      // z webové stránky stripneme HTML. Při `query` vrátíme jen relevantní pasáže (stejně jako
      // get_legal_document) — návody bývají dlouhé a celý text by zbytečně žral tokeny.
      const motoId = String(args.moto_id || '').trim()
      const query = typeof args.query === 'string' ? String(args.query).trim() : ''
      if (!motoId) return { error: 'Chybí moto_id.' }
      const { data: moto } = await sb.from('motorcycles')
        .select('id, brand, model, manual_url, manual_external_url')
        .eq('id', motoId).maybeSingle()
      if (!moto) return { error: 'Motorka nenalezena.' }
      const mm = moto as Record<string, unknown>
      const mName = motoDisplayName(mm.brand as string, mm.model as string)
      const pdfUrl = String(mm.manual_url || '').trim()
      const extUrl = String(mm.manual_external_url || '').trim()
      const sourceUrl = pdfUrl || extUrl
      if (!sourceUrl) {
        return {
          found: false, model: mName,
          notice: `K motorce ${mName} není v systému nahraný návod ani externí odkaz. NEVYMÝŠLEJ si technické údaje — řekni, že návod k téhle motorce k dispozici nemáš, a odkaž na detail motorky (https://www.motogo24.cz/katalog/${motoId}) nebo na kontakt firmy.`,
        }
      }

      // Stažení + parsování dělá sdílený ../_shared/manual-reader.ts (browser UA,
      // retry, PDF magic bytes, PDF odkazy z rozcestníku, oba zdroje) — viz komentář tam.
      return await readManual({
        modelName: mName, pdfUrl, extUrl, query, instruction: MANUAL_INSTRUCTION,
        contactHint: `detail motorky (https://www.motogo24.cz/katalog/${motoId}) nebo kontakt firmy`,
        cachedText: await getBundledManualText(motoId) || undefined,
      })
    }
    case 'get_extras_catalog': {
      // Dva zdroje: `extras_catalog` (top case, GPS, přistavení…) + `accessory_types` (ceník
      // OBLEČENÍ/výbavy — helma, bunda, kalhoty, rukavice, boty, kukla; stejný zdroj jako
      // rezervační formulář na webu). Bez druhého zdroje agent neuměl říct cenu výbavy spolujezdce.
      const [{ data }, { data: acc }] = await Promise.all([
        sb.from('extras_catalog')
          .select('id, name, description, price, unit, category, is_active')
          .eq('is_active', true).order('sort_order', { ascending: true }).order('name'),
        sb.from('accessory_types')
          .select('key, label, sizes, price_czk, pricing_unit, is_active')
          .eq('is_active', true).order('sort_order', { ascending: true }),
      ])
      return {
        extras: (data || []).map((e: Record<string, unknown>) => ({
          id: e.id, name: e.name, price_kc: e.price, unit: e.unit || 'ks', category: e.category, description: e.description,
        })),
        gear_pricing: (acc || []).map((a: Record<string, unknown>) => ({
          type: a.key, label: a.label, sizes: a.sizes,
          price_kc: a.pricing_unit === 'free' ? 0 : Number(a.price_czk || 0),
          pricing_unit: a.pricing_unit, // free = v ceně | per_booking = jednorázově za rezervaci | per_day = za každý den
        })),
        gear_notice: 'Ceny výbavy (oblečení) ber VÝHRADNĚ z `gear_pricing`: `free`/0 Kč = v ceně pronájmu, `per_booking` = jednorázový příplatek za rezervaci, `per_day` = příplatek za každý den. Základní výbava ŘIDIČE (helma, bunda, kalhoty, rukavice) je v ceně; placené bývají boty řidiče a výbava spolujezdce — ale řiď se daty, ne touto větou. Když je `gear_pricing` prázdné, řekni, že přesný ceník výbavy potvrdí půjčovna — NEVYMÝŠLEJ částky.',
      }
    }
    case 'get_branches': {
      // select('*') SCHVÁLNĚ — dřívější výčet obsahoval sloupce, které v DB `branches`
      // neexistují (zip, lat, lng, email, opening_hours) → PostgREST 42703, chyba se
      // tiše zahodila a tool vrátil prázdný seznam („pobočky nemáme"). Incident 2026-08-05.
      const { data, error } = await sb.from('branches').select('*').order('name')
      // is_open === false = trvale zavřená pobočka: nenabízet (zákazník tam nic
      // nezarezervuje). Když tím seznam vyjde prázdný, projde se fallback níž —
      // agent NIKDY netvrdí „pobočky nemáme" (incident 2026-08-05).
      const rows = ((data || []) as Array<Record<string, unknown>>)
        .filter((b) => b.active !== false && b.is_open !== false)
      if (error || rows.length === 0) {
        const { data: ci } = await sb.from('app_settings').select('value').eq('key', 'company_info').maybeSingle()
        const c = (ci?.value || {}) as Record<string, unknown>
        return {
          branches: [],
          ...(error ? { error: `Načtení poboček selhalo: ${error.message}` } : {}),
          fallback_contact: {
            name: c.name || 'MotoGo24',
            address: c.address || 'Mezná 9, 393 01 Pelhřimov',
            phone: c.phone || '+420 774 256 271',
            email: c.email || 'info@motogo24.cz',
          },
          notice: 'Seznam poboček se teď nepodařilo načíst — TECHNICKÁ chyba, NE stav reality. NIKDY zákazníkovi netvrď, že žádné pobočky nemáme nebo že je seznam v databázi prázdný. Vyzvednutí motorky probíhá na naší pobočce — pošli zákazníka na adresu ve `fallback_contact` (hlavní výdejní místo) a nabídni telefon/e-mail pro potvrzení detailů.',
        }
      }
      return {
        branches: rows.map((b) => {
          const lat = b.lat ?? b.gps_lat ?? null
          const lng = b.lng ?? b.gps_lng ?? null
          return {
            id: b.id, name: b.name,
            address: [b.address, `${b.zip || ''} ${b.city || ''}`.trim()].filter(Boolean).join(', '),
            lat, lng,
            maps_url: (lat != null && lng != null) ? `https://mapy.cz/zakladni?q=${lat},${lng}` : null,
            phone: b.phone ?? null, email: b.email ?? null,
            opening_hours: b.opening_hours || null,
            is_open_nonstop: !!b.is_open, type: b.type, notes: b.notes,
          }
        }),
        notice: 'REŽIM výdeje/vrácení urči VÝHRADNĚ z pole `type` konkrétní pobočky: "samoobslužná" = výdej i vrácení 24/7 přístupovým kódem; "obslužná" = motorku předává a přebírá OBSLUHA osobně (řiď se `opening_hours` / domluvou). Přístupové kódy chodí e-mailem u OBOU typů — u obslužné pobočky neotvírají dveře, slouží jako IDENTIFIKACE: zákazník je řekne obsluze, ta podle nich rezervaci dohledá, předání ~2 minuty; sken dokladů předem není povinný, ale doporučuje se (urychlí odbavení, zvlášť při více odjezdech najednou). NIKDY netvrď paušálně, že výdej je samoobslužný a nonstop, ani že u obslužné pobočky kódy nechodí. Rezervaci lze VYTVOŘIT 24/7 u obou typů — u OBSLUŽNÉ pobočky proběhne výdej vždy až 1–6 hodin PO vytvoření a zaplacení rezervace (příprava stroje), tam neslibuj okamžité vyzvednutí. U SAMOOBSLUŽNÉ pobočky se čas vyzvednutí zadává (sleva za pozdní vyzvednutí), ale hodina předem potřeba není — rezervovat lze i na dnešek; čas vrácení na pobočku se nezadává (konec dne). U přistavení platí čas min. aktuální + 6 h.',
      }
    }
    case 'validate_promo_or_voucher': {
      const code = String(args.code || '').trim()
      if (!code) return { valid: false, error: 'Prázdný kód' }
      const { data: promo } = await sb.rpc('validate_promo_code', { p_code: code })
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
      const startMs = start.getTime()
      const endMs = new Date(a.end_date).getTime()
      if (isNaN(endMs) || endMs < startMs) {
        return { error: 'Neplatné datum konce — musí být stejné nebo pozdější než začátek (YYYY-MM-DD).' }
      }
      // Min/max délka pronájmu z dat motorky — stejné vynucení jako v calculate_price.
      const rentalDays = Math.round((endMs - startMs) / 86_400_000) + 1
      const { data: motoLimits } = await sb.from('motorcycles')
        .select('min_rental_days, max_rental_days, branches!branch_id(type)').eq('id', a.moto_id).maybeSingle()
      // Parita s webem/appkou: samoobsluha — vrácení na pobočce bez času → 23:59
      // (čas vyzvednutí se zadává vždy, řídí slevu za pozdní vyzvednutí).
      const ssBranch = ((motoLimits as Record<string, unknown> | null)?.branches as Record<string, unknown> | null)?.type === 'samoobslužná'
      const limMin = Number((motoLimits as Record<string, unknown>)?.min_rental_days || 0)
      const limMax = Number((motoLimits as Record<string, unknown>)?.max_rental_days || 0)
      if (limMin > 0 && rentalDays < limMin) {
        return { error: `Tato motorka má minimální délku pronájmu ${limMin} dní (požadováno ${rentalDays}). Rezervaci nevytvářím — nabídni delší termín nebo jinou motorku.` }
      }
      if (limMax > 0 && rentalDays > limMax) {
        return { error: `Tato motorka má maximální délku pronájmu ${limMax} dní (požadováno ${rentalDays}). Rezervaci nevytvářím — nabídni kratší termín nebo jinou motorku.` }
      }
      // Validate availability
      const { data: booked } = await sb.rpc('get_moto_booked_dates', { p_moto_id: a.moto_id })
      const bookedArr = Array.isArray(booked) ? booked : []
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
      // Parita s webovým formulářem: VOP + GDPR jsou na webu povinné checkboxy. Tady je nahrazuje
      // výslovný souhlas zákazníka v chatu — bez obou rezervaci nevytvoříme (jinak by se do profilu
      // uložil defaultní „true" bez reálného souhlasu, viz mig. 20260523_create_web_booking_consents).
      const consentVop = ax.consent_vop === true || ax.consent_vop === 'true'
      const consentGdpr = ax.consent_gdpr === true || ax.consent_gdpr === 'true'
      if (!consentVop || !consentGdpr) {
        return { error: 'Chybí povinný souhlas. Nejdřív si od zákazníka vyžádej VÝSLOVNÝ souhlas s VOP (obchodní podmínky + smlouva) a se zpracováním osobních údajů (GDPR), pak zavolej znovu s consent_vop=true a consent_gdpr=true.' }
      }
      // Datum narození — na webu povinné pole. Vyžadujeme platný formát YYYY-MM-DD.
      const dob = String(a.date_of_birth || '').slice(0, 10)
      if (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || isNaN(new Date(dob).getTime())) {
        return { error: 'Chybí nebo je neplatné datum narození (očekávám YYYY-MM-DD). Doptej se zákazníka a zavolej znovu.' }
      }
      // consent_photo default true (potřebné k ověření dokladů), false jen při výslovném odmítnutí.
      const consentPhoto = !(ax.consent_photo === false || ax.consent_photo === 'false')
      const marketingConsent = ax.marketing_consent === true || ax.marketing_consent === 'true'
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
        p_passenger_pants_size: a.passenger_pants_size || null,
        // Stejně jako web: přistavení + vrácení na stejné adrese = vrácení mimo pobočku.
        p_return_time: (ssBranch && !a.return_address && !a.delivery_address) ? '23:59' : (a.return_time || null),
        p_date_of_birth: dob,
        p_consent_vop: true,
        p_consent_gdpr: true,
        p_marketing_consent: marketingConsent,
        p_consent_photo: consentPhoto,
      })
      if (error) {
        return { error: `Rezervaci se nepodařilo vytvořit: ${error.message}` }
      }
      const result = data as Record<string, unknown>
      const bookingId = String(result?.booking_id || '')
      const userId = String(result?.user_id || '')
      const amount = Number(result?.amount || 0)

      // Označ rezervaci jako vytvořenou přes AI agenta — Velín tak zobrazí
      // 🤖 AI badge vedle WEB. Sloupec `created_via_ai` přibyl 2026-05-02
      // (booking-source granularity per request od admina).
      try {
        if (bookingId) {
          await sb.from('bookings').update({ created_via_ai: true }).eq('id', bookingId)
          // i18n: ulož jazyk konverzace do bookings.language → maily/SMS/push
          // pro tohoto zákazníka půjdou v jazyce v jakém s agentem mluvil.
          try {
            const detectedLang = (lang || 'cs').slice(0, 2).toLowerCase()
            if (['cs','en','de','nl','es','fr','pl'].includes(detectedLang)) {
              await sb.rpc('set_booking_language', {
                p_booking_id: bookingId, p_language: detectedLang,
              })
            }
          } catch { /* non-blocking */ }
        }
      } catch { /* non-blocking — feature degraduje gracefully na obyč WEB badge */ }

      // Skupina ŘP do profilu, pokud ji agent z konverzace zná (nepovinné — čísla
      // dokladů se v NOVÉM flow nesbírají v chatu, zákazník je doplní až po platbě).
      try {
        if (userId && a.license_group) {
          await sb.from('profiles').update({ license_group: [a.license_group] }).eq('id', userId)
        }
      } catch { /* non-blocking */ }

      // Nastavit heslo zákazníka (pro správu rezervace a přihlášení do appky).
      // Selhání NEshazuje rezervaci, ale musí se propsat do odpovědi — dřív bylo tiché
      // a agent zákazníkovi tvrdil „heslo nastaveno", i když se neuložilo.
      let passwordSet = false
      try {
        if (a.password && bookingId) {
          const { error: pwErr } = await sb.rpc('set_web_booking_password', { p_booking_id: bookingId, p_password: a.password })
          passwordSet = !pwErr
          if (pwErr) console.warn('[create_booking_request] set_web_booking_password failed:', pwErr.message)
        }
      } catch (e) { console.warn('[create_booking_request] set_web_booking_password error:', (e as Error).message) }
      const passwordNotice = passwordSet
        ? null
        : 'POZOR: heslo se NEPODAŘILO uložit. Zákazníkovi řekni, že pro přihlášení do správy rezervace / appky použije „Zapomenuté heslo" (obnovu přes e-mail) — netvrď mu, že heslo je nastavené.'

      // Platební metoda: "qr" = QR / bankovní převod (spustí edge fn qr-payment,
      // která přidělí VS, vystaví ZF a pošle zákazníkovi platební údaje + QR mailem),
      // jinak "card" = online kartou (resume URL → krok platby na webu). Doklady se
      // v OBOU případech doplňují až PO platbě přímo v rezervaci (žádný skener v chatu).
      const paymentMethod = String((a.payment_method || 'card')).toLowerCase() === 'qr' ? 'qr' : 'card'
      const langShort = (lang || 'cs').slice(0, 2)

      if (paymentMethod === 'qr') {
        try {
          const qrRes = await fetch(`${SUPABASE_URL}/functions/v1/qr-payment`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
              apikey: SUPABASE_SERVICE_KEY,
            },
            body: JSON.stringify({ booking_id: bookingId, locale: langShort }),
          })
          const qr = (await qrRes.json().catch(() => ({}))) as Record<string, unknown>
          if (qr?.success) {
            return {
              success: true,
              booking_id: bookingId,
              amount_kc: amount,
              is_new_user: !!result?.is_new_user,
              password_set: passwordSet,
              password_notice: passwordNotice,
              payment_method: 'qr',
              qr_payment: {
                account: qr.account,
                iban: qr.iban,
                bank: qr.bank,
                variable_symbol: qr.vs,
                amount_kc: qr.amount,
                due_hours: qr.due_hours || 4,
                invoice_number: qr.invoice_number || null,
                booking_number: qr.booking_number,
              },
              message: 'Rezervace vytvořena, platba QR / převodem je připravena. NEPIŠ žádnou URL. Tvoje odpověď: krátké shrnutí (motorka, termín, celková cena) + přehledně zopakuj platební údaje z pole qr_payment — číslo účtu, IBAN, variabilní symbol a částku. Řekni, že stejné údaje i QR kód dostal právě e-mailem (v příloze zálohová faktura) a že platbu je potřeba provést do 4 hodin, jinak se rezervace automaticky zruší a termín uvolní. Dodej, že po připsání platby rezervaci ručně potvrdíme a pošleme potvrzení; ČÍSLA dokladů (OP/ŘP) a případný sken doplní až potom přímo v rezervaci na motogo24.cz nebo v appce — teď je řešit nemusí.',
            }
          }
          // QR selhalo → spadni na kartu (nechceme zákazníka nechat bez cesty k platbě)
          console.warn('[create_booking_request] qr-payment failed:', JSON.stringify(qr))
        } catch (e) {
          console.warn('[create_booking_request] qr-payment error:', (e as Error).message)
        }
      }

      // Karta (default nebo QR fallback): resume URL → krok platby na webu.
      // V NOVÉM flow zákazník nejdřív zaplatí a AŽ POTOM (samostatný krok) doplní
      // čísla dokladů + volitelný sken — proto v chatu žádné doklady neřešíme.
      const paymentUrl = `https://www.motogo24.cz/rezervace?resume=${bookingId}`
      return {
        success: true,
        booking_id: bookingId,
        amount_kc: amount,
        is_new_user: !!result?.is_new_user,
        password_set: passwordSet,
        password_notice: passwordNotice,
        payment_method: 'card',
        payment_url: paymentUrl,
        message: 'Rezervace vytvořena. NEPIŠ URL do textu — systém k tvé odpovědi automaticky doplní tlačítko "Pokračovat k platbě". Tvoje odpověď: krátké shrnutí (motorka, termín, celková cena) + věta "Rezervaci jsem vytvořil — klikni na tlačítko níže a otevře se zabezpečená platba kartou (Stripe). Po zaplacení tě systém navede na doplnění čísel dokladů (OP/ŘP); teď v chatu je řešit nemusíš. Potvrzení a přístupové údaje ti dorazí e-mailem."',
      }
    }
    case 'find_my_booking': {
      const a = args as Record<string, string>
      // Přelož krátkou referenci (#XXXXXXXX = posledních 8 znaků) NEBO plné UUID na plné UUID.
      const ref = await resolveBookingRef(a.booking_id)
      if (ref.error) return { success: false, error: ref.error }
      const bid = ref.id as string
      // LIGHT (jen číslo rezervace, bez hesla) → server vrátí stav bez PII.
      // FULL (s heslem) → 3faktorové ověření jako dřív.
      const hasFull = !!(a.password_last4 && a.contact)
      if (!hasFull) {
        const { data, error } = await sb.rpc('find_booking_light', { p_booking_id: bid })
        if (error) return { success: false, error: error.message }
        return data
      }
      const { data, error } = await sb.rpc('find_booking_for_modification', {
        p_booking_id: bid,
        p_contact: a.contact,
        p_password_last4: a.password_last4,
      })
      if (error) return { success: false, error: error.message }
      return data
    }
    case 'lookup_my_bookings': {
      // READ-ONLY ověření podle e-mailu/telefonu — bez hesla. Vrací stav + odeslané maily, NE citlivá PII.
      const a = args as Record<string, string>
      const contact = String(a.contact || '').trim()
      if (!contact) return { success: false, error: 'missing_inputs' }
      const { data, error } = await sb.rpc('ai_lookup_bookings_by_contact', { p_contact: contact })
      if (error) return { success: false, error: error.message }
      return data
    }
    case 'get_booking_emails': {
      // READ-ONLY — které maily reálně odešly k rezervaci. Bez hesla. Slouží k ověření platby/stavu.
      const a = args as Record<string, string>
      const ref = await resolveBookingRef(a.booking_id)
      if (ref.error) return { success: false, error: ref.error }
      const { data, error } = await sb.rpc('ai_get_booking_emails', { p_ref: ref.id })
      if (error) return { success: false, error: error.message }
      return data
    }
    case 'get_booking_readiness': {
      // READ-ONLY — připravenost k vyzvednutí (doklady + kódy), jen stav, bez hesla, bez PII.
      const a = args as Record<string, string>
      const ref = await resolveBookingRef(a.booking_id)
      if (ref.error) return { success: false, error: ref.error }
      const { data, error } = await sb.rpc('ai_booking_readiness', { p_ref: ref.id })
      if (error) return { success: false, error: error.message }
      return data
    }
    case 'get_order_status': {
      // READ-ONLY — stav e-shop objednávky / poukazu podle e-mailu nebo čísla objednávky. PII-minimal.
      const a = args as Record<string, string>
      const contact = String(a.contact || '').trim()
      if (!contact) return { success: false, error: 'missing_inputs' }
      const { data, error } = await sb.rpc('ai_get_order_status', { p_contact: contact })
      if (error) return { success: false, error: error.message }
      return data
    }
    case 'preview_booking_change':
    case 'apply_booking_change': {
      const a = args as Record<string, unknown>
      const isDryRun = name === 'preview_booking_change'
      const ref = await resolveBookingRef(a.booking_id)
      if (ref.error) return { success: false, error: ref.error }
      const bid = ref.id as string
      const hasFull = !!(a.password_last4 && a.contact)
      // LIGHT: bez hesla — server pustí REÁLNOU změnu jen u nulového dopadu (net_diff=0),
      // jinak vrátí full_verification_required a agent si vyžádá heslo (FULL větev níže).
      if (!hasFull) {
        const { data, error } = await sb.rpc('apply_booking_change_light', {
          p_booking_id: bid,
          p_new_start: a.new_start_date || null,
          p_new_end: a.new_end_date || null,
          p_new_moto_id: a.new_moto_id || null,
          p_new_pickup_method: a.new_pickup_method || null,
          p_new_pickup_address: a.new_pickup_address || null,
          p_new_pickup_fee: a.new_pickup_fee ?? null,
          p_new_return_method: a.new_return_method || null,
          p_new_return_address: a.new_return_address || null,
          p_new_return_fee: a.new_return_fee ?? null,
          p_new_pickup_time: null,
          p_reason: a.reason || (isDryRun ? 'light_preview' : 'light_edit'),
          p_dry_run: isDryRun,
        })
        if (error) return { success: false, error: error.message }
        return data
      }
      const { data, error } = await sb.rpc('apply_booking_changes_anon', {
        p_booking_id: bid,
        p_contact: a.contact,
        p_password_last4: a.password_last4,
        p_new_start: a.new_start_date || null,
        p_new_end: a.new_end_date || null,
        p_new_moto_id: a.new_moto_id || null,
        p_new_pickup_method: a.new_pickup_method || null,
        p_new_pickup_address: a.new_pickup_address || null,
        p_new_pickup_lat: null,
        p_new_pickup_lng: null,
        p_new_pickup_fee: a.new_pickup_fee ?? null,
        p_new_return_method: a.new_return_method || null,
        p_new_return_address: a.new_return_address || null,
        p_new_return_lat: null,
        p_new_return_lng: null,
        p_new_return_fee: a.new_return_fee ?? null,
        p_reason: a.reason || (isDryRun ? 'preview' : 'ai_agent_edit'),
        p_dry_run: isDryRun,
      })
      if (error) return { success: false, error: error.message }
      return data
    }
    case 'redirect_to_booking': {
      const params = new URLSearchParams()
      if (args.moto_id) params.set('moto', String(args.moto_id))
      if (args.start_date) params.set('start', String(args.start_date))
      if (args.end_date) params.set('end', String(args.end_date))
      return {
        url: `https://www.motogo24.cz/rezervace?${params}`,
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

// Rozparsuje aktivní filtry z URL výpisu katalogu (/katalog?q=...&kategorie=...&ridicak=...&jezdci=...).
// Web tyhle filtry NEVYSTAVUJE přes window.MOTOGO_PAGE_CTX, posílá je jen v query stringu URL —
// bez tohoto parsování agent filtry „nevidí" a začne si domýšlet (např. že „nic nemáme" nebo
// dokonce halucinuje kategorii, kterou nenabízíme). Vrací human-readable řádky.
function describeKatalogFilters(url: string, path: string): string[] {
  const out: string[] = []
  try {
    const base = (url && /^https?:\/\//.test(url)) ? url : `https://www.motogo24.cz${path || ''}`
    const q = new URL(base).searchParams
    const katLabel: Record<string, string> = {
      cestovni: 'cestovní', naked: 'naked', supermoto: 'supermoto', detske: 'dětské',
      scootery: 'skútry', sportovni: 'sportovní', chopper: 'chopper', ostatni: 'ostatní',
    }
    const pairs: Array<[string, string]> = []
    const text = (q.get('q') || '').trim()
    if (text) pairs.push(['hledaný text', text])
    const kat = (q.get('kategorie') || '').trim()
    if (kat) pairs.push(['kategorie', katLabel[kat] || kat])
    const rid = (q.get('ridicak') || '').trim()
    if (rid) pairs.push(['skupina ŘP', rid])
    const jezdci = (q.get('jezdci') || '').trim()
    if (jezdci && jezdci !== '0') pairs.push(['počet jezdců', jezdci])
    for (const [k, v] of pairs) out.push(`  • ${k}: ${v}`)
  } catch { /* ignore — bez filtrů jen vynecháme blok */ }
  return out
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
  // Katalog: vytáhni aktivní filtry z URL, aby agent věděl, podle čeho si zákazník právě prohlíží výpis.
  const katFilters = (type === 'katalog') ? describeKatalogFilters(url, path) : []
  if (katFilters.length > 0) {
    lines.push('- AKTIVNÍ FILTRY KATALOGU (zákazník je má právě nastavené ve výpisu):')
    for (const f of katFilters) lines.push(f)
  }
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
  if (type === 'katalog') {
    lines.push('- KATALOG: Zákazník je ve výpisu motorek. Když napíše krátký dotaz ("125ccm", "něco menšího", "co tu máte", "na tohle") bez upřesnění, ber AKTIVNÍ FILTRY KATALOGU výše jako jeho zadání a ZAVOLEJ `search_motorcycles` s odpovídajícími filtry (license_group ze „skupina ŘP", category z „kategorie", kw/ccm/cena z „hledaný text"). Odpověz POUZE z toho, co tool vrátí — nikdy „od oka".')
    lines.push('- KATALOG zobrazuje aktuální flotilu. JESTLI MÁME daný typ stroje (skútr, naked, cestovní, supermoto, dětská…) NEHÁDEJ z hlavy — řiď se sekcí „KOMPLETNÍ FLOTILA" výše (pole „kat."; skútr = kategorie „scootery") a/nebo zavolej `search_motorcycles` s `category`. Když tam kategorie je, potvrď a nabídni; když není, řekni rovně, že tu kategorii teď nemáme. NIKDY netvrď paušálně „skútry nepronajímáme", pokud skútr v živé flotile je. A NIKDY si neprotiřeč: co potvrdíš, v další větě nepopři.')
    lines.push('- Když pod aktivními filtry žádná motorka není, neříkej jen „nic nemáme" — nabídni REÁLNOU alternativu z živé flotily (jiná skupina ŘP, jiná kategorie, vyšší/nižší výkon) a doptej se, co je pro zákazníka důležité. Žádnou kategorii ani typ stroje, který nemáme, si nevymýšlej.')
  }
  return lines.join('\n')
}

function buildSystemPrompt(lang: string, cfg: WebAgentConfig, company: CompanyInfo, fleet: FleetMoto[], branches: BranchRow[], pageCtx: PageContext | null | undefined, kb: string): Array<{ type: 'text'; text: string; cache_control?: { type: 'ephemeral' } }> {
  // Jazyk je adaptivní — model VŽDY odpovídá ve stejném jazyce, jakým píše uživatel.
  // `lang` je jen hint z prohlížeče (UI jazyk webu) pro úvodní zprávu.
  const langHint = (lang || 'cs').slice(0, 2)
  const langInstr = `JAZYK ODPOVĚDI — NEJVYŠŠÍ PRIORITA, platí i pro úplně PRVNÍ odpověď:
1. Urči jazyk POSLEDNÍ zprávy uživatele a odpověz VÝHRADNĚ v tomto jazyce. Toto pravidlo přebíjí vše ostatní v tomto promptu. Celý system prompt je psaný česky kvůli interní konfiguraci — to NESMÍ ovlivnit jazyk tvojí odpovědi. Píše-li zákazník anglicky, odpovíš anglicky; německy → německy; atd.
2. Platí to i pro PRVNÍ zprávu konverzace — pokud zákazník otevře chat rovnou anglickou (nebo jinou cizojazyčnou) zprávou, odpovídáš v jejím jazyce, NE v češtině.
3. Hint UI jazyka webu je: ${langHint}. Použij ho POUZE jako záchranu, když jazyk z textu uživatele nejde rozpoznat (zpráva je jen "ok", "?", jméno, číslo nebo emoji). Jakmile je v textu uživatele jazyk jasný, hint ignoruj.
4. Když zákazník jazyk uprostřed konverzace přepne, přepni s ním. Nikdy nemíchej jazyky ani neodpovídej dvojjazyčně — vyber jeden jazyk a celou odpověď napiš v něm.`

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
  // Předpočítané referenční datumy — agent na to nesmí spoléhat, že si „víkend"
  // nebo „příští pondělí" spočítá sám (v reálných konverzacích to plete: říká
  // „tento víkend = ne–po" místo „so+ne"). Zde to spočítáme deterministicky
  // v Europe/Prague a injektujeme jako autoritativní reference.
  const dateRefs = (() => {
    // Kotva v POLEDNE UTC pražského dneška: ±12 h rezerva od DST, takže aritmetika po dnech
    // ani formátování do Europe/Prague nikdy nepřeteče do jiného kalendářního dne. Dřívější
    // kotva `T00:00:00+02:00` (natvrdo letní offset) + getUTCDay() posouvala v ZIMĚ všechny
    // reference (Dnes/Zítra/víkendy) o den zpět a v létě počítala den v týdnu z UTC půlnoci
    // → „TENTO VÍKEND (sobota)" ukazoval neděli. Ověřeno reprodukcí.
    const todayDate = new Date(`${todayIso}T12:00:00Z`)
    // Den v týdnu DNEŠKA v Europe/Prague (Po=1 … Ne=7) — z formatteru, NIKDY z getUTCDay()
    const dowMap: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 }
    const todayDow = dowMap[new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'Europe/Prague' }).format(now)] || 1
    const fmtIsoLocal = (d: Date): string => fmtIso.format(d)
    const fmtCsLong = new Intl.DateTimeFormat('cs-CZ', { weekday: 'long', day: 'numeric', month: 'numeric', year: 'numeric', timeZone: 'Europe/Prague' })
    const addDays = (base: Date, n: number): Date => new Date(base.getTime() + n * 24 * 3600 * 1000)
    // Tento víkend = nejbližší upcoming sobota a neděle (pokud je dnes so → dnes+zítra; pokud ne → dnes + následující den; pokud po-pá → nejbližší so/ne; pokud ne → dnes a včera, ale pro budoucí význam bereme „za 6 dní" so+ne)
    // Konvence: pokud je dnes Mon–Fri → tento víkend = nejbližší So+Ne; So → dnes+zítra; Ne → včera+dnes (jen orientačně, agent se má zeptat).
    let satOffset: number
    if (todayDow <= 5) satOffset = 6 - todayDow      // Po(1)→5, Út(2)→4, ... Pá(5)→1
    else if (todayDow === 6) satOffset = 0           // So → dnes
    else satOffset = -1                              // Ne → včera (so), agent se má zeptat na příští víkend
    const sat = addDays(todayDate, satOffset)
    const sun = addDays(sat, 1)
    const nextSat = addDays(sat, 7)
    const nextSun = addDays(sat, 8)
    const tomorrow = addDays(todayDate, 1)
    const dayAfter = addDays(todayDate, 2)
    const inWeek = addDays(todayDate, 7)
    return {
      today: `${fmtIsoLocal(todayDate)} (${fmtCsLong.format(todayDate)})`,
      tomorrow: `${fmtIsoLocal(tomorrow)} (${fmtCsLong.format(tomorrow)})`,
      dayAfter: `${fmtIsoLocal(dayAfter)} (${fmtCsLong.format(dayAfter)})`,
      thisWeekendSat: `${fmtIsoLocal(sat)} (${fmtCsLong.format(sat)})`,
      thisWeekendSun: `${fmtIsoLocal(sun)} (${fmtCsLong.format(sun)})`,
      nextWeekendSat: `${fmtIsoLocal(nextSat)} (${fmtCsLong.format(nextSat)})`,
      nextWeekendSun: `${fmtIsoLocal(nextSun)} (${fmtCsLong.format(nextSun)})`,
      inWeek: `${fmtIsoLocal(inWeek)} (${fmtCsLong.format(inWeek)})`,
    }
  })()

  const persona = cfg.persona_name || 'Rezervační asistent MotoGo24'
  const userPrompt = (cfg.system_prompt || '').trim()
  const tone = TONE_DESC[cfg.tone || 'concise'] || TONE_DESC.concise

  let parts: string[] = []
  const companyAddr = company.address || 'Mezná 9, 393 01 Pelhřimov'
  const companyName = company.name || 'MotoGo24'
  parts.push(`DNES JE ${todayHuman} (ISO ${todayIso}, časová zóna Europe/Prague). Tento údaj je zdroj pravdy o aktuálním datu — vždy ho použij místo vlastních odhadů.

REFERENČNÍ DATA (předpočítané, nikdy je nepřepočítávej; používej tyto ISO hodnoty pro tooly):
- Dnes: ${dateRefs.today}
- Zítra: ${dateRefs.tomorrow}
- Pozítří: ${dateRefs.dayAfter}
- TENTO VÍKEND (sobota): ${dateRefs.thisWeekendSat}
- TENTO VÍKEND (neděle): ${dateRefs.thisWeekendSun}
- PŘÍŠTÍ VÍKEND (sobota): ${dateRefs.nextWeekendSat}
- PŘÍŠTÍ VÍKEND (neděle): ${dateRefs.nextWeekendSun}
- Za týden (stejný den jako dnes +7): ${dateRefs.inWeek}

Když user řekne „víkend" / „weekend" / „Wochenende", mluví o **sobotě + neděli** — viz ISO data výše. „Tento víkend" je řádek THIS WEEKEND, „příští víkend" je NEXT WEEKEND. NIKDY nepárová ne+po nebo po+út jako víkend.

Datum bez roku (např. „19. 7.") = AKTUÁLNÍ rok z hlavičky (příští rok jen pokud datum letos už proběhlo). Den v týdnu k datu urči VÝHRADNĚ z ISO kalendáře aktuálního roku — NIKDY zákazníka „neopravuj" na jiný den v týdnu podle jiného roku; pokud jeho datum a den v týdnu nesedí ani v aktuálním roce, zdvořile se doptej, co platí.`)
  parts.push(`Jsi ${persona}. Pracuješ v půjčovně motorek ${companyName} (${companyAddr}, ČR).`)
  // Live snapshot kompletní flotily — injektujeme co nejvýš, aby model měl
  // autoritativní seznam motorek v kontextu od první odpovědi a NIKDY nemohl
  // halucinovat model, který nemáme, nebo tvrdit "nemáme" o modelu, který máme.
  parts.push(formatFleetSnapshot(fleet))
  // Live snapshot poboček — režim výdeje/vrácení (samoobslužná vs. obslužná) musí model
  // znát od první odpovědi; paušální „výdej je samoobslužný a nonstop" byl reálný incident.
  parts.push(formatBranchesSnapshot(branches))
  // Kontext aktuální stránky — vyšší priorita než obecný brain,
  // protože uživatel mluví typicky o tom, na co se právě dívá.
  const pageCtxStr = formatPageContext(pageCtx)
  // page context NEDÁVÁME do statického (cachovaného) prefixu — mění se per request/stránku;
  // přijde až do odděleného necachovaného bloku na konci (viz return).
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
  if (kb) parts.push(kb)
  if (cfg.knowledge_extra && cfg.knowledge_extra.trim()) {
    parts.push('AKTUÁLNÍ ZNALOSTI Z VELÍNU (sezonní akce, novinky, ad-hoc info — vyšší priorita než ostatní brain, pokud kolidují):\n' + cfg.knowledge_extra.trim())
  }
  const ctPhone = company.phone || '+420 774 256 271'
  const ctEmail = company.email || 'info@motogo24.cz'
  const ctWeb = company.web || 'https://www.motogo24.cz'
  parts.push(`KONTAKTY (DAVAT JEN NA VYZADANI ČLOVĚKA / SOS / PRÁVO): telefon ${ctPhone}, email ${ctEmail}, web ${ctWeb}.`)
  parts.push(langInstr)

  // Prompt caching: statický prefix (pravidla + znalostní báze + brain + datum + flotila) jde do
  // cachovaného bloku, volatilní KONTEXT STRÁNKY za něj jako necachovaný blok. Na dražším modelu
  // (Sonnet + myšlení) to srazí náklady i latenci — opakované requesty čtou prefix z cache (~10 %).
  const blocks: Array<{ type: 'text'; text: string; cache_control?: { type: 'ephemeral' } }> = [
    { type: 'text', text: parts.join('\n\n'), cache_control: { type: 'ephemeral' } },
  ]
  if (pageCtxStr) blocks.push({ type: 'text', text: pageCtxStr })
  return blocks
}

// ============================================================================
// Anthropic loop
// ============================================================================

async function runClaudeLoop(
  messages: Array<{ role: string; content: unknown }>,
  system: unknown,
  maxTokens: number,
  lang: string = 'cs',
  maxIters = 6,
): Promise<{ reply: string; toolUses: Array<{ name: string; input: Record<string, unknown>; result: unknown }> }> {
  const toolUses: Array<{ name: string; input: Record<string, unknown>; result: unknown }> = []
  const apiMessages: Array<{ role: string; content: unknown }> = [...messages]
  // Celkový wall-clock strop pro celou tool-use smyčku. Edge funkce má omezený běh; když ho překročí,
  // platforma ji zabije UPROSTŘED → widget dostane prázdno/chybu („něco se zaseklo") a konverzace umře.
  // Radši se zastavíme sami a vrátíme slušnou hlášku, než aby nás zabil runtime.
  const deadline = Date.now() + 110_000
  // Fallback při timeoutu/chybě: NEŽÁDÁ zákazníka o zopakování zprávy — celou historii drží
  // widget i server, takže stačí libovolná další zpráva („pokračuj") a agent naváže. Dřívější
  // „pošli poslední zprávu znovu" nutilo zákazníka opakovat se (viz analýza reálné konverzace).
  const fb = lang.startsWith('en')
    ? 'Sorry — that took too long on my side. Just type "continue" — I remember our whole conversation and will pick up right where we left off, no need to repeat anything.'
    : lang.startsWith('de')
      ? 'Sorry — das hat bei mir gerade zu lange gedauert. Schreib einfach „weiter“ — ich habe unser ganzes Gespräch im Kopf und mache genau dort weiter, du musst nichts wiederholen.'
      : 'Promiň, tohle mi teď na mé straně trvalo moc dlouho. Napiš prosím jen „pokračuj" — celou naši konverzaci si pamatuju a navážu přesně tam, kde jsme skončili. Nemusíš nic opakovat.'
  // Dovětek k odpovědi uříznuté limitem tokenů (stop_reason max_tokens i po navýšení stropu).
  const truncNote = lang.startsWith('en')
    ? '\n\n*(The reply got cut off — type "continue" and I\'ll finish the rest.)*'
    : lang.startsWith('de')
      ? '\n\n*(Die Antwort wurde abgeschnitten — schreib „weiter“ und ich ergänze den Rest.)*'
      : '\n\n*(Odpověď se nevešla celá — napiš „pokračuj" a dopovím zbytek.)*'

  for (let iter = 0; iter < maxIters; iter++) {
    if (Date.now() > deadline) return { reply: fb, toolUses }
    // Retry až 3× na 429/5xx/timeout/síťovou chybu — Anthropic občas vrátí transientní chybu.
    let resp: Response | null = null
    let lastErr = ''
    for (let attempt = 0; attempt < 3; attempt++) {
      if (Date.now() > deadline) break
      const ctrl = new AbortController()
      const timer = setTimeout(() => ctrl.abort(), 45_000) // per-call timeout, ať jeden zatuhlý call nezablokuje vše
      try {
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
            thinking: ANTHROPIC_THINKING,
            // effort 'medium' drží kvalitu Sonnetu, ale omezuje přemýšlení i počet tool callů
            // → výrazně nižší latence a spolehlivost (default 'high' chat zpomaloval do timeoutů).
            output_config: { effort: 'medium' },
            system: system,
            tools: PUBLIC_TOOLS,
            messages: apiMessages,
          }),
          signal: ctrl.signal,
        })
      } catch (e) {
        // abort (timeout) nebo síťová chyba → retry s backoffem
        resp = null
        lastErr = `fetch_failed: ${(e as Error).message}`
        clearTimeout(timer)
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1) ** 2))
        continue
      }
      clearTimeout(timer)
      if (resp.ok) break
      lastErr = await resp.text()
      if (resp.status >= 500 || resp.status === 429) {
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1) ** 2))
        continue
      }
      break
    }
    if (!resp || !resp.ok) {
      // Po vyčerpání pokusů NEHÁZEJ výjimku (serve by vrátil 500 → widget „něco se zaseklo" a uživatel
      // zůstane viset). Vrať slušnou hlášku; konverzace zůstane živá a další zpráva může projít.
      console.error('ai-public-agent: Anthropic call failed', resp?.status || 'no-resp', String(lastErr).slice(0, 300))
      return { reply: fb, toolUses }
    }
    const data = await resp.json() as { content: Array<Record<string, unknown>>; stop_reason: string }

    // Odpověď uříznutá limitem tokenů (adaptivní thinking se do max_tokens počítá, takže nízký
    // strop usekne tabulku uprostřed řádku — viděno v reálných konverzacích). Jednou to zopakuj
    // s maximálním stropem; pokud nezbývá čas, nech doběhnout normální zpracování níže.
    if (data.stop_reason === 'max_tokens' && maxTokens < 8000 && Date.now() < deadline - 20_000) {
      maxTokens = 8000
      continue
    }

    if (data.stop_reason === 'tool_use') {
      const toolBlocks = data.content.filter((b) => b.type === 'tool_use')
      apiMessages.push({ role: 'assistant', content: data.content })
      const toolResults: Array<Record<string, unknown>> = []
      for (const tb of toolBlocks) {
        const result = await execPublicTool(String(tb.name), tb.input as Record<string, unknown>, lang)
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
    // I když model kvůli max_tokens skončí jen s thinking blokem (prázdný text), NEVRACEJ prázdno —
    // widget by `reply || error` ukázal „něco se zaseklo". Radši slušná výzva k zopakování.
    if (!reply) return { reply: fb, toolUses }
    // Uříznutý text (i po navýšení stropu) — přiznej to a naveď na „pokračuj" místo tichého useknutí.
    return { reply: data.stop_reason === 'max_tokens' ? reply + truncNote : reply, toolUses }
  }
  return { reply: fb, toolUses }
}

// Sestaví historii konverzace pro Claude. Cíl: agent si pamatuje CELOU vedenou konverzaci,
// ne jen pár posledních zpráv (dřív se tvrdě usekávalo na `slice(-20)` → ztráta staršího
// kontextu uprostřed delšího chatu). Sonnet 4.6 má 1M kontext, takže se vejde i dlouhá konverzace.
// Widget posílá celou historii (drží ji i v sessionStorage), tady jen přidáme pojistky proti
// zneužití/nákladům — `messages` chodí z anonymního widgetu a řídí je klient:
//   - jen role user/assistant s neprázdným stringovým obsahem,
//   - každá zpráva ořezaná na 8000 znaků (shodně s persistencí),
//   - celkový rozpočet ~240k znaků (~80k tokenů) — při přetečení se zahazují NEJSTARŠÍ zprávy,
//   - tvrdý strop 400 zpráv,
//   - historie musí začínat 'user' zprávou (Anthropic API to vyžaduje) → odřízneme úvodní assistant tahy.
function buildHistory(
  messages: Array<{ role: string; content: string }>,
): Array<{ role: string; content: string }> {
  const MAX_MSGS = 400
  const PER_MSG_CHARS = 8000
  const TOTAL_CHARS = 240_000
  let hist = messages
    .filter((m) => (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string' && m.content.trim() !== '')
    .map((m) => ({ role: m.role, content: m.content.length > PER_MSG_CHARS ? m.content.slice(0, PER_MSG_CHARS) : m.content }))
  if (hist.length > MAX_MSGS) hist = hist.slice(-MAX_MSGS)
  // Rozpočet znaků — zahazuj nejstarší zprávy, dokud se nevejdeme (poslední kontext je nejdůležitější).
  let total = hist.reduce((s, m) => s + m.content.length, 0)
  while (hist.length > 1 && total > TOTAL_CHARS) {
    total -= hist[0].content.length
    hist.shift()
  }
  // Anthropic API vyžaduje, aby konverzace začínala 'user' zprávou.
  while (hist.length && hist[0].role !== 'user') hist.shift()
  return hist
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
    // session_id ze widgetu — stabilní napříč navigací, používá se pro upsert do ai_public_conversations.
    // Když chybí (starý widget cache, partner integrace), vygenerujeme nový — log se neztratí.
    const rawSession = typeof body.session_id === 'string' ? body.session_id : ''
    const sessionId = /^[0-9a-f-]{8,40}$/i.test(rawSession) ? rawSession : crypto.randomUUID()

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: 'Missing messages' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }
    const recent = buildHistory(messages)

    // Fotky budíků/kontrolek z widgetu (max 3) — připnou se k POSLEDNÍ user zprávě
    // jako content blocks JEN pro volání API; do logu konverzace jde textový marker
    // „[N× foto]" (base64 do ai_public_conversations nepatří).
    const imgs = (Array.isArray(body.images) ? body.images : [])
      .filter((i: Record<string, unknown>) => typeof i?.base64 === 'string' && /^image\//.test(String(i?.media_type || '')))
      .slice(0, 3) as Array<{ base64: string; media_type: string }>
    let apiRecent: Array<{ role: string; content: unknown }> = recent
    if (imgs.length > 0 && recent.length > 0 && recent[recent.length - 1].role === 'user') {
      const lastText = recent[recent.length - 1].content
      apiRecent = [
        ...recent.slice(0, -1),
        { role: 'user', content: [
          ...imgs.map((i) => ({ type: 'image', source: { type: 'base64', media_type: i.media_type, data: i.base64 } })),
          { type: 'text', text: lastText },
        ] },
      ]
      recent[recent.length - 1] = { role: 'user', content: `[${imgs.length}× foto] ${lastText}` }
    }

    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: 'AI agent je dočasně nedostupný (chybí klíč). Zkus to za chvíli, nebo napiš dotaz formulářem na webu.' }), {
        status: 503, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // Config + znalostní báze (FAQ/VOP/smlouva/GDPR/podmínky) paralelně. KB se drží v module cache s TTL.
    const [{ cfg, company, fleet, branches }, kb] = await Promise.all([loadConfig(), loadKnowledgeBase(sb, lang)])
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

    const systemBlocks = buildSystemPrompt(lang, cfg, company, fleet, branches, pageCtx, kb)
    // Fotky: nový widget posílá supports_images=true a má tlačítko 📷 — agent smí o fotku
    // AKTIVNĚ požádat. Starý widget (cache prohlížeče) tlačítko nemá — tam o fotku nežádat.
    systemBlocks.push({
      type: 'text',
      text: body.supports_images === true
        ? 'FOTKY OD ZÁKAZNÍKA: widget umí přiložit až 3 fotky (tlačítko 📷 u pole zprávy). Když si nejsi jistý, kterou kontrolku zákazník vidí nebo jak vypadá problém, AKTIVNĚ ho popros o fotku budíků / přístrojové desky. Došlou fotku vyhodnoť: popiš, co na ní vidíš, a význam kontrolek VŽDY ověř v návodu té motorky (get_motorcycle_manual) — nikdy jen „od oka".'
        : 'FOTKY OD ZÁKAZNÍKA: tato verze widgetu přílohy NEUMÍ — o fotku NEŽÁDEJ, doptávej se slovně. Když fotka přesto přijde, vyhodnoť ji.',
    })
    // S adaptivním myšlením se thinking tokeny počítají do max_tokens — proto vyšší strop i floor,
    // ať zbyde prostor na myšlení i na samotnou odpověď (nízký limit by odpověď uřízl uprostřed).
    // Cap držíme na 8000, ať edge fn nenarazí na wall-clock limit a non-streaming fetch nevytimeoutuje.
    // Default 5000 (dřív 2048): thinking tokeny se počítají do max_tokens, takže nízký strop
    // usekával tabulky uprostřed řádku. Floor 2048 chrání i před příliš nízkou hodnotou z Velínu.
    const maxTokens = Math.min(Math.max(Number(cfg.max_tokens) || 5000, 2048), 8000)
    const { reply, toolUses } = await runClaudeLoop(apiRecent, systemBlocks, maxTokens, lang)

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

    // Uložíme kompletní konverzaci včetně právě vygenerované assistant odpovědi.
    const fullConv = recent.concat([{ role: 'assistant', content: reply }])
    void persistConversation(
      sessionId, fullConv, lang, pageCtx, ip, ua,
      bookingCreated ? 'booking_created' : 'view',
      bookingCreated,
    )

    return new Response(JSON.stringify({ reply, tool_uses: toolUses, booking_url: bookingUrl, session_id: sessionId }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    void logTraffic(null, 500, Date.now() - startedAt, 'error', ip, ua)
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
