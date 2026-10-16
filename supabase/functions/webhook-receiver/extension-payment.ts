// ===== webhook-receiver/extension-payment.ts =====
// D4 (oprava 2026-10-16) — dvě pojistky webhooku:
//  1) Doplatek úpravy rezervace (type 'extension') už NEvolá confirm_payment. Ten
//     zrušenou rezervaci „oživil" (status reserved/active + paid): zákazník, který
//     zaplatil otevřený list úpravy až po zrušení (i po vrácení peněz), dostal
//     rezervaci zpět za cenu doplatku. Teď: PaymentIntent se jen uloží (když rezervace
//     žádný nemá), živé rezervaci po dřívější vratce se vrátí stav 'paid' AŽ PO zapsání
//     změny (markPaidAfterChange — nezapsaná změna se vrací a rezervace zůstává přesně
//     v původním stavu, i s 'partial_refund') a zrušená / ukončená rezervace se nemění — změnu odmítne zápis
//     (extension-apply: booking_cancelled / wrong_status) a doplatek se vrátí.
//  2) Druhá platba za rezervaci / SOS / objednávku, která už zaplacená je →
//     _shared/duplicate-payment.ts (ponechá nejdřívější stržení, ostatní vrátí).
import type { Sb } from '../_shared/extension-apply-types.ts'
import { findDuplicateCharges, refundDuplicatePayment, type StripeDupLike } from '../_shared/duplicate-payment.ts'
export { markPaidAfterChange } from '../_shared/paid-change-guard.ts'

export type ExtPrep = 'ok' | 'closed' | 'retry'

export async function prepareExtensionPayment(sb: Sb, bookingId: string, piId: string | null, sessionId: string | null): Promise<ExtPrep> {
  let bk: { status?: string; payment_status?: string; stripe_payment_intent_id?: string | null } | null = null
  try {
    const { data, error } = await sb.from('bookings').select('status, payment_status, stripe_payment_intent_id').eq('id', bookingId).maybeSingle()
    if (error) return 'retry'
    bk = data
  } catch { return 'retry' }
  if (!bk) return 'closed'
  const closed = bk.status === 'cancelled' || bk.status === 'completed'
  try {
    // Zrušené / ukončené rezervaci PI neukládat: payment_intent.succeeded bez metadat (web
    // Checkout doplatku) by ji podle uloženého PI dohledal jako platbu REZERVACE a oživil.
    if (piId && !bk.stripe_payment_intent_id && !closed) {
      await sb.from('bookings').update({ stripe_payment_intent_id: piId, ...(sessionId ? { stripe_session_id: sessionId } : {}) })
        .eq('id', bookingId).is('stripe_payment_intent_id', null)
    }
  } catch { /* best-effort — zápis změny níže rozhoduje */ }
  try {
    await sb.from('debug_log').insert({ source: 'webhook-receiver', action: 'extension_payment_received', component: 'stripe',
      status: closed ? 'warning' : 'ok', request_data: { booking_id: bookingId, payment_intent_id: piId, booking_status: bk.status } })
  } catch { /* ignore */ }
  return closed ? 'closed' : 'ok'
}

/** Řádek už zaplacený a přišla úspěšná platba → je to druhá platba za totéž? Pak vrátit
 *  všechny kromě nejdřív stržené (deterministicky — obě události obou plateb dojdou ke
 *  stejnému výsledku; Stripe idempotency klíč + zámek v debug_log vratku nezdvojí). */
export async function refundDuplicateCharges(sb: Sb, stripe: StripeDupLike, a: {
  piId: string; customer: string | null; table: 'bookings' | 'shop_orders'; refId: string; type: string
}): Promise<void> {
  try {
    const dup = await findDuplicateCharges(stripe, { piId: a.piId, customer: a.customer,
      refKey: a.table === 'bookings' ? 'booking_id' : 'order_id', refId: a.refId, type: a.type })
    if (!dup) return
    for (const r of dup.refund) {
      await refundDuplicatePayment(sb, stripe, { piId: r.id, table: a.table, refId: a.refId, keepRef: dup.keep,
        amountCzk: r.amountCzk, via: 'webhook' })
    }
  } catch { /* pojistka — chyba nesmí shodit zpracování platby */ }
}
