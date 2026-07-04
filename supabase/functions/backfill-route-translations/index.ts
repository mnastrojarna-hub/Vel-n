/**
 * MotoGo24 — Edge Function: backfill-route-translations
 *
 * Dávkově dopřeloží VŠECHNY trasy (`routes`) a body zájmu (`route_pois`) —
 * pole `name` + `description` — do všech jazyků, aby žádná trasa ani bod
 * nezůstaly bez překladu. Interně volá ověřenou funkci `translate-content`
 * (per řádek), takže překlad je konzistentní se zbytkem webu/appky.
 *
 * Proč dávkově: řádků jsou tisíce a jedna edge invokace má časový limit.
 * Voláš opakovaně s posunem `offset`, dokud `processed > 0`.
 *
 * POST /functions/v1/backfill-route-translations
 * Body (vše volitelné):
 *   {
 *     scope?: 'routes' | 'pois' | 'all',   // default 'all'
 *     limit?: number,                       // řádků na běh (default 12, max 40)
 *     offset?: number,                      // stránkování (default 0)
 *     only_missing?: boolean,               // default true = přeskoč už přeložené
 *     target_langs?: string[],              // default = jako translate-content
 *     concurrency?: number,                 // souběžných řádků (default 3)
 *   }
 * Odpověď: { success, scope, limit, offset, scanned, processed, skipped, failed, next_offset, details[] }
 *
 * Bezpečnost: vyžaduje service_role Bearer token.
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

/** Potřebuje řádek překlad? = některý cílový jazyk nemá přeložený `name`
 *  (nebo `description`, pokud v CZ existuje). */
function needsTranslation(row: any, langs: string[]): boolean {
  const tr = row.translations && typeof row.translations === 'object' ? row.translations : {}
  const hasDesc = typeof row.description === 'string' && row.description.trim().length > 0
  for (const l of langs) {
    const t = tr[l]
    if (!t || typeof t !== 'object') return true
    if (typeof t.name !== 'string' || t.name.trim() === '') return true
    if (hasDesc && (typeof t.description !== 'string' || t.description.trim() === '')) return true
  }
  return false
}

async function callTranslateContent(table: string, id: string, fields: Record<string, string>, langs: string[]): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/translate-content`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ table, id, fields, target_langs: langs }),
  })
  return res.ok
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const auth = req.headers.get('authorization') || ''
  if (!auth.includes(SUPABASE_SERVICE_KEY)) {
    return jsonResponse({ error: 'service_role required' }, 401)
  }

  const body = await req.json().catch(() => ({}))
  const scope: string = body.scope || 'all'
  const limit: number = Math.min(Math.max(Number(body.limit) || 12, 1), 40)
  const offset: number = Number(body.offset) || 0
  const onlyMissing: boolean = body.only_missing !== false
  const langs: string[] = Array.isArray(body.target_langs) && body.target_langs.length > 0
    ? body.target_langs : DEFAULT_LANGS
  const concurrency: number = Math.min(Math.max(Number(body.concurrency) || 3, 1), 6)

  const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  const table = scope === 'pois' ? 'route_pois' : 'routes' // 'all' zpracuj po dvou bězích (routes, pak pois)

  const { data, error } = await db
    .from(table)
    .select('id, name, description, translations')
    .order('created_at')
    .range(offset, offset + limit - 1)
  if (error) return jsonResponse({ error: error.message }, 500)

  const rows = data || []
  let processed = 0, skipped = 0, failed = 0
  const details: any[] = []

  // zpracuj po malých skupinách (concurrency), aby se nepřekročil rate limit
  for (let i = 0; i < rows.length; i += concurrency) {
    const chunk = rows.slice(i, i + concurrency)
    await Promise.all(chunk.map(async (r: any) => {
      if (onlyMissing && !needsTranslation(r, langs)) { skipped++; return }
      const fields: Record<string, string> = {}
      if (typeof r.name === 'string' && r.name.trim()) fields.name = r.name
      if (typeof r.description === 'string' && r.description.trim()) fields.description = r.description
      if (Object.keys(fields).length === 0) { skipped++; return }
      const ok = await callTranslateContent(table, r.id, fields, langs)
      if (ok) { processed++ } else { failed++; details.push({ id: r.id, name: r.name }) }
    }))
  }

  return jsonResponse({
    success: true, scope: table, limit, offset,
    scanned: rows.length, processed, skipped, failed,
    next_offset: rows.length === limit ? offset + limit : null, // null = konec
    details: details.slice(0, 40),
  })
})
