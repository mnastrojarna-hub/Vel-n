// ===== process-payment/floor-check.ts =====
// D1/D4 (oprava 2026-10-16): bookings.total_price zapisuje klient (RLS) — server ji
// ověřuje proti spodní mezi z ceníku (due-verify.ts):
//  • odpuštění do 1 Kč / dorovnání na 15 Kč u rezervace → VYNUCENO (beze změny),
//  • běžná platba rezervace / SOS → zatím jen záznam do debug_log (`booking_price_below_floor`)
//    ke kalibraci; PP_FLOOR_ENFORCE=1 vynutí i tu (jen typ booking — SOS cenu určuje obsluha),
//  • nesoulad = `outdated` → odmítnutí `price_outdated` (NEnabízí jinou částku: zaplaceno
//    by se lišilo od ceny na dokladech).
//  • zdarma (cena 0): slevy / odpuštění musí pokrýt doloženou spodní mez (do 1 Kč, u dřív
//    odpuštěného zbytku s tolerancí 1 Kč jako při odpuštění).
import { verifiedBookingFloors } from './due-verify.ts'
import type { DueKind } from './card-minimum.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

export type FloorResult = 'ok' | 'outdated' | 'unavailable'

export async function floorCheck(sb: Sb, b: Record<string, unknown>, a: { due: number; kind: DueKind; type: string }): Promise<FloorResult> {
  if (a.kind === 'free' || a.kind === 'below') return 'ok'
  const d1 = a.type === 'booking' && (a.kind === 'waive' || a.kind === 'round')
  const enforce = d1 || (a.type === 'booking' && Deno.env.get('PP_FLOOR_ENFORCE') === '1')
  const f = await verifiedBookingFloors(sb, b)
  if (f == null) return enforce ? 'unavailable' : 'ok'
  if (f.floor <= a.due + 1) {
    if (f.full > a.due + 1) await log(sb, 'booking_price_below_full_floor', 'info', b, a, f, false)
    return 'ok'
  }
  await log(sb, d1 ? 'card_minimum_price_unverified' : 'booking_price_below_floor', 'warning', b, a, f, enforce)
  return enforce ? 'outdated' : 'ok'
}

/** Rezervace s cenou 0: `accepted` = už ji uznaly dosavadní kontroly (100% kód / poukaz).
 *  Vrací true, když ji uznaly ony NEBO doložená spodní mez (slevy / odpuštění pokryjí cenu).
 *  Uznanou dosavadními kontrolami, kterou spodní mez nepotvrdí, jen zapíše do debug_log
 *  (`free_booking_floor_mismatch`) — ke kalibraci, než se i tady začne vynucovat. */
export async function freeVerifiedByFloor(sb: Sb, b: Record<string, unknown>, accepted = false): Promise<boolean> {
  if (Number(b.total_price || 0) > 0) return accepted
  const f = await verifiedBookingFloors(sb, b)
  if (f == null) return accepted
  const waived = Math.min(Math.max(-Number(b.card_rounding || 0), 0), 1)
  const ok = f.floor <= waived + 1
  if (accepted && !ok) await log(sb, 'free_booking_floor_mismatch', 'warning', b, { due: 0, kind: 'free', type: 'booking' }, f, false)
  return accepted || ok
}

async function log(sb: Sb, action: string, status: string, b: Record<string, unknown>, a: { due: number; kind: string; type: string },
  f: { floor: number; full: number }, enforced: boolean) {
  try {
    await sb.from('debug_log').insert({ source: 'process-payment', action, component: 'price_floor', status,
      request_data: { booking_id: b.id, type: a.type, kind: a.kind, due: a.due, floor: f.floor, floor_full: f.full, enforced } })
  } catch { /* ignore */ }
}
