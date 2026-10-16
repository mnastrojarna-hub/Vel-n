// ===== process-payment/intent-guard.ts =====
// D4 (2026-10-16): nejvýš JEDEN strhnutelný PaymentIntent na rezervaci / objednávku.
//  • uložený PI (bookings/shop_orders.stripe_payment_intent_id) už zaplacený nebo
//    se zpracovává → odmítnout (`payment_in_progress`) — FAB, druhé zařízení ani
//    „Zkusit znovu" tak nestrhne podruhé, zatímco webhook ještě nedoběhl;
//  • nezaplacený PI → stejný požadavek Payment Sheetu ho znovu použije, jinak se
//    zruší (starý list na jiném zařízení už nic nestrhne);
//  • Stripe idempotency klíč na každém paymentIntents.create — ztracená odpověď
//    + automatické opakování = žádná druhá platba.
// Guard je pojistka: chyba Stripe při kontrole platbu NEblokuje (proceed).
import type Stripe from 'https://esm.sh/stripe@14'

// deno-lint-ignore no-explicit-any
type Sb = any

const LIVE = ['succeeded', 'processing', 'requires_capture']
const OPEN = ['requires_payment_method', 'requires_confirmation', 'requires_action']

/** attempt_id z appky: jedna hodnota na klepnutí „Zaplatit" (opakuje se jen při
 *  automatickém znovuodeslání po nejistém výsledku). Neplatný tvar = ignorovat. */
export function sanitizeAttemptId(v: unknown): string | null {
  return typeof v === 'string' && /^[A-Za-z0-9-]{8,64}$/.test(v) ? v : null
}

/** Prvních 16 hex SHA-256 z JSON payloadu změny (identita doplatku). */
export async function chgHash(change: unknown): Promise<string | null> {
  if (!change || typeof change !== 'object') return null
  try {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(change)))
    return Array.from(new Uint8Array(buf)).slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('')
  } catch { return null }
}

/** Stripe idempotency klíč (≤ 255 znaků). Stejný klíč = Stripe vrátí původní odpověď
 *  (i zamítnutí), proto: nová appka = attempt_id (nové klepnutí = nový klíč, jen
 *  automatické znovuodeslání téhož pokusu ho opakuje); staré appky bez attempt_id
 *  = 15s kbelík (zachytí zdvojený požadavek, ale ne vědomé „Zkusit znovu"). */
export function idempotencyKey(p: {
  type: string; refId: string; chargeCents: number; pm: string | null; attemptId: string | null; chg: string | null; nowMs?: number
}): string {
  const bucket = p.attemptId || `t${Math.floor((p.nowMs ?? Date.now()) / 15000)}`
  return `pp1:${p.type}:${p.refId}:${p.chargeCents}:${p.pm || 'sheet'}:${bucket}:${p.chg || '-'}`.slice(0, 255)
}

export type GuardResult =
  | { action: 'proceed' }
  | { action: 'refuse'; piId: string; status: string }
  | { action: 'reuse'; pi: Stripe.PaymentIntent }
  | { action: 'paid_extension'; pi: Stripe.PaymentIntent }

type StripeLike = { paymentIntents: {
  retrieve: (id: string) => Promise<Stripe.PaymentIntent>; cancel: (id: string) => Promise<Stripe.PaymentIntent>
  search?: (p: { query: string; limit?: number }) => Promise<{ data: Stripe.PaymentIntent[] }>
} }

