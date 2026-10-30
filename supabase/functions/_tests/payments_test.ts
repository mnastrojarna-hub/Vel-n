// ===== _tests/payments_test.ts =====
// deno test supabase/functions/_tests — D1/D2/D4/D5 (2026-10-16): minimum karty,
// idempotence, ochrana proti dvojí platbě, kódy a texty odmítnutí bez kontaktů.
import { classifyDue, waiveBooking, waiveShop, CARD_MIN_CZK } from '../process-payment/card-minimum.ts'
import { idempotencyKey, sanitizeAttemptId, chgHash, guardStoredIntent, sameAttempt, findRecentLiveIntent } from '../process-payment/intent-guard.ts'
import { mapStripeError, isUncertainStripeError } from '../process-payment/stripe-errors.ts'
import { CS, declineMessageCs, refuse, cancelledReasonKey } from '../process-payment/refusals.ts'
import { FakeDb } from './fake-supabase.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }

// ── classifyDue ────────────────────────────────────────────────────────────
Deno.test('classifyDue: pravidla majitele (≤1 odpustit, 1–15 → 15, ≥15 beze změny)', () => {
  const k = (due: number, amt: number, cm: boolean) => classifyDue(due, amt, cm).kind
  // zdarma
  eq(k(-5, 0, true), 'free'); eq(k(0, 0, true), 'free'); eq(k(0, 0, false), 'free'); eq(k(0, 200, true), 'free')
  // odpuštění jen s card_min a částkou pod 15
  eq(k(0.4, 0, true), 'waive'); eq(k(1, 0, true), 'waive'); eq(k(1, 1, true), 'waive'); eq(k(0.6, 7, true), 'waive')
  eq(k(1, 15, true), 'waive'); eq(k(0.6, 300, true), 'ok') // zastaralých 15 Kč se nestrhne; nad 15 = upsell
  eq(classifyDue(0.6, 0, true).rounding, -0.6)
  // stará appka pod 15 Kč → below_minimum (nic se nestrhne)
  eq(k(0.4, 0, false), 'below'); eq(k(1, 1, false), 'below'); eq(k(7, 7, false), 'below'); eq(k(14.4, 14, false), 'below')
  // dorovnání: card_min + amount 15
  eq(k(1.01, 15, true), 'round'); eq(k(7.5, 15, true), 'round'); eq(k(14.6, 15, true), 'round')
  eq(classifyDue(7, 15, true).rounding, 8); eq(classifyDue(14.6, 15, true).rounding, 0.4); eq(classifyDue(7.5, 15, true).charge, 15)
  // nová appka s jinou částkou pod 15 → below (appka nabídne „Zaplatit 15 Kč")
  eq(k(7, 7, true), 'below'); eq(k(7, 16, true), 'ok') // ≥ 15 (např. upsell) = běžná platba
  // stará appka 14,5–15 Kč (posílá 15) = beze změny, bez záznamu dorovnání
  eq(k(14.6, 15, false), 'ok'); eq(classifyDue(14.6, 15, false).rounding, 0)
  // ≥ 15 beze změny; nesoulad částky řeší volající (amount_mismatch / free_mismatch)
  eq(k(15, 15, true), 'ok'); eq(k(15.4, 15, true), 'ok'); eq(k(100, 100, false), 'ok'); eq(k(100, 0, false), 'ok'); eq(k(100, 0, true), 'ok')
  eq(CARD_MIN_CZK, 15)
})

Deno.test('classifyDue: celá tabulka due × card_min × amount je konzistentní', () => {
  for (const due of [-5, 0, 0.4, 1, 1.01, 7.5, 14.6, 15, 15.4, 100]) {
    for (const cm of [true, false]) {
      for (const amt of [0, 1, 7, 15, 16]) {
        const c = classifyDue(due, amt, cm)
        // server nikdy nestrhne víc, než klient poslal
        ok(c.charge <= Math.max(amt, 0) || c.kind === 'below', `charge>amount ${due}/${cm}/${amt}`)
        if (c.kind === 'waive') { eq(c.charge, 0); ok(due <= 1 && cm && amt <= 15) }
        if (c.kind === 'round') { eq(amt, 15); ok(cm && due > 1 && due < 15); eq(Math.round((c.due + c.rounding) * 100) / 100, 15) }
        if (c.kind === 'below') ok(due > 0 && due < 15 && amt < 15)
      }
    }
  }
})

