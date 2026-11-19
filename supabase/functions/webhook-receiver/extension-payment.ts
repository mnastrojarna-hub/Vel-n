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
import { findDuplicateCharges, refundDuplicatePayment } from '../_shared/duplicate-payment.ts';
export { markPaidAfterChange } from '../_shared/paid-change-guard.ts';
export async function prepareExtensionPayment(sb, bookingId, piId, sessionId) {
  let bk = null;
  try {
    const { data, error } = await sb.from('bookings').select('status, payment_status, stripe_payment_intent_id').eq('id', bookingId).maybeSingle();
    if (error) return 'retry';
    bk = data;
  } catch  {
    return 'retry';
  }
  if (!bk) return 'closed';
  const closed = bk.status === 'cancelled' || bk.status === 'completed';
  try {
    // Zrušené / ukončené rezervaci PI neukládat: payment_intent.succeeded bez metadat (web
    // Checkout doplatku) by ji podle uloženého PI dohledal jako platbu REZERVACE a oživil.
    if (piId && !bk.stripe_payment_intent_id && !closed) {
      await sb.from('bookings').update({
        stripe_payment_intent_id: piId,
        ...sessionId ? {
          stripe_session_id: sessionId
        } : {}
      }).eq('id', bookingId).is('stripe_payment_intent_id', null);
    }
  } catch  {}
  try {
    await sb.from('debug_log').insert({
      source: 'webhook-receiver',
      action: 'extension_payment_received',
      component: 'stripe',
      status: closed ? 'warning' : 'ok',
      request_data: {
        booking_id: bookingId,
        payment_intent_id: piId,
        booking_status: bk.status
      }
    });
  } catch  {}
  return closed ? 'closed' : 'ok';
}
/** Řádek už zaplacený a přišla úspěšná platba → je to druhá platba za totéž? Pak vrátit
 *  všechny kromě nejdřív stržené (deterministicky — obě události obou plateb dojdou ke
 *  stejnému výsledku; Stripe idempotency klíč + zámek v debug_log vratku nezdvojí). */ export async function refundDuplicateCharges(sb, stripe, a) {
  try {
    const dup = await findDuplicateCharges(stripe, {
      piId: a.piId,
      customer: a.customer,
      refKey: a.table === 'bookings' ? 'booking_id' : 'order_id',
      refId: a.refId,
      type: a.type
    });
    if (!dup) return;
    for (const r of dup.refund){
      await refundDuplicatePayment(sb, stripe, {
        piId: r.id,
        table: a.table,
        refId: a.refId,
        keepRef: dup.keep,
        amountCzk: r.amountCzk,
        via: 'webhook'
      });
    }
  } catch  {}
}
