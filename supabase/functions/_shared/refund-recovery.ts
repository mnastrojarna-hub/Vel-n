// ===== _shared/refund-recovery.ts =====
// Opravné (recovery-only) volání process-refund: NIKDY nevytvoří Stripe vratku, jen dohraje
// chybějící dobropis / PDF k vratce, která už proběhla (větev `/_retry$/` v process-refund).
// Oprava f3 2026-10-22: webhook charge.refunded volal process-refund jen s {booking_id} (bez
// částky a důvodu). U rezervace ve stavu 'refund_pending' (storno z Velínu ho zapíše před vratkou;
// process-refund ho zapíše, když Stripe vratku ještě nepotvrdil) to prošlo bránou jako nová PLNÁ
// vratka zbytku uložené platby s jiným idempotency klíčem → storno 50 % vrátilo 100 %, zkrácení
// s čekající vratkou vrátilo celou cenu živé rezervace. Teď webhook posílá recovery důvod.

/** Důvod, se kterým webhook charge.refunded volá process-refund (končí na `_retry`). */
export const WEBHOOK_REFUND_RECOVERY_REASON = 'webhook_refund_retry'

/** Recovery-only dispatch (attach smyčky e-mailů `…_retry`, webhook): žádná nová Stripe vratka. */
export function isRecoveryOnlyReason(reason: unknown): boolean {
  return typeof reason === 'string' && /_retry$/.test(reason)
}

/** Tělo recovery volání process-refund z webhooku — bez částky, s recovery důvodem. */
export function webhookRecoveryBody(bookingId: string, refundId: string | null): Record<string, string> {
  return { booking_id: bookingId, reason: WEBHOOK_REFUND_RECOVERY_REASON, ...(refundId ? { refund_id: refundId } : {}) }
}

// deno-lint-ignore no-explicit-any
type Sb = any

/** Stav rezervace po charge.refunded (webhook-receiver). Vratka z process-refund (mg_source):
 *  stav zapisuje process-refund sám (vrací i z více plateb — „tahle charge je celá vrácená" ≠
 *  „rezervace je vrácená celá"); webhook ho jen zastoupí, dokud je rezervace stále 'paid' —
 *  compare-and-set (oprava f3: dřív read-then-write — když process-refund mezitím zapsal
 *  'partial_refund', webhook ho přepsal na 'refunded' a každá další vratka pak skončila jako
 *  already_refunded). 'refund_pending' (storno z Velínu / čekající vratka) nepřepisuje.
 *  stripe_refund_id jen do prázdného (také compare-and-set). Externí vratka (Stripe portál):
 *  stav dle Stripe + případné storno bezpodmínečně jako dřív. */
export async function syncRefundBooking(sb: Sb, a: {
  bookingId: string; currentStatus: string | null | undefined; currentRefundId: string | null | undefined
  fromProcessRefund: boolean; fullyRefunded: boolean; refundId: string | null; cancelPatch?: Record<string, unknown> | null
}): Promise<{ statusWritten: boolean; refundIdWritten: boolean }> {
  const status = a.fullyRefunded ? 'refunded' : 'partial_refund'
  if (!a.fromProcessRefund) {
    const patch: Record<string, unknown> = { payment_status: status, ...(a.cancelPatch || {}) }
    if (a.refundId) patch.stripe_refund_id = a.refundId
    await sb.from('bookings').update(patch).eq('id', a.bookingId)
    return { statusWritten: true, refundIdWritten: !!a.refundId }
  }
  let statusWritten = false
  let refundIdWritten = false
  if (a.currentStatus === 'paid') {
    const { data, error } = await sb.from('bookings').update({ payment_status: status })
      .eq('id', a.bookingId).eq('payment_status', 'paid').select('id')
    statusWritten = !error && Array.isArray(data) && data.length > 0
  }
  if (a.refundId && !a.currentRefundId) {
    const { data, error } = await sb.from('bookings').update({ stripe_refund_id: a.refundId })
      .eq('id', a.bookingId).is('stripe_refund_id', null).select('id')
    refundIdWritten = !error && Array.isArray(data) && data.length > 0
  }
  return { statusWritten, refundIdWritten }
}
