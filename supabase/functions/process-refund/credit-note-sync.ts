// ===== process-refund/credit-note-sync.ts =====
// Oprava f3 2026-10-22: dobropis k vratce rozdělené mezi více plateb (hlavní vratka + zbytek
// z ostatních plateb rezervace — f1/f2) mohl být podhodnocený. charge.refunded hlavní (uložené)
// platby dorazí pár sekund po refunds.create; webhook zapíše stripe_refund_id a recovery
// (createCreditNoteForExistingRefund) vystaví dobropis jen z částky HLAVNÍ vratky (např. −115 Kč),
// zatímco process-refund ještě vrací zbytek. process-refund pak dobropis k refund.id najde a jen
// přegeneroval PDF na 500 Kč → invoices.total −115, PDF −500, vráceno 500; konečná faktura pak
// ukázala přeplatek 385 Kč (dobropis final_overpay) a sváděla k druhé vratce. Teď:
//  • recovery přičte zbytek, který už k téže hlavní vratce proběhl (metadata mg_main_refund),
//  • process-refund dobropis k refund.id s nižší částkou, než skutečně vrátil, dorovná (položka,
//    základ, celkem, poznámka + účetní záznam) — se stejným stropem jako DB trigger
//    _cap_refund_to_paid při vložení (zaplacené DP − ostatní dobropisy). Nikdy nesnižuje.
import { otherRefundableIntents, type BookingIntentsStripe } from '../_shared/booking-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

/** Kolik se už vrátilo z OSTATNÍCH plateb rezervace jako zbytek k hlavní vratce `mainRefundId`
 *  (haléře). Chyba → 0 (dobropis jen z hlavní vratky; process-refund ho pak dorovná). */
export async function remainderForMainHaleru(stripe: BookingIntentsStripe, sb: Sb, a: {
  bookingId: string; mainPi: string | null; mainRefundId: string
}): Promise<number> {
  try {
    const cands = await otherRefundableIntents(stripe, sb, a.bookingId, a.mainPi, a.mainRefundId)
    return cands.reduce((s, c) => s + c.refundsForMain, 0)
  } catch (e) {
    console.warn('[process-refund] remainder for main refund failed:', (e as Error).message)
    return 0
  }
}

/** Dorovná existující dobropis na skutečně vrácenou částku `targetCzk` (jen nahoru). Vrací novou
 *  částku (Kč, kladně), nebo null, když se nic neměnilo. */
export async function reconcileCreditNote(sb: Sb, a: {
  cnId: string; cnNumber: string; bookingId: string; currentTotal: number; targetCzk: number
  /** položka dobropisu („Dobropis – Storno rezervace (model)") a důvod pro účetní záznam */
  description: string; reasonText: string; notes: string; issueDate: string
}): Promise<number | null> {
  const curH = Math.round(Math.abs(Number(a.currentTotal) || 0) * 100)
  let newH = Math.round(Math.abs(Number(a.targetCzk) || 0) * 100)
  if (newH <= curH) return null
  // Strop jako _cap_refund_to_paid (BEFORE INSERT — UPDATE ho nespouští).
  const { data: dps } = await sb.from('invoices').select('id, total')
    .eq('booking_id', a.bookingId).eq('type', 'payment_receipt').neq('status', 'cancelled')
  const paidH = (dps || []).reduce((s: number, r: { total?: number }) => s + Math.round((Number(r.total) || 0) * 100), 0)
  if (paidH > 0) {
    const { data: cns } = await sb.from('invoices').select('id, total')
      .eq('booking_id', a.bookingId).eq('type', 'credit_note').neq('status', 'cancelled')
    const otherH = (cns || []).filter((r: { id: string }) => r.id !== a.cnId)
      .reduce((s: number, r: { total?: number }) => s + Math.round(Math.abs(Number(r.total) || 0) * 100), 0)
    newH = Math.min(newH, Math.max(0, paidH - otherH))
  }
  if (newH <= curH) return null
  const czk = newH / 100
  const { error } = await sb.from('invoices').update({
    items: [{ description: a.description, qty: 1, unit_price: -czk }],
    subtotal: -czk, total: -czk, notes: a.notes,
  }).eq('id', a.cnId)
  if (error) throw new Error(`credit note reconcile failed: ${error.message}`)
  // Účetní záznam dobropisu: recovery ho váže přes invoice_id, process-refund přes popis „Dobropis <číslo> …".
  const byInvoice = await sb.from('accounting_entries').update({ amount: -czk }).eq('invoice_id', a.cnId).select('id')
  let done = Array.isArray(byInvoice?.data) && byInvoice.data.length > 0
  if (!done) {
    const byDesc = await sb.from('accounting_entries').update({ amount: -czk })
      .eq('booking_id', a.bookingId).eq('category', 'refund').like('description', `Dobropis ${a.cnNumber} %`).select('id')
    done = Array.isArray(byDesc?.data) && byDesc.data.length > 0
  }
  if (!done) {
    await sb.from('accounting_entries').insert({
      type: 'expense', amount: -czk, description: `Dobropis ${a.cnNumber} – ${a.reasonText}`,
      category: 'refund', date: a.issueDate, booking_id: a.bookingId, invoice_id: a.cnId,
    }).then(() => {}, () => {})
  }
  return czk
}
