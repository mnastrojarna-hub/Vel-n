// deno test supabase/functions/_tests — D2 (oprava 2026-10-16): /potvrzeni (verify_shop_session)
// zapíše dorovnání platby kartou do objednávky PŘED potvrzením — doklady vystavené při
// potvrzení (DP triggerem) pak nesou zaplacených 15 Kč, ne 7 Kč.
import { verifyShopSession, type StripeSessionsLike } from '../process-payment/verify-shop-session.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }

type Row = Record<string, unknown>
function setup(order: Row, session: Row) {
  const db = new FakeDb({ shop_orders: [order], shop_order_items: [{ order_id: order.id, product_name: 'Tričko' }], vouchers: [], debug_log: [] })
  /** stav objednávky v okamžiku potvrzení (tehdy trigger vystaví DP) */
  const atConfirm: Row[] = []
  db.rpcs.confirm_shop_payment = (a) => {
    const o = db.rows('shop_orders').find((r) => r.id === a.p_order_id)!
    atConfirm.push({ ...o })
    const was = o.payment_status === 'paid'
    o.payment_status = 'paid'
    return { data: { success: true, was_already_paid: was }, error: null }
  }
  const stripe: StripeSessionsLike = { checkout: { sessions: { retrieve: (_id: string) => Promise.resolve(session) } } }
  const fetched: string[] = []
  const fetchFn = ((u: string) => { fetched.push(String(u)); return Promise.resolve(new Response('{}')) }) as unknown as typeof fetch
  return { db, atConfirm, fetched, deps: { sb: db, stripe, supabaseUrl: 'https://x', serviceKey: 'k', fetchFn } }
}
const paidSession = (md: Row) => ({ id: 'cs_1', payment_status: 'paid', status: 'complete', amount_total: 1500,
  payment_intent: 'pi_1', metadata: { order_id: 'o1', type: 'shop', source: 'web', ...md } })

Deno.test('verify_shop_session: due 7 / dorovnání 8 → před potvrzením total 15 a card_rounding 8', async () => {
  const s = setup({ id: 'o1', total: 7, card_rounding: 0, payment_status: 'pending', stripe_payment_intent_id: null },
    paidSession({ due: '7', card_rounding: '8' }))
  const res = await verifyShopSession({ action: 'verify_shop_session', session_id: 'cs_1', order_id: 'o1' }, s.deps)
  const j = await res.json()
  eq(res.status, 200); eq(j.success, true); eq(j.confirmed, true)
  eq(s.atConfirm.length, 1, 'potvrzeno jednou')
  eq(s.atConfirm[0].total, 15, 'DP při potvrzení = zaplacená částka'); eq(s.atConfirm[0].card_rounding, 8)
  eq(s.atConfirm[0].payment_status, 'pending', 'dorovnání zapsané ještě před potvrzením')
  const o = s.db.rows('shop_orders')[0]
  eq([o.total, o.card_rounding, o.payment_status, o.stripe_payment_intent_id], [15, 8, 'paid', 'pi_1'])
  ok(s.db.rows('debug_log').some((r) => r.action === 'card_rounding_applied'))
})

Deno.test('verify_shop_session: webhook dorovnání už zapsal (souběh) → nic nepřičte podruhé, potvrdí', async () => {
  const s = setup({ id: 'o1', total: 15, card_rounding: 8, payment_status: 'pending', stripe_payment_intent_id: null },
    paidSession({ due: '7', card_rounding: '8' }))
  const j = await (await verifyShopSession({ session_id: 'cs_1', order_id: 'o1' }, s.deps)).json()
  eq(j.success, true)
  eq(s.atConfirm[0].total, 15); eq(s.db.rows('shop_orders')[0].card_rounding, 8)
  // webhook potvrdil i dorovnal dřív → already_paid, bez druhého mailu
  const s2 = setup({ id: 'o1', total: 15, card_rounding: 8, payment_status: 'paid', stripe_payment_intent_id: 'pi_1' },
    paidSession({ due: '7', card_rounding: '8' }))
  const j2 = await (await verifyShopSession({ session_id: 'cs_1', order_id: 'o1' }, s2.deps)).json()
  eq([j2.success, j2.already_paid], [true, true]); eq(s2.db.rows('shop_orders')[0].total, 15); eq(s2.fetched.length, 0)
})

Deno.test('verify_shop_session: výpadek DB při dorovnání → retry, objednávka NEpotvrzená', async () => {
  const s = setup({ id: 'o1', total: 7, card_rounding: 0, payment_status: 'pending', stripe_payment_intent_id: null },
    paidSession({ due: '7', card_rounding: '8' }))
  s.db.failUpdate = (t) => (t === 'shop_orders' ? { code: '57014', message: 'canceling statement due to statement timeout' } : null)
  const res = await verifyShopSession({ session_id: 'cs_1', order_id: 'o1' }, s.deps)
  const j = await res.json()
  eq([res.status, j.success, j.retry], [200, false, true])
  eq(s.atConfirm.length, 0, 'bez potvrzení'); eq(s.db.rows('shop_orders')[0].payment_status, 'pending')
  eq(s.db.rows('shop_orders')[0].total, 7)
})

Deno.test('verify_shop_session: cena objednávky se mezitím změnila → mismatch jen záznam, potvrdí bez dorovnání', async () => {
  const s = setup({ id: 'o1', total: 20, card_rounding: 0, payment_status: 'pending', stripe_payment_intent_id: null },
    paidSession({ due: '7', card_rounding: '8' }))
  const j = await (await verifyShopSession({ session_id: 'cs_1', order_id: 'o1' }, s.deps)).json()
  eq(j.success, true); eq(s.atConfirm[0].total, 20); eq(s.db.rows('shop_orders')[0].card_rounding, 0)
  ok(s.db.rows('debug_log').some((r) => r.action === 'card_rounding_mismatch'))
})

Deno.test('verify_shop_session: beze změny — bez dorovnání, nezaplacená session, cizí objednávka', async () => {
  // běžná objednávka (≥ 15 Kč, bez metadat dorovnání)
  const s = setup({ id: 'o1', total: 990, card_rounding: 0, payment_status: 'pending', stripe_payment_intent_id: null }, paidSession({}))
  eq((await (await verifyShopSession({ session_id: 'cs_1' }, s.deps)).json()).confirmed, true)
  eq(s.atConfirm[0].total, 990)
  // nezaplacená session → pending, nic se nezapíše
  const u = setup({ id: 'o1', total: 7, card_rounding: 0, payment_status: 'pending' },
    { ...paidSession({ due: '7', card_rounding: '8' }), payment_status: 'unpaid', status: 'open' })
  const ju = await (await verifyShopSession({ session_id: 'cs_1', order_id: 'o1' }, u.deps)).json()
  eq([ju.success, ju.payment_status], [false, 'unpaid']); eq(u.db.rows('shop_orders')[0].total, 7); eq(u.atConfirm.length, 0)
  // session patří jiné objednávce → order_mismatch
  const m = setup({ id: 'o2', total: 7, card_rounding: 0, payment_status: 'pending' }, paidSession({ due: '7', card_rounding: '8' }))
  const rm = await verifyShopSession({ session_id: 'cs_1', order_id: 'o2' }, m.deps)
  eq(rm.status, 400); eq((await rm.json()).error, 'order_mismatch'); eq(m.atConfirm.length, 0)
  // chybí identifikátor
  eq((await verifyShopSession({}, m.deps)).status, 400)
})
