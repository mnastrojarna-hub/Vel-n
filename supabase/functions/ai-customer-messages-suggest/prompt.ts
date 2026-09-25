// ===== ai-customer-messages-suggest/prompt.ts =====
// System prompt = znalosti servisního agenta (appka) + veřejného agenta (web) +
// ustálené úpravy z Velína (knowledge_extra / pravidla všech tří agentů) + kontext vlákna.

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildDateHeader, SERVICE_OPS_KNOWLEDGE, SEASON_NOTE, APP_PAY_NOTE } from '../ai-moto-agent/booking-context.ts'
import { type CompanyInfo, type FleetMoto, type BranchRow, formatFleetSnapshot, formatBranchesSnapshot } from '../_shared/agent-knowledge/snapshots.ts'
import { loadKnowledgeBase } from '../_shared/agent-knowledge/knowledge-base.ts'
import { buildCompanyBrain } from '../_shared/agent-knowledge/company-brain.ts'
import { HARD_RULES_CS } from '../_shared/agent-knowledge/hard-rules.ts'
import { type ThreadContext, dirLabel } from './context.ts'

export interface AgentConfig {
  enabled?: boolean; persona_name?: string; system_prompt?: string; situations?: string[]; forbidden?: string[]
  mustDo?: string[]; tone?: string; max_tokens?: number; channels?: Record<string, boolean>
  mode?: 'suggest_only' | 'auto_send'; knowledge_extra?: string
}
type Cfg = { situations?: string[]; mustDo?: string[]; forbidden?: string[]; knowledge_extra?: string }

export const CHANNEL_LIMITS: Record<string, { max_chars: number; hint: string }> = {
  sms: { max_chars: 320, hint: 'krátká SMS, bez podpisu, bez dlouhých URL' },
  whatsapp: { max_chars: 600, hint: 'krátké, lidské, emoji jen pokud je psal zákazník' },
  email: { max_chars: 1500, hint: 'celé věty, oslovení, krátký podpis „Tým MotoGo24"' },
  app_chat: { max_chars: 500, hint: 'stručné, lze odkázat na obrazovku v appce' },
}
const TONE: Record<string, string> = {
  friendly: 'přátelský a vstřícný', professional: 'profesionální a věcný',
  concise: 'maximálně stručný', detailed: 'podrobný, s vysvětlením souvislostí',
}

export async function loadKnowledgeInputs(sb: SupabaseClient) {
  const [pub, moto, ci, fleet, br, kb] = await Promise.all([
    sb.from('app_settings').select('value').eq('key', 'ai_public_agent_config').maybeSingle(),
    sb.from('app_settings').select('value').eq('key', 'ai_moto_agent_config').maybeSingle(),
    sb.from('app_settings').select('value').eq('key', 'company_info').maybeSingle(),
    sb.from('motorcycles')
      .select('id, brand, model, category, license_required, status, power_kw, engine_cc, weight_kg, price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun, branch_id, branches!branch_id(name, type, is_open)')
      .in('status', ['active', 'maintenance', 'unavailable']).order('brand').order('model'),
    sb.from('branches').select('*').order('name'),
    loadKnowledgeBase(sb, 'cs'),
  ])
  return {
    pubCfg: (pub.data?.value as Cfg) || {},
    motoCfg: (moto.data?.value as Cfg) || {},
    company: (ci.data?.value as CompanyInfo) || {},
    fleet: ((fleet.data || []) as Array<Record<string, unknown>>)
      .filter((m) => (m.branches as Record<string, unknown> | null)?.is_open !== false) as unknown as FleetMoto[],
    branches: ((br.data || []) as Array<Record<string, unknown>>)
      .filter((b) => b.active !== false && b.is_open !== false) as unknown as BranchRow[],
    kb,
  }
}

function rules(title: string, c: Cfg): string {
  const out: string[] = []
  if (c.knowledge_extra?.trim()) out.push(`Aktuální znalosti: ${c.knowledge_extra.trim()}`)
  if (c.situations?.length) out.push('Situace:\n' + c.situations.map((s) => `- ${s}`).join('\n'))
  if (c.mustDo?.length) out.push('Vždy:\n' + c.mustDo.map((s) => `- ${s}`).join('\n'))
  if (c.forbidden?.length) out.push('Nikdy:\n' + c.forbidden.map((s) => `- ${s}`).join('\n'))
  return out.length ? `### ${title}\n${out.join('\n')}` : ''
}

type K = Awaited<ReturnType<typeof loadKnowledgeInputs>>

