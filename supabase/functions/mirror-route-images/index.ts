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

const MAX_IMAGES = 800 // strop fotek na jeden běh (reálně limituje čas níže)
const TIME_BUDGET_MS = 280_000 // ~280 s (limit gatewaye je 400 s wall-clock)
const CONCURRENCY = 4 // souběžných stažení+uploadů (výš už weserv škrtí 429)
const THUMB_WIDTH = 1280 // dost pro hero i fullscreen, ~150–400 KB

// Wikimedia vyžaduje popisný User-Agent, jinak 403.
const WIKI_HEADERS = {
  'User-Agent': 'MotoGo24Mirror/1.0 (+https://motogo24.cz; info@motogo24.cz)',
}

const isWiki = (u: unknown): u is string =>
  typeof u === 'string' &&
  (u.includes('wikimedia.org') || u.includes('wikipedia.org'))

/// Je token service_role JWT? Kontroluje claim `role`, ne přesnou shodu —
/// projekt může mít po rotaci/migraci klíčů víc platných service_role klíčů
/// zároveň (viz send-push FIX 2026-06-06). Bez ověření podpisu (na bráně je
/// verify_jwt=false; pro tuhle low-risk fn stačí claim, jako u send-push).
function isServiceRole(token: string): boolean {
  try {
    const p = token.split('.')
    if (p.length !== 3) return false
    const pad = '='.repeat((4 - (p[1].length % 4)) % 4)
    const payload = JSON.parse(atob(p[1].replace(/-/g, '+').replace(/_/g, '/') + pad))
    return payload.role === 'service_role'
  } catch (_) {
    return false
  }
}

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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

type FetchOk = { bytes: Uint8Array; type: string }
type FetchErr = { err: string; permanent: boolean }

/// Jedno stažení z jedné URL. Vrací bajty, HTTP status (číslo), nebo síťovou chybu.
async function tryFetch(u: string, headers: Record<string, string>): Promise<FetchOk | { status: number } | { neterr: string }> {
  try {
    const r = await fetch(u, { headers, redirect: 'follow' })
    if (!r.ok) { await r.body?.cancel().catch(() => {}); return { status: r.status } }
    const type = (r.headers.get('content-type') || 'image/jpeg').split(';')[0].trim()
    if (!type.startsWith('image/')) { await r.body?.cancel().catch(() => {}); return { status: 415 } }
    const bytes = new Uint8Array(await r.arrayBuffer())
    if (bytes.length < 100) return { status: 422 }
    return { bytes, type }
  } catch (e) {
    return { neterr: String(e).slice(0, 40) }
  }
}

