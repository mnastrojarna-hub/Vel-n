// ===== process-payment/web-booking-guards.ts =====
// Webová rezervace (handleWebBookingCheckout) — rozhodnutí oddělená kvůli testům (f1 2026-10-22):
//  • webBookingMiss: rezervace k zaplacení nenalezena (dotaz hledá jen webovou nezaplacenou) → PROČ,
//    s kódem: zaplacená = already_paid (web přejde na potvrzení), neexistuje = not_found, jinak
//    wrong_status. Dřív 400 „Booking not found or already paid" bez kódu, anglicky ve všech jazycích.
//  • freeShopPlan: rezervace zdarma (100% sleva / poukaz) s přibaleným zbožím z doprodeje — dřív jen
//    ověření karty (setup) a objednávka zůstala nezaplacená, i když web ukázal platbu za zboží. Teď
//    platba jen za zboží (+ doprava); pod 15 Kč dorovnání na 15 Kč (jen po SQL 20261016p1; jde
//    k rezervaci jako u každé platby s přibalenou objednávkou — due = cena rezervace).
import { refuse } from './refusals.ts'

const CARD_MIN = 15
const r2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100

// Web vyká; web ukazuje vlastní přeložený text podle `code`, starší web JS tento `error`.
export const WEB_TXT = {
  not_found: 'Rezervaci jsme nenašli. Nic jsme nestrhli – vytvořte si prosím rezervaci znovu.',
  wrong_status: 'Tuto rezervaci už zaplatit nejde (je zrušená nebo ukončená). Nic jsme nestrhli – vytvořte si prosím novou rezervaci.',
  already_paid: 'Rezervace je už zaplacená – nic dalšího neplaťte.',
  free_unverified: 'Slevu se nepodařilo ověřit na celou cenu, proto rezervaci zdarma potvrdit nejde. Nic jsme nestrhli – obnovte prosím stránku a zkontrolujte slevový kód nebo poukaz.',
}

// deno-lint-ignore no-explicit-any
export async function webBookingMiss(sb: any, bookingId: string): Promise<Response> {
  let row: { payment_status?: string } | null = null
  try {
    const { data, error } = await sb.from('bookings').select('id, payment_status').eq('id', bookingId).maybeSingle()
    if (error) return refuse(503, 'validation_unavailable')
    row = data
  } catch { return refuse(503, 'validation_unavailable') }
  if (!row) return refuse(404, 'not_found', {}, WEB_TXT.not_found)
  if (row.payment_status === 'paid') return refuse(409, 'already_paid', { already_paid: true, booking_id: bookingId }, WEB_TXT.already_paid)
  return refuse(409, 'wrong_status', {}, WEB_TXT.wrong_status)
}

export type FreeShopPlan =
  | { kind: 'none' }                                         // není „zdarma + zboží" → beze změny
  | { kind: 'pay'; rounding: { due: number; r: number } | null } // platba za zboží (± dorovnání)
  | { kind: 'below' }                                        // pod 15 Kč a dorovnání na serveru ještě není

export function freeShopPlan(a: { isFree: boolean; shopSum: number; roundingCol: boolean; bookingTotal: number }): FreeShopPlan {
  if (!a.isFree || !(a.shopSum > 0)) return { kind: 'none' }
  if (a.shopSum >= CARD_MIN) return { kind: 'pay', rounding: null }
  if (!a.roundingCol) return { kind: 'below' }
  return { kind: 'pay', rounding: { due: r2(a.bookingTotal), r: r2(CARD_MIN - a.shopSum) } }
}
