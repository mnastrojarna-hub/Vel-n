// ===== process-payment/gear-checkout.ts =====
// Výpůjčka JEN výbavy (bookings.booking_kind = 'gear', DESIGN-GEAR §3.4, 2026-10-23):
//  • hosted Checkout webové gear rezervace (handleWebBookingCheckout): položka
//    „MotoGo24 — Půjčení výbavy" v jazyce webu (ne „Pronájem motorky") a návrat na stránku
//    /pujceni-obleceni — úspěch `?booking_id=…&session_id=…` (potvrzení + doklady),
//    zrušení `?resume=…&payfail=1` (znovu zaplatit) místo motorkového /potvrzeni a /rezervace.
//  • úpravy zaplacené gear rezervace (index.ts, doplatek): jen termín ve tvaru `p_new_*`, naceněný
//    dry-runem apply_booking_changes (dny × gear_per_day, sklad + zavřená pobočka). Zapisuje ho
//    po platbě webhook-receiver (applyExtensionChange, UPDATE sloupců pod service_role);
//    gear_lines přepočte a sklad v přidaných dnech znovu ověří DB trigger trg_zzz_gear_lines_days
//    (20261023e, i pod service_role) a zavřenou pobočku trg_check_booking_branch_open — při
//    odmítnutí zápisu (P0001) webhook JEN zapíše extension_change_apply_failed do debug_log — bez
//    automatické vratky i bez upozornění obsluhy (stejně jako u motorky; řešit ve webhook-receiver).
//    Výměna motorky (`_swap`), výbava motorkové rezervace
//    (`_gear` → update_booking_gear) a app formát (cenu počítá klient, webhook pak zapisuje
//    sloupce jako service_role MIMO strážce _gear_booking_guard) — i smíšený s `p_new_*` — se
//    u gear rezervace odmítají dřív, než se cokoli strhne.
import { resolveSiteLang, withLangParam } from './stripe-customer.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

const GEAR_PRODUCT: Record<string, string> = {
  cs: 'MotoGo24 — Půjčení výbavy',
  en: 'MotoGo24 — Riding gear rental',
  de: 'MotoGo24 — Verleih von Motorradausrüstung',
  es: 'MotoGo24 — Alquiler de equipamiento de moto',
  fr: 'MotoGo24 — Location d’équipement moto',
  nl: 'MotoGo24 — Verhuur van motoruitrusting',
  pl: 'MotoGo24 — Wypożyczenie odzieży motocyklowej',
  uk: 'MotoGo24 — Оренда мотоспорядження',
}

/** Řádek rezervace je výpůjčka výbavy? (`moto_id IS NULL` samo o sobě gear NEZNAMENÁ — FK SET NULL.) */
export function isGearRow(b: unknown): boolean {
  return !!b && typeof b === 'object' && (b as Record<string, unknown>).booking_kind === 'gear'
}

/** booking_kind z DB tolerantně: chyba / chybějící sloupec (SQL ještě nenasazené) = motorka. */
export async function loadIsGear(sb: Sb, bookingId: string | null | undefined): Promise<boolean> {
  if (!bookingId) return false
  try {
    const { data, error } = await sb.from('bookings').select('booking_kind').eq('id', bookingId).maybeSingle()
    return !error && isGearRow(data)
  } catch { return false }
}

/** Druh rezervace pro doplatek úpravy (fail closed): 'gear' | 'moto'; chybějící sloupec (SQL ještě
 *  nenasazené, PostgREST 42703) = 'moto'; jiná chyba = null → validation_unavailable (nic se nestrhne). */
export async function loadBookingKind(sb: Sb, bookingId: string | null | undefined): Promise<'gear' | 'moto' | null> {
  if (!bookingId) return 'moto'
  try {
    const { data, error } = await sb.from('bookings').select('booking_kind').eq('id', bookingId).maybeSingle()
    if (error) return error.code === '42703' ? 'moto' : null
    return isGearRow(data) ? 'gear' : 'moto'
  } catch { return null }
}

