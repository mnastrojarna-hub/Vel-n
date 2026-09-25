/**
 * MotoGo24 — Edge Function: AI Customer Messages Suggest (Velín → Zprávy)
 *
 * Návrh odpovědi na zákaznickou zprávu (SMS / e-mail / WhatsApp / app chat).
 * Od 2026-09-25 má agent KOMPLETNÍ znalosti a nástroje servisního agenta z appky
 * (ai-moto-agent) i veřejného agenta z webu (ai-public-agent) + Velínské nástroje
 * nad celou DB a ustálené úpravy všech AI agentů. Dřívější verze byla Haiku bez
 * nástrojů a bez znalostní báze → návrhy byly „informačně mimo".
 *
 * Auth: service_role nebo přihlášený admin (verify_jwt=false → ověřuje funkce sama).
 *
 * POST body:
 *   { message_id }            — návrh k inbound zprávě; běží na pozadí, výsledek
 *                               zapíše do messages.ai_suggested_reply (+ auto_send).
 *                               Response 202 { ok, message_id, status: 'queued' }.
 *   { thread_id, mode:'draft' } — synchronní návrh odpovědi na celé vlákno (spodní
 *                               tlačítko „AI návrh odpovědi" v ChatPanelu); nic neukládá.
 *                               Response 200 { reply, confidence, admin_note }.
 *
 * Konfigurace: app_settings.ai_customer_messages_config (CustomerMessagesAgentSettingsPanel).
 * Audit: ai_traffic_log (source='customer_messages').
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { requireAdminOrService } from '../_shared/auth.ts'
import { loadThreadContext } from './context.ts'
import { type AgentConfig, buildSystem, loadKnowledgeInputs } from './prompt.ts'
import { ANTHROPIC_MODEL, runAgent } from './llm.ts'

const sb = createClient(Deno.env.get('SUPABASE_URL') || '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '')
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

async function loadConfig(): Promise<AgentConfig> {
  const { data } = await sb.from('app_settings').select('value').eq('key', 'ai_customer_messages_config').maybeSingle()
  return (data?.value as AgentConfig) || {}
}

async function logTraffic(o: { outcome: string; message_id?: string; thread_id?: string; channel?: string; latency_ms?: number; status_code?: number; details?: Record<string, unknown> }) {
  try {
    await sb.from('ai_traffic_log').insert({
      source: 'customer_messages', bot_name: 'customer-messages-suggest', path: `cm://${o.channel || 'unknown'}`,
      endpoint: 'suggest', method: 'POST', status_code: o.status_code ?? 200, latency_ms: o.latency_ms ?? 0,
      outcome: o.outcome, details: { message_id: o.message_id, thread_id: o.thread_id, ...o.details },
    })
  } catch { /* silent */ }
}

async function generate(cfg: AgentConfig, threadId: string, focusMessageId?: string) {
  const [ctx, k] = await Promise.all([loadThreadContext(sb, threadId, focusMessageId), loadKnowledgeInputs(sb)])
  if (!ctx) return null
  const task = ctx.focus
    ? `Navrhni odpověď na tuto zprávu zákazníka (z ${String(ctx.focus.created_at).slice(0, 16).replace('T', ' ')}):\n"""${ctx.focus.content || ''}"""`
    : 'Ve vlákně není zpráva od zákazníka — navrhni vhodnou další zprávu týmu podle historie vlákna.'
  const out = await runAgent(sb, buildSystem(cfg, k, ctx), task + '\n\nNejdřív si ověř fakta (kontext + nástroje), pak vrať JSON.', ctx.customerId, cfg.max_tokens)
  return { ...out, ctx }
}

