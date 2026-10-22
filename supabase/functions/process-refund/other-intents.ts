// ===== process-refund/other-intents.ts =====
// Odpověď majitele 2026-10-16 (otázka 1, „ano stejně"): při stornu se dorovnání na
// minimální platbu kartou vrací POMĚRNĚ jako zbytek ceny. Dorovnání je součástí
// bookings.total_price (storno = % × total_price), ale u doplatku úpravy / výměny bylo
// zaplacené JINÝM PaymentIntentem než původní rezervace. process-refund dřív vracel jen
// z bookings.stripe_payment_intent_id (oříznuto na jeho zbytek) → storno 100 % po
// zaplacené úpravě nevrátilo doplatek ani jeho dorovnání. Zbytek nad možnosti hlavní
// platby se teď vrátí z ostatních úspěšných plateb TÉŽE rezervace (doplatky úprav,
// výměn, starší platba rezervace), nejstarší první. Výběr plateb + výluky (e-shop,
// duplicitní platba, platba nezapsané změny) → _shared/booking-intents.ts.
// Idempotence: klíč refund-rest:<id hlavní vratky>:<pi>:<částka> + metadata
// mg_main_refund. Hlavní vratka je mezi duplicitními dispatchi idempotentní (Stripe ji
// přehraje se stejným id) → i zbytek: co už se k TÉTO hlavní vratce vrátilo (i z jiné
// platby), se od požadavku odečte a stejná částka z téže platby dostane stejný klíč.
// Legitimní pozdější vratka má novou hlavní vratku → nový klíč.
// Oprava f2 2026-10-22: totéž platí i pro ZÁKAZNICKOU vratku z appky (zkrácení / levnější
// motorka). Dřív šla jen z uložené platby — typicky poslední doplatek úpravy / výměny (process-
// payment ukládá každý PaymentIntent doplatku) — a oříznutá na jeho zbytek: např. vratka 500 Kč
// po doplatku 115 Kč vrátila 115 Kč, odpověď „success" a 385 Kč se tiše ztratilo. Teď: hlavní
// vratka z platby v ceně rezervace (mainSource jako u obsluhy), zbytek do ověřeného přeplatku
// (customerCapHaleru — jen platby v ceně) z ostatních plateb; co nejde automaticky → obsluha.
import { otherRefundableIntents, outsidePrice, type BookingIntentsStripe, type IntentLike, type Outside, type RefundLike } from '../_shared/booking-intents.ts'

// deno-lint-ignore no-explicit-any
type Sb = any
export type OtherIntentsStripe = BookingIntentsStripe
export type ExtraRefund = { piId: string; refundId: string; amountHaleru: number; status: string }
export { otherRefundableIntents }

/** Vrátí `remainingHaleru` z ostatních plateb rezervace (po částech, nejstarší první).
 *  `leftHaleru` = co na nich po této vratce ještě zbývá (≠ 0 → vratka byla jen částečná). */
export async function refundRemainder(stripe: OtherIntentsStripe, sb: Sb, a: {
  bookingId: string; mainPi: string | null; mainRefundId: string; remainingHaleru: number; reason?: string | null
}): Promise<{ refunds: ExtraRefund[]; refundedHaleru: number; leftHaleru: number; error?: string }> {
  const refunds: ExtraRefund[] = []
  let remaining = Math.max(0, Math.round(a.remainingHaleru))
  let left = 0
  if (!remaining) return { refunds, refundedHaleru: 0, leftHaleru: 0 }
  let cands: Awaited<ReturnType<typeof otherRefundableIntents>> = []
  try {
    cands = await otherRefundableIntents(stripe, sb, a.bookingId, a.mainPi, a.mainRefundId)
  } catch (e) {
    return { refunds, refundedHaleru: 0, leftHaleru: 0, error: (e as Error).message }
  }
  // Opakovaný dispatch téhož storna: k této hlavní vratce už vrácené (i z jiné platby) se nevrací znovu.
  const already = cands.reduce((s, c) => s + c.refundsForMain, 0)
  const alreadyDone = Math.min(already, remaining)
  remaining -= alreadyDone
  for (const c of cands) {
    const amt = Math.min(c.refundableHaleru, remaining)
    if (amt <= 0) { left += c.refundableHaleru; continue }
    try {
      const r = await stripe.refunds.create({
        payment_intent: c.id, amount: amt, reason: 'requested_by_customer',
        metadata: { mg_source: 'process-refund', mg_reason: a.reason || '', mg_booking_id: a.bookingId, mg_part: 'remainder', mg_main_refund: a.mainRefundId },
      }, { idempotencyKey: `refund-rest:${a.mainRefundId}:${c.id}:${amt}` })
      refunds.push({ piId: c.id, refundId: r.id, amountHaleru: Number(r.amount ?? amt), status: String(r.status || 'succeeded') })
      remaining -= amt
      left += c.refundableHaleru - amt
    } catch (e) {
      const done = refunds.reduce((s, x) => s + x.amountHaleru, 0) + alreadyDone
      return { refunds, refundedHaleru: done, leftHaleru: left + c.refundableHaleru, error: (e as Error).message }
    }
  }
  return { refunds, refundedHaleru: refunds.reduce((s, x) => s + x.amountHaleru, 0) + alreadyDone, leftHaleru: left }
}

