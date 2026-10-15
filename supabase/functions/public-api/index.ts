/**
 * MotoGo24 — Edge Function: Public REST API
 *
 * Veřejné REST API pro AI agenty, partnery a integrátory.
 * Tenká vrstva nad existujícími Supabase RPC funkcemi.
 *
 * Auth model (hybrid):
 *   - Bez API klíče: nízký rate-limit (60 req/min/IP read, 30/h create_booking)
 *   - S API klíčem (X-Api-Key): per-partner rate_limit_rpm z `api_keys` tabulky
 *
 * Endpoints:
 *   GET  /api/v1/motorcycles                    list (filtry: category, license_group, kw_min, price_max)
 *   GET  /api/v1/motorcycles/:id                detail
 *   GET  /api/v1/motorcycles/:id/availability   booked dates pro kalendář
 *   GET  /api/v1/branches                       seznam poboček
 *   GET  /api/v1/extras                         katalog příslušenství
 *   GET  /api/v1/faq                            strukturovaná FAQ
 *   POST /api/v1/quotes                         kalkulace ceny (bez vytvoření)
 *   POST /api/v1/bookings                       vytvoří rezervaci přes create_web_booking
 *   POST /api/v1/promo/validate                 validuje promo kód
 *   POST /api/v1/voucher/validate               validuje voucher
 *
 * Logging: každý request → ai_traffic_log (source='rest_api').
 */ import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { normLang, siteUrl } from '../_shared/agent-knowledge/site-url.ts';
