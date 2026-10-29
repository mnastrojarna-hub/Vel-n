// Výpůjčka JEN výbavy (bookings.booking_kind = 'gear', DESIGN-GEAR §3.4, 2026-10-23):
//  • smlouva: požadavek 'rental_contract' u gear rezervace → šablona `gear_rental_contract`
//    („Smlouva o nájmu motorkářské výbavy“, Velín Dokumenty); bez ní 503 jako u ostatních
//    právních dokumentů — NIKDY motorková smlouva;
//  • {{proměnné}} výpůjčky: {{gear_items_table}} (HTML tabulka kus / velikost / cena za den /
//    celkem), {{gear_items}} (text), {{gear_period}}, {{gear_days}}, {{gear_per_day}};
//    {{accessories_block}} / {{accessories}} bez „(řidič)“; {{daily_rate}} / {{rental_price}}
//    z ceny výbavy. Pobočka ({{branch_name}}, {{branch_address}}), cena ({{total_price}}) a
//    zákazník ({{customer_*}}) zůstávají z vars.ts. Hodnoty v jazyce TEXTU dokumentu (docLang),
//    názvy kusů z gear_rental_prices.translations (Velín ceník), HTML escapované.

import { fmtDateL, fmtPriceL, labelsFor, rentalPeriod } from './labels.ts'

// deno-lint-ignore no-explicit-any
type Any = any
export const GEAR_CONTRACT_SLUG = 'gear_rental_contract'

const TH: Record<string, { perDay: string; total: string; sum: string; notTaken: string }> = {
  cs: { perDay: 'Cena za den', total: 'Celkem', sum: 'Výbava celkem za den', notTaken: 'nepřevzato' },
  en: { perDay: 'Price per day', total: 'Total', sum: 'Gear total per day', notTaken: 'not taken' },
  de: { perDay: 'Preis pro Tag', total: 'Gesamt', sum: 'Ausrüstung gesamt pro Tag', notTaken: 'nicht übernommen' },
  es: { perDay: 'Precio por día', total: 'Total', sum: 'Equipamiento total por día', notTaken: 'no recogido' },
  fr: { perDay: 'Prix par jour', total: 'Total', sum: 'Équipement total par jour', notTaken: 'non retiré' },
  nl: { perDay: 'Prijs per dag', total: 'Totaal', sum: 'Uitrusting totaal per dag', notTaken: 'niet meegenomen' },
  pl: { perDay: 'Cena za dzień', total: 'Razem', sum: 'Wyposażenie razem za dzień', notTaken: 'nieodebrane' },
  uk: { perDay: 'Ціна за день', total: 'Разом', sum: 'Спорядження разом за день', notTaken: 'не отримано' },
}

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))

export function isGearDoc(b: Any): boolean {
  return !!b && b.booking_kind === 'gear'
}

/** Šablona dokumentu: 'rental_contract' u gear rezervace → gear smlouva; jinak beze změny.
 *  Chyba dotazu / chybějící sloupec (SQL ještě nenasazené) = motorka. */
// deno-lint-ignore no-explicit-any
export async function resolveDocSlug(sb: any, slug: string, bookingId: string): Promise<string> {
  if (slug !== 'rental_contract') return slug
  try {
    const { data, error } = await sb.from('bookings').select('booking_kind').eq('id', bookingId).maybeSingle()
    return !error && isGearDoc(data) ? GEAR_CONTRACT_SLUG : slug
  } catch { return slug }
}

export type PriceRow = { key: string; label: string | null; translations: Record<string, { label?: string }> | null }

/** Ceník výbavy (názvy + překlady); chyba = prázdný (názvy pak z gear_lines / labels.ts). */
// deno-lint-ignore no-explicit-any
export async function loadGearPriceRows(sb: any): Promise<PriceRow[]> {
  try {
    const { data, error } = await sb.from('gear_rental_prices').select('key, label, translations')
    return !error && Array.isArray(data) ? data as PriceRow[] : []
  } catch { return [] }
}

/** Počet dní včetně prvního i posledního (jako ceník výpůjčky). */
export function gearDocDays(b: Any): number {
  const s = Date.parse(String(b?.start_date || '').slice(0, 10) + 'T00:00:00Z')
  const e = Date.parse(String(b?.end_date || '').slice(0, 10) + 'T00:00:00Z')
  if (!Number.isFinite(s) || !Number.isFinite(e) || e < s) return 1
  return Math.round((e - s) / 86400000) + 1
}

