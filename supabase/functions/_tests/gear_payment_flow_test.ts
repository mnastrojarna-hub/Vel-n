// ===== _tests/gear_payment_flow_test.ts =====
// Výpůjčka výbavy (2026-10-23) — flow testy CELÝCH handlerů plateb na kódu main (po hotfixu #2213):
// process-payment (doplatek úpravy = jen p_new_* termín, 0 Kč ověření → mail dle dokladu, popis
// platby appky) + generate-invoice (rozdílový doklad prodloužení) — gear i motorková regrese.
// Potřebují import mapu (supabase-js = LooseDb); spouští je gear_flow_runner_test.ts v podprocesu:
//   deno test --allow-all --no-check --import-map=supabase/functions/_tests/gear-flow-map.json supabase/functions/_tests/gear_payment_flow_test.ts
import { LooseDb, stubFetch } from './gear-fake.ts'
import { GEAR_DRY_TXT } from '../process-payment/gear-checkout.ts'
import { stripe } from '../process-payment/stripe-customer.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, unknown>
type Handler = (req: Request) => Response | Promise<Response>

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
const SVC = 'svc-test-key'
if (MAPPED) { // stejné hodnoty jako gear_flow_test.ts (sdílený proces)
  Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test')
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
}
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown }
const BID = '11111111-2222-3333-4444-555566667777'
const handlers: Record<string, Handler> = {}

/** Handler přes Deno.serve (process-payment) nebo std serve (generate-invoice, gear-flow-stubs.ts). */
async function handlerOf(path: string): Promise<Handler> {
  if (handlers[path]) return handlers[path]
  const d = Deno as unknown as { serve: unknown }
  const orig = d.serve
  let captured: Handler | null = null
  const before = (g.__gearHandlers || []).length
  d.serve = (h: Handler) => { captured = h; return { finished: Promise.resolve(), shutdown: () => Promise.resolve() } }
  try { await import(path) } finally { d.serve = orig }
  const h = captured || (g.__gearHandlers || [])[before]
  if (!h) throw new Error(`handler ${path} se nezaregistroval`)
  return (handlers[path] = h)
}

type StripeMock = { paymentIntents: { create: (p: Row) => Promise<Row> }; checkout: { sessions: { retrieve: (id: string) => Promise<Row> } } }
function patchStripe(session: Row = {}) {
  const st = stripe as unknown as StripeMock
  const orig = { pi: st.paymentIntents.create, ret: st.checkout.sessions.retrieve }
  const intents: Row[] = []
  st.paymentIntents.create = (p: Row) => { intents.push(p); return Promise.resolve({ id: 'pi_t', client_secret: 'pi_t_secret', status: 'requires_payment_method' }) }
  st.checkout.sessions.retrieve = () => Promise.resolve(session)
  return { intents, restore: () => { st.paymentIntents.create = orig.pi; st.checkout.sessions.retrieve = orig.ret } }
}

