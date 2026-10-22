// submit-handover-protocol — varianta výpůjčky JEN výbavy (bookings.booking_kind = 'gear',
// DESIGN-GEAR §3.4, 2026-10-23). Rozdíly proti motorce (index.ts volá jen tyto háčky):
//  • identita kiosku = VYDANÝ kód ŠATNY (code_type 'accessories') téže rezervace na pobočce
//    zařízení — gear rezervace kód k motorce nemá;
//  • typ pobočky z bookings.branch_id (motorka nemá) — samostatný dotaz, embed by při
//    nejednoznačné FK shodil celý podpis;
//  • žádné km / VIN / kontroly motorky / výbava motorky; kontroly gear_condition / gear_fit /
//    gear_return (kiosk: předvyplněné — podpis je potvrzuje, jako u motorky);
//  • číselník velikostí = aktivní kusy gear_rental_prices ∩ limity samoobsluhy (selfServiceSizeOk),
//    přidat kus nejde (vše je placené), odebrat poslední kus nejde (zanikl by kód šatny a
//    strážce trg_zz_gear_booking_guard by zápis odmítl) → odebrání se vrátí, jen ☐ v dokumentu;
//  • změněná velikost se propíše i do gear_lines (doklady / KF tisknou velikosti z řádků);
//  • e-mail `handover_protocol_gear_sent`, chybí-li šablona (404) → `handover_protocol_sent`
//    s předmětem „Motorkářská výbava (bez motocyklu)“ místo motorky; filled_data._gear_only.

import { GEAR_KEYS, selfServiceSizeOk, type AccessoryItem, type SizeUpdates } from './gear.ts'
import { esc, makeTr } from './i18n.ts'
import { gearDateLabel, gearDaysLabel } from './i18n-gear.ts'

// deno-lint-ignore no-explicit-any
type Admin = any
type Row = Record<string, unknown>

export const GEAR_MAIL_SLUG = 'handover_protocol_gear_sent'
export const BASE_MAIL_SLUG = 'handover_protocol_sent'
export const GEAR_DEFAULT_CHECKS = { gear_condition: true, gear_fit: true, gear_return: true } as const

export function isGearBooking(b: Row | null | undefined): boolean {
  return !!b && b.booking_kind === 'gear'
}

/** Typ kódu, kterým se kiosk prokazuje (VYDANÝ kód téže rezervace na pobočce zařízení). */
export function kioskIdentityCodeType(gear: boolean): 'accessories' | 'motorcycle' {
  return gear ? 'accessories' : 'motorcycle'
}

export interface GearBranch { id: string; type: string | null; name: string | null; address: string | null; city: string | null }

/** Pobočka gear rezervace (bookings.branch_id); neexistuje → null (index.ts → not_self_service, trvalá 4xx).
 *  Chyba DB VYHODÍ výjimku → index.ts vrátí 500 = dočasná chyba, kiosk podpis z fronty zopakuje (§0). */
export async function loadGearBranch(admin: Admin, branchId: unknown): Promise<GearBranch | null> {
  if (!branchId) return null
  const { data, error } = await admin.from('branches').select('id, type, name, address, city').eq('id', String(branchId)).maybeSingle()
  if (error) throw new Error(`gear_branch_lookup: ${error.message}`)
  return (data as GearBranch | null) || null
}

export type GearPriceRow = { key: string; kind: string; label?: string | null; sizes?: string[] | null; is_active?: boolean | null }

/** Ceník výpůjčky (aktivní kusy) → povolené velikosti na samoobsluze (gear.ts selfServiceSizeOk, dospělá velikost). */
export function gearAllowedSizes(rows: GearPriceRow[]): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>()
  for (const r of rows) {
    if (r.kind !== 'item' || r.is_active === false || !(GEAR_KEYS as readonly string[]).includes(r.key)) continue
    const s = out.get(r.key) ?? new Set<string>()
    for (const x of r.sizes || []) {
      const v = String(x).trim()
      if (v && selfServiceSizeOk(r.key, v, false)) s.add(v)
    }
    out.set(r.key, s)
  }
  return out
}

/** Číselník velikostí z DB; chyba dotazu = prázdný (velikost se nezapíše — jako u accessory_types). */
export async function loadGearAllowedSizes(admin: Admin): Promise<Map<string, Set<string>>> {
  try {
    const { data, error } = await admin.from('gear_rental_prices').select('key, kind, sizes, is_active').eq('kind', 'item')
    return error ? new Map() : gearAllowedSizes((data || []) as GearPriceRow[])
  } catch { return new Map() }
}

/** Kiosk: kontroly výpůjčky předvyplněné (podpis je potvrzuje), poslané hodnoty mají přednost. */
export function gearKioskChecks(provided: unknown): Record<string, unknown> {
  return { ...GEAR_DEFAULT_CHECKS, ...((provided && typeof provided === 'object') ? provided as Row : {}) }
}

/**
 * Výpůjčka musí mít aspoň jeden kus (jinak zanikne kód šatny a DB strážce zápis odmítne).
 * Když by po změnách nezůstal žádný sloupec řidiče, VŠECHNA odebrání se vrátí (rezervace beze
 * změny, v dokumentu jen ☐ bez poznámky o odebrání). Vrací vrácené sloupce.
 */
