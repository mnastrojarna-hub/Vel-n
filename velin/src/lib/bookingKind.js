// MotoGo24 Velín — výpůjčka JEN výbavy jako běžná rezervace (bookings.booking_kind = 'gear',
// migrace 20261023a_gear_booking_schema.sql). Gear řádek: moto_id NULL, pobočka v bookings.branch_id,
// velikosti v helmet/jacket/pants/gloves/boots_size (sloupce spolujezdce se nepoužívají), naceněné
// řádky v gear_lines [{key,kind,label,includes,sizes,price_per_day,total}], cena/den v gear_per_day.
// POZOR: `moto_id IS NULL` samo o sobě gear NEZNAMENÁ (FK ON DELETE SET NULL) — vždy isGearBooking().
// Doklady u výbavy: JEN doklad totožnosti (OP líc+rub nebo pas) + věk 18+, žádný ŘP.
import { identityMissing } from './docVerification'
import { rentalDays } from './rentalDays'
import { effBranch } from './bookingBranch'

export const GEAR_KIND = 'gear'
export const GEAR_KEYS = ['helmet', 'jacket', 'pants', 'gloves', 'boots']
export const GEAR_LABELS = { helmet: 'Helma', jacket: 'Bunda', pants: 'Kalhoty', gloves: 'Rukavice', boots: 'Boty' }
export const GEAR_TITLE = 'Výpůjčka výbavy'
// teal = barva změny výbavy v historii úprav (bookingConstants describeHistoryEntry)
export const GEAR_PILL = { label: 'JEN VÝBAVA', color: '#0e7490', bg: '#cffafe' }

export const isGearBooking = (b) => b?.booking_kind === GEAR_KIND

/** Půjčené kusy z velikostí rezervace (jen řidičské sloupce), v pořadí ceníku. */
export function gearItems(b) {
  return GEAR_KEYS.filter(k => b?.[`${k}_size`]).map(k => ({ key: k, label: GEAR_LABELS[k], size: String(b[`${k}_size`]) }))
}

/** „Helma M, Bunda L…“ */
export function gearSizeSummary(b) {
  return gearItems(b).map(i => `${i.label} ${i.size}`).join(', ')
}

/** Popisek předmětu rezervace do seznamů / CSV: model + SPZ, u výbavy „Jen výbava · Helma M…“. */
export function bookingItemLabel(b) {
  if (isGearBooking(b)) {
    const s = gearSizeSummary(b)
    return s ? `Jen výbava · ${s}` : 'Jen výbava'
  }
  return [b?.motorcycles?.model, b?.motorcycles?.spz].filter(Boolean).join(' ')
}

/** Vyžaduje rezervace ŘP? Ne u výbavy a u dětské motorky (license_required 'N'). */
export function bookingNeedsLicense(b) {
  return !isGearBooking(b) && String(b?.motorcycles?.license_required || '').toUpperCase() !== 'N'
}

/** Typ pobočky rezervace: výbava = bookings.branch_id (embed `branch`), motorka beze změny = pobočka motorky. */
export function bookingBranchType(b) {
  return isGearBooking(b) ? (effBranch(b)?.type || null) : (b?.motorcycles?.branches?.type || null)
}

/** ID pobočky pro kód brány: výbava = bookings.branch_id, motorka = AKTUÁLNÍ pobočka motorky (beze změny). */
export function bookingGateBranchId(b) {
  return isGearBooking(b) ? (b?.branch_id || null) : (b?.motorcycles?.branch_id || null)
}

/** Kód ověřující identitu při předání: výbava = kód šatny (accessories), motorka = kód motorky. */
export function bookingIdentityCodeType(b) {
  return isGearBooking(b) ? 'accessories' : 'motorcycle'
}

export function gearLines(b) {
  return Array.isArray(b?.gear_lines) ? b.gear_lines.filter(l => l && typeof l === 'object') : []
}

/** gear_lines s přepsanými velikostmi (`sizeUpd` = {helmet_size:'L',…} — změny z předávacího protokolu);
 *  ceny řádků beze změny. null/undefined velikost (nepřevzatý kus) řádek NEmění — zaplacený kus zůstává. */
export function gearLinesWithSizes(lines, sizeUpd) {
  if (!Array.isArray(lines)) return lines
  return lines.map(l => {
    if (!l || typeof l !== 'object' || !l.sizes || typeof l.sizes !== 'object') return l
    const sizes = { ...l.sizes }
    for (const k of Object.keys(sizes)) { const v = sizeUpd?.[`${k}_size`]; if (v) sizes[k] = v }
    return { ...l, sizes }
  })
}

