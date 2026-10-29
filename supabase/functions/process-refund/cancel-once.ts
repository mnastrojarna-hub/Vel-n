// HOTFIX storno 2026-10-29 — vratka storna nejvýš JEDNOU za storno rezervace.
// Dřív dostalo DRUHÉ volání téže storno vratky (send-cancellation-email po Velínu, když Stripe
// vratka čekala „pending“ nebo process-refund spadl po refunds.create; webhook charge.refunded
// doručený znovu po 30min okně claimu mailu; ruční vratka v Stripe dashboardu později) NOVÝ Stripe
// idempotency klíč (`refundable` už první vratku odečetl) a vrátilo peníze podruhé.
//  • Zámek: claim_email_send(booking, 'refund_cancellation') — souběžná storno volání téže
//    rezervace jdou po sobě (uvolní se po doběhnutí, jinak vyprší za LOCK_WINDOW_MIN).
//  • Značka: každá storno vratka nese v metadatech mg_cancel_at = bookings.cancelled_at (identita
//    storna; po obnovení a novém stornu je jiná).
//  • Kontrola: volání ze serveru (send-cancellation-email → reason 'cancellation') na storno, ke
//    kterému už naše storno vratka existuje (succeeded/pending), žádnou další nevytvoří — jen dorovná
//    stav platby a dobropis k existující vratce. Volání obsluhy z Velínu (storno i „Potvrdit vrácení“
//    = vědomá další vratka) kontrola neomezuje; jen počká na zámek.

type Md = Record<string, string | undefined>
export type StripeRefundLike = { id: string; amount: number; status: string; created: number; metadata?: Md | null }
type CnResult = { creditNoteId: string | null; pdfPath: string | null; refundId: string | null }
// deno-lint-ignore no-explicit-any
type Db = any

export const CANCEL_LOCK_SLUG = 'refund_cancellation'
const LOCK_WINDOW_MIN = 3
const LOCK_WAIT_MS = 8000
const LOCK_POLL_MS = 250
// Vratka z verze před hotfixem (bez mg_cancel_at): k tomuto stornu patří, vznikla-li nejdřív hodinu
// před bookings.cancelled_at (Velín zapisuje čas prohlížeče — tolerance posunutých hodin).
const LEGACY_SLACK_MS = 60 * 60_000

/** Identita storna = bookings.cancelled_at přesně tak, jak ho vrací PostgREST (všichni čtou týž řádek). */
export function cancelToken(cancelledAt: unknown): string {
  return typeof cancelledAt === 'string' ? cancelledAt : ''
}

/** Naše vratky TOHOTO storna (succeeded/pending), v pořadí ze Stripe (nejnovější první). */
export function priorCancellationRefunds(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): StripeRefundLike[] {
  const t = Date.parse(token)
  return (refunds || []).filter((r) => {
    const md = r.metadata || {}
    if (r.status !== 'succeeded' && r.status !== 'pending') return false
    if (md.mg_source !== 'process-refund' || md.mg_reason !== 'cancellation' || md.mg_booking_id !== bookingId) return false
    if (typeof md.mg_cancel_at === 'string') return md.mg_cancel_at === token
    return !token || !Number.isFinite(t) || Number(r.created) * 1000 >= t - LEGACY_SLACK_MS
  })
}

/** Zámek storno vratky rezervace (čeká až LOCK_WAIT_MS). false = bez zámku (RPC chybí / stále drženo). */
export async function acquireCancelLock(supabase: Db, bookingId: string): Promise<boolean> {
  const until = Date.now() + LOCK_WAIT_MS
  for (;;) {
    try {
      const { data, error } = await supabase.rpc('claim_email_send', {
        p_booking_id: bookingId, p_slug: CANCEL_LOCK_SLUG, p_window_minutes: LOCK_WINDOW_MIN,
      })
      if (error) return false
      if (data === true) return true
    } catch { return false }
    if (Date.now() >= until) return false
    await new Promise((r) => setTimeout(r, LOCK_POLL_MS))
  }
}

export async function releaseCancelLock(supabase: Db, bookingId: string): Promise<void> {
  try {
    await supabase.from('email_send_locks').delete().eq('booking_id', bookingId).eq('template_slug', CANCEL_LOCK_SLUG)
  } catch { /* vyprší samo */ }
}

/** Vratka tohoto storna už existuje → žádný nový Stripe refund; dorovnat stav + dobropis a vrátit ji. */
export async function respondExistingCancelRefund(o: {
  supabase: Db; bookingId: string; token: string; prior: StripeRefundLike; refundableHaleru: number | null
  booking: { payment_status?: string | null; stripe_refund_id?: string | null; card_brand?: string | null; card_last4?: string | null }
  createCn: (supabase: Db, bookingId: string, bk: { stripe_refund_id: string }) => Promise<CnResult>
  ensureCn: (supabase: Db, bookingId: string, bk: { stripe_refund_id: string }) => Promise<CnResult>
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown
  headers: Record<string, string>
}): Promise<Response> {
  const { supabase, bookingId, prior, booking } = o
  // process-refund spadl po refunds.create a před zápisem stavu → dopsat, co by zapsal sám.
  if (!booking.stripe_refund_id && (booking.payment_status === 'paid' || booking.payment_status === 'refund_pending')) {
    const payment_status = prior.status === 'pending' ? 'refund_pending' : (o.refundableHaleru === 0 ? 'refunded' : 'partial_refund')
    await supabase.from('bookings').update({ payment_status, stripe_refund_id: prior.id }).eq('id', bookingId)
  }
  let cn = await o.createCn(supabase, bookingId, { stripe_refund_id: prior.id })
  if (cn.creditNoteId && !cn.pdfPath) cn = await o.ensureCn(supabase, bookingId, { stripe_refund_id: prior.id })
  await o.dlog('cancellation_refund_exists', 'info', { refund_id: prior.id, refund_status: prior.status, cancel_token: o.token, credit_note_id: cn.creditNoteId })
  return new Response(JSON.stringify({
    success: true, already_refunded: true, cancellation_refund_exists: true,
    refund_id: prior.id, status: prior.status, credit_note_id: cn.creditNoteId, credit_note_pdf_path: cn.pdfPath,
    card_brand: booking.card_brand ?? null, card_last4: booking.card_last4 ?? null,
  }), { status: 200, headers: o.headers })
}
