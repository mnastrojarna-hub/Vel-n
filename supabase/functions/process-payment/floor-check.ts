// ===== process-payment/floor-check.ts =====
// D1/D4 (oprava 2026-10-16): bookings.total_price zapisuje klient (RLS) — server ji
// ověřuje proti spodní mezi z ceníku (due-verify.ts):
//  • odpuštění do 1 Kč / dorovnání na 15 Kč u rezervace → VYNUCENO (beze změny),
//  • běžná platba rezervace / SOS → zatím jen záznam do debug_log (`booking_price_below_floor`)
//    ke kalibraci; PP_FLOOR_ENFORCE=1 vynutí i tu (jen typ booking — SOS cenu určuje obsluha),
//  • rezervace OBNOVENÁ zákazníkem v appce (restored_by_source 'app', SQL 20261016p2) → VYNUCENO
//    vždy (pojistka k _customer_restore_check: draft za mimosezónní cenu nejde nechat propadnout,
//    v sezóně obnovit a zaplatit za starou cenu),
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
  const restored = a.type === 'booking' && b.restored_by_source === 'app'
  const enforce = d1 || restored || (a.type === 'booking' && Deno.env.get('PP_FLOOR_ENFORCE') === '1')
  const f = await verifiedBookingFloors(sb, b)
  if (f == null) return enforce ? 'unavailable' : 'ok'
  if (f.floor <= a.due + 1) {
    if (f.full > a.due + 1) await log(sb, 'booking_price_below_full_floor', 'info', b, a, f, false)
    return 'ok'
  }
  await log(sb, d1 ? 'card_minimum_price_unverified' : restored ? 'restored_price_below_floor' : 'booking_price_below_floor', 'warning', b, a, f, enforce)
  return enforce ? 'outdated' : 'ok'
}

/** Rezervace s cenou 0: `accepted` = už ji uznaly dosavadní kontroly (100% kód / poukaz).
 *  Vrací true, když ji uznaly ony NEBO doložená spodní mez (slevy / odpuštění pokryjí cenu).
 *  Oprava i2 (2026-11-05): dosavadní kontroly věří sloupcům, které si zákazník zapisuje sám (total_price,
 *  discount_amount, voucher_id — RLS bookings_user_update): vlastní poukaz na 100 Kč + total_price 0 +
 *  discount_amount 100 „pokryl“ libovolnou cenu. Uznanou dosavadními kontrolami, kterou spodní mez NEpotvrdí
 *  (`f.floor > odpuštěno + 1`), teď zapíše do debug_log (`free_booking_floor_mismatch`), POKAŽDÉ pošle mail
 *  obsluze a s `PP_FREE_FLOOR_ENFORCE=1` ji ODMÍTNE (→ free_mismatch, nic se nepotvrdí). Bez env = kalibrace
 *  (chování jako dřív + mail). Nelze-li mez spočítat (chyba RPC) → jako dosud `accepted`. */
export async function freeVerifiedByFloor(sb: Sb, b: Record<string, unknown>, accepted = false): Promise<boolean> {
  if (Number(b.total_price || 0) > 0) return accepted
  const f = await verifiedBookingFloors(sb, b)
  if (f == null) return accepted
  const waived = Math.min(Math.max(-Number(b.card_rounding || 0), 0), 1)
  const ok = f.floor <= waived + 1
  if (accepted && !ok) {
    const enforce = Deno.env.get('PP_FREE_FLOOR_ENFORCE') === '1'
    await log(sb, 'free_booking_floor_mismatch', enforce ? 'error' : 'warning', b, { due: 0, kind: 'free', type: 'booking' }, f, enforce)
    await freeMismatchMail(b, f, enforce)
    if (enforce) return false
  }
  return accepted || ok
}

async function freeMismatchMail(b: Record<string, unknown>, f: { floor: number; full: number }, enforced: boolean) {
  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const num = String(b.id || '').slice(-8).toUpperCase()
    await fetch(`${url}/functions/v1/send-email`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ to: 'info@motogo24.cz',
        subject: `⚠️ Rezervace #${num} za 0 Kč: slevy nepokrývají cenu dle ceníku (${f.floor} Kč) — ${enforced ? 'ODMÍTNUTO' : 'potvrzeno, prověřte'}`,
        raw_html: `<p style="margin:0 0 8px">Rezervace <strong>#${num}</strong> (${String(b.id || '')}) má cenu 0 Kč a zákazník ji potvrzuje jako zdarma `
          + `(promo kód / poukaz dle řádku rezervace), ale server z ceníku dokládá nejméně <strong>${f.floor} Kč</strong> `
          + `(vč. výbavy a dopravy ${f.full} Kč) nepokrytých doloženými slevami. Uložená sleva: ${String(b.discount_amount ?? 0)} Kč, `
          + `poukaz ${String(b.voucher_id || '—')}, promo ${String(b.promo_code_id || '—')}.</p>`
          + (enforced
            ? '<p style="margin:0">Potvrzení bylo ODMÍTNUTO (PP_FREE_FLOOR_ENFORCE=1) — zákazník vidí „slevu nejde ověřit“. Zkontrolujte poukaz / kód a rezervaci případně potvrďte ručně.</p>'
            : '<p style="margin:0">Rezervace BYLA potvrzena (kalibrační režim). Zkontrolujte poukaz / kód — sloupce rezervace si zákazník umí přepsat sám. Vynucení: PP_FREE_FLOOR_ENFORCE=1.</p>') }),
    })
  } catch { /* ignore */ }
}

async function log(sb: Sb, action: string, status: string, b: Record<string, unknown>, a: { due: number; kind: string; type: string },
  f: { floor: number; full: number }, enforced: boolean) {
  try {
    await sb.from('debug_log').insert({ source: 'process-payment', action, component: 'price_floor', status,
      request_data: { booking_id: b.id, type: a.type, kind: a.kind, due: a.due, floor: f.floor, floor_full: f.full, enforced } })
  } catch { /* ignore */ }
}
