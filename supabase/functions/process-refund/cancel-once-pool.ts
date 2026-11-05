// ===== process-refund/cancel-once-pool.ts =====
// Spojení HOTFIXU storna 2026-10-29 (cancel-once.ts — storno vratka nejvýš jednou za storno) s vratkou
// z více plateb rezervace (dev f1–f3: mainSource / staffFullBalanceHaleru / refundRemainder), 2026-11-05.
// Storno může vrátit z jiné platby než z uložené (bookings.stripe_payment_intent_id): hlavní vratka
// z nejstarší platby v ceně (retarget) a zbytek z ostatních plateb. Kontrola „už vráceno pro toto
// storno" jen nad vratkami uložené platby by takovou vratku neviděla → druhé volání (send-cancellation-
// email po Velínu, trigger, retry) by vrátilo podruhé. Proto:
//  • cancellationRefundPool — vratky VŠECH plateb rezervace (uložená + search + historie úprav, i vyčerpané),
//    nejnovější první; chyba čtení ostatních plateb → jen uložená platba (chování hotfixu) + `complete: false`,
//  • completeCancelRemainder — dorovnání po pádu mezi hlavní vratkou a zbytkem: dovrátí nevrácený zbytek
//    TÉHOŽ storna do mg_target (požadavek zapsaný na hlavní vratce) stejnou cestou jako process-refund
//    (refundRemainder: idempotency klíč dle hlavní vratky, odečte už vrácené) a dobropis k hlavní vratce
//    dorovná nahoru (reconcileCreditNote; PDF přegeneruje ensureCreditNotePdf). Bez mg_target nic (hotfix).
import { bookingIntents, type BookingIntentsStripe } from '../_shared/booking-intents.ts'
import { refundRemainder } from './other-intents.ts'
import { reconcileCreditNote } from './credit-note-sync.ts'
import { cancelTargetHaleru, cancellationMissingHaleru, cancellationRefundedHaleru, logicalRefundHaleru, openCancelMains, type StripeRefundLike } from './cancel-once.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
export type RefundPool = { refunds: StripeRefundLike[]; complete: boolean; error: string | null }
/** Stripe i s refunds.update (snížení cíle staré hlavní vratky) — volitelné kvůli starším fake klientům. */
export type PoolStripe = BookingIntentsStripe & { refunds: { update?: (id: string, p: Record<string, unknown>) => Promise<unknown> } }
type Dlog = (action: string, status: string, extra?: Record<string, unknown>) => unknown

/** Oprava i1 (2026-11-05): stará hlavní vratka s nedokončeným zbytkem, který už mezitím pokrylo jiné rozhodnutí
 *  (vědomá vratka obsluhy / nižší cíl) → cíl snížit na skutečně vrácené, ať ji recovery nepovažuje za otevřenou.
 *  mg_cancel_total = vráceno k tomuto stornu celkem (jen text pojistného mailu). */
async function closeStaleMain(stripe: PoolStripe, a: { main: StripeRefundLike; pool: StripeRefundLike[]; bookingId: string; token: string; dlog: Dlog; why: string }): Promise<void> {
  const done = logicalRefundHaleru(a.main, a.pool)
  const total = cancellationRefundedHaleru(a.pool, a.bookingId, a.token)
  try {
    if (!stripe.refunds.update) throw new Error('refunds.update unavailable')
    await stripe.refunds.update(a.main.id, { metadata: { mg_target: String(done), mg_cancel_total: String(total) } })
    await a.dlog('cancellation_remainder_stale_closed', 'info', { refund_id: a.main.id, target_haleru: cancelTargetHaleru(a.main), done_haleru: done, why: a.why })
  } catch (e) {
    await a.dlog('cancellation_remainder_stale_close_failed', 'error', { refund_id: a.main.id, error: (e as Error).message, why: a.why })
  }
}

/** Obsluha vědomě vrací další částku téhož storna (prošla kontrolou duplicity) → starší hlavní vratky s nedokončeným
 *  zbytkem uzavřít (jejich zbytek by jinak recovery dovrátila vedle vratky obsluhy — oprava i1 2026-11-05). */
export async function closeStaleCancelMains(stripe: PoolStripe, a: { bookingId: string; pool: StripeRefundLike[]; token: string; dlog: Dlog }): Promise<number> {
  const open = openCancelMains(a.pool, a.bookingId, a.token)
  for (const m of open) await closeStaleMain(stripe, { ...a, main: m, why: 'admin_refund' })
  return open.length
}

const piOf = (r: { payment_intent?: unknown }): string | null =>
  typeof r.payment_intent === 'string' ? r.payment_intent : ((r.payment_intent as { id?: string } | null)?.id ?? null)

