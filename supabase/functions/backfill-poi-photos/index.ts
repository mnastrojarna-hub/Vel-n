// backfill-poi-photos — doplnění fotek bodů zájmu z VOLNÝCH zdrojů.
//
// PROČ: většina katalogových bodů (`points_of_interest`, generováno z Wikidata)
// nemá fotku, protože jejich entita na Wikidatech nemá P18. Tahle funkce se
// pokusí najít fotku s volnou licencí (Wikimedia Commons / Wikipedia) a doplnit
// `image_url`. Následně ji cron `mirror-route-images` zrcadlí do bucketu `media`
// (points_of_interest už pokrývá) → v appce se pak načítá rychle.
//
// BEZPEČNOST (proti „špatné fotce u špatného místa"):
//  - bere JEN Commons/Wikipedia (vše CC/public-domain, kredit i mirror fungují),
//  - fotku přijme jen při SHODĚ NÁZVU (token-overlap), jinak bod nechá bez fotky,
//  - `?dry_run=1` NIC nezapíše, jen vrátí návrhy (bod → URL → zdroj → jistota),
//    ať se dá výsledek zkontrolovat, než se zapne cron.
//
// Auth: stejná jako mirror-route-images (service_role z app_settings / admin JWT),
// verify_jwt=false v config.toml.
//
// Použití:
//   dry-run (nezapisuje):  POST ...&dry_run=1&limit=40&wait=1
//   ostrý běh:             POST ...&limit=100&wait=1
//   cron:                  RPC backfill_poi_photos_tick() → pg_net POST (bez wait)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DEFAULT_LIMIT = 60 // bodů na jeden běh
const MAX_LIMIT = 300
const TIME_BUDGET_MS = 120_000
const CONCURRENCY = 3
const GEO_RADIUS_M = 1200 // okruh pro geosearch fotek
const MIN_SCORE = 0.5 // min. shoda názvu (0..1)
// KONTROLA „fotka opravdu zobrazuje dané místo" = GEOGRAFICKÁ shoda + shoda názvu.
const WD_RADIUS_KM = 0.6 // Wikidata: entita s fotkou musí ležet do 600 m od bodu
const WIKI_NEAR_M = 700 // Wikipedie: článek se souřadnicemi do 700 m od bodu
const WIKI_NAME_ONLY = 0.8 // Wikipedie bez souřadnic: jen skoro přesná shoda názvu
const GEO_MIN_SCORE = 0.66 // Commons geosearch (bez entity): vyžaduj silnou shodu názvu

const WIKI_HEADERS = {
  'User-Agent': 'MotoGo24Backfill/1.0 (+https://motogo24.cz; info@motogo24.cz)',
}

