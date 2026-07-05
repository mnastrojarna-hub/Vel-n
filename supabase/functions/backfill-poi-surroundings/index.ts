/**
 * MotoGo24 — Edge Function: backfill-poi-surroundings
 *
 * Dávkově dogeneruje KONKRÉTNÍ popis okolí (`surroundings`) u bodů zájmu —
 * katalogové `points_of_interest` i body na trase `route_pois` — a hned ho
 * (i případně doplněný `description`) přeloží do všech jazyků přes ověřenou
 * edge fn `translate-content`. Popis je konkrétní k DANÉMU místu (název +
 * kategorie + kraj/země + stávající popis + GPS), 2–3 věty, bez smyšlených
 * faktů.
 *
 * „Samovyprazdňovací" model: vybere řádky, kde `surroundings is null`,
 * zpracuje max `limit` a skončí. Opakovaným voláním (DB cron
 * `trigger_poi_surroundings_backfill`) se DB postupně vyprázdní; když už nic
 * nechybí, vrátí `done:true` a cron se sám odplánuje.
 *
 * POST /functions/v1/backfill-poi-surroundings
 * Body (vše volitelné): { scope?: 'catalog'|'route_pois'|'all' (def 'all'),
 *   limit?: number (def 8, max 25), concurrency?: number (def 2) }
 * Auth: Bearer service_role (ručně nebo z DB cronu — klíč z app_settings).
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY') || ''
const MODEL = 'claude-haiku-4-5-20251001'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const CAT_LABEL: Record<string, string> = {
  food: 'restaurace / občerstvení', castle: 'hrad / zámek', lookout: 'rozhledna / vyhlídka',
  water: 'vodní plocha (přehrada/jezero/rybník)', sights: 'památka / zajímavost',
  nature: 'přírodní lokalita', military: 'vojenská památka / opevnění',
  aviation: 'letecká památka / muzeum', tech: 'technická / průmyslová památka',
  moto: 'motoristická zajímavost (okruh, muzeum)', other: 'zajímavé místo',
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

function buildPrompt(row: any, catalog: boolean): string {
  const cat = catalog ? (CAT_LABEL[row.category] || 'zajímavé místo') : 'bod zájmu na motorkářské trase'
  const where = [row.region, row.country].filter(Boolean).join(', ')
  const needDesc = !row.description || String(row.description).trim().length < 40
  const parts = [
    `Jsi znalec cestování a motorkářských výletů po Evropě. Napiš text o KONKRÉTNÍM místě:`,
    `- Název: ${row.name}`,
    `- Typ: ${cat}`,
    where ? `- Poloha: ${where}` : '',
    (row.lat && row.lng) ? `- GPS: ${row.lat}, ${row.lng}` : '',
    row.description ? `- Stávající popis: ${String(row.description).slice(0, 400)}` : '',
    '',
    'Vrať STRIKTNĚ validní JSON objekt v ČEŠTINĚ s klíči:',
    `- "surroundings": 3–4 věty (cca 55–90 slov) o OKOLÍ tohoto konkrétního místa — co je v bezprostřední blízkosti k vidění, jaká je krajina/terén, jaké další KONKRÉTNÍ zajímavosti (jménem) jsou poblíž a proč se sem na motorce vyplatí zajet.`,
    needDesc
      ? `- "description": 3–4 věty (cca 55–90 slov) — poutavý, konkrétní popis samotného místa: co to je, čím je výjimečné, co tam návštěvník uvidí/zažije.`
      : '',
    '',
    'PRAVIDLA (KRITICKÁ — FAKTICKÁ PŘESNOST PŘED VŠÍM):',
    '- NIKDY si NEVYMÝŠLEJ fakta. Používej VÝHRADNĚ informace, kterými si jsi opravdu jistý: údaje uvedené výše (název, typ, poloha, stávající popis) a všeobecně známá, ověřená fakta o tomto konkrétním místě a jeho regionu.',
    '- ZAKÁZÁNO uvádět konkrétní letopočty, jména stavitelů/majitelů, rozměry, nadmořské výšky, vzdálenosti v km, statistiky nebo názvy blízkých objektů, pokud si jimi nejsi JISTÝ. Když fakt neznáš, prostě ho vynech — nedomýšlej ho.',
    '- Když o místě víš málo, popiš PRAVDIVĚ jen to, co plyne z názvu/typu/regionu (charakter objektu, typ krajiny oblasti) — stručně a věcně. Radši kratší a pravdivé než delší a smyšlené.',
    '- Zároveň se vyhni prázdným klišé („krásné místo v přírodě", „stojí za návštěvu") — buď konkrétní tam, kde máš jistá fakta.',
    '- Zachovej vlastní jména a názvy míst v původním tvaru. Piš čtivě, ale věcně (žádná reklamní vata).',
    '- Žádný markdown, žádné uvozovky navíc — jen čistý JSON objekt.',
  ].filter(Boolean)
  return parts.join('\n')
}

async function generate(row: any, catalog: boolean): Promise<{ surroundings?: string; description?: string } | null> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({ model: MODEL, max_tokens: 700, messages: [{ role: 'user', content: buildPrompt(row, catalog) }] }),
  })
  if (!res.ok) throw new Error(`anthropic ${res.status}: ${(await res.text()).slice(0, 200)}`)
  const data = await res.json()
  const text = (data?.content?.[0]?.text || '').trim()
  let parsed: Record<string, string>
  try { parsed = JSON.parse(text) }
  catch {
    const a = text.indexOf('{'), b = text.lastIndexOf('}')
    if (a === -1 || b <= a) return null
    parsed = JSON.parse(text.slice(a, b + 1))
  }
  const out: { surroundings?: string; description?: string } = {}
  if (typeof parsed.surroundings === 'string' && parsed.surroundings.trim()) out.surroundings = parsed.surroundings.trim()
  if (typeof parsed.description === 'string' && parsed.description.trim()) out.description = parsed.description.trim()
  return out.surroundings ? out : null
}

async function translate(table: string, id: string, fields: Record<string, string>): Promise<void> {
  await fetch(`${SUPABASE_URL}/functions/v1/translate-content`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ table, id, fields, target_langs: ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'] }),
  }).catch(() => {})
}

async function fetchMissing(db: any, table: string, limit: number) {
  const cols = table === 'points_of_interest'
    ? 'id, name, description, category, country, region, lat, lng'
    : 'id, name, description, lat, lng'
  const { data, error } = await db.from(table).select(cols).is('surroundings', null).limit(limit)
  if (error) throw new Error(error.message)
  return data || []
}

async function processTable(db: any, table: string, rows: any[], concurrency: number) {
  const catalog = table === 'points_of_interest'
  let processed = 0, failed = 0
  for (let i = 0; i < rows.length; i += concurrency) {
    const chunk = rows.slice(i, i + concurrency)
    await Promise.all(chunk.map(async (r: any) => {
      try {
        const gen = await generate(r, catalog)
        if (!gen || !gen.surroundings) { failed++; return }
        const patch: Record<string, string> = { surroundings: gen.surroundings }
        if (gen.description) patch.description = gen.description
        const { error } = await db.from(table).update(patch).eq('id', r.id)
        if (error) { failed++; return }
        // Hned přelož do všech jazyků (surroundings + případně nový description).
        await translate(table, r.id, patch)
        processed++
      } catch (_) { failed++ }
    }))
  }
  return { processed, failed }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const auth = req.headers.get('authorization') || ''
  if (!auth.includes(SUPABASE_SERVICE_KEY)) return jsonResponse({ error: 'service_role required' }, 401)
  if (!ANTHROPIC_API_KEY) return jsonResponse({ error: 'ANTHROPIC_API_KEY not configured' }, 500)

  const body = await req.json().catch(() => ({}))
  const scope: string = body.scope || 'all'
  const limit: number = Math.min(Math.max(Number(body.limit) || 8, 1), 25)
  const concurrency: number = Math.min(Math.max(Number(body.concurrency) || 2, 1), 4)
  const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  try {
    // Pořadí: nejdřív katalogové body (vidí je nejvíc uživatelů), pak body na trase.
    let table = 'points_of_interest'
    let rows: any[] = []
    if (scope === 'route_pois') { table = 'route_pois'; rows = await fetchMissing(db, table, limit) }
    else if (scope === 'catalog') { rows = await fetchMissing(db, table, limit) }
    else {
      rows = await fetchMissing(db, 'points_of_interest', limit)
      if (rows.length === 0) { table = 'route_pois'; rows = await fetchMissing(db, table, limit) }
    }
    if (rows.length === 0) return jsonResponse({ success: true, table, processed: 0, failed: 0, done: true })
    const { processed, failed } = await processTable(db, table, rows, concurrency)
    return jsonResponse({ success: true, table, limit, processed, failed })
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500)
  }
})