/** Uložená platba rezervace nemá z čeho vracet (nikdy nezaplacená / už celá vrácená) →
 *  hlavní vratka z nejstarší jiné úspěšné platby TÉŽE rezervace (typicky původní platba).
 *  Vratka s částkou (storno, obsluha i zákazník — f2); null = žádná jiná platba (→ ruční vratka / no_op). */
export async function pickMainIntent(stripe: OtherIntentsStripe, sb: Sb, a: {
  bookingId: string; storedPi: string | null; chargedHaleru: number | null; refundableHaleru: number | null
  /** od opravy f2 bez vlivu (zákaznická vratka se přesměrovává stejně) */
  isCustomer?: boolean; amount: number | null | undefined
  /** uložená platba stojí mimo cenu rezervace (outsidePrice) → hledat i když z ní vracet jde */
  force?: boolean
}): Promise<{ piId: string; refundableHaleru: number } | null> {
  if (!(Number(a.amount) > 0)) return null
  if (!a.force && !(a.chargedHaleru === 0 || a.refundableHaleru === 0)) return null
  const cands = (await otherRefundableIntents(stripe, sb, a.bookingId, a.storedPi)).filter((c) => c.refundableHaleru > 0)
  return cands.length ? { piId: cands[0].id, refundableHaleru: cands[0].refundableHaleru } : null
}

export type MainSource =
  | { kind: 'stored' }
  | { kind: 'retarget'; piId: string; refundableHaleru: number; outside: Outside | null }
  | { kind: 'manual'; outside: Outside }

/** Z čeho vratka s částkou vrací (storno / obsluha — oprava f1; zákazník z appky — oprava f2 2026-10-22):
 *  • uložená platba nemá z čeho vracet (nikdy nezaplacená / celá vrácená) → nejstarší jiná platba kartou,
 *  • uložená platba stojí MIMO cenu rezervace (doplatek nezapsané / ještě nezapsané změny, duplicita,
 *    platba vrácená jen jako peníze mimo cenu — outsidePrice) → nejstarší jiná platba kartou; když
 *    žádná není (rezervace placená QR / převodem / hotově), ruční vratka (dobropis + refund_pending;
 *    u zákazníka jen do ověřeného přeplatku z příchozích plateb, jinak obsluha).
 *    Dřív: storno vrátilo část ceny z doplatku ještě nezapsané změny (doplatek se pak nezapsal ani
 *    nevrátil), resp. u vyčerpaného doplatku skončilo no_op → 'refunded' a nevrátilo nic; zákaznická
 *    vratka brala doplatek nevrácené nezapsané změny (obsluha) jako vratku za zkrácení, u ještě
 *    nezapsaného doplatku šla celá na obsluhu a u nikdy nezaplaceného (opuštěný doplatek) na ruční
 *    vratku i u rezervace placené kartou,
 *  • jinak z uložené platby jako dosud. Vratka bez částky beze změny. */
export async function mainSource(stripe: OtherIntentsStripe, sb: Sb, a: {
  bookingId: string; storedPiId: string | null; storedPi: IntentLike | null; storedRefunds: RefundLike[] | null
  chargedHaleru: number | null; refundableHaleru: number | null; isCustomer?: boolean; amount: number | null | undefined; nowMs?: number
}): Promise<MainSource> {
  let outside: Outside | null = null
  if (Number(a.amount) > 0 && a.storedPi && Number(a.chargedHaleru) > 0) {
    outside = await outsidePrice(sb, a.bookingId, a.storedPi, { refunds: a.storedRefunds, errAs: false, nowMs: a.nowMs })
  }
  if (!(a.chargedHaleru === 0 || a.refundableHaleru === 0 || outside)) return { kind: 'stored' }
  const main = await pickMainIntent(stripe, sb, { bookingId: a.bookingId, storedPi: a.storedPiId, chargedHaleru: a.chargedHaleru,
    refundableHaleru: a.refundableHaleru, amount: a.amount, force: !!outside })
  if (main) return { kind: 'retarget', ...main, outside }
  return outside ? { kind: 'manual', outside } : { kind: 'stored' }
}