// Které jazykové Wikipedie zkusit dle země bodu (+ vždy en jako záloha).
const WIKI_LANGS: Record<string, string[]> = {
  CZ: ['cs'], SK: ['sk', 'cs'], PL: ['pl'], DE: ['de'], AT: ['de'], CH: ['de', 'fr', 'it'],
  FR: ['fr'], IT: ['it'], ES: ['es'], NL: ['nl'], BE: ['nl', 'fr'], PT: ['pt'],
  HU: ['hu'], SI: ['sl'], HR: ['hr'], RO: ['ro'], BG: ['bg'], RS: ['sr'], GR: ['el'],
  DK: ['da'], SE: ['sv'], NO: ['no'], FI: ['fi'], GB: ['en'], IE: ['en'],
  LT: ['lt'], LV: ['lv'], EE: ['et'], MD: ['ro'], MK: ['mk'],
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

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

// ── Porovnání názvů (bez diakritiky, token-overlap) ──
function fold(s: string): string {
  // Odstraň diakritiku (kombinující znaky U+0300–U+036F) přes NFD rozklad.
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
}
const STOP = new Set([
  'the', 'a', 'an', 'of', 'de', 'la', 'le', 'el', 'und', 'and', 'na', 'v', 've', 'u',
  'nad', 'pod', 'pri', 'die', 'der', 'das', 'von', 'zum', 'zur', 'am', 'im',
  'hrad', 'zamek', 'rozhledna', 'kostel', 'jezero', 'rybnik', 'prehrada', 'vrch',
  'castle', 'lake', 'tower', 'church', 'mount', 'burg', 'schloss', 'see',
])
function tokset(s: string): Set<string> {
  const out = new Set<string>()
  for (const t of fold(s).replace(/[^a-z0-9\s]/g, ' ').split(/\s+/)) {
    if (t.length >= 3 && !STOP.has(t)) out.add(t)
  }
  return out
}
/// Shoda 0..1 = kolik VÝZNAMOVÝCH tokenů názvu bodu je i v názvu kandidáta.
function nameScore(poiName: string, candidate: string): number {
  const a = tokset(poiName)
  if (a.size === 0) return 0
  const b = tokset(candidate)
  let hit = 0
  for (const t of a) if (b.has(t)) hit++
  return hit / a.size
}

const filePathUrl = (file: string) =>
  `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(file.replace(/^File:/i, '').replace(/ /g, '_'))}`

async function getJson(url: string): Promise<Record<string, unknown> | null> {
  try {
    const r = await fetch(url, { headers: WIKI_HEADERS })
    if (!r.ok) { await r.body?.cancel().catch(() => {}); return null }
    return await r.json() as Record<string, unknown>
  } catch (_) {
    return null
  }
}

type Poi = { id: string; name: string; lat: number; lng: number; country: string | null; alt?: string }
type Hit = { url: string; source: string; score: number } | null

/// 1) NEJSILNĚJŠÍ kontrola: Wikidata entita S FOTKOU (P18) ležící PŘÍMO na místě
///    bodu (do WD_RADIUS_KM) a se sedícím názvem → fotka je vázaná na konkrétní
///    objekt na daných souřadnicích, takže skoro jistě zobrazuje to, co má.
async function viaWikidata(p: Poi): Promise<Hit> {
  const sparql = `SELECT ?itemLabel ?img ?d WHERE {
    SERVICE wikibase:around {
      ?item wdt:P625 ?loc .
      bd:serviceParam wikibase:center "Point(${p.lng} ${p.lat})"^^geo:wktLiteral .
      bd:serviceParam wikibase:radius "${WD_RADIUS_KM}" .
      bd:serviceParam wikibase:distance ?d .
    }
    ?item wdt:P18 ?img .
    SERVICE wikibase:label { bd:serviceParam wikibase:language "en,cs,de,sk,pl,fr,it,es,nl". }
  } ORDER BY ?d LIMIT 15`
  const url = `https://query.wikidata.org/sparql?format=json&query=${encodeURIComponent(sparql)}`
  const data = await getJson(url)
  const results = data?.results as Record<string, unknown> | undefined
  const rows = (results?.bindings as Array<Record<string, { value?: unknown }>> | undefined) || []
  for (const r of rows) {
    const label = r.itemLabel?.value != null ? String(r.itemLabel.value) : ''
    const img = r.img?.value != null ? String(r.img.value) : ''
    if (!img) continue
    const score = Math.max(nameScore(p.name, label), p.alt ? nameScore(p.alt, label) : 0)
    if (score >= MIN_SCORE) {
      // Hodnota P18 už je Special:FilePath URL (jen vynuť https).
      return { url: img.replace(/^http:/, 'https:'), source: 'wikidata', score: Math.min(1, score + 0.2) }
    }
  }
  return null
}

/// 2) Úvodní foto článku na Wikipedii shodného názvu, jehož poloha sedí s bodem
///    (do WIKI_NEAR_M). Úvodní foto článku je skoro vždy o daném místě.
async function viaWikipedia(p: Poi): Promise<Hit> {
  const langs = [...(WIKI_LANGS[(p.country || '').toUpperCase()] || []), 'en']
  const seen = new Set<string>()
  for (const lang of langs) {
    if (seen.has(lang)) continue
    seen.add(lang)
    const q = encodeURIComponent(p.name)
    const url = `https://${lang}.wikipedia.org/w/api.php?action=query&format=json&origin=*` +
      `&generator=search&gsrsearch=${q}&gsrlimit=3&gsrnamespace=0` +
      `&prop=pageimages|coordinates&piprop=name&colimit=3`
    const data = await getJson(url)
    const pages = (data?.query as Record<string, unknown> | undefined)?.pages as Record<string, Record<string, unknown>> | undefined
    if (!pages) continue
    for (const pg of Object.values(pages)) {
      const title = String(pg.title || '')
      const file = pg.pageimage ? String(pg.pageimage) : ''
      if (!file) continue
      const score = Math.max(nameScore(p.name, title), p.alt ? nameScore(p.alt, title) : 0)
      const co = (pg.coordinates as Array<Record<string, unknown>> | undefined)?.[0]
      const hasCo = !!co && typeof co.lat === 'number' && typeof co.lon === 'number'
      let ok = false
      if (hasCo) {
        // Kontrola polohy: článek musí ležet U BODU (do WIKI_NEAR_M) A sedět názvem.
        const d = haversine(p.lat, p.lng, co!.lat as number, co!.lon as number)
        ok = d <= WIKI_NEAR_M && score >= MIN_SCORE
      } else {
        // Bez souřadnic přijmi jen skoro přesnou shodu názvu (opatrně).
        ok = score >= WIKI_NAME_ONLY
      }
      if (ok) {
        return { url: filePathUrl(file), source: `wikipedia:${lang}`, score: Math.min(1, score + (hasCo ? 0.2 : 0)) }
      }
    }
  }
  return null
}

/// 3) Poslední záloha: geotagovaná fotka z Commons blízko bodu. Nemá za sebou
///    entitu, tak vyžaduj SILNOU shodu názvu (GEO_MIN_SCORE), ať nechytne
///    náhodnou fotku odjinud poblíž.
async function viaCommonsGeo(p: Poi): Promise<Hit> {
  const url = `https://commons.wikimedia.org/w/api.php?action=query&format=json&origin=*` +
    `&generator=geosearch&ggscoord=${p.lat}|${p.lng}&ggsradius=${GEO_RADIUS_M}` +
    `&ggslimit=20&ggsnamespace=6`
  const data = await getJson(url)
  const pages = (data?.query as Record<string, unknown> | undefined)?.pages as Record<string, Record<string, unknown>> | undefined
  if (!pages) return null
  let best: Hit = null
  for (const pg of Object.values(pages)) {
    const title = String(pg.title || '') // "File:Xxx.jpg"
    if (!/\.(jpe?g|png|webp)$/i.test(title)) continue
    const score = Math.max(nameScore(p.name, title), p.alt ? nameScore(p.alt, title) : 0)
    if (score >= GEO_MIN_SCORE && (!best || score > best.score)) {
      best = { url: filePathUrl(title), source: 'commons-geo', score }
    }
  }
  return best
}

function haversine(la1: number, lo1: number, la2: number, lo2: number): number {
  const R = 6371000, r = Math.PI / 180
  const dLa = (la2 - la1) * r, dLo = (lo2 - lo1) * r
  const s = Math.sin(dLa / 2) ** 2 +
    Math.cos(la1 * r) * Math.cos(la2 * r) * Math.sin(dLo / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)))
}