export function keepLastGearItem(booking: Row, res: SizeUpdates, items: AccessoryItem[]): string[] {
  const left = GEAR_KEYS.some((k) => {
    const f = `${k}_size`
    const v = f in res.updates ? res.updates[f] : booking[f]
    return !!String(v ?? '').trim()
  })
  if (left) return []
  const reverted: string[] = []
  for (const [f, v] of Object.entries(res.updates)) {
    if (v !== null) continue
    delete res.updates[f]
    const m = /^(passenger_)?(\w+)_size$/.exec(f)
    if (m) delete res.changes[m[1] ? `passenger_${m[2]}` : m[2]]
    reverted.push(f)
  }
  for (const a of items) if (a.field && reverted.includes(a.field)) delete a.removed
  return reverted
}

/** Změněné velikosti (ne odebrání) → kopie gear_lines s novou velikostí; beze změny → null. */
export function syncGearLines(lines: unknown, updates: Record<string, string | null>): unknown[] | null {
  if (!Array.isArray(lines)) return null
  let changed = false
  const out = lines.map((ln) => {
    if (!ln || typeof ln !== 'object') return ln
    const l = ln as Row
    const sizes = (l.sizes && typeof l.sizes === 'object') ? { ...(l.sizes as Row) } : null
    if (!sizes) return ln
    let touched = false
    for (const k of GEAR_KEYS) {
      const v = updates[`${k}_size`]
      if (typeof v === 'string' && v && k in sizes && sizes[k] !== v) { sizes[k] = v; touched = true }
    }
    if (!touched) return ln
    changed = true
    return { ...l, sizes }
  })
  return changed ? out : null
}

const SITE: Record<string, string> = { cs: 'https://www.motogo24.cz' }
const daysIncl = (s: unknown, e: unknown) => {
  const a = Date.parse(String(s || '').slice(0, 10) + 'T00:00:00Z'), b = Date.parse(String(e || '').slice(0, 10) + 'T00:00:00Z')
  return Number.isFinite(a) && Number.isFinite(b) && b >= a ? Math.round((b - a) / 86400000) + 1 : 1
}
const hm = (v: unknown) => (v && !String(v).startsWith('00:01') ? String(v).slice(0, 5) : '')

/** Proměnné e-mailu protokolu výpůjčky (hodnoty HTML-escapované, v jazyce dokumentu). */
export function gearMailVars(booking: Row, items: AccessoryItem[], branch: GearBranch | null, lang: string,
  base: { customer_name: string; booking_number: string; doc_name: string }): Record<string, string> {
  const tr = makeTr(lang)
  const L = tr.lang
  const taken = items.filter((a) => a.checked && a.key && a.size)
  const li = (taken.length ? taken.map((a) => ({ k: String(a.key), v: String(a.size) }))
    : GEAR_KEYS.map((k) => ({ k: String(k), v: String(booking[`${k}_size`] ?? '').trim() })).filter((x) => x.v))
    .map((x) => `<li>${esc(tr.plain('g_' + x.k))}: <strong>${esc(x.v)}</strong></li>`).join('')
  const period = `${gearDateLabel(booking.start_date, L)} – ${gearDateLabel(booking.end_date, L)}`
  const subject = tr.plain('gr_subject_val')
  return {
    customer_name: esc(base.customer_name),
    booking_number: esc(base.booking_number),
    doc_name: esc(base.doc_name),
    branch_name: esc(branch?.name || ''),
    branch_address: esc([branch?.address, branch?.city].filter(Boolean).join(', ')),
    gear_period: esc(period),
    rental_period: esc(period),
    gear_days: esc(gearDaysLabel(daysIncl(booking.start_date, booking.end_date), L)),
    start_date: esc(gearDateLabel(booking.start_date, L)),
    end_date: esc(gearDateLabel(booking.end_date, L)),
    pickup_time: esc(hm(booking.pickup_time)),
    return_time: esc(hm(booking.return_time)),
    gear_items_block: li ? `<ul style="margin:6px 0 6px 18px;padding:0">${li}</ul>` : '',
    site_url: SITE[L] || 'https://motogo24.com',
    // starší šablona handover_protocol_sent (fallback) má řádek „Motocykl: {{moto}}“
    moto: esc(subject),
    moto_model: esc(subject),
  }
}

/** POST send-email; gear šablona chybí (404) → stejný mail se základní šablonou protokolu. */
export async function sendProtocolMail(url: string, key: string, body: Row, fallbackSlug: string | null,
  fetchFn: typeof fetch = fetch): Promise<boolean> {
  const post = (b: Row) => fetchFn(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${key}` }, body: JSON.stringify(b),
  })
  let r = await post(body)
  if (r.status === 404 && fallbackSlug) {
    await r.body?.cancel().catch(() => {})
    r = await post({ ...body, template_slug: fallbackSlug })
  }
  const j = await r.json().catch(() => null)
  return !!(r.ok && j && j.success !== false)
}
