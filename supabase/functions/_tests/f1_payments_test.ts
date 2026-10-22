// ===== _tests/f1_payments_test.ts =====
// fix f1 (2026-10-22):
//  1) rezervace placená převodem / QR / hotově + nezapsaná zaplacená změna (doplatek vrácen) →
//     uložená platba se vymaže a storno jde ruční vratkou (ne no_op → 'refunded' bez peněz);
//  2) vrácená (zrušená + obnovená) platba rezervace neblokuje novou platbu (payment_in_progress);
//  3) storno / vratka obsluhy nevrací z doplatku změny, kterou ještě nikdo nezapsal;
//  5) e-mail zákazníkovi podle důvodu (zrušená rezervace ≠ „platí beze změny");
//  6/12) web: proč se rezervace nedá zaplatit (kódy) + rezervace zdarma se zbožím = platba za zboží;
//  10) Stripe položky webu v jazyce webu.
import { handlePaidChangeFailure, mailWhy, changeKindOf } from '../_shared/paid-change-failure.ts'
import { otherRefundableIntents, outsidePrice } from '../_shared/booking-intents.ts'
import { paidChangeCustomerMail } from '../_shared/paid-change-customer-mail.ts'
import { mainSource } from '../process-refund/other-intents.ts'
import { guardStoredIntent, findRecentLiveIntent, refundedOut } from '../process-payment/intent-guard.ts'
import { webBookingMiss, freeShopPlan } from '../process-payment/web-booking-guards.ts'
import { webLabels, fillLabel, shippingLabel } from '../process-payment/checkout-labels.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
type Row = Record<string, unknown>
const BID = '11111111-2222-4333-8444-555555555555'
const NOW = Date.UTC(2026, 9, 22, 12, 0, 0)
type Pi = { id: string; status: string; amount_received: number; created: number; metadata: Record<string, string> }
const pi = (id: string, h: number, created: number, md: Record<string, string> = { booking_id: BID, type: 'booking' }): Pi =>
  ({ id, status: 'succeeded', amount_received: h, created, metadata: md })

function fakeStripe(intents: Pi[], sessions: Record<string, Row> = {}) {
  const refunds: Record<string, Array<{ id: string; amount: number; status: string; metadata: Row }>> = {}
  const created: Row[] = []
  const left = (id: string) => (intents.find((x) => x.id === id)?.amount_received || 0) - (refunds[id] || []).reduce((s, r) => s + r.amount, 0)
  const stripe = {
    paymentIntents: {
      search: () => Promise.resolve({ data: intents.filter((x) => x.metadata.booking_id === BID && x.status === 'succeeded') }),
      retrieve: (id: string) => { const x = intents.find((p) => p.id === id); return x ? Promise.resolve(x) : Promise.reject(new Error('missing')) },
    },
    refunds: {
      list: (p: Row) => Promise.resolve({ data: refunds[String(p.payment_intent)] || [] }),
      create: (p: Row) => {
        const id = String(p.payment_intent)
        const amt = p.amount != null ? Number(p.amount) : left(id)
        if (amt <= 0 || amt > left(id)) return Promise.reject(new Error('charge_already_refunded'))
        const r = { id: `re_${created.length + 1}`, amount: amt, status: 'succeeded', metadata: (p.metadata || {}) as Row }
        ;(refunds[id] ||= []).push(r); created.push(p)
        return Promise.resolve(r)
      },
    },
    checkout: { sessions: { retrieve: (id: string) => sessions[id] ? Promise.resolve(sessions[id]) : Promise.reject(new Error('missing')) } },
  }
  return { stripe, created, refunds, left }
}
async function withFetch<T>(fn: (mails: Row[]) => Promise<T>): Promise<T> {
  const mails: Row[] = []
  const orig = globalThis.fetch
  globalThis.fetch = ((url: string, init?: RequestInit) => {
    if (String(url).includes('/send-email')) mails.push(JSON.parse(String(init?.body || '{}')))
    return Promise.resolve(new Response('{}'))
  }) as typeof fetch
  try { return await fn(mails) } finally { globalThis.fetch = orig }
}
const bk = (o: Row = {}): Row => ({ id: BID, user_id: 'u1', status: 'reserved', payment_status: 'paid', payment_method: null,
  total_price: 3000, modification_history: [], stripe_payment_intent_id: 'pi_x', stripe_session_id: null, ...o })

