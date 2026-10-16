// ===== process-payment/card-minimum.ts =====
// D1/D2 (rozhodnutí majitele 2026-10-16): minimální platba kartou je 15 Kč.
//   due ≤ 0          → zdarma (stávající cesty),
//   0 < due ≤ 1 Kč   → NEÚČTUJE SE (odpuštěno; nic se nestrhne),
//   1 < due < 15 Kč  → zaplatí se 15 Kč (dorovnání 15 − due),
//   due ≥ 15 Kč      → beze změny.
// `due` = SERVEROVÁ částka (total_price / dry-run doplatku / shop_orders.total),
// nikdy klientská. Server NIKDY nestrhne jinou částku, než klient poslal
// (`amount`) — dorovnává jen při `card_min: true` + `amount = 15`, odpouští jen
// při `card_min: true` + `amount < 15`. Staré appky (bez card_min) s částkou pod
// 15 Kč dostanou `below_minimum` (srozumitelný text, nic se nestrhne).
// Dorovnání se zapisuje do card_rounding (SQL 20261016p1) a JE součástí
// total_price / total — doklady ho vypisují samostatným řádkem. Dorovnání na 15 Kč
// zapisuje webhook AŽ PO zaplacení (_shared/charge-rounding.ts, metadata due /
// card_rounding); tady se hned zapisuje jen odpuštění (nic se nestrhne).

// deno-lint-ignore no-explicit-any
type Sb = any

export const CARD_MIN_CZK = 15
export const WAIVE_MAX_CZK = 1

export type DueKind = 'free' | 'waive' | 'round' | 'ok' | 'below'
export type DueClass = { kind: DueKind; due: number; charge: number; rounding: number }

export const round2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100

/** Zařazení platby podle serverové částky `due` a částky z požadavku. */
export function classifyDue(due: number, amount: number, cardMin: boolean): DueClass {
  const d = round2(Math.max(Number(due) || 0, 0))
  const amt = Math.round(Number(amount) || 0)
  if (!(d > 0)) return { kind: 'free', due: d, charge: 0, rounding: 0 }
  // ≤ 1 Kč se neúčtuje ani při zastaralé částce 15 z klienta; nad 15 Kč jde o upsell (běžná platba).
  if (cardMin && d <= WAIVE_MAX_CZK && amt <= CARD_MIN_CZK) return { kind: 'waive', due: d, charge: 0, rounding: round2(-d) }
  if (cardMin && d > WAIVE_MAX_CZK && d < CARD_MIN_CZK && amt === CARD_MIN_CZK) {
    return { kind: 'round', due: d, charge: CARD_MIN_CZK, rounding: round2(CARD_MIN_CZK - d) }
  }
  // Strhne se aspoň 15 Kč (běžná platba; u rezervace i s upsellem z e-shopu), nebo
  // serverová částka minimum splňuje a klient poslal jinou (nesoulad ceny) — částku
  // vůči `due` hlídá volající podle typu platby (amount_mismatch / free_mismatch).
  if (amt >= CARD_MIN_CZK || d >= CARD_MIN_CZK) return { kind: 'ok', due: d, charge: amt, rounding: 0 }
  return { kind: 'below', due: d, charge: CARD_MIN_CZK, rounding: d <= WAIVE_MAX_CZK ? round2(-d) : round2(CARD_MIN_CZK - d) }
}

/** Chybí sloupec card_rounding (SQL 20261016p1 ještě nenasazené)? */
export function isMissingColumn(e: { code?: string | null; message?: string | null } | null | undefined): boolean {
  return /42703|PGRST204|card_rounding/i.test(`${e?.code || ''} ${e?.message || ''}`)
}

export type CasResult = 'done' | 'raced' | 'unavailable' | 'error'

/** Atomické (compare-and-set) odpuštění na nezaplacené rezervaci nebo objednávce:
 *  zápis projde jen proti přesně tomu stavu, ze kterého se počítalo.
 *  0 řádků = souběžný požadavek byl rychlejší → volající znovu načte a zařadí. */
async function cas(sb: Sb, table: 'bookings' | 'shop_orders', id: string, due: number): Promise<CasResult> {
  const totalCol = table === 'bookings' ? 'total_price' : 'total'
  const { data: row, error: rErr } = await sb.from(table).select(`${totalCol}, card_rounding, payment_status`).eq('id', id).maybeSingle()
  if (rErr) return isMissingColumn(rErr) ? 'unavailable' : 'error'
  if (!row) return 'error'
  const t0 = Number(row[totalCol] ?? 0)
  const c0 = Number(row.card_rounding ?? 0)
  if (round2(t0) !== round2(due)) return 'raced'
  const unpaid = table === 'bookings' ? 'unpaid' : 'pending'
  if (row.payment_status !== unpaid) return 'raced'
  const patch: Record<string, number> = { [totalCol]: 0, card_rounding: round2(c0 - t0) }
  let q = sb.from(table).update(patch).eq('id', id).eq(totalCol, t0).eq('card_rounding', c0).eq('payment_status', unpaid)
  if (table === 'bookings') q = q.not('status', 'in', '(cancelled,completed)')
  const { data, error } = await q.select('id')
  if (error) return isMissingColumn(error) ? 'unavailable' : 'error'
  return Array.isArray(data) && data.length === 1 ? 'done' : 'raced'
}

export const waiveBooking = (sb: Sb, id: string, due: number) => cas(sb, 'bookings', id, due)
export const waiveShop = (sb: Sb, id: string, due: number) => cas(sb, 'shop_orders', id, due)

/** Ověří, že sloupec card_rounding na rezervacích existuje (doplatky úprav). */
export async function bookingRoundingAvailable(sb: Sb, id: string): Promise<boolean> {
  try {
    const { error } = await sb.from('bookings').select('card_rounding').eq('id', id).maybeSingle()
    return !error
  } catch { return false }
}
