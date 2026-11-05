// ===== _tests/i1_units_test.ts =====
// Oprava i1 (2026-11-05) — jednotkové testy čistých pomocníků: cíl storna přes všechny hlavní vratky
// (cancel-once.ts), zaokrouhlení v celých Kč i o přesně 1 Kč (card-minimum.ts), text storno mailu při
// nepotvrzené vratce (send-cancellation-email), částka pojistného mailu u neúplného poolu (cancel-mail-amount.ts).
import { cancelBusy, cancellationGoalHaleru, cancellationMissingHaleru, openCancelMains, type StripeRefundLike } from '../process-refund/cancel-once.ts'
import { wholeCrownRounding } from '../process-payment/card-minimum.ts'
import { refundDeferredNote, renderEmail } from '../send-cancellation-email/i18n.ts'
import { stripRefundParagraph } from '../send-cancellation-email/index.ts'
import { cancellationMailRefundCzk } from '../webhook-receiver/cancel-mail-amount.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
const BID = '11111111-2222-4333-8444-555555555555'
const TOK = '2026-11-05T10:00:00.123456+00:00'
const ref = (o: Partial<StripeRefundLike> & { md?: Record<string, string> }): StripeRefundLike => ({
  id: o.id || 're_x', amount: o.amount ?? 11500, status: o.status || 'succeeded', created: o.created ?? 1_800_000_000,
  payment_intent: o.payment_intent ?? 'pi_ext1',
  metadata: { mg_source: 'process-refund', mg_reason: 'cancellation', mg_booking_id: BID, mg_cancel_at: TOK, ...(o.md || {}) },
})
// A1: hlavní 115 (cíl 1558) bez zbytku; obsluha vědomě vrátila 1443 (nová hlavní, mg_cancel_total 1558)
const re1 = ref({ id: 're_1', amount: 11500, md: { mg_target: '155800', mg_cancel_total: '155800' } })
const re2 = ref({ id: 're_2', amount: 144300, payment_intent: 'pi_orig', created: 1_800_000_500, md: { mg_target: '144300', mg_cancel_total: '155800' } })

Deno.test('i1 cancel-once: cíl storna = mg_cancel_total nejnovější hlavní vratky; stará vratka není „otevřená“, když stornu nic nechybí', () => {
  eq(cancellationGoalHaleru([re1], BID, TOK), 155800)
  eq(cancellationMissingHaleru([re1], BID, TOK), 144300, 'po pádu zbytku chybí 1443')
  eq(openCancelMains([re1], BID, TOK).map((r) => r.id), ['re_1'])
  eq(cancellationGoalHaleru([re1, re2], BID, TOK), 155800, 'nejnovější první')
  eq(cancellationMissingHaleru([re1, re2], BID, TOK), 0)
  eq(openCancelMains([re1, re2], BID, TOK), [], 'obsluha zbytek vrátila → re_1 se nedovrací')
  // obsluha vrátila 100 % (3000 z pi_orig, cíl 311500) → storno celé, re_1 zavřená
  const full = ref({ id: 're_3', amount: 300000, payment_intent: 'pi_orig', created: 1_800_000_900, md: { mg_target: '300000', mg_cancel_total: '311500' } })
  eq(openCancelMains([re1, full], BID, TOK), [])
  // starší vratky bez mg_cancel_total → cíl neznámý → jen mg_target jednotlivých vratek (chování před i1)
  const legacy = ref({ id: 're_l', amount: 11500, md: { mg_target: '155800' } })
  eq(cancellationGoalHaleru([legacy], BID, TOK), null)
  eq(openCancelMains([legacy], BID, TOK).map((r) => r.id), ['re_l'])
  // zbytek k re_1 dorazil → nic nechybí
  const rest = ref({ id: 're_r', amount: 144300, payment_intent: 'pi_orig', created: 1_800_000_001, md: { mg_part: 'remainder', mg_main_refund: 're_1' } })
  eq(cancellationMissingHaleru([rest, re1], BID, TOK), 0); eq(openCancelMains([rest, re1], BID, TOK), [])
})

