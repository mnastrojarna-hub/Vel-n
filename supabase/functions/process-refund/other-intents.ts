// ===== process-refund/other-intents.ts =====
// Odpověď majitele 2026-10-16 (otázka 1, „ano stejně"): při stornu se dorovnání na
// minimální platbu kartou vrací POMĚRNĚ jako zbytek ceny. Dorovnání je součástí
// bookings.total_price (storno = % × total_price), ale u doplatku úpravy / výměny bylo
// zaplacené JINÝM PaymentIntentem než původní rezervace. process-refund dřív vracel jen
// z bookings.stripe_payment_intent_id (oříznuto na jeho zbytek) → storno 100 % po
// zaplacené úpravě nevrátilo doplatek ani jeho dorovnání. Zbytek nad možnosti hlavní
// platby se teď vrátí z ostatních úspěšných plateb TÉŽE rezervace (doplatky úprav,
// výměn, starší platba rezervace), nejstarší první.
// Nikdy z: e-shopu (type shop) a přibalené e-shop části platby, duplicitní platby
// (duplicate_of / záznam duplicate_payment — vrací se celá zvlášť) a platby nezapsané
// změny (paid_change_failed — vrací se celá zvlášť, do ceny nepatří).
// Idempotence: klíč refund-rest:<rezervace>:<pi>:<částka>:<zbývá na pi> — souběžné
// duplicitní dispatche se na Stripe sejdou v jedné vratce, další legitimní vratka má
// menší „zbývá" → jiný klíč (stejný vzor jako hlavní vratka v index.ts).

// deno-lint-ignore no-explicit-any
type Sb = any
type Pi = { id: string; status?: string; amount_received?: number | null; created?: number | null; metadata?: Record<string, string> | null }
export type OtherIntentsStripe = {
  paymentIntents: { search: (p: Record<string, unknown>) => Promise<{ data: Pi[] }> }
  refunds: {
    list: (p: Record<string, unknown>) => Promise<{ data: Array<{ amount: number; status?: string | null }> }>
    create: (p: Record<string, unknown>, o?: Record<string, unknown>) => Promise<{ id: string; amount: number; status?: string | null }>
  }
}
export type ExtraRefund = { piId: string; refundId: string; amountHaleru: number; status: string }

const UUID_RX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

async function logged(sb: Sb, action: string, payRef: string): Promise<boolean> {
  try {
    const { data } = await sb.from('debug_log').select('id').eq('action', action).eq('request_data->>payment_ref', payRef).limit(1)
    return Array.isArray(data) && data.length > 0
  } catch { return true } // nejistota → tuhle platbu nepoužít (raději vyřídí obsluha)
}

/** Ostatní úspěšné platby rezervace s tím, co z nich ještě jde vrátit (haléře), nejstarší první. */
export async function otherRefundableIntents(stripe: OtherIntentsStripe, sb: Sb, bookingId: string, mainPi: string | null):
  Promise<Array<{ id: string; refundableHaleru: number }>> {
  if (!UUID_RX.test(bookingId)) return []
  const found = await stripe.paymentIntents.search({ query: `metadata['booking_id']:'${bookingId}' AND status:'succeeded'`, limit: 100 })
  const rows = (found?.data || []).filter((p) => p.id !== mainPi && p.status === 'succeeded'
    && (p.metadata || {}).booking_id === bookingId && ((p.metadata || {}).type || 'booking') !== 'shop'
    && !(p.metadata || {}).duplicate_of)
  rows.sort((a, b) => (Number(a.created || 0) - Number(b.created || 0)) || (a.id < b.id ? -1 : 1))
  const out: Array<{ id: string; refundableHaleru: number }> = []
  for (const p of rows) {
    if (await logged(sb, 'paid_change_failed', p.id) || await logged(sb, 'duplicate_payment', p.id)) continue
    const received = Number(p.amount_received || 0)
    if (!(received > 0)) continue
    let refunded = 0
    const rl = await stripe.refunds.list({ payment_intent: p.id, limit: 100 })
    for (const r of rl?.data || []) if (r.status === 'succeeded' || r.status === 'pending') refunded += Number(r.amount || 0)
    let shopPart = 0
    const shopId = (p.metadata || {}).shop_order_id
    if (shopId) {
      const { data: so } = await sb.from('shop_orders').select('total').eq('id', shopId).maybeSingle()
      shopPart = Math.round((Number(so?.total) || 0) * 100)
    }
    const left = received - refunded - shopPart
    if (left > 0) out.push({ id: p.id, refundableHaleru: left })
  }
  return out
}

/** Vrátí `remainingHaleru` z ostatních plateb rezervace (po částech, nejstarší první).
 *  `leftHaleru` = co na nich po této vratce ještě zbývá (≠ 0 → vratka byla jen částečná). */
export async function refundRemainder(stripe: OtherIntentsStripe, sb: Sb, a: {
  bookingId: string; mainPi: string | null; remainingHaleru: number; reason?: string | null
}): Promise<{ refunds: ExtraRefund[]; refundedHaleru: number; leftHaleru: number; error?: string }> {
  const refunds: ExtraRefund[] = []
  let remaining = Math.max(0, Math.round(a.remainingHaleru))
  let left = 0
  if (!remaining) return { refunds, refundedHaleru: 0, leftHaleru: 0 }
  let cands: Array<{ id: string; refundableHaleru: number }> = []
  try {
    cands = await otherRefundableIntents(stripe, sb, a.bookingId, a.mainPi)
  } catch (e) {
    return { refunds, refundedHaleru: 0, leftHaleru: 0, error: (e as Error).message }
  }
  for (const c of cands) {
    const amt = Math.min(c.refundableHaleru, remaining)
    if (amt <= 0) { left += c.refundableHaleru; continue }
    try {
      const r = await stripe.refunds.create({
        payment_intent: c.id, amount: amt, reason: 'requested_by_customer',
        metadata: { mg_source: 'process-refund', mg_reason: a.reason || '', mg_booking_id: a.bookingId, mg_part: 'remainder' },
      }, { idempotencyKey: `refund-rest:${a.bookingId}:${c.id}:${amt}:${c.refundableHaleru}` })
      refunds.push({ piId: c.id, refundId: r.id, amountHaleru: Number(r.amount ?? amt), status: String(r.status || 'succeeded') })
      remaining -= amt
      left += c.refundableHaleru - amt
    } catch (e) {
      const done = refunds.reduce((s, x) => s + x.amountHaleru, 0)
      return { refunds, refundedHaleru: done, leftHaleru: left + c.refundableHaleru, error: (e as Error).message }
    }
  }
  return { refunds, refundedHaleru: refunds.reduce((s, x) => s + x.amountHaleru, 0), leftHaleru: left }
}
