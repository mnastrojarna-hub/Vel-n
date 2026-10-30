// ===== _shared/extension-apply-gear.ts =====
// Placená změna výbavy (web, `_gear`) — vyčleněno z extension-apply.ts (2026-10-16).
// D1 (oprava po kontrole): dorovnání / odpuštění se zapisuje v TÉMŽE zápisu jako změna
// výbavy — apply_paid_gear_change rev.2 (SQL 20261016p4) dostane zaplacenou částku
// (p_paid), dorovnání spočítá ze skutečného doplatku a zapíše ho s cenou; mail o úpravě
// a rozdílový DP pak nesou zaplacenou částku s řádkem dorovnání. Dřív šlo dorovnání
// zvlášť milisekundy po změně → spadlo do deduplikace mailu a DP chyběl (odpuštěná
// výbava 0,60 Kč dostala dokonce DP na 1 Kč). Značka platby (payment_ref) v historii
// = opakování nic nepřičte (RPC vrátí already_applied).
// Samostatné dorovnání (extension-apply-rounding.ts) zůstává jen pro změnu, kterou
// zapsal web sám bez dorovnání (doplatek při zápisu 0), a pro SQL bez rev.2.
import type { ApplyArgs, ApplyResult, Sb } from './extension-apply-types.ts'
import { isMissingFunction, logDebug, otherPaymentEntry, round2 } from './extension-apply-types.ts'
import { roundingFixup } from './extension-apply-rounding.ts'

type RpcRes = { data: Record<string, unknown> | null; error: { code?: string; message?: string } | null }

export async function applyGear(sb: Sb, args: ApplyArgs, sizes: Record<string, unknown>, hash: string | null): Promise<ApplyResult> {
  const bookingId = args.bookingId
  const r = round2(Number(args.rounding || 0))
  const call = async (p: Record<string, unknown>): Promise<RpcRes> => {
    try {
      const res = await sb.rpc('apply_paid_gear_change', p)
      return { data: (res.data || null) as Record<string, unknown> | null, error: res.error || null }
    } catch (e) { return { data: null, error: { message: (e as Error).message } } }
  }
  const full: Record<string, unknown> = { p_booking_id: bookingId, p_sizes: sizes, p_payment_ref: args.payRef || null, p_chg_hash: hash }
  if (args.paidCzk != null && Number.isFinite(args.paidCzk)) full.p_paid = round2(args.paidCzk)
  else if (r !== 0) full.p_card_rounding = r
  let { data, error } = await call(full)
  // rev.2 ještě nenasazená → 2parametrová verze (dorovnání pak zvlášť; process-payment
  // dorovnání výbavy bez rev.2 nepovolí, takže jde jen o pojistku).
  let legacy = false
  if (error && isMissingFunction(error)) {
    legacy = true
    ;({ data, error } = await call({ p_booking_id: bookingId, p_sizes: sizes }))
  }
  const failed = !error && data && data.success === false
  await logDebug(sb, error || failed ? 'gear_change_apply_failed' : 'gear_change_applied', error || failed ? 'error' : 'ok',
    { booking_id: bookingId, rpc_result: data, legacy, payment_ref: args.payRef }, error?.message || (failed ? String(data?.error || '') : null))
  if (error) return isMissingFunction(error) ? { state: 'no_payload' } : { state: 'retry', code: 'apply_failed', detail: error.message }
  if (failed) return { state: 'failed', code: 'change_failed', reason: String(data?.error || 'gear_failed') }
  if (data?.already_applied === true) return { state: 'already_applied', bookingId }
  if (r === 0) return { state: 'applied', bookingId }
  // Dorovnání zapsané v témže zápisu (rev.2) → hotovo.
  if (!legacy && round2(Number(data?.card_rounding ?? 0)) !== 0) return { state: 'applied', bookingId }
  if (Number(data?.net_diff ?? NaN) === 0) {
    // RPC nic nezměnila: tutéž změnu (chg_hash) od vytvoření platby zaplatila JINÁ platba → duplicita;
    // jinak ji zapsal web sám (bez dorovnání) → dorovnání této platby zvlášť, jednou (payment_ref).
    if (hash) {
      const other = await otherRefWithHash(sb, bookingId, hash, args)
      if (other) {
        await logDebug(sb, 'gear_change_duplicate', 'error', { booking_id: bookingId, payment_ref: args.payRef, other_ref: other })
        return { state: 'duplicate', bookingId, otherRef: other }
      }
    }
    const rr = await roundingFixup(sb, bookingId, r, args, hash)
    if (rr) return rr
  } else if (legacy) {
    const rr = await roundingFixup(sb, bookingId, r, args, hash)
    if (rr) return rr
  }
  // Doplatek > 0, ale rev.2 dorovnání neuplatnila (zaplaceno nesedí s doplatkem — cena se
  // mezitím změnila): záznam gear_paid_mismatch v debug_log, rozhodne obsluha.
  return { state: 'applied', bookingId }
}

async function otherRefWithHash(sb: Sb, bookingId: string, hash: string, args: ApplyArgs): Promise<string | null> {
  try {
    const { data } = await sb.from('bookings').select('modification_history').eq('id', bookingId).maybeSingle()
    const hist = Array.isArray(data?.modification_history) ? (data.modification_history as Array<Record<string, unknown> | null>) : []
    const sinceMs = args.since ? Date.parse(args.since) : NaN
    const e = hist.find((h) => !!h && h.chg_hash === hash && otherPaymentEntry(h, args.payRef, Number.isFinite(sinceMs) ? sinceMs : null))
    return e ? String(e.payment_ref) : null
  } catch { return null }
}
