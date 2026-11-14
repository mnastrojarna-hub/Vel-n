// ===== _tests/pp_currency_flow_test.ts =====
// verify:charges (2026-11-07) — celý handler process-payment: „dokonči předchozí zaplacenou úpravu" (uložený
// doplatek, který webhook nezapsal) NEzapíše platbu v cizí měně jako Kč (500 HUF ≈ 15 Kč → změna za 500 Kč);
// nová úprava pokračuje normálně (PaymentIntent v CZK). Import mapa gear-flow-map.json (gear_flow_runner_test.ts).
import { LooseDb, stubFetch } from './gear-fake.ts'
import { stripe } from '../process-payment/stripe-customer.ts'

type Row = Record<string, unknown>
type Handler = (req: Request) => Response | Promise<Response>
const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').startsWith('file:') } catch { return false } })()
if (MAPPED) { Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'svc-test-key') }
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown; __gearAuthUser?: Row | null }
const BID = '11111111-2222-3333-4444-5555666677ff'

async function pp(): Promise<Handler> {
  const d = Deno as unknown as { serve: unknown }
  const orig = d.serve
  let captured: Handler | null = null
  const before = (g.__gearHandlers || []).length
  d.serve = (h: Handler) => { captured = h; return { finished: Promise.resolve(), shutdown: () => Promise.resolve() } }
  // vlastní instance modulu (?currency): pp_charges_flow_test ve stejném procesu si handler drží sám
  try { await import('../process-payment/index.ts?currency') } finally { d.serve = orig }
  const h = captured || (g.__gearHandlers || [])[before]
  if (!h) throw new Error('process-payment handler se nezaregistroval')
  return h
}

Deno.test({ name: 'currency flow: předchozí doplatek v HUF se při nové úpravě nezapíše jako Kč, nová úprava jde v CZK', ignore: !MAPPED, fn: async () => {
  const chg = JSON.stringify({ total_price: 1500, end_date: '2026-12-12', _base: { s: '2026-12-10', e: '2026-12-11', t: '10:00', p: 1000 } })
  const prev: Row = { id: 'pi_huf', status: 'succeeded', amount: 50000, amount_received: 50000, currency: 'huf', created: Math.floor(Date.now() / 1000) - 60,
    metadata: { type: 'extension', booking_id: BID, chg, attempt_id: 'att-12345678', chg_hash: 'abcd' }, latest_charge: { amount: 50000, amount_refunded: 0 } }
  const bk: Row = { id: BID, user_id: 'u1', status: 'reserved', payment_status: 'paid', booking_source: 'app', booking_kind: 'moto', moto_id: 'm1',
    trailer_moto_id: null, total_price: 1000, card_rounding: 0, discount_amount: 0, extras_price: 0, delivery_fee: 0, loyalty_discount_amount: 0,
    start_date: '2026-12-10', end_date: '2026-12-11', pickup_time: '10:00:00', pickup_method: 'branch', pickup_address: null, return_method: 'branch',
    return_address: null, stripe_payment_intent_id: 'pi_huf', modification_history: [], updated_at: '2026-11-01T00:00:00Z', motorcycles: { is_trailer: false } }
  const db = new LooseDb({ bookings: [bk], booking_discounts: [], vouchers: [], promo_codes: [], feature_flags: [], debug_log: [], shop_orders: [],
    profiles: [{ id: 'u1', stripe_customer_id: 'cus_1', email: 'j@x.cz' }] })
  db.rpcs.check_moto_availability = () => ({ data: true, error: null })
  g.__gearFakeDb = db
  g.__gearAuthUser = { id: 'u1', email: 'j@x.cz' }
  const h = await pp()
  const s = stripe as unknown as { paymentIntents: Record<string, unknown>; customers: Record<string, unknown>; ephemeralKeys: Record<string, unknown> }
  const keep = { pi: { ...s.paymentIntents }, cu: { ...s.customers }, ek: { ...s.ephemeralKeys } }
  const created: Row[] = []
  s.paymentIntents.retrieve = () => Promise.resolve({ ...prev })
  s.paymentIntents.update = () => Promise.resolve({})
  s.paymentIntents.cancel = () => Promise.resolve({ ...prev })
  s.paymentIntents.create = (p: Row) => { created.push(p); return Promise.resolve({ id: 'pi_new', client_secret: 'cs', status: 'requires_payment_method', amount: p.amount, currency: p.currency, metadata: p.metadata }) }
  s.customers.create = () => Promise.reject(new Error('žádné živé Stripe'))
  s.ephemeralKeys.create = () => Promise.resolve({ secret: 'ek' })
  const f = stubFetch(() => new Response('{}', { status: 200 }))
  try {
    const res = await h(new Request('http://x/pp', { method: 'POST', headers: { Authorization: 'Bearer eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl' },
      body: JSON.stringify({ type: 'extension', booking_id: BID, amount: 200, mode: 'intent', card_min: true,
        change: { total_price: 1200, start_date: '2026-12-09', _base: { s: '2026-12-10', e: '2026-12-11', t: '10:00', p: 1000 } } }) }))
    const json = await res.json()
    const got = [res.status, json.success, created.length, created[0]?.amount, created[0]?.currency, bk.total_price, bk.end_date]
    if (JSON.stringify(got) !== JSON.stringify([200, true, 1, 20000, 'czk', 1000, '2026-12-11'])) throw new Error(`čekáno nová platba 200 Kč v CZK a rezervace beze změny, přišlo ${JSON.stringify(got)} ${JSON.stringify(json)}`)
  } finally { Object.assign(s.paymentIntents, keep.pi); Object.assign(s.customers, keep.cu); Object.assign(s.ephemeralKeys, keep.ek); f.restore(); g.__gearAuthUser = null }
} })
