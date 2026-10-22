// In-memory supabase-js stand-in for end-to-end refund tests (verify:refunds). Based on
// supabase/functions/_tests/fake-supabase.ts, plus: real-time created_at (the 15-min dedupe windows
// in process-refund compare against Date.now()), or(), count/head, upsert, auth.getUser, storage.
// deno-lint-ignore-file no-explicit-any
type Row = Record<string, any>
type Err = { code?: string; message: string }
type Res = { data: any; error: Err | null; count?: number }

export class Db {
  tables: Record<string, Row[]>
  rpcs: Record<string, (args: Row) => Res | Promise<Res>> = {}
  users = new Map<string, { id: string }>() // token → user
  storageFiles = new Map<string, Blob>()
  /** called right before an UPDATE (simulate a concurrent writer) */
  beforeUpdate: ((table: string, patch: Row) => void) | null = null
  /** called for each inserted row (simulate BEFORE INSERT triggers, e.g. _cap_refund_to_paid) */
  beforeInsert: ((table: string, row: Row) => void) | null = null
  private n = 0
  constructor(tables: Record<string, Row[]>) { this.tables = tables }
  from(t: string) { return new Q(this, t) }
  rpc(fn: string, args: Row = {}): Promise<Res> {
    const h = this.rpcs[fn]
    if (!h) return Promise.resolve({ data: null, error: { code: 'PGRST202', message: `Could not find the function public.${fn}` } })
    return Promise.resolve(h(args))
  }
  now(): string { return new Date(Date.now() + (this.n++)).toISOString() }
  rows(t: string): Row[] { return (this.tables[t] ||= []) }
  auth = { getUser: (t: string) => {
    const u = this.users.get(t)
    return Promise.resolve(u ? { data: { user: u }, error: null } : { data: { user: null }, error: { message: 'invalid' } })
  } }
  storage = { from: (_b: string) => ({
    upload: (p: string, blob: Blob) => { this.storageFiles.set(p, blob); return Promise.resolve({ data: { path: p }, error: null }) },
    download: (p: string) => Promise.resolve(this.storageFiles.has(p) ? { data: this.storageFiles.get(p), error: null } : { data: null, error: { message: 'not found' } }),
  }) }
}

const get = (r: Row, col: string): any => {
  const m = col.match(/^(\w+)->>(\w+)$/)
  if (m) { const o = r[m[1]]; return o == null ? undefined : (o[m[2]] == null ? undefined : String(o[m[2]])) }
  return r[col]
}
const same = (a: any, b: any) => {
  if (a == null || b == null) return a == b
  if (typeof a === 'number' || typeof b === 'number') return Number(a) === Number(b)
  return String(a) === String(b)
}
/** minimal PostgREST or(): `a.eq.x,and(b.eq.y,c.eq.z)` */
function orFilter(expr: string): (r: Row) => boolean {
  const parts: string[] = []; let depth = 0, cur = ''
  for (const ch of expr) { if (ch === '(') depth++; if (ch === ')') depth--; if (ch === ',' && depth === 0) { parts.push(cur); cur = '' } else cur += ch }
  if (cur) parts.push(cur)
  const one = (p: string): ((r: Row) => boolean) => {
    const and = p.match(/^and\((.*)\)$/)
    if (and) { const subs = and[1].split(',').map(one); return (r) => subs.every((f) => f(r)) }
    const [c, op, ...v] = p.split('.'); const val = v.join('.')
    if (op === 'eq') return (r) => same(get(r, c), val)
    if (op === 'neq') return (r) => !same(get(r, c), val)
    if (op === 'is') return (r) => get(r, c) == null
    return () => false
  }
  const fs = parts.map(one)
  return (r) => fs.some((f) => f(r))
}

