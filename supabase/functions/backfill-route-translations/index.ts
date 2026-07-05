/**
 * MotoGo24 — Edge Function: backfill-route-translations
 *
 * Dávkově dopřeloží trasy (`routes`) a body zájmu (`route_pois`) — pole
 * `name` + `description` — do všech jazyků, aby žádná trasa ani bod nezůstaly
 * bez překladu. Interně volá ověřenou funkci `translate-content` (per řádek).
 *
 * „Samovyprazdňovací" model: vybere řádky, kterým chybí KTERÝKOLI z cílových
 * jazyků (name, nebo description pokud řádek popis má) — dřívější proxy „chybí
 * jen en.name" nechávala částečně přeložené řádky (padlý jazyk, ručně přepsaný
 * název) navždy nedopřeložené. Přeloží jich max `limit` a skončí.
 * Opakovaným voláním (cron) se DB postupně vyprázdní; když už nic nechybí,
 * vrátí `processed:0`. Není potřeba stránkovat offsetem.
 *
 * POST /functions/v1/backfill-route-translations
 * Body (vše volitelné):
 *   { scope?: 'routes'|'pois'|'all' (def 'all'), limit?: number (def 12, max 40),
 *     target_langs?: string[], concurrency?: number (def 3) }
 * Odpověď: { success, table, limit, processed, failed, details[] }
 *
 * Volá se buď ručně (Bearer service_role), nebo z DB cronu
 * `trigger_route_translation_backfill()` (klíč z app_settings) — stejný vzor
 * jako send-push.
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DEFAULT_LANGS = ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
}

async function callTranslateContent(table: string, id: string, fields: Record<string, string>, langs: string[]): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/translate-content`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ table, id, fields, target_langs: langs }),
  })
  return res.ok
}

/** PostgREST OR podmínka: chybí name v některém jazyce, nebo description
 *  v některém jazyce u řádku, který popis má. */
const MISSING_OR = DEFAULT_LANGS.flatMap((l) => [
  `translations->${l}->>name.is.null`,
  `and(description.not.is.null,translations->${l}->>description.is.null)`,
]).join(',')

/** Vybere řádky, kterým chybí překlad v kterémkoli cílovém jazyce. */
async function fetchMissing(db: any, table: string, limit: number) {
  const { data, error } = await db
    .from(table)
    .select('id, name, description')
    .or(MISSING_OR)
    .limit(limit)
  if (error) throw new Error(error.message)
  return data || []
}

async function processTable(db: any, table: string, rows: any[], langs: string[], concurrency: number) {
  let processed = 0, failed = 0
  const details: any[] = []
  for (let i = 0; i < rows.length; i += concurrency) {
    const chunk = rows.slice(i, i + concurrency)
    await Promise.all(chunk.map(async (r: any) => {
      const fields: Record<string, string> = {}
      if (typeof r.name === 'string' && r.name.trim()) fields.name = r.name
      if (typeof r.description === 'string' && r.description.trim()) fields.description = r.description
      if (Object.keys(fields).length === 0) return
      const ok = await callTranslateContent(table, r.id, fields, langs)
      if (ok) processed++; else { failed++; details.push({ table, id: r.id, name: r.name }) }
    }))
  }
  return { processed, failed, details }
}

/** Je token service_role JWT? Kontroluje claim `role` (ne přesnou shodu) —
 *  projekt může mít nový formát klíčů sb_secret_ / víc platných klíčů. */
function isServiceRole(token: string): boolean {
  try {
    const p = token.split('.')
    if (p.length !== 3) return false
    const pad = '='.repeat((4 - (p[1].length % 4)) % 4)
    const payload = JSON.parse(atob(p[1].replace(/-/g, '+').replace(/_/g, '/') + pad))
    return payload.role === 'service_role'
  } catch (_) { return false }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

  // ── Autorizace (tolerantní jako mirror-route-images) — cron posílá Bearer =
  // app_settings.service_role_key, který se u nového formátu klíčů (sb_secret_…)
  // NEROVNÁ env SUPABASE_SERVICE_ROLE_KEY → striktní shoda dávala 401 a překlady
  // se nedoplňovaly. Přijmi env klíč, JWT service_role, nebo app_settings klíč.
  let bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (bearer.length > 1 && bearer.startsWith('"') && bearer.endsWith('"')) bearer = bearer.slice(1, -1)
  let authOk = bearer.length > 0 && (bearer === SUPABASE_SERVICE_KEY || isServiceRole(bearer))
  if (!authOk && bearer.length > 0) {
    const { data: row } = await db.from('app_settings').select('value').eq('key', 'service_role_key').maybeSingle()
    if (row?.value && bearer === String(row.value).replace(/^"|"$/g, '').trim()) authOk = true
  }
  if (!authOk) return jsonResponse({ error: 'service_role required' }, 401)

  const body = await req.json().catch(() => ({}))
  const scope: string = body.scope || 'all'
  const limit: number = Math.min(Math.max(Number(body.limit) || 12, 1), 40)
  const langs: string[] = Array.isArray(body.target_langs) && body.target_langs.length > 0 ? body.target_langs : DEFAULT_LANGS
  const concurrency: number = Math.min(Math.max(Number(body.concurrency) || 3, 1), 6)

  try {
    // Pořadí: nejdřív trasy, pak body zájmu (u scope='all').
    let table = 'routes'
    let rows: any[] = []
    if (scope === 'pois') {
      table = 'route_pois'
      rows = await fetchMissing(db, table, limit)
    } else if (scope === 'routes') {
      rows = await fetchMissing(db, 'routes', limit)
    } else {
      rows = await fetchMissing(db, 'routes', limit)
      if (rows.length === 0) { table = 'route_pois'; rows = await fetchMissing(db, table, limit) }
    }

    if (rows.length === 0) return jsonResponse({ success: true, table, limit, processed: 0, failed: 0, done: true })

    const { processed, failed, details } = await processTable(db, table, rows, langs, concurrency)
    return jsonResponse({ success: true, table, limit, processed, failed, details: details.slice(0, 40) })
  } catch (e) {
    return jsonResponse({ error: String(e instanceof Error ? e.message : e) }, 500)
  }
})
