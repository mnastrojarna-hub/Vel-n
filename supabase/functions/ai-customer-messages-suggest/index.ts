/**
 * MotoGo24 — Edge Function: AI Customer Messages Suggest
 *
 * Generuje AI návrh odpovědi na příchozí zákaznickou zprávu (SMS / e-mail /
 * WhatsApp / app chat). Návrh ukládá do `messages.ai_suggested_reply` +
 * `ai_suggestion_status`. Default mode = `suggest_only` → admin musí ve Velíně
 * schválit; po natrénování může admin přepnout na `auto_send` → po vygenerování
 * návrhu rovnou volá `send-message`.
 *
 * Konfigurace z Velínu: `app_settings.ai_customer_messages_config` (klíč spravuje
 * `velin/src/components/ai/CustomerMessagesAgentSettingsPanel.jsx`).
 *
 * POST body (auth = service_role nebo authenticated admin):
 *   { message_id: uuid }   — jediný povinný parametr
 *
 * Synchronní response (do ~5 s, nečeká na LLM):
 *   { ok: true, message_id, status: 'queued' }
 *
 * Vlastní inference běží v EdgeRuntime.waitUntil() — výsledek si Velín přečte
 * z `messages` tabulky (realtime nebo polling), nikdy nedostane 504.
 *
 * Audit: každý request loguje do `ai_traffic_log` (source='customer_messages').
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

// Limity podle kanálu — vejít se do běžných UX/technických mezí
const CHANNEL_LIMITS: Record<string, { max_chars: number; tone_hint: string }> = {
  sms:      { max_chars: 320,  tone_hint: 'krátká SMS, bez podpisu, bez dlouhých URL' },
  whatsapp: { max_chars: 600,  tone_hint: 'krátké, lidské, smí emoji jen pokud je psal zákazník' },
  email:    { max_chars: 1500, tone_hint: 'celá věta, lze strukturované, krátký podpis' },
  app_chat: { max_chars: 400,  tone_hint: 'stručné jako SMS, lze odkaz na obrazovku v appce' },
}

// ───────────────────────────────────────────────────────────────────────────
// Helpers
// ───────────────────────────────────────────────────────────────────────────

interface AgentConfig {
  enabled?: boolean
  persona_name?: string
  system_prompt?: string
  situations?: string[]
  forbidden?: string[]
  mustDo?: string[]
  tone?: string
  max_tokens?: number
  channels?: Record<string, boolean>
  mode?: 'suggest_only' | 'auto_send'
  knowledge_extra?: string
}

async function loadConfig(): Promise<AgentConfig> {
  const { data } = await sb
    .from('app_settings')
    .select('value')
    .eq('key', 'ai_customer_messages_config')
    .maybeSingle()
  return (data?.value as AgentConfig) || {}
}

async function logTraffic(opts: {
  outcome: string
  message_id?: string
  thread_id?: string
  channel?: string
  latency_ms?: number
  status_code?: number
  details?: Record<string, unknown>
}) {
  try {
    await sb.from('ai_traffic_log').insert({
      source: 'customer_messages',
      bot_name: 'customer-messages-suggest',
      path: `cm://${opts.channel || 'unknown'}`,
      endpoint: 'suggest',
      method: 'POST',
      status_code: opts.status_code ?? 200,
      latency_ms: opts.latency_ms ?? 0,
      outcome: opts.outcome,
      details: { message_id: opts.message_id, thread_id: opts.thread_id, ...opts.details },
    })
  } catch { /* silent */ }
}

interface MessageContext {
  message: {
    id: string
    thread_id: string
    direction: string
    content: string
    created_at: string
    ai_suggestion_status: string | null
  }
  thread: {
    id: string
    channel: string | null
    status: string | null
    customer_id: string | null
    assigned_admin: string | null
  }
  customer: Record<string, unknown> | null
  booking: Record<string, unknown> | null
  history: Array<{ direction: string; content: string; created_at: string }>
}

async function loadContext(messageId: string): Promise<MessageContext | null> {
  const { data: m } = await sb
    .from('messages')
    .select('id, thread_id, direction, content, created_at, ai_suggestion_status')
    .eq('id', messageId)
    .maybeSingle()
  if (!m) return null

  const { data: t } = await sb
    .from('message_threads')
    .select('id, channel, status, customer_id, assigned_admin')
    .eq('id', m.thread_id)
    .maybeSingle()
  if (!t) return null

  let customer: Record<string, unknown> | null = null
  if (t.customer_id) {
    const { data: c } = await sb
      .from('profiles')
      .select('id, full_name, email, phone, language, license_group, riding_experience, city, ico')
      .eq('id', t.customer_id)
      .maybeSingle()
    customer = c
  }

  // Aktuální / nejbližší rezervace zákazníka
  let booking: Record<string, unknown> | null = null
  if (t.customer_id) {
    const { data: b } = await sb
      .from('bookings')
      .select('id, moto_id, start_date, end_date, status, payment_status, total_price, pickup_method, return_method, deposit, contract_url')
      .eq('user_id', t.customer_id)
      .in('status', ['pending', 'reserved', 'active', 'completed'])
      .order('start_date', { ascending: false })
      .limit(1)
      .maybeSingle()
    booking = b
  }

  // Posledních 10 zpráv ve vlákně (pro kontext)
  const { data: hist } = await sb
    .from('messages')
    .select('direction, content, created_at')
    .eq('thread_id', m.thread_id)
    .order('created_at', { ascending: true })
    .limit(20)
  const history = (hist || []).slice(-10)

  return { message: m, thread: t, customer, booking, history }
}

