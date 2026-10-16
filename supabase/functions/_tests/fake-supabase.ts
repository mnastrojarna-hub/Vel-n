// ===== _tests/fake-supabase.ts =====
// Minimální in-memory náhrada supabase-js klienta pro jednotkové testy plateb
// (deno test, bez sítě a bez DB). Podporuje řetězení, které používají moduly
// process-payment / _shared/extension-apply: from().select/update/insert/delete,
// eq/neq/not(in)/in/gt/lte/order/limit, maybeSingle/single, rpc().
// `missingCols` simuluje nenasazené SQL (sloupec neexistuje → PostgREST 42703).
type Row = Record<string, unknown>
type Err = { code?: string; message: string }
type Res = { data: unknown; error: Err | null }

export class FakeDb {
  tables: Record<string, Row[]>
  rpcs: Record<string, (args: Record<string, unknown>) => Res | Promise<Res>> = {}
  missingCols = new Set<string>()
  /** Vrátí chybu pro UPDATE dané tabulky (simulace triggeru / výpadku). */
  failUpdate: ((table: string, patch: Row) => Err | null) | null = null
  /** Volá se těsně před UPDATE (simulace souběžného zápisu). */
  beforeUpdate: ((table: string) => void) | null = null
  calls: Array<{ op: string; table?: string; fn?: string; data?: unknown }> = []
  private clock = 1

  constructor(tables: Record<string, Row[]>) {
    this.tables = tables
  }
  from(t: string) { return new Query(this, t) }
  rpc(fn: string, args: Record<string, unknown> = {}): Promise<Res> {
    this.calls.push({ op: 'rpc', fn, data: args })
    const h = this.rpcs[fn]
    if (!h) return Promise.resolve({ data: null, error: { code: 'PGRST202', message: `Could not find the function public.${fn}` } })
    return Promise.resolve(h(args))
  }
  tick(): string { return new Date(Date.UTC(2026, 9, 16, 12, 0, this.clock++)).toISOString() }
  rows(t: string): Row[] { return (this.tables[t] ||= []) }
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

class Query implements PromiseLike<Res> {
  private op: 'select' | 'update' | 'insert' | 'delete' = 'select'
  private filters: Array<(r: Row) => boolean> = []
  private cols = '*'
  private patch: Row | Row[] | null = null
  private mode: 'many' | 'one' | 'maybe' = 'many'
  private wantReturn = false
  private lim: number | null = null
  private orders: Array<[string, boolean]> = []
  constructor(private db: FakeDb, private table: string) {}

  select(cols = '*') { if (this.op === 'select') this.cols = cols; else this.wantReturn = true; return this }
  update(p: Row) { this.op = 'update'; this.patch = p; return this }
  insert(p: Row | Row[]) { this.op = 'insert'; this.patch = p; return this }
  delete() { this.op = 'delete'; return this }
  eq(c: string, v: unknown) { this.filters.push((r) => same(get(r, c), v)); return this }
  neq(c: string, v: unknown) { this.filters.push((r) => !same(get(r, c), v)); return this }
  gt(c: string, v: number) { this.filters.push((r) => Number(get(r, c)) > v); return this }
  gte(c: string, v: unknown) { this.filters.push((r) => String(get(r, c) ?? '') >= String(v)); return this }
  lte(c: string, v: number) { this.filters.push((r) => Number(get(r, c)) <= v); return this }
  in(c: string, vs: unknown[]) { this.filters.push((r) => vs.some((v) => same(get(r, c), v))); return this }
  is(c: string, v: unknown) { this.filters.push((r) => get(r, c) == v); return this }
  not(c: string, op: string, v: string) {
    if (op === 'in') { const vs = v.replace(/[()]/g, '').split(','); this.filters.push((r) => !vs.includes(String(get(r, c)))) }
    return this
  }
  order(c: string, o: { ascending?: boolean } = {}) { this.orders.push([c, o.ascending !== false]); return this }
  limit(n: number) { this.lim = n; return this }
  maybeSingle() { this.mode = 'maybe'; return this }
  single() { this.mode = 'one'; return this }

  then<A = Res, B = never>(ok?: ((v: Res) => A | PromiseLike<A>) | null, ko?: ((e: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    return Promise.resolve(this.run()).then(ok, ko)
  }

  private missing(cols: string[]): Err | null {
    const bad = cols.find((c) => this.db.missingCols.has(c))
    return bad ? { code: '42703', message: `column ${this.table}.${bad} does not exist` } : null
  }
  private shape(rows: Row[], cols: string): Row[] {
    if (cols.trim() === '*' ) {
      return rows.map((r) => Object.fromEntries(Object.entries(r).filter(([k]) => !this.db.missingCols.has(k))))
    }
    const list = cols.split(',').map((c) => c.trim()).filter((c) => c && !c.includes('('))
    return rows.map((r) => Object.fromEntries(list.map((c) => [c, r[c]])))
  }
  private run(): Res {
    const all = this.db.rows(this.table)
    let rows = all.filter((r) => this.filters.every((f) => f(r)))
    if (this.orders.length) {
      rows = [...rows].sort((a, b) => {
        for (const [c, asc] of this.orders) {
          const x = String(a[c] ?? ''), y = String(b[c] ?? '')
          if (x !== y) return (x < y ? -1 : 1) * (asc ? 1 : -1)
        }
        return 0
      })
    }
    if (this.lim != null) rows = rows.slice(0, this.lim)
    if (this.op === 'select') {
      if (this.cols.trim() !== '*') {
        const e = this.missing(this.cols.split(',').map((c) => c.trim()))
        if (e) return { data: null, error: e }
      }
      this.db.calls.push({ op: 'select', table: this.table })
      return this.finish(this.shape(rows, this.cols))
    }
    if (this.op === 'insert') {
      const list = (Array.isArray(this.patch) ? this.patch : [this.patch]) as Row[]
      const made = list.map((r) => ({ id: crypto.randomUUID(), created_at: this.db.tick(), ...r }))
      all.push(...made)
      this.db.calls.push({ op: 'insert', table: this.table, data: made })
      return this.finish(made)
    }
    if (this.op === 'delete') {
      this.db.tables[this.table] = all.filter((r) => !rows.includes(r))
      return { data: null, error: null }
    }
    // update
    const patch = this.patch as Row
    const e = this.missing(Object.keys(patch))
    if (e) return { data: null, error: e }
    this.db.beforeUpdate?.(this.table)
    // filtry znovu po případném souběžném zápisu
    rows = this.db.rows(this.table).filter((r) => this.filters.every((f) => f(r)))
    const fail = this.db.failUpdate?.(this.table, patch)
    if (fail) return { data: null, error: fail }
    for (const r of rows) Object.assign(r, patch, 'updated_at' in r ? { updated_at: this.db.tick() } : {})
    this.db.calls.push({ op: 'update', table: this.table, data: patch })
    return { data: this.wantReturn ? rows.map((r) => ({ id: r.id })) : null, error: null }
  }
  private finish(rows: Row[]): Res {
    if (this.mode === 'many') return { data: rows, error: null }
    if (rows.length === 0) return this.mode === 'maybe' ? { data: null, error: null } : { data: null, error: { code: 'PGRST116', message: 'no rows' } }
    return { data: rows[0], error: null }
  }
}
