// Výpůjčka JEN výbavy (booking_kind 'gear') v ElectronicProtocolModal — načtení, kontroly a příprava uložení
// v jednom modulu, ať velký modal nebobtná (DESIGN §0). Předávací protokol i protokol o poškození: bez
// motocyklu a km; identita = kód ŠATNY; velikosti z ceníku výbavy (na samoobsluze ∩ limity, parita
// edge/kiosk/web); aspoň jeden kus musí zůstat převzatý; změna velikosti se propíše i do gear_lines.
import { supabase } from '../../lib/supabase'
import { effBranch } from '../../lib/bookingBranch'
import { isGearBooking, gearItems, gearSizeCatalog, gearSizeSummary, gearLinesWithSizes } from '../../lib/bookingKind'
import { GEAR_HANDOVER_CHECKS, gearProtocolEmailVars } from './protocolGearOnly'
import { buildGearProtocolHtml } from './protocolGearDoc'
import { GEAR_DAMAGE_CHECKS, buildGearDamageHtml } from './protocolGearDamage'

export const GEAR_NEEDS_ITEM_MSG = 'Výpůjčka výbavy musí mít aspoň jeden převzatý kus. Když si zákazník nevezme nic, zrušte rezervaci (Storno).'

/**
 * Stav modalu pro výpůjčku výbavy, u motorky null. → { booking, branch, prices, accessories, sizesByType,
 * checks, checkList, subject, docName, codeName } (prices = gear_rental_prices i s překlady názvů pro e-mail).
 */
export async function loadGearProtocol(booking, { isDamage = false, selfService = false } = {}) {
  if (!isGearBooking(booking)) return null
  let prices = []
  try {
    const { data } = await supabase.from('gear_rental_prices').select('key, kind, label, sizes, is_active, translations').eq('kind', 'item')
    prices = data || []
  } catch { prices = [] }
  const checkList = isDamage ? GEAR_DAMAGE_CHECKS : GEAR_HANDOVER_CHECKS
  const sum = gearSizeSummary(booking)
  return {
    booking, branch: effBranch(booking), prices, checkList,
    // origSize = velikost z rezervace (propisuje se jen skutečná změna); popisek bez „(řidič)“
    accessories: gearItems(booking).map(i => ({ label: i.label, size: i.size, type: i.key, field: `${i.key}_size`, checked: true, origSize: i.size })),
    sizesByType: gearSizeCatalog(prices, selfService),
    checks: Object.fromEntries(checkList.map(c => [c.key, isDamage ? { checked: false, note: '' } : false])),
    subject: `Výpůjčka výbavy${sum ? ` · ${sum}` : ''}`,
    docName: (isDamage ? 'Protokol o poškození výbavy' : 'Předávací protokol výbavy') + ' (elektronický)',
  }
}

/** Předání: aspoň jeden převzatý kus (bez velikostí by zanikl kód šatny; DB guard gear_booking_needs_item). */
export const gearHasTakenItem = accessories => accessories.some(a => a.field && !a.deleted && a.checked)

/** UPDATE velikostí z protokolu → u výbavy i velikosti v naceněných řádcích gear_lines (ceny beze změny). */
export function withGearLines(gear, upd) {
  if (!gear || !Object.keys(upd).length || !Array.isArray(gear.booking?.gear_lines)) return upd
  return { ...upd, gear_lines: gearLinesWithSizes(gear.booking.gear_lines, upd) }
}

/** HTML podepsaného protokolu výbavy (předání / poškození). */
export function buildGearProtocolDoc(gear, { isDamage, vars, form, signatures, lang }) {
  return isDamage
    ? buildGearDamageHtml({ vars, form, signatures, lang, branch: gear.branch })
    : buildGearProtocolHtml({ vars, form, signatures: { customer: signatures.customer }, lang, branch: gear.branch })
}

/** Proměnné e-mailu handover_protocol_gear_sent se skutečností z protokolu (změněné velikosti, nepřevzaté kusy). */
export function gearProtocolMailVars(gear, accessories, lang) {
  const sizes = Object.fromEntries(accessories.filter(a => a.field).map(a => [a.field, !a.deleted && a.checked ? a.size : null]))
  return gearProtocolEmailVars({ ...gear.booking, ...sizes }, lang, gear.prices)
}

/** Proměnné e-mailu protokolu výbavy při „Odeslat znovu“ (Doklady) — názvy kusů z ceníku v jazyce zákazníka. */
export async function gearMailVarsFor(booking) {
  let prices = null
  try {
    const { data } = await supabase.from('gear_rental_prices').select('key, label, translations').eq('kind', 'item')
    prices = data || null
  } catch { prices = null }
  return gearProtocolEmailVars(booking, booking?.language || 'cs', prices)
}
