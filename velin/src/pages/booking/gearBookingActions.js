// Výpůjčka JEN výbavy — kontroly akcí detailu rezervace (BookingDetail.jsx), ať velký soubor nebobtná.
import { supabase } from '../../lib/supabase'
import { fetchDocsGate } from '../../lib/docsGate'
import { gearDocsGate, gearItems } from '../../lib/bookingKind'

/** Ruční aktivace výpůjčky: doklad totožnosti + 18+ (backendová brána, bez ŘP). Nejde-li ověřit → false. */
export async function gearActivationDocsOk(bookingId) {
  const gate = await fetchDocsGate({ bookingId })
  return gearDocsGate(gate)?.ok === true
}

/**
 * Obnovení zrušené výpůjčky výbavy (místo kolize motorky): pobočka musí být v termínu otevřená
 * (branch_is_closed — chyba) a výbava volná na skladu, je-li kontrola skladu zapnutá
 * (get_gear_rental_availability — jen varování, obsluha rozhodne). → { error } | { warning } | {}
 */
export async function gearRestoreCheck(booking, start, end) {
  const branchId = booking?.branch_id
  if (!branchId) return { error: 'Výpůjčka výbavy nemá pobočku — obnovení není možné.' }
  const { data: closed, error } = await supabase.rpc('branch_is_closed', { p_branch_id: branchId, p_start: start, p_end: end })
  if (!error && closed === true) return { error: 'Rezervaci nelze obnovit — pobočka je v termínu zavřená (Pobočky → zavírací období / přepínač otevřeno).' }
  try {
    const { data: av } = await supabase.rpc('get_gear_rental_availability', { p_branch_id: branchId, p_start: start, p_end: end })
    if (av?.enabled && av.sizes && typeof av.sizes === 'object') {
      // sledované typy: velikost s 0 volnými kusy (hodnota už bez kusů držených pro motorky)
      const short = gearItems(booking).filter(i => {
        const t = av.sizes[i.key]
        return t && Object.prototype.hasOwnProperty.call(t, i.size) && Number(t[i.size]) <= 0
      })
      if (short.length) return { warning: `Na skladu pobočky není v termínu volná výbava: ${short.map(i => `${i.label} ${i.size}`).join(', ')}.` }
    }
  } catch { /* sklad je jen informativní */ }
  return {}
}