export function buildSystem(cfg: AgentConfig, k: K, ctx: ThreadContext) {
  const lim = CHANNEL_LIMITS[ctx.channel] || { max_chars: 1000, hint: 'standardní formát' }
  const persona = cfg.persona_name || 'správce zákaznických zpráv'
  const staticPart = [
    `Jsi ${persona} v půjčovně motorek MotoGo24. Připravuješ NÁVRH odpovědi, kterou za firmu odešle člověk z týmu ve Velíně (admin ji schválí, upraví nebo zamítne). Musíš znát a používat VŠECHNY procesy, podmínky a detaily firmy níže — stejné znalosti jako servisní AI agent v aplikaci i veřejný AI agent na webu dohromady. Odpověď musí být fakticky přesná a konkrétní pro TOHOTO zákazníka a JEHO rezervaci; obecné vyhýbavé odpovědi („ozveme se", „prověříme") jsou chyba, pokud odpověď znáš nebo ji zjistíš nástrojem.`,
    cfg.system_prompt?.trim() ? `## ZADÁNÍ Z VELÍNU (role, styl, kanály):\n${cfg.system_prompt.trim()}` : '',
    `## JAK PRACOVAT
1. Než napíšeš návrh, zjisti fakta: kontext vlákna a rezervace níže, znalostní báze, a když něco chybí, ZAVOLEJ nástroj (get_customer_overview, get_access_status, calculate_price, get_availability, get_policies, get_faq, get_legal_document, get_extras_catalog, get_branches, get_motorcycle_manual, search_troubleshooting, find_booking…). Nikdy nehádej.
2. Odpověz přímo na to, na co se zákazník ptá — konkrétně (jeho motorka, jeho termín, jeho pobočka). Neopakuj, co už tým ve vlákně napsal; navaž na to.
3. Nástroje veřejného agenta, které tu NEMÁŠ (create_booking_request, redirect_to_booking, preview_booking_change, apply_booking_change, find_my_booking, lookup_my_bookings, get_booking_emails, get_booking_readiness, get_order_status), nahraď: údaje o rezervaci/e-mailech/objednávkách máš přes get_customer_overview a find_booking; vytvoření nebo změnu rezervace zákazníkovi popíšeš (formulář v appce/na webu, detail rezervace → „Upravit rezervaci", motogo24.cz/upravit-rezervaci), případně do admin_note napíšeš, co má admin udělat ručně.
4. Formát ---JSON--- / suggest_sos ze sekcí níže IGNORUJ — tvůj výstupní formát je na konci. Pravidla o oslovení a jazyku platí; o délce odpovědi rozhoduje limit kanálu níže (má přednost před pravidly web chatu).
5. Rozhodnutí o penězích (refund nad rámec pravidel, výjimka ze storna, sleva, uznání reklamace, škody) nevyslovuj za firmu — navrhni neutrální formulaci a do admin_note napiš, co musí rozhodnout člověk. Přístupové kódy (číslice) NIKDY nepiš.`,
    buildDateHeader(),
    formatFleetSnapshot(k.fleet),
    formatBranchesSnapshot(k.branches),
    '## PROVOZNÍ ZNALOSTI (servisní agent v appce)\n' + SERVICE_OPS_KNOWLEDGE + SEASON_NOTE + APP_PAY_NOTE,
    '## PRAVIDLA A ZNALOSTI VEŘEJNÉHO AGENTA (web)\n' + HARD_RULES_CS,
    buildCompanyBrain(k.company),
    k.kb,
    ['## USTÁLENÉ ÚPRAVY Z VELÍNU (nastavení všech AI agentů — při rozporu s obecnými pravidly mají přednost)',
      rules('Agent zákaznických zpráv (tento)', cfg), rules('Servisní agent v appce', k.motoCfg), rules('Veřejný agent na webu', k.pubCfg)]
      .filter(Boolean).join('\n\n'),
  ].filter(Boolean).join('\n\n')

  const c = ctx.customer || {}
  const dyn = [
    ctx.staffExamples,
    `## TOTO VLÁKNO
- Kanál: ${ctx.channel} — limit ${lim.max_chars} znaků (${lim.hint})
- Tón: ${TONE[cfg.tone || ''] || 'přátelský a vstřícný'}; oslovení a jazyk zrcadli podle zákazníka
- Předmět vlákna: ${ctx.thread.subject || '—'}
- Zákazník: ${ctx.customerId ? `${c.full_name || '?'} | ${c.email || '?'} | ${c.phone || '?'} | jazyk ${c.language || 'cs'} | ŘP ${Array.isArray(c.license_group) ? (c.license_group as string[]).join(', ') : c.license_group || '?'}${c.is_blocked ? ' | ZABLOKOVANÝ' : ''} [customer_id=${ctx.customerId}]` : 'nepřiřazen (dohledej přes find_booking)'}`,
    ctx.bookingContext + ctx.bookingsList,
    '## HISTORIE VLÁKNA (od nejstarší)\n' + (ctx.history.map((h) =>
      `[${dirLabel(h.direction)} ${String(h.created_at).slice(0, 16).replace('T', ' ')}] ${(h.content || '').slice(0, 1500)}`).join('\n') || '(prázdná)'),
    `## VÝSTUPNÍ FORMÁT
Vrať POUZE validní JSON (bez dalšího textu):
{"reply": "hotový text odpovědi zákazníkovi", "confidence": "low|medium|high", "admin_note": "stručně pro admina: z čeho jsi vycházel, co ověřit nebo co musí udělat ručně; null když není co"}`,
  ].filter(Boolean).join('\n\n')

  return [
    { type: 'text' as const, text: staticPart, cache_control: { type: 'ephemeral' as const } },
    { type: 'text' as const, text: dyn },
  ]
}
