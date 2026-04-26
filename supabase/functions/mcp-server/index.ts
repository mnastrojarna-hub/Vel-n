/**
 * MotoGo24 — Edge Function: MCP Server (HTTP Transport)
 *
 * Implementuje Model Context Protocol (MCP) přes HTTP/JSON-RPC 2.0.
 * Specifikace: https://modelcontextprotocol.io/specification/
 *
 * Klient (Claude Desktop / Cursor / Cline / Smithery / vlastní agent) se
 * připojí přes HTTP transport a získá:
 *   - tools/list  → seznam dostupných nástrojů (search, quote, book...)
 *   - tools/call  → vykonat nástroj
 *   - resources/list + resources/read → veřejné MD/JSON zdroje
 *
 * Auth: anonymous pro read tools, optional X-Api-Key pro vyšší rate-limit
 * a write tools (motogo_create_booking).
 *
 * URL pro registraci v Claude Desktop:
 *   {
 *     "mcpServers": {
 *       "motogo24": {
 *         "url": "https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/mcp-server"
 *       }
 *     }
 *   }
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key, mcp-session-id',
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

// ============================================================================
// MCP Protocol — JSON-RPC 2.0
// ============================================================================

interface JsonRpcRequest {
  jsonrpc: '2.0'
  id?: string | number | null
  method: string
  params?: Record<string, unknown>
}

interface JsonRpcResponse {
  jsonrpc: '2.0'
  id: string | number | null
  result?: unknown
  error?: { code: number; message: string; data?: unknown }
}

function rpcOk(id: string | number | null | undefined, result: unknown): JsonRpcResponse {
  return { jsonrpc: '2.0', id: id ?? null, result }
}

function rpcErr(id: string | number | null | undefined, code: number, message: string, data?: unknown): JsonRpcResponse {
  return { jsonrpc: '2.0', id: id ?? null, error: { code, message, ...(data !== undefined ? { data } : {}) } }
}

// ============================================================================
// Tool definitions (MCP tools/list)
// ============================================================================

const TOOLS = [
  {
    name: 'motogo_search_motorcycles',
    description: 'Search MotoGo24 motorcycle catalog. Returns motorcycles available for rental matching the criteria (category, license group, power range, max price). Use this when user asks for motorcycle recommendations.',
    inputSchema: {
      type: 'object',
      properties: {
        category: { type: 'string', enum: ['cestovni', 'naked', 'supermoto', 'detske'], description: 'Motorcycle category' },
        license_group: { type: 'string', enum: ['AM', 'A1', 'A2', 'A', 'B', 'N'], description: 'Required driver license group. N = no license needed (kids motorcycles).' },
        kw_min: { type: 'number', description: 'Minimum engine power in kW' },
        kw_max: { type: 'number', description: 'Maximum engine power in kW' },
        price_max: { type: 'number', description: 'Maximum price per day in CZK' },
      },
    },
  },
  {
    name: 'motogo_get_motorcycle',
    description: 'Get detailed info about a specific motorcycle including full specs, daily prices and pickup branch.',
    inputSchema: {
      type: 'object',
      properties: { moto_id: { type: 'string', description: 'Motorcycle UUID' } },
      required: ['moto_id'],
    },
  },
  {
    name: 'motogo_get_availability',
    description: 'Get booked date ranges for a motorcycle. Use this BEFORE quoting/booking to verify date availability.',
    inputSchema: {
      type: 'object',
      properties: { moto_id: { type: 'string', description: 'Motorcycle UUID' } },
      required: ['moto_id'],
    },
  },
  {
    name: 'motogo_quote',
    description: 'Calculate exact rental price for a motorcycle and date range. Returns per-day breakdown, extras total, promo discount. Does NOT create a booking.',
    inputSchema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string', description: 'Motorcycle UUID' },
        start_date: { type: 'string', format: 'date', description: 'Pickup date (YYYY-MM-DD)' },
        end_date: { type: 'string', format: 'date', description: 'Return date (YYYY-MM-DD), inclusive' },
        extras: { type: 'array', items: { type: 'object' }, description: 'Optional extras [{name, unit_price}]' },
        promo_code: { type: 'string', description: 'Optional promo code' },
      },
      required: ['moto_id', 'start_date', 'end_date'],
    },
  },
  {
    name: 'motogo_create_booking',
    description: 'Create a booking. Returns booking_id and Stripe payment_url for the customer. Customer completes payment on payment_url. ALWAYS confirm with user before calling — this creates a real reservation.',
    inputSchema: {
      type: 'object',
      properties: {
        moto_id: { type: 'string' },
        start_date: { type: 'string', format: 'date' },
        end_date: { type: 'string', format: 'date' },
        customer_name: { type: 'string' },
        customer_email: { type: 'string', format: 'email' },
        customer_phone: { type: 'string' },
        license_group: { type: 'string', enum: ['AM','A1','A2','A','B','N'] },
        pickup_time: { type: 'string', description: 'HH:MM' },
        delivery_address: { type: 'string', description: 'Optional — delivery anywhere in CZ' },
        return_address: { type: 'string', description: 'Optional — return at different location' },
        extras: { type: 'array', items: { type: 'object' } },
        promo_code: { type: 'string' },
        note: { type: 'string' },
      },
      required: ['moto_id', 'start_date', 'end_date', 'customer_name', 'customer_email', 'customer_phone'],
    },
  },
  {
    name: 'motogo_get_branches',
    description: 'List MotoGo24 rental branches with address and GPS coordinates. Currently 1 branch in Mezná near Pelhřimov, Vysočina.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'motogo_get_faq',
    description: 'Get the FAQ entries (questions + answers) about MotoGo24 rental policies. Optional query filters by keyword.',
    inputSchema: {
      type: 'object',
      properties: { query: { type: 'string', description: 'Optional keyword filter' } },
    },
  },
  {
    name: 'motogo_validate_promo',
    description: 'Validate a promo code. Returns {valid, type, value} if active, {valid:false} otherwise.',
    inputSchema: {
      type: 'object',
      properties: { code: { type: 'string' } },
      required: ['code'],
    },
  },
  {
    name: 'motogo_validate_voucher',
    description: 'Validate a gift voucher code.',
    inputSchema: {
      type: 'object',
      properties: { code: { type: 'string' } },
      required: ['code'],
    },
  },
]

const RESOURCES = [
  { uri: 'motogo://about',         name: 'About MotoGo24',          mimeType: 'text/markdown' },
  { uri: 'motogo://motorcycles',   name: 'Full motorcycle catalog', mimeType: 'application/json' },
  { uri: 'motogo://branches',      name: 'Rental branches',         mimeType: 'application/json' },
  { uri: 'motogo://faq',           name: 'FAQ — rental policies',   mimeType: 'text/markdown' },
  { uri: 'motogo://policies',      name: 'Rental policies summary', mimeType: 'text/markdown' },
]

// ============================================================================
// Tool implementations
// ============================================================================

async function execTool(name: string, args: Record<string, unknown>): Promise<unknown> {
  switch (name) {
    case 'motogo_search_motorcycles': {
      let q = sb.from('motorcycles')
        .select('id, model, brand, category, engine_cc, power_kw, license_required, color, image_url, branch_id, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, ideal_usage')
        .eq('status', 'active')
        .order('model')
      if (args.category) q = q.ilike('category', `%${args.category}%`)
      if (args.license_group) q = q.eq('license_required', args.license_group)
      if (args.kw_min) q = q.gte('power_kw', Number(args.kw_min))
      if (args.kw_max) q = q.lte('power_kw', Number(args.kw_max))
      const { data, error } = await q
      if (error) throw new Error(error.message)
      let result = data || []
      if (args.price_max) {
        const maxP = Number(args.price_max)
        result = result.filter((m: Record<string, unknown>) => {
          const prices = ['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
            .map((k) => Number((m as Record<string, unknown>)[k] || 0))
            .filter((p) => p > 0)
          return prices.length > 0 && Math.min(...prices) <= maxP
        })
      }
      return {
        count: result.length,
        motorcycles: result.map((m: Record<string, unknown>) => ({
          id: m.id, name: `${m.brand || ''} ${m.model}`.trim(),
          category: m.category, power_kw: m.power_kw, engine_cc: m.engine_cc,
          license: m.license_required, color: m.color,
          min_price_per_day: Math.min(...['price_mon','price_tue','price_wed','price_thu','price_fri','price_sat','price_sun']
            .map((k) => Number((m as Record<string, unknown>)[k] || 0)).filter((p) => p > 0)),
          ideal_usage: m.ideal_usage, image_url: m.image_url,
          url: `https://motogo24.cz/katalog/${m.id}`,
        })),
      }
    }

    case 'motogo_get_motorcycle': {
      const { data, error } = await sb.from('motorcycles')
        .select('*, branches(name, address, city, latitude, longitude)')
        .eq('id', args.moto_id)
        .maybeSingle()
      if (error) throw new Error(error.message)
      if (!data) throw new Error('Motorcycle not found')
      return data
    }

    case 'motogo_get_availability': {
      const { data, error } = await sb.rpc('get_moto_booked_dates', { p_moto_id: args.moto_id })
      if (error) throw new Error(error.message)
      return { moto_id: args.moto_id, booked_ranges: data || [] }
    }

    case 'motogo_quote': {
      const { moto_id, start_date, end_date, extras = [], promo_code } = args as Record<string, unknown>
      const { data: moto, error: mErr } = await sb.from('motorcycles')
        .select('id, model, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun')
        .eq('id', moto_id).maybeSingle()
      if (mErr) throw new Error(mErr.message)
      if (!moto) throw new Error('Motorcycle not found')
      const days = ['sun','mon','tue','wed','thu','fri','sat']
      const start = new Date(String(start_date)), end = new Date(String(end_date))
      let total = 0, count = 0
      const breakdown: Array<{date:string;day:string;price:number}> = []
      const d = new Date(start)
      while (d <= end) {
        const dn = days[d.getDay()]
        const p = Number((moto as Record<string, unknown>)['price_' + dn] ?? 0)
        total += p; count++
        breakdown.push({ date: d.toISOString().slice(0,10), day: dn, price: p })
        d.setDate(d.getDate() + 1)
      }
      const extrasTotal = Array.isArray(extras) ? (extras as Array<{unit_price?:number}>).reduce((s,e) => s + Number(e.unit_price || 0), 0) : 0
      let discount = 0, promoMsg = null
      if (promo_code) {
        const { data: pr } = await sb.rpc('validate_promo_code', { code: promo_code })
        if (pr && (pr as Record<string, unknown>).valid) {
          const p = pr as Record<string, unknown>
          if (p.type === 'percent') discount = Math.round(total * Number(p.value) / 100)
          else if (p.type === 'fixed') discount = Number(p.value)
          promoMsg = `Promo aplikováno: −${discount} Kč`
        } else { promoMsg = 'Promo neplatí' }
      }
      return {
        moto_id, days: count, breakdown, rental_total: total, extras_total: extrasTotal,
        promo_discount: discount, promo_message: promoMsg,
        grand_total: total + extrasTotal - discount, currency: 'CZK',
      }
    }

    case 'motogo_create_booking': {
      const a = args as Record<string, unknown>
      const { data, error } = await sb.rpc('create_web_booking', {
        p_moto_id: a.moto_id, p_start_date: a.start_date, p_end_date: a.end_date,
        p_name: a.customer_name, p_email: a.customer_email, p_phone: a.customer_phone,
        p_street: a.street ?? '', p_city: a.city ?? '', p_zip: a.zip ?? '', p_country: a.country ?? 'CZ',
        p_note: a.note ?? null,
        p_pickup_time: a.pickup_time ?? '12:00',
        p_delivery_address: a.delivery_address ?? null,
        p_return_address: a.return_address ?? null,
        p_extras: a.extras ?? [],
        p_discount_amount: 0, p_discount_code: null,
        p_promo_code: a.promo_code ?? null, p_voucher_id: null,
        p_license_group: a.license_group ?? null, p_password: null,
        p_helmet_size: null, p_jacket_size: null, p_pants_size: null,
        p_boots_size: null, p_gloves_size: null,
        p_passenger_helmet_size: null, p_passenger_jacket_size: null,
        p_passenger_gloves_size: null, p_passenger_boots_size: null,
        p_return_time: null,
      })
      if (error) throw new Error(error.message)
      const r = data as Record<string, unknown>
      return {
        ...r,
        payment_url: `https://motogo24.cz/rezervace?id=${r.booking_id}`,
        next_step: 'Customer must visit payment_url to complete Stripe payment.',
      }
    }

    case 'motogo_get_branches': {
      const { data, error } = await sb.from('branches').select('*').order('name')
      if (error) throw new Error(error.message)
      return { count: data?.length ?? 0, branches: data || [] }
    }

    case 'motogo_get_faq': {
      // Pull from our static FAQ markdown via web (cached) — simpler than DB (would need a cms_pages slug=faq).
      // Stačí krátký dictionary: nejčastější otázky.
      const faqs = [
        { q: 'Jak si rezervovat motorku?', a: 'Online přes formulář na motogo24.cz/rezervace, nebo přes MCP nástroj motogo_create_booking. Telefon +420 774 256 271.' },
        { q: 'Musím složit kauci?', a: 'Ne — MotoGo24 půjčuje bez kauce. Žádná blokace peněz na kartě.' },
        { q: 'Co je v ceně?', a: 'Pronájem motorky, motorkářská výbava (helma, bunda, kalhoty, rukavice), povinné ručení.' },
        { q: 'Jaký řidičský průkaz potřebuji?', a: 'Skupina A pro silnější stroje, A2 do 35 kW, A1 do 11 kW. Dětské motorky bez ŘP (ručí zákonný zástupce).' },
        { q: 'Můžu jet do zahraničí?', a: 'Ano, sjezd do zahraničí povolen. Zelená karta v ceně.' },
        { q: 'Kde si motorku vyzvednu?', a: 'Mezná 9, Pelhřimov, Vysočina. Volitelně přistavení kamkoliv v ČR za příplatek.' },
        { q: 'Můžu storno?', a: 'Bezplatné storno minimálně 7 dní před převzetím. Později individuálně.' },
        { q: 'Jak platím?', a: 'Online platební kartou přes Stripe. Visa, Mastercard, Amex, Apple Pay, Google Pay.' },
        { q: 'Otevírací doba?', a: '24/7 nonstop, 365 dní v roce. Vyzvednutí přes přístupové kódy.' },
        { q: 'Minimální věk?', a: '18 let pro dospělé motorky. Dětské motorky bez věkového limitu (ručí rodič).' },
      ]
      const query = String(args.query || '').toLowerCase()
      const filtered = query ? faqs.filter((f) => (f.q + ' ' + f.a).toLowerCase().includes(query)) : faqs
      return { count: filtered.length, faqs: filtered }
    }

    case 'motogo_validate_promo': {
      const { data, error } = await sb.rpc('validate_promo_code', { code: args.code })
      if (error) throw new Error(error.message)
      return data || { valid: false }
    }

    case 'motogo_validate_voucher': {
      const { data, error } = await sb.rpc('validate_voucher_code', { p_code: args.code })
      if (error) throw new Error(error.message)
      return data || { valid: false }
    }

    default:
      throw new Error(`Unknown tool: ${name}`)
  }
}

async function readResource(uri: string): Promise<{ uri: string; mimeType: string; text: string }> {
  if (uri === 'motogo://about') {
    return {
      uri, mimeType: 'text/markdown',
      text: `# MotoGo24

Czech motorcycle rental in Mezná near Pelhřimov (Vysočina region).

- **No deposit** — no card hold
- **Riding gear included** — helmet, jacket, pants, gloves
- **24/7 nonstop** — pickup via access codes
- **Online booking** — Stripe payment

Contact: +420 774 256 271 · info@motogo24.cz · Mezná 9, 393 01 Pelhřimov, CZ
GPS: 49.4147, 15.2953
Web: https://motogo24.cz`,
    }
  }
  if (uri === 'motogo://motorcycles') {
    const { data } = await sb.from('motorcycles').select('id, model, brand, category, power_kw, engine_cc, license_required, status').eq('status', 'active')
    return { uri, mimeType: 'application/json', text: JSON.stringify(data || []) }
  }
  if (uri === 'motogo://branches') {
    const { data } = await sb.from('branches').select('*')
    return { uri, mimeType: 'application/json', text: JSON.stringify(data || []) }
  }
  if (uri === 'motogo://faq') {
    const faqs = await execTool('motogo_get_faq', {}) as { faqs: Array<{q:string;a:string}> }
    let md = '# MotoGo24 FAQ\n\n'
    for (const f of faqs.faqs) md += `## ${f.q}\n\n${f.a}\n\n`
    return { uri, mimeType: 'text/markdown', text: md }
  }
  if (uri === 'motogo://policies') {
    return {
      uri, mimeType: 'text/markdown',
      text: `# MotoGo24 Rental Policies

## Deposit
**None.** No money held on customer's card.

## Cancellation
- Free cancellation: at least 7 days before pickup
- Later: individual agreement

## License Requirements
- **A**: unlimited, min. age 24 (or 21 with 2y A2 experience)
- **A2**: up to 35 kW, min. age 18
- **A1**: up to 11 kW, 125 ccm, min. age 16
- **B**: automatic scooters up to 125 ccm (CZ specific, 2y B experience)
- **N**: kids motorcycles, no license needed (parent guarantor)

## Abroad
Allowed. Green card included.

## Fuel & Cleaning
Return without need to refuel or wash. Excessive dirt — individual.

## Late Return
Please return on time. Late returns charged per agreement (other bookings).
`,
    }
  }
  throw new Error(`Unknown resource: ${uri}`)
}

// ============================================================================
// Logging
// ============================================================================

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s))
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function logCall(toolName: string, args: Record<string, unknown>, statusCode: number, latencyMs: number, outcome: string, ip: string, ua: string, partnerId: string | null) {
  try {
    const ipHash = await sha256Hex(ip + '|motogo24')
    await sb.from('ai_traffic_log').insert({
      source: 'mcp',
      bot_name: ua.slice(0, 100) || 'mcp-client',
      user_agent: ua.slice(0, 500),
      path: `mcp://${toolName}`,
      endpoint: toolName,
      method: 'tools/call',
      ip_hash: ipHash,
      partner_id: partnerId,
      status_code: statusCode,
      latency_ms: latencyMs,
      outcome,
      details: { args_keys: Object.keys(args) },
    })
  } catch { /* silent */ }
}

