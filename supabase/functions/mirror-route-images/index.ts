// mirror-route-images — zrcadlení fotek tras/bodů zájmu do vlastního storage.
//
// PROČ: Seed tras odkazuje ~1800 fotek hotlinkem na Wikimedia Commons
// (Special:FilePath). Wikimedia neprohlížečové klienty throttluje (403/429)
// a thumbnaily generuje líně → v appce se fotky načítají pomalu, náhodně,
// nebo vůbec. Definitivní řešení: fotky jednorázově stáhnout server-side
// (zmenšené na 1280 px), nahrát do public bucketu `media` pod
// `routes-mirror/…` a přepsat URL v `routes` + `route_pois`. Appka pak vše
// tahá z vlastního CDN (RouteImage navíc umí render/image zmenšeniny).
//
// Chování: dávkové — jeden běh zpracuje max MAX_IMAGES fotek nebo běží max
// TIME_BUDGET_MS; vrací kolik zbývá. Volat opakovaně (ručně / cron), dokud
// `remaining_rows` > 0. Když nezbývá nic, běh je levný no-op → cron může
// zůstat naplánovaný a automaticky pozrcadlí i budoucí wiki URL.
//
// Auth: verify_jwt zapnuté (default). Uvnitř navíc: service role key NEBO
// admin JWT (RPC is_admin) — funkce zapisuje do DB a storage.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_IMAGES = 200 // strop fotek na jeden běh
const TIME_BUDGET_MS = 280_000 // ~280 s (limit gatewaye je 400 s wall-clock)
const FETCH_DELAY_MS = 120 // slušnost k Wikimedii
const THUMB_WIDTH = 1280 // dost pro hero i fullscreen, ~150–400 KB

// Wikimedia vyžaduje popisný User-Agent, jinak 403.
const WIKI_HEADERS = {
  'User-Agent': 'MotoGo24Mirror/1.0 (+https://motogo24.cz; info@motogo24.cz)',
}

const isWiki = (u: unknown): u is string =>
  typeof u === 'string' &&
  (u.includes('wikimedia.org') || u.includes('wikipedia.org'))

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

async function sha1hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(s))
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
}

/// Stáhne fotku — nejdřív zmenšeninu (?width=), při neúspěchu originál.
async function fetchWiki(url: string): Promise<{ bytes: Uint8Array; type: string } | null> {
  const sep = url.includes('?') ? '&' : '?'
  for (const u of [`${url}${sep}width=${THUMB_WIDTH}`, url]) {
    try {
      const r = await fetch(u, { headers: WIKI_HEADERS })
      if (!r.ok) continue
      const type = (r.headers.get('content-type') || 'image/jpeg').split(';')[0].trim()
      if (!type.startsWith('image/')) continue
      const bytes = new Uint8Array(await r.arrayBuffer())
      if (bytes.length < 100) continue
      return { bytes, type }
    } catch (_) {
      /* zkus další variantu */
    }
  }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const sb = createClient(SUPABASE_URL, SERVICE_KEY)

  // ── Autorizace: service role key, nebo admin JWT ──
  const bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '')
  if (bearer !== SERVICE_KEY) {
    try {
      const caller = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
        global: { headers: { Authorization: `Bearer ${bearer}` } },
      })
      const { data: isAdmin } = await caller.rpc('is_admin')
      if (isAdmin !== true) return json({ error: 'forbidden' }, 403)
    } catch (_) {
      return json({ error: 'forbidden' }, 403)
    }
  }

  const task = runBatch(sb).catch(async (e) => {
    await sb.from('debug_log').insert({
      source: 'mirror-route-images',
      action: 'batch',
      component: 'edge_function',
      status: 'error',
      request_data: { error: String(e) },
    }).then(() => {}, () => {})
    return { error: String(e) }
  })

  // ?wait=1 → počkej a vrať výsledek (ruční kick curl-em / ověření).
  // Jinak (cron přes pg_net, který čeká jen ~5 s): odpověz HNED a dávku
  // dokonči na pozadí, ať gateway spojení neutne a runtime funkci nezabije.
  const wait = new URL(req.url).searchParams.get('wait')
  if (wait === '1' || wait === 'true') {
    return json({ success: true, ...(await task) })
  }
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime
  if (rt?.waitUntil) {
    rt.waitUntil(task)
    return json({ success: true, started: true }, 202)
  }
  return json({ success: true, ...(await task) }) // lokální běh bez EdgeRuntime
})