/** Strop ZÁKAZNICKÉ vratky (appka po zkrácení / levnější motorce), haléře: co z plateb V CENĚ
 *  rezervace ještě zbývá — uložená platba (pokud do ceny patří) + ostatní platby (tentýž výběr,
 *  ze kterého vrací hlavní vratka i zbytek) — minus AKTUÁLNÍ total_price (appka nižší cenu zapíše
 *  dřív, než vratku zavolá). Zaplaceno se bere ze Stripe, ne z řádku rezervace (ten si zákazník
 *  umí přepsat). Oprava f2 2026-10-22: platby MIMO cenu (doplatek nezapsané / ještě nezapsané
 *  změny, duplicita, platba vrácená jen mimo cenu, e-shop) se nepočítají — vracejí se celé zvlášť,
 *  takže by strop nafoukly a zákazník by je přes vratku z původní platby dostal podruhé.
 *  Chyba čtení ostatních plateb → jen uložená platba (jako dřív při chybě vyhledávání).
 *  null = nelze ověřit (→ vyřídí obsluha). */
export async function customerCapHaleru(stripe: OtherIntentsStripe, sb: Sb, a: {
  bookingId: string; storedPi: IntentLike | null; storedRefunds: RefundLike[] | null; totalPrice: number; nowMs?: number
}): Promise<number | null> {
  try {
    const p = a.storedPi
    const md = (p?.metadata || {}) as Record<string, string>
    const received = Number(p?.amount_received || 0)
    let stored = 0
    if (p && received > 0 && (!md.booking_id || md.booking_id === a.bookingId) && md.type !== 'shop') {
      const refunds = a.storedRefunds ?? ((await stripe.refunds.list({ payment_intent: p.id, limit: 100 }))?.data || [])
      if (!(await outsidePrice(sb, a.bookingId, p, { refunds, nowMs: a.nowMs }))) {
        const back = refunds.filter((r) => r.status === 'succeeded' || r.status === 'pending').reduce((s, r) => s + Number(r.amount || 0), 0)
        let shopPart = 0
        if (md.shop_order_id) {
          const { data: so } = await sb.from('shop_orders').select('total').eq('id', md.shop_order_id).maybeSingle()
          shopPart = Math.round((Number(so?.total) || 0) * 100)
        }
        stored = Math.max(0, received - back - shopPart)
      }
    }
    let others = 0
    try {
      others = (await otherRefundableIntents(stripe, sb, a.bookingId, p?.id || null)).reduce((s, c) => s + c.refundableHaleru, 0)
    } catch (e) { console.warn('[process-refund] customer cap: other payments failed:', (e as Error).message) }
    return Math.max(0, stored + others - Math.round((Number(a.totalPrice) || 0) * 100))
  } catch (e) {
    console.warn('[process-refund] customer cap failed:', (e as Error).message)
    return null
  }
}

/** Zákaznická vratka: nevrácený zbytek do 1 Kč = zaokrouhlení (cena numeric(10,2) vs. rozdíl
 *  z appky na haléře) — jako odpuštění do 1 Kč (D1) bez obsluhy, bez `partial`. Appka
 *  (refundFellShort) má stejnou toleranci. */
export const CUSTOMER_SHORT_TOLERANCE_HALERU = 100

/** payment_status rezervace po vratce: Stripe ještě nepotvrdil → refund_pending; zákaznická
 *  vratka (jen přeplatek) nebo zákaznická vratka, ze které se automaticky nevrátilo všechno
 *  (`shortHaleru` — zbytek vyřídí obsluha), menší než zbývá na hlavní platbě, nebo na ostatních
 *  platbách ještě něco zůstalo → partial_refund; jinak refunded. */
export function refundedStatus(a: {
  refundStatus: string | null | undefined; isCustomer: boolean; bookingTotalPrice: number; amount: number | null | undefined
  refundableHaleru: number | null; effectiveAmountHaleru: number | null; leftHaleru: number; shortHaleru?: number
}): 'refund_pending' | 'partial_refund' | 'refunded' {
  const isPartial = (a.isCustomer && (a.bookingTotalPrice > 0 || (a.shortHaleru || 0) > 0)) ||
    (!!a.amount && a.refundableHaleru != null && a.effectiveAmountHaleru != null && a.effectiveAmountHaleru < a.refundableHaleru) ||
    a.leftHaleru > 0
  return a.refundStatus === 'pending' ? 'refund_pending' : (isPartial ? 'partial_refund' : 'refunded')
}
