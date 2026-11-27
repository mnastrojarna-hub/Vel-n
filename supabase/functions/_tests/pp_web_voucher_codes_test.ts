// ===== _tests/pp_web_voucher_codes_test.ts =====
// Web 2026-11-27: slevové kódy u nákupu dárkového poukazu (process-payment handleWebShopCheckout, voucher
// větev) nad falešným Stripe + in-memory DB (import mapa storno-flow-map.json):
//  • platný kód → cena a sleva ze serveru (RPC quote_web_voucher_order), objednávka nese discount,
//    discount_codes a promo_code_id; Checkout má jednu položku s konečnou cenou a kódem v názvu,
//  • neplatný kód → 409 s hláškou serveru, žádná objednávka ani Checkout Session,
//  • výpadek ověření kódů → 503, nic se nezaloží,
//  • bez kódů se RPC nevolá a objednávka je beze změny (hodnota + tisk, dvě položky).
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/pp_web_voucher_codes_test.ts
// deno-lint-ignore-file no-explicit-any
import { FN, fresh, rows, world } from './storno-harness.ts'

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
const pf: any = MAPPED ? await import(`${FN}process-payment/payment-flows.ts`) : null
const db = () => (globalThis as any).__STORNO_DB

const PROMO = '3a7ebbf2-c547-403d-8a8a-431ebcc2cabf'
const body = (extra: Record<string, unknown> = {}) => ({ amount: 1062, voucher_amount: 1000, is_print: true, customer_email: 'kupujici@example.com',
  customer_name: 'Kup Ující', type: 'shop', source: 'web', mode: 'checkout', origin: 'https://www.motogo24.cz', locale: 'cs', ...extra })
function setup() {
  fresh(10)
  for (const t of ['shop_orders', 'shop_order_items', 'debug_log']) db().rows(t)
  const calls: any[] = []
  db().rpcs['quote_web_voucher_order'] = (a: any) => {
    calls.push(a)
    if ((a.p_codes || []).includes('NOPE')) return { data: { success: false, error: 'bad_code', code: 'NOPE', message: 'Kód neexistuje nebo už neplatí.' }, error: null }
    if ((a.p_codes || []).includes('DOWN')) return { data: null, error: { message: 'connection lost' } }
    return { data: { success: true, amount: 1000, print_fee: 180, subtotal: 1180, discount: 118, total: 1062, promo_code_id: PROMO,
      discount_codes: [{ kind: 'promo_code', code: 'PCT10', promo_code_id: PROMO, discount_type: 'percent', value: 10, amount: 118 }] }, error: null }
  }
  return calls
}

Deno.test({ name: 'poukaz + slevový kód: sleva a cena ze serveru, objednávka nese kódy, jedna položka s konečnou cenou', ignore: !MAPPED, fn: async () => {
  const calls = setup()
  const res: Response = await pf.handleWebShopCheckout(body({ codes: [' pct10 '] }))
  const json = await res.json()
  if (res.status !== 200 || !json.checkout_url) throw new Error(`čekáno 200 + checkout_url, přišlo ${res.status} ${JSON.stringify(json)}`)
  if (calls.length !== 1 || calls[0].p_amount !== 1000 || calls[0].p_print !== true) throw new Error(`RPC volání ${JSON.stringify(calls)}`)
  const so = rows('shop_orders')[0]
  if (!so || Number(so.total) !== 1062 || Number(so.discount) !== 118 || Number(so.subtotal) !== 1000 || so.promo_code_id !== PROMO
      || !Array.isArray(so.discount_codes) || so.discount_codes[0]?.code !== 'PCT10') throw new Error(`shop_orders ${JSON.stringify(so)}`)
  const items = rows('shop_order_items').map((x: any) => [x.product_name, Number(x.total_price)])
  if (JSON.stringify(items) !== JSON.stringify([['Dárkový poukaz', 1000], ['Tisk a poštovné', 180]])) throw new Error(`položky objednávky ${JSON.stringify(items)}`)
  const li = world().sessions[0]?.line_items || []
  if (li.length !== 1 || li[0].price_data?.unit_amount !== 106200 || !String(li[0].price_data?.product_data?.name).includes('PCT10')) throw new Error(`Checkout ${JSON.stringify(li)}`)
} })

Deno.test({ name: 'poukaz + neplatný kód: 409 s hláškou serveru, nic se nezaloží', ignore: !MAPPED, fn: async () => {
  setup()
  const res: Response = await pf.handleWebShopCheckout(body({ codes: ['NOPE'] }))
  const json = await res.json()
  if (res.status !== 409 || json.error !== 'Kód neexistuje nebo už neplatí.' || json.discount_code !== 'NOPE') throw new Error(`přišlo ${res.status} ${JSON.stringify(json)}`)
  if (rows('shop_orders').length || world().sessions.length) throw new Error('objednávka ani session se neměly založit')
} })

Deno.test({ name: 'poukaz + výpadek ověření kódů: 503, nic se nezaloží', ignore: !MAPPED, fn: async () => {
  setup()
  const res: Response = await pf.handleWebShopCheckout(body({ codes: ['DOWN'] }))
  if (res.status !== 503) throw new Error(`čekáno 503, přišlo ${res.status}`)
  if (rows('shop_orders').length || world().sessions.length) throw new Error('objednávka ani session se neměly založit')
} })

Deno.test({ name: 'poukaz bez kódů: RPC se nevolá, objednávka a položky beze změny', ignore: !MAPPED, fn: async () => {
  const calls = setup()
  const res: Response = await pf.handleWebShopCheckout(body({ amount: 1180, codes: [] }))
  if (res.status !== 200) throw new Error(`čekáno 200, přišlo ${res.status}`)
  if (calls.length) throw new Error('RPC se nemělo volat')
  const so = rows('shop_orders')[0]
  if (Number(so.total) !== 1180 || Number(so.discount) !== 0 || 'discount_codes' in so) throw new Error(`shop_orders ${JSON.stringify(so)}`)
  const li = (world().sessions[0]?.line_items || []).map((x: any) => x.price_data?.unit_amount)
  if (JSON.stringify(li) !== JSON.stringify([100000, 18000])) throw new Error(`položky ${JSON.stringify(li)}`)
} })