/// Jedna dávka zrcadlení — max MAX_IMAGES fotek / TIME_BUDGET_MS.
async function runBatch(sb: ReturnType<typeof createClient>) {
  const t0 = Date.now()
  const outOfBudget = () => Date.now() - t0 > TIME_BUDGET_MS

  {
    // ── Načti kandidáty (malé sloupce; ~50 tras + ~950 bodů) ──
    const [routesQ, poisQ] = await Promise.all([
      sb.from('routes').select('id, cover_image, images'),
      sb.from('route_pois').select('id, image_url, images'),
    ])
    if (routesQ.error) throw routesQ.error
    if (poisQ.error) throw poisQ.error

    type Row = { table: 'routes' | 'route_pois'; id: string; patch: Record<string, unknown>; urls: string[] }
    const rows: Row[] = []
    for (const r of routesQ.data || []) {
      const urls = [
        ...(isWiki(r.cover_image) ? [r.cover_image] : []),
        ...((r.images || []) as unknown[]).filter(isWiki),
      ]
      if (urls.length) rows.push({ table: 'routes', id: r.id, patch: { cover_image: r.cover_image, images: r.images }, urls })
    }
    for (const p of poisQ.data || []) {
      const urls = [
        ...(isWiki(p.image_url) ? [p.image_url] : []),
        ...((p.images || []) as unknown[]).filter(isWiki),
      ]
      if (urls.length) rows.push({ table: 'route_pois', id: p.id, patch: { image_url: p.image_url, images: p.images }, urls })
    }

    // ── Zrcadli (cache přes duplicitní URL — stejná fotka u více řádků) ──
    const mirrored = new Map<string, string>() // stará URL → nová URL
    const failed = new Set<string>()
    let images = 0
    let updated = 0
    let processedRows = 0

    for (const row of rows) {
      if (outOfBudget() || images >= MAX_IMAGES) break
      let rowOk = true

      for (const url of new Set(row.urls)) {
        if (mirrored.has(url)) continue
        if (failed.has(url)) { rowOk = false; continue }
        if (outOfBudget() || images >= MAX_IMAGES) { rowOk = false; break }

        const img = await fetchWiki(url)
        images++
        await new Promise((res) => setTimeout(res, FETCH_DELAY_MS))
        if (!img) { failed.add(url); rowOk = false; continue }

        const path = `routes-mirror/${await sha1hex(url)}.${EXT[img.type] || 'jpg'}`
        const up = await sb.storage.from('media').upload(path, img.bytes, {
          contentType: img.type,
          upsert: true,
        })
        if (up.error) { failed.add(url); rowOk = false; continue }
        mirrored.set(url, sb.storage.from('media').getPublicUrl(path).data.publicUrl)
      }

      // Přepiš URL v řádku (jen ty úspěšně zrcadlené; zbytek doběhne příště).
      const swap = (v: unknown) => (typeof v === 'string' && mirrored.has(v) ? mirrored.get(v)! : v)
      const patch: Record<string, unknown> = {}
      if ('cover_image' in row.patch && isWiki(row.patch.cover_image) && mirrored.has(row.patch.cover_image as string)) {
        patch.cover_image = swap(row.patch.cover_image)
      }
      if ('image_url' in row.patch && isWiki(row.patch.image_url) && mirrored.has(row.patch.image_url as string)) {
        patch.image_url = swap(row.patch.image_url)
      }
      const imgs = row.patch.images as unknown[] | null
      if (Array.isArray(imgs) && imgs.some((u) => isWiki(u) && mirrored.has(u as string))) {
        patch.images = imgs.map(swap)
      }
      if (Object.keys(patch).length > 0) {
        const upd = await sb.from(row.table).update(patch).eq('id', row.id)
        if (!upd.error) updated++
      }
      if (rowOk) processedRows++
    }

    const result = {
      rows_with_wiki: rows.length,
      rows_done: processedRows,
      rows_updated: updated,
      images_fetched: images,
      images_failed: failed.size,
      remaining_rows: Math.max(0, rows.length - processedRows),
      ms: Date.now() - t0,
    }

    // Loguj jen běhy, které něco dělaly (jinak by no-op cron spamoval debug_log).
    if (rows.length > 0 || failed.size > 0) {
      await sb.from('debug_log').insert({
        source: 'mirror-route-images',
        action: 'batch',
        component: 'edge_function',
        status: failed.size > 0 ? 'partial' : 'ok',
        request_data: result,
      })
    }
    return result
  }
}
