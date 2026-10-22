// ===== process-payment/checkout-labels.ts =====
// Názvy položek na hosted Stripe Checkout stránce (web) v jazyce zákazníka — Stripe
// stránku lokalizuje (resolveStripeLocale), naše položky dřív zůstávaly česky.
//  • dorovnání na minimální platbu kartou (D1/D2, doplatek / rezervace / objednávka 1–15 Kč),
//  • doplatek webové úpravy rezervace podle druhu změny (výměna motorky / výbava / úprava) —
//    dřív vždy „Prodloužení rezervace". Jen popisky: částky ani metadata se nemění.
//  • webová rezervace a e-shop (f1 2026-10-22): pronájem + „Rezervace #…", velikost, doprava,
//    sleva — dřív česky i na en/de/… stránce (vedle přeloženého dorovnání).
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

type Web = { booking: string; bookingDesc: string; shipping: string; shippingZasilkovna: string; shippingPost: string; size: string; discount: string }
// {num} = číslo rezervace, {size} = velikost
const WEB: Record<string, Web> = {
  cs: { booking: 'MotoGo24 — Pronájem motorky', bookingDesc: 'Rezervace #{num}', shipping: 'Doprava', shippingZasilkovna: 'Doprava — Zásilkovna',
    shippingPost: 'Doprava — Česká pošta', size: '(vel. {size})', discount: 'Sleva' },
  en: { booking: 'MotoGo24 — Motorcycle rental', bookingDesc: 'Booking #{num}', shipping: 'Shipping', shippingZasilkovna: 'Shipping — Packeta (Zásilkovna)',
    shippingPost: 'Shipping — Czech Post', size: '(size {size})', discount: 'Discount' },
  de: { booking: 'MotoGo24 — Motorradmiete', bookingDesc: 'Buchung Nr. {num}', shipping: 'Versand', shippingZasilkovna: 'Versand — Packeta (Zásilkovna)',
    shippingPost: 'Versand — Tschechische Post', size: '(Größe {size})', discount: 'Rabatt' },
  es: { booking: 'MotoGo24 — Alquiler de moto', bookingDesc: 'Reserva n.º {num}', shipping: 'Envío', shippingZasilkovna: 'Envío — Packeta (Zásilkovna)',
    shippingPost: 'Envío — Correos checos', size: '(talla {size})', discount: 'Descuento' },
  fr: { booking: 'MotoGo24 — Location de moto', bookingDesc: 'Réservation n° {num}', shipping: 'Livraison', shippingZasilkovna: 'Livraison — Packeta (Zásilkovna)',
    shippingPost: 'Livraison — Poste tchèque', size: '(taille {size})', discount: 'Remise' },
  nl: { booking: 'MotoGo24 — Motorverhuur', bookingDesc: 'Boeking nr. {num}', shipping: 'Verzending', shippingZasilkovna: 'Verzending — Packeta (Zásilkovna)',
    shippingPost: 'Verzending — Tsjechische post', size: '(maat {size})', discount: 'Korting' },
  pl: { booking: 'MotoGo24 — Wynajem motocykla', bookingDesc: 'Rezerwacja nr {num}', shipping: 'Dostawa', shippingZasilkovna: 'Dostawa — Packeta (Zásilkovna)',
    shippingPost: 'Dostawa — Poczta Czeska', size: '(rozm. {size})', discount: 'Rabat' },
  uk: { booking: 'MotoGo24 — Оренда мотоцикла', bookingDesc: 'Бронювання № {num}', shipping: 'Доставка', shippingZasilkovna: 'Доставка — Packeta (Zásilkovna)',
    shippingPost: 'Доставка — Чеська пошта', size: '(розмір {size})', discount: 'Знижка' },
}

/** Popisky položek webové rezervace / e-shopu na Stripe stránce v jazyce webu (neznámý → čeština). */
export function webLabels(lang: string | null | undefined): Web {
  return WEB[resolveSiteLang(lang)] || WEB.cs
}

/** Doplní {num} / {size} do popisku. */
export function fillLabel(s: string, v: Record<string, string>): string {
  return s.replace(/\{(\w+)\}/g, (_m, k) => v[k] ?? '')
}

/** Název dopravy podle způsobu doručení e-shopu. */
export function shippingLabel(method: string | null | undefined, lang: string | null | undefined): string {
  const t = webLabels(lang)
  return method === 'zasilkovna' ? t.shippingZasilkovna : method === 'post' ? t.shippingPost : t.shipping
}