/** Vratky všech plateb rezervace, nejnovější první (Stripe `created`). */
export async function cancellationRefundPool(stripe: BookingIntentsStripe, sb: Sb, a: {
  bookingId: string; storedPiId: string | null; storedRefunds: StripeRefundLike[] | null
}): Promise<RefundPool> {
  const pool: StripeRefundLike[] = (a.storedRefunds || []).map((r) => ({ ...r, payment_intent: piOf(r) ?? a.storedPiId }))
  let complete = true, error: string | null = null
  try {
    const { rows } = await bookingIntents(stripe, sb, a.bookingId, a.storedPiId)
    for (const p of rows) {
      const rl = await stripe.refunds.list({ payment_intent: p.id, limit: 100 })
      for (const r of (rl?.data || []) as unknown as StripeRefundLike[]) pool.push({ ...r, payment_intent: piOf(r) ?? p.id })
    }
  } catch (e) {
    complete = false; error = (e as Error).message
    console.warn('[process-refund] cancellation refund pool (other payments) failed:', error)
  }
  const seen = new Set<string>()
  const refunds = pool.filter((r) => !seen.has(r.id) && !!seen.add(r.id))
    .sort((x, y) => (Number(y.created || 0) - Number(x.created || 0)) || (x.id < y.id ? 1 : -1))
  return { refunds, complete, error }
}

/** Dovrátí nevrácený zbytek storna `main` do mg_target; vrací haléře vrácené TEĎ (0 = nic; stav + dobropis se dorovnají).
 *  Oprava i1 (2026-11-05): dovrací se jen to, co stornu JAKO CELKU chybí (cíl = mg_cancel_total nejnovější hlavní
 *  vratky — pozdější vědomá vratka obsluhy zbytek staré vratky pokryla); nic nechybí → starou vratku uzavřít.
 *  Neúplný pool (ostatní platby nečitelné) → nedovracet (chyběl by přehled, co už se vrátilo). */
export async function completeCancelRemainder(stripe: PoolStripe, sb: Sb, a: {
  bookingId: string; main: StripeRefundLike; pool: StripeRefundLike[]; token: string; poolComplete?: boolean; dlog: Dlog
}): Promise<number> {
  const target = cancelTargetHaleru(a.main)
  const done = logicalRefundHaleru(a.main, a.pool)
  if (target == null || done >= target) return 0
  if (a.poolComplete === false) {
    await a.dlog('cancellation_remainder_skipped_pool_incomplete', 'error', { refund_id: a.main.id, target_haleru: target, done_haleru: done })
    return 0
  }
  const missing = cancellationMissingHaleru(a.pool, a.bookingId, a.token)
  const want = missing == null ? target - done : Math.min(target - done, missing)
  if (want <= 0) {
    await closeStaleMain(stripe, { main: a.main, pool: a.pool, bookingId: a.bookingId, token: a.token, dlog: a.dlog, why: 'goal_reached' })
    return 0
  }
  const extra = await refundRemainder(stripe, sb, {
    // refundRemainder odečte, co se k této hlavní vratce už vrátilo (done − hlavní) → požadavek = to + chybějící
    bookingId: a.bookingId, mainPi: piOf(a.main), mainRefundId: a.main.id, remainingHaleru: want + (done - Number(a.main.amount || 0)),
    reason: 'cancellation', metadata: { mg_cancel_at: a.token },
  })
  const fresh = extra.refunds.reduce((s, x) => s + x.amountHaleru, 0)
  await a.dlog('cancellation_remainder_completed', extra.error ? 'error' : 'info', {
    refund_id: a.main.id, target_haleru: target, before_haleru: done, wanted_haleru: want, missing_haleru: missing, refunded_now_haleru: fresh,
    extra: extra.refunds, left_haleru: extra.leftHaleru, error: extra.error || null,
  })
  if (!(fresh > 0)) return 0
  try {
    const { data } = await sb.from('invoices').select('id, number, total, items, notes')
      .eq('booking_id', a.bookingId).eq('type', 'credit_note').eq('stripe_refund_id', a.main.id).neq('status', 'cancelled').limit(1)
    const cn = data?.[0]
    if (cn) {
      const fixed = await reconcileCreditNote(sb, { cnId: cn.id, cnNumber: cn.number, bookingId: a.bookingId, currentTotal: Number(cn.total || 0),
        targetCzk: (done + fresh) / 100, description: cn.items?.[0]?.description || 'Dobropis – Storno rezervace', reasonText: 'Storno rezervace',
        notes: `${cn.notes || ''} Vráceno z více plateb: ${a.main.id} + ${extra.refunds.map((x) => x.refundId).join(', ')}.`.trim(),
        issueDate: new Date().toISOString().slice(0, 10) })
      // PDF s dorovnanou částkou vyrobí ensureCreditNotePdf (respondExistingCancelRefund → ensureCn)
      if (fixed != null) await sb.from('invoices').update({ pdf_path: null }).eq('id', cn.id)
    }
  } catch (e) {
    await a.dlog('credit_note_reconcile_failed', 'error', { refund_id: a.main.id, error: (e as Error).message })
  }
  return fresh
}
