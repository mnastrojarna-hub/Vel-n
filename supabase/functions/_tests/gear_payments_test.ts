// ===== _tests/gear_payments_test.ts =====
// EDGE-B (2026-10-23) výpůjčka JEN výbavy: hosted Checkout (název položky, návrat na
// /pujceni-obleceni), doplatky úprav jen přes serverový dry-run (doklady po zaplacení:
// gear_paid_docs_test.ts). Motorka beze změny (regrese).
import { bookingKindForEdit, gearBookingLabel, gearChangeBlock, gearCheckoutUrls, GEAR_DRY_TXT, isGearRow, loadBookingKind, loadIsGear } from '../process-payment/gear-checkout.ts'
import { handleWebBookingCheckout } from '../process-payment/payment-flows.ts'
import { stripe, PRODUCT_NAMES } from '../process-payment/stripe-customer.ts'
import { FakeDb } from './gear-fake-supabase.ts'
import { LooseDb, stubFetch } from './gear-fake.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, unknown>
const BID = '11111111-2222-3333-4444-555566667777'

Deno.test('gear checkout: název položky v 8 jazycích, neznámý jazyk = čeština, nikdy „motork…“', () => {
  eq(gearBookingLabel('cs'), 'MotoGo24 — Půjčení výbavy')
  eq(gearBookingLabel('xx'), 'MotoGo24 — Půjčení výbavy')
  eq(gearBookingLabel(null), 'MotoGo24 — Půjčení výbavy')
  const all = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'].map((l) => gearBookingLabel(l))
  eq(new Set(all).size, 8, 'každý jazyk vlastní text')
  const LANGS = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']
  LANGS.forEach((l, i) => ok(all[i].startsWith('MotoGo24 — ') && all[i] !== PRODUCT_NAMES.booking && !/motork|motorcycle rental/i.test(all[i]), `${l}: ne „Pronájem motorky“`))
})

Deno.test('gear checkout: návrat na /pujceni-obleceni (úspěch s booking_id + session, zrušení resume + payfail), lang jen mimo cs/en', () => {
  const cs = gearCheckoutUrls('https://www.motogo24.cz', BID, 'cs')
  eq(cs.success, `https://www.motogo24.cz/pujceni-obleceni?booking_id=${BID}&session_id={CHECKOUT_SESSION_ID}`)
  eq(cs.cancel, `https://www.motogo24.cz/pujceni-obleceni?resume=${BID}&payfail=1`)
  const de = gearCheckoutUrls('https://motogo24.com', BID, 'de')
  eq(de.success, `https://motogo24.com/pujceni-obleceni?booking_id=${BID}&session_id={CHECKOUT_SESSION_ID}&lang=de`)
  eq(de.cancel, `https://motogo24.com/pujceni-obleceni?resume=${BID}&payfail=1&lang=de`)
  eq(gearCheckoutUrls('https://motogo24.com', BID, 'en').cancel, `https://motogo24.com/pujceni-obleceni?resume=${BID}&payfail=1`)
})

Deno.test('gear checkout: isGearRow jen booking_kind=gear (moto_id NULL samo nestačí); loadIsGear tolerantní', async () => {
  ok(isGearRow({ booking_kind: 'gear' })); ok(!isGearRow({ booking_kind: 'moto', moto_id: null })); ok(!isGearRow({ moto_id: null })); ok(!isGearRow(null))
  const d = new FakeDb({ bookings: [{ id: 'g1', booking_kind: 'gear' }, { id: 'm1', booking_kind: 'moto' }] })
  eq(await loadIsGear(d, 'g1'), true); eq(await loadIsGear(d, 'm1'), false); eq(await loadIsGear(d, 'nope'), false); eq(await loadIsGear(d, null), false)
  eq(await loadBookingKind(d, 'g1'), 'gear'); eq(await loadBookingKind(d, 'm1'), 'moto')
  d.missingCols.add('booking_kind') // SQL ještě nenasazené → motorka, žádná výjimka
  eq(await loadIsGear(d, 'g1'), false)
  eq(await loadBookingKind(d, 'g1'), 'moto', 'chybějící sloupec (42703) = motorka')
  const down = new LooseDb({ bookings: [{ id: 'g1', booking_kind: 'gear' }] })
  down.failSelect = () => ({ code: '57014', message: 'canceling statement due to statement timeout' })
  eq(await loadBookingKind(down, 'g1'), null, 'výpadek DB = null → doplatek úpravy fail closed (validation_unavailable)')
  eq(await loadIsGear(down, 'g1'), false)
  // doplatek úpravy: řádek s motorkou = motorka BEZ dotazu → výpadek druhého čtení motorku neodmítne
  const live = new LooseDb({ bookings: [{ id: 'g1', booking_kind: 'gear' }] })
  eq(await bookingKindForEdit(down, { moto_id: 'm1' }, 'g1'), 'moto')
  eq(await bookingKindForEdit(live, { moto_id: 'm1' }, 'g1'), 'moto')
  eq(live.callsOf('select', 'bookings').length, 0, 'bookingKindForEdit s motorkou nečte')
  eq(await bookingKindForEdit(down, null, 'g1'), 'moto', 'nenačtený řádek (už dryErr) → beze změny')
  eq(await bookingKindForEdit(down, { moto_id: null }, 'g1'), null, 'bez motorky + výpadek → fail closed')
  eq(await bookingKindForEdit(live, { moto_id: null }, 'g1'), 'gear')
  eq(live.callsOf('select', 'bookings').length, 1)
})

