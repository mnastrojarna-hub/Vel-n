// Ruční vratka převodem (dobropis bez Stripe vratky) v detailu rezervace — banner „VRÁTIT NA ÚČET“ a akce
// „Vratka odeslána“. Oprava i4 (2026-11-07, verify:refunds S7): rezervace placená kartou + doplatek převodem
// po plném stornu bez Fio má kartovou vratku (bookings.stripe_refund_id) A ruční dobropis na část převodem;
// dřív se ruční část ukazovala jen bez stripe_refund_id, takže ji obsluha neviděla (mail jí přitom říkal
// „potvrďte tlačítkem Vratka odeslána“) a „Vratka odeslána“ pak stav nastavila jen podle ručního dobropisu.

/** Otevřený ruční dobropis: rezervace „Čeká na vrácení“ a živý dobropis bez Stripe vratky (i vedle vratky kartou). */
export function manualRefundOpen(booking, creditNotes) {
  if (booking?.payment_status !== 'refund_pending') return null
  return (creditNotes || []).find((c) => !c.stripe_refund_id) || null
}

/** Stav po „Vratka odeslána“: živé dobropisy (karta + převod) kryjí cenu → 'refunded', jinak 'partial_refund'. */
export function manualRefundSentStatus(booking, creditNotes) {
  const total = Number(booking?.total_price) || 0
  const back = (creditNotes || []).reduce((s, c) => s + Math.abs(Number(c.total) || 0), 0)
  return total > 0 && back + 1 < total ? 'partial_refund' : 'refunded'
}