import { branchPublicFieldsEn } from '../_shared/agent-knowledge/branch-facts.ts';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key, idempotency-key',
  'Access-Control-Max-Age': '86400'
};
const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
// In-memory rate limiter (per IP / per key) — ephemeral, reset on cold start.
// Pro produkční DB-backed limiter později přepíšeme přes pg counter.
const rateBuckets = new Map();
function rateLimit(key, limit, windowMs = 60_000) {
  const now = Date.now();
  const b = rateBuckets.get(key);
  if (!b || b.resetAt < now) {
    rateBuckets.set(key, {
      count: 1,
      resetAt: now + windowMs
    });
    return {
      allowed: true,
      remaining: limit - 1
    };
  }
  if (b.count >= limit) return {
    allowed: false,
    remaining: 0
  };
  b.count++;
  return {
    allowed: true,
    remaining: limit - b.count
  };
}
function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS,
      'Content-Type': 'application/json',
      ...extraHeaders
    }
  });
}
async function sha256Hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b)=>b.toString(16).padStart(2, '0')).join('');
}
async function logTraffic(params) {
  try {
    const ip_hash = params.ip ? await sha256Hex(params.ip + '|motogo24') : null;
    await sb.from('ai_traffic_log').insert({
      source: params.source,
      bot_name: params.bot_name ?? null,
      user_agent: (params.user_agent || '').slice(0, 500),
      path: params.path ?? null,
      endpoint: params.endpoint ?? null,
      method: params.method ?? null,
      ip_hash,
      partner_id: params.partner_id ?? null,
      status_code: params.status_code,
      latency_ms: params.latency_ms,
      outcome: params.outcome ?? null,
      booking_id: params.booking_id ?? null,
      details: params.details ?? {}
    });
  } catch  {}
}
async function authPartner(req) {
  const key = req.headers.get('x-api-key') || req.headers.get('X-Api-Key');
  if (!key) return null;
  const hash = await sha256Hex(key);
  const { data } = await sb.from('api_keys').select('id, partner_name, rate_limit_rpm, scopes, is_active, revoked_at').eq('key_hash', hash).maybeSingle();
  if (!data || !data.is_active || data.revoked_at) return null;
  // Async update — nebrzdíme request
  void sb.from('api_keys').update({
    last_used_at: new Date().toISOString(),
    request_count: data.request_count ? undefined : 1
  }).eq('id', data.id).then(()=>{});
  return {
    id: data.id,
    partner_name: data.partner_name,
    rate_limit_rpm: data.rate_limit_rpm,
    scopes: data.scopes
  };
}
function getClientIp(req) {
  return req.headers.get('x-forwarded-for')?.split(',')[0].trim() || req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') || 'unknown';
}
// ============================================================================
// Handlers
// ============================================================================
async function handleListMotorcycles(req) {
  const url = new URL(req.url);
  const category = url.searchParams.get('category');
  const license = url.searchParams.get('license_group');
  const kwMin = url.searchParams.get('kw_min');
  const kwMax = url.searchParams.get('kw_max');
  const priceMax = url.searchParams.get('price_max');
  let q = sb.from('motorcycles').select('id, model, brand, category, engine_cc, power_kw, torque_nm, weight_kg, fuel_tank_l, seat_height_mm, has_abs, license_required, color, year, ideal_usage, image_url, images, branch_id, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, min_rental_days, max_rental_days, status, branches(name, address, city, is_open)').eq('status', 'active').order('model');
  if (category) q = q.ilike('category', `%${category}%`);
  if (license) q = q.eq('license_required', license);
  if (kwMin) q = q.gte('power_kw', Number(kwMin));
  if (kwMax) q = q.lte('power_kw', Number(kwMax));
  const { data, error } = await q;
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  // Trvale zavřená pobočka (is_open=false) se nikde nenabízí — ani její motorky.
  let result = (data || []).filter((m)=>m.branches?.is_open !== false);
  if (priceMax) {
    const maxP = Number(priceMax);
    result = result.filter((m)=>{
      const prices = [
        'price_mon',
        'price_tue',
        'price_wed',
        'price_thu',
        'price_fri',
        'price_sat',
        'price_sun'
      ].map((k)=>Number(m[k] || 0)).filter((p)=>p > 0);
      return prices.length > 0 && Math.min(...prices) <= maxP;
    });
  }
  return jsonResponse({
    count: result.length,
    motorcycles: result
  });
}
async function handleMotorcycleDetail(id) {
  // branches má jen gps_lat/gps_lng (latitude/longitude neexistují → dotaz padal).
  const { data, error } = await sb.from('motorcycles').select('*, branches(id, name, address, city, gps_lat, gps_lng, is_open)').eq('id', id).maybeSingle();
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  // Motorka na zavřené pobočce se navenek nenabízí → jako neexistující.
  if (!data || data.branches?.is_open === false) {
    return jsonResponse({
      error: 'Not found'
    }, 404);
  }
  return jsonResponse(data);
}
async function handleAvailability(id) {
  const { data, error } = await sb.rpc('get_moto_booked_dates', {
    p_moto_id: id
  });
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  return jsonResponse({
    moto_id: id,
    booked: data || []
  });
}
async function handleBranches() {
  const { data, error } = await sb.from('branches').select('*').order('name');
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  // Neaktivní / zavřená pobočka se nikde nenabízí (stejně jako web a AI agent).
  const branches = (data || []).filter((b)=>b.active !== false && b.is_open !== false)// + mode / opening_hours_text (čitelně; obě pobočky NONSTOP — majitel 2026-10-10), syrová pole beze změny
  .map((b)=>({
      ...b,
      ...branchPublicFieldsEn(b)
    }));
  return jsonResponse({
    count: branches.length,
    branches
  });
}
async function handleExtras() {
  const { data, error } = await sb.from('extras_catalog').select('*').order('name');
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  return jsonResponse({
    extras: data || []
  });
}
async function handleQuote(req) {
  const body = await req.json();
  const { moto_id, start_date, end_date } = body;
  if (!moto_id || !start_date || !end_date) {
    return jsonResponse({
      error: 'Missing required fields: moto_id, start_date, end_date'
    }, 400);
  }
  const { data: moto, error: motoErr } = await sb.from('motorcycles').select('id, model, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, min_rental_days, max_rental_days').eq('id', moto_id).maybeSingle();
  if (motoErr) return jsonResponse({
    error: motoErr.message
  }, 500);
  if (!moto) return jsonResponse({
    error: 'Motorcycle not found'
  }, 404);
  // Per-day price calculation (inclusive start+end)
  const days = [
    'sun',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat'
  ];
  const start = new Date(start_date), end = new Date(end_date);
  if (isNaN(start.valueOf()) || isNaN(end.valueOf()) || end < start) {
    return jsonResponse({
      error: 'Invalid date range'
    }, 400);
  }
  let total = 0, dayCount = 0;
  const breakdown = [];
  const d = new Date(start);
  while(d <= end){
    const dayName = days[d.getDay()];
    const price = Number(moto['price_' + dayName] ?? 0);
    total += price;
    dayCount++;
    breakdown.push({
      date: d.toISOString().slice(0, 10),
      day: dayName,
      price
    });
    d.setDate(d.getDate() + 1);
  }
  // Extras
  let extrasTotal = 0;
  if (Array.isArray(body.extras)) {
    extrasTotal = body.extras.reduce((s, e)=>s + Number(e.unit_price || 0), 0);
  }
  // Promo
  let discount = 0, promoMessage = null;
  if (body.promo_code) {
    const { data: promoRes } = await sb.rpc('validate_promo_code', {
      p_code: body.promo_code
    });
    if (promoRes && promoRes.valid) {
      const p = promoRes;
      if (p.type === 'percent') discount = Math.round(total * Number(p.value) / 100);
      else if (p.type === 'fixed') discount = Number(p.value);
      promoMessage = `Promo ${body.promo_code} aplikováno: −${discount} Kč`;
    } else {
      promoMessage = `Promo ${body.promo_code} neplatí`;
    }
  }
  return jsonResponse({
    moto_id,
    moto_model: moto.model,
    start_date,
    end_date,
    days: dayCount,
    breakdown,
    rental_total: total,
    extras_total: extrasTotal,
    promo_code: body.promo_code || null,
    promo_discount: discount,
    promo_message: promoMessage,
    grand_total: total + extrasTotal - discount,
    currency: 'CZK'
  });
}
async function handleCreateBooking(req) {
  const body = await req.json();
  // Souhlasy + datum narození (audit i18n AI-09): bez p_consent_* create_web_booking uložil do
  // profilu souhlasy (i marketing) jako true bez reálného souhlasu zákazníka.
  if (body.consent_vop !== true || body.consent_gdpr !== true) {
    return jsonResponse({
      error: 'Explicit customer consent required: consent_vop=true (General Terms + rental contract, Czech version binding) and consent_gdpr=true (personal data processing).'
    }, 400);
  }
  const dob = String(body.date_of_birth || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || isNaN(new Date(dob).getTime())) {
    return jsonResponse({
      error: 'date_of_birth (YYYY-MM-DD) is required — the renter must be 18+.'
    }, 400);
  }
  // Jazyk zákazníka: body.language → Accept-Language → cs (dosavadní chování). Řídí smlouvu,
  // VOP, e-maily (bookings.language) i jazyk platební stránky.
  const acceptLang = (req.headers.get('accept-language') || '').slice(0, 2);
  const bookLang = normLang(body.language, normLang(acceptLang, 'cs'));
  // Mapuj API parametry na create_web_booking signature
  const { data, error } = await sb.rpc('create_web_booking', {
    p_moto_id: body.moto_id,
    p_start_date: body.start_date,
    p_end_date: body.end_date,
    p_name: body.customer_name ?? body.name,
    p_email: body.customer_email ?? body.email,
    p_phone: body.customer_phone ?? body.phone,
    p_street: body.street ?? '',
    p_city: body.city ?? '',
    p_zip: body.zip ?? '',
    p_country: body.country ?? 'CZ',
    p_note: body.note ?? null,
    // Výchozí 10:00 (2026-10-01): 12:00 by dalo slevu za vyzvednutí od 12:00
    // a u samoobslužné pobočky výdej kioskem až od 12:00.
    p_pickup_time: body.pickup_time ?? '10:00',
    p_delivery_address: body.delivery_address ?? null,
    p_return_address: body.return_address ?? null,
    p_extras: body.extras ?? [],
    p_discount_amount: body.discount_amount ?? 0,
    p_discount_code: body.discount_code ?? null,
    p_promo_code: body.promo_code ?? null,
    p_voucher_id: body.voucher_id ?? null,
    p_license_group: body.license_group ?? null,
    p_password: body.password ?? null,
    p_helmet_size: body.helmet_size ?? null,
    p_jacket_size: body.jacket_size ?? null,
    p_pants_size: body.pants_size ?? null,
    p_boots_size: body.boots_size ?? null,
    p_gloves_size: body.gloves_size ?? null,
    p_passenger_helmet_size: body.passenger_helmet_size ?? null,
    p_passenger_jacket_size: body.passenger_jacket_size ?? null,
    p_passenger_gloves_size: body.passenger_gloves_size ?? null,
    p_passenger_boots_size: body.passenger_boots_size ?? null,
    p_return_time: body.return_time ?? null,
    p_date_of_birth: dob,
    p_consent_vop: true,
    p_consent_gdpr: true,
    p_marketing_consent: body.marketing_consent === true
  });
  if (error) return jsonResponse({
    error: error.message
  }, 400);
  const bookingId = data?.booking_id;
  const { error: langErr } = await sb.rpc('set_booking_language', {
    p_booking_id: bookingId,
    p_language: bookLang
  });
  if (langErr) console.warn('[public-api] set_booking_language failed:', langErr.message);
  return jsonResponse({
    ...data || {},
    language: bookLang,
    // ?resume= (web /rezervace čte jen resume; dřívější ?id= vedl na prázdný formulář) v jazyce zákazníka
    payment_url: siteUrl(bookLang, `/rezervace?resume=${bookingId}`),
    next_step: 'Open payment_url to complete the payment (card / Apple Pay / Google Pay, or QR / bank transfer). Then upload ID and driving licence photos in the booking.'
  });
}
async function handleValidatePromo(req) {
  const { code } = await req.json();
  if (!code) return jsonResponse({
    error: 'Missing code'
  }, 400);
  const { data, error } = await sb.rpc('validate_promo_code', {
    p_code: code
  });
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  return jsonResponse(data || {
    valid: false
  });
}
async function handleValidateVoucher(req) {
  const { code } = await req.json();
  if (!code) return jsonResponse({
    error: 'Missing code'
  }, 400);
  const { data, error } = await sb.rpc('validate_voucher_code', {
    p_code: code
  });
  if (error) return jsonResponse({
    error: error.message
  }, 500);
  return jsonResponse(data || {
    valid: false
  });
}
// ============================================================================
// Router
// ============================================================================
serve(async (req)=>{
  const startedAt = Date.now();
  if (req.method === 'OPTIONS') return new Response('ok', {
    headers: CORS
  });
  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/public-api/, '').replace(/\/$/, '') || '/';
  const ua = req.headers.get('user-agent') || '';
  const ip = getClientIp(req);
  // ===== Auth + rate limit =====
  let partner = null;
  try {
    partner = await authPartner(req);
  } catch  {}
  let rateKey, rateLimitN;
  if (partner) {
    rateKey = `key:${partner.id}`;
    rateLimitN = partner.rate_limit_rpm;
  } else {
    rateKey = `ip:${ip}`;
    // Defaults dle endpoint typu
    if (req.method === 'POST' && path.includes('/bookings')) rateLimitN = 30 // 30/h pro anon create_booking — pojistka, hodinové okno
    ;
    else if (req.method === 'POST') rateLimitN = 30;
    else rateLimitN = 60;
  }
  const windowMs = req.method === 'POST' && path.includes('/bookings') && !partner ? 3_600_000 : 60_000;
  const rl = rateLimit(rateKey, rateLimitN, windowMs);
  if (!rl.allowed) {
    void logTraffic({
      source: 'rest_api',
      user_agent: ua,
      path,
      method: req.method,
      ip,
      partner_id: partner?.id,
      status_code: 429,
      latency_ms: Date.now() - startedAt,
      outcome: 'rate_limited'
    });
    return jsonResponse({
      error: 'Rate limit exceeded',
      retry_after_seconds: Math.ceil(windowMs / 1000)
    }, 429, {
      'Retry-After': String(Math.ceil(windowMs / 1000)),
      'X-RateLimit-Limit': String(rateLimitN),
      'X-RateLimit-Remaining': '0'
    });
  }
  // ===== Routing =====
  let response;
  let endpoint = '';
  try {
    // GET /api/v1/motorcycles
    if (req.method === 'GET' && path === '/api/v1/motorcycles') {
      endpoint = 'list_motorcycles';
      response = await handleListMotorcycles(req);
    } else if (req.method === 'GET' && /^\/api\/v1\/motorcycles\/[a-f0-9-]+$/.test(path)) {
      endpoint = 'motorcycle_detail';
      response = await handleMotorcycleDetail(path.split('/').pop());
    } else if (req.method === 'GET' && /^\/api\/v1\/motorcycles\/[a-f0-9-]+\/availability$/.test(path)) {
      endpoint = 'availability';
      response = await handleAvailability(path.split('/')[4]);
    } else if (req.method === 'GET' && path === '/api/v1/branches') {
      endpoint = 'branches';
      response = await handleBranches();
    } else if (req.method === 'GET' && path === '/api/v1/extras') {
      endpoint = 'extras';
      response = await handleExtras();
    } else if (req.method === 'POST' && path === '/api/v1/quotes') {
      endpoint = 'quote';
      response = await handleQuote(req);
    } else if (req.method === 'POST' && path === '/api/v1/bookings') {
      endpoint = 'create_booking';
      response = await handleCreateBooking(req);
    } else if (req.method === 'POST' && path === '/api/v1/promo/validate') {
      endpoint = 'validate_promo';
      response = await handleValidatePromo(req);
    } else if (req.method === 'POST' && path === '/api/v1/voucher/validate') {
      endpoint = 'validate_voucher';
      response = await handleValidateVoucher(req);
    } else if (req.method === 'GET' && (path === '/api/v1/openapi.json' || path === '/openapi.json')) {
      endpoint = 'openapi';
      response = jsonResponse(buildOpenApiSpec(), 200, {
        'Cache-Control': 'public, max-age=3600'
      });
    } else if (req.method === 'GET' && (path === '/' || path === '/api/v1' || path === '/api/v1/')) {
      endpoint = 'root';
      response = jsonResponse({
        name: 'MotoGo24 Public API',
        version: '1.0.0',
        documentation: 'https://www.motogo24.cz/api/v1/openapi.json',
        endpoints: [
          'GET  /api/v1/motorcycles',
          'GET  /api/v1/motorcycles/:id',
          'GET  /api/v1/motorcycles/:id/availability',
          'GET  /api/v1/branches',
          'GET  /api/v1/extras',
          'POST /api/v1/quotes',
          'POST /api/v1/bookings',
          'POST /api/v1/promo/validate',
          'POST /api/v1/voucher/validate'
        ]
      });
    } else {
      response = jsonResponse({
        error: 'Not found',
        path,
        method: req.method
      }, 404);
    }
  } catch (e) {
    response = jsonResponse({
      error: e.message
    }, 500);
  }
  const latency = Date.now() - startedAt;
  const statusCode = response.status;
  const outcome = statusCode >= 400 ? 'error' : endpoint === 'create_booking' && statusCode < 300 ? 'booking_created' : endpoint === 'quote' ? 'quote' : 'view';
  void logTraffic({
    source: 'rest_api',
    user_agent: ua,
    path,
    endpoint,
    method: req.method,
    ip,
    partner_id: partner?.id,
    status_code: statusCode,
    latency_ms: latency,
    outcome
  });
  // Add rate-limit headers to non-error responses
  if (statusCode < 400) {
    const h = new Headers(response.headers);
    h.set('X-RateLimit-Limit', String(rateLimitN));
    h.set('X-RateLimit-Remaining', String(rl.remaining));
    return new Response(response.body, {
      status: statusCode,
      headers: h
    });
  }
  return response;
});
// ============================================================================
// OpenAPI 3.1 spec — vrací se přes GET /api/v1/openapi.json
// ============================================================================
function buildOpenApiSpec() {
  return {
    openapi: '3.1.0',
    info: {
      title: 'MotoGo24 Public API',
      version: '1.0.0',
      description: 'Veřejné REST API půjčovny motorek MotoGo24. Tenká vrstva nad Supabase RPC. Hybrid auth: bez klíče = nízký rate-limit, s X-Api-Key = partner rate-limit dle DB.',
      contact: {
        name: 'MotoGo24',
        email: 'info@motogo24.cz',
        url: 'https://www.motogo24.cz'
      },
      license: {
        name: 'Proprietary',
        url: 'https://www.motogo24.cz/dokumenty/obchodni-podminky'
      }
    },
    servers: [
      {
        url: 'https://api.motogo24.cz',
        description: 'Production'
      }
    ],
    components: {
      securitySchemes: {
        ApiKeyAuth: {
          type: 'apiKey',
          in: 'header',
          name: 'X-Api-Key'
        }
      }
    },
    paths: {
      '/api/v1/motorcycles': {
        get: {
          summary: 'List active motorcycles',
          parameters: [
            {
              name: 'category',
              in: 'query',
              schema: {
                type: 'string'
              }
            },
            {
              name: 'license_group',
              in: 'query',
              schema: {
                type: 'string',
                enum: [
                  'AM',
                  'A1',
                  'A2',
                  'A',
                  'B',
                  'N'
                ]
              }
            },
            {
              name: 'kw_min',
              in: 'query',
              schema: {
                type: 'number'
              }
            },
            {
              name: 'kw_max',
              in: 'query',
              schema: {
                type: 'number'
              }
            },
            {
              name: 'price_max',
              in: 'query',
              schema: {
                type: 'number',
                description: 'Max Kč/den'
              }
            }
          ],
          responses: {
            '200': {
              description: 'List of motorcycles'
            }
          }
        }
      },
      '/api/v1/motorcycles/{id}': {
        get: {
          summary: 'Motorcycle detail',
          parameters: [
            {
              name: 'id',
              in: 'path',
              required: true,
              schema: {
                type: 'string',
                format: 'uuid'
              }
            }
          ],
          responses: {
            '200': {
              description: 'Motorcycle'
            },
            '404': {
              description: 'Not found'
            }
          }
        }
      },
      '/api/v1/motorcycles/{id}/availability': {
        get: {
          summary: 'Booked dates for calendar',
          parameters: [
            {
              name: 'id',
              in: 'path',
              required: true,
              schema: {
                type: 'string',
                format: 'uuid'
              }
            }
          ],
          responses: {
            '200': {
              description: 'Booked date ranges'
            }
          }
        }
      },
      '/api/v1/branches': {
        get: {
          summary: 'List branches',
          responses: {
            '200': {
              description: 'Branches with GPS'
            }
          }
        }
      },
      '/api/v1/extras': {
        get: {
          summary: 'Catalog of accessories/extras',
          responses: {
            '200': {
              description: 'Extras list'
            }
          }
        }
      },
      '/api/v1/quotes': {
        post: {
          summary: 'Calculate price (no booking created)',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: [
                    'moto_id',
                    'start_date',
                    'end_date'
                  ],
                  properties: {
                    moto_id: {
                      type: 'string',
                      format: 'uuid'
                    },
                    start_date: {
                      type: 'string',
                      format: 'date'
                    },
                    end_date: {
                      type: 'string',
                      format: 'date'
                    },
                    extras: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: {
                          name: {
                            type: 'string'
                          },
                          unit_price: {
                            type: 'number'
                          }
                        }
                      }
                    },
                    promo_code: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          },
          responses: {
            '200': {
              description: 'Quote with breakdown'
            }
          }
        }
      },
      '/api/v1/bookings': {
        post: {
          summary: 'Create booking (returns payment URL)',
          security: [
            {
              ApiKeyAuth: []
            },
            {}
          ],
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: [
                    'moto_id',
                    'start_date',
                    'end_date',
                    'customer_name',
                    'customer_email',
                    'customer_phone',
                    'date_of_birth',
                    'consent_vop',
                    'consent_gdpr'
                  ],
                  properties: {
                    moto_id: {
                      type: 'string',
                      format: 'uuid'
                    },
                    date_of_birth: {
                      type: 'string',
                      format: 'date',
                      description: 'Renter date of birth (18+).'
                    },
                    language: {
                      type: 'string',
                      enum: [
                        'cs',
                        'en',
                        'de',
                        'es',
                        'fr',
                        'nl',
                        'pl',
                        'uk'
                      ],
                      description: 'Customer language — contract, General Terms, e-mails and payment page. Default: Accept-Language, else cs.'
                    },
                    consent_vop: {
                      type: 'boolean',
                      description: 'Must be true — explicit consent to the General Terms and rental contract (Czech version binding).'
                    },
                    consent_gdpr: {
                      type: 'boolean',
                      description: 'Must be true — explicit consent to personal data processing.'
                    },
                    marketing_consent: {
                      type: 'boolean',
                      default: false
                    },
                    start_date: {
                      type: 'string',
                      format: 'date'
                    },
                    end_date: {
                      type: 'string',
                      format: 'date'
                    },
                    customer_name: {
                      type: 'string'
                    },
                    customer_email: {
                      type: 'string',
                      format: 'email'
                    },
                    customer_phone: {
                      type: 'string'
                    },
                    street: {
                      type: 'string'
                    },
                    city: {
                      type: 'string'
                    },
                    zip: {
                      type: 'string'
                    },
                    country: {
                      type: 'string',
                      default: 'CZ'
                    },
                    license_group: {
                      type: 'string',
                      enum: [
                        'AM',
                        'A1',
                        'A2',
                        'A',
                        'B',
                        'N'
                      ]
                    },
                    pickup_time: {
                      type: 'string',
                      example: '10:00',
                      description: 'HH:MM, default 10:00. Pickup from 12:00 on a 2+ day rental = 50 % off the 1st day; at a self-service branch the kiosk then releases the booking only from 12:00 on the start day.'
                    },
                    delivery_address: {
                      type: 'string'
                    },
                    return_address: {
                      type: 'string'
                    },
                    extras: {
                      type: 'array',
                      items: {
                        type: 'object'
                      }
                    },
                    promo_code: {
                      type: 'string'
                    },
                    voucher_id: {
                      type: 'string',
                      format: 'uuid'
                    },
                    helmet_size: {
                      type: 'string'
                    },
                    jacket_size: {
                      type: 'string'
                    },
                    pants_size: {
                      type: 'string'
                    },
                    gloves_size: {
                      type: 'string'
                    },
                    boots_size: {
                      type: 'string'
                    },
                    note: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          },
          responses: {
            '200': {
              description: 'Booking created, payment URL returned'
            },
            '400': {
              description: 'Validation error'
            },
            '429': {
              description: 'Rate limit exceeded'
            }
          }
        }
      },
      '/api/v1/promo/validate': {
        post: {
          summary: 'Validate promo code',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    code: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          },
          responses: {
            '200': {
              description: 'Validation result'
            }
          }
        }
      },
      '/api/v1/voucher/validate': {
        post: {
          summary: 'Validate voucher code',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    code: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          },
          responses: {
            '200': {
              description: 'Validation result'
            }
          }
        }
      }
    }
  };
}
