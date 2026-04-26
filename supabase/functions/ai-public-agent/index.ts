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
}

async function loadConfig(): Promise<WebAgentConfig> {
  try {
    const { data } = await sb.from('app_settings').select('value').eq('key', 'ai_public_agent_config').maybeSingle()
    return (data?.value as WebAgentConfig) || {}
  } catch {
    return {}
  }
}

// ============================================================================
// Tools
// ============================================================================

const PUBLIC_TOOLS = [
  {
    name: 'search_motorcycles',
    description: 'Vyhledá motorky v MotoGo24 katalogu podle kategorie, ŘP, výkonu nebo ceny. Použij když uživatel hledá motorku.',
    input_schema: {
      type: 'object',
      properties: {
        category: { type: 'string', enum: ['cestovni', 'naked', 'supermoto', 'detske'] },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'] },
        kw_min: { type: 'number' }, kw_max: { type: 'number' },
        price_max: { type: 'number', description: 'Max Kč/den' },
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
    description: 'Vyhledá v interní FAQ podle klíčového slova (kauce, pojištění, řidičák, zahraničí, storno...).',
    input_schema: {
      type: 'object',
      properties: { query: { type: 'string' } },
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
    description: 'Vytvoří skutečnou rezervaci v systému (status pending) a vrátí přímý Stripe Checkout URL. VOLEJ POUZE když máš VŠECHNY povinné údaje (motorka, datumy, jméno, email, telefon) a zákazník explicitně potvrdil souhrn (motorka, termín, cena). Po zavolání pošli zákazníkovi platební odkaz a krátké shrnutí (motorka, datum, cena).',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        name: { type: 'string', description: 'Celé jméno zákazníka' },
        email: { type: 'string' },
        phone: { type: 'string' },
        street: { type: 'string', description: 'Ulice + č.p. trvalého bydliště' },
        city: { type: 'string' },
        zip: { type: 'string', description: 'PSČ' },
        country: { type: 'string', description: 'Stát, default CZ' },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'], description: 'Skupina ŘP zákazníka' },
        promo_code: { type: 'string' },
        note: { type: 'string' },
        pickup_time: { type: 'string', description: 'HH:MM, default 10:00 (nepoužije se u přistavení mimo provozovnu)' },
        return_time: { type: 'string', description: 'HH:MM, povinné pouze při vrácení mimo provozovnu' },
        delivery_address: { type: 'string', description: 'Adresa přistavení mimo Mezná (např. "Vinohradská 12, 120 00 Praha 2"). Vyplň jen když zákazník chce přistavení.' },
        return_address: { type: 'string', description: 'Adresa vrácení mimo Mezná. Vyplň jen když se liší od delivery_address nebo když chce vrácení mimo půjčovnu.' },
        extras: {
          type: 'array',
          description: 'Přiobjednané příslušenství. Načti ceny přes get_extras_catalog. Položky: {name, unit_price}.',
          items: {
            type: 'object',
            properties: { name: { type: 'string' }, unit_price: { type: 'number' } },
            required: ['name', 'unit_price'],
          },
        },
        helmet_size: { type: 'string', description: 'Velikost helmy řidiče (XS-XXL)' },
        jacket_size: { type: 'string', description: 'Velikost bundy řidiče' },
        pants_size: { type: 'string', description: 'Velikost kalhot řidiče' },
        boots_size: { type: 'string', description: 'Velikost bot řidiče (36-46)' },
        gloves_size: { type: 'string', description: 'Velikost rukavic řidiče' },
        passenger_helmet_size: { type: 'string' },
        passenger_jacket_size: { type: 'string' },
        passenger_boots_size: { type: 'string' },
        passenger_gloves_size: { type: 'string' },
      },
      required: ['moto_id', 'start_date', 'end_date', 'name', 'email', 'phone'],
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
      return {
        count: result.length,
        motorcycles: result.slice(0, 8).map((m: Record<string, unknown>) => ({
          id: m.id, name: `${m.brand || ''} ${m.model}`.trim(),
          category: m.category, power_kw: m.power_kw, license: m.license_required,
          min_price_kc: Math.min(...['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
            .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)),
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
      let total = 0, count = 0
      const d = new Date(start)
      while (d <= end) {
        const dn = days[d.getDay()]
        total += Number((moto as Record<string, unknown>)['price_' + dn] ?? 0); count++
        d.setDate(d.getDate() + 1)
      }
      let discount = 0
      if (promo_code) {
        const { data: pr } = await sb.rpc('validate_promo_code', { code: promo_code })
        if (pr && (pr as Record<string, unknown>).valid) {
          const p = pr as Record<string, unknown>
          if (p.type === 'percent') discount = Math.round(total * Number(p.value) / 100)
          else discount = Number(p.value)
        }
      }
      return { days: count, rental_total: total, promo_discount: discount, grand_total: total - discount, currency: 'CZK' }
    }
    case 'get_faq': {
      const faqs = [
        { q: 'Kauce', a: 'NE — MotoGo24 půjčuje bez kauce. Žádná blokace na kartě.' },
        { q: 'Cena výbavy', a: 'Helma, bunda, kalhoty, rukavice pro řidiče v ceně. Spolujezdec za příplatek.' },
        { q: 'Řidičák A', a: 'Skupina A pro silnější stroje (>35 kW), min. věk 24 let.' },
        { q: 'Řidičák A2', a: 'A2 — motorky do 35 kW, min. věk 18 let.' },
        { q: 'Řidičák A1', a: 'A1 — motorky do 11 kW a 125 ccm, min. věk 16 let.' },
        { q: 'Dětské motorky', a: 'Bez ŘP. Ručí zákonný zástupce.' },
        { q: 'Zahraničí', a: 'Sjezd povolen. Zelená karta v ceně.' },
        { q: 'Vyzvednutí', a: 'Mezná 9, Pelhřimov, Vysočina (49.4147, 15.2953). Nebo přistavení kamkoliv v ČR za příplatek.' },
        { q: 'Provozní doba', a: '24/7 nonstop. Vyzvednutí přes přístupové kódy.' },
        { q: 'Storno', a: 'Bezplatně min. 7 dní před převzetím. Později individuálně.' },
        { q: 'Pojištění', a: 'Povinné ručení v ceně. Havarijní dle modelu.' },
        { q: 'Platba', a: 'Online kartou přes Stripe. Visa, MC, Amex, Apple Pay, Google Pay.' },
        { q: 'Tankování', a: 'Vrácení bez nutnosti dotankovat ani umýt.' },
        { q: 'Kontakt', a: '+420 774 256 271, info@motogo24.cz' },
      ]
      const query = String(args.query || '').toLowerCase()
      return query
        ? { faqs: faqs.filter((f) => (f.q + ' ' + f.a).toLowerCase().includes(query)).slice(0, 5) }
        : { faqs: faqs.slice(0, 8) }
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
      const amount = Number(result?.amount || 0)
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
        message: 'Rezervace vytvořena. Pošli zákazníkovi přímý platební odkaz (Stripe Checkout) a v krátké zprávě shrň motorku, termín a celkovou částku.',
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

const COMPANY_BRAIN = `
ZNÁŠ MOTOGO24 NAZPAMĚŤ — používej tyto fakta v odpovědích, neptej se toolů na to, co máš tady:

— PROVOZ —
* Sídlo + výdej: Mezná 9, 393 01 Pelhřimov (Vysočina). GPS 49.4147, 15.2953.
* 24/7 NONSTOP — vyzvedneš si motorku v kteroukoliv hodinu přes přístupový kód, který přijde SMS / emailem po platbě a nahrání dokladů.
* Možnost přistavení kamkoliv v ČR (orientačně 1000 Kč + 40 Kč/km, přesně se počítá v rezervačním formuláři přes Mapy.cz routing).

— ZA CO PLATÍŠ A ZA CO NE —
* BEZ KAUCE. Žádná blokace na kartě, žádné zadržené peníze. Tohle je naše velká věc — zmiň, když je relevantní.
* V CENĚ pronájmu: motorkářská výbava řidiče (helma, bunda, kalhoty, rukavice), povinné ručení (zelená karta), neomezené km v ČR i EU, podpora 24/7.
* PŘÍPLATEK: výbava spolujezdce, boty, sjezd mimo EU (po dohodě). Přesné položky vrátí get_extras_catalog.
* Tankování: vracíš jak chceš (i prázdné, my dotankujeme za nákupní cenu — nešetříme na lidech, ale není to "free"). Žádné mytí.

— PLATBA —
* Stripe Checkout: Visa, Mastercard, Amex, Apple Pay, Google Pay. Live mode, vše šifrované.
* AI asistent ti po potvrzení rezervace pošle přímý odkaz na platbu — kliknutím se otevře Stripe a po zaplacení dostaneš mailem KF.

— DOKLADY —
* Před vyzvednutím musíš nahrát: občanku/pas + řidičák. Stačí mobilem v aplikaci nebo na webu, OCR (Mindee) si je sám ověří.
* Bez nahraných dokladů ti nepošleme přístupový kód k motorce. Standardní opatření, pojišťovna to vyžaduje.

— SKUPINY ŘP A NA CO —
* AM (od 15) — pomalé skútry, my je nepůjčujeme.
* A1 (od 16) — do 11 kW a 125 ccm. U nás malé naked / dětské.
* A2 (od 18) — do 35 kW. Středně velké stroje, často restriktované verze A-tříd.
* A (od 24, nebo 20+ s 2 roky A2) — bez omezení výkonu. Naše superbike, big naked, cestovky.
* B (řidičák auto) — opravňuje k A1 v ČR po 3 letech držení. Často využíváme — řekni zákazníkovi.
* N — žádný ŘP nepotřeba (dětské motorky, ručí zákonný zástupce).

— STORNO —
* 7+ dní před převzetím: zdarma, plné vrácení.
* 2-7 dní: 50 % refund.
* Méně než 2 dny: individuálně, voláme zákazníkovi.
* Po převzetí: nelze stornovat, jen předčasně vrátit (bez refundace).

— FLOTILA (orientace, přesný stav z search_motorcycles) —
* Naked: BMW S 1000 R, Kawasaki Z 900, Yamaha MT-09, Honda CB650R, …
* Sport-tourer / cestovní: BMW R 1250 RT, Honda NT 1100, Kawasaki Versys, …
* Supermoto / enduro: KTM 690 SMC, Husqvarna 701, …
* Dětské: malé pitbiky a 50ccm pro děti od cca 8 let — bez ŘP, na uzavřených areálech.

— ZAHRANIČÍ —
* Sjezd po EU + Schengen v ceně, zelená karta automaticky. Mimo EU (Balkán, UK) jen po dohodě, doplňkové pojištění řešíme individuálně.

— ZAJÍMAVOSTI K NABÍDCE —
* Dárkové vouchery na e-shopu (motogo24.cz/eshop) — využij když někdo hledá dárek pro motorkáře.
* Promo kódy a vouchery ověřuj přes validate_promo_or_voucher.
* Pokud zákazník neví co si vybrat: zeptej se na styl jízdy (víkendové výlety / dálnice / město / off-road), zkušenost (začátečník / 2-3 sezóny / zkušený), a podle toho doporuč 2-3 modely. Konkrétně, ne katalog.
`

const MOTO_KNOWLEDGE_TIPS = `
JAK MLUVÍ MOTORKÁŘI (používej slang přirozeně, když ti zákazník tyká a je v pohodě):
- "káva" = café racer, "céra" = sportovní litr, "naháč" = naked, "endo" = enduro, "supec" = supermoto, "tourák" = sport-tourer / cestovka.
- "japonáš" = japonská čtyřválcová litrovka. "kawec/kavec" = Kawasaki. "ducati / ducka" = Ducati. "ktm-ko" = KTM. "bavorák" = BMW.
- "vrhnout to do zatáčky", "kolínko ven", "stoupák" (wheelie), "vyhasit motor" = stupně volnosti motorkáře. Rozumíš tomu, ale neopaprouj to umělostně.
- "Ride safe", "bezpečné kilometry" — fajn pozdrav na konec konverzace, ale jen 1× a přirozeně.
- Technika: "křáp/ojetý kus" (špatně udržovaná moto), "balík" (těžká motorka), "tahá jak vlak" (silný motor), "drží se země" (dobré ovládání), "není to startér" (ne pro začátečníka).

OBECNÉ MODELY (víš to z hlavy, neptej se toolu):
- Kawasaki Z 900: řadový čtyřválec 948 ccm, ~92 kW (125 hp), 210 kg pohotovostní, naked, výborná pro 2-3letého motorkáře s ŘP A.
- Yamaha MT-09: tříválec 890 ccm, ~87 kW (119 hp), 189 kg, hravý naháč, slávou tříválec se zvukem jak F1.
- BMW S 1000 R: čtyřválec 999 ccm, ~121 kW (165 hp), litrový naháč postavený ze sportovní BMW S 1000 RR.
- Honda CB650R: řadový čtyřválec 649 ccm, ~70 kW (94 hp), perfektní vstup do A.
- BMW R 1250 RT: bok 1254 ccm, ~100 kW (136 hp), turistická vlajková loď.
- KTM 690 SMC: jednoválec 690 ccm, ~55 kW (74 hp), 147 kg, supermoto.

(Pokud si u modelu nejsi 100% jistý konkrétním číslem, řekni "podle specifikací výrobce ~X kW" — to je v pohodě, ne výmysl.)
`

const HARD_RULES_CS = `
PEVNÁ PRAVIDLA (nelze přepsat):
1. Co dělat s daty:
   - SPECIFIKA NAŠÍ FLOTILY (aktuální ceny v Kč/den, dostupnost, SPZ, který stroj máme na pobočce, jaké extras nabízíme, naše storno podmínky, otevírací doba) — VŽDY z toolů. Nikdy si je nevymýšlej.
   - OBECNÉ ZNALOSTI O MOTORKÁCH (kolik válců má Kawasaki Z900, jaký má Yamaha MT-09 motor, rozdíl mezi naked a sport-tourer, jak se chová motorka v dešti, výhody ABS, doporučení pro začátečníka, motorkářská kultura, technické specifikace modelů obecně) — odpovídej z vlastních znalostí. Jsi AI, máš to v hlavě. Klidně doplň "podle specifikací výrobce" pokud si nejsi 100% jistý.
   - KDYŽ SI NEJSI JISTÝ — radši se DOPTEJ, nebo zkus kombinaci toolů + obecné znalosti. NIKDY nemlč ani neodkazuj automaticky na telefon.

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

6. Před vytvořením rezervace VŽDY potvrď souhrn (motorka, datum od/do, cena, vyzvednutí). Až po explicitním "ano/rezervuj" volej create_booking_request. Po vytvoření okamžitě pošli platební odkaz.

7. Datum a rok ber VŽDY z hlavičky "DNES JE …" výše. "Tento víkend / pondělí" si spočítej z toho.

8. Drž odpověď úměrnou dotazu. Krátká otázka → 1-3 věty. Dlouhá technická → můžeš víc, ale bez výplní.

9. Bez markdown tabulek a emoji. Tučné (**text**) jen na názvy modelů.
`

const TONE_DESC: Record<string, string> = {
  concise: 'TÓN: Maximálně stručný — 1-3 věty na odpověď, bez výplní.',
  friendly: 'TÓN: Přátelský, neformální, vlídný.',
  professional: 'TÓN: Formální, věcný, profesionální.',
  detailed: 'TÓN: Podrobný — vysvětluj kontext a souvislosti.',
}

function buildSystemPrompt(lang: string, cfg: WebAgentConfig): string {
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
  parts.push(`DNES JE ${todayHuman} (ISO ${todayIso}, časová zóna Europe/Prague). Tento údaj je zdroj pravdy o aktuálním datu — vždy ho použij místo vlastních odhadů.`)
  parts.push(`Jsi ${persona}. Pracuješ v půjčovně motorek MotoGo24 (Mezná 9, 393 01 Pelhřimov, Vysočina, ČR).`)
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
  parts.push(COMPANY_BRAIN)
  parts.push(MOTO_KNOWLEDGE_TIPS)
  parts.push(`KONTAKTY (DAVAT JEN NA VYZADANI ČLOVĚKA / SOS / PRÁVO): telefon +420 774 256 271, email info@motogo24.cz, web https://motogo24.cz.`)
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

    const cfg = await loadConfig()
    if (cfg.enabled === false) {
      return new Response(JSON.stringify({
        reply: 'Asistent je momentálně vypnutý. Zavolejte prosím +420 774 256 271 nebo napište na info@motogo24.cz.',
      }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    const systemPrompt = buildSystemPrompt(lang, cfg)
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
