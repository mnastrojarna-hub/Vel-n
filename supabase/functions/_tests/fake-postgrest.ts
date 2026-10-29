// ===== _tests/fake-postgrest.ts =====
// Síťová náhrada Supabase (PostgREST /rest/v1, /rpc, /functions/v1, /storage) + Resend pro
// testy CELÉ edge funkce (index.ts se `serve()`), bez sítě a bez DB. Funkce se importuje až po
// installFakeNet(): Deno.listen jde na náhodný port 127.0.0.1 (port vrací `servers`), globální
// fetch obsluhuje SB_URL / api.resend.com / api.anthropic.com z paměti a zapisuje `calls`.
// Filtry: eq / neq / in / gte / gt / lte / is; `or`, `order`, `limit` (jen limit) — stačí na e-maily.
export const SB_URL = 'http://sb.test'
export const SVC_KEY = 'svc-test-key'
type Row = Record<string, unknown>
export type Call = { kind: 'rest' | 'rpc' | 'fn' | 'storage' | 'resend' | 'other'; name: string; method: string; query?: URLSearchParams; body?: unknown }

export class FakeNet {
  tables: Record<string, Row[]> = {}
  rpcs: Record<string, (args: Row) => unknown> = {}
  fns: Record<string, (body: Row) => unknown> = {}
  calls: Call[] = []
  /** Soubory Storage: '<bucket>/<cesta>' → obsah (GET /storage/v1/object/…). */
  files: Record<string, string> = {}
  reset(tables: Record<string, Row[]>) { this.tables = tables; this.calls = []; this.rpcs = {}; this.fns = {}; this.files = {} }
  rows(t: string) { return (this.tables[t] ||= []) }
  mails() { return this.calls.filter((c) => c.kind === 'resend').map((c) => c.body as Row) }
  restSelects(t: string) { return this.calls.filter((c) => c.kind === 'rest' && c.name === t && c.method === 'GET') }
}

const match = (v: unknown, op: string): boolean => {
  const i = op.indexOf('.')
  const k = op.slice(0, i), x = op.slice(i + 1)
  const s = v == null ? null : String(v)
  if (k === 'eq') return s === x
  if (k === 'neq') return s !== x
  if (k === 'is') return x === 'null' ? v == null : s === x
  if (k === 'in') return x.replace(/^\(|\)$/g, '').split(',').map((y) => y.replace(/^"|"$/g, '')).includes(String(s))
  if (k === 'gte') return s != null && s >= x
  if (k === 'gt') return s != null && Number(s) > Number(x)
  if (k === 'lte') return s != null && Number(s) <= Number(x)
  return true
}
const SKIP = new Set(['select', 'order', 'limit', 'or', 'offset', 'on_conflict', 'columns'])
const json = (b: unknown, status = 200) => new Response(b === undefined ? '' : JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } })

export const servers: Deno.Listener[] = []
let installed: FakeNet | null = null
const ENV_KEYS = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'RESEND_API_KEY', 'ANTHROPIC_API_KEY']
const savedEnv: Record<string, string | undefined> = {}
let savedFetch: typeof fetch | null = null
let savedListen: typeof Deno.listen | null = null

/** Vrátí env, globální fetch i Deno.listen procesu (funkce si env přečetly při importu) a zavře servery —
 *  další testové soubory ve stejném procesu `deno test` už náhradní síť nedostanou (a mohou si ji nainstalovat znovu). */
export function restoreFakeEnv(): void {
  for (const k of ENV_KEYS) { const v = savedEnv[k]; if (v === undefined) Deno.env.delete(k); else Deno.env.set(k, v) }
  for (const l of servers) { try { l.close() } catch { /* zavřený */ } }
  servers.length = 0
  if (savedFetch) { globalThis.fetch = savedFetch; savedFetch = null }
  // deno-lint-ignore no-explicit-any
  if (savedListen) { (Deno as any).listen = savedListen; savedListen = null }
  installed = null
}

