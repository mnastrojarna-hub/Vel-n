// ===== _shared/currency.ts =====
// Měna plateb je VÝHRADNĚ CZK a určuje ji SERVER (oprava 2026-11-05). Dřív šla do Stripe
// `currency` z požadavku klienta (`body.currency || 'czk'`): PaymentIntent / Checkout Session na
// částku `amount` v levnější měně (2000 HUF ≈ 120 Kč za rezervaci 2000 Kč) by webhook potvrdil
// jako zaplacenou (confirm_payment částku ani měnu nekontroluje) a zaúčtoval jako Kč.
// Sdílí process-payment (odmítnutí požadavku + konstanta) a webhook-receiver (pojistka: platbu
// v jiné měně nepotvrdit). Appka (i 4.1.3) `currency` neposílá, web posílá 'czk'.
export const CZK = 'czk'

/** `currency` z požadavku chybí, nebo je CZK (velikost písmen nerozhoduje). */
export function requestedCurrencyOk(v: unknown): boolean {
  if (v == null || v === '') return true
  return typeof v === 'string' && v.trim().toLowerCase() === CZK
}

/** Měna zaplacené platby ze Stripe (PaymentIntent.currency / Checkout Session.currency) je CZK;
 *  chybějící (setup session bez platby) = v pořádku. */
export function paymentCurrencyOk(v: unknown): boolean {
  if (v == null || v === '') return true
  return String(v).toLowerCase() === CZK
}

/** Oprava i4 (2026-11-07, verify:charges): Stripe Checkout s Adaptive Pricing (lokální měna zákazníka — nastavení účtu
 *  Settings → Payments → Adaptive Pricing; MÁ být vypnuté) ukáže a strhne cenu v měně zákazníka: Session.currency = 'eur',
 *  amount_total v eurocentech, původní cena v `currency_conversion` (source_currency 'czk', amount_total v haléřích).
 *  Taková platba JE za naši cenu v CZK → potvrdit (dřív webhook rezervaci nepotvrdil, obsluze „vraťte“ a cron ji zrušil)
 *  a částky brát z currency_conversion (amount_total v eurocentech by se četl jako Kč).
 *  ok = CZK cena (přímo nebo převedená), amountTotalH = cena v haléřích CZK (null = neznámá), converted = Adaptive Pricing. */
export type CheckoutLike = { currency?: string | null; amount_total?: number | null
  currency_conversion?: { source_currency?: string | null; amount_total?: number | null } | null }
export function checkoutCzk(s: CheckoutLike | null | undefined): { ok: boolean; amountTotalH: number | null; converted: boolean } {
  if (!s) return { ok: true, amountTotalH: null, converted: false }
  if (paymentCurrencyOk(s.currency)) return { ok: true, amountTotalH: s.amount_total ?? null, converted: false }
  const cc = s.currency_conversion
  if (cc && String(cc.source_currency || '').toLowerCase() === CZK) {
    return { ok: true, amountTotalH: Number.isFinite(Number(cc.amount_total)) ? Number(cc.amount_total) : null, converted: true }
  }
  return { ok: false, amountTotalH: null, converted: false }
}