// ============================================================================
// Server
// ============================================================================

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown'
  const ua = req.headers.get('user-agent') || 'mcp-client'

  // Optional API key auth
  let partnerId: string | null = null
  const apiKey = req.headers.get('x-api-key')
  if (apiKey) {
    const hash = await sha256Hex(apiKey)
    const { data } = await sb.from('api_keys').select('id, is_active, revoked_at').eq('key_hash', hash).maybeSingle()
    if (data && data.is_active && !data.revoked_at) partnerId = data.id
  }

  // Discovery endpoint (GET / nebo /info)
  if (req.method === 'GET') {
    return new Response(JSON.stringify({
      name: 'motogo24-mcp',
      version: '1.0.0',
      description: 'MotoGo24 motorcycle rental MCP server. Search catalog, check availability, get quotes, create bookings.',
      protocolVersion: '2024-11-05',
      capabilities: {
        tools: { listChanged: false },
        resources: { listChanged: false, subscribe: false },
      },
      info: {
        provider: 'MotoGo24',
        contact: 'info@motogo24.cz',
        homepage: 'https://motogo24.cz',
        languages: ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl'],
        currencies: ['CZK'],
        regions: ['CZ', 'SK', 'AT', 'DE', 'PL'],
      },
    }, null, 2), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify(rpcErr(null, -32600, 'Only POST or GET allowed')), {
      status: 405, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  let request: JsonRpcRequest
  try {
    request = await req.json()
  } catch {
    return new Response(JSON.stringify(rpcErr(null, -32700, 'Parse error')), {
      status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const { id, method, params } = request
  const startedAt = Date.now()

  try {
    let result: unknown
    switch (method) {
      case 'initialize':
        result = {
          protocolVersion: '2024-11-05',
          serverInfo: { name: 'motogo24-mcp', version: '1.0.0' },
          capabilities: { tools: {}, resources: {} },
        }
        break
      case 'tools/list':
        result = { tools: TOOLS }
        break
      case 'tools/call': {
        const p = params as { name?: string; arguments?: Record<string, unknown> }
        if (!p?.name) throw new Error('Missing tool name')
        const out = await execTool(p.name, p.arguments || {})
        result = {
          content: [{ type: 'text', text: typeof out === 'string' ? out : JSON.stringify(out, null, 2) }],
          isError: false,
        }
        const outcome = p.name === 'motogo_create_booking' ? 'booking_created' : (p.name === 'motogo_quote' ? 'quote' : 'view')
        void logCall(p.name, p.arguments || {}, 200, Date.now() - startedAt, outcome, ip, ua, partnerId)
        break
      }
      case 'resources/list':
        result = { resources: RESOURCES }
        break
      case 'resources/read': {
        const p = params as { uri?: string }
        if (!p?.uri) throw new Error('Missing resource uri')
        const r = await readResource(p.uri)
        result = { contents: [r] }
        break
      }
      case 'ping':
        result = {}
        break
      default:
        return new Response(JSON.stringify(rpcErr(id, -32601, `Method not found: ${method}`)), {
          headers: { ...CORS, 'Content-Type': 'application/json' },
        })
    }

    return new Response(JSON.stringify(rpcOk(id, result)), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    const msg = (e as Error).message
    void logCall((params as Record<string, unknown>)?.name as string || method, (params as Record<string, unknown>)?.arguments as Record<string, unknown> || {}, 500, Date.now() - startedAt, 'error', ip, ua, partnerId)
    return new Response(JSON.stringify(rpcErr(id, -32603, msg)), {
      status: 200, // JSON-RPC error v body, ne HTTP status
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
