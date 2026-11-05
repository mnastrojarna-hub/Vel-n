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
