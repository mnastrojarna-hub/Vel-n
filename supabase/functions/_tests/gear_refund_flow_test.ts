// ===== _tests/gear_refund_flow_test.ts =====
// Výpůjčka výbavy (2026-10-23) — flow testy CELÉHO handleru process-refund (kód main po hotfixu #2213):
// spodní mez ceny zákaznické vratky (gear = cena/den × dny − slevy; dřív null = vždy obsluha)
// a předmět ručního dobropisu „výpůjčka výbavy“ — gear i motorková regrese.
// Potřebují import mapu (supabase-js = LooseDb); spouští je gear_flow_runner_test.ts v podprocesu:
//   deno test --allow-all --no-check --import-map=supabase/functions/_tests/gear-flow-map.json supabase/functions/_tests/gear_refund_flow_test.ts
import { LooseDb, stubFetch } from './gear-fake.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, unknown>
type Handler = (req: Request) => Response | Promise<Response>

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
const SVC = 'svc-test-key'
if (MAPPED) { // stejné hodnoty jako ostatní flow testy (sdílený proces)
  Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test')
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
}
const g = globalThis as unknown as { __gearFakeDb?: unknown; __gearAuthUser?: Row | null }
const BID = '11111111-2222-3333-4444-555566667777'
const USER_JWT = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2ln' // tvar JWT; ověřuje ho LooseDb.auth.getUser
let handler: Handler | null = null

async function refundHandler(): Promise<Handler> {
  if (handler) return handler
  const d = Deno as unknown as { serve: unknown }
  const orig = d.serve
  d.serve = (h: Handler) => { handler = h; return { finished: Promise.resolve(), shutdown: () => Promise.resolve() } }
  try { await import('../process-refund/index.ts') } finally { d.serve = orig }
  if (!handler) throw new Error('handler process-refund se nezaregistroval')
  return handler
}