// ── 1) převod / QR + nezapsaná změna → storno ruční vratkou ─────────────────────────────
Deno.test('f1/1: rezervace bez platby kartou + vrácený doplatek nezapsané změny → uložená platba vymazána, storno = ruční vratka', async () => {
  const d = new FakeDb({ bookings: [bk()], profiles: [], debug_log: [] })
  const f = fakeStripe([pi('pi_x', 1500, 200, { booking_id: BID, type: 'extension', chg_hash: 'abc' })])
  const a = { bookingId: BID, payRef: 'pi_x', paidCzk: 15, code: 'change_failed', reason: 'new_moto_unavailable', via: 'test', stripe: f.stripe }
  eq(await withFetch(() => handlePaidChangeFailure(d, a as never)), 'auto')
  eq(f.left('pi_x'), 0)
  const b = d.rows('bookings')[0]
  eq(b.stripe_payment_intent_id, null, 'uložená platba (vrácený doplatek) vymazána → process-refund jde ruční vratkou')
  eq(b.payment_status, 'paid'); eq(b.total_price, 3000)
  eq((d.rows('debug_log')[0].response_data as Row).stored_payment_cleared, true)

  // pojistka v process-refund, i kdyby uložená platba zůstala (starší záznam): mimo cenu → ruční vratka, ne no_op
  b.stripe_payment_intent_id = 'pi_x'
  const src = await mainSource(f.stripe as never, d, { bookingId: BID, storedPiId: 'pi_x', storedPi: await f.stripe.paymentIntents.retrieve('pi_x'),
    storedRefunds: f.refunds.pi_x, chargedHaleru: 1500, refundableHaleru: 0, isCustomer: false, amount: 3000, nowMs: NOW } as never)
  eq(src, { kind: 'manual', outside: 'failed' })
  // jen vratky mimo cenu (bez záznamu paid_change_failed) → 'returned'
  const d2 = new FakeDb({ bookings: [bk()], debug_log: [] })
  eq(await outsidePrice(d2, BID, { id: 'pi_y', metadata: { booking_id: BID, type: 'booking' } },
    { refunds: [{ amount: 1500, status: 'succeeded', metadata: { mg_source: 'late_payment' } }], errAs: false }), 'returned')
  eq(await outsidePrice(d2, BID, { id: 'pi_y', metadata: { booking_id: BID, type: 'booking' } },
    { refunds: [{ amount: 1500, status: 'succeeded', metadata: { mg_source: 'process-refund' } }], errAs: false }), null)
})