async function findPhoto(p: Poi): Promise<Hit> {
  // Od nejsilnější kontroly (Wikidata entita na místě) po nejslabší (geosearch).
  return (await viaWikidata(p)) || (await viaWikipedia(p)) || (await viaCommonsGeo(p))
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  const sb = createClient(SUPABASE_URL, SERVICE_KEY)

  // ── Autorizace (shodná s mirror-route-images) ──
  let bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (bearer.length > 1 && bearer.startsWith('"') && bearer.endsWith('"')) bearer = bearer.slice(1, -1)
  const svcMatch = bearer.length > 0 && bearer === SERVICE_KEY
  const roleMatch = !svcMatch && isServiceRole(bearer)
  let appMatch = false
  if (!svcMatch && !roleMatch && bearer.length > 0) {
    const { data: row } = await sb.from('app_settings').select('value').eq('key', 'service_role_key').maybeSingle()
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
    return json({ error: 'forbidden' }, 403)
  }

  const params = new URL(req.url).searchParams
  const dryRun = ['1', 'true'].includes(params.get('dry_run') || '')
  const limit = Math.min(MAX_LIMIT, Math.max(1, parseInt(params.get('limit') || '', 10) || DEFAULT_LIMIT))
  const wait = ['1', 'true'].includes(params.get('wait') || '')

  const task = runBatch(sb, { dryRun, limit }).catch(async (e) => {
    await sb.from('debug_log').insert({
      source: 'backfill-poi-photos', action: 'batch', component: 'edge_function',
      status: 'error', request_data: { error: String(e) },
    }).then(() => {}, () => {})
    return { error: String(e) }
  })

  if (wait || dryRun) return json({ success: true, ...(await task) })
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime
  if (rt?.waitUntil) { rt.waitUntil(task); return json({ success: true, started: true }, 202) }
  return json({ success: true, ...(await task) })
})