/** Druh pro doplatek úpravy z už načteného řádku: s motorkou = vždy 'moto' (CHECK bookings_gear_shape:
 *  gear ⇒ moto_id NULL) bez dalšího dotazu a bez nového důvodu odmítnutí; jen řádek bez motorky se dohledá
 *  (i motorka smazaná z flotily — FK SET NULL: výpadek DB na tomto dotazu = validation_unavailable,
 *  záměrně fail closed, jinak by gear rezervace obešla odmítnutí app formátu). */
export function bookingKindForEdit(sb: Sb, cur: { moto_id?: string | null } | null, bookingId: string | null | undefined): Promise<'gear' | 'moto' | null> {
  return cur && !cur.moto_id ? loadBookingKind(sb, bookingId) : Promise.resolve('moto')
}

/** Název položky na Stripe stránce v jazyce webu (neznámý jazyk → čeština). */
export function gearBookingLabel(lang: string | null | undefined): string {
  return GEAR_PRODUCT[resolveSiteLang(lang)] || GEAR_PRODUCT.cs
}

/** Návratové adresy hosted Checkoutu gear rezervace (origin = resolveReturnOrigin). */
export function gearCheckoutUrls(origin: string, bookingId: string, locale: string | null | undefined): { success: string; cancel: string } {
  return {
    success: withLangParam(`${origin}/pujceni-obleceni?booking_id=${bookingId}&session_id={CHECKOUT_SESSION_ID}`, locale),
    cancel: withLangParam(`${origin}/pujceni-obleceni?resume=${bookingId}&payfail=1`, locale),
  }
}

/** Doplatek úpravy gear rezervace: nepovolený tvar změny → kód (jinak null = pokračovat k dry-runu). */
export function gearChangeBlock(change: unknown): string | null {
  const c = (change && typeof change === 'object' ? change : {}) as Record<string, unknown>
  if (c._swap || ('p_new_moto_id' in c && c.p_new_moto_id) || ('moto_id' in c && c.moto_id)) return 'gear_no_moto'
  if (c._gear) return 'gear_sizes_free'
  // Smíšený payload (`p_new_*` + DB sloupce): dry-run nacení jen `p_new_*`, ale webhook by
  // sloupce (start_date, discount_amount, delivery_fee…) zapsal jako service_role → odmítnout.
  // Web posílá jen `p_new_*`, `_…` (_base, _time_update, _pb) a new_total.
  const keys = Object.keys(c)
  if (keys.some((k) => !k.startsWith('p_new_') && !k.startsWith('_') && k !== 'new_total')) return 'gear_app_format'
  if (keys.some((k) => k.startsWith('p_new_'))) return null
  return 'gear_app_format'
}

// Český text odmítnutí (tykání, bez kontaktů — D5). Kód pro klienty zůstává
// `change_not_applicable` (+ reason), který web i appka už překládají.
export const GEAR_DRY_TXT: Record<string, string> = {
  gear_no_moto: 'U výpůjčky výbavy nejde měnit ani přidat motorku. Platba doplatku zrušena, nic jsme nestrhli.',
  gear_sizes_free: 'Velikosti výpůjčky výbavy změníš zdarma v úpravě rezervace (Velikosti) — nic se neplatí. Platba doplatku zrušena, nic jsme nestrhli.',
  gear_app_format: 'Tuhle úpravu výpůjčky výbavy tady zaplatit nejde — změň termín v úpravě rezervace na webu. Platba doplatku zrušena, nic jsme nestrhli.',
  out_of_stock: 'Výbava v tvojí velikosti už v novém termínu není volná. Zvol prosím jiný termín. Platba doplatku zrušena, nic jsme nestrhli.',
  branch_closed: 'Pobočka je v novém termínu zavřená. Zvol prosím jiný termín. Platba doplatku zrušena, nic jsme nestrhli.',
  gear_no_delivery: 'Výbavu nepřivážíme — vyzvedneš i vrátíš ji na pobočce. Platba doplatku zrušena, nic jsme nestrhli.',
  too_long: 'Výpůjčka výbavy by byla delší, než je povolené maximum. Zvol prosím kratší termín. Platba doplatku zrušena, nic jsme nestrhli.',
}
