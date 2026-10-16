// ===== process-refund/other-intents.ts =====
// Odpověď majitele 2026-10-16 (otázka 1, „ano stejně"): při stornu se dorovnání na
// minimální platbu kartou vrací POMĚRNĚ jako zbytek ceny. Dorovnání je součástí
// bookings.total_price (storno = % × total_price), ale u doplatku úpravy / výměny bylo
// zaplacené JINÝM PaymentIntentem než původní rezervace. process-refund dřív vracel jen
// z bookings.stripe_payment_intent_id (oříznuto na jeho zbytek) → storno 100 % po
// zaplacené úpravě nevrátilo doplatek ani jeho dorovnání. Zbytek nad možnosti hlavní
// platby se teď vrátí z ostatních úspěšných plateb TÉŽE rezervace (doplatky úprav,
// výměn, starší platba rezervace), nejstarší první. Výběr plateb + výluky (e-shop,
// duplicitní platba, platba nezapsané změny) → _shared/booking-intents.ts.
// Idempotence: klíč refund-rest:<id hlavní vratky>:<pi>:<částka> + metadata
// mg_main_refund. Hlavní vratka je mezi duplicitními dispatchi idempotentní (Stripe ji
// přehraje se stejným id) → i zbytek: co už se k TÉTO hlavní vratce vrátilo (i z jiné
// platby), se od požadavku odečte a stejná částka z téže platby dostane stejný klíč.
// Legitimní pozdější vratka má novou hlavní vratku → nový klíč.
import { otherRefundableIntents, type BookingIntentsStripe } from '../_shared/booking-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
export type OtherIntentsStripe = BookingIntentsStripe
export type ExtraRefund = { piId: string; refundId: string; amountHaleru: number; status: string }
export { otherRefundableIntents }

/** Vrátí `remainingHaleru` z ostatních plateb rezervace (po částech, nejstarší první).
 *  `leftHaleru` = co na nich po této vratce ještě zbývá (≠ 0 → vratka byla jen částečná). */
export async function refundRemainder(stripe: OtherIntentsStripe, sb: Sb, a: {
  bookingId: string; mainPi: string | null; mainRefundId: string; remainingHaleru: number; reason?: string | null
}): Promise<{ refunds: ExtraRefund[]; refundedHaleru: number; leftHaleru: number; error?: string }> {
  const refunds: ExtraRefund[] = []
  let remaining = Math.max(0, Math.round(a.remainingHaleru))
  let left = 0
  if (!remaining) return { refunds, refundedHaleru: 0, leftHaleru: 0 }
  let cands: Awaited<ReturnType<typeof otherRefundableIntents>> = []
  try {
    cands = await otherRefundableIntents(stripe, sb, a.bookingId, a.mainPi, a.mainRefundId)
  } catch (e) {
    return { refunds, refundedHaleru: 0, leftHaleru: 0, error: (e as Error).message }
  }
  // Opakovaný dispatch téhož storna: k této hlavní vratce už vrácené (i z jiné platby) se nevrací znovu.
  const already = cands.reduce((s, c) => s + c.refundsForMain, 0)
  const alreadyDone = Math.min(already, remaining)
  remaining -= alreadyDone
  for (const c of cands) {
    const amt = Math.min(c.refundableHaleru, remaining)
    if (amt <= 0) { left += c.refundableHaleru; continue }
    try {
      const r = await stripe.refunds.create({
        payment_intent: c.id, amount: amt, reason: 'requested_by_customer',
        metadata: { mg_source: 'process-refund', mg_reason: a.reason || '', mg_booking_id: a.bookingId, mg_part: 'remainder', mg_main_refund: a.mainRefundId },
      }, { idempotencyKey: `refund-rest:${a.mainRefundId}:${c.id}:${amt}` })
      refunds.push({ piId: c.id, refundId: r.id, amountHaleru: Number(r.amount ?? amt), status: String(r.status || 'succeeded') })
      remaining -= amt
      left += c.refundableHaleru - amt
    } catch (e) {
      const done = refunds.reduce((s, x) => s + x.amountHaleru, 0) + alreadyDone
      return { refunds, refundedHaleru: done, leftHaleru: left + c.refundableHaleru, error: (e as Error).message }
    }
  }
  return { refunds, refundedHaleru: refunds.reduce((s, x) => s + x.amountHaleru, 0) + alreadyDone, leftHaleru: left }
}