Deno.test('gear doplatek: jen termín (p_new_*) projde k dry-runu; motorka / výbava / app formát → kód + text bez kontaktů', () => {
  eq(gearChangeBlock({ p_new_end: '2026-11-20', _base: { e: '2026-11-18' } }), null)
  eq(gearChangeBlock({ p_new_start: '2026-11-10', p_new_end: '2026-11-12', p_new_moto_id: null }), null)
  eq(gearChangeBlock({ p_new_end: '2026-11-20', p_new_moto_id: 'm2' }), 'gear_no_moto')
  eq(gearChangeBlock({ _swap: { m: 'm2', d: '2026-11-11' } }), 'gear_no_moto')
  eq(gearChangeBlock({ _gear: { sizes: { helmet: 'L' } } }), 'gear_sizes_free')
  eq(gearChangeBlock({ total_price: 2000, end_date: '2026-11-20' }), 'gear_app_format')
  eq(gearChangeBlock({ moto_id: 'm2', total_price: 2000 }), 'gear_no_moto')
  eq(gearChangeBlock(null), 'gear_app_format')
  // Smíšený payload: `p_new_*` + DB sloupce (webhook by je zapsal mimo nacenění) → odmítnout.
  for (const col of ['start_date', 'end_date', 'discount_amount', 'delivery_fee', 'extras_price', 'loyalty_discount_amount', 'late_pickup_discount_amount', 'total_price', 'pickup_time', 'moto_id']) {
    eq(gearChangeBlock({ p_new_end: '2026-11-20', [col]: col === 'moto_id' ? null : 0 }), 'gear_app_format', col)
  }
  // Payload webu (_submitChange / prodloužení) dál projde.
  eq(gearChangeBlock({ p_new_start: '2026-11-10', p_new_end: '2026-11-20', p_new_pickup_time: '10:00', new_total: 2000,
    _base: { s: '2026-11-10', e: '2026-11-18', t: '10:00', p: 1200, l: 0 }, _time_update: { return_time: '18:00' }, _pb: 1 }), null)
  eq(gearChangeBlock({ _base: { s: '2026-11-10' }, new_total: 2000 }), 'gear_app_format')
  for (const [k, t] of Object.entries(GEAR_DRY_TXT)) {
    ok(/nic jsme nestrhli/i.test(t), k)
    ok(!/@|\+420|info@|telefon/i.test(t), `${k}: žádný kontakt (D5)`)
  }
  for (const k of ['out_of_stock', 'branch_closed', 'gear_no_moto']) ok(GEAR_DRY_TXT[k], k)
})

// ── handleWebBookingCheckout (Stripe a fetch nahrazené) ───────────────────────
type StripeLike = {
  checkout: { sessions: { create: (p: Row) => Promise<Row>; retrieve: (id: string) => Promise<Row> } }
  customers: { list: (p: Row) => Promise<Row>; create: (p: Row) => Promise<Row> }
}
function patchStripe() {
  const st = stripe as unknown as StripeLike
  const orig = { create: st.checkout.sessions.create, list: st.customers.list, ccreate: st.customers.create }
  const sessions: Row[] = []
  st.checkout.sessions.create = (p: Row) => { sessions.push(p); return Promise.resolve({ id: 'cs_test_1', url: 'https://checkout.stripe.test/cs_test_1', payment_intent: 'pi_test_1' }) }
  st.customers.list = () => Promise.resolve({ data: [] })
  st.customers.create = () => Promise.resolve({ id: 'cus_new' })
  return { sessions, restore: () => { st.checkout.sessions.create = orig.create; st.customers.list = orig.list; st.customers.create = orig.ccreate } }
}
function webBooking(over: Row = {}) {
  return {
    id: BID, booking_source: 'web', payment_status: 'unpaid', status: 'pending', booking_kind: 'gear', moto_id: null,
    total_price: 1470, discount_amount: 0, start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00',
    created_at: new Date().toISOString(), language: 'cs', user_id: 'u1', stripe_session_id: null, voucher_id: null, promo_code_id: null,
    gear_per_day: 490, gear_lines: [{ key: 'set_rider', kind: 'set', label: 'Komplet bez bot', price_per_day: 490, total: 1470 }],
    profiles: { full_name: 'Jana Nováková', email: 'jana@example.com', phone: '+420777000111', stripe_customer_id: 'cus_1' }, ...over,
  }
}
async function runCheckout(b: Row, extra: Partial<Record<string, Row[]>> = {}, locale = 'cs') {
  const db = new LooseDb({ bookings: [b], booking_discounts: [], vouchers: [], promo_codes: [], debug_log: [], profiles: [], ...extra })
  const st = patchStripe()
  const f = stubFetch(() => new Response(JSON.stringify({ success: true }), { status: 200 }))
  try {
    const res = await handleWebBookingCheckout({ booking_id: BID, amount: Number(b.total_price) || 0, type: 'booking', source: 'web', mode: 'checkout', origin: 'https://www.motogo24.cz', locale } as never, db as never)
    return { res, json: await res.json(), sessions: st.sessions, db, fetches: f.calls }
  } finally { st.restore(); f.restore() }
}

