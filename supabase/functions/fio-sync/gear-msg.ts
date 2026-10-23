// ===== fio-sync/gear-msg.ts =====
// Zpráva do appky po zaplacení výpůjčky JEN výbavy převodem (booking_kind = 'gear',
// DESIGN-GEAR §3.4, 2026-10-23) v jazyce zákazníka (8 jazyků, tykání). Jazyk = bookings.language
// → detect_customer_language (webhook-receiver/customer-lang.ts); neznámý → čeština.
// Motorková zpráva fio-sync zůstává beze změny (česky).
import { normalizeCustomerLang, resolveBookingLanguage } from '../webhook-receiver/customer-lang.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

const LOCALE: Record<string, string> = {
  cs: 'cs-CZ', en: 'en-GB', de: 'de-DE', es: 'es-ES', fr: 'fr-FR', nl: 'nl-NL', pl: 'pl-PL', uk: 'uk-UA',
}

// {n} = číslo rezervace, {p} = termín
const MSG: Record<string, string> = {
  cs: 'Tvoje výpůjčka výbavy #{n} ({p}) je zaplacená a potvrzená. Potvrzení a doklady ti posíláme e-mailem.',
  en: 'Your gear rental #{n} ({p}) is paid and confirmed. We are sending you the confirmation and documents by e-mail.',
  de: 'Deine Ausrüstungsmiete #{n} ({p}) ist bezahlt und bestätigt. Die Bestätigung und die Unterlagen schicken wir dir per E-Mail.',
  es: 'Tu alquiler de equipamiento #{n} ({p}) está pagado y confirmado. Te enviamos la confirmación y los documentos por correo electrónico.',
  fr: 'Ta location d’équipement #{n} ({p}) est payée et confirmée. Nous t’envoyons la confirmation et les documents par e-mail.',
  nl: 'Je huur van uitrusting #{n} ({p}) is betaald en bevestigd. De bevestiging en de documenten sturen we je per e-mail.',
  pl: 'Twoje wypożyczenie odzieży #{n} ({p}) jest opłacone i potwierdzone. Potwierdzenie i dokumenty wyślemy Ci e-mailem.',
  uk: 'Твою оренду спорядження #{n} ({p}) оплачено й підтверджено. Підтвердження та документи надішлемо тобі електронною поштою.',
}

/** Kalendářní datum rezervace (uložené jako půlnoc UTC) v místním formátu jazyka. */
export function gearMsgDate(v: unknown, lang: string): string {
  const d = String(v || '').slice(0, 10)
  const t = Date.parse(d + 'T00:00:00Z')
  if (!Number.isFinite(t)) return ''
  return new Date(t).toLocaleDateString(LOCALE[lang] || LOCALE.cs, { timeZone: 'UTC' })
}

/** Text zprávy (čistá funkce — testy). */
export function gearPaidMessage(lang: unknown, bookingId: string, start: unknown, end: unknown): string {
  const L = normalizeCustomerLang(lang) ?? 'cs'
  const n = String(bookingId || '').slice(-8).toUpperCase()
  const p = `${gearMsgDate(start, L)} – ${gearMsgDate(end, L)}`
  return (MSG[L] || MSG.cs).replace('{n}', n).replace('{p}', p)
}

/** Jazyk z rezervace (nikdy nehází) → text zprávy. */
export async function gearPaidMessageFor(sb: Sb, bookingId: string, start: unknown, end: unknown): Promise<string> {
  const lang = await resolveBookingLanguage(sb, bookingId).catch(() => undefined)
  return gearPaidMessage(lang, bookingId, start, end)
}