function buildSystemPrompt(cfg: AgentConfig, ctx: MessageContext): string {
  const channel = (ctx.thread.channel || 'unknown').toLowerCase()
  const limits = CHANNEL_LIMITS[channel] || { max_chars: 800, tone_hint: 'standardní formát' }
  const today = new Date().toLocaleDateString('cs-CZ', { timeZone: 'Europe/Prague' })

  const parts: string[] = []
  parts.push(cfg.system_prompt || 'Jsi správce zákaznických zpráv MotoGo24.')

  parts.push(`\n— KONTEXT —\nDNES: ${today}\nKANÁL: ${channel} (limit ${limits.max_chars} znaků, ${limits.tone_hint})\nPERSONA: ${cfg.persona_name || 'správce zpráv'}`)
  if (cfg.tone) parts.push(`TÓN: ${cfg.tone}`)

  if (ctx.customer) {
    const c = ctx.customer
    parts.push(`\n— ZÁKAZNÍK —\n${(c as { full_name?: string }).full_name || '?'} | ${(c as { email?: string }).email || '?'} | jazyk: ${(c as { language?: string }).language || 'cs'}`)
  }
  if (ctx.booking) {
    const b = ctx.booking as Record<string, string>
    parts.push(`\n— REZERVACE —\nID ${b.id}, moto ${b.moto_id}, ${b.start_date}–${b.end_date}, status: ${b.status}, platba: ${b.payment_status}, cena: ${b.total_price} Kč`)
  } else {
    parts.push('\n— REZERVACE —\nžádná aktivní rezervace v DB')
  }

  if (ctx.history.length > 0) {
    parts.push('\n— HISTORIE VLÁKNA (od nejstaršího) —')
    for (const h of ctx.history) {
      const d = (h.direction || '').toLowerCase()
      const label = (d === 'customer' || d === 'inbound') ? 'Zákazník'
        : (d === 'admin' || d === 'outbound') ? 'Admin'
        : (d === 'system') ? 'Systém'
        : d
      parts.push(`[${label}] ${(h.content || '').slice(0, 400)}`)
    }
  }

  if (cfg.situations?.length) parts.push('\n— SITUAČNÍ PRAVIDLA —\n' + cfg.situations.map(s => `- ${s}`).join('\n'))
  if (cfg.mustDo?.length) parts.push('\n— VŽDY MUSÍ —\n' + cfg.mustDo.map(s => `- ${s}`).join('\n'))
  if (cfg.forbidden?.length) parts.push('\n— ZAKÁZÁNO —\n' + cfg.forbidden.map(s => `- ${s}`).join('\n'))
  if (cfg.knowledge_extra?.trim()) parts.push('\n— AKTUÁLNÍ ZNALOSTI Z VELÍNU (vyšší priorita) —\n' + cfg.knowledge_extra.trim())

  parts.push(`\n— VÝSTUPNÍ FORMÁT —\nVrať POUZE validní JSON bez dalšího textu, formát:
{"reply": "text odpovědi pro zákazníka", "confidence": "low|medium|high", "admin_note": "krátká poznámka pro admina, proč low/medium nebo na co si dát pozor; null pokud high a vše standardní"}`)

  return parts.join('\n')
}

interface AnthropicResponse {
  reply: string
  confidence: 'low' | 'medium' | 'high'
  admin_note: string | null
}

async function callAnthropic(systemPrompt: string, userMessage: string, maxTokens: number): Promise<AnthropicResponse> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: Math.min(maxTokens || 600, 2048),
      system: systemPrompt,
      messages: [{ role: 'user', content: `Příchozí zákaznická zpráva:\n${userMessage}\n\nNavrhni odpověď ve formátu JSON.` }],
    }),
  })
  if (!res.ok) {
    const errText = await res.text().catch(() => '')
    throw new Error(`Anthropic ${res.status}: ${errText.slice(0, 200)}`)
  }
  const data = await res.json()
  const text = data?.content?.[0]?.text || ''

  // Parsuj JSON — model občas přidá prefix/suffix, najdi první {...}
  const jsonMatch = text.match(/\{[\s\S]*\}/)
  if (!jsonMatch) throw new Error('Anthropic vrátil odpověď bez JSON: ' + text.slice(0, 200))
  const parsed = JSON.parse(jsonMatch[0])
  const reply = String(parsed.reply || '').trim()
  const confidence = (['low', 'medium', 'high'].includes(parsed.confidence) ? parsed.confidence : 'medium') as 'low' | 'medium' | 'high'
  const admin_note = parsed.admin_note ? String(parsed.admin_note).slice(0, 500) : null
  if (!reply) throw new Error('Anthropic vrátil prázdný reply')
  return { reply, confidence, admin_note }
}

