// ===== _tests/gear-fake.ts =====
// Volná in-memory náhrada supabase-js pro testy výpůjčky výbavy (EDGE-B, 2026-10-23).
// Na rozdíl od gear-fake-supabase.ts vrací SELECT celé řádky (i s předpřipravenými embedy
// `motorcycles`, `profiles`…), takže jde pustit i celý handler edge funkce (flow testy
// přes _tests/gear-flow-map.json). Neznámé metody řetězu (like, or, match…) = bez filtru.
type Row = Record<string, unknown>
type Err = { code?: string; message: string }
export type Res = { data: unknown; error: Err | null }

export class LooseDb {
  tables: Record<string, Row[]>
  rpcs: Record<string, (args: Record<string, unknown>) => Res | Promise<Res>> = {}
  calls: Array<{ op: string; table?: string; fn?: string; data?: unknown }> = []
  files: Record<string, unknown> = {}
  /** Vrátí chybu SELECTu dané tabulky (simulace chybějícího sloupce / výpadku). */
  failSelect: ((table: string, cols: string) => Err | null) | null = null
  storage = {
    from: (_bucket: string) => ({
      upload: (path: string, body: unknown) => { this.files[path] = body; this.calls.push({ op: 'upload', data: path }); return Promise.resolve({ data: { path }, error: null }) },
      remove: (paths: string[]) => { for (const p of paths) delete this.files[p]; this.calls.push({ op: 'remove', data: paths }); return Promise.resolve({ data: null, error: null }) },
      download: (path: string) => Promise.resolve(this.files[path] ? { data: new Blob(['x']), error: null } : { data: null, error: { message: 'not found' } }),
    }),
  }
  // Přihlášený zákazník pro _shared/auth.ts: globalThis.__gearAuthUser (globálně — auth.ts si
  // service klienta cachuje, takže by per-instanci nastavený uživatel u další LooseDb nebyl vidět).
  auth = { getUser: () => {
    const u = (globalThis as unknown as { __gearAuthUser?: Row | null }).__gearAuthUser
    return Promise.resolve(u ? { data: { user: u }, error: null } : { data: { user: null }, error: { message: 'no user' } })
  } }

  constructor(tables: Record<string, Row[]> = {}) { this.tables = tables }
  rows(t: string): Row[] { return (this.tables[t] ||= []) }
  from(t: string) {
    const q = new LQuery(this, t)
    const p: unknown = new Proxy(q, {
      get(target, prop, recv) {
        if (prop in target) {
          const v = Reflect.get(target, prop, recv)
          return typeof v === 'function' ? (...a: unknown[]) => { const r = v.apply(target, a); return r === target ? p : r } : v
        }
        return () => p // neznámý filtr / modifikátor → bez účinku
      },
    })
    return p as LQuery
  }
  rpc(fn: string, args: Record<string, unknown> = {}): Promise<Res> {
    this.calls.push({ op: 'rpc', fn, data: args })
    const h = this.rpcs[fn]
    if (!h) return Promise.resolve({ data: null, error: { code: 'PGRST202', message: `Could not find the function public.${fn}` } })
    return Promise.resolve(h(args))
  }
  callsOf(op: string, name?: string) { return this.calls.filter((c) => c.op === op && (!name || c.table === name || c.fn === name)) }
}

const get = (r: Row, col: string): unknown => {
  const m = col.match(/^(\w+)->>(\w+)$/)
  if (m) { const o = r[m[1]] as Row | null | undefined; return o == null ? undefined : (o[m[2]] == null ? undefined : String(o[m[2]])) }
  return r[col]
}
const same = (a: unknown, b: unknown) => {
  if (a == null || b == null) return a == b
  if (typeof a === 'number' || typeof b === 'number') return Number(a) === Number(b)
  return String(a) === String(b)
}