/// Stáhne + zmenší fotku. Přednostně přes proxy images.weserv.nl (stahuje ze
/// své infrastruktury s dobrou reputací → Wikimedia neškrtí jako cloud IP a
/// rovnou zmenší), fallback přímo na Wikimedia (?width= i originál). Rozlišuje
/// trvalé selhání (404/415/422 — nemá smysl opakovat) od dočasného (429/5xx/net).
async function fetchWiki(url: string): Promise<FetchOk | FetchErr> {
  const sep = url.includes('?') ? '&' : '?'
  const candidates: Array<{ u: string; h: Record<string, string> }> = [
    { u: `https://images.weserv.nl/?url=${encodeURIComponent(url)}&w=${THUMB_WIDTH}&output=jpg&q=80`, h: {} },
    { u: `${url}${sep}width=${THUMB_WIDTH}`, h: WIKI_HEADERS },
    { u: url, h: WIKI_HEADERS },
  ]
  let lastErr = 'unknown'
  let lastStatus = 0
  for (const { u, h } of candidates) {
    for (let attempt = 0; attempt < 2; attempt++) {
      const res = await tryFetch(u, h)
      if ('bytes' in res) return res
      if ('status' in res) {
        lastStatus = res.status
        lastErr = `http_${res.status}`
        if (res.status === 429 || res.status >= 500) { await sleep(700 * (attempt + 1)); continue } // retry
        break // 404/415/422 → další kandidát, bez retry
      } else {
        lastErr = `net_${res.neterr}`
        await sleep(700 * (attempt + 1))
      }
    }
  }
  const permanent = lastStatus === 404 || lastStatus === 415 || lastStatus === 422
  return { err: lastErr, permanent }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const sb = createClient(SUPABASE_URL, SERVICE_KEY)

  // ── Autorizace (verify_jwt=false na bráně → řešíme tady) ──
  // Projekt používá nový formát klíčů (sb_secret_…, NEJSOU JWT), takže se
  // nelze spolehnout na shodu env SERVICE_KEY s klíčem, který posílá cron.
  // Přijmi, když bearer == env service key, NEBO == app_settings.service_role_key
  // (přesně to, co posílá cron tick), NEBO jde o admin user JWT (Velín).
  let bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '').trim()
  // Klíč mohl přijít jako JSON string (jsonb bez `#>> '{}'`) → obalený "…".
  if (bearer.length > 1 && bearer.startsWith('"') && bearer.endsWith('"')) {
    bearer = bearer.slice(1, -1)
  }
  const svcMatch = bearer.length > 0 && bearer === SERVICE_KEY
  const roleMatch = !svcMatch && isServiceRole(bearer) // JWT s claim role=service_role
  let appMatch = false
  if (!svcMatch && !roleMatch && bearer.length > 0) {
    const { data: row } = await sb
      .from('app_settings').select('value').eq('key', 'service_role_key').maybeSingle()
    if (row?.value && bearer === String(row.value).trim()) appMatch = true
  }
  let adminMatch = false
  if (!svcMatch && !roleMatch && !appMatch && bearer.length > 0) {
    try {
      const caller = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY') || '', {
        global: { headers: { Authorization: `Bearer ${bearer}` } },
      })
      const { data: isAdmin } = await caller.rpc('is_admin')
      adminMatch = isAdmin === true
    } catch (_) { /* ne */ }
  }
  if (!svcMatch && !roleMatch && !appMatch && !adminMatch) {
    await sb.from('debug_log').insert({
      source: 'mirror-route-images', action: 'auth_denied', component: 'edge_function',
      status: 'error',
      request_data: { hasBearer: bearer.length > 0, bearerLen: bearer.length, bearerTail: bearer.slice(-6) },
    }).then(() => {}, () => {})
    return json({ error: 'forbidden' }, 403)
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
    // ── Načti VŠECHNY kandidáty (PostgREST vrací max 1000/dotaz → stránkuj,
    // jinak funkce nikdy neuvidí body zájmu za hranicí 1000 a count neklesne) ──
    async function fetchAll(table: string, cols: string): Promise<Record<string, unknown>[]> {
      const out: Record<string, unknown>[] = []
      const page = 1000
      for (let from = 0; ; from += page) {
        const { data, error } = await sb.from(table).select(cols).range(from, from + page - 1)
        if (error) throw error
        out.push(...((data || []) as Record<string, unknown>[]))
        if (!data || data.length < page) break
      }
      return out
    }

    const [routesData, poisData] = await Promise.all([
      fetchAll('routes', 'id, cover_image, images'),
      fetchAll('route_pois', 'id, image_url, images'),
    ])

    type Row = { table: 'routes' | 'route_pois'; id: string; patch: Record<string, unknown>; urls: string[] }
    const rows: Row[] = []
    for (const r of routesData) {
      const urls = [
        ...(isWiki(r.cover_image) ? [r.cover_image as string] : []),
        ...((r.images || []) as unknown[]).filter(isWiki),
      ]
      if (urls.length) rows.push({ table: 'routes', id: r.id as string, patch: { cover_image: r.cover_image, images: r.images }, urls })
    }
    for (const p of poisData) {
      const urls = [
        ...(isWiki(p.image_url) ? [p.image_url as string] : []),
        ...((p.images || []) as unknown[]).filter(isWiki),
      ]
      if (urls.length) rows.push({ table: 'route_pois', id: p.id as string, patch: { image_url: p.image_url, images: p.images }, urls })
    }

    // ── Zrcadli (cache přes duplicitní URL — stejná fotka u více řádků) ──
    const mirrored = new Map<string, string>() // stará URL → nová URL
    const failedTransient = new Set<string>() // 429/5xx/net — zkusí se příště
    const failedPermanent = new Set<string>() // 404/415/422 — nemá smysl opakovat
    const failSamples: Record<string, number> = {} // důvod → počet
    let images = 0
    let updated = 0
    let processedRows = 0
    const note = (why: string) => { failSamples[why] = (failSamples[why] || 0) + 1 }

    // Unikátní wiki URL v pořadí řádků (stejná fotka u více bodů se řeší jednou).
    const pending: string[] = []
    const seenUrl = new Set<string>()
    for (const row of rows) {
      for (const u of row.urls) {
        if (!seenUrl.has(u)) { seenUrl.add(u); pending.push(u) }
      }
    }

    // Zrcadlení jedné fotky (stáhni → ulož do storage).
    const mirrorOne = async (url: string) => {
      const img = await fetchWiki(url)
      if ('err' in img) {
        note(img.err)
        ;(img.permanent ? failedPermanent : failedTransient).add(url)
        return
      }
      const path = `routes-mirror/${await sha1hex(url)}.${EXT[img.type] || 'jpg'}`
      const up = await sb.storage.from('media').upload(path, img.bytes, { contentType: img.type, upsert: true })
      if (up.error) { failedTransient.add(url); note(`upload_${up.error.message}`.slice(0, 40)); return }
      mirrored.set(url, sb.storage.from('media').getPublicUrl(path).data.publicUrl)
    }

    // Paralelní pool (CONCURRENCY souběžně) — weserv/storage to zvládnou a je
    // to řádově rychlejší než sekvenčně; respektuje časový budget i MAX_IMAGES.
    let idx = 0
    const worker = async () => {
      while (idx < pending.length && images < MAX_IMAGES && !outOfBudget()) {
        const url = pending[idx++]
        images++
        await mirrorOne(url)
      }
    }
    await Promise.all(Array.from({ length: Math.min(CONCURRENCY, pending.length) }, worker))

    // Přepiš URL v řádcích. Řádek je „hotový" (počítá se do rows_done), jen když
    // jsou VŠECHNY jeho wiki URL buď zrcadlené, nebo trvale mrtvé (404) — dočasně
    // selhané / nestihnuté se dojedou příště.
    for (const row of rows) {
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
      const rowDone = [...new Set(row.urls)].every((u) => mirrored.has(u) || failedPermanent.has(u))
      if (rowDone) processedRows++
    }

    const failedCount = failedTransient.size + failedPermanent.size
    const result = {
      rows_with_wiki: rows.length,
      rows_done: processedRows,
      rows_updated: updated,
      images_fetched: images,
      images_failed: failedCount,
      images_failed_permanent: failedPermanent.size,
      fail_reasons: failSamples, // důvod → počet (diagnostika stahování)
      remaining_rows: Math.max(0, rows.length - processedRows),
      ms: Date.now() - t0,
    }

    // Loguj jen běhy, které něco dělaly (jinak by no-op cron spamoval debug_log).
    if (rows.length > 0 || failedCount > 0) {
      await sb.from('debug_log').insert({
        source: 'mirror-route-images',
        action: 'batch',
        component: 'edge_function',
        status: failedCount > 0 ? 'partial' : 'ok',
        request_data: result,
      })
    }
    return result
  }
}
