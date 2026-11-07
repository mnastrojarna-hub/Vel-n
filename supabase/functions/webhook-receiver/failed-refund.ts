// ===== webhook-receiver/failed-refund.ts =====
// Oprava i5 (2026-11-07, verify:refunds V2 / V3 / V9) — selhaná / zrušená NAŠE vratka v ceně rezervace (refund-updated.ts):
//  • dobropis celé vratky (stripe_refund_id = hlavní vratka) se automaticky ZMENŠÍ na to, co skutečně odešlo: hlavní
//    vratka (succeeded / pending) + živé zbytky z ostatních plateb (mg_main_refund = hlavní); 0 → dobropis zrušen.
//    Dřív zůstal celý a mail obsluze velel „Zrušte dobropis …“: bez zrušení Velín „Potvrdit vrácení“ vratku přeskočil
//    (dobropis na tutéž částku) a zákazník dostal mail o vrácení 0 Kč; po zrušení u selhaného ZBYTKU (hlavní vratka
//    odešla) nekryl dobropis už nic a recovery / Velín pak vrátily víc, než ukazovaly doklady.
//  • stará událost (Stripe doručí znovu po ne-2xx, druhý typ události, zpožděná) PO úspěšném opakování rezervaci znovu
//    neotevírá: vratka je „současná“, jen když je uloženou vratkou rezervace (nebo uložená chybí / je starší) a žádná
//    novější živá naše vratka téhož důvodu (mimo tutéž logickou vratku) ji nenahradila a uvnitř téže logické vratky není
//    živá část už ≥ cíl (mg_target — recovery selhaný zbytek dovrátila).
// Stav se čte ze Stripe znovu (ne ze snímku v události); nečitelné platby → nic se nemění (jen mail jako dřív).
import { cancellationRefundPool } from '../process-refund/cancel-once-pool.ts'
import { shrinkCreditNote } from '../process-refund/credit-note-sync.ts'
import type { StripeRefundLike } from '../process-refund/cancel-once.ts'
import type { BookingIntentsStripe } from '../_shared/booking-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
export type FailedRefundStripe = BookingIntentsStripe & { refunds: { retrieve?: (id: string) => Promise<unknown> } }
type RefundObj = { id: string; status?: string | null; amount?: number | null; created?: number | null; metadata?: Record<string, string> | null }

const live = (x: { status?: string | null } | null | undefined) => x?.status === 'succeeded' || x?.status === 'pending'

export type FailedRefundState = {
  /** všechny platby rezervace přečtené (pool úplný) */
  known: boolean
  /** Stripe ji teď vede jako selhanou / zrušenou (false = událost neodpovídá stavu ve Stripe) */
  failedNow: boolean
  mainId: string
  /** živá část logické vratky (hlavní + zbytky), haléře; null = nevím */
  liveHaleru: number | null
  /** novější vratka ji nahradila / uložená vratka rezervace je novější → neotevírat */
  superseded: boolean
}

async function retrieve(stripe: FailedRefundStripe, id: string): Promise<StripeRefundLike | null> {
  if (!stripe.refunds.retrieve) return null
  try { return (await stripe.refunds.retrieve(id)) as StripeRefundLike } catch { return null }
}

// deno-lint-ignore no-explicit-any
export async function failedRefundState(sb: Sb, stripe: FailedRefundStripe, r: RefundObj, bk: Record<string, any>): Promise<FailedRefundState> {
  const md = r.metadata || {}
  const mainId = md.mg_part === 'remainder' && md.mg_main_refund ? md.mg_main_refund : r.id
  let storedRefunds: StripeRefundLike[] | null = null
  let known = true
  if (bk.stripe_payment_intent_id) {
    try {
      storedRefunds = (await stripe.refunds.list({ payment_intent: bk.stripe_payment_intent_id, limit: 100 })).data as unknown as StripeRefundLike[]
    } catch { known = false }
  }
  const pool = await cancellationRefundPool(stripe, sb, { bookingId: bk.id, storedPiId: bk.stripe_payment_intent_id || null, storedRefunds })
  known = known && pool.complete
  const find = (id: string) => pool.refunds.find((x) => x.id === id) || null
  const fresh = find(r.id) || await retrieve(stripe, r.id)
  const failedNow = !fresh || !live(fresh)
  const main = mainId === r.id ? fresh : (find(mainId) || await retrieve(stripe, mainId))
  const liveHaleru = main ? (live(main) ? Number(main.amount || 0) : 0)
    + pool.refunds.filter((x) => x.id !== mainId && live(x) && x.metadata?.mg_main_refund === mainId).reduce((s, x) => s + Number(x.amount || 0), 0) : null
  const created = Number(fresh?.created ?? r.created ?? 0)
  const storedId = bk.stripe_refund_id || null
  const stored = storedId ? find(storedId) : null
  const current = !storedId || storedId === r.id || storedId === mainId || !stored || Number(stored.created || 0) <= created
  const reason = md.mg_reason || ''
  const newer = pool.refunds.some((x) => {
    const xm = x.metadata || {}
    return x.id !== r.id && x.id !== mainId && xm.mg_main_refund !== mainId && live(x) && xm.mg_source === 'process-refund'
      && xm.mg_booking_id === bk.id && (xm.mg_reason || '') === reason && Number(x.created || 0) > created
  })
  // selhaná část už nahrazena uvnitř TÉŽE logické vratky (recovery dovrátila zbytek, cíl snížen) → živá část ≥ mg_target
  const target = Number(main?.metadata?.mg_target)
  const redone = liveHaleru != null && Number.isFinite(target) && target > 0 && liveHaleru >= target
  return { known, failedNow, mainId, liveHaleru: known ? liveHaleru : null, superseded: !current || newer || redone }
}

/** Dobropis logické vratky (k hlavní vratce) zmenšit na živou část. Vrací { number, before, after } (after null = beze změny). */
export async function shrinkFailedRefundCreditNote(sb: Sb, a: { bookingId: string; mainId: string; refundId: string; amountKc: number; liveHaleru: number }):
  Promise<{ number: string | null; before: number; after: number | null } | null> {
  const { data } = await sb.from('invoices').select('id, number, total, items').eq('booking_id', a.bookingId).eq('type', 'credit_note')
    .neq('status', 'cancelled').in('stripe_refund_id', [...new Set([a.mainId, a.refundId])]).limit(1)
  const cn = data?.[0]
  if (!cn) return null
  const liveKc = a.liveHaleru / 100
  const after = await shrinkCreditNote(sb, {
    cnId: cn.id, cnNumber: cn.number, bookingId: a.bookingId, currentTotal: Number(cn.total || 0), targetCzk: liveKc,
    description: cn.items?.[0]?.description || 'Dobropis',
    note: liveKc > 0
      ? `Upraveno automaticky: Stripe vratka ${a.refundId} (${a.amountKc} Kč) selhala — dobropis = skutečně vrácená část ${liveKc} Kč.`
      : `Zrušeno automaticky: Stripe vratka ${a.refundId} (${a.amountKc} Kč) selhala — peníze neodešly.`,
  })
  return { number: cn.number || null, before: Math.abs(Number(cn.total || 0)), after }
}
