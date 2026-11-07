// ===== process-refund/refunded-check.ts =====
// Oprava i6r1 (2026-11-07, verify:refunds W3) — Velín „Potvrdit vrácení“ s částkou u zrušené KARTOVÉ rezervace ve stavu
// 'refunded'. Dřív process-refund slepě odpověděl „už vráceno“ a Velín poslal zákazníkovi mail „X Kč vráceno“. Stav ale
// mohl být nepravdivý: kartová vratka selhala (webhook zrušil její dobropis) a „Vratka odeslána“ ze zastaralé stránky
// (nebo starší Velín během nasazení) sečetla dobropisy z doby před selháním → 'refunded', ačkoli kartou neodešlo nic.
// Teď se sečte, co se k TOMUTO stornu opravdu vrátilo: naše storno vratky všech plateb (cancellationRefundedHaleru, vč.
// osiřelých zbytků) + externí vratky ze Stripe dashboardu po stornu (bez mg_source) + ruční dobropisy storna (převodem).
// Méně než požadavek (tolerance 1 Kč) → chyba s vysvětlením; Velín ji ukáže a mail neodejde. Nečitelné → jako dřív.
import { cancellationRefundPool } from './cancel-once-pool.ts'
import { cancellationRefundedHaleru, type StripeRefundLike } from './cancel-once.ts'
import type { BookingIntentsStripe } from '../_shared/booking-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
const SLACK_MS = 120_000 // dobropis / vratka storna vznikly nejdřív 2 min před cancelled_at (Velín: čas prohlížeče)
const live = (r: StripeRefundLike) => r.status === 'succeeded' || r.status === 'pending'

/** Vráceno k tomuto stornu (haléře): karta (naše + externí po stornu) + ruční dobropisy storna; null = nelze zjistit. */
export async function stornoRefundedHaleru(stripe: BookingIntentsStripe, sb: Sb, a: {
  bookingId: string; storedPiId: string; token: string
}): Promise<{ card: number; manual: number } | null> {
  const since = Date.parse(a.token)
  if (!Number.isFinite(since)) return null
  try {
    const stored = (await stripe.refunds.list({ payment_intent: a.storedPiId, limit: 100 })).data as unknown as StripeRefundLike[]
    const pool = await cancellationRefundPool(stripe, sb, { bookingId: a.bookingId, storedPiId: a.storedPiId, storedRefunds: stored })
    if (!pool.complete) return null
    const ours = cancellationRefundedHaleru(pool.refunds, a.bookingId, a.token)
    const ext = pool.refunds.filter((r) => live(r) && !r.metadata?.mg_source && Number(r.created || 0) * 1000 >= since - SLACK_MS)
      .reduce((s, r) => s + Number(r.amount || 0), 0)
    const { data, error } = await sb.from('invoices').select('total').eq('booking_id', a.bookingId).eq('type', 'credit_note')
      .neq('status', 'cancelled').is('stripe_refund_id', null).gte('created_at', new Date(since - SLACK_MS).toISOString())
    if (error) return null
    const manual = (data || []).reduce((s: number, c: { total?: unknown }) => s + Math.round(Math.abs(Number(c.total) || 0) * 100), 0)
    return { card: ours + ext, manual }
  } catch { return null }
}

/** 'refunded' neodpovídá vratkám storna → odpověď 409 (nic se nevrací ani neposílá); null = v pořádku / nelze ověřit. */
export async function refundedStatusMismatch(stripe: BookingIntentsStripe, sb: Sb, a: {
  bookingId: string; storedPiId: string; token: string; amountHaleru: number
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown; headers: Record<string, string>
}): Promise<Response | null> {
  const got = await stornoRefundedHaleru(stripe, sb, a)
  if (!got || got.card + got.manual + 100 >= a.amountHaleru) return null
  const kc = (h: number) => Math.round(h) / 100
  await a.dlog('refunded_status_mismatch', 'error', { requested_haleru: a.amountHaleru, card_haleru: got.card, manual_haleru: got.manual })
  return new Response(JSON.stringify({
    success: false, code: 'refunded_status_mismatch', refunded_total: kc(got.card + got.manual),
    error: `Rezervace je vedená jako „Vráceno“, ale k tomuto stornu se vrátilo jen ${kc(got.card + got.manual)} Kč z ${kc(a.amountHaleru)} Kč `
      + `(kartou ${kc(got.card)} Kč, převodem ${kc(got.manual)} Kč) — kartová vratka zřejmě selhala. Nic se nevrátilo ani neodeslalo: `
      + `chybějících ${kc(a.amountHaleru - got.card - got.manual)} Kč vraťte ve Stripe dashboardu (platba rezervace → Refund).`,
  }), { status: 409, headers: a.headers })
}
