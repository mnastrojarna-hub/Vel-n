// ===== _tests/gear_rounding_test.ts =====
// D1 (oprava 2026-10-16): placená výbava (web) — dorovnání na minimální platbu kartou v TÉMŽE
// zápisu jako změna (apply_paid_gear_change rev.2, SQL 20261016p4), samostatné dorovnání jen
// když změnu zapsal web sám (záznam price_diff = r) + DP na něj, pokud ho nevystaví mail o úpravě.
import { applyPaidExtension } from '../_shared/extension-apply.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
function db(over: Row = {}) {
  const d = new FakeDb({ bookings: [{
    id: 'b1', user_id: 'u1', status: 'reserved', payment_status: 'paid', moto_id: 'm1', total_price: 3000, card_rounding: 0,
    modification_history: [], updated_at: '2026-10-16T11:00:00.000Z', ...over }], debug_log: [] })
  return d
}
const row = (d: FakeDb) => d.rows('bookings')[0]
const hist = (d: FakeDb) => row(d).modification_history as Row[]

Deno.test('gear D1 (20261016p4): doplatek 7 Kč zaplacený 15 Kč → RPC dostane zaplacenou částku, dorovnání v TÉMŽE zápisu', async () => {
  const d = db()
  const calls: Row[] = []
  // rev.2: dorovnání spočítá SQL ze skutečného doplatku (7) a zaplacené částky (15) a zapíše ho s cenou
  d.rpcs.apply_paid_gear_change = (p) => {
    calls.push(p)
    if (hist(d).some((h) => h.payment_ref === p.p_payment_ref)) return { data: { success: true, already_applied: true, net_diff: 0, card_rounding: 0 }, error: null }
    const r = Number(p.p_paid) - 7
    Object.assign(row(d), { total_price: Number(row(d).total_price) + 7 + r, card_rounding: Number(row(d).card_rounding) + r,
      modification_history: [...hist(d), { auto: true, price_diff: 15, card_rounding: r, payment_ref: p.p_payment_ref }] })
    return { data: { success: true, net_diff: 7, card_rounding: r }, error: null }
  }
  const a = { bookingId: 'b1', chg: JSON.stringify({ _gear: { sizes: { helmet: 'L' } } }), paidCzk: 15, payRef: 'pi_g', rounding: 8 } as never
  eq((await applyPaidExtension(d, a)).state, 'applied')
  eq([calls[0].p_paid, calls[0].p_payment_ref, typeof calls[0].p_chg_hash, 'p_card_rounding' in calls[0]], [15, 'pi_g', 'string', false])
  eq([row(d).total_price, row(d).card_rounding], [3015, 8])
  eq(d.calls.filter((c) => c.op === 'update' && c.table === 'bookings').length, 0, 'žádný samostatný zápis dorovnání')
  eq((await applyPaidExtension(d, a)).state, 'already_applied'); eq([row(d).total_price, row(d).card_rounding], [3015, 8])
  // bez zaplacené částky (přibalená objednávka) → p_card_rounding z metadat
  const d2 = db()
  const c2: Row[] = []
  d2.rpcs.apply_paid_gear_change = (p) => { c2.push(p); return { data: { success: true, net_diff: 7, card_rounding: 8 }, error: null } }
  await applyPaidExtension(d2, { bookingId: 'b1', chg: JSON.stringify({ _gear: { sizes: { helmet: 'L' } } }), paidCzk: null, payRef: 'pi_h', rounding: 8 } as never)
  eq([c2[0].p_card_rounding, 'p_paid' in c2[0]], [8, false])
})

Deno.test('gear D1: web změnu zapsal sám (doplatek při zápisu 0) → dorovnání zvlášť, záznam price_diff = r, jednou', async () => {
  const d = db({ total_price: 3007 })
  d.rpcs.apply_paid_gear_change = () => ({ data: { success: true, net_diff: 0, card_rounding: 0 }, error: null })
  const a = { bookingId: 'b1', chg: JSON.stringify({ _gear: { sizes: { helmet: 'L' } } }), paidCzk: 15, payRef: 'pi_w', rounding: 8 } as never
  eq((await applyPaidExtension(d, a)).state, 'applied')
  eq([row(d).total_price, row(d).card_rounding], [3015, 8])
  const e = hist(d).at(-1) as Row
  eq([e.type, e.price_diff, e.card_rounding, e.paid, e.payment_ref], ['card_rounding', 8, 8, 15, 'pi_w'])
  // bez SUPABASE_URL v testu → DP se nevystaví, ale je to v debug_log (obsluha)
  eq(d.rows('debug_log').some((r) => r.action === 'rounding_doc_skipped' || r.action === 'rounding_doc_issued'), true)
  eq((await applyPaidExtension(d, a)).state, 'applied'); eq([row(d).total_price, row(d).card_rounding], [3015, 8])
})

