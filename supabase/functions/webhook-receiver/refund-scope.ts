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
import { instantKey } from '../process-refund/cancel-once.ts'
import { staffFullBalanceHaleru, type OtherIntentsStripe } from '../process-refund/other-intents.ts'
import { bookingIntents, outsidePrice, type IntentLike } from '../_shared/booking-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
type Md = Record<string, string | undefined>
export type RefundLike = { id?: string; amount?: number | null; created?: number | null; metadata?: Md | null } | null | undefined

/** Jako cancel-once.ts (LEGACY_SLACK_MS / CLOCK_SLACK_S). */
const LEGACY_SLACK_MS = 60 * 60_000
const CLOCK_SLACK_MS = 2_000

/** Smí webhook k této vratce poslat pojistný storno mail (a vzít claim mailu)? */
export function stornoMailEligible(a: { shouldCancel: boolean; latest: RefundLike; cancelledAt: unknown }): boolean {
  if (a.shouldCancel) return true
  const md = (a.latest?.metadata || {}) as Md
  const cancelMs = typeof a.cancelledAt === 'string' ? Date.parse(a.cancelledAt) : NaN
  const createdMs = Number(a.latest?.created || 0) * 1000
  if (md.mg_source === 'process-refund') {
    if (md.mg_reason !== 'cancellation') return false
    if (typeof md.mg_cancel_at === 'string' && md.mg_cancel_at) {
      const k = instantKey(md.mg_cancel_at)
      return md.mg_cancel_at === a.cancelledAt || (k != null && k === instantKey(a.cancelledAt))
    }
    return Number.isFinite(cancelMs) && createdMs >= cancelMs - LEGACY_SLACK_MS
  }
  if (md.mg_source) return false // vratky mimo cenu (duplicita, nezapsaná změna, pozdní platba)
  // externí vratka (Stripe dashboard) — jen vzniklá po stornu
  return Number.isFinite(cancelMs) && createdMs > 0 && createdMs >= cancelMs - CLOCK_SLACK_MS
}

const UUID_RX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
type StripeLike = OtherIntentsStripe & {
  paymentIntents: OtherIntentsStripe['paymentIntents'] & { retrieve: (id: string) => Promise<IntentLike> }
  checkout?: { sessions: { list?: (p: Record<string, unknown>) => Promise<{ data: Array<{ id?: string; metadata?: Md | null }> }> } }
}

/** Rezervace platby, která NENÍ uložená v bookings.stripe_payment_intent_id: metadata.booking_id platby / její Checkout
 *  Session (ne e-shop), jinak historie úprav (payment_ref pi_ / cs_). Ověří, že platba k rezervaci patří (bookingIntents)
 *  a stojí v ceně (outsidePrice — duplicita / nezapsaná změna se vrací svým flow). null = nedohledáno / mimo cenu. */
export async function resolveRefundBooking(stripe: StripeLike, sb: Sb, piId: string, select: string):
  Promise<{ booking: Record<string, unknown>; via: string } | null> {
  let bookingId: string | null = null
  let via = 'metadata'
  let pi: IntentLike | null = null
  try {
    pi = await stripe.paymentIntents.retrieve(piId)
    const md = (pi?.metadata || {}) as Md
    if (md.type !== 'shop' && md.booking_id && UUID_RX.test(md.booking_id)) bookingId = md.booking_id
  } catch { return null }
  const refs = [piId]
  if (!bookingId && stripe.checkout?.sessions.list) {
    try {
      const s = (await stripe.checkout.sessions.list({ payment_intent: piId, limit: 1 }))?.data?.[0]
      const smd = (s?.metadata || {}) as Md
      if (smd.type !== 'shop' && smd.booking_id && UUID_RX.test(smd.booking_id)) { bookingId = smd.booking_id; via = 'session' }
      if (s?.id) refs.push(s.id)
    } catch { /* bez session */ }
  }
  if (!bookingId) {
    for (const ref of refs) {
      try {
        const { data } = await sb.from('bookings').select('id').contains('modification_history', [{ payment_ref: ref }]).limit(1)
        if (data?.[0]?.id) { bookingId = String(data[0].id); via = 'history'; break }
      } catch { /* PostgREST bez contains / chyba → nedohledáno */ }
    }
  }
  if (!bookingId) return null
  try {
    const { rows, history } = await bookingIntents(stripe, sb, bookingId, null)
    if (via !== 'history' && !rows.some((p) => p.id === piId)) return null
    if (pi && await outsidePrice(sb, bookingId, { ...pi, metadata: { ...(pi.metadata || {}), booking_id: bookingId } }, { history })) return null
  } catch { return null }
  const { data: bk } = await sb.from('bookings').select(select).eq('id', bookingId).maybeSingle()
  return bk ? { booking: bk as Record<string, unknown>, via } : null
}

/** Zůstatek V CENĚ rezervace přes všechny její platby (haléře) po externí vratce; null = nelze zjistit. */
export async function externalBookingBalanceHaleru(stripe: StripeLike, sb: Sb, a: { bookingId: string; storedPiId: string | null }): Promise<number | null> {
  let storedPi: IntentLike | null = null
  if (a.storedPiId) {
    try { storedPi = await stripe.paymentIntents.retrieve(a.storedPiId) } catch { return null }
  }
  return await staffFullBalanceHaleru(stripe, sb, { bookingId: a.bookingId, storedPi, storedRefunds: null })
}
