// ===== process-refund/doc-owed.ts =====
// Oprava i3 (2026-11-07, verify:refunds V1 / V36) — co rezervaci dle DOKLADŮ ještě dlužíme a kolik z toho
// patří k části zaplacené mimo Stripe (převod / QR):
//  • docsOwedCzk = PŘESNĚ jako DB trigger _cap_refund_to_paid: Σ živých DP (payment_receipt) − Σ živých dobropisů.
//    i2 počítal total_price − Σ dobropisů: snížení ceny (zkrácení, levnější motorka, odebraná výbava) sníží
//    total_price A vystaví dobropis → odečteno dvakrát (QR 3000, zkrácení 500, storno 100 % → dobropis jen 2000).
//    Bez DP (trigger neořezává) → null = volající použije strop jako před i2 (total_price).
//  • stripeRefundsWithoutCnHaleru = vratky Stripe V CENĚ rezervace, ke kterým dobropis není (vratka v dashboardu,
//    spadlý zápis dobropisu) — peníze odešly, doklady o nich nevědí → o tolik méně „dlužíme převodem“.
//  • bankPaidCzk = doložené příchozí platby převodem (fio_transactions dle booking_id / payment_vs / mod_surcharge_vs).
// deno-lint-ignore no-explicit-any
type Sb = any
type RefundLike = { amount?: number | null; status?: string | null; metadata?: Record<string, string | undefined> | null }

export type DocSums = { dpCzk: number; cnCzk: number; stripeCnCzk: number; manualCnCzk: number }
const r2 = (n: number) => Math.round(n * 100) / 100

/** Součty živých dokladů rezervace (Kč). Chyba čtení se propaguje (volající rozliší „nevím“). */
export async function docSums(sb: Sb, bookingId: string): Promise<DocSums> {
  const { data, error } = await sb.from('invoices').select('type, total, stripe_refund_id')
    .eq('booking_id', bookingId).in('type', ['payment_receipt', 'credit_note']).neq('status', 'cancelled')
  if (error) throw new Error(`documents unreadable: ${error.message}`)
  let dp = 0, cn = 0, scn = 0, mcn = 0
  for (const r of (data || []) as Array<{ type: string; total: unknown; stripe_refund_id: unknown }>) {
    const v = Number(r.total) || 0
    if (r.type === 'payment_receipt') { dp += v; continue }
    const a = Math.abs(v)
    cn += a
    if (r.stripe_refund_id) scn += a; else mcn += a
  }
  return { dpCzk: r2(dp), cnCzk: r2(cn), stripeCnCzk: r2(scn), manualCnCzk: r2(mcn) }
}

/** Co dle dokladů ještě dlužíme (Kč) jako _cap_refund_to_paid; null = rezervace nemá DP (trigger neořezává). */
export function docsOwedCzk(s: DocSums): number | null {
  return s.dpCzk > 0 ? Math.max(0, r2(s.dpCzk - s.cnCzk)) : null
}

/** Vratky, které vracejí peníze MIMO cenu rezervace (vlastní flow, bez dobropisu) — jako booking-intents.ts. */
const OUTSIDE_REFUND_SOURCES = ['unapplied_change', 'duplicate_payment', 'late_payment']

/** Vratky Stripe v ceně rezervace bez dobropisu (haléře): Σ živých vratek všech plateb rezervace (bez vratek mimo
 *  cenu a bez vratek e-shopu — mg_order_id) − Σ kartových dobropisů (stripe_refund_id). Nikdy záporné. */
export function stripeRefundsWithoutCnHaleru(refunds: RefundLike[], stripeCnCzk: number): number {
  const back = refunds.filter((r) => (r.status === 'succeeded' || r.status === 'pending')
    && !OUTSIDE_REFUND_SOURCES.includes(String(r.metadata?.mg_source || '')) && !r.metadata?.mg_order_id)
    .reduce((s, r) => s + Number(r.amount || 0), 0)
  return Math.max(0, back - Math.round(stripeCnCzk * 100))
}

/** Doložené příchozí platby převodem (Kč, bez duplicit fio_id); rows = počet plateb; mod_surcharge_paid_at z rezervace. */
export async function bankPaidCzk(sb: Sb, bookingId: string): Promise<{ czk: number; rows: number; modSurchargePaidAt: string | null }> {
  const { data: bk } = await sb.from('bookings').select('payment_vs, mod_surcharge_vs, mod_surcharge_paid_at').eq('id', bookingId).maybeSingle()
  const seen = new Map<string, number>()
  const { data: byId, error: e1 } = await sb.from('fio_transactions').select('fio_id, amount').eq('booking_id', bookingId).gt('amount', 0)
  if (e1) throw new Error(`fio_transactions unreadable: ${e1.message}`)
  for (const r of byId || []) seen.set(String(r.fio_id), Number(r.amount) || 0)
  const vses = [bk?.payment_vs, bk?.mod_surcharge_vs].filter(Boolean).map(String)
  if (vses.length) {
    const { data: byVs, error: e2 } = await sb.from('fio_transactions').select('fio_id, amount').in('vs', vses).gt('amount', 0)
    if (e2) throw new Error(`fio_transactions unreadable: ${e2.message}`)
    for (const r of byVs || []) seen.set(String(r.fio_id), Number(r.amount) || 0)
  }
  const czk = r2([...seen.values()].reduce((s, v) => s + v, 0))
  return { czk, rows: seen.size, modSurchargePaidAt: bk?.mod_surcharge_paid_at || null }
}

/** Přibalená e-shop část platby (haléře), která na platbě ještě zbývá: shop_orders.total objednávky z
 *  metadata.shop_order_id − vratky téže platby k objednávce (mg_order_id — vratka e-shopu přes process-refund order_id
 *  jde z téže platby; bez odečtu by se e-shop část odečetla dvakrát). Chyba čtení → 0 (bez ořezu, jako dřív). */
export async function shopPartHaleru(sb: Sb, shopOrderId: string | null | undefined, refunds: RefundLike[] | null = null): Promise<number> {
  if (!shopOrderId) return 0
  try {
    const { data: so } = await sb.from('shop_orders').select('total').eq('id', shopOrderId).maybeSingle()
    const back = (refunds || []).filter((r) => (r.status === 'succeeded' || r.status === 'pending') && r.metadata?.mg_order_id === shopOrderId)
      .reduce((s, r) => s + Number(r.amount || 0), 0)
    return Math.max(0, Math.round((Number(so?.total) || 0) * 100) - back)
  } catch { return 0 }
}
