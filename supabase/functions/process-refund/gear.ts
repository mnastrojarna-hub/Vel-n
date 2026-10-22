// ===== process-refund/gear.ts =====
// Výpůjčka JEN výbavy (bookings.booking_kind = 'gear', DESIGN-GEAR §3.4, 2026-10-23):
//  • text dobropisu „Rezervace: výpůjčka výbavy“ / „Dobropis – … (výpůjčka výbavy)“ místo
//    fallbacku „motorky“ (gear řádek motorku nemá);
//  • spodní mez ceny pro zákaznickou vratku (customerPriceFloorCzk): dřív `null` (bez motorky)
//    → KAŽDÁ zákaznická vratka gear rezervace (zkrácení, odebraný kus) skončila „vyřídí obsluha“.
//    Gear cenu zapisuje jen serverové RPC (zákaznický JWT ji změnit nesmí — RLS + strážce
//    trg_zz_gear_booking_guard), proto mez = cena/den × dny AKTUÁLNÍHO termínu − uplatněné slevy
//    (bez věrnosti a slevy za 12:00 — u výbavy neplatí). Zkrácení se 100 / 50 / 0 % vratkou
//    nechává v ceně odebrané dny × (1 − procento), takže cena nikdy neklesne pod tuto mez.

// deno-lint-ignore no-explicit-any
type Any = any

export const GEAR_REFUND_SUBJECT = 'výpůjčka výbavy'

export function isGearRefundRow(b: Any): boolean {
  return !!b && b.booking_kind === 'gear'
}

/** Předmět dobropisu: gear → „výpůjčka výbavy“, jinak model motorky (fallback „motorky“ jako dřív). */
export function refundSubject(b: Any): string {
  return isGearRefundRow(b) ? GEAR_REFUND_SUBJECT : (b?.motorcycles?.model || 'motorky')
}

/** Počet dní včetně prvního i posledního dne (kalendářní data). */
export function gearDaysInclusive(start: unknown, end: unknown): number {
  const s = Date.parse(String(start || '').slice(0, 10) + 'T00:00:00Z')
  const e = Date.parse(String(end || '').slice(0, 10) + 'T00:00:00Z')
  if (!Number.isFinite(s) || !Number.isFinite(e) || e < s) return 0
  return Math.round((e - s) / 86400000) + 1
}

/** Cena výbavy za den: gear_per_day, jinak součet price_per_day řádků gear_lines; neznámá → null. */
export function gearPerDay(b: Any): number | null {
  const p = Number(b?.gear_per_day)
  if (b?.gear_per_day != null && Number.isFinite(p) && p >= 0) return p
  const lines = Array.isArray(b?.gear_lines) ? b.gear_lines : []
  if (!lines.length) return null
  const sum = lines.reduce((t: number, l: Any) => t + (Number(l?.price_per_day) || 0), 0)
  return Number.isFinite(sum) ? sum : null
}

/** Spodní věrohodná mez ceny gear rezervace (Kč); null = nelze ověřit (→ vratku vyřídí obsluha). */
export async function gearPriceFloorCzk(sb: Any, b: Any, bookingId: string): Promise<number | null> {
  try {
    const perDay = gearPerDay(b)
    const days = gearDaysInclusive(b?.start_date, b?.end_date)
    if (perDay == null || days < 1) return null
    const { data: disc, error } = await sb.from('booking_discounts').select('amount').eq('booking_id', bookingId)
    if (error) return null
    const discounts = (disc || []).reduce((t: number, d: Any) => t + Math.max(0, Number(d.amount) || 0), 0)
    return Math.max(0, Math.floor(perDay * days - discounts))
  } catch { return null }
}
