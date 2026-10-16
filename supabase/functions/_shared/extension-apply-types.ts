// ===== _shared/extension-apply-types.ts =====
// Typy a drobné pomocníky pro dokončení zaplacené změny rezervace (D6, 2026-10-16).
// Sdílí webhook-receiver a process-payment (complete_extension, odpuštění do 1 Kč).

// deno-lint-ignore no-explicit-any
export type Sb = any

/** Výsledek pokusu o zapsání zaplacené změny.
 *  applied / already_applied = hotovo · no_payload = změna se do Stripe metadat
 *  nevešla (dokončí ji klient postaru) · retry = přechodná chyba (síť, DB 5xx,
 *  souběh) → zkusit znovu · failed = trvale nejde zapsat (motorku mezitím obsadil
 *  někdo jiný, rezervace skončila…) → vrátit doplatek + upozornit obsluhu. */
export type ApplyResult =
  | { state: 'applied'; bookingId: string; newBookingId?: string; totalPrice?: number }
  | { state: 'already_applied'; bookingId: string; newBookingId?: string; totalPrice?: number }
  | { state: 'no_payload' }
  | { state: 'retry'; code: string; detail?: string }
  | { state: 'failed'; code: string; reason: string; detail?: string; manual?: boolean }

export type ApplyArgs = {
  bookingId: string
  /** spojený payload změny (chg + chg_2…chg_8) */
  chg: string | null | undefined
  /** výsledek serverového dry-runu (metadata.srv) */
  srv?: string | null
  /** skutečně zaplaceno (Kč) — u dorovnání 15, u odpuštění 0 */
  paidCzk: number | null
  /** identita platby pro deduplikaci (PI id / session id / waive:…) */
  payRef: string | null
  /** D1: +r dorovnání na 15 Kč, −r odpuštěný doplatek do 1 Kč, |r| < 1 platba v celých Kč, jinak 0 */
  rounding?: number
  /** čas vytvoření platby (ISO) — výměna provedená OD té doby (klientem, souběžně) = hotovo */
  since?: string | null
}

export const round2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100

/** Otisk místa rezervace (delivery_fee + způsob a adresa obou stran) — process-payment
 *  ho dává do metadata.srv.f, apply podle něj pozná, že se místo mezitím změnilo. */
export function placeFingerprint(r: Record<string, unknown> | null): string {
  if (!r) return ''
  const norm = (v: unknown) => String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ')
  const src = [Math.round(Number(r.delivery_fee || 0)), norm(r.pickup_method), norm(r.pickup_address),
    norm(r.return_method), norm(r.return_address)].join('|')
  let h = 2166136261
  for (let i = 0; i < src.length; i++) { h ^= src.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0 }
  return h.toString(16)
}

/** Payload změny je v metadatech rozdělený po 500 znacích: chg, chg_2 … chg_8. */
export function chgFromMetadata(md: Record<string, string | undefined> | null | undefined): string | null {
  if (!md || !md.chg) return null
  let out = md.chg
  for (let i = 2; i <= 8; i++) {
    const part = md[`chg_${i}`]
    if (!part) break
    out += part
  }
  return out
}

/** `failed` + manual = nejednoznačný stav (např. rezervace už jezdí na nové motorce, ale
 *  bez záznamu této platby) → bez automatické vratky, rozhodne obsluha. */

/** Odmítnutí triggerem / omezením (překryv, zavřená pobočka, vozík, pojistka
 *  přistavení) = trvalé; vše ostatní (síť, 5xx, timeout) = přechodné. */
export function isPermanentDbError(e: { code?: string | null; message?: string | null } | null | undefined): boolean {
  const c = String(e?.code || '')
  return ['P0001', '23505', '23514', '23P01', '23502', '22P02', '22023'].includes(c)
}

/** Chybí funkce / její signatura (SQL ještě nenasazené). */
export function isMissingFunction(e: { code?: string | null; message?: string | null } | null | undefined): boolean {
  return /PGRST202|42883|could not find the function|does not exist/i.test(`${e?.code || ''} ${e?.message || ''}`)
}

export async function logDebug(sb: Sb, action: string, status: string, data: Record<string, unknown>, message?: string | null) {
  try {
    await sb.from('debug_log').insert({
      source: 'extension-apply', action, component: 'stripe', status,
      error_message: message ?? null, request_data: data,
    })
  } catch { /* ignore */ }
}