function bookingRow(kind: 'gear' | 'moto', over: Row = {}): Row {
  return {
    id: BID, booking_kind: kind, user_id: 'u1', status: 'reserved', payment_status: 'unpaid',
    payment_method: 'card', moto_id: kind === 'gear' ? null : 'm1', start_date: '2026-11-10', end_date: '2026-11-11',
    total_price: 800, gear_per_day: kind === 'gear' ? 400 : null,
    gear_lines: kind === 'gear' ? [{ key: 'helmet', size: 'M', price_per_day: 250 }, { key: 'gloves', size: 'L', price_per_day: 150 }] : null,
    motorcycles: kind === 'gear' ? null : { model: 'BMW R 1250 GS' },
    profiles: { id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' }, ...over,
  }
}
function dbOf(row: Row, extra: Record<string, Row[]> = {}) {
  const db = new LooseDb({
    bookings: [row], booking_discounts: [], invoices: [], debug_log: [], app_settings: [], accounting_entries: [],
    motorcycles: [{ id: 'm1', price_mon: 1000, price_tue: 1000, price_wed: 1000, price_thu: 1000, price_fri: 1000, price_sat: 1000, price_sun: 1000 }],
    ...extra,
  })
  db.rpcs._moto_dayprice_sum = () => ({ data: 2000, error: null })
  db.rpcs.next_document_number = () => ({ data: 'DB-2026-0042', error: null })
  return db
}
async function refund(db: LooseDb, body: Row, customer: boolean) {
  g.__gearFakeDb = db
  g.__gearAuthUser = customer ? { id: 'u1', email: 'jana@example.com' } : null
  const h = await refundHandler()
  const f = stubFetch(() => new Response('{}', { status: 200 }))
  try {
    const res = await h(new Request('http://x/pr', { method: 'POST',
      headers: { Authorization: `Bearer ${customer ? USER_JWT : SVC}` }, body: JSON.stringify({ booking_id: BID, ...body }) }))
    return { status: res.status, json: await res.json(), fetches: f.calls, db }
  } finally { f.restore(); g.__gearAuthUser = null }
}
const shorten = { amount: 400, reason: 'edit_shortening' }
const logged = (db: LooseDb, action: string) => db.rows('debug_log').filter((r) => r.action === action)
const starReads = (db: LooseDb) => db.callsOf('select', 'bookings').filter((c) => String(c.data).trim() === '*').length

Deno.test({ name: 'flow vratka gear (zákazník): cena ≥ cena/den × dny → mez projde (dál jako motorka — tady not_paid), dřív vždy obsluha', ignore: !MAPPED, fn: async () => {
  const r = await refund(dbOf(bookingRow('gear')), shorten, true)
  eq([r.status, r.json.code], [400, 'not_paid'], JSON.stringify(r.json))
  eq(logged(r.db, 'customer_price_below_floor').length, 0)
  eq(r.db.callsOf('rpc', '_moto_dayprice_sum').length, 0, 'gear: motorkový ceník se nevolá')
  // 50 % vratka zkrácení nechá v ceně půlku odebraného dne → nad mezí.
  const half = await refund(dbOf(bookingRow('gear', { total_price: 1000 })), shorten, true)
  eq(half.json.code, 'not_paid')
} })

Deno.test({ name: 'flow vratka gear (zákazník): cena pod mezí → refund_needs_staff + mail obsluze; poukaz mez snižuje', ignore: !MAPPED, fn: async () => {
  const lo = await refund(dbOf(bookingRow('gear', { total_price: 500 })), shorten, true)
  eq([lo.status, lo.json.code], [200, 'refund_needs_staff'], JSON.stringify(lo.json))
  eq((logged(lo.db, 'customer_price_below_floor')[0]?.request_data as Row)?.floor, 800)
  ok(lo.fetches.some((c) => c.url.endsWith('/functions/v1/send-email')), 'mail obsluze')
  const v = await refund(dbOf(bookingRow('gear', { total_price: 500 }), { booking_discounts: [{ booking_id: BID, amount: 300 }] }), shorten, true)
  eq(v.json.code, 'not_paid', 'mez 800 − poukaz 300 = 500')
} })

Deno.test({ name: 'flow vratka gear (zákazník): výpadek DB při čtení druhu → jako motorka bez motorky = obsluha (beze změny proti main)', ignore: !MAPPED, fn: async () => {
  const db = dbOf(bookingRow('gear'))
  db.failSelect = (t, cols) => (t === 'bookings' && cols.trim() === '*' ? { code: '57P01', message: 'terminating connection' } : null)
  const r = await refund(db, shorten, true)
  eq(r.json.code, 'refund_needs_staff')
  eq((logged(r.db, 'customer_price_below_floor')[0]?.request_data as Row)?.floor, null)
} })

Deno.test({ name: 'flow vratka MOTO regrese (zákazník): mez z _moto_dayprice_sum přesně jako dřív, bez dotazu na druh', ignore: !MAPPED, fn: async () => {
  const r = await refund(dbOf(bookingRow('moto', { total_price: 2000 })), shorten, true)
  eq(r.json.code, 'not_paid', JSON.stringify(r.json))
  eq(r.db.callsOf('rpc', '_moto_dayprice_sum').map((c) => c.data), [{ p_moto_id: 'm1', p_start: '2026-11-10', p_end: '2026-11-11' }])
  eq(starReads(r.db), 0, 'motorka: žádný select(*) pro gear')
  const lo = await refund(dbOf(bookingRow('moto', { total_price: 900 })), shorten, true)
  eq(lo.json.code, 'refund_needs_staff', '0.8 × 2000 − 0.5 × 1000 = 1100 > 900')
  eq((logged(lo.db, 'customer_price_below_floor')[0]?.request_data as Row)?.floor, 1100)
} })

async function manualCn(row: Row) {
  const r = await refund(dbOf({ ...row, payment_status: 'paid', payment_method: 'bank_transfer', total_price: 1200 }),
    { amount: 400, reason: 'edit_shortening' }, false)
  eq([r.status, r.json.code], [200, 'manual_refund_pending'], JSON.stringify(r.json))
  const cn = r.db.rows('invoices').find((i) => i.type === 'credit_note') as Row
  const blob = Object.values(r.db.files)[0] as Blob | undefined
  const html = blob ? await blob.text() : ''
  return { desc: (cn.items as Array<{ description: string }>)[0].description, stars: starReads(r.db), html }
}
Deno.test({ name: 'flow ruční dobropis: gear „(výpůjčka výbavy)“, motorka model, motorka bez modelu „(motorky)“', ignore: !MAPPED, fn: async () => {
  const gr = await manualCn(bookingRow('gear'))
  ok(/\(výpůjčka výbavy\)$/.test(gr.desc), gr.desc)
  ok(gr.html.includes('Rezervace: výpůjčka výbavy'), 'dobropis (HTML ve Storage) nese „výpůjčka výbavy“')
  const mo = await manualCn(bookingRow('moto'))
  ok(/\(BMW R 1250 GS\)$/.test(mo.desc), mo.desc)
  eq(mo.stars, 0, 'motorka s modelem: bez dotazu na druh')
  ok(mo.html.includes('Rezervace: BMW R 1250 GS'), 'motorkový dobropis beze změny')
  const del = await manualCn(bookingRow('moto', { moto_id: null, motorcycles: null }))
  ok(/\(motorky\)$/.test(del.desc), del.desc)
} })
