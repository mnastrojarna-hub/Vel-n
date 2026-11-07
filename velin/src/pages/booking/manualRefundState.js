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

/** Stav po „Vratka odeslána“. Oprava i5r2 (verify:refunds R2): ŽIVÁ (nezrušená) rezervace má svou aktuální cenu dál
 *  zaplacenou → vždy 'partial_refund' (dřív součet dobropisů dvou zkrácení ≥ snížená cena → 'refunded' u živé rezervace:
 *  storno pak „už vráceno“ nevrátilo nic a triggery čekající paid/partial_refund se přeskočily). Zrušená: živé dobropisy
 *  (karta + převod) kryjí zaplacené doklady (Σ živých DP — `paidDocsCzk`; bez nich cenu) → 'refunded', jinak 'partial_refund'.
 *  Bez stavu rezervace jako dřív (dle ceny). */
export function manualRefundSentStatus(booking, creditNotes, paidDocsCzk = null) {
  if (booking?.status && booking.status !== 'cancelled') return 'partial_refund'
  const paid = Number(paidDocsCzk) || 0
  const total = booking?.status === 'cancelled' && paid > 0 ? paid : (Number(booking?.total_price) || 0)
  const back = (creditNotes || []).reduce((s, c) => s + Math.abs(Number(c.total) || 0), 0)
  return total > 0 && back + 1 < total ? 'partial_refund' : 'refunded'
}

/** Σ živých dokladů o přijaté platbě (DP, Kč) rezervace — pro manualRefundSentStatus u zrušené rezervace; null = nečitelné. */
export async function livePaidDocsCzk(supabase, bookingId) {
  try {
    const { data, error } = await supabase.from('invoices').select('total').eq('booking_id', bookingId)
      .eq('type', 'payment_receipt').neq('status', 'cancelled')
    if (error) return null
    return (data || []).reduce((s, r) => s + (Number(r.total) || 0), 0)
  } catch { return null }
}
