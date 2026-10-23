// ===== ai-moto-agent/customer-branch.ts =====
// POBOČKA ZÁKAZNÍKA (2026-10-12, zadání majitele): agent v appce má sám vědět, kterou
// pobočku zákazník reálně využívá nebo se chystá využít — ne se ptát / mluvit obecně.
// Zdroj: bookings.branch_id (od 2026-10-10 = pobočka skutečného převzetí; do vyzvednutí
// následuje motorku) má přednost před AKTUÁLNÍ pobočkou motorky (ta se po vrácení /
// přesunu mění). Bez aktivní/nadcházející rezervace: rozpracovaná nezaplacená, jinak
// poslední dokončená rezervace.

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { markBookingsGate } from '../_shared/agent-knowledge/branch-gate.ts'
import { formatBranchLines } from './booking-context.ts'
import { bookingTitle, formatGearBranchLines, isGearBooking } from './gear-context.ts'
import { GEAR_BOOKING_COLS, selectGearSafe } from '../_shared/agent-knowledge/gear-booking.ts'

const BRANCH_COLS = 'id, name, address, city, phone, type, is_open, notes, gps_lat, gps_lng'

/** Embed pobočky REZERVACE (alias `booking_branch`) do selectu z `bookings`. */
export const BOOKING_BRANCH_SELECT = `booking_branch:branches!branch_id(${BRANCH_COLS})`

type Row = Record<string, unknown>

/** Pobočku rezervace propíše do motorcycles.branches (všechny formátovače čtou odtud);
 *  výpůjčka jen výbavy (booking_kind='gear', 2026-10-23) ji drží v `gear_branch`. Rezervace
 *  motorky se smazanou motorkou (FK SET NULL) zůstává beze změny — rozhoduje jen booking_kind. */
export function preferBookingBranch(rows: Array<Row | null | undefined>): void {
  for (const b of rows) {
    if (!b) continue
    const bb = b.booking_branch as Row | null
    const m = b.motorcycles as Row | null
    if (bb && m) m.branches = bb
    else if (bb && !m && isGearBooking(b)) b.gear_branch = bb
    delete b.booking_branch
  }
}

/** Název pobočky rezervace (pro výpisy více rezervací). */
export function bookingBranchName(b: Row): string {
  const br = ((b.motorcycles as Row | null)?.branches as Row | null) || (b.gear_branch as Row | null) || null
  return br ? String(br.name || br.city || '?') : '?'
}

/** Kontext pro zákazníka BEZ aktivní/nadcházející rezervace: pending → poslední dokončená. */
export async function customerBranchFallback(sb: SupabaseClient, userId: string): Promise<string> {
  const sel = `id, status, start_date, end_date, ${GEAR_BOOKING_COLS}, ${BOOKING_BRANCH_SELECT},
    motorcycles!moto_id(brand, model, branches!branch_id(${BRANCH_COLS}))`
  const today = new Date().toISOString().slice(0, 10)
  // selectGearSafe: bez migrace 20261023a dotaz bez gear sloupců (motorky beze změny)
  const [pend, done] = await Promise.all([
    selectGearSafe(sel, (c) => sb.from('bookings').select(c).eq('user_id', userId).eq('status', 'pending')
      .gte('end_date', today).order('created_at', { ascending: false }).limit(1)),
    selectGearSafe(sel, (c) => sb.from('bookings').select(c).eq('user_id', userId).eq('status', 'completed')
      .order('end_date', { ascending: false }).limit(1)),
  ])
  const b = ((!pend.error && pend.data?.[0]) || (!done.error && done.data?.[0]) || null) as Row | null
  if (!b) return ''
  preferBookingBranch([b])
  await markBookingsGate(sb, [b])
  const m = b.motorcycles as Row | null
  const gear = isGearBooking(b)
  if (!(m?.branches) && !(gear && b.gear_branch)) return ''
  const moto = bookingTitle(b)
  const why = b.status === 'pending'
    ? `rozpracovaná NEZAPLACENÁ rezervace #${String(b.id).slice(-8).toUpperCase()} (${moto}, ${b.start_date} – ${b.end_date}) — chystá se ji využít`
    : `naposledy si půjčil ${gear ? `jen výbavu — ${moto}` : moto} (${b.start_date} – ${b.end_date}, dokončeno)`
  return `\n\n## POBOČKA ZÁKAZNÍKA (z jeho rezervací — ber ji jako výchozí):
Zákazník teď nemá zaplacenou aktivní ani nadcházející rezervaci, ale ${why}.
${gear ? formatGearBranchLines(b.gear_branch as Row) : formatBranchLines(m, false)}
Na obecné dotazy (kde si motorku vyzvednu/vrátím, jak probíhá výdej a vrácení, mytí, tankování, kódy) odpovídej ROVNOU pro tuto pobočku — neptej se, kterou pobočku myslí, a nemluv obecně o obou. Jen když sám zmíní jinou pobočku nebo novou rezervaci jinde, řiď se jí (seznam v sekci POBOČKY).`
}
