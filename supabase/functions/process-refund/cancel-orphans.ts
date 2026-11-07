// ===== process-refund/cancel-orphans.ts =====
// Oprava i5 (2026-11-07, verify:refunds V1): storno vratka z více plateb, jejíž HLAVNÍ vratka selhala (Stripe 'failed' /
// 'canceled'), ale zbytek z jiné platby odešel (osiřelý zbytek — cancel-once.ts orphanCancelRemainders). Dřív ho
// kontrola „už vráceno k tomuto stornu“ nevěděla: opakované volání služby (send-cancellation-email, trigger, webhook)
// vrátilo celé storno znovu (zbytek podruhé) a částky v mailu / booking_cancellations ho vynechaly. Teď:
//  • orphanCoverHaleru — kolik osiřelé zbytky k tomuto stornu už vrátily (haléře),
//  • služba vrací jen nepokrytý rozdíl požadavku (process-refund/index.ts); pokryly-li celý požadavek, žádná nová
//    vratka — respondOrphanCancelRefund jen dorovná stav ('refund_pending' → 'refunded' / 'partial_refund') a odpoví
//    jako existující storno vratka (dobropis = dobropis hlavní vratky, webhook ho po selhání zmenšil na živou část).
//  • obsluha (Velín) dál vrací zvolenou částku NAVÍC (otevřené rozhodnutí P2), jen se správným součtem.
import { cancellationRefundedHaleru, hasLiveManualCreditNote, orphanCancelRemainders, type StripeRefundLike } from './cancel-once.ts'

// deno-lint-ignore no-explicit-any
type Db = any

/** Osiřelé zbytky TOHOTO storna a jejich součet (haléře). */
export function orphanCoverHaleru(refunds: StripeRefundLike[] | null | undefined, bookingId: string, token: string): { sumHaleru: number; orphans: StripeRefundLike[] } {
  const orphans = orphanCancelRemainders(refunds, bookingId, token)
  return { sumHaleru: orphans.reduce((s, r) => s + Number(r.amount || 0), 0), orphans }
}

/** Požadavek služby je celý pokryt osiřelými zbytky → žádná nová vratka; stav + odpověď. */
export async function respondOrphanCancelRefund(o: {
  supabase: Db; bookingId: string; token: string; refunds: StripeRefundLike[]; orphans: StripeRefundLike[]
  /** co po vratkách zbývá na platbách V CENĚ rezervace (haléře; null = nevím) */
  remaining: () => Promise<number | null>
  dlog: (action: string, status: string, extra?: Record<string, unknown>) => unknown
  headers: Record<string, string>
}): Promise<Response> {
  const { supabase, bookingId } = o
  const first = o.orphans[0]
  const sum = o.orphans.reduce((s, r) => s + Number(r.amount || 0), 0)
  const done = cancellationRefundedHaleru(o.refunds, bookingId, o.token)
  const { data: cur } = await supabase.from('bookings').select('payment_status, card_brand, card_last4').eq('id', bookingId).maybeSingle()
  let repaired = false
  const pending = o.orphans.some((r) => r.status === 'pending')
  if (cur?.payment_status === 'refund_pending' && !pending && !(await hasLiveManualCreditNote(supabase, bookingId))) {
    const left = await o.remaining().catch(() => null)
    const { data: upd } = await supabase.from('bookings').update({ payment_status: left === 0 ? 'refunded' : 'partial_refund' })
      .eq('id', bookingId).eq('payment_status', 'refund_pending').select('id')
    repaired = Array.isArray(upd) && upd.length > 0
  }
  let cn: { id?: string; pdf_path?: string | null } | null = null
  try {
    const ids = [...new Set(o.orphans.flatMap((r) => [String(r.metadata?.mg_main_refund || ''), r.id]).filter(Boolean))]
    const { data } = await supabase.from('invoices').select('id, pdf_path').eq('booking_id', bookingId).eq('type', 'credit_note')
      .neq('status', 'cancelled').in('stripe_refund_id', ids).limit(1)
    cn = data?.[0] || null
  } catch { /* bez dobropisu */ }
  await o.dlog('cancellation_orphan_remainders_cover', 'info', { refund_id: first?.id ?? null, orphan_haleru: sum, cancel_refunded_haleru: done, repaired })
  return new Response(JSON.stringify({
    success: true, already_refunded: true, cancellation_refund_exists: true, refund_id: first?.id ?? null, status: first?.status ?? null,
    credit_note_id: cn?.id ?? null, credit_note_pdf_path: cn?.pdf_path ?? null, card_brand: cur?.card_brand ?? null, card_last4: cur?.card_last4 ?? null,
    refunded_haleru: sum, target_haleru: null, cancel_refunded_haleru: done, cancel_goal_haleru: null, refund_deferred: false,
    cancel_refunded_total: done / 100,
  }), { status: 200, headers: o.headers })
}
