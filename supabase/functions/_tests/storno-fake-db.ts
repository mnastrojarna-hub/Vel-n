// ===== _tests/storno-fake-db.ts =====
// In-memory náhrada supabase-js pro flow testy storna (HOTFIX 2026-10-29): select se sloupci
// i embedy (profiles, motorcycles), filtry eq/neq/gte/lt/in/is/or/like/not, order, limit, single,
// insert/update/delete/upsert, count/head, rpc, storage a auth.getUser. created_at = reálný čas
// (15min okna process-refund); beforeInsert / beforeUpdate simulují DB triggery a pád isolatu.
// deno-lint-ignore-file no-explicit-any
type Row = Record<string, any>
type Res = { data: any; error: { code?: string; message: string } | null; count?: number }

export class Db {
  tables: Record<string, Row[]>
  rpcs: Record<string, (args: Row) => Res | Promise<Res>> = {}
  users = new Map<string, { id: string }>() // token → uživatel
  files = new Map<string, Blob>()
  beforeUpdate: ((table: string, patch: Row) => void) | null = null
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
    upload: (p: string, blob: Blob) => { this.files.set(p, blob); return Promise.resolve({ data: { path: p }, error: null }) },
    download: (p: string) => Promise.resolve(this.files.has(p) ? { data: this.files.get(p), error: null } : { data: null, error: { message: 'not found' } }),
  }) }
}

const get = (r: Row, col: string): any => {
  const m = col.match(/^(\w+)->>(\w+)$/)
  if (m) { const o = r[m[1]]; return o == null || o[m[2]] == null ? undefined : String(o[m[2]]) }
  return r[col]
}
const same = (a: any, b: any) => {
  if (a == null || b == null) return a == b
  if (typeof a === 'number' || typeof b === 'number') return Number(a) === Number(b)
  return String(a) === String(b)
}
function splitTop(s: string): string[] {
  const out: string[] = []; let d = 0, cur = ''
  for (const ch of s) { if (ch === '(') d++; if (ch === ')') d--; if (ch === ',' && d === 0) { out.push(cur.trim()); cur = '' } else cur += ch }
  if (cur.trim()) out.push(cur.trim())
  return out
}
/** PostgREST or(): `a.eq.x,and(b.eq.y,c.eq.z)` */
function orFilter(expr: string): (r: Row) => boolean {
  const one = (p: string): ((r: Row) => boolean) => {
    const and = p.match(/^and\((.*)\)$/)
    if (and) { const subs = splitTop(and[1]).map(one); return (r) => subs.every((f) => f(r)) }
    const [c, op, ...v] = p.split('.'); const val = v.join('.')
    if (op === 'eq') return (r) => same(get(r, c), val)
    if (op === 'neq') return (r) => !same(get(r, c), val)
    if (op === 'is') return (r) => get(r, c) == null
    return () => false
  }
  const fs = splitTop(expr).map(one)
  return (r) => fs.some((f) => f(r))
}
// embed alias:fk(cols) | table!fk(cols) | table(cols) → [tabulka, sloupec FK]
const FK: Record<string, [string, string]> = { profiles: ['profiles', 'user_id'], user_id: ['profiles', 'user_id'],
  customer_id: ['profiles', 'customer_id'], motorcycles: ['motorcycles', 'moto_id'], moto_id: ['motorcycles', 'moto_id'] }

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
    const parts = splitTop(this.cols)
    return rows.map((r) => {
      const o: Row = {}
      for (const c of parts) {
        const m = c.match(/^(?:(\w+):)?(\w+)(?:!(\w+))?\((.*)\)$/)
        if (!m) { o[c] = r[c]; continue }
        const [, alias, name, fk, sub] = m
        const spec = (fk && FK[fk]) || FK[name]
        const ref = spec ? this.db.rows(spec[0]).find((x) => same(x.id, r[spec[1]])) : null
        o[alias || name] = ref ? Object.fromEntries(sub.split(',').map((x) => x.trim()).filter(Boolean).map((x) => [x, ref[x]])) : null
      }
      return o
    })
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
      if (this.op === 'upsert' && this.upsertOpts.onConflict && this.upsertOpts.ignoreDuplicates) {
        const k = String(this.upsertOpts.onConflict)
        if (list.some((r) => all.some((x) => same(x[k], r[k])))) return this.finish([])
      }
      const made = list.map((r) => ({ id: crypto.randomUUID(), created_at: this.db.now(), ...r }))
      for (const r of made) this.db.beforeInsert?.(this.table, r)
      all.push(...made)
      return this.finish(made.map((r) => ({ ...r })))
    }
    if (this.op === 'delete') { this.db.tables[this.table] = all.filter((r) => !rows.includes(r)); return { data: null, error: null } }
    this.db.beforeUpdate?.(this.table, this.patch as Row)
    for (const r of rows) Object.assign(r, this.patch)
    return { data: this.wantReturn ? rows.map((r) => ({ id: r.id })) : null, error: null }
  }
  private finish(rows: Row[]): Res {
    if (this.mode === 'many') return { data: rows, error: null }
    if (rows.length === 0) return this.mode === 'maybe' ? { data: null, error: null } : { data: null, error: { code: 'PGRST116', message: 'no rows' } }
    return { data: rows[0], error: null }
  }
}
