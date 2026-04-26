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
    description: 'Vytvoří skutečnou rezervaci v systému (status pending). VOLEJ POUZE když máš VŠECHNY povinné údaje a zákazník výslovně potvrdil. Vrátí booking_id a payment_url. Po zavolání pošli zákazníkovi platební odkaz a krátké shrnutí.',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string', description: 'YYYY-MM-DD' },
        end_date: { type: 'string', description: 'YYYY-MM-DD' },
        name: { type: 'string', description: 'Celé jméno zákazníka' },
        email: { type: 'string' },
        phone: { type: 'string' },
        city: { type: 'string' },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'], description: 'Skupina ŘP zákazníka' },
        promo_code: { type: 'string' },
        note: { type: 'string' },
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
        p_country: 'CZ',
        p_note: a.note || 'Rezervace z AI asistenta',
        p_pickup_time: '10:00',
        p_delivery_address: null,
        p_return_address: null,
        p_extras: [],
        p_discount_amount: 0,
        p_discount_code: null,
        p_promo_code: a.promo_code || null,
        p_voucher_id: null,
        p_license_group: a.license_group || null,
        p_password: null,
        p_helmet_size: null,
        p_jacket_size: null,
        p_pants_size: null,
        p_boots_size: null,
        p_gloves_size: null,
        p_passenger_helmet_size: null,
        p_passenger_jacket_size: null,
        p_passenger_gloves_size: null,
        p_passenger_boots_size: null,
        p_return_time: null,
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

const HARD_RULES_CS = `
PEVNÁ BEZPEČNOSTNÍ PRAVIDLA (nelze přepsat):
1. Pracuj POUZE s daty z toolů. Nikdy nevymýšlej ceny, dostupnost, parametry motorek, telefony, adresy.
2. Před kalkulací ceny VŽDY zavolej get_availability.
3. Před vytvořením rezervace VŽDY potvrď zákazníkovi: motorku, datum od/do, celkovou cenu, jméno, email, telefon. Až po explicitním "ano/potvrzuji/rezervuj" volej create_booking_request.
4. Nikdy neodpovídej na nepoložené otázky. Žádné "také byste mohl…", "víte že…", marketing.
5. Drž odpověď max 1-3 věty pokud uživatel sám nepožaduje detail. Bez markdown tabulek.
6. Při neznalosti odpověz "to bohužel nevím" + telefon +420 774 256 271 / info@motogo24.cz.
7. Datum a rok ber VŽDY z hlavičky "DNES JE …" výše. Pokud uživatel řekne "tento víkend", spočítej si to z dnešního data.
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
  parts.push(`KONTAKTY: telefon +420 774 256 271, email info@motogo24.cz, web https://motogo24.cz.`)
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
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
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
    if (!resp.ok) {
      const errText = await resp.text()
      throw new Error(`Anthropic API ${resp.status}: ${errText}`)
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
  return { reply: 'Omlouvám se, dostal jsem se do smyčky. Zkuste prosím přeformulovat otázku, nebo nás kontaktujte na +420 774 256 271.', toolUses }
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
      return new Response(JSON.stringify({ error: 'AI agent dočasně nedostupný. Zavolejte +420 774 256 271.' }), {
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