async function runBatch(
  sb: ReturnType<typeof createClient>,
  opts: { dryRun: boolean; limit: number },
) {
  const t0 = Date.now()

  // Kolik bodů bez fotky ještě zbývá (informativně).
  const { count: remaining } = await sb.from('points_of_interest')
    .select('id', { count: 'exact', head: true })
    .is('image_url', null).eq('is_active', true)

  // Kolik bodů se ještě NEZKOUŠELO (skutečná práce pro cron; když 0 → job končí).
  const { count: remainingUnchecked } = await sb.from('points_of_interest')
    .select('id', { count: 'exact', head: true })
    .is('image_url', null).is('photo_checked_at', null).eq('is_active', true)

  // Bere jen body, u kterých se fotka JEŠTĚ nezkoušela (photo_checked_at null) —
  // jinak by dávka pořád narážela na vodní blok bodů BEZ dohledatelné fotky na
  // začátku řazení a nikdy nepostoupila dál. Každý bod se po pokusu označí jako
  // „zkoušený", takže se okno posouvá a backfill monotónně dojede.
  const { data, error } = await sb.from('points_of_interest')
    .select('id, name, lat, lng, country, translations')
    .is('image_url', null).is('photo_checked_at', null).eq('is_active', true)
    .order('sort_order', { ascending: true, nullsFirst: false })
    .order('id', { ascending: true })
    .limit(opts.limit)
  if (error) throw error

  const pois: Poi[] = (data || []).map((r) => {
    const tr = r.translations as Record<string, Record<string, unknown>> | null
    const alt = tr?.en?.name ? String(tr.en.name) : undefined
    return { id: String(r.id), name: String(r.name), lat: Number(r.lat), lng: Number(r.lng), country: r.country as string | null, alt }
  }).filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lng) && p.name)

  const proposals: Array<{ id: string; name: string; url: string; source: string; score: number }> = []
  const bySource: Record<string, number> = {}
  let updated = 0, skipped = 0
  let idx = 0

  const nowIso = new Date().toISOString()
  const worker = async () => {
    while (idx < pois.length && Date.now() - t0 < TIME_BUDGET_MS) {
      const p = pois[idx++]
      const hit = await findPhoto(p)
      if (hit) {
        bySource[hit.source] = (bySource[hit.source] || 0) + 1
        proposals.push({ id: p.id, name: p.name, url: hit.url, source: hit.source, score: Math.round(hit.score * 100) / 100 })
      } else {
        skipped++
      }
      // Ostrý běh: označ bod jako „zkoušený" (i bez nálezu), ať se příště
      // nepřeskenovává donekonečna; při nálezu rovnou doplň i image_url.
      if (!opts.dryRun) {
        const patch: Record<string, unknown> = { photo_checked_at: nowIso }
        if (hit) patch.image_url = hit.url
        const upd = await sb.from('points_of_interest').update(patch).eq('id', p.id).is('image_url', null)
        if (!upd.error && hit) updated++
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, pois.length) }, worker))

  const result = {
    dry_run: opts.dryRun,
    scanned: pois.length,
    found: proposals.length,
    skipped,
    updated,
    remaining_without_photo: remaining ?? null,
    remaining_unchecked: remainingUnchecked ?? null,
    by_source: bySource,
    ms: Date.now() - t0,
    // v dry-run vrať i vzorek návrhů ke kontrole (max 40)
    ...(opts.dryRun ? { samples: proposals.slice(0, 40) } : {}),
  }

  if (pois.length > 0) {
    await sb.from('debug_log').insert({
      source: 'backfill-poi-photos', action: 'batch', component: 'edge_function',
      status: 'ok', request_data: result,
    }).then(() => {}, () => {})
  }
  return result
}
