// ===== _shared/charge-rounding.ts =====
// D1/D2 (oprava 2026-10-16): dorovnání platby kartou se do ceny zapisuje AŽ PO
// úspěšné platbě (webhook-receiver), ne při vytvoření PaymentIntentu. Opuštěná
// platba (zavřený platební list, jiná částka s upsellem, přecenění ve Velínu) tak
// nikdy nezanechá v ceně dorovnání, které se nestrhlo.
// process-payment dává do metadat PaymentIntentu / Checkout Session:
//   due           = cena řádku (bookings.total_price / shop_orders.total), ze které
//                   se dorovnání počítalo,
//   card_rounding = r (+ dorovnání na 15 Kč, ± rozdíl platby v celých Kč).
// Zápis je compare-and-set: projde jen proti řádku s cenou `due` (nezaplacenému,
// nebo už potvrzenému touto platbou při opakování události) — cena + r
// a card_rounding + r v témže UPDATE. Opakovaná událost (Stripe retry,
// checkout.session.completed + payment_intent.succeeded) → 'already'. Jiná cena
// → 'mismatch' (zaplaceno ≠ cena, debug_log pro obsluhu), platba se potvrdí i tak.
// 'error' (výpadek DB) → webhook vrátí 500 a Stripe událost zopakuje.
import type { Sb } from './extension-apply-types.ts'
import { round2, logDebug } from './extension-apply-types.ts'

export type ChargeRoundingResult = 'none' | 'applied' | 'already' | 'mismatch' | 'unavailable' | 'error'

const missingCol = (e: { code?: string | null; message?: string | null } | null | undefined) =>
  /42703|PGRST204|card_rounding/i.test(`${e?.code || ''} ${e?.message || ''}`)

export async function applyChargeRounding(sb: Sb, a: {
  table: 'bookings' | 'shop_orders'; id: string; md: Record<string, string | undefined> | null | undefined; payRef: string
}): Promise<ChargeRoundingResult> {
  const md = a.md || {}
  const r = round2(Number(md.card_rounding || 0))
  const due = round2(Number(md.due))
  if (!r || md.due == null || !Number.isFinite(due)) return 'none'
  const totalCol = a.table === 'bookings' ? 'total_price' : 'total'
  const okStatus = a.table === 'bookings' ? ['unpaid', 'paid'] : ['pending', 'paid']
  const log = (action: string, status: string, extra: Record<string, unknown> = {}) =>
    logDebug(sb, action, status, { table: a.table, id: a.id, due, card_rounding: r, payment_ref: a.payRef, ...extra })
  for (let pass = 0; pass < 2; pass++) {
    const { data: row, error } = await sb.from(a.table).select(`${totalCol}, card_rounding, payment_status`).eq('id', a.id).maybeSingle()
    if (error) {
      if (missingCol(error)) { await log('card_rounding_unavailable', 'error'); return 'unavailable' }
      return 'error'
    }
    if (!row) return 'error'
    const t0 = round2(Number(row[totalCol] ?? 0))
    const c0 = round2(Number(row.card_rounding ?? 0))
    if (t0 === round2(due + r)) return 'already'
    if (!okStatus.includes(String(row.payment_status)) || t0 !== due) {
      await log('card_rounding_mismatch', 'error', { current_total: t0, payment_status: row.payment_status })
      return 'mismatch'
    }
    const { data: upd, error: uErr } = await sb.from(a.table)
      .update({ [totalCol]: round2(due + r), card_rounding: round2(c0 + r) })
      .eq('id', a.id).eq(totalCol, t0).eq('card_rounding', c0).eq('payment_status', row.payment_status).select('id')
    if (uErr) return missingCol(uErr) ? 'unavailable' : 'error'
    if (Array.isArray(upd) && upd.length === 1) { await log('card_rounding_applied', 'ok'); return 'applied' }
    // souběh (druhá událost téže platby) → načíst znovu
  }
  return 'error'
}
