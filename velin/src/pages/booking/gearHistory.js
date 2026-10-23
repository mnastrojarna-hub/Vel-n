// Záznamy modification_history výpůjčky JEN výbavy (booking_kind 'gear') pro describeHistoryEntry:
//  • gear_admin_update — Velín admin_update_gear_booking (+ „Zdarma“ úprava GearModifyModal, charged:false):
//    from_start/from_end/to_start/to_end, from/to = mapy velikostí {helmet:'M',…}, from_branch/to_branch, from_total/to_total
//  • gear_sizes  — zákazník customer_update_gear_sizes (from/to, bez termínu a ceny)
//  • gear_remove — zákazník customer_remove_gear_item (key, from/to, price_diff = nová − stará cena,
//    refund_amount / refund_percent dle pravidla vratek §1.11)
// Termín popisuje describeHistoryEntry (jen když záznam data nese); tady kusy, velikosti, pobočka a cena.
import { GEAR_KEYS, GEAR_LABELS } from '../../lib/bookingKind'

export const GEAR_HISTORY_TYPES = ['gear_admin_update', 'gear_sizes', 'gear_remove']
export const isGearHistoryEntry = h => GEAR_HISTORY_TYPES.includes(h?.type)

const asMap = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
const kc = n => `${Math.abs(Number(n) || 0).toLocaleString('cs-CZ')} Kč`
const num = v => (v === null || v === undefined || v === '' ? NaN : Number(v))

/** Kusy a velikosti: „Helma M → L, Rukavice přidáno (M), Boty 43 → odebráno“ (pořadí ceníku). */
export function gearItemChanges(h) {
  const from = asMap(h?.from), to = asMap(h?.to)
  const keys = [...GEAR_KEYS, ...Object.keys({ ...from, ...to }).filter(k => !GEAR_KEYS.includes(k))]
  const out = []
  for (const k of keys) {
    const a = from[k] ? String(from[k]) : null
    const b = to[k] ? String(to[k]) : null
    if (a === b) continue
    const lbl = GEAR_LABELS[k] || k
    out.push(a && !b ? `${lbl} ${a} → odebráno` : !a ? `${lbl} přidáno (${b})` : `${lbl} ${a} → ${b}`)
  }
  // gear_remove bez map (starší tvar) — aspoň odebraný kus
  if (!out.length && h?.type === 'gear_remove' && h.key) out.push(`${GEAR_LABELS[h.key] || h.key} odebráno`)
  return out
}

/**
 * Popis gear záznamu → { items:[…], changes:[text], branchChanged }. Cena: gear_admin_update = to_total − from_total
 * (u „Zdarma“ charged:false jen poznámka o neúčtovaném rozdílu), gear_remove = price_diff + skutečná vratka.
 */
export function describeGearHistory(h) {
  const items = gearItemChanges(h)
  const changes = []
  if (items.length) changes.push(`výbava: ${items.join(', ')}`)
  const branchChanged = !!(h.from_branch && h.to_branch && h.from_branch !== h.to_branch)
  if (branchChanged) changes.push('změna pobočky')

  if (h.type === 'gear_remove') {
    const diff = num(h.price_diff)
    if (Number.isFinite(diff) && diff !== 0) changes.push(`cena ${diff > 0 ? '+' : '−'}${kc(diff)}`)
    const refund = num(h.refund_amount)
    if (Number.isFinite(refund) && refund > 0) changes.push(`vratka ${kc(refund)}${h.refund_percent != null ? ` (${h.refund_percent} %)` : ''}`)
    else if (Number.isFinite(diff) && diff < 0 && Number.isFinite(refund)) changes.push('bez vratky')
  } else if (h.charged === false) {
    const free = num(h.free_diff)
    if (Number.isFinite(free) && free !== 0) changes.push(`zdarma — rozdíl ${free > 0 ? '+' : '−'}${kc(free)} neúčtován`)
  } else {
    const diff = num(h.to_total) - num(h.from_total)
    if (Number.isFinite(diff) && diff !== 0) changes.push(diff > 0 ? `doplatek +${kc(diff)}` : `vratka −${kc(diff)}`)
  }
  return { items, changes, branchChanged }
}