export function buildGearVars(b: Any, docLang: string, prices: PriceRow[]): Record<string, string> {
  const L = labelsFor(docLang)
  const t = TH[docLang] || TH.cs
  const byKey = new Map(prices.map((p) => [p.key, p]))
  const generic = L.gear as Record<string, string>
  // název kusu / kompletu: překlad z ceníku → (cs) název z ceníku → obecný název (labels.ts) → uložený název
  const name = (key: string, fallback?: string) => {
    const p = byKey.get(key)
    const tr = docLang !== 'cs' ? p?.translations?.[docLang]?.label : null
    return String(tr || (docLang === 'cs' ? p?.label : null) || (docLang !== 'cs' ? generic[key] : null)
      || fallback || p?.label || generic[key] || key)
  }
  const days = gearDocDays(b)
  const lines = (Array.isArray(b?.gear_lines) ? b.gear_lines : []).filter((l: Any) => l && typeof l === 'object')
  const td = 'padding:6px 8px;border:1px solid #ddd;text-align:left'
  const tdR = 'padding:6px 8px;border:1px solid #ddd;text-align:right;white-space:nowrap'
  const rows: string[] = []
  const text: string[] = []
  let perDay = 0
  for (const ln of lines) {
    const ppd = Number(ln.price_per_day) || 0
    perDay += ppd
    // nepřevzatý kus při předání (submit-handover-protocol: `not_taken`, řádek zaplacený dál) → „nepřevzato“
    const nt: string[] = Array.isArray(ln.not_taken) ? ln.not_taken.map(String) : []
    const keys: string[] = Array.isArray(ln.includes) && ln.includes.length ? ln.includes.map(String)
      : [...Object.keys(ln.sizes || {}), ...nt.filter((k) => !(k in (ln.sizes || {})))]
    const sizes = keys.map((k) => ({ k, v: nt.includes(k) ? t.notTaken : String((ln.sizes || {})[k] ?? '').trim() })).filter((x) => x.v)
    const sizeTxt = ln.kind === 'set' || sizes.length > 1 ? sizes.map((x) => `${name(x.k)} ${x.v}`).join(', ') : (sizes[0]?.v || '')
    // název řádku: překlad z ceníku (klíč řádku), u češtiny uložený název z objednávky
    const label = docLang === 'cs' ? String(ln.label || name(String(ln.key))) : name(String(ln.key), String(ln.label || ''))
    rows.push(`<tr><td style="${td};background:#f8faf9;font-weight:600">${esc(label)}</td><td style="${td}">${esc(sizeTxt)}</td>`
      + `<td style="${tdR}">${fmtPriceL(ppd, docLang)} Kč</td><td style="${tdR}">${fmtPriceL(ppd * days, docLang)} Kč</td></tr>`)
    text.push(sizeTxt ? `${label} (${sizeTxt})` : label)
  }
  if (!rows.length) {
    // bez naceněných řádků (ruční zásah) — aspoň velikosti z rezervace
    for (const k of ['helmet', 'jacket', 'pants', 'gloves', 'boots']) {
      const v = String(b?.[`${k}_size`] ?? '').trim()
      if (!v) continue
      rows.push(`<tr><td style="${td};background:#f8faf9;font-weight:600">${esc(name(k))}</td><td style="${td}">${esc(v)}</td><td style="${tdR}"></td><td style="${tdR}"></td></tr>`)
      text.push(`${name(k)} (${v})`)
    }
  }
  if (b?.gear_per_day != null && Number.isFinite(Number(b.gear_per_day))) perDay = Number(b.gear_per_day)
  const th = 'padding:6px 8px;border:1px solid #ddd;text-align:left;background:#f0f7ff;font-weight:700;font-size:10px;text-transform:uppercase'
  const table = rows.length
    ? `<table class="checklist" style="width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd">`
      + `<tr><th style="${th}">${esc(L.thItem)}</th><th style="${th}">${esc(L.thSize)}</th><th style="${th};text-align:right">${esc(t.perDay)}</th><th style="${th};text-align:right">${esc(t.total)}</th></tr>`
      + rows.join('')
      + (perDay > 0 ? `<tr><td colspan="2" style="${td};font-weight:700">${esc(t.sum)}</td><td style="${tdR};font-weight:700">${fmtPriceL(perDay, docLang)} Kč</td><td style="${tdR};font-weight:700">${fmtPriceL(perDay * days, docLang)} Kč</td></tr>` : '')
      + `</table>`
    : `<p style="font-size:12px">${esc(L.noGear)}</p>`
  const items = text.length ? esc(text.join(', ')) : esc(L.none)
  return {
    gear_items_table: table,
    gear_items: items,
    gear_period: `${fmtDateL(b?.start_date, docLang)} – ${fmtDateL(b?.end_date, docLang)}`,
    gear_days: rentalPeriod(days, docLang),
    gear_per_day: fmtPriceL(perDay, docLang),
    accessories_block: table,
    accessories: items,
    daily_rate: fmtPriceL(perDay, docLang),
    rental_price: fmtPriceL(perDay * days, docLang),
  }
}
