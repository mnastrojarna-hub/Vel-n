// ===== _shared/agent-knowledge/gear-booking.ts =====
// Rezervace JEN VÝBAVY (bookings.booking_kind='gear', 2026-10-23) v nástrojích a
// kontextech agentů: rozpoznání, čitelný souhrn kusů a doplnění výsledků RPC, které
// gear neznají (ai_lookup_bookings_by_contact vrací „Motorka“, find_booking_light
// moto_name NULL, ai_booking_readiness bez pobočky). Čte service role; kódy ani
// doklady nevrací. `moto_id IS NULL` samo o sobě gear NEZNAMENÁ (FK SET NULL) —
// rozhoduje jen booking_kind.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

type Row = Record<string, unknown>

export const GEAR_BOOKING_TITLE_CS = 'Výpůjčka výbavy'
export const GEAR_KEYS = ['helmet', 'jacket', 'pants', 'gloves', 'boots'] as const
export const GEAR_LABEL_CS: Record<string, string> = { helmet: 'helma', jacket: 'bunda', pants: 'kalhoty', gloves: 'rukavice', boots: 'boty' }

/** Sloupce bookings potřebné pro gear souhrn (do selectů agentů). */
export const GEAR_BOOKING_COLS = 'booking_kind, branch_id, gear_lines, gear_per_day, helmet_size, jacket_size, pants_size, gloves_size, boots_size'

export function isGearBooking(b: Row | null | undefined): boolean {
  return !!b && b.booking_kind === 'gear'
}

// Sloupce, které přidala až migrace 20261023a (branch_id a *_size existovaly dřív).
const GEAR_NEW_COLS = new Set(['booking_kind', 'gear_lines', 'gear_per_day'])

/** PostgREST „sloupec neexistuje“ u sloupců z 20261023a — edge (deploy-functions.yml) běží dřív
 *  než SQL (deploy-sql.yml, nezávislý workflow), nebo migrace spadla a blokuje řetěz. */
export function isMissingGearColumn(err: unknown): boolean {
  if (!err) return false
  const e = (typeof err === 'object' ? err : { message: String(err) }) as Row
  const msg = `${e.message ?? ''} ${e.details ?? ''} ${e.hint ?? ''}`
  return /\b(booking_kind|gear_lines|gear_per_day)\b/.test(msg)
    && (e.code === '42703' || e.code === 'PGRST204' || /does not exist|could not find|schema cache/i.test(msg))
}

/** Výčet sloupců bez sloupců z 20261023a (dělí jen čárky nejvyšší úrovně — embedy v závorkách zůstanou). */
export function stripGearCols(cols: string): string {
  const parts: string[] = []
  let depth = 0, cur = ''
  for (const ch of cols) {
    if (ch === '(') depth++
    else if (ch === ')') depth--
    if (ch === ',' && depth === 0) { parts.push(cur); cur = ''; continue }
    cur += ch
  }
  parts.push(cur)
  return parts.map((p) => p.trim()).filter((p) => p && !GEAR_NEW_COLS.has(p)).join(', ')
}

/**
 * Select rezervací se zálohou na starší schéma: chybí-li sloupce z 20261023a, dotaz se
 * zopakuje bez nich → rezervace MOTOREK fungují jako před výpůjčkou výbavy (gear řádky
 * bez sloupce booking_kind existovat nemohou). `run(cols)` = celý dotaz včetně filtrů.
 */
export async function selectGearSafe<D = Row[]>(cols: string, run: (cols: string) => PromiseLike<unknown>): Promise<SelectRes<D>> {
  const r = await run(cols) as SelectRes<D>
  if (!r.error || !isMissingGearColumn(r.error)) return r
  console.warn('[gear] chybí sloupce z migrace 20261023a — dotaz bez nich (rezervace motorek beze změny)')
  return await run(stripGearCols(cols)) as SelectRes<D>
}

/** Výsledek selectu (dynamický výčet sloupců → řádky jako obecné objekty). */
export type SelectRes<D> = { data: D | null; error: { message: string; code?: string } | null; count?: number | null }