function bookingRow(kind: 'gear' | 'moto', over: Row = {}): Row {
  return {
    id: BID, booking_kind: kind, user_id: 'u1', status: 'reserved', payment_status: 'paid', booking_source: 'web',
    moto_id: kind === 'gear' ? null : 'm1', trailer_moto_id: null, total_price: 1200, sos_replacement: false,
    start_date: '2026-11-10', end_date: '2026-11-12', pickup_time: '10:00:00', delivery_fee: 0,
    pickup_method: 'store', pickup_address: null, return_method: 'store', return_address: null,
    gear_per_day: kind === 'gear' ? 400 : null,
    motorcycles: kind === 'gear' ? null : { model: 'BMW R 1250 GS', manual_url: '', is_trailer: false },
    profiles: { full_name: 'Jana Nováková', email: 'jana@example.com' }, ...over,
  }
}
async function pay(db: LooseDb, body: Row, session: Row = {}) {
  g.__gearFakeDb = db
  const h = await handlerOf('../process-payment/index.ts')
  const st = patchStripe(session)
  const f = stubFetch(() => new Response('{}', { status: 200 }))
  try {
    const res = await h(new Request('http://x/pp', { method: 'POST', headers: { Authorization: `Bearer ${SVC}` }, body: JSON.stringify(body) }))
    return { status: res.status, json: await res.json(), intents: st.intents, fetches: f.calls, db }
  } finally { st.restore(); f.restore() }
}
const kindReads = (db: LooseDb) => db.callsOf('select', 'bookings').filter((c) => String(c.data).trim() === 'booking_kind').length
function editDb(kind: 'gear' | 'moto', dry: Row) {
  const db = new LooseDb({ bookings: [bookingRow(kind)], profiles: [], debug_log: [] })
  for (const fn of ['apply_booking_changes', 'split_booking_moto_swap', 'update_booking_gear']) db.rpcs[fn] = () => ({ data: dry, error: null })
  return db
}
const ext = (change: Row, amount = 400) => ({ type: 'extension', booking_id: BID, amount, mode: 'intent', change })

Deno.test({ name: 'flow doplatek gear: výměna / přidání motorky, výbava motorkové rezervace a app formát → change_not_applicable bez dry-runu a bez platby', ignore: !MAPPED, fn: async () => {
  for (const [change, reason] of [
    [{ _swap: { m: 'm2', d: '2026-11-11' } }, 'gear_no_moto'],
    [{ p_new_end: '2026-11-13', p_new_moto_id: 'm2' }, 'gear_no_moto'],
    [{ _gear: { sizes: { helmet: 'L' } } }, 'gear_sizes_free'],
    [{ total_price: 1600, end_date: '2026-11-13' }, 'gear_app_format'],
    // Smíšený payload (review 2026-10-23): dry-run by nacenil jen p_new_end, webhook by zapsal i sloupce.
    [{ p_new_end: '2026-11-13', start_date: '2026-11-01' }, 'gear_app_format'],
    [{ p_new_end: '2026-11-13', discount_amount: 0 }, 'gear_app_format'],
    [{ p_new_end: '2026-11-13', start_date: '2026-11-01', delivery_fee: 700, discount_amount: 0 }, 'gear_app_format'],
  ] as Array<[Row, string]>) {
    const r = await pay(editDb('gear', { success: true, net: 400, net_diff: 400 }), ext(change))
    eq([r.status, r.json.code, r.json.reason], [409, 'change_not_applicable', reason], JSON.stringify(change))
    eq(r.json.error, GEAR_DRY_TXT[reason])
    eq(r.db.calls.filter((c) => c.op === 'rpc').length, 0, `${reason}: žádný dry-run`)
    eq(r.intents.length, 0, `${reason}: nic se nestrhlo`)
  }
} })