Deno.test('gear D1: SQL bez rev.2 (PGRST202 s novými parametry) → 2parametrové volání + dorovnání zvlášť', async () => {
  const d = db()
  const seen: string[] = []
  d.rpcs.apply_paid_gear_change = (p) => {
    seen.push(Object.keys(p).sort().join(','))
    if ('p_payment_ref' in p) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.apply_paid_gear_change' } }
    Object.assign(row(d), { total_price: Number(row(d).total_price) + 7 })
    return { data: { success: true, net_diff: 7 }, error: null }
  }
  const a = { bookingId: 'b1', chg: JSON.stringify({ _gear: { sizes: { helmet: 'L' } } }), paidCzk: 15, payRef: 'pi_l', rounding: 8 } as never
  eq((await applyPaidExtension(d, a)).state, 'applied')
  eq(seen[1], 'p_booking_id,p_sizes')
  eq([row(d).total_price, row(d).card_rounding, (hist(d).at(-1) as Row).price_diff], [3015, 8, 8])
})

// ── DP na samostatně zapsané dorovnání (issueRoundingDoc) ────────────────────
Deno.test('rounding doc: mail o úpravě ho vystaví sám (http_post_queued v téže transakci) → bez druhého DP', async () => {
  const { issueRoundingDoc } = await import('../_shared/extension-apply-rounding.ts')
  const at = '2026-10-16T12:00:05.123456+00:00'
  const sent: Row[] = []
  const f = ((_u: string, o: { body: string }) => { sent.push(JSON.parse(o.body)); return Promise.resolve(new Response('{}')) }) as unknown as typeof fetch
  const env = { url: 'https://x', key: 'k' }
  const queued = new FakeDb({ debug_log: [{ source: 'trg_booking_modified_email', action: 'http_post_queued', request_data: { booking_id: 'b1' }, created_at: at }] })
  eq(await issueRoundingDoc(queued, 'b1', 12, at, f, env), 'mail'); eq(sent.length, 0)
  // zápis spadl do deduplikace (skipped_dedup_5min) → DP přímo, bez mailu
  const dedup = new FakeDb({ debug_log: [
    { source: 'trg_booking_modified_email', action: 'http_post_queued', request_data: { booking_id: 'b1' }, created_at: '2026-10-16T12:00:01.000000+00:00' },
    { source: 'trg_booking_modified_email', action: 'skipped_dedup_5min', request_data: { booking_id: 'b1' }, created_at: at }] })
  eq(await issueRoundingDoc(dedup, 'b1', 12, at, f, env), 'issued')
  eq(sent[0], { type: 'payment_receipt', booking_id: 'b1', source: 'edit', price_difference: 12, send_email: false })
  // zaokrouhlení pod 1 Kč ani odpuštění doklad nemají
  eq(await issueRoundingDoc(dedup, 'b1', 0.4, at, f, env), 'skipped'); eq(await issueRoundingDoc(dedup, 'b1', -0.6, at, f, env), 'skipped')
  eq(sent.length, 1)
})
Deno.test('process-payment: dorovnání výbavy jen s apply_paid_gear_change rev.2 (sonda bez změn)', async () => {
  const { gearRoundingAvailable } = await import('../process-payment/card-minimum.ts')
  const none = new FakeDb({})
  eq(await gearRoundingAvailable(none), false) // funkce s p_paid není (PGRST202)
  const rev2 = new FakeDb({})
  let probe: Row = {}
  rev2.rpcs.apply_paid_gear_change = (p) => { probe = p; return { data: { success: false, error: 'not_found' }, error: null } }
  eq(await gearRoundingAvailable(rev2), true)
  eq([probe.p_booking_id, probe.p_paid], ['00000000-0000-0000-0000-000000000000', 0])
})
