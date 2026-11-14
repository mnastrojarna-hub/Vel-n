// ===== _tests/pp_web_checkout_flow_test.ts =====
// Oprava i1 (2026-11-05), process-payment web flows (payment-flows.ts) nad falešným Stripe + in-memory DB
// (import mapa storno-flow-map.json, spouští storno_hotfix_test.ts):
//  • web rezervace s cenou 0 (nedoložená 100% sleva) a částkou 15 Kč z klienta → free_unverified, žádná session
//    (dřív rozhodla klientská částka: zaplaceno 15 Kč, doklady 0),
//  • web poukaz: celkem objednávky = hodnota poukazu + tisk ze SERVERU (1000 + 180), klientská `amount` 5 Kč
//    nevede na below_minimum ani nepřepíše shop_orders.total.
// deno-lint-ignore-file no-explicit-any
import { BID, FN, fresh, rows, world } from './storno-harness.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
const pf: any = MAPPED ? await import(`${FN}process-payment/payment-flows.ts`) : null
const db = () => (globalThis as any).__STORNO_DB

Deno.test({ name: 'i1 web rezervace: cena 0 bez doložené slevy + částka 15 Kč z klienta → free_unverified, žádná Checkout Session', ignore: !MAPPED, fn: async () => {
  fresh(10, { booking: { booking_source: 'web', payment_status: 'unpaid', status: 'pending', total_price: 0, discount_amount: 0, promo_code_id: null, voucher_id: null,
    stripe_payment_intent_id: null, created_at: new Date().toISOString(), language: 'cs' } })
  for (const t of ['booking_discounts', 'vouchers', 'promo_codes']) db().rows(t)
  const res: Response = await pf.handleWebBookingCheckout({ booking_id: BID, amount: 15, type: 'booking', source: 'web', mode: 'checkout',
    origin: 'https://www.motogo24.cz', locale: 'cs' }, db())
  const json = await res.json()
  if (res.status !== 400 || json.code !== 'free_unverified') throw new Error(`čekáno 400 free_unverified, přišlo ${res.status} ${JSON.stringify(json)}`)
  if (world().sessions.length) throw new Error(`session se neměla vytvořit: ${JSON.stringify(world().sessions[0]?.line_items)}`)
} })

Deno.test({ name: 'i1 web poukaz: celkem = hodnota + tisk ze serveru (1 180), klientská amount 5 Kč nic nepřepíše ani neodmítne', ignore: !MAPPED, fn: async () => {
  fresh(10)
  for (const t of ['shop_orders', 'shop_order_items', 'debug_log']) db().rows(t)
  const res: Response = await pf.handleWebShopCheckout({ amount: 5, voucher_amount: 1000, is_print: true, customer_email: 'kupujici@example.com', customer_name: 'Kup Ující',
    type: 'shop', source: 'web', mode: 'checkout', origin: 'https://www.motogo24.cz', locale: 'cs' })
  const json = await res.json()
  if (res.status !== 200 || !json.checkout_url) throw new Error(`čekáno 200 + checkout_url, přišlo ${res.status} ${JSON.stringify(json)}`)
  const so = rows('shop_orders')[0]
  if (!so || Number(so.total) !== 1180 || Number(so.subtotal) !== 1000) throw new Error(`shop_orders ${JSON.stringify(so)}`)
  const li = (world().sessions[0]?.line_items || []).map((x: any) => x.price_data?.unit_amount)
  if (JSON.stringify(li) !== JSON.stringify([100000, 18000])) throw new Error(`položky ${JSON.stringify(li)}`)
} })