class Q implements PromiseLike<Res> {
  private op: 'select' | 'update' | 'insert' | 'delete' | 'upsert' = 'select'
  private filters: Array<(r: Row) => boolean> = []
  private cols = '*'
  private patch: any = null
  private mode: 'many' | 'one' | 'maybe' = 'many'
  private wantReturn = false
  private lim: number | null = null
  private orders: Array<[string, boolean]> = []
  private countMode = false
  private head = false
  private upsertOpts: Row = {}
  constructor(private db: Db, private table: string) {}
  select(cols = '*', o: Row = {}) {
    if (this.op === 'select') { this.cols = cols; this.countMode = !!o.count; this.head = !!o.head } else this.wantReturn = true
    return this
  }
  update(p: Row) { this.op = 'update'; this.patch = p; return this }
  insert(p: Row | Row[]) { this.op = 'insert'; this.patch = p; return this }
  upsert(p: Row | Row[], o: Row = {}) { this.op = 'upsert'; this.patch = p; this.upsertOpts = o; return this }
  delete() { this.op = 'delete'; return this }
  eq(c: string, v: any) { this.filters.push((r) => same(get(r, c), v)); return this }
  neq(c: string, v: any) { this.filters.push((r) => !same(get(r, c), v)); return this }
  gt(c: string, v: number) { this.filters.push((r) => Number(get(r, c)) > v); return this }
  gte(c: string, v: any) { this.filters.push((r) => String(get(r, c) ?? '') >= String(v)); return this }
  lt(c: string, v: any) { this.filters.push((r) => String(get(r, c) ?? '') < String(v)); return this }
  lte(c: string, v: number) { this.filters.push((r) => Number(get(r, c)) <= v); return this }
  in(c: string, vs: any[]) { this.filters.push((r) => vs.some((v) => same(get(r, c), v))); return this }
  is(c: string, v: any) { this.filters.push((r) => get(r, c) == v); return this }
  or(expr: string) { this.filters.push(orFilter(expr)); return this }
  like(c: string, pat: string) {
    const rx = new RegExp('^' + pat.split('%').map((x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$')
    this.filters.push((r) => rx.test(String(get(r, c) ?? ''))); return this
  }
  not(c: string, op: string, v: any) {
    if (op === 'in') { const vs = String(v).replace(/[()]/g, '').split(','); this.filters.push((r) => !vs.includes(String(get(r, c)))) }
    if (op === 'is') this.filters.push((r) => get(r, c) != null)
    return this
  }
  order(c: string, o: { ascending?: boolean } = {}) { this.orders.push([c, o.ascending !== false]); return this }
  limit(n: number) { this.lim = n; return this }
  range(a: number, b: number) { this.lim = b - a + 1; return this }
  maybeSingle() { this.mode = 'maybe'; return this }
  single() { this.mode = 'one'; return this }
  then<A = Res, B = never>(ok?: ((v: Res) => A | PromiseLike<A>) | null, ko?: ((e: any) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    return Promise.resolve().then(() => this.run()).then(ok, ko)
  }
  private shape(rows: Row[]): Row[] {
    if (this.cols.trim() === '*') return rows.map((r) => ({ ...r }))
    // top-level split (commas inside embedded resources stay)
    const parts: string[] = []; let depth = 0, cur = ''
    for (const ch of this.cols) { if (ch === '(') depth++; if (ch === ')') depth--; if (ch === ',' && depth === 0) { parts.push(cur.trim()); cur = '' } else cur += ch }
    if (cur.trim()) parts.push(cur.trim())
    // embedded: alias:fk(cols) | table!fk(cols) | table(cols) — FK map for the tables the refund flows read
    const FK: Record<string, [string, string]> = { profiles: ['profiles', 'user_id'], user_id: ['profiles', 'user_id'], customer_id: ['profiles', 'customer_id'],
      motorcycles: ['motorcycles', 'moto_id'], moto_id: ['motorcycles', 'moto_id'] }
    return rows.map((r) => {
      const o: Row = {}
      for (const c of parts) {
        const m = c.match(/^(?:(\w+):)?(\w+)(?:!(\w+))?\((.*)\)$/)
        if (!m) { o[c] = r[c]; continue }
        const [, alias, name, fk, sub] = m
        const key = alias || name
        const spec = FK[fk || name] || FK[name]
        if (!spec) { o[key] = null; continue }
        const [tbl, col] = fk && FK[fk] ? [FK[fk][0] === 'profiles' || FK[fk][0] === 'motorcycles' ? FK[fk][0] : tbl0(name), FK[fk][1]] : spec
        const ref = this.db.rows(tbl).find((x) => same(x.id, r[col]))
        if (!ref) { o[key] = null; continue }
        const subCols = sub.split(',').map((x) => x.trim()).filter(Boolean)
        o[key] = Object.fromEntries(subCols.map((x) => [x, ref[x]]))
      }
      return o
    })
    function tbl0(n: string) { return n }
  }
  private run(): Res {
    const all = this.db.rows(this.table)
    let rows = all.filter((r) => this.filters.every((f) => f(r)))
    if (this.orders.length) {
      rows = [...rows].sort((a, b) => {
        for (const [c, asc] of this.orders) { const x = String(a[c] ?? ''), y = String(b[c] ?? ''); if (x !== y) return (x < y ? -1 : 1) * (asc ? 1 : -1) }
        return 0
      })
    }
    if (this.lim != null) rows = rows.slice(0, this.lim)
    if (this.op === 'select') {
      if (this.countMode) return { data: this.head ? null : this.shape(rows), error: null, count: rows.length }
      return this.finish(this.shape(rows))
    }
    if (this.op === 'insert' || this.op === 'upsert') {
      const list = (Array.isArray(this.patch) ? this.patch : [this.patch]) as Row[]
      if (this.op === 'upsert' && this.upsertOpts.onConflict) {
        const k = String(this.upsertOpts.onConflict)
        const dup = list.filter((r) => all.some((x) => same(x[k], r[k])))
        if (dup.length && this.upsertOpts.ignoreDuplicates) return this.finish([])
      }
      const made = list.map((r) => ({ id: crypto.randomUUID(), created_at: this.db.now(), ...r }))
      for (const r of made) this.db.beforeInsert?.(this.table, r)
      all.push(...made)
      return this.finish(made.map((r) => ({ ...r })))
    }
    if (this.op === 'delete') { this.db.tables[this.table] = all.filter((r) => !rows.includes(r)); return { data: null, error: null } }
    const patch = this.patch as Row
    this.db.beforeUpdate?.(this.table, patch)
    rows = this.db.rows(this.table).filter((r) => this.filters.every((f) => f(r)))
    for (const r of rows) Object.assign(r, patch)
    return { data: this.wantReturn ? rows.map((r) => ({ id: r.id })) : null, error: null }
  }
  private finish(rows: Row[]): Res {
    if (this.mode === 'many') return { data: rows, error: null }
    if (rows.length === 0) return this.mode === 'maybe' ? { data: null, error: null } : { data: null, error: { code: 'PGRST116', message: 'no rows' } }
    return { data: rows[0], error: null }
  }
}
