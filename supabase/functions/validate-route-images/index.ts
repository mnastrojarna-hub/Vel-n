/**
 * MotoGo24 — Edge Function: validate-route-images
 *
 * Zkontroluje VŠECHNY fotky tras (`routes.cover_image` + `routes.images`)
 * a bodů zájmu (`route_pois.image_url` + `route_pois.images`) a mrtvé
 * Wikimedia odkazy automaticky opraví:
 *   1. každou unikátní URL ověří přes HEAD (s ?width=320 u Wikimedia — levné),
 *   2. mrtvou Wikimedia URL zkusí nahradit hlavní fotkou článku Wikipedie
 *      (cs → en) dle názvu bodu zájmu / trasy (API prop=pageimages),
 *   3. neopravitelné URL z polí `images` vyřadí; `image_url`/`cover_image`
 *      nahradí první živou fotkou z pole (nebo NULL → appka ukáže placeholder).
 *
 * POZN. k rychlosti v appce: rychlé načítání NEřeší tato funkce, ale klient —
 * appka si Wikimedia URL sama přepisuje na thumbnail (?width=…). Tahle funkce
 * řeší JEN mrtvé odkazy (fotka se nenačte vůbec).
 *
 * POST /functions/v1/validate-route-images
 * Body (vše volitelné):
 *   {
 *     dry_run?: boolean,   // true = jen report, nic nezapisuje (default false)
 *     limit?: number,      // max řádků tras+POI na jeden běh (default 200)
 *     offset?: number,     // stránkování pro velké dávky (default 0)
 *     scope?: 'routes' | 'pois' | 'all',  // default 'all'
 *   }
 * Odpověď: { success, checked, ok, fixed, dropped, updated_rows, details[] }
 *
 * Bezpečnost: vyžaduje service_role Bearer token (volá se ze SQL editoru /
 * serveru, NE z prohlížeče zákazníka).
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

// Wikimedia vyžaduje popisný User-Agent (jinak 403)
const UA = 'MotoGo24RouteImageBot/1.0 (+https://motogo24.cz; info@motogo24.cz)'

const isWiki = (u: string) => /wikimedia\.org|wikipedia\.org/i.test(u)

/** HEAD check — u Wikimedia s width=320 (ověří existenci souboru levně). */
async function urlAlive(url: string): Promise<boolean> {
  try {
    let u = url
    if (isWiki(u) && /special:filepath/i.test(u) && !/width=/i.test(u)) {
      u += (u.includes('?') ? '&' : '?') + 'width=320'
    }
    const res = await fetch(u, {
      method: 'HEAD',
      redirect: 'follow',
      headers: { 'User-Agent': UA },
      signal: AbortSignal.timeout(8000),
    })
    if (!res.ok) return false
    const ct = res.headers.get('content-type') || ''
    return ct.startsWith('image/')
  } catch (_) {
    return false
  }
}

/** Najde hlavní fotku článku Wikipedie pro daný název (cs, pak en).
 *  Vrací Special:FilePath URL (konzistentní formát — appka si přidá ?width=). */
async function wikiPageImage(title: string): Promise<string | null> {
  for (const lang of ['cs', 'en']) {
    try {
      const api = `https://${lang}.wikipedia.org/w/api.php?action=query&format=json` +
        `&redirects=1&prop=pageimages&piprop=name&titles=${encodeURIComponent(title)}`
      const res = await fetch(api, {
        headers: { 'User-Agent': UA },
        signal: AbortSignal.timeout(8000),
      })
      if (!res.ok) continue
      const data = await res.json()
      const pages = data?.query?.pages || {}
      for (const k of Object.keys(pages)) {
        const name = pages[k]?.pageimage
        if (name && typeof name === 'string') {
          return 'https://commons.wikimedia.org/wiki/Special:FilePath/' +
            encodeURIComponent(name)
        }
      }
    } catch (_) { /* zkus další jazyk */ }
  }
  return null
}