class LQuery implements PromiseLike<Res> {
  private op: 'select' | 'update' | 'insert' | 'delete' = 'select'
  private cols = '*'
  private filters: Array<(r: Row) => boolean> = []
  private patch: Row | Row[] | null = null
  private mode: 'many' | 'one' | 'maybe' = 'many'
  private wantReturn = false
  private lim: number | null = null
  constructor(private db: LooseDb, private table: string) {}
  select(cols = '*') { if (this.op === 'select') this.cols = cols; else this.wantReturn = true; return this }
  update(p: Row) { this.op = 'update'; this.patch = p; return this }
  insert(p: Row | Row[]) { this.op = 'insert'; this.patch = p; return this }
  upsert(p: Row | Row[]) { this.op = 'insert'; this.patch = p; return this }
  delete() { this.op = 'delete'; return this }
  eq(c: string, v: unknown) { this.filters.push((r) => same(get(r, c), v)); return this }
  neq(c: string, v: unknown) { this.filters.push((r) => !same(get(r, c), v)); return this }
  in(c: string, vs: unknown[]) { this.filters.push((r) => vs.some((v) => same(get(r, c), v))); return this }
  is(c: string, v: unknown) { this.filters.push((r) => (get(r, c) ?? null) === v); return this }
  gte(c: string, v: unknown) { this.filters.push((r) => String(get(r, c) ?? '') >= String(v)); return this }
  order() { return this }
  limit(n: number) { this.lim = n; return this }
  maybeSingle() { this.mode = 'maybe'; return this }
  single() { this.mode = 'one'; return this }
  then<A = Res, B = never>(ok?: ((v: Res) => A | PromiseLike<A>) | null, ko?: ((e: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    return Promise.resolve(this.run()).then(ok, ko)
  }
  private run(): Res {
    const all = this.db.rows(this.table)
    let rows = all.filter((r) => this.filters.every((f) => f(r)))
    if (this.lim != null) rows = rows.slice(0, this.lim)
    if (this.op === 'select') {
      const e = this.db.failSelect?.(this.table, this.cols)
      if (e) return { data: null, error: e }
      this.db.calls.push({ op: 'select', table: this.table, data: this.cols })
      return this.finish(rows.map((r) => ({ ...r })))
    }
    if (this.op === 'insert') {
      const list = (Array.isArray(this.patch) ? this.patch : [this.patch]) as Row[]
      const made = list.map((r) => ({ id: crypto.randomUUID(), ...r }))
      all.push(...made)
      this.db.calls.push({ op: 'insert', table: this.table, data: made })
      return this.finish(made)
    }
    if (this.op === 'delete') {
      this.db.tables[this.table] = all.filter((r) => !rows.includes(r))
      this.db.calls.push({ op: 'delete', table: this.table })
      return { data: null, error: null }
    }
    const patch = this.patch as Row
    for (const r of rows) Object.assign(r, patch)
    this.db.calls.push({ op: 'update', table: this.table, data: patch })
    if (!this.wantReturn) return { data: null, error: null }
    return this.finish(rows.map((r) => ({ ...r })))
  }
  private finish(rows: Row[]): Res {
    if (this.mode === 'many') return { data: rows, error: null }
    if (rows.length === 0) return this.mode === 'maybe' ? { data: null, error: null } : { data: null, error: { code: 'PGRST116', message: 'no rows' } }
    return { data: rows[0], error: null }
  }
}

/** Náhrada globálního fetch — zaznamená volání (URL + JSON tělo), odpověď z `reply`. */
export function stubFetch(reply: (url: string, body: Record<string, unknown> | null) => Response | Promise<Response>) {
  const calls: Array<{ url: string; body: Record<string, unknown> | null }> = []
  const orig = globalThis.fetch
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
    let body: Record<string, unknown> | null = null
    try { body = init?.body ? JSON.parse(String(init.body)) : null } catch { body = null }
    calls.push({ url, body })
    return await reply(url, body)
  }) as typeof fetch
  return { calls, restore: () => { globalThis.fetch = orig } }
}