// ── CAS zápis odpuštění (dorovnání na 15 Kč zapisuje až webhook — _shared/charge-rounding) ──
Deno.test('waiveBooking: nenasazené SQL (chybí card_rounding) → unavailable, cena beze změny', async () => {
  const db = new FakeDb({ bookings: [{ id: 'b1', total_price: 0.6, payment_status: 'unpaid', status: 'pending' }] })
  db.missingCols.add('card_rounding')
  eq(await waiveBooking(db, 'b1', 0.6), 'unavailable')
  eq(db.rows('bookings')[0].total_price, 0.6)
})
Deno.test('waiveBooking: total 0, card_rounding −due; zaplacená/zrušená se nemění', async () => {
  const db = new FakeDb({ bookings: [
    { id: 'b1', total_price: 0.6, card_rounding: 0, payment_status: 'unpaid', status: 'pending' },
    { id: 'b2', total_price: 0.6, card_rounding: 0, payment_status: 'paid', status: 'reserved' },
    { id: 'b3', total_price: 0.6, card_rounding: 0, payment_status: 'unpaid', status: 'cancelled' },
  ] })
  eq(await waiveBooking(db, 'b1', 0.6), 'done')
  eq(db.rows('bookings')[0].total_price, 0); eq(db.rows('bookings')[0].card_rounding, -0.6)
  eq(await waiveBooking(db, 'b2', 0.6), 'raced')
  eq(await waiveBooking(db, 'b3', 0.6), 'raced')
})
Deno.test('waiveShop: e-shop do 1 Kč → total 0, card_rounding −due', async () => {
  const db = new FakeDb({ shop_orders: [{ id: 'o1', total: 0.8, card_rounding: 0, payment_status: 'pending' }] })
  eq(await waiveShop(db, 'o1', 0.8), 'done')
  eq(db.rows('shop_orders')[0].total, 0); eq(db.rows('shop_orders')[0].card_rounding, -0.8)
  eq(await waiveShop(db, 'o1', 0.8), 'raced')
})

// ── idempotence ────────────────────────────────────────────────────────────
Deno.test('idempotencyKey: deterministický; attempt_id vs. 15s kbelík; hash změny', async () => {
  const base = { type: 'booking', refId: 'b1', chargeCents: 1500, pm: null, attemptId: 'a1b2c3d4-0001', chg: null }
  eq(idempotencyKey(base), idempotencyKey({ ...base }))
  ok(idempotencyKey(base) !== idempotencyKey({ ...base, attemptId: 'a1b2c3d4-0002' }))
  ok(idempotencyKey(base) !== idempotencyKey({ ...base, chargeCents: 1600 }))
  ok(idempotencyKey(base) !== idempotencyKey({ ...base, pm: 'pm_1' }))
  const t = Date.UTC(2026, 9, 16, 12, 0, 1)
  eq(idempotencyKey({ ...base, attemptId: null, nowMs: t }), idempotencyKey({ ...base, attemptId: null, nowMs: t + 10_000 }))
  ok(idempotencyKey({ ...base, attemptId: null, nowMs: t }) !== idempotencyKey({ ...base, attemptId: null, nowMs: t + 16_000 }))
  ok(idempotencyKey(base).length <= 255)
  eq(sanitizeAttemptId('a1b2c3d4-0001'), 'a1b2c3d4-0001'); eq(sanitizeAttemptId('short'), null); eq(sanitizeAttemptId('x y'), null)
  eq(sanitizeAttemptId(42), null)
  const h1 = await chgHash({ _swap: { m: 'x', d: '2026-11-01' } }), h2 = await chgHash({ _swap: { m: 'x', d: '2026-11-01' } })
  eq(h1, h2); eq(String(h1).length, 16); ok(h1 !== await chgHash({ _swap: { m: 'y', d: '2026-11-01' } }))
  eq(await chgHash(null), null)
})