type Detail = { table: string; id: string; name: string; action: string; url?: string }

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  // Jen service_role smí spouštět (funkce zapisuje přes service klienta)
  const auth = req.headers.get('authorization') || ''
  if (!auth.includes(SUPABASE_SERVICE_KEY)) {
    return new Response(JSON.stringify({ error: 'service_role required' }), {
      status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const body = await req.json().catch(() => ({}))
  const dryRun: boolean = body.dry_run === true
  const limit: number = Math.min(Number(body.limit) || 200, 500)
  const offset: number = Number(body.offset) || 0
  const scope: string = body.scope || 'all'

  const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  const aliveCache = new Map<string, boolean>()
  const fixCache = new Map<string, string | null>()
  const details: Detail[] = []
  let checked = 0, okCount = 0, fixed = 0, dropped = 0, updatedRows = 0

  async function check(url: string): Promise<boolean> {
    if (aliveCache.has(url)) return aliveCache.get(url)!
    checked++
    const ok = await urlAlive(url)
    aliveCache.set(url, ok)
    if (ok) okCount++
    return ok
  }

  /** Vrátí opravenou verzi seznamu fotek (mrtvé nahradí/vyřadí). */
  async function repair(name: string, urls: string[]): Promise<{ list: string[]; changed: boolean }> {
    const out: string[] = []
    let changed = false
    for (const u of urls) {
      if (!u) { changed = true; continue }
      if (await check(u)) { out.push(u); continue }
      changed = true
      // pokus o náhradu přes Wikipedii dle názvu bodu/trasy
      let repl = fixCache.has(name) ? fixCache.get(name)! : null
      if (!fixCache.has(name)) {
        repl = await wikiPageImage(name)
        if (repl && !(await check(repl))) repl = null
        fixCache.set(name, repl)
      }
      if (repl && !out.includes(repl)) { out.push(repl); fixed++ }
      else dropped++
    }
    return { list: [...new Set(out)], changed }
  }

  // ── Trasy ──
  if (scope === 'all' || scope === 'routes') {
    const { data: routes, error } = await db
      .from('routes')
      .select('id, name, cover_image, images')
      .order('created_at')
      .range(offset, offset + limit - 1)
    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }
    for (const r of routes || []) {
      const all = [r.cover_image, ...(r.images || [])].filter(Boolean) as string[]
      const { list, changed } = await repair(r.name, all)
      if (!changed) continue
      const patch = { cover_image: list[0] ?? null, images: list }
      details.push({ table: 'routes', id: r.id, name: r.name, action: 'updated', url: patch.cover_image ?? undefined })
      if (!dryRun) {
        const { error: e2 } = await db.from('routes').update(patch).eq('id', r.id)
        if (!e2) updatedRows++
      }
    }
  }

  // ── Body zájmu ──
  if (scope === 'all' || scope === 'pois') {
    const { data: pois, error } = await db
      .from('route_pois')
      .select('id, name, image_url, images')
      .order('created_at')
      .range(offset, offset + limit - 1)
    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }
    for (const p of pois || []) {
      const all = [p.image_url, ...(p.images || [])].filter(Boolean) as string[]
      const { list, changed } = await repair(p.name, all)
      if (!changed) continue
      const patch = { image_url: list[0] ?? null, images: list }
      details.push({ table: 'route_pois', id: p.id, name: p.name, action: 'updated', url: patch.image_url ?? undefined })
      if (!dryRun) {
        const { error: e2 } = await db.from('route_pois').update(patch).eq('id', p.id)
        if (!e2) updatedRows++
      }
    }
  }

  return new Response(JSON.stringify({
    success: true, dry_run: dryRun, scope, limit, offset,
    checked, ok: okCount, fixed, dropped, updated_rows: updatedRows,
    details: details.slice(0, 200),
  }), { headers: { ...CORS, 'Content-Type': 'application/json' } })
})