/** „Komplet bez bot (helma M, bunda L, kalhoty L, rukavice M) · boty 43“ — z gear_lines, jinak z velikostí. */
export function gearItemsCs(b: Row): string {
  const lines = Array.isArray(b.gear_lines) ? (b.gear_lines as Row[]) : []
  const sz = (o: unknown) => Object.entries((o || {}) as Record<string, unknown>)
    .map(([k, v]) => `${GEAR_LABEL_CS[k] || k}${v ? ' ' + v : ''}`).join(', ')
  if (lines.length) {
    return lines.map((l) => l.kind === 'set' ? `${l.label} (${sz(l.sizes)})` : sz(l.sizes) || String(l.label || l.key)).join(' · ')
  }
  const parts = GEAR_KEYS.filter((k) => b[`${k}_size`]).map((k) => `${GEAR_LABEL_CS[k]} ${b[`${k}_size`]}`)
  return parts.length ? parts.join(', ') : '?'
}

/** Pobočka gear rezervace — embed `gear_branch` (customer-branch.ts) / `booking_branch` / `branches`. */
export function gearBranchOf(b: Row): Row | null {
  return ((b.gear_branch || b.booking_branch || b.branches) as Row | null) || null
}

/** Řádek „Výpůjčka výbavy (helma M, …) — pobočka X“ pro výpisy více rezervací. */
export function gearBookingLabel(b: Row): string {
  return `${GEAR_BOOKING_TITLE_CS} (${gearItemsCs(b)})`
}

const GEAR_NOTE = 'Výpůjčka JEN VÝBAVY (bez motorky) — viz pravidlo VÝPŮJČKA VÝBAVY BEZ MOTORKY: doklady jen doklad totožnosti (ŘP ne), na samoobsluze jen kód šatny (+ kód schránky od brány), žádný kód motorky, kóje ani SOS.'

/**
 * Fakta gear rezervace pro výsledky toolů; null = rezervace motorky (nebo nenalezena).
 * `minimal` = jen druh rezervace (tazatel ověřený jen číslem rezervace — pobočku ani
 * velikosti konkrétní rezervace neprozrazujeme, stejně jako u motorky; pevné pravidlo 32).
 */
export async function gearBookingFacts(sb: SupabaseClient, bookingId: string, opts: { minimal?: boolean } = {}): Promise<Row | null> {
  try {
    const { data, error } = await sb.from('bookings')
      .select(`${GEAR_BOOKING_COLS}, branch:branches!branch_id(name, city, type)`).eq('id', bookingId).maybeSingle()
    if (error || !data || !isGearBooking(data as Row)) return null
    const b = data as Row
    if (opts.minimal) return { booking_kind: 'gear', gear_only: true, title: GEAR_BOOKING_TITLE_CS, gear_note: GEAR_NOTE }
    const br = (b.branch as Row | null) || null
    return {
      booking_kind: 'gear', gear_only: true, title: GEAR_BOOKING_TITLE_CS,
      gear_items: gearItemsCs(b), gear_per_day: b.gear_per_day ?? null,
      branch: br ? { name: br.name, city: br.city ?? null, type: br.type ?? null, self_service: br.type === 'samoobslužná' } : null,
      gear_note: GEAR_NOTE,
    }
  } catch { return null }
}

/** Doplní gear fakta do výsledku toolu (objekt s `success`), když jde o gear rezervaci. */
export async function withGearFacts(sb: SupabaseClient, data: unknown, bookingId: string | null | undefined, opts: { minimal?: boolean } = {}): Promise<unknown> {
  if (!bookingId || !data || typeof data !== 'object' || Array.isArray(data)) return data
  const d = data as Row
  if (d.success === false || d.moto_id) return data   // s motorkou = rezervace motorky, dotaz netřeba
  const f = await gearBookingFacts(sb, bookingId, opts)
  if (!f) return data
  const out: Row = { ...d, ...f }
  if ('moto_name' in d) out.moto_name = null
  return out
}

/**
 * `ai_lookup_bookings_by_contact` vrací u rezervace bez motorky moto_name „Motorka“ —
 * u takových řádků přeloží booking_number (resolve_booking_ref) a doplní gear fakta.
 */
export async function annotateGearLookup(sb: SupabaseClient, data: unknown): Promise<unknown> {
  const d = (data || {}) as Row
  if (!Array.isArray(d.bookings)) return data
  const rows = await Promise.all((d.bookings as Row[]).map(async (r) => {
    if (r.moto_name && r.moto_name !== 'Motorka') return r
    try {
      const { data: ref } = await sb.rpc('resolve_booking_ref', { p_ref: String(r.booking_number || '') })
      const id = (ref as Row | null)?.success ? String((ref as Row).booking_id || '') : ''
      const f = id ? await gearBookingFacts(sb, id) : null
      return f ? { ...r, ...f, moto_name: null } : r
    } catch { return r }
  }))
  return { ...d, bookings: rows }
}
