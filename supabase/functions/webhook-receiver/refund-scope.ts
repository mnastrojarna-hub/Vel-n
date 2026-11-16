// ===== webhook-receiver/refund-scope.ts =====
// Oprava i3 (2026-11-07, verify:refunds V2 / V26) — charge.refunded se týká JEDNÉ platby, ne rezervace:
//  • stornoMailEligible — pojistný storno mail (send-cancellation-email se skip_refund, bere claim 'booking_cancelled'
//    na 30 min) jen k vratce TOHOTO storna: naše vratka s mg_reason 'cancellation' a mg_cancel_at = bookings.cancelled_at
//    (starší vratka bez mg_cancel_at: vznikla nejdřív LEGACY_SLACK před stornem), nebo externí vratka vzniklá po stornu.
//    Dřív šel i k vratce zkrácení / úpravy / výbavy / výměny nebo ke znovu doručené dřívější vratce: když dorazila mezi
//    commitem cancel_booking_tracked a jeho pg_net voláním, vzala claim a storno vratka se neprovedla nikdy
//    (zkrácení 500 + storno 100 % → vráceno jen 500, mail „storno, vráceno 500 Kč (20 %)“).
//  • resolveRefundBooking — rezervace i podle metadata.booking_id platby (Checkout Session) a historie úprav
//    (payment_ref), ne jen podle bookings.stripe_payment_intent_id (= poslední doplatek): externí vratka původní
//    platby se dřív ignorovala úplně.
//  • externalBookingBalanceHaleru — externí vratka (Stripe dashboard) rozhoduje o stornu podle zůstatku V CENĚ
//    rezervace přes všechny její platby (staffFullBalanceHaleru), ne podle „tahle charge je celá vrácená“: plná
//    vratka doplatku 115 Kč z 3 115 dřív rezervaci zrušila, zapsala 'refunded' a 3 000 se nevrátilo nikdy.
import { instantKey } from '../process-refund/cancel-once.ts';
import { staffFullBalanceHaleru } from '../process-refund/other-intents.ts';
import { bookingIntents, outsidePrice } from '../_shared/booking-intents.ts';
import { cancellationRefundPool } from '../process-refund/cancel-once-pool.ts';
import { stripeRefundsWithoutCnHaleru } from '../process-refund/doc-owed.ts';
/** Jako cancel-once.ts (LEGACY_SLACK_MS / CLOCK_SLACK_S). */ const LEGACY_SLACK_MS = 60 * 60_000;
const CLOCK_SLACK_MS = 2_000;
/** Smí webhook k této vratce poslat pojistný storno mail (a vzít claim mailu)? */ export function stornoMailEligible(a) {
  if (a.shouldCancel) return true;
  const md = a.latest?.metadata || {};
  const cancelMs = typeof a.cancelledAt === 'string' ? Date.parse(a.cancelledAt) : NaN;
  const createdMs = Number(a.latest?.created || 0) * 1000;
  if (md.mg_source === 'process-refund') {
    if (md.mg_reason !== 'cancellation') return false;
    if (typeof md.mg_cancel_at === 'string' && md.mg_cancel_at) {
      const k = instantKey(md.mg_cancel_at);
      return md.mg_cancel_at === a.cancelledAt || k != null && k === instantKey(a.cancelledAt);
    }
    return Number.isFinite(cancelMs) && createdMs >= cancelMs - LEGACY_SLACK_MS;
  }
  if (md.mg_source) return false // vratky mimo cenu (duplicita, nezapsaná změna, pozdní platba)
  ;
  // externí vratka (Stripe dashboard) — jen vzniklá po stornu
  return Number.isFinite(cancelMs) && createdMs > 0 && createdMs >= cancelMs - CLOCK_SLACK_MS;
}
const UUID_RX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Rezervace platby, která NENÍ uložená v bookings.stripe_payment_intent_id: metadata.booking_id platby / její Checkout
 *  Session (ne e-shop), jinak historie úprav (payment_ref pi_ / cs_). Ověří, že platba k rezervaci patří (bookingIntents)
 *  a stojí v ceně (outsidePrice — duplicita / nezapsaná změna se vrací svým flow). null = nedohledáno / mimo cenu. */ export async function resolveRefundBooking(stripe, sb, piId, select) {
  let bookingId = null;
  let via = 'metadata';
  let pi = null;
  try {
    pi = await stripe.paymentIntents.retrieve(piId);
    const md = pi?.metadata || {};
    if (md.type !== 'shop' && md.booking_id && UUID_RX.test(md.booking_id)) bookingId = md.booking_id;
  } catch  {
    return null;
  }
  const refs = [
    piId
  ];
  if (!bookingId && stripe.checkout?.sessions.list) {
    try {
      const s = (await stripe.checkout.sessions.list({
        payment_intent: piId,
        limit: 1
      }))?.data?.[0];
      const smd = s?.metadata || {};
      if (smd.type !== 'shop' && smd.booking_id && UUID_RX.test(smd.booking_id)) {
        bookingId = smd.booking_id;
        via = 'session';
      }
      if (s?.id) refs.push(s.id);
    } catch  {}
  }
  if (!bookingId) {
    for (const ref of refs){
      try {
        const { data } = await sb.from('bookings').select('id').contains('modification_history', [
          {
            payment_ref: ref
          }
        ]).limit(1);
        if (data?.[0]?.id) {
          bookingId = String(data[0].id);
          via = 'history';
          break;
        }
      } catch  {}
    }
  }
  if (!bookingId) return null;
  try {
    const { rows, history } = await bookingIntents(stripe, sb, bookingId, null);
    if (via !== 'history' && !rows.some((p)=>p.id === piId)) return null;
    if (pi && await outsidePrice(sb, bookingId, {
      ...pi,
      metadata: {
        ...pi.metadata || {},
        booking_id: bookingId
      }
    }, {
      history
    })) return null;
  } catch  {
    return null;
  }
  const { data: bk } = await sb.from('bookings').select(select).eq('id', bookingId).maybeSingle();
  return bk ? {
    booking: bk,
    via
  } : null;
}
/** Zůstatek V CENĚ rezervace přes všechny její platby (haléře) po externí vratce; null = nelze zjistit. */ export async function externalBookingBalanceHaleru(stripe, sb, a) {
  let storedPi = null;
  if (a.storedPiId) {
    try {
      storedPi = await stripe.paymentIntents.retrieve(a.storedPiId);
    } catch  {
      return null;
    }
  }
  return await staffFullBalanceHaleru(stripe, sb, {
    bookingId: a.bookingId,
    storedPi,
    storedRefunds: null
  });
}
/** Vráceno k rezervaci celkem V CENĚ (haléře, všechny její platby, bez vratek mimo cenu a e-shopu) — částka pojistného
 *  storno mailu u EXTERNÍ vratky (dřív charge.amount_refunded jen té jedné platby: storno 1558 z více plateb + 500
 *  v dashboardu → mail „1943 Kč“). null = nelze zjistit (→ částka z charge jako dřív). */ export async function bookingRefundedInPriceHaleru(stripe, sb, a) {
  try {
    const stored = a.storedPiId ? (await stripe.refunds.list({
      payment_intent: a.storedPiId,
      limit: 100
    }))?.data || [] : [];
    const pool = await cancellationRefundPool(stripe, sb, {
      bookingId: a.bookingId,
      storedPiId: a.storedPiId,
      storedRefunds: stored
    });
    return pool.complete ? stripeRefundsWithoutCnHaleru(pool.refunds, 0) : null;
  } catch  {
    return null;
  }
}
