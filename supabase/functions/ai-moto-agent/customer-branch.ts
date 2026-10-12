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

const BRANCH_COLS = 'id, name, address, city, phone, type, is_open, notes, gps_lat, gps_lng'

/** Embed pobočky REZERVACE (alias `booking_branch`) do selectu z `bookings`. */
export const BOOKING_BRANCH_SELECT = `booking_branch:branches!branch_id(${BRANCH_COLS})`

type Row = Record<string, unknown>

/** Pobočku rezervace propíše do motorcycles.branches (všechny formátovače čtou odtud). */
export function preferBookingBranch(rows: Array<Row | null | undefined>): void {
  for (const b of rows) {
    if (!b) continue
    const bb = b.booking_branch as Row | null
    const m = b.motorcycles as Row | null
    if (bb && m) m.branches = bb
    delete b.booking_branch
  }
}

/** Název pobočky rezervace (pro výpisy více rezervací). */
export function bookingBranchName(b: Row): string {
  const br = ((b.motorcycles as Row | null)?.branches as Row | null) || null
  return br ? String(br.name || br.city || '?') : '?'
}

/** Kontext pro zákazníka BEZ aktivní/nadcházející rezervace: pending → poslední dokončená. */
export async function customerBranchFallback(sb: SupabaseClient, userId: string): Promise<string> {
  const sel = `id, status, start_date, end_date, ${BOOKING_BRANCH_SELECT},
    motorcycles!moto_id(brand, model, branches!branch_id(${BRANCH_COLS}))`
  const today = new Date().toISOString().slice(0, 10)
  const [pend, done] = await Promise.all([
    sb.from('bookings').select(sel).eq('user_id', userId).eq('status', 'pending')
      .gte('end_date', today).order('created_at', { ascending: false }).limit(1),
    sb.from('bookings').select(sel).eq('user_id', userId).eq('status', 'completed')
      .order('end_date', { ascending: false }).limit(1),
  ])
  const b = ((!pend.error && pend.data?.[0]) || (!done.error && done.data?.[0]) || null) as Row | null
  if (!b) return ''
  preferBookingBranch([b])
  await markBookingsGate(sb, [b])
  const m = b.motorcycles as Row | null
  if (!(m?.branches)) return ''
  const moto = `${m.brand || ''} ${m.model || ''}`.trim() || '?'
  const why = b.status === 'pending'
    ? `rozpracovaná NEZAPLACENÁ rezervace #${String(b.id).slice(-8).toUpperCase()} (${moto}, ${b.start_date} – ${b.end_date}) — chystá se ji využít`
    : `naposledy si půjčil ${moto} (${b.start_date} – ${b.end_date}, dokončeno)`
  return `\n\n## POBOČKA ZÁKAZNÍKA (z jeho rezervací — ber ji jako výchozí):
Zákazník teď nemá zaplacenou aktivní ani nadcházející rezervaci, ale ${why}.
${formatBranchLines(m, false)}
Na obecné dotazy (kde si motorku vyzvednu/vrátím, jak probíhá výdej a vrácení, mytí, tankování, kódy) odpovídej ROVNOU pro tuto pobočku — neptej se, kterou pobočku myslí, a nemluv obecně o obou. Jen když sám zmíní jinou pobočku nebo novou rezervaci jinde, řiď se jí (seznam v sekci POBOČKY).`
}
