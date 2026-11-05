// ===== webhook-receiver/cancel-mail-amount.ts =====
// Spojení HOTFIXU storna 2026-10-29 (pojistný storno mail z charge.refunded se skip_refund — jen text)
// s vratkou z více plateb (dev f1–f3), 2026-11-05: storno vrací hlavní vratkou + zbytkem z ostatních
// plateb rezervace, takže `charge.amount_refunded` uložené platby ≠ vratka storna (např. doplatek 115 Kč
// z 1 558 Kč) a mail, který předběhne mail z Velínu / RPC (claim 30 min), by tvrdil špatnou částku.
// Naše storno vratka nese mg_cancel_total = vráceno k tomuto stornu celkem (dřívější vratky téhož storna
// + tento požadavek, haléře; process-refund) → mail ji použije; zbytek (mg_part 'remainder') ji vezme
// z hlavní vratky (mg_main_refund). Jinak null → částka z charge jako dřív (externí vratka ze Stripe
// portálu, starší vratka bez mg_cancel_total).
type Md = Record<string, string | undefined>
export type RefundLike = { amount?: number | null; metadata?: Md | null } | null | undefined
type RefundsApi = { refunds: { retrieve: (id: string) => Promise<{ metadata?: unknown } | null> } }

const totalCzk = (md: Md | null | undefined): number | null => {
  // Oprava i1 (2026-11-05): vratka vznikla s neúplným přehledem plateb (mg_pool_incomplete) → mg_cancel_total je jen
  // z uložené platby (podhodnocený) → částka z charge jako dřív.
  if (md?.mg_pool_incomplete) return null
  const t = Number(md?.mg_cancel_total)
  return Number.isFinite(t) && t > 0 ? Math.round(t) / 100 : null
}

/** Částka storno vratky pro mail (Kč) z metadat naší vratky; null = použij charge.amount_refunded. */
export async function cancellationMailRefundCzk(stripe: RefundsApi, latest: RefundLike): Promise<number | null> {
  const md = (latest?.metadata || {}) as Md
  if (md.mg_source !== 'process-refund' || md.mg_reason !== 'cancellation') return null
  if (md.mg_part !== 'remainder') return totalCzk(md)
  if (!md.mg_main_refund) return null
  try {
    const main = await stripe.refunds.retrieve(md.mg_main_refund)
    return totalCzk((main?.metadata || null) as Md | null)
  } catch { return null }
}

/** Naše vratka je jen ČÁST větší vratky rezervace (zbytek jde z jiných plateb — mg_target > částka, nebo
 *  je sama zbytkem) → „tahle charge je celá vrácená" ≠ rezervace vrácená celá (zástupný stav webhooku). */
export function partOfLargerRefund(latest: RefundLike): boolean {
  const md = (latest?.metadata || {}) as Md
  if (md.mg_source !== 'process-refund') return false
  if (md.mg_part === 'remainder') return true
  const t = Number(md.mg_target)
  return Number.isFinite(t) && t > Number(latest?.amount || 0)
}