Deno.test('f1/1: rezervace placená kartou → po vrácení doplatku zpět původní platba (beze změny), storno z ní', async () => {
  const d = new FakeDb({ bookings: [bk({ stripe_payment_intent_id: 'pi_x' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), pi('pi_x', 1500, 200, { booking_id: BID, type: 'extension', chg_hash: 'abc' })])
  await withFetch(() => handlePaidChangeFailure(d, { bookingId: BID, payRef: 'pi_x', paidCzk: 15, code: 'change_failed',
    reason: 'new_moto_unavailable', via: 'test', stripe: f.stripe } as never))
  eq(d.rows('bookings')[0].stripe_payment_intent_id, 'pi_orig')
  const src = await mainSource(f.stripe as never, d, { bookingId: BID, storedPiId: 'pi_orig', storedPi: await f.stripe.paymentIntents.retrieve('pi_orig'),
    storedRefunds: [], chargedHaleru: 300000, refundableHaleru: 300000, isCustomer: false, amount: 3000, nowMs: NOW } as never)
  eq(src, { kind: 'stored' })
})

Deno.test('f1/1: web Checkout doplatku (cs_) bez jiné platby kartou → vymazána i session doplatku', async () => {
  const d = new FakeDb({ bookings: [bk({ stripe_payment_intent_id: 'pi_w', stripe_session_id: 'cs_w' })], debug_log: [] })
  const f = fakeStripe([pi('pi_w', 1500, 200, {})], { cs_w: { payment_intent: 'pi_w', metadata: { booking_id: BID, type: 'extension' } } })
  eq(await withFetch(() => handlePaidChangeFailure(d, { bookingId: BID, payRef: 'pi_w', paidCzk: 15, code: 'change_failed',
    reason: 'new_moto_unavailable', via: 'test', stripe: f.stripe } as never)), 'auto')
  const b = d.rows('bookings')[0]
  eq(b.stripe_payment_intent_id, null); eq(b.stripe_session_id, null)
})

// ── 3) doplatek ještě nezapsané změny není zdroj vratky ─────────────────────────────────
Deno.test('f1/3: storno 100 % s uloženým doplatkem, který webhook ještě nezapsal → vratka z původní platby, doplatek nedotčen', async () => {
  const pend = pi('pi_e', 1500, NOW / 1000 - 30, { booking_id: BID, type: 'extension', chg_hash: 'h1' })
  const d = new FakeDb({ bookings: [bk({ stripe_payment_intent_id: 'pi_e' })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), pend])
  const src = await mainSource(f.stripe as never, d, { bookingId: BID, storedPiId: 'pi_e', storedPi: pend, storedRefunds: [],
    chargedHaleru: 1500, refundableHaleru: 1500, isCustomer: false, amount: 3000, nowMs: NOW } as never)
  eq(src, { kind: 'retarget', piId: 'pi_orig', refundableHaleru: 300000, outside: 'pending' })
  // zbytek storna ani vratka obsluhy ho nebere
  eq((await otherRefundableIntents(f.stripe as never, d, BID, 'pi_orig')).map((c) => c.id), [])
  // zákaznická vratka z appky z čekajícího doplatku → obsluha (nic automaticky)
  eq(await mainSource(f.stripe as never, d, { bookingId: BID, storedPiId: 'pi_e', storedPi: pend, storedRefunds: [],
    chargedHaleru: 1500, refundableHaleru: 1500, isCustomer: true, amount: 100, nowMs: NOW } as never), { kind: 'customer_staff' })
  // rezervace placená převodem + čekající doplatek → ruční vratka (ne z doplatku)
  const q = fakeStripe([pend])
  eq(await mainSource(q.stripe as never, d, { bookingId: BID, storedPiId: 'pi_e', storedPi: pend, storedRefunds: [],
    chargedHaleru: 1500, refundableHaleru: 1500, isCustomer: false, amount: 3000, nowMs: NOW } as never), { kind: 'manual', outside: 'pending' })
})

Deno.test('f1/3: zapsaný doplatek (applied_at / payment_ref v historii / starý bez značky) zůstává zdrojem vratky', async () => {
  const d = new FakeDb({ bookings: [bk({ modification_history: [{ type: 'edit', payment_ref: 'pi_h' }] })], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100),
    pi('pi_a', 1000, NOW / 1000 - 60, { booking_id: BID, type: 'extension', chg_hash: 'a', applied_at: '2026-10-22T11:59:00Z' }),
    pi('pi_h', 900, NOW / 1000 - 50, { booking_id: BID, type: 'extension', attempt_id: 'att-12345678' }),
    pi('pi_legacy', 800, NOW / 1000 - 40, { booking_id: BID, type: 'extension' }),
    pi('pi_old', 700, NOW / 1000 - 8 * 86400, { booking_id: BID, type: 'extension', chg_hash: 'o' }),
    pi('pi_new', 600, NOW / 1000 - 20, { booking_id: BID, type: 'extension', chg_hash: 'n' })])
  const c = await otherRefundableIntents(f.stripe as never, d, BID, 'pi_orig')
  ok(!c.some((x) => x.id === 'pi_new'), 'čekající doplatek vyřazen')
  eq(c.map((x) => x.id).sort(), ['pi_a', 'pi_h', 'pi_legacy', 'pi_old'])
})

// ── 2) vrácená platba rezervace neblokuje ───────────────────────────────────────────────
function guardStripe(p: Row) {
  return { paymentIntents: {
    retrieve: (_id: string, o?: Row) => Promise.resolve({ ...p, latest_charge: (o as { expand?: string[] } | undefined)?.expand ? p.latest_charge : 'ch_1' }),
    cancel: () => Promise.reject(new Error('no')),
    search: (q: Row) => Promise.resolve({ data: [{ ...p, latest_charge: (q.expand as string[] | undefined)?.length ? p.latest_charge : 'ch_1' }] }),
  } }
}
const G = (s: unknown, o: Row = {}) => guardStoredIntent(s as never, { storedPiId: 'pi_1', type: 'booking', refKey: 'booking_id', refId: 'b1',
  sheet: true, chargeCents: 300000, chg: null, ...o } as never)
Deno.test('f1/2: uložená platba rezervace zaplacená a celá vrácená (storno + obnovení) → nová platba smí', async () => {
  const base = { id: 'pi_1', status: 'succeeded', amount: 300000, amount_received: 300000, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1' } }
  eq((await G(guardStripe({ ...base, latest_charge: { amount: 300000, amount_refunded: 300000 } }))).action, 'proceed')
  eq((await G(guardStripe({ ...base, latest_charge: { amount: 300000, amount_refunded: 0 } }))).action, 'refuse')
  // částečně vrácená: jen u řádku, který na platbu čeká (unpaid)
  eq((await G(guardStripe({ ...base, latest_charge: { amount: 300000, amount_refunded: 150000 } }))).action, 'refuse')
  eq((await G(guardStripe({ ...base, latest_charge: { amount: 300000, amount_refunded: 150000 } }), { rowUnpaid: true })).action, 'proceed')
  // e-shop a SOS stejně; doplatek (extension) beze změny — hlídá paidChangeEligibility
  eq((await G(guardStripe({ ...base, metadata: { type: 'shop', order_id: 'b1' }, latest_charge: { amount: 300000, amount_refunded: 300000 } }),
    { type: 'shop', refKey: 'order_id' })).action, 'proceed')
  eq((await G(guardStripe({ ...base, metadata: { type: 'extension', booking_id: 'b1' }, latest_charge: { amount: 300000, amount_refunded: 300000 } }),
    { type: 'extension' })).action, 'paid_extension')
  ok(!refundedOut({ status: 'succeeded', amount_received: 100, latest_charge: 'ch_1' }), 'nerozbalený latest_charge → nevíme → jako dosud')
})
Deno.test('f1/2: uložená karta — nedávná vrácená platba neblokuje (findRecentLiveIntent)', async () => {
  const base = { id: 'pi_9', status: 'succeeded', amount: 300000, amount_received: 300000, metadata: { type: 'booking', booking_id: BID } }
  eq(await findRecentLiveIntent(guardStripe({ ...base, latest_charge: { amount: 300000, amount_refunded: 300000 } }) as never,
    { refKey: 'booking_id', refId: BID, type: 'booking' }), null)
  eq(await findRecentLiveIntent(guardStripe({ ...base, latest_charge: { amount: 300000, amount_refunded: 0 } }) as never,
    { refKey: 'booking_id', refId: BID, type: 'booking' }), { piId: 'pi_9', status: 'succeeded' })
})

// ── 5) e-mail zákazníkovi podle důvodu ──────────────────────────────────────────────────
Deno.test('f1/5: e-mail — zrušená rezervace: bez „platí beze změny" a bez „zkuste znovu", odkaz na seznam', () => {
  eq(mailWhy('booking_cancelled'), 'closed'); eq(mailWhy('booking_completed'), 'closed'); eq(mailWhy('not_paid'), 'closed')
  eq(mailWhy('new_moto_unavailable'), 'taken'); eq(mailWhy('swap_date_out_of_range'), 'date'); eq(mailWhy('license_insufficient'), 'license')
  eq(mailWhy('db_refused'), 'failed')
  const m = paidChangeCustomerMail({ lang: 'cs', bookingId: BID, amount: 20.5, taken: false, staff: false, why: 'closed', site: 'https://www.motogo24.cz' })
  ok(!m.html.includes('platí beze změny') && !m.html.includes('zkusit znovu'), 'zrušená: nic falešného')
  ok(m.html.includes('skončila nebo byla zrušená') && m.html.includes('20,50 Kč'), 'důvod + částka 2 desetinná místa')
  ok(m.html.includes('href="https://www.motogo24.cz/upravit-rezervaci"') && m.html.includes('Moje rezervace'), 'odkaz na seznam rezervací')
  for (const lang of ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk']) {
    for (const why of ['closed', 'date', 'license'] as const) {
      const x = paidChangeCustomerMail({ lang, bookingId: BID, amount: 15, taken: false, staff: true, why })
      ok(x.lang === lang && !/\{\w+\}|undefined/.test(x.html + x.subject), `${lang}/${why}: doplněné texty`)
      ok(!/info@|\+420|774/.test(x.html), `${lang}/${why}: bez kontaktů`)
    }
  }
})
Deno.test('f1/5: e-mail — den výměny uplynul / řidičák: konkrétní důvod; výměna → odkaz na záložku Výměna', () => {
  const d = paidChangeCustomerMail({ lang: 'cs', bookingId: BID, amount: 15, taken: false, staff: false, why: 'date', kind: 'swap', site: 'https://x.cz' })
  ok(d.html.includes('den výměny mezitím uplynul') && d.html.includes('platí beze změny'), 'date')
  ok(!d.html.includes('rezervace mezitím změnila'), 'ne obecný důvod')
  ok(d.html.includes('edit_booking=' + BID + '&amp;edit_tab=swap'), 'záložka Výměna')
  const t = paidChangeCustomerMail({ lang: 'cs', bookingId: BID, amount: 15, taken: true, staff: false, kind: 'swap', site: 'https://x.cz' })
  ok(t.html.includes('&amp;edit_tab=swap'), 'obsazená motorka u výměny → záložka Výměna')
  const e = paidChangeCustomerMail({ lang: 'cs', bookingId: BID, amount: 15, taken: true, staff: false, kind: 'edit', site: 'https://x.cz' })
  ok(!e.html.includes('edit_tab'), 'úprava → výchozí záložka')
  const l = paidChangeCustomerMail({ lang: 'en', bookingId: BID, amount: 15, taken: false, staff: false, why: 'license' })
  ok(l.html.includes('driving licence') && l.html.includes('stays unchanged'), 'license EN')
  eq(changeKindOf('{"_swap":{"m":"x"}}'), 'swap'); eq(changeKindOf('{"p_new_end":"2026-11-13"}'), 'edit'); eq(changeKindOf(null), null)
})
Deno.test('f1/5: handlePaidChangeFailure — zrušená rezervace dostane e-mail bez „platí beze změny"', async () => {
  const d = new FakeDb({ bookings: [{ ...bk({ stripe_payment_intent_id: 'pi_orig' }), language: 'cs' }], profiles: [{ id: 'u1', email: 'jan@example.com' }], debug_log: [] })
  const f = fakeStripe([pi('pi_orig', 300000, 100), pi('pi_c', 1500, 200, { booking_id: BID, type: 'extension' })])
  await withFetch(async (mails) => {
    eq(await handlePaidChangeFailure(d, { bookingId: BID, payRef: 'pi_c', paidCzk: 15, code: 'change_failed', reason: 'booking_cancelled',
      via: 'test', stripe: f.stripe, kind: 'swap' } as never), 'auto')
    const c = mails.filter((m) => m.to === 'jan@example.com')
    eq(c.length, 1)
    const h = String(c[0].raw_html)
    ok(!h.includes('platí beze změny') && !h.includes('zkusit znovu') && h.includes('zrušená'), h)
    ok(h.includes('/upravit-rezervaci"') && !h.includes('edit_tab'), 'zrušená → seznam, ne záložka')
  })
})

// ── 6 / 12) web rezervace ───────────────────────────────────────────────────────────────
Deno.test('f1/6: web — rezervace k zaplacení nenalezena → kód (zaplacená / neexistuje / jiný stav)', async () => {
  const d = new FakeDb({ bookings: [{ id: 'b_paid', payment_status: 'paid' }, { id: 'b_canc', payment_status: 'refunded' }] })
  const a = await (await webBookingMiss(d, 'b_paid')).json()
  eq([a.code, a.already_paid, a.booking_id], ['already_paid', true, 'b_paid'])
  const b = await webBookingMiss(d, 'b_none'); eq([b.status, (await b.json()).code], [404, 'not_found'])
  const c = await webBookingMiss(d, 'b_canc'); eq([c.status, (await c.json()).code], [409, 'wrong_status'])
})
Deno.test('f1/12: rezervace zdarma se zbožím → platba za zboží (pod 15 Kč dorovnání jen po SQL); bez zboží beze změny', () => {
  eq(freeShopPlan({ isFree: true, shopSum: 0, roundingCol: true, bookingTotal: 0 }), { kind: 'none' })
  eq(freeShopPlan({ isFree: false, shopSum: 200, roundingCol: true, bookingTotal: 500 }), { kind: 'none' })
  eq(freeShopPlan({ isFree: true, shopSum: 250, roundingCol: false, bookingTotal: 0 }), { kind: 'pay', rounding: null })
  eq(freeShopPlan({ isFree: true, shopSum: 7.5, roundingCol: true, bookingTotal: 0 }), { kind: 'pay', rounding: { due: 0, r: 7.5 } })
  eq(freeShopPlan({ isFree: true, shopSum: 7.5, roundingCol: false, bookingTotal: 0 }), { kind: 'below' })
})

// ── 10) Stripe položky webu v jazyce webu ───────────────────────────────────────────────
Deno.test('f1/10: web rezervace / e-shop — pronájem, číslo, velikost, doprava, sleva v jazyce webu', () => {
  eq(webLabels('en').booking, 'MotoGo24 — Motorcycle rental')
  eq(fillLabel(webLabels('de').bookingDesc, { num: 'ABCD1234' }), 'Buchung Nr. ABCD1234')
  eq(fillLabel(webLabels('cs').size, { size: 'XL' }), '(vel. XL)')
  eq(shippingLabel('zasilkovna', 'pl'), 'Dostawa — Packeta (Zásilkovna)')
  eq(shippingLabel('post', 'cs'), 'Doprava — Česká pošta'); eq(shippingLabel(null, 'fr'), 'Livraison')
  eq(webLabels('xx'), webLabels('cs'))
  for (const l of ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
    const w = webLabels(l) as Record<string, string>
    for (const k of ['booking', 'bookingDesc', 'shipping', 'shippingZasilkovna', 'shippingPost', 'size', 'discount']) ok(w[k], `${l}.${k}`)
    ok(w.bookingDesc.includes('{num}') && w.size.includes('{size}'), `${l}: zástupné znaky`)
  }
})