async function processSuggestion(messageId: string): Promise<void> {
  const start = Date.now()
  let channel: string | undefined, threadId: string | undefined
  const fail = (msg: string) => sb.from('messages').update({ ai_suggestion_status: 'failed', ai_error: msg.slice(0, 500), ai_suggested_at: new Date().toISOString() }).eq('id', messageId)
  try {
    const cfg = await loadConfig()
    const { data: m } = await sb.from('messages').select('id, thread_id, direction, ai_suggestion_status').eq('id', messageId).maybeSingle()
    if (!m) { await logTraffic({ outcome: 'not_found', message_id: messageId, status_code: 404 }); return }
    threadId = m.thread_id
    if (!cfg.enabled) {
      await fail('AI agent zákaznických zpráv je ve Velínu vypnutý (Nastavení AI → Zákaznické zprávy).')
      await logTraffic({ outcome: 'disabled', message_id: messageId, thread_id: threadId }); return
    }
    const dir = String(m.direction || '').toLowerCase()
    if (dir !== 'inbound' && dir !== 'customer') { await logTraffic({ outcome: 'skip_outbound', message_id: messageId, thread_id: threadId, details: { direction: dir } }); return }
    if (m.ai_suggestion_status && m.ai_suggestion_status !== 'failed') { await logTraffic({ outcome: 'already_processed', message_id: messageId, thread_id: threadId }); return }

    const { data: th } = await sb.from('message_threads').select('channel').eq('id', m.thread_id).maybeSingle()
    channel = String(th?.channel || 'unknown').toLowerCase()
    if (cfg.channels && cfg.channels[channel] === false) { await fail(`Kanál ${channel} má AI návrhy ve Velínu vypnuté.`); await logTraffic({ outcome: 'channel_off', message_id: messageId, thread_id: threadId, channel }); return }

    const res = await generate(cfg, m.thread_id, messageId)
    if (!res) { await fail('Vlákno nenalezeno'); return }

    const isAuto = cfg.mode === 'auto_send'
    const { error: updErr } = await sb.from('messages').update({
      ai_suggested_reply: res.reply, ai_suggested_at: new Date().toISOString(),
      ai_suggestion_status: isAuto ? 'auto_sent' : 'pending', ai_suggested_by_model: ANTHROPIC_MODEL,
      ai_confidence: res.confidence, ai_admin_note: res.admin_note, ai_error: null,
    }).eq('id', messageId)
    if (updErr) throw updErr

    if (isAuto) {
      try {
        await sb.functions.invoke('send-message', { body: { thread_id: threadId, channel, content: res.reply, ai_generated: true, source_message_id: messageId } })
      } catch (sendErr) {
        await sb.from('messages').update({ ai_suggestion_status: 'pending', ai_error: `auto_send failed: ${sendErr instanceof Error ? sendErr.message : 'unknown'}` }).eq('id', messageId)
      }
    }
    await logTraffic({ outcome: isAuto ? 'auto_sent' : 'suggested', message_id: messageId, thread_id: threadId, channel, latency_ms: Date.now() - start, details: { confidence: res.confidence, tools: res.tools } })
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    await fail(msg)
    await logTraffic({ outcome: 'error', message_id: messageId, thread_id: threadId, channel, status_code: 500, latency_ms: Date.now() - start, details: { error: msg.slice(0, 300) } })
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const auth = await requireAdminOrService(req)
  if (!auth.ok) return json({ error: 'unauthorized', reason: auth.reason }, 403)

  let body: { message_id?: string; thread_id?: string; mode?: string }
  try { body = await req.json() } catch { return json({ error: 'Invalid JSON' }, 400) }

  if (body.mode === 'draft') {
    if (!body.thread_id || typeof body.thread_id !== 'string') return json({ error: 'thread_id required' }, 400)
    const start = Date.now()
    try {
      const res = await generate(await loadConfig(), body.thread_id)
      if (!res) return json({ error: 'thread not found' }, 404)
      await logTraffic({ outcome: 'draft', thread_id: body.thread_id, channel: res.ctx.channel, latency_ms: Date.now() - start, details: { confidence: res.confidence, tools: res.tools } })
      return json({ reply: res.reply, confidence: res.confidence, admin_note: res.admin_note, model: ANTHROPIC_MODEL })
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      await logTraffic({ outcome: 'error', thread_id: body.thread_id, status_code: 500, latency_ms: Date.now() - start, details: { error: msg.slice(0, 300), mode: 'draft' } })
      return json({ error: msg }, 500)
    }
  }

  const messageId = body.message_id
  if (!messageId || typeof messageId !== 'string') return json({ error: 'message_id required' }, 400)
  // Inference běží na pozadí — Velín si výsledek přečte z `messages` (Realtime).
  // @ts-expect-error EdgeRuntime existuje v Supabase Deno runtime
  if (typeof EdgeRuntime !== 'undefined' && EdgeRuntime?.waitUntil) EdgeRuntime.waitUntil(processSuggestion(messageId))
  else processSuggestion(messageId).catch(() => { /* logged uvnitř */ })
  return json({ ok: true, message_id: messageId, status: 'queued', model: ANTHROPIC_MODEL }, 202)
})
