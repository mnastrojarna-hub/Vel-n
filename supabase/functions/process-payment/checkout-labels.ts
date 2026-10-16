// ===== process-payment/checkout-labels.ts =====
// Názvy položek na hosted Stripe Checkout stránce (web) v jazyce zákazníka — Stripe
// stránku lokalizuje (resolveStripeLocale), naše položky dřív zůstávaly česky.
//  • dorovnání na minimální platbu kartou (D1/D2, doplatek / rezervace / objednávka 1–15 Kč),
//  • doplatek webové úpravy rezervace podle druhu změny (výměna motorky / výbava / úprava) —
//    dřív vždy „Prodloužení rezervace". Jen popisky: částky ani metadata se nemění.
import { resolveSiteLang } from './stripe-customer.ts'

const ROUNDING: Record<string, string> = {
  cs: 'Dorovnání na minimální platbu kartou (15 Kč)',
  en: 'Top-up to the minimum card payment (CZK 15)',
  de: 'Aufrundung auf die Mindestzahlung per Karte (15 CZK)',
  es: 'Redondeo al pago mínimo con tarjeta (15 CZK)',
  fr: 'Complément au paiement minimum par carte (15 CZK)',
  nl: 'Aanvulling tot de minimale kaartbetaling (15 CZK)',
  pl: 'Wyrównanie do minimalnej płatności kartą (15 CZK)',
  uk: 'Доплата до мінімального платежу карткою (15 CZK)',
}

type EditKind = 'swap' | 'gear' | 'edit'
const EDIT: Record<string, Record<EditKind, string>> = {
  cs: { swap: 'Doplatek za výměnu motorky', gear: 'Doplatek za výbavu', edit: 'Doplatek za úpravu rezervace' },
  en: { swap: 'Motorcycle swap surcharge', gear: 'Riding gear surcharge', edit: 'Booking change surcharge' },
  de: { swap: 'Aufpreis für den Motorradtausch', gear: 'Aufpreis für die Ausrüstung', edit: 'Aufpreis für die Buchungsänderung' },
  es: { swap: 'Suplemento por el cambio de moto', gear: 'Suplemento por el equipamiento', edit: 'Suplemento por el cambio de la reserva' },
  fr: { swap: 'Supplément pour l’échange de moto', gear: 'Supplément pour l’équipement', edit: 'Supplément pour la modification de la réservation' },
  nl: { swap: 'Toeslag voor de motorruil', gear: 'Toeslag voor de uitrusting', edit: 'Toeslag voor de reserveringswijziging' },
  pl: { swap: 'Dopłata za wymianę motocykla', gear: 'Dopłata za wyposażenie', edit: 'Dopłata za zmianę rezerwacji' },
  uk: { swap: 'Доплата за заміну мотоцикла', gear: 'Доплата за спорядження', edit: 'Доплата за зміну бронювання' },
}

/** Položka „dorovnání na minimální platbu kartou" v jazyce webu (neznámý jazyk → čeština). */
export function roundingLabel(lang: string | null | undefined): string {
  return ROUNDING[resolveSiteLang(lang)] || ROUNDING.cs
}

/** Druh webové úpravy z payloadu změny (process-payment `change`). */
export function editKind(change: unknown): EditKind {
  const c = (change && typeof change === 'object' ? change : {}) as Record<string, unknown>
  if (c._swap && typeof c._swap === 'object') return 'swap'
  if (c._gear && typeof c._gear === 'object') return 'gear'
  return 'edit'
}

/** Hlavní položka doplatku webové úpravy: „MotoGo24 — <druh změny>" v jazyce webu. */
export function editLineLabel(change: unknown, lang: string | null | undefined): string {
  const t = EDIT[resolveSiteLang(lang)] || EDIT.cs
  return `MotoGo24 — ${t[editKind(change)]}`
}