Deno.test({ name: 'flow doplatek gear: termín (p_new_*) → dry-run apply_booking_changes; out_of_stock = gear text; úspěch = PaymentIntent na serverovou částku', ignore: !MAPPED, fn: async () => {
  const no = await pay(editDb('gear', { error: 'out_of_stock' }), ext({ p_new_end: '2026-11-13' }))
  eq([no.status, no.json.code, no.json.reason, no.json.error], [409, 'change_not_applicable', 'out_of_stock', GEAR_DRY_TXT.out_of_stock])
  eq(no.db.callsOf('rpc', 'apply_booking_changes')[0].data, { p_booking_id: BID, p_dry_run: true, p_new_end: '2026-11-13' })
  const st = await pay(editDb('gear', { error: 'wrong_status' }), ext({ p_new_end: '2026-11-13' }))
  eq([st.status, st.json.code], [409, 'wrong_status'], 'kód mimo gear texty → motorková hláška main beze změny')
  const r = await pay(editDb('gear', { success: true, net_diff: 400, new_total: 1600 }), ext({ p_new_end: '2026-11-13' }))
  eq([r.status, r.json.success], [200, true], JSON.stringify(r.json))
  eq(r.intents.length, 1)
  eq([r.intents[0].amount, r.intents[0].description], [40000, 'MotoGo24 — Prodloužení rezervace'])
  ok(String((r.intents[0].metadata as Row).chg).includes('p_new_end'), 'změna v metadatech pro webhook')
  eq(kindReads(r.db), 1, 'gear: druh se dohledá (řádek bez motorky)')
  // Celý tvar payloadu webu (_submitChange: p_new_* + new_total + _base + _time_update) projde.
  const web = await pay(editDb('gear', { success: true, net_diff: 400, new_total: 1600 }), ext({ p_new_end: '2026-11-13', new_total: 1600,
    _base: { s: '2026-11-10', e: '2026-11-12', t: '10:00', p: 1200, l: 0 }, _time_update: { return_time: '18:00' } }))
  eq([web.status, web.json.success, web.intents.length], [200, true, 1], JSON.stringify(web.json))
  eq(web.db.callsOf('rpc', 'apply_booking_changes')[0].data, { p_booking_id: BID, p_dry_run: true, p_new_end: '2026-11-13' })
  const bad = await pay(editDb('gear', { success: true, net_diff: 400 }), ext({ p_new_end: '2026-11-13' }, 50))
  eq([bad.status, bad.json.code], [400, 'amount_mismatch'])
} })

Deno.test({ name: 'flow doplatek MOTO regrese: kódy main beze změny, swap přes split_booking_moto_swap, bez dotazu na booking_kind', ignore: !MAPPED, fn: async () => {
  const no = await pay(editDb('moto', { error: 'moto_unavailable' }), ext({ p_new_end: '2026-11-13' }))
  eq([no.status, no.json.code], [409, 'moto_unavailable'])
  ok(/Motorka je v novém termínu už obsazená/.test(String(no.json.error)))
  eq(kindReads(no.db), 0, 'motorka: žádný dotaz na druh')
  const sw = await pay(editDb('moto', { success: true, net: 500 }), ext({ _swap: { m: 'm2', d: '2026-11-11' } }, 500))
  eq([sw.status, sw.json.success], [200, true], JSON.stringify(sw.json))
  eq(sw.db.callsOf('rpc', 'split_booking_moto_swap').length, 1)
  eq(sw.intents[0].amount, 50000)
  eq(kindReads(sw.db), 0)
} })

async function verifyFree(kind: 'gear' | 'moto', docs: string | null) {
  const db = new LooseDb({ bookings: [bookingRow(kind, { payment_status: 'unpaid', total_price: 0 })], debug_log: [] })
  db.rpcs.confirm_payment = () => ({ data: { success: true, was_already_paid: false }, error: null })
  db.rpcs.check_booking_docs_status_for = () => ({ data: docs, error: null })
  db.rpcs.check_booking_docs_status = () => ({ data: docs, error: null })
  const r = await pay(db, { action: 'verify_setup_session', session_id: 'cs_free' },
    { id: 'cs_free', status: 'complete', mode: 'setup', metadata: { action: 'verify_free_booking', booking_id: BID } })
  eq([r.status, r.json.confirmed], [200, true], JSON.stringify(r.json))
  eq(db.callsOf('rpc', 'check_booking_docs_status').length, 0, 'motorková brána dokladů se tu nevolá (beze změny)')
  return { type: r.fetches.find((c) => c.url.endsWith('/functions/v1/send-booking-email'))?.body?.type, kindReads: kindReads(db) }
}
Deno.test({ name: 'flow 0 Kč ověření (verify_setup_session) gear: web bez dokladu → invoice_payment_receipt, s dokladem booking_reserved', ignore: !MAPPED, fn: async () => {
  eq(await verifyFree('gear', 'missing'), { type: 'invoice_payment_receipt', kindReads: 1 })
  eq(await verifyFree('gear', null), { type: 'booking_reserved', kindReads: 1 })
} })
Deno.test({ name: 'flow 0 Kč ověření MOTO regrese: vždy booking_reserved, bez dotazu na booking_kind', ignore: !MAPPED, fn: async () => {
  eq(await verifyFree('moto', 'missing'), { type: 'booking_reserved', kindReads: 0 })
} })