// ── guardStoredIntent ───────────────────────────────────────────────────────
type Pi = { id: string; status: string; amount: number; currency: string; metadata: Record<string, string>; client_secret?: string }
function fakeStripe(pis: Pi[], opts: { cancelMovesTo?: string } = {}) {
  const cancelled: string[] = []
  return {
    cancelled,
    paymentIntents: {
      retrieve: (id: string) => {
        const p = pis.find((x) => x.id === id)
        return p ? Promise.resolve(structuredClone(p)) : Promise.reject(Object.assign(new Error('No such PI'), { code: 'resource_missing' }))
      },
      cancel: (id: string) => {
        const p = pis.find((x) => x.id === id)!
        if (opts.cancelMovesTo) { p.status = opts.cancelMovesTo; return Promise.reject(new Error('cannot cancel')) }
        p.status = 'canceled'; cancelled.push(id); return Promise.resolve(structuredClone(p))
      },
    },
  }
}
// deno-lint-ignore no-explicit-any
const G = (s: any, a: Record<string, unknown>) => guardStoredIntent(s, { storedPiId: 'pi_1', type: 'booking', refKey: 'booking_id', refId: 'b1', sheet: true, chargeCents: 1500, chg: null, ...a } as never)

Deno.test('guard: zaplacený / zpracovávaný PI → refuse (žádná druhá platba)', async () => {
  for (const st of ['succeeded', 'processing', 'requires_capture']) {
    const s = fakeStripe([{ id: 'pi_1', status: st, amount: 1500, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1' } }])
    eq((await G(s, {})).action, 'refuse', st)
  }
})
Deno.test('guard: otevřený PI — stejný list = reuse, jiná částka / uložená karta = cancel', async () => {
  const mk = () => fakeStripe([{ id: 'pi_1', status: 'requires_payment_method', amount: 1500, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1' } }])
  eq((await G(mk(), {})).action, 'reuse')
  const s2 = mk(); eq((await G(s2, { chargeCents: 1600 })).action, 'proceed'); eq(s2.cancelled, ['pi_1'])
  const s3 = mk(); eq((await G(s3, { sheet: false })).action, 'proceed'); eq(s3.cancelled, ['pi_1'])
  const s4 = mk(); eq((await G(s4, { liveOnly: true })).action, 'proceed'); eq(s4.cancelled, [])
  // dorovnání v metadatech starého PI jiné (cena se mezitím změnila) → nepoužít, zrušit
  const s5 = mk(); eq((await G(s5, { matchMeta: { due: '7', card_rounding: '8' } })).action, 'proceed'); eq(s5.cancelled, ['pi_1'])
})
Deno.test('guard: stejný attempt_id = reuse i pro uloženou kartu (requires_action)', async () => {
  const s = fakeStripe([{ id: 'pi_1', status: 'requires_action', amount: 1500, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1', attempt_id: 'att-12345678' } }])
  eq((await G(s, { sheet: false, attemptId: 'att-12345678' })).action, 'reuse')
  eq(s.cancelled, [])
  ok(sameAttempt({ metadata: { attempt_id: 'att-12345678' } }, 'att-12345678')); ok(!sameAttempt({ metadata: {} }, 'att-12345678'))
})
Deno.test('guard: cizí / neexistující / zrušený PI → proceed', async () => {
  eq((await G(fakeStripe([{ id: 'pi_1', status: 'succeeded', amount: 1500, currency: 'czk', metadata: { type: 'booking', booking_id: 'b2' } }]), {})).action, 'proceed')
  eq((await G(fakeStripe([]), {})).action, 'proceed')
  eq((await G(fakeStripe([{ id: 'pi_1', status: 'canceled', amount: 1500, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1' } }]), {})).action, 'proceed')
  eq((await G(fakeStripe([]), { storedPiId: 'cs_test' })).action, 'proceed')
})
Deno.test('guard: zrušení selže, protože PI mezitím prošel → refuse', async () => {
  const s = fakeStripe([{ id: 'pi_1', status: 'requires_action', amount: 1500, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1' } }], { cancelMovesTo: 'succeeded' })
  eq((await G(s, { sheet: false })).action, 'refuse')
  // i doplatek, který právě prošel (druhé zařízení) → refuse, ne nový PI naceněný proti starému stavu
  const x = fakeStripe([{ id: 'pi_1', status: 'requires_payment_method', amount: 900, currency: 'czk', metadata: { type: 'extension', booking_id: 'b1' } }], { cancelMovesTo: 'succeeded' })
  eq((await G(x, { type: 'extension', sheet: false })).action, 'refuse')
})
Deno.test('findRecentLiveIntent: uložená karta bez uloženého PI najde nedávnou zaplacenou platbu', async () => {
  const id = '00000000-0000-0000-0000-0000000000b1'
  let q = ''
  const s = { paymentIntents: {
    retrieve: () => Promise.reject(new Error('x')), cancel: () => Promise.reject(new Error('x')),
    search: (p: { query: string }) => { q = p.query; return Promise.resolve({ data: [{ id: 'pi_9', status: 'succeeded' }] as never }) },
  } }
  eq(await findRecentLiveIntent(s as never, { refKey: 'booking_id', refId: id, type: 'booking', nowMs: 1_700_000_000_000 }), { piId: 'pi_9', status: 'succeeded' })
  ok(q.includes(`metadata['booking_id']:'${id}'`) && q.includes('created>'), q)
  eq(await findRecentLiveIntent(s as never, { refKey: 'booking_id', refId: "x' OR 1", type: 'booking' }), null) // neplatné id = nehledat
  const bad = { paymentIntents: { ...s.paymentIntents, search: () => Promise.reject(new Error('search down')) } }
  eq(await findRecentLiveIntent(bad as never, { refKey: 'booking_id', refId: id, type: 'booking' }), null)
})
Deno.test('guard: doplatek — zaplacený předchozí doplatek = paid_extension, původní platba rezervace nevadí', async () => {
  const ext = fakeStripe([{ id: 'pi_1', status: 'succeeded', amount: 1500, currency: 'czk', metadata: { type: 'extension', booking_id: 'b1' } }])
  eq((await G(ext, { type: 'extension' })).action, 'paid_extension')
  const orig = fakeStripe([{ id: 'pi_1', status: 'succeeded', amount: 300000, currency: 'czk', metadata: { type: 'booking', booking_id: 'b1' } }])
  eq((await G(orig, { type: 'extension' })).action, 'proceed')
  const proc = fakeStripe([{ id: 'pi_1', status: 'processing', amount: 1500, currency: 'czk', metadata: { type: 'extension', booking_id: 'b1' } }])
  eq((await G(proc, { type: 'extension' })).action, 'refuse')
})

// ── chyby Stripe a texty ───────────────────────────────────────────────────
Deno.test('isUncertainStripeError: spojení / 5xx = nejisté, zamítnutí / neplatný požadavek = jisté', () => {
  ok(isUncertainStripeError({ type: 'StripeConnectionError' })); ok(isUncertainStripeError({ type: 'StripeAPIError', statusCode: 500 }))
  ok(isUncertainStripeError(new Error('fetch failed')))
  ok(!isUncertainStripeError({ type: 'StripeInvalidRequestError', statusCode: 400 }))
  ok(!isUncertainStripeError({ type: 'StripeIdempotencyError', statusCode: 400 }))
  ok(!isUncertainStripeError({ type: 'StripeCardError', statusCode: 402 }))
  ok(/neplať prosím znovu/i.test(CS.payment_uncertain) && !/nestrhli/.test(CS.payment_uncertain))
})

Deno.test('mapStripeError: třídy chyb → stabilní kód, žádný anglický text', () => {
  eq(mapStripeError({ type: 'StripeInvalidRequestError', code: 'amount_too_small', statusCode: 400 }).code, 'below_minimum')
  eq(mapStripeError({ type: 'StripeIdempotencyError', statusCode: 400 }).code, 'duplicate_request')
  eq(mapStripeError({ type: 'StripeInvalidRequestError', code: 'idempotency_key_in_use', statusCode: 409 }).code, 'duplicate_request')
  for (const t of ['StripeRateLimitError', 'StripeConnectionError', 'StripeAPIError']) eq(mapStripeError({ type: t }).code, 'stripe_unavailable')
  eq(mapStripeError({ type: 'StripeInvalidRequestError', statusCode: 503 }).status, 503)
  eq(mapStripeError(new Error('boom')).code, 'server_error')
  eq(mapStripeError(null).code, 'server_error')
  for (const e of [{ type: 'StripeAPIError', message: 'An unknown error occurred' }, new Error('Payment failed: x')]) {
    ok(!/error occurred|failed|Payment/i.test(mapStripeError(e).error))
  }
})

const CONTACT = /@|\+420|774\s?256|napi[sš]\s+n[aá]m|ozveme|kontaktuj|zavolej|info@|motogo24\.cz/i
Deno.test('D5: žádný text odmítnutí ani zamítnutí karty neobsahuje kontakt', () => {
  for (const [k, v] of Object.entries(CS)) ok(!CONTACT.test(v), `CS.${k}`)
  const codes = ['insufficient_funds', 'expired_card', 'incorrect_cvc', 'invalid_cvc', 'incorrect_number', 'invalid_number',
    'invalid_expiry_month', 'invalid_expiry_year', 'card_not_supported', 'currency_not_supported', 'card_velocity_exceeded',
    'withdrawal_count_limit_exceeded', 'card_decline_rate_limit_exceeded', 'incorrect_pin', 'pin_try_exceeded', 'offline_pin_required',
    'issuer_not_available', 'try_again_later', 'reenter_transaction', 'processing_error', 'authentication_required',
    'payment_intent_authentication_failure', 'lost_card', 'stolen_card', 'pickup_card', 'generic_decline', 'card_declined', 'do_not_honor',
    'do_not_try_again', 'fraudulent', 'restricted_card', 'call_issuer', 'duplicate_transaction', 'resource_missing',
    'payment_intent_payment_attempt_expired', 'amount_too_small', 'something_new']
  for (const c of codes) {
    const t = declineMessageCs(c, null)
    ok(t.length > 20 && !CONTACT.test(t), c)
    ok(/nestrhli|neplať/i.test(t), `${c}: musí říct, zda se něco strhlo`)
  }
})
Deno.test('D5: ztracená / odcizená / zadržená karta = obecné bezpečné znění', () => {
  const generic = declineMessageCs('card_declined', 'generic_decline')
  for (const d of ['lost_card', 'stolen_card', 'pickup_card', 'fraudulent']) {
    eq(declineMessageCs('card_declined', d), generic, d)
    ok(!/ztracen|odcizen|zadržen|podvod/i.test(declineMessageCs('card_declined', d)))
  }
  ok(/peněz/.test(declineMessageCs('card_declined', 'insufficient_funds')))
  ok(/vypršela/.test(declineMessageCs('expired_card', null)))
})
Deno.test('refuse(): kód + český text s dosazenou částkou', async () => {
  const r = refuse(400, 'below_minimum', { due: 7.5 })
  eq(r.status, 400)
  const j = await r.json()
  eq(j.code, 'below_minimum'); eq(j.success, false); ok(String(j.error).includes('7,5 Kč'), j.error)
  const v = await refuse(409, 'voucher_unavailable', { voucher_code: 'VTEST1' }).json()
  ok(String(v.error).includes('VTEST1'))
  // číselný kód poukazu se vkládá doslova (dřív „0042" → „42", „12345678" → „12 345 678")
  ok(String((await refuse(409, 'voucher_unavailable', { voucher_code: '0042' }).json()).error).includes('Poukaz 0042 '))
  ok(String((await refuse(409, 'voucher_unavailable', { voucher_code: '12345678' }).json()).error).includes('Poukaz 12345678 '))
  ok(String((await refuse(409, 'amount_mismatch', { server_total: 12345 }).json()).error).includes('12\u00a0345') ||
     String((await refuse(409, 'amount_mismatch', { server_total: 12345 }).json()).error).includes('12 345'))
  const u = await refuse(409, 'nonexistent_code').json()
  eq(u.error, CS.server_error)
})

Deno.test('booking_cancelled: tlačítko „Obnovit rezervaci", konkrétní důvod odmítnutého obnovení, tykání', () => {
  ok(CS.booking_cancelled.includes('„Obnovit rezervaci"') && !CS.booking_cancelled.includes('Obnovit a zaplatit'))
  ok(/novou rezervaci/.test(CS.booking_cancelled))
  eq(cancelledReasonKey('cancelled_by_staff'), 'booking_cancelled_staff'); eq(cancelledReasonKey('restore_limit'), 'booking_cancelled_limit')
  eq(cancelledReasonKey('voucher_unavailable'), 'booking_cancelled_voucher'); eq(cancelledReasonKey(null), 'booking_cancelled')
  for (const k of ['auth_required', 'auth_required_edit', 'forbidden', 'forbidden_edit', 'forbidden_shop']) {
    ok(!/přihlaste|zkuste|Načtěte/.test(CS[k]), k)
  }
  ok(!/dorovnat/.test(CS.rounding_unavailable_waiver) && /odpustit/.test(CS.rounding_unavailable_waiver))
  ok(!/za pár minut/.test(CS.rounding_unavailable))
})
