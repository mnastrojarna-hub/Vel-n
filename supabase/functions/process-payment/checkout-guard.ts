// ===== process-payment/checkout-guard.ts =====
// D4 (oprava 2026-10-16): web (hosted Checkout) — nejvýš JEDNA zaplatitelná Checkout
// Session na rezervaci / objednávku / doplatek. Dřív každé klepnutí na „Zaplatit"
// založilo novou session a starší zůstaly otevřené (dvě záložky, zpět + znovu
// zaplatit) → zaplatit šlo dvakrát a druhá platba se tiše ponechala.
// Před založením nové session:
//  • předchozí OTEVŘENOU session zrušit (checkout.sessions.expire) — stará záložka
//    pak ukáže „platnost vypršela" a nic nestrhne,
//  • předchozí DOKONČENOU (zaplacenou / ověřenou kartou), kterou webhook ještě
//    nezpracoval → odmítnout `payment_in_progress` (nic znovu neplatit),
//  • zrušení selže, protože se session mezitím dokončila → také odmítnout.
// Pojistka: výpadek Stripe při kontrole platbu NEblokuje (proceed) — případnou
// dvojí platbu pak zachytí webhook (_shared/duplicate-payment.ts, vratka).
type Sess = {
  id: string; status?: string | null; mode?: string | null; payment_status?: string | null; created?: number
  metadata?: Record<string, string> | null
  payment_intent?: string | { id?: string; status?: string; latest_charge?: unknown } | null
}
export type StripeCheckoutLike = { checkout: { sessions: {
  retrieve: (id: string, p?: Record<string, unknown>) => Promise<Sess>
  expire: (id: string) => Promise<Sess>
  list?: (p: Record<string, unknown>) => Promise<{ data: Sess[] }>
} } }

export type CheckoutGuard =
  | { action: 'proceed'; expired: string[] }
  | { action: 'refuse'; sessionId: string; status: string }

/** Dokončená session, za kterou peníze NEodešly zpět a která je čerstvá (webhook ji ještě
 *  může zpracovávat). Starší než 60 min / vrácená = vyřízená jinak → nová platba smí. */
function liveComplete(s: Sess, nowMs: number): boolean {
  if (s.status !== 'complete') return false
  const pi = s.payment_intent && typeof s.payment_intent === 'object' ? s.payment_intent : null
  const ch = pi && pi.latest_charge && typeof pi.latest_charge === 'object'
    ? pi.latest_charge as { amount_refunded?: number; created?: number } : null
  if (ch && Number(ch.amount_refunded || 0) > 0) return false
  const at = Number(ch?.created || s.created || 0) * 1000
  return !at || nowMs - at < 60 * 60_000
}

async function settle(stripe: StripeCheckoutLike, s: Sess, nowMs: number): Promise<'expired' | 'refuse' | 'skip'> {
  if (liveComplete(s, nowMs)) return 'refuse'
  if (s.status !== 'open') return 'skip'
  try {
    await stripe.checkout.sessions.expire(s.id)
    return 'expired'
  } catch {
    // Zrušit nejde, protože ji zákazník právě dokončil (jiná záložka) → neplatit znovu.
    try {
      const again = await stripe.checkout.sessions.retrieve(s.id, { expand: ['payment_intent.latest_charge'] })
      if (liveComplete(again, nowMs)) return 'refuse'
    } catch { /* proceed */ }
    return 'skip'
  }
}

/** Uložená session řádku (bookings / shop_orders.stripe_session_id). */
export async function settleStoredSession(stripe: StripeCheckoutLike, sessionId: string | null | undefined,
  nowMs = Date.now()): Promise<CheckoutGuard> {
  if (!sessionId || !sessionId.startsWith('cs_')) return { action: 'proceed', expired: [] }
  let s: Sess
  try { s = await stripe.checkout.sessions.retrieve(sessionId, { expand: ['payment_intent.latest_charge'] }) }
  catch { return { action: 'proceed', expired: [] } }
  const r = await settle(stripe, s, nowMs)
  if (r === 'refuse') return { action: 'refuse', sessionId: s.id, status: String(s.status || '') }
  return { action: 'proceed', expired: r === 'expired' ? [s.id] : [] }
}

/** Session bez uloženého id (doplatek úpravy z webu): dohledá otevřené / čerstvě dokončené
 *  session téhož typu a téže rezervace / objednávky (zákazník, posledních 24 h). */
export async function settleMatchingSessions(stripe: StripeCheckoutLike, a: {
  customerId: string | null; refKey: 'booking_id' | 'order_id'; refId: string; type: string; nowMs?: number
  /** dokončená session už zpracovaná (doplatek zapsaný / vyhodnocený) → neblokuje další úpravu */
  settled?: (piId: string | null, piMeta: Record<string, string>, sessionId: string) => Promise<boolean>
}): Promise<CheckoutGuard> {
  const list = stripe.checkout.sessions.list
  if (!list) return { action: 'proceed', expired: [] }
  const nowMs = a.nowMs ?? Date.now()
  const base: Record<string, unknown> = { created: { gte: Math.floor(nowMs / 1000) - 24 * 3600 }, limit: 100 }
  if (a.customerId) base.customer = a.customerId
  const mine = (s: Sess) => (s.metadata || {})[a.refKey] === a.refId && ((s.metadata || {}).type || '') === a.type
  const expired: string[] = []
  try {
    const done = await list.call(stripe.checkout.sessions, { ...base, status: 'complete', expand: ['data.payment_intent.latest_charge'] })
    for (const s of (done.data || []).filter((x) => mine(x) && liveComplete(x, nowMs))) {
      const pi = s.payment_intent && typeof s.payment_intent === 'object' ? s.payment_intent as { id?: string; metadata?: Record<string, string> } : null
      const piId = pi?.id || (typeof s.payment_intent === 'string' ? s.payment_intent : null)
      if (a.settled && await a.settled(piId, pi?.metadata || {}, s.id)) continue
      return { action: 'refuse', sessionId: s.id, status: 'complete' }
    }
    const open = await list.call(stripe.checkout.sessions, { ...base, status: 'open' })
    for (const s of (open.data || []).filter(mine)) {
      const r = await settle(stripe, s, nowMs)
      if (r === 'refuse') return { action: 'refuse', sessionId: s.id, status: 'complete' }
      if (r === 'expired') expired.push(s.id)
    }
  } catch { /* pojistka — Stripe nedostupný → proceed */ }
  return { action: 'proceed', expired }
}