async function processSuggestion(messageId: string): Promise<void> {
  const start = Date.now()
  let channel: string | undefined
  let threadId: string | undefined

  try {
    const cfg = await loadConfig()
    if (!cfg.enabled) {
      await logTraffic({ outcome: 'disabled', message_id: messageId, latency_ms: Date.now() - start })
      return
    }

    const ctx = await loadContext(messageId)
    if (!ctx) {
      await logTraffic({ outcome: 'not_found', message_id: messageId, status_code: 404, latency_ms: Date.now() - start })
      return
    }
    channel = ctx.thread.channel || 'unknown'
    threadId = ctx.thread.id

    // Inbound = zpráva od zákazníka. DB historicky používá 'customer' (chat),
    // novější integrace mohou ukládat 'inbound' (SMS/email/WA). Akceptujeme oba.
    const dir = (ctx.message.direction || '').toLowerCase()
    if (dir !== 'inbound' && dir !== 'customer') {
      await logTraffic({ outcome: 'skip_outbound', message_id: messageId, thread_id: threadId, channel, latency_ms: Date.now() - start, details: { direction: dir } })
      return
    }
    if (ctx.message.ai_suggestion_status && ctx.message.ai_suggestion_status !== 'failed') {
      await logTraffic({ outcome: 'already_processed', message_id: messageId, thread_id: threadId, channel, latency_ms: Date.now() - start, details: { existing_status: ctx.message.ai_suggestion_status } })
      return
    }

    const channels = cfg.channels || {}
    if (channel && channels[channel] === false) {
      await logTraffic({ outcome: 'channel_off', message_id: messageId, thread_id: threadId, channel, latency_ms: Date.now() - start })
      return
    }

    const systemPrompt = buildSystemPrompt(cfg, ctx)
    const result = await callAnthropic(systemPrompt, ctx.message.content || '', cfg.max_tokens || 600)

    const isAuto = cfg.mode === 'auto_send'
    const status = isAuto ? 'auto_sent' : 'pending'

    const { error: updErr } = await sb
      .from('messages')
      .update({
        ai_suggested_reply: result.reply,
        ai_suggested_at: new Date().toISOString(),
        ai_suggestion_status: status,
        ai_suggested_by_model: ANTHROPIC_MODEL,
        ai_confidence: result.confidence,
        ai_admin_note: result.admin_note,
        ai_error: null,
      })
      .eq('id', messageId)
    if (updErr) throw updErr

    // Auto-send mode: rovnou pošli odpověď stejným kanálem přes existující edge fn
    if (isAuto) {
      try {
        await sb.functions.invoke('send-message', {
          body: {
            thread_id: ctx.thread.id,
            channel,
            content: result.reply,
            ai_generated: true,
            source_message_id: messageId,
          },
        })
      } catch (sendErr) {
        // Pokud send-message selže, vrať status na 'pending', aby admin viděl návrh
        await sb.from('messages').update({
          ai_suggestion_status: 'pending',
          ai_error: `auto_send failed: ${sendErr instanceof Error ? sendErr.message : 'unknown'}`,
        }).eq('id', messageId)
      }
    }

    await logTraffic({
      outcome: isAuto ? 'auto_sent' : 'suggested',
      message_id: messageId,
      thread_id: threadId,
      channel,
      latency_ms: Date.now() - start,
      details: { confidence: result.confidence },
    })
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err)
    await sb.from('messages').update({
      ai_suggestion_status: 'failed',
      ai_error: errMsg.slice(0, 500),
      ai_suggested_at: new Date().toISOString(),
    }).eq('id', messageId)
    await logTraffic({
      outcome: 'error',
      message_id: messageId,
      thread_id: threadId,
      channel,
      status_code: 500,
      latency_ms: Date.now() - start,
      details: { error: errMsg.slice(0, 300) },
    })
  }
}

// ───────────────────────────────────────────────────────────────────────────
// HTTP handler
// ───────────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  let body: { message_id?: string }
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  const messageId = body.message_id
  if (!messageId || typeof messageId !== 'string') {
    return new Response(JSON.stringify({ error: 'message_id required' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }

  // Pošli inferenci na pozadí — HTTP odpovídá okamžitě, frontend si výsledek
  // přečte z messages tabulky (Realtime nebo polling).
  // @ts-expect-error EdgeRuntime existuje v Supabase Deno runtime
  if (typeof EdgeRuntime !== 'undefined' && EdgeRuntime?.waitUntil) {
    // @ts-expect-error see above
    EdgeRuntime.waitUntil(processSuggestion(messageId))
  } else {
    // Lokální dev / fallback — fire and forget
    processSuggestion(messageId).catch(() => { /* logged uvnitř */ })
  }

  return new Response(
    JSON.stringify({ ok: true, message_id: messageId, status: 'queued', model: ANTHROPIC_MODEL }),
    { status: 202, headers: { ...CORS, 'Content-Type': 'application/json' } },
  )
})