/** Velikosti řádku ceníku: kus → „M“, komplet → „Helma M, Bunda L…“. */
export function gearLineSizes(line) {
  const sizes = line?.sizes && typeof line.sizes === 'object' ? line.sizes : {}
  const keys = Object.keys(sizes).filter(k => sizes[k])
  if (line?.kind !== 'set' && keys.length === 1) return String(sizes[keys[0]])
  return keys.map(k => `${GEAR_LABELS[k] || k} ${sizes[k]}`).join(', ')
}

/**
 * Řádky dokladu (ZF/DP/KF) výpůjčky výbavy — zrcadlo edge generate-invoice a SQL KF:
 * „Půjčení výbavy: <label> (<velikosti>)“, množství = dny, jednotková cena = Kč/den.
 * Bez řádků (nemělo by nastat — CHECK bookings_gear_shape) jeden souhrnný řádek z gear_per_day.
 */
export function gearInvoiceItems(b) {
  const days = rentalDays(b?.start_date, b?.end_date) || 1
  const lines = gearLines(b)
  if (!lines.length) {
    const perDay = Number(b?.gear_per_day) || 0
    const s = gearSizeSummary(b)
    return perDay > 0 ? [{ description: `Půjčení výbavy${s ? ` (${s})` : ''}`, qty: days, unit_price: perDay }] : []
  }
  return lines.map(l => {
    const sz = gearLineSizes(l)
    return { description: `Půjčení výbavy: ${l.label || l.key}${sz ? ` (${sz})` : ''}`, qty: days, unit_price: Number(l.price_per_day) || 0 }
  })
}

/**
 * Verdikt dokladů pro výbavu z běžného verdiktu (applyDocsGate / computeDocVerification):
 * stačí doklad totožnosti + 18 let k začátku; ŘP, jeho platnost a skupiny se ignorují.
 * Funguje, ať backend get_docs_gate_checklist výbavu zná, nebo ne (bere jen identitu a věk).
 */
export function gearDocsVerdict(vs) {
  if (!vs) return vs
  const missing = []
  const idMiss = vs.hasIdentity ? null : (identityMissing(vs) || 'Chybí OP (líc a rub) nebo pas')
  if (idMiss) missing.push(idMiss)
  if (!vs.ageOk) missing.push(vs.dateOfBirth ? 'Zákazníkovi není 18 let' : 'Chybí datum narození')
  return { ...vs, gearOnly: true, isChildMoto: false, missing, reason: missing.length ? missing.join('; ') : null, allOk: missing.length === 0 }
}

/** Stejné pravidlo pro syrovou odpověď get_docs_gate_checklist (DetailTab / BranchDoorCodes). */
export function gearDocsGate(gate) {
  if (!gate || typeof gate !== 'object') return gate
  const missing = (Array.isArray(gate.missing) ? gate.missing : []).filter(m => !/ŘP/.test(String(m)))
  const ok = gate.identity_ok === true && gate.age_ok === true
  return { ...gate, ok, missing: ok ? [] : missing, reason: ok ? null : (missing.join('; ') || 'Chybí doklad totožnosti') }
}

/** Filtr typu rezervace v seznamu (Bookings.jsx): '' = vše, 'moto' = motorky, 'gear' = jen výbava. */
export const KIND_OPTIONS = [{ value: '', label: 'Motorky i výbava' }, { value: 'moto', label: 'Jen motorky' }, { value: 'gear', label: 'Jen výbava' }]
export function applyKindFilter(query, kind) {
  if (kind === 'gear') return query.eq('booking_kind', 'gear')
  if (kind === 'moto') return query.eq('booking_kind', 'moto')
  return query
}

// ── Velikosti na SAMOOBSLUŽNÉ pobočce (zadání majitele 2026-10-10) — parita edge
// submit-handover-protocol/gear.ts selfServiceSizeOk, web gear-ss-cap.js, kiosk gear_limits.py:
// helma S–3XL, bunda/kalhoty/rukavice nejvýš 4XL; boty a velikosti mimo pořadí beze změny.
const SIZE_RANK = { XXS: 0, XS: 1, S: 2, M: 3, L: 4, XL: 5, '2XL': 6, XXL: 6, '3XL': 7, XXXL: 7, '4XL': 8, XXXXL: 8, '5XL': 9, '6XL': 10 }
const SS_LIMITS = { helmet: [2, 7], jacket: [0, 8], pants: [0, 8], gloves: [0, 8] }

export function selfServiceSizeOk(key, size) {
  const lim = SS_LIMITS[key]
  const r = SIZE_RANK[String(size ?? '').trim().toUpperCase()]
  if (!lim || r === undefined) return true
  return r >= lim[0] && r <= lim[1]
}