/** Krok A (stav=live) + krok B (otevřený PI → reuse / cancel). */
export async function guardStoredIntent(stripe: StripeLike, a: {
  storedPiId: string | null | undefined; type: string; refKey: 'booking_id' | 'order_id'; refId: string
  sheet: boolean; chargeCents: number; chg: string | null; reuseOpen?: boolean
  /** jen krok A: zaplacený / zpracovávaný PI odmítnout, otevřený nechat (nerušit) */
  liveOnly?: boolean
  /** attempt_id aktuálního požadavku — otevřený PI TÉHOŽ pokusu se nikdy neruší, vrací se */
  attemptId?: string | null
  /** metadata, která musí u znovupoužitého listu sedět (due / card_rounding — dorovnání
   *  zapisuje webhook podle metadat PI, takže starý PI s jiným dorovnáním nejde použít) */
  matchMeta?: Record<string, string | undefined>
}): Promise<GuardResult> {
  const id = a.storedPiId
  if (!id || !id.startsWith('pi_')) return { action: 'proceed' }
  let pi: Stripe.PaymentIntent
  try { pi = await stripe.paymentIntents.retrieve(id) } catch { return { action: 'proceed' } }
  const md = (pi.metadata || {}) as Record<string, string>
  if (md[a.refKey] !== a.refId) return { action: 'proceed' }
  const live = (p: Stripe.PaymentIntent): GuardResult | null => {
    if (!LIVE.includes(p.status)) return null
    const pmd = (p.metadata || {}) as Record<string, string>
    if (a.type === 'extension') {
      // Původní platba rezervace (type booking) doplatku nevadí.
      if (pmd.type !== 'extension') return { action: 'proceed' }
      return p.status === 'succeeded' ? { action: 'paid_extension', pi: p } : { action: 'refuse', piId: p.id, status: p.status }
    }
    return { action: 'refuse', piId: p.id, status: p.status }
  }
  const l = live(pi)
  if (l) return l
  if (!OPEN.includes(pi.status) || a.liveOnly) return { action: 'proceed' } // canceled / jen krok A
  // Automatické znovuodeslání téhož pokusu (nejistý výsledek) → stejný PI, nic nerušit.
  if (a.reuseOpen !== false && a.attemptId && md.attempt_id === a.attemptId) return { action: 'reuse', pi }
  const metaOk = Object.entries(a.matchMeta || {}).every(([k, v]) => (md[k] || '') === (v || ''))
  if (a.reuseOpen !== false && a.sheet && pi.status === 'requires_payment_method' && pi.amount === a.chargeCents
      && String(pi.currency).toLowerCase() === 'czk' && md.type === a.type && (md.chg_hash || null) === (a.chg || null) && metaOk) {
    return { action: 'reuse', pi }
  }
  try {
    await stripe.paymentIntents.cancel(pi.id)
    return { action: 'proceed' }
  } catch {
    // Zrušení selhalo, protože se PI mezitím posunul (zákazník právě platí jinde,
    // druhé zařízení). Jakákoli živá platba (i doplatek, který právě prošel) =
    // NEzakládat nový PaymentIntent — nová úprava by byla naceněná proti stavu
    // před touto platbou a zákazník by platil dvakrát.
    try {
      const again = await stripe.paymentIntents.retrieve(pi.id)
      if (LIVE.includes(again.status)) return { action: 'refuse', piId: again.id, status: again.status }
    } catch { /* proceed */ }
    return { action: 'proceed' }
  }
}

/** Uložená karta (stržení hned) a k rezervaci/objednávce není uložený živý PI: dohledá
 *  ve Stripe nedávný zaplacený / zpracovávaný PI téhož typu (ztracená odpověď, neuložené
 *  id) → refuse. Vyhledávání Stripe je jen pojistka (zpoždění indexu ~1 min): chyba = proceed. */
export async function findRecentLiveIntent(stripe: StripeLike, a: {
  refKey: 'booking_id' | 'order_id'; refId: string; type: string; nowMs?: number
}): Promise<{ piId: string; status: string } | null> {
  if (!stripe.paymentIntents.search || !/^[0-9a-f-]{36}$/i.test(a.refId)) return null
  try {
    const since = Math.floor(((a.nowMs ?? Date.now()) - 30 * 60_000) / 1000)
    const res = await stripe.paymentIntents.search({
      query: `metadata['${a.refKey}']:'${a.refId}' AND metadata['type']:'${a.type.replace(/[^a-z_]/g, '')}' AND created>${since}`,
      limit: 10,
    })
    const hit = (res.data || []).find((p) => LIVE.includes(p.status))
    return hit ? { piId: hit.id, status: hit.status } : null
  } catch { return null }
}

/** Je PI z téhož pokusu (attempt_id) jako aktuální požadavek? */
export function sameAttempt(pi: { metadata?: Record<string, string> | null } | null | undefined, attemptId: string | null): boolean {
  return !!attemptId && !!pi && (pi.metadata || {}).attempt_id === attemptId
}

/** Uloží PI k rezervaci/objednávce (s jedním opakováním) — guard i webhook z něj vychází. */
export async function storeIntentId(sb: Sb, bookingId: string | undefined, orderId: string | undefined, piId: string) {
  const one = async (table: string, id: string) => {
    for (let i = 0; i < 2; i++) {
      try {
        const { error } = await sb.from(table).update({ stripe_payment_intent_id: piId }).eq('id', id)
        if (!error) return
      } catch { /* retry */ }
    }
    try {
      await sb.from('debug_log').insert({ source: 'process-payment', action: 'store_intent_id_failed', component: table, status: 'error',
        request_data: { id, payment_intent_id: piId } })
    } catch { /* ignore */ }
  }
  if (bookingId) await one('bookings', bookingId)
  if (orderId) await one('shop_orders', orderId)
}

/** Probíhající platba nezaplacené rezervace → cron ji 10 min neruší (SQL 20261016p2). */
export async function markCheckoutStarted(sb: Sb, bookingId: string) {
  try { await sb.from('bookings').update({ checkout_started_at: new Date().toISOString() }).eq('id', bookingId).eq('payment_status', 'unpaid') } catch { /* ignore */ }
}
