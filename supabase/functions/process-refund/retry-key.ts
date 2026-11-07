// ===== process-refund/retry-key.ts =====
// Oprava i4 (2026-11-07, verify:refunds S1a–S1c): SELHANÁ vratka (Stripe 'failed' / 'canceled') peníze nevrátila,
// takže `refundable` platby je po ní stejné jako před ní. Idempotency klíče vratek (`refund:<rez>:<částka>:<refundable>`,
// zbytek `refund-rest:<hlavní>:<pi>:<částka>`) byly proto po pádu STEJNÉ — opakování do 24 h (Velín „Potvrdit vrácení“,
// služba / recovery, pokyn z mailu „vratku zopakujte“) dostalo od Stripe PŘEHRANOU původní (selhanou) vratku se stavem
// z doby vzniku ('pending'), žádná nová nevznikla a process-refund hlásil úspěch.
//  • retrySuffix — sekvenční složka klíče = počet selhaných / zrušených vratek platby: souběžné duplicity ji vidí
//    stejnou (jeden refund), po pádu se změní (nový refund). Bez selhaných vratek prázdná → klíč beze změny proti
//    živé verzi (okno nasazení: stará a nová verze srazí duplicitu stejně jako dřív).
//  • isReplayOfFailed — Stripe vrátil vratku, o které už víme, že selhala (klíč staré verze / jiný souběh) → chyba,
//    žádný zápis stavu, dobropisu ani bookkeepingu zbytku.
type RefundLike = { id?: string | null; status?: string | null }

/** Vratka, která peníze NEvrátila. */
export const failedRefund = (r: RefundLike): boolean => r.status === 'failed' || r.status === 'canceled'

/** Id selhaných / zrušených vratek (seznam vratek jedné platby). */
export function failedRefundIds(refunds: RefundLike[] | null | undefined): string[] {
  return (refunds || []).filter((r) => failedRefund(r) && !!r.id).map((r) => String(r.id))
}

/** Přípona idempotency klíče: '' bez selhaných vratek (klíč jako dřív), jinak `:f<počet>`. */
export function retrySuffix(failedIds: string[] | null | undefined): string {
  const n = (failedIds || []).length
  return n > 0 ? `:f${n}` : ''
}

/** Stripe přehrál (idempotency klíč) vratku, která už selhala → nepovažovat za vrácení. */
export function isReplayOfFailed(refundId: string | null | undefined, failedIds: string[] | null | undefined): boolean {
  return !!refundId && (failedIds || []).includes(String(refundId))
}

export const REPLAYED_FAILED = 'stripe_replayed_failed_refund'