/** Katalog velikostí výbavy = aktivní kusy gear_rental_prices (∩ limity samoobsluhy). → {helmet:['S',…],…} */
export function gearSizeCatalog(prices, selfService = false) {
  const out = {}
  for (const p of prices || []) {
    if (p?.kind !== 'item' || p.is_active === false || !GEAR_KEYS.includes(p.key)) continue
    out[p.key] = (p.sizes || []).map(s => String(s).trim()).filter(Boolean).filter(s => !selfService || selfServiceSizeOk(p.key, s))
  }
  return out
}

/** {helmet:'M',…} z rezervace (výchozí výběr editoru) */
export function gearSelectionFromBooking(b) {
  const sel = {}
  for (const k of GEAR_KEYS) if (b?.[`${k}_size`]) sel[k] = String(b[`${k}_size`])
  return sel
}

/** {helmet:'M',…} → p_items [{key,size}] pro RPC (pořadí ceníku) */
export function gearItemsPayload(sel) {
  return GEAR_KEYS.filter(k => sel?.[k]).map(k => ({ key: k, size: sel[k] }))
}

const GEAR_ERRORS = {
  disabled: 'Půjčování výbavy je vypnuté (Flotila → Půjčení oblečení → Nastavení).',
  bad_branch: 'Neplatná nebo neaktivní pobočka.',
  branch_closed: 'Pobočka je v termínu zavřená.',
  bad_dates: 'Neplatný termín.',
  too_long: 'Termín je delší, než povoluje nastavení půjčování výbavy.',
  no_items: 'Vyberte aspoň jeden kus výbavy.',
  too_many_items: 'Příliš mnoho kusů výbavy.',
  bad_item: 'Kus výbavy není v aktivním ceníku.',
  duplicate_item: 'Kus výbavy je vybraný dvakrát.',
  bad_size: 'Neplatná velikost (mimo ceník nebo mimo rozsah samoobslužné pobočky).',
  out_of_stock: 'Výbava v dané velikosti není na pobočce v termínu volná.',
  below_minimum: 'Cena je pod minimální platbou.',
  gear_no_moto: 'U výpůjčky výbavy nelze měnit motorku.',
  not_found: 'Rezervace nenalezena.',
  forbidden: 'Nedostatečná oprávnění.',
  not_gear: 'Rezervace není výpůjčka výbavy.',
  bad_customer: 'Neplatný zákazník.',
  bad_status: 'Dokončenou ani zrušenou výpůjčku nelze upravit.',
  bad_voucher: 'Neplatný dárkový poukaz.',
  failed: 'Chyba serveru',
}

// Varování admin RPC (_gear_prepare p_admin / admin_update_gear_booking) — admin smí pokračovat
const GEAR_WARNINGS = {
  out_of_stock: 'Výbava v dané velikosti není na pobočce v termínu volná (sklad).',
  disabled: 'Půjčování výbavy je v nastavení vypnuté.',
  start_in_past: 'Začátek je v minulosti.',
  too_far_ahead: 'Začátek je dál, než povoluje nastavení.',
  too_long: 'Termín je delší, než povoluje nastavení.',
  below_minimum: 'Cena je pod minimální platbou kartou (15 Kč).',
  paid_total_changed: 'Výpůjčka je zaplacená — rozdíl ceny se vyrovná doplatkem / vratkou.',
}
/** Kódy chyb quote_gear_booking, které admin může přebít (admin RPC je vrací jen jako varování). */
export const GEAR_ADMIN_SOFT_ERRORS = ['out_of_stock', 'disabled', 'bad_dates', 'too_long', 'below_minimum', 'bad_voucher']

/** Text varování admin RPC (kód nebo {error,…}); `short` = stock_short [{key,size,free}] pro detail skladu. */
export function gearWarningText(w, short = null) {
  if (w && typeof w === 'object') return gearErrorText(w)
  let txt = GEAR_WARNINGS[w] || String(w)
  if (w === 'out_of_stock' && Array.isArray(short) && short.length) {
    txt += ' ' + short.map(i => `${GEAR_LABELS[i.key] || i.key} ${i.size}: volno ${i.free ?? 0}`).join(', ')
  }
  return txt
}

/** Text chyby gear RPC ({error, key?, size?, items?}). */
export function gearErrorText(res) {
  const code = typeof res === 'string' ? res : res?.error
  let txt = GEAR_ERRORS[code] || code || 'Neznámá chyba'
  if (code === 'failed' && res?.message) txt += `: ${res.message}`
  if (code === 'out_of_stock' && Array.isArray(res?.items) && res.items.length) {
    txt += ' ' + res.items.map(i => `${GEAR_LABELS[i.key] || i.key} ${i.size}: volno ${i.free ?? 0}`).join(', ')
  } else if (res?.key && (code === 'bad_size' || code === 'bad_item')) {
    txt += ` (${GEAR_LABELS[res.key] || res.key}${res.size ? ' ' + res.size : ''})`
  }
  return txt
}
