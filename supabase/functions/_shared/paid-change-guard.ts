// ===== _shared/paid-change-guard.ts =====
// Kdy se SMÍ zaplacená změna rezervace (PaymentIntent type 'extension') ještě
// zapsat (D6, oprava 2026-10-16). Sdílí webhook-receiver, process-payment
// („dokonči předchozí zaplacenou úpravu") a complete_extension (fronta v appce).
// Bez téhle kontroly šlo starou platbu přehrát znovu: výměna motorky se po
// bezplatné výměně zpět provedla podruhé (cena + doplatek bez platby), už
// vrácený doplatek se zapsal, nebo se stará úprava přepsala přes novější stav.
//  • applied  — trvalá značka: metadata.applied_at na PaymentIntentu nebo
//               záznam s payment_ref = id platby v historii rezervace → hotovo,
//  • failed   — platbu už jednou vyhodnotil paid_change_failed (vratka/obsluha),
//  • refunded — z platby se už něco vrátilo → nic nezapisovat,
//  • stale    — platba z doby před nasazením (bez attempt_id / chg_hash) nebo
//               starší než lhůta → zapisovat automaticky nelze (jen obsluha).
import type { Sb } from './extension-apply-types.ts'

export type PiLike = {
  id: string
  created?: number | null
  metadata?: Record<string, string> | null
  latest_charge?: string | { amount_refunded?: number | null } | null
}

export type Eligibility =
  | { ok: true }
  | { ok: false; kind: 'applied' }
  | { ok: false; kind: 'failed'; reason: string; refund: string }
  | { ok: false; kind: 'refunded' }
  | { ok: false; kind: 'stale'; why: 'legacy' | 'too_old' }

type StripeLike = {
  charges?: { retrieve: (id: string) => Promise<{ amount_refunded?: number | null }> }
  paymentIntents?: { update: (id: string, p: Record<string, unknown>) => Promise<unknown> }
}

/** PaymentIntent vytvořený novým process-payment (od 2026-10-16) nese attempt_id nebo chg_hash. */
export const isNewCodePi = (md: Record<string, string> | null | undefined) => !!(md && (md.attempt_id || md.chg_hash))

/** Lhůty: process-payment „dokonči předchozí" 72 h, fronta v appce 7 dní (stejně jako appka). */
export const PREVIOUS_MAX_AGE_H = 72
export const QUEUE_MAX_AGE_H = 7 * 24

export async function paidChangeEligibility(sb: Sb, pi: PiLike, o: {
  bookingId: string; requireNewCode: boolean; maxAgeH: number | null; stripe?: StripeLike | null; nowMs?: number
}): Promise<Eligibility> {
  const md = (pi.metadata || {}) as Record<string, string>
  if (md.applied_at) return { ok: false, kind: 'applied' }
  if (await historyHasRef(sb, o.bookingId, pi.id)) return { ok: false, kind: 'applied' }
  const fail = await failureRow(sb, pi.id)
  if (fail) return { ok: false, kind: 'failed', reason: fail.reason, refund: fail.refund }
  if ((await refundedAmount(pi, o.stripe)) > 0) return { ok: false, kind: 'refunded' }
  if (o.requireNewCode && !isNewCodePi(md)) return { ok: false, kind: 'stale', why: 'legacy' }
  if (o.maxAgeH != null && pi.created) {
    const ageH = ((o.nowMs ?? Date.now()) - pi.created * 1000) / 3_600_000
    if (ageH > o.maxAgeH) return { ok: false, kind: 'stale', why: 'too_old' }
  }
  return { ok: true }
}

/** Záznam úpravy s payment_ref = id platby v historii rezervace (webhook / výměna rev.12). */
export async function historyHasRef(sb: Sb, bookingId: string, payRef: string): Promise<boolean> {
  try {
    const { data } = await sb.from('bookings').select('modification_history').eq('id', bookingId).maybeSingle()
    const h = data?.modification_history
    return Array.isArray(h) && h.some((e: Record<string, unknown> | null) => !!e && e.payment_ref === payRef)
  } catch { return false }
}

/** Už vyhodnocené trvalé selhání (paid_change_failed) — {reason, refund} prvního záznamu. */
export async function failureRow(sb: Sb, payRef: string): Promise<{ reason: string; refund: string } | null> {
  try {
    const { data } = await sb.from('debug_log').select('request_data, response_data')
      .eq('action', 'paid_change_failed').eq('request_data->>payment_ref', payRef)
      .order('created_at', { ascending: true }).limit(1)
    if (!Array.isArray(data) || data.length === 0) return null
    const rq = (data[0].request_data || {}) as Record<string, unknown>
    const rs = (data[0].response_data || {}) as Record<string, unknown>
    return { reason: String(rq.reason || 'change_failed'), refund: String(rs.refund || 'staff') }
  } catch { return null }
}

async function refundedAmount(pi: PiLike, stripe?: StripeLike | null): Promise<number> {
  const lc = pi.latest_charge
  if (lc && typeof lc === 'object') return Number(lc.amount_refunded || 0)
  if (typeof lc === 'string' && stripe?.charges) {
    try { return Number((await stripe.charges.retrieve(lc)).amount_refunded || 0) } catch { return 0 }
  }
  return 0
}

/** Trvalá značka „zapsáno" přímo na PaymentIntentu (best-effort; pojistka vedle historie). */
export async function markApplied(stripe: StripeLike | null | undefined, piId: string | null | undefined) {
  if (!stripe?.paymentIntents || !piId || !piId.startsWith('pi_')) return
  try { await stripe.paymentIntents.update(piId, { metadata: { applied_at: new Date().toISOString() } }) } catch { /* ignore */ }
}