Deno.test('i1 cancel-once: busy = zámek drží jiné volání a vratka je mladší než 60 s', () => {
  const now = 1_800_000_000_000
  eq(cancelBusy(ref({ created: 1_800_000_000 - 30 }), false, now), true)
  eq(cancelBusy(ref({ created: 1_800_000_000 - 30 }), true, now), false, 'zámek držíme my')
  eq(cancelBusy(ref({ created: 1_800_000_000 - 61 }), false, now), false, 'po 60 s (zámek zabitého isolatu) se jde dál')
})

Deno.test('i1 card-minimum: zaokrouhlení v celých Kč se zapíše i při rozdílu přesně 1 Kč, víc ne', () => {
  eq(wholeCrownRounding(15, 15.4), -0.4); eq(wholeCrownRounding(15, 14.6), 0.4)
  eq(wholeCrownRounding(15, 16), -1, 'doklad 16, strženo 15 → −1 na dokladu (dřív nezapsáno)')
  eq(wholeCrownRounding(16, 15), 1); eq(wholeCrownRounding(15, 15), null); eq(wholeCrownRounding(15, 17), null)
  eq(wholeCrownRounding(100, 99.5), 0.5)
})

Deno.test('i1 storno mail: nepotvrzená vratka → věta o dokončení obsluhou (8 jazyků, bez „byl zpracován“), 5–10 dnů jinak', () => {
  for (const lang of ['cs', 'en', 'de', 'nl', 'es', 'fr', 'pl', 'uk'] as const) {
    const v = { booking_number: 'ABC', refund_amount: '1 558', refund_percent: '50', cancellation_reason: '', site_url: 'x', customer_name: '' }
    const ok = renderEmail('booking_cancelled', lang, v)!.body
    const def = renderEmail('booking_cancelled', lang, { ...v, refund_state: 'deferred' })!.body
    if (!/5–10|5 à 10/.test(ok)) throw new Error(`${lang}: okno 5–10 dnů`)
    if (!def.includes(refundDeferredNote(lang, '1 558'))) throw new Error(`${lang}: chybí věta o dokončení obsluhou`)
    if (def.includes('5–10') || def.includes('5 à 10')) throw new Error(`${lang}: odložená vratka slibuje kartu`)
    if (!def.includes('1 558')) throw new Error(`${lang}: částka`)
  }
  if (!/ti pošleme/.test(refundDeferredNote('cs', '1', { informal: true }))) throw new Error('tykání pro výbavu')
  const raw = '<p>hi</p><p style="x">Refund <strong>{{refund_amount}} Kč</strong> ({{refund_percent}} %) vrácen.</p><p>bye</p>'
  eq(stripRefundParagraph(raw), '<p>hi</p><p>bye</p>')
  eq(stripRefundParagraph('<p>bez částky</p>'), '<p>bez částky</p>')
})

Deno.test('i1 webhook mail: vratka vzniklá s neúplným poolem → částka z charge (mg_cancel_total se nepoužije)', async () => {
  const stripe = { refunds: { retrieve: (_id: string) => Promise.resolve({ metadata: { mg_cancel_total: '155800', mg_pool_incomplete: '1' } }) } }
  eq(await cancellationMailRefundCzk(stripe, { amount: 11500, metadata: { mg_source: 'process-refund', mg_reason: 'cancellation', mg_cancel_total: '155800', mg_pool_incomplete: '1' } }), null)
  eq(await cancellationMailRefundCzk(stripe, { amount: 11500, metadata: { mg_source: 'process-refund', mg_reason: 'cancellation', mg_cancel_total: '155800' } }), 1558)
  eq(await cancellationMailRefundCzk(stripe, { amount: 144300, metadata: { mg_source: 'process-refund', mg_reason: 'cancellation', mg_part: 'remainder', mg_main_refund: 're_1' } }), null, 'hlavní s příznakem')
})
