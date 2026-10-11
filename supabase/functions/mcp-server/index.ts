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
import { normLang, siteUrl } from '../_shared/agent-knowledge/site-url.ts'
import { formatOpeningHours, branchModeCs } from '../_shared/agent-knowledge/branch-facts.ts'
import { LANG_ENUM, keyFacts, dbFaq, foreignTravelCs, factsMarkdown } from './facts.ts'

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
        language: { type: 'string', enum: LANG_ENUM, description: 'Language of the end customer — returned links open the website in it (default en).' },
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
    description: 'Create a booking. Returns booking_id and payment_url (website in the customer\'s language) for the customer. Customer completes payment on payment_url. ALWAYS confirm with user before calling — this creates a real reservation. Requires the customer\'s EXPLICIT consent to the General Terms (incl. rental contract; the Czech version is binding) and to personal data processing (GDPR), date of birth (renter 18+) and the customer\'s language (contract, terms and e-mails are sent in it).',
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
        pickup_time: { type: 'string', description: 'HH:MM, default 10:00. Pickup from 12:00 on a 2+ day rental = 50 % off the 1st day; at a self-service branch such a booking is released by the kiosk only from 12:00 on the start day.' },
        delivery_address: { type: 'string', description: 'Optional — delivery anywhere in CZ' },
        return_address: { type: 'string', description: 'Optional — return at different location' },
        extras: { type: 'array', items: { type: 'object' } },
        promo_code: { type: 'string' },
        note: { type: 'string' },
        date_of_birth: { type: 'string', format: 'date', description: 'Renter date of birth YYYY-MM-DD (must be 18+).' },
        language: { type: 'string', enum: LANG_ENUM, description: 'Language the customer speaks — contract, General Terms, e-mails and payment page use it.' },
        consent_vop: { type: 'boolean', description: 'true ONLY if the customer explicitly agreed to the General Terms and rental contract.' },
        consent_gdpr: { type: 'boolean', description: 'true ONLY if the customer explicitly agreed to personal data processing (GDPR).' },
        marketing_consent: { type: 'boolean', description: 'Optional newsletter consent (default false).' },
      },
      required: ['moto_id', 'start_date', 'end_date', 'customer_name', 'customer_email', 'customer_phone', 'date_of_birth', 'language', 'consent_vop', 'consent_gdpr'],
    },
  },
  {
    name: 'motogo_get_branches',
    description: 'List MotoGo24 rental branches with address, GPS, mode and opening hours. Two branches, both NONSTOP: Mezná near Pelhřimov (staffed handover at the booked time) and Velké Němčice (100 % self-service with access codes).',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'motogo_get_faq',
    description: 'Get key facts (deposit, damage cover, branches, cancellation, travel ban…) and the FAQ (questions + answers) in the requested language. Optional query filters by keyword (in that language).',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Optional keyword filter' },
        language: { type: 'string', enum: LANG_ENUM, description: 'FAQ language (default en).' },
      },
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
        .select('id, model, brand, category, engine_cc, power_kw, license_required, color, image_url, branch_id, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, ideal_usage, branches(is_open)')
        .eq('status', 'active')
        .order('model')
      if (args.category) q = q.ilike('category', `%${args.category}%`)
      if (args.license_group) q = q.eq('license_required', args.license_group)
      if (args.kw_min) q = q.gte('power_kw', Number(args.kw_min))
      if (args.kw_max) q = q.lte('power_kw', Number(args.kw_max))
      const { data, error } = await q
      if (error) throw new Error(error.message)
      // Trvale zavřená pobočka (is_open=false) se nikde nenabízí — ani její motorky.
      let result = (data || []).filter((m: Record<string, unknown>) =>
        (m.branches as Record<string, unknown> | null)?.is_open !== false)
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
          url: siteUrl(normLang(args.language, 'en'), `/katalog/${m.id}`),
        })),
      }
    }

    case 'motogo_get_motorcycle': {
      // branches má jen gps_lat/gps_lng (latitude/longitude neexistují → dotaz padal).
      const { data, error } = await sb.from('motorcycles')
        .select('*, branches(name, address, city, gps_lat, gps_lng, is_open)')
        .eq('id', args.moto_id)
        .maybeSingle()
      if (error) throw new Error(error.message)
      // Motorka na zavřené pobočce se navenek nenabízí → jako neexistující.
      if (!data || (data.branches as Record<string, unknown> | null)?.is_open === false) {
        throw new Error('Motorcycle not found')
      }
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
        const { data: pr } = await sb.rpc('validate_promo_code', { p_code: promo_code })
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
      // Souhlasy + datum narození + jazyk (audit i18n AI-09): bez p_consent_* create_web_booking
      // uložil do profilu souhlasy (i marketing) jako true bez reálného souhlasu zákazníka.
      if (a.consent_vop !== true || a.consent_gdpr !== true) {
        throw new Error('Explicit customer consent required: consent_vop=true (General Terms + rental contract) and consent_gdpr=true (personal data processing).')
      }
      const dob = String(a.date_of_birth || '').slice(0, 10)
      if (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || isNaN(new Date(dob).getTime())) throw new Error('date_of_birth (YYYY-MM-DD) is required.')
      const bookLang = normLang(a.language, 'en')
      // Parita s webem/appkou (zadání 2026-10-01 večer): čas vyzvednutí se volí
      // u všech poboček (řídí slevu za vyzvednutí od 12:00), výchozí 10:00 —
      // NIKDY 12:00 (dala by slevu a u samoobsluhy výdej až od 12:00).
      // Vrácení na samoobslužné pobočce bez času → 23:59.
      const { data: mb } = await sb.from('motorcycles').select('branches(type)').eq('id', a.moto_id).maybeSingle()
      const ssBranch = ((mb as Record<string, unknown> | null)?.branches as Record<string, unknown> | null)?.type === 'samoobslužná'
      const { data, error } = await sb.rpc('create_web_booking', {
        p_moto_id: a.moto_id, p_start_date: a.start_date, p_end_date: a.end_date,
        p_name: a.customer_name, p_email: a.customer_email, p_phone: a.customer_phone,
        p_street: a.street ?? '', p_city: a.city ?? '', p_zip: a.zip ?? '', p_country: a.country ?? 'CZ',
        p_note: a.note ?? null,
        p_pickup_time: a.pickup_time ?? '10:00',
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
        p_return_time: (ssBranch && !a.return_address && !a.delivery_address) ? '23:59' : null,
        p_date_of_birth: dob,
        p_consent_vop: true,
        p_consent_gdpr: true,
        p_marketing_consent: a.marketing_consent === true,
      })
      if (error) throw new Error(error.message)
      const r = data as Record<string, unknown>
      // Jazyk rezervace → smlouva, VOP, e-maily (RPC z migrace 20261011_i18n_customer_language).
      const { error: langErr } = await sb.rpc('set_booking_language', { p_booking_id: r.booking_id, p_language: bookLang })
      if (langErr) console.warn('[mcp] set_booking_language failed:', langErr.message)
      return {
        ...r,
        language: bookLang,
        // ?resume= (web /rezervace čte jen resume; dřívější ?id= vedl na prázdný formulář) v jazyce zákazníka
        payment_url: siteUrl(bookLang, `/rezervace?resume=${r.booking_id}`),
        next_step: 'Customer must open payment_url to pay (card / Apple Pay / Google Pay, or QR / bank transfer on the website). After payment the customer uploads ID and driving licence photos in the booking; access codes / handover details then arrive by e-mail.',
      }
    }

    case 'motogo_get_branches': {
      const { data, error } = await sb.from('branches').select('*').order('name')
      if (error) throw new Error(error.message)
      // Neaktivní / zavřená pobočka se nikde nenabízí (stejně jako web a AI agent).
      const branches = (data || []).filter((b: Record<string, unknown>) => b.active !== false && b.is_open !== false)
        .map((b: Record<string, unknown>) => ({
          ...b,
          // Čitelně (jsonb opening_hours) + režim; obě pobočky NONSTOP (majitel 2026-10-10).
          opening_hours_text: b.type === 'samoobslužná' ? 'NONSTOP (0–24 h, self-service with access code)' : (formatOpeningHours(b.opening_hours) || 'NONSTOP (0–24 h, handover by staff at the booked time)'),
          mode: b.type === 'samoobslužná' ? 'self-service (24/7 access code, no staff)' : b.type === 'obslužná' ? 'staffed (handover by staff at the booked time, nonstop)' : null,
          mode_cs: branchModeCs(b.type),
        }))
      return { count: branches.length, branches }
    }

    case 'motogo_get_faq': {
      // Klíčová fakta (opravená dle majitele 2026-10-10 + site.policies) + FAQ z DB v jazyce klienta
      // (dřív 11 natvrdo českých odpovědí s chybami: zahraničí bez omezení, 24/7 přes kódy, 1 pobočka…).
      const lang = normLang(args.language, 'en')
      const query = String(args.query || '').toLowerCase()
      const facts = keyFacts(lang, await foreignTravelCs(sb))
      const keyHits = query ? facts.filter((f) => (f.q + ' ' + f.a).toLowerCase().includes(query)) : facts
      const faqs = (await dbFaq(sb, lang, query)).slice(0, 40)
      return { language: lang, binding_language: 'cs', key_facts: keyHits, count: faqs.length, faqs }
    }

    case 'motogo_validate_promo': {
      const { data, error } = await sb.rpc('validate_promo_code', { p_code: args.code })
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
    const facts = keyFacts('en', await foreignTravelCs(sb))
    return {
      uri, mimeType: 'text/markdown',
      text: factsMarkdown('MotoGo24 — motorcycle rental, Czech Republic (Vysočina)', facts)
        + `\nContact: +420 774 256 271 (Mon–Fri 8:00–17:00) · info@motogo24.cz · Mezná 9, 393 01 Pelhřimov, CZ\nWeb: https://www.motogo24.cz (cs) · ${siteUrl('en', '/')} (en, de, es, fr, nl, pl, uk via ?lang=)\n`,
    }
  }
  if (uri === 'motogo://motorcycles') {
    const { data } = await sb.from('motorcycles').select('id, model, brand, category, power_kw, engine_cc, license_required, status, branches(is_open)').eq('status', 'active')
    // Motorky zavřené pobočky vynech; embed branches jen pro filtr, ven se nevrací.
    const motos = (data || [])
      .filter((m: Record<string, unknown>) => (m.branches as Record<string, unknown> | null)?.is_open !== false)
      .map(({ branches: _b, ...m }: Record<string, unknown>) => m)
    return { uri, mimeType: 'application/json', text: JSON.stringify(motos) }
  }
  if (uri === 'motogo://branches') {
    const { data } = await sb.from('branches').select('*')
    const branches = (data || []).filter((b: Record<string, unknown>) => b.active !== false && b.is_open !== false)
    return { uri, mimeType: 'application/json', text: JSON.stringify(branches) }
  }
  if (uri === 'motogo://faq') {
    const faqs = await execTool('motogo_get_faq', { language: 'en' }) as { key_facts: Array<{q:string;a:string}>; faqs: Array<{q:string;a:string}> }
    let md = '# MotoGo24 FAQ\n\n'
    for (const f of [...faqs.key_facts, ...faqs.faqs]) md += `## ${f.q}\n\n${f.a}\n\n`
    return { uri, mimeType: 'text/markdown', text: md }
  }
  if (uri === 'motogo://policies') {
    return {
      uri, mimeType: 'text/markdown',
      text: factsMarkdown('MotoGo24 Rental Policies (summary — the Czech General Terms are binding)', keyFacts('en', await foreignTravelCs(sb))),
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
        homepage: 'https://www.motogo24.cz',
        languages: LANG_ENUM,
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