Deno.test('handleWebBookingCheckout: gear rezervace — „Půjčení výbavy“, návrat na /pujceni-obleceni, ZF se generuje', async () => {
  const r = await runCheckout(webBooking())
  eq(r.json.checkout_url, 'https://checkout.stripe.test/cs_test_1')
  const s = r.sessions[0] as Row
  eq(s.mode, 'payment')
  const li = (s.line_items as Row[])[0] as { price_data: { unit_amount: number; product_data: { name: string; description: string } } }
  eq(li.price_data.product_data.name, 'MotoGo24 — Půjčení výbavy')
  eq(li.price_data.unit_amount, 147000)
  eq(li.price_data.product_data.description, 'Rezervace #66667777')
  eq(s.success_url, `https://www.motogo24.cz/pujceni-obleceni?booking_id=${BID}&session_id={CHECKOUT_SESSION_ID}`)
  eq(s.cancel_url, `https://www.motogo24.cz/pujceni-obleceni?resume=${BID}&payfail=1`)
  eq((s.metadata as Row).type, 'booking')
  eq((s.payment_intent_data as Row).metadata, s.metadata, 'metadata i na PaymentIntentu')
  ok(r.fetches.some((c) => c.url.endsWith('/functions/v1/generate-invoice') && c.body?.type === 'proforma'), 'ZF')
})

Deno.test('handleWebBookingCheckout: gear zdarma (poukaz na celou cenu) — ověření karty, návrat na /pujceni-obleceni', async () => {
  const b = webBooking({ total_price: 0, discount_amount: 1470, voucher_id: 'v1' })
  const r = await runCheckout(b, { vouchers: [{ id: 'v1', amount: 2000, status: 'redeemed', booking_id: BID }] }, 'fr')
  eq(r.json.free, true, JSON.stringify(r.json))
  const s = r.sessions[0] as Row
  eq(s.mode, 'setup')
  eq(s.success_url, `https://www.motogo24.cz/pujceni-obleceni?booking_id=${BID}&session_id={CHECKOUT_SESSION_ID}&lang=fr`)
  eq(s.cancel_url, `https://www.motogo24.cz/pujceni-obleceni?resume=${BID}&payfail=1&lang=fr`)
})

Deno.test('handleWebBookingCheckout: motorka beze změny (Pronájem motorky, /potvrzeni, /rezervace?resume)', async () => {
  const r = await runCheckout(webBooking({ booking_kind: 'moto', moto_id: 'm1', gear_lines: null, gear_per_day: null }))
  const s = r.sessions[0] as Row
  const li = (s.line_items as Row[])[0] as { price_data: { product_data: { name: string } } }
  eq(li.price_data.product_data.name, 'MotoGo24 — Pronájem motorky')
  eq(s.success_url, 'https://www.motogo24.cz/potvrzeni?session_id={CHECKOUT_SESSION_ID}')
  eq(s.cancel_url, `https://www.motogo24.cz/rezervace?resume=${BID}&payfail=1`)
})

Deno.test('handleWebBookingCheckout: motorka zdarma beze změny (setup, /potvrzeni, /rezervace?resume, lang)', async () => {
  const b = webBooking({ booking_kind: 'moto', moto_id: 'm1', gear_lines: null, gear_per_day: null, total_price: 0, discount_amount: 3000, voucher_id: 'v1' })
  const r = await runCheckout(b, { vouchers: [{ id: 'v1', amount: 5000 }] }, 'de')
  eq(r.json.free, true, JSON.stringify(r.json))
  const s = r.sessions[0] as Row
  eq(s.mode, 'setup')
  eq(s.success_url, 'https://www.motogo24.cz/potvrzeni?session_id={CHECKOUT_SESSION_ID}&lang=de')
  eq(s.cancel_url, `https://www.motogo24.cz/rezervace?resume=${BID}&payfail=1&lang=de`)
  ok(r.fetches.some((c) => c.url.endsWith('/functions/v1/generate-invoice') && c.body?.type === 'proforma'), 'ZF')
})