/** Nainstaluje síťovou náhradu (jednou na proces) a vrátí sdílený stav. */
export function installFakeNet(): FakeNet {
  if (installed) return installed
  const net = new FakeNet()
  installed = net
  // Env je společné celému procesu deno test (i dalším testovým souborům) → restoreFakeEnv().
  for (const k of ENV_KEYS) savedEnv[k] = Deno.env.get(k)
  Deno.env.set('SUPABASE_URL', SB_URL)
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC_KEY)
  Deno.env.set('RESEND_API_KEY', 're_test')
  Deno.env.delete('ANTHROPIC_API_KEY')
  const origListen = Deno.listen
  savedListen = origListen
  // deno-lint-ignore no-explicit-any
  ;(Deno as any).listen = (o: Deno.ListenOptions) => { const l = origListen({ ...o, hostname: '127.0.0.1', port: 0 }); servers.push(l); return l }
  const origFetch = globalThis.fetch
  savedFetch = origFetch
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const req = input instanceof Request ? input : new Request(String(input), init)
    const u = new URL(req.url)
    if (u.hostname === '127.0.0.1') return origFetch(input, init)
    const text = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text()
    let body: unknown = text
    try { body = text ? JSON.parse(text) : undefined } catch { /* text */ }
    if (u.hostname === 'api.resend.com') {
      net.calls.push({ kind: 'resend', name: 'emails', method: req.method, body })
      return json({ id: 're_' + net.calls.filter((c) => c.kind === 'resend').length })
    }
    if (u.origin !== SB_URL) { net.calls.push({ kind: 'other', name: u.href, method: req.method, body }); return json({ error: 'offline' }, 503) }
    const p = u.pathname
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.slice('/rest/v1/rpc/'.length)
      net.calls.push({ kind: 'rpc', name: fn, method: req.method, body })
      const h = net.rpcs[fn]
      if (!h) return json({ code: 'PGRST202', message: `Could not find the function public.${fn}` }, 404)
      return json(h((body || {}) as Row) ?? null)
    }
    if (p.startsWith('/rest/v1/')) {
      const t = p.slice('/rest/v1/'.length)
      net.calls.push({ kind: 'rest', name: t, method: req.method, query: u.searchParams, body })
      const filt = (r: Row) => [...u.searchParams.entries()].every(([k, v]) => SKIP.has(k) || match(r[k], v))
      if (req.method === 'POST') {
        const list = (Array.isArray(body) ? body : [body]) as Row[]
        net.rows(t).push(...list.map((r) => ({ id: crypto.randomUUID(), ...r })))
        return new Response(null, { status: 201 })
      }
      if (req.method === 'PATCH') { for (const r of net.rows(t).filter(filt)) Object.assign(r, body as Row); return new Response(null, { status: 204 }) }
      let rows = net.rows(t).filter(filt)
      const lim = u.searchParams.get('limit')
      if (lim) rows = rows.slice(0, Number(lim))
      if ((req.headers.get('Accept') || '').includes('vnd.pgrst.object')) {
        return rows.length ? json(rows[0]) : json({ code: 'PGRST116', message: 'no rows' }, 406)
      }
      return json(rows)
    }
    if (p.startsWith('/functions/v1/')) {
      const fn = p.slice('/functions/v1/'.length)
      net.calls.push({ kind: 'fn', name: fn, method: req.method, body })
      const h = net.fns[fn]
      return json(h ? h((body || {}) as Row) : { success: false, error: 'not mocked' })
    }
    net.calls.push({ kind: 'storage', name: p, method: req.method, body })
    const file = p.startsWith('/storage/v1/object/') ? net.files[decodeURIComponent(p.slice('/storage/v1/object/'.length))] : undefined
    if (file !== undefined && req.method === 'GET') return new Response(file, { status: 200, headers: { 'Content-Type': 'application/pdf' } })
    return json({ error: 'not_found' }, 404)
  }) as typeof fetch
  return net
}

/** POST na edge funkci spuštěnou přes serve() (servers[i] = pořadí importu). */
export async function callFn(i: number, body: Row): Promise<{ status: number; json: Row }> {
  const port = (servers[i].addr as Deno.NetAddr).port
  // 127.0.0.1 propouští náhradní fetch na skutečnou síť (k funkci v tomto procesu).
  const res = await fetch(`http://127.0.0.1:${port}/`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${SVC_KEY}` }, body: JSON.stringify(body),
  })
  return { status: res.status, json: await res.json().catch(() => ({})) }
}
