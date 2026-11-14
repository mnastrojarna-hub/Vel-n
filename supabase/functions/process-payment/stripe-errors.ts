// ===== process-payment/stripe-errors.ts =====
// D4/D5 (2026-10-16): chyba Stripe / serveru → stabilní kód + český text bez
// anglického znění Stripe (to jde jen do debug_log a pole `stripe_code`).
import { CS } from './refusals.ts'

export type MappedError = { status: number; code: string; error: string; stripe_code: string | null }

export function mapStripeError(err: unknown): MappedError {
  const e = (err || {}) as { type?: string; rawType?: string; code?: string; statusCode?: number; raw?: { type?: string; code?: string } }
  const type = String(e.type || e.rawType || e.raw?.type || '')
  const code = String(e.code || e.raw?.code || '')
  const status = Number(e.statusCode || 0)
  const stripeCode = code || type || null
  if (code === 'amount_too_small') {
    return { status: 400, code: 'below_minimum', error: CS.below_minimum_generic, stripe_code: stripeCode }
  }
  if (type === 'StripeIdempotencyError' || type === 'idempotency_error' || code === 'idempotency_key_in_use' || code === 'idempotency_error') {
    return { status: 409, code: 'duplicate_request', error: CS.duplicate_request, stripe_code: stripeCode }
  }
  if (['StripeRateLimitError', 'StripeConnectionError', 'StripeAPIError', 'api_error', 'api_connection_error', 'rate_limit_error'].includes(type)
      || code === 'rate_limit' || code === 'lock_timeout' || status >= 500 || status === 429) {
    return { status: 503, code: 'stripe_unavailable', error: CS.stripe_unavailable, stripe_code: stripeCode }
  }
  return { status: 500, code: 'server_error', error: CS.server_error, stripe_code: stripeCode }
}

/** Chyba PO odeslání požadavku (spojení přerušené, 5xx Stripe, neznámá síťová chyba):
 *  výsledek stržení NENÍ jistý — karta mohla být stržena. (Neplatný požadavek, idempotence,
 *  karetní zamítnutí jisté jsou.) */
export function isUncertainStripeError(err: unknown): boolean {
  const e = (err || {}) as { type?: string; rawType?: string; statusCode?: number; raw?: { type?: string } }
  const type = String(e.type || e.rawType || e.raw?.type || '')
  const status = Number(e.statusCode || 0)
  if (['StripeConnectionError', 'StripeAPIError', 'api_error', 'api_connection_error'].includes(type)) return true
  if (status >= 500) return true
  // Nezařazená výjimka bez typu Stripe (fetch failed, timeout) = nejisté
  return !type && !status
}