async function appIntent(kind: 'gear' | 'moto') {
  const db = new LooseDb({ bookings: [bookingRow(kind, { payment_status: 'unpaid', booking_source: 'app' })], profiles: [], debug_log: [] })
  const r = await pay(db, { type: 'booking', booking_id: BID, amount: 1200, mode: 'intent' })
  eq([r.status, r.json.success], [200, true], JSON.stringify(r.json))
  return [r.intents[0].description, r.intents[0].amount]
}
Deno.test({ name: 'flow platba appky (intent) gear: popis „Půjčení výbavy“', ignore: !MAPPED, fn: async () => {
  eq(await appIntent('gear'), ['MotoGo24 — Půjčení výbavy', 120000])
} })
Deno.test({ name: 'flow platba appky (intent) MOTO regrese: popis „Pronájem motorky“', ignore: !MAPPED, fn: async () => {
  eq(await appIntent('moto'), ['MotoGo24 — Pronájem motorky', 120000])
} })

// ── generate-invoice: rozdílový doklad prodloužení (source 'edit') ───────────
async function editInvoice(kind: 'gear' | 'moto') {
  const hist = [{ at: new Date().toISOString(), from_start: '2026-11-10', from_end: '2026-11-12', to_start: '2026-11-10', to_end: '2026-11-13', source: 'web' }]
  const db = new LooseDb({
    bookings: [{ ...bookingRow(kind, { total_price: 1600, end_date: '2026-11-13', stripe_payment_intent_id: 'pi_1', modification_history: hist }),
      motorcycles: kind === 'gear' ? null : { model: 'BMW R 1250 GS', spz: '1AB 2345', price_mon: 1000, price_tue: 1000, price_wed: 1000, price_thu: 1000, price_fri: 1000, price_sat: 1000, price_sun: 1000 },
      profiles: { id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' } }],
    booking_extras: [], booking_discounts: [], invoices: [], payment_methods: [], app_settings: [], debug_log: [],
  })
  db.rpcs.next_document_number = () => ({ data: 'DP-2026-0042', error: null })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  g.__gearFakeDb = db
  const h = await handlerOf('../generate-invoice/index.ts')
  const res = await h(new Request('http://x/gi', { method: 'POST', headers: { Authorization: `Bearer ${SVC}` },
    body: JSON.stringify({ type: 'payment_receipt', booking_id: BID, source: 'edit', price_difference: kind === 'gear' ? 400 : 1000, send_email: false }) }))
  const inv = db.rows('invoices')[0] as Row
  return { status: res.status, items: ((inv?.items || []) as Array<{ description: string; qty: number; unit_price: number }>).filter((i) => !i.description.startsWith('──')) }
}

Deno.test({ name: 'flow rozdílový doklad prodloužení gear: den = gear_per_day „Půjčení výbavy“, bez motorky', ignore: !MAPPED, fn: async () => {
  const gr = await editInvoice('gear')
  eq(gr.status, 200)
  eq(gr.items.map((i) => [i.description.replace(/ — .*/, ''), i.qty, i.unit_price]), [['Půjčení výbavy', 1, 400]], JSON.stringify(gr.items))
  ok(!gr.items.some((i) => /motork|Pronájem/i.test(i.description)))
} })
Deno.test({ name: 'flow rozdílový doklad prodloužení MOTO regrese: „Pronájem <model>“ za den beze změny', ignore: !MAPPED, fn: async () => {
  const mo = await editInvoice('moto')
  eq(mo.items.map((i) => [i.description.replace(/ — .*/, ''), i.qty, i.unit_price]), [['Pronájem BMW R 1250 GS (1AB 2345)', 1, 1000]], JSON.stringify(mo.items))
} })
