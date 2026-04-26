/**
 * MotoGo24 — Edge Function: Public AI Agent (booking widget backend)
 *
 * Anonymní AI asistent pro zákazníky na motogo24.cz. Volá Anthropic Claude
 * a má read-only přístup k motorkám/pobočkám/FAQ + akce (kalkulace ceny,
 * vytvoření rezervace).
 *
 * Bez JWT (anonymní). Rate-limit per IP.
 *
 * POST body:
 *   { messages: [{role, content}], lang?: 'cs'|'en'|... }
 *
 * Response (streaming JSON nebo single response):
 *   { reply, tool_calls?, suggestions?, conversation_id? }
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const ANTHROPIC_MODEL = 'claude-haiku-4-5-20251001'  // rychlý + levný pro veřejný widget

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

// In-memory rate limiter
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

async function logTraffic(toolName: string | null, statusCode: number, latencyMs: number, outcome: string, ip: string, ua: string) {
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
    })
  } catch { /* silent */ }
}

// ============================================================================
// Tools — interní (Claude je volá, výsledky se vrací do Claude loop)
// ============================================================================

const PUBLIC_TOOLS = [
  {
    name: 'search_motorcycles',
    description: 'Vyhledej motorky v MotoGo24 katalogu podle kategorie, ŘP, výkonu nebo ceny. Použij když uživatel hledá motorku k pronájmu.',
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
    description: 'Zkontroluj obsazené termíny pro motorku. Použij PŘED kalkulací.',
    input_schema: {
      type: 'object',
      properties: { moto_id: { type: 'string' } },
      required: ['moto_id'],
    },
  },
  {
    name: 'calculate_price',
    description: 'Vypočítá přesnou cenu pronájmu pro motorku a termín. NEvytváří rezervaci.',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' }, start_date: { type: 'string' }, end_date: { type: 'string' },
        promo_code: { type: 'string' },
      },
      required: ['moto_id', 'start_date', 'end_date'],
    },
  },
  {
    name: 'get_faq',
    description: 'Získá odpovědi z FAQ podle klíčového slova (cena, kauce, řidičák, výbava, zahraničí, storno...).',
    input_schema: {
      type: 'object',
      properties: { query: { type: 'string' } },
    },
  },
  {
    name: 'redirect_to_booking',
    description: 'Vygeneruj URL na rezervační formulář s předvyplněnými údaji. Po dokončení v UI uživatel klikne na odkaz a sám dokončí. NIKDY nevytvářej rezervaci přímo přes tento nástroj — pošli odkaz a uživatel ji potvrdí na webu.',
    input_schema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' }, start_date: { type: 'string' }, end_date: { type: 'string' },
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
    case 'redirect_to_booking': {
      const params = new URLSearchParams()
      if (args.moto_id) params.set('moto', String(args.moto_id))
      if (args.start_date) params.set('start', String(args.start_date))
      if (args.end_date) params.set('end', String(args.end_date))
      return {
        url: `https://motogo24.cz/rezervace?${params}`,
        instruction: 'Pošli uživateli tento odkaz s pozváním k dokončení rezervace na webu (kde vyplní jméno, email, doklady).',
      }
    }
    default:
      return { error: `Unknown tool: ${name}` }
  }
}

// ============================================================================
// System prompt
// ============================================================================

function buildSystemPrompt(lang: string): string {
  const langMap: Record<string, string> = {
    cs: 'Odpovídej česky.', en: 'Reply in English.', de: 'Antworte auf Deutsch.',
    es: 'Responde en español.', fr: 'Réponds en français.', nl: 'Antwoord in het Nederlands.', pl: 'Odpowiadaj po polsku.',
  }
  const langInstr = langMap[lang] || langMap.cs
  return `Jsi přátelský AI asistent půjčovny motorek MotoGo24 (Mezná 9, 393 01 Pelhřimov, Vysočina, Česko).
Pomáháš zákazníkům najít motorku, spočítat cenu, odpovídat na dotazy o pronájmu a navést je na rezervační formulář.

KLÍČOVÁ FAKTA O MOTOGO24:
- Bez kauce, bez skrytých poplatků
- Motorkářská výbava (helma, bunda, kalhoty, rukavice) v ceně
- Nonstop provoz 24/7, 365 dní v roce
- Pojištění (povinné ručení) v ceně
- Sjezd do zahraničí povolen, zelená karta v ceně
- Online rezervace s platbou kartou (Stripe)
- Telefon: +420 774 256 271, email: info@motogo24.cz

PRAVIDLA:
1. NIKDY si nevymýšlej fakta o cenách, dostupnosti nebo motorkách — vždy zavolej příslušný nástroj.
2. Před kalkulací ceny ZKONTROLUJ dostupnost (get_availability).
3. Při doporučení motorky uveď: model, kategorii, výkon, cenu od/den, ŘP, URL.
4. Rezervaci NIKDY nevytváříš sám — vždy vygeneruj odkaz na /rezervace?moto=...&start=...&end=... přes redirect_to_booking a pozvi uživatele dokončit ji na webu.
5. Buď stručný a přátelský. Používej max 3-4 odstavce. Žádné markdown tabulky — jednoduchý text.
6. Pokud nevíš → upřímně to řekni a nasměruj na +420 774 256 271 nebo info@motogo24.cz.

${langInstr}`
}

// ============================================================================
// Anthropic API loop
// ============================================================================

async function runClaudeLoop(
  messages: Array<{ role: string; content: unknown }>,
  systemPrompt: string,
  maxIters = 5
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
        max_tokens: 1024,
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
  return { reply: 'Omlouvám se, dostal jsem se do smyčky. Zkus prosím přeformulovat otázku, nebo nás kontaktuj na +420 774 256 271.', toolUses }
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
    // Limit historie na 20 zpráv pro rychlost + náklady
    const recent = messages.slice(-20).filter((m) => m.role === 'user' || m.role === 'assistant')

    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: 'AI agent dočasně nedostupný. Zavolejte +420 774 256 271.' }), {
        status: 503, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const systemPrompt = buildSystemPrompt(lang)
    const { reply, toolUses } = await runClaudeLoop(recent, systemPrompt)

    const latency = Date.now() - startedAt
    void logTraffic(null, 200, latency, 'view', ip, ua)
    for (const tu of toolUses) {
      void logTraffic(tu.name, 200, latency, tu.name === 'redirect_to_booking' ? 'quote' : 'view', ip, ua)
    }

    return new Response(JSON.stringify({ reply, tool_uses: toolUses }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    void logTraffic(null, 500, Date.now() - startedAt, 'error', ip, ua)
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
