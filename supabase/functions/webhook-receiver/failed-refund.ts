// ===== webhook-receiver/failed-refund.ts =====
// Oprava i5 (2026-11-07, verify:refunds V2 / V3 / V9) — selhaná / zrušená NAŠE vratka v ceně rezervace (refund-updated.ts):
//  • dobropis celé vratky (stripe_refund_id = hlavní vratka) se automaticky ZMENŠÍ na to, co skutečně odešlo: hlavní
//    vratka (succeeded / pending) + živé zbytky z ostatních plateb (mg_main_refund = hlavní); 0 → dobropis zrušen.
//    Dřív zůstal celý a mail obsluze velel „Zrušte dobropis …“: bez zrušení Velín „Potvrdit vrácení“ vratku přeskočil
//    (dobropis na tutéž částku) a zákazník dostal mail o vrácení 0 Kč; po zrušení u selhaného ZBYTKU (hlavní vratka
//    odešla) nekryl dobropis už nic a recovery / Velín pak vrátily víc, než ukazovaly doklady.
//  • stará událost (Stripe doručí znovu po ne-2xx, druhý typ události, zpožděná) PO úspěšném opakování rezervaci znovu
//    neotevírá: nahrazená je jen OPAKOVANÁ vratka (i5r2: novější živá naše vratka téhož důvodu se stejným požadavkem
//    mg_target, ne jen „novější uložená“ / „téhož důvodu“), storno, kterému už nic nechybí (novější hlavní vratka
//    storna), nebo vratka, jejíž živá část téže logické vratky je už ≥ cíl (mg_target — recovery dovrátila zbytek).
// Stav se čte ze Stripe znovu (ne ze snímku v události); nečitelné platby → nic se nemění (jen mail jako dřív).
import { cancellationRefundPool } from '../process-refund/cancel-once-pool.ts'
import { shrinkCreditNote } from '../process-refund/credit-note-sync.ts'
import { cancellationMissingHaleru, priorCancellationRefunds, type StripeRefundLike } from '../process-refund/cancel-once.ts'
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
  const reason = md.mg_reason || ''
  // i5r2 (verify:refunds R1): novější vratka selhanou nahrazuje JEN jako její OPAKOVÁNÍ — naše, téže rezervace a důvodu,
  // ne zbytek, živá, novější a se stejným požadavkem (mg_target, jinak částka). Dřív stačila novější uložená vratka
  // rezervace / naše vratka téhož důvodu → selhaná vratka 1. zkrácení „nahrazená“ vratkou 2. úpravy o JINOU částku:
  // rezervace se neotevřela a mail obsluze místo „Chybí vrátit“ tvrdil „nahradila novější vratka“.
  const ask = Number(main?.metadata?.mg_target ?? r.amount)
  const newer = pool.refunds.some((x) => {
    const xm = x.metadata || {}
    return x.id !== r.id && x.id !== mainId && xm.mg_main_refund !== mainId && xm.mg_part !== 'remainder' && live(x)
      && xm.mg_source === 'process-refund' && xm.mg_booking_id === bk.id && (xm.mg_reason || '') === reason
      && Number(x.created || 0) > created && Number(xm.mg_target ?? x.amount) === ask
  })
  // storno: novější rozhodnutí o TOMTO stornu (nejnovější živá hlavní vratka storna vznikla po selhané) a stornu jako celku
  // nic nechybí (Velín „Potvrdit vrácení“ jiné částky, dovrácení) → nahrazeno. Starší hlavní vratka (selhalo dorovnání
  // 50 % → 100 %) nic nenahrazuje — její cíl je menší.
  let covered = false
  if (reason === 'cancellation' && md.mg_cancel_at) {
    const newest = priorCancellationRefunds(pool.refunds, bk.id, md.mg_cancel_at)[0]
    covered = !!newest && newest.id !== mainId && Number(newest.created || 0) > created
      && cancellationMissingHaleru(pool.refunds, bk.id, md.mg_cancel_at) === 0
  }
  // selhaná část už nahrazena uvnitř TÉŽE logické vratky (recovery dovrátila zbytek, cíl snížen) → živá část ≥ mg_target
  const target = Number(main?.metadata?.mg_target)
  const redone = liveHaleru != null && Number.isFinite(target) && target > 0 && liveHaleru >= target
  return { known, failedNow, mainId, liveHaleru: known ? liveHaleru : null, superseded: newer || covered || redone }
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
