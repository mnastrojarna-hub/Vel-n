import { supabase } from '../../lib/supabase'

// Rezervace, které BRÁNÍ vyřazení / servisu / smazání motorky.
// Pravidlo (potvrzeno provozem): hromadné ani fleet akce NIKDY neruší ani nemažou
// rezervace. Motorku s aktivní (probíhající), nadcházející (reserved) nebo čekající
// (pending) rezervací nelze takto vyřadit/smazat — každá rezervace se řeší
// individuálně přes úpravu rezervace dle dohody zákazníka a administrátora.
export const BLOCKING_STATUSES = ['pending', 'reserved', 'active']

const STATUS_LABEL = { pending: 'čekající', reserved: 'nadcházející', active: 'aktivní' }
const fmtD = (d) => (d ? new Date(d).toLocaleDateString('cs-CZ') : '—')

/** Rezervace bránící vyřazení/servisu/smazání (pending/reserved/active, konec dnes nebo později). */
export async function fetchBlockingBookings(motoIds) {
  const ids = (Array.isArray(motoIds) ? motoIds : [motoIds]).filter(Boolean)
  if (!ids.length) return []
  const today = new Date().toISOString().slice(0, 10)
  const { data } = await supabase
    .from('bookings')
    .select('id, moto_id, status, start_date, end_date, profiles(full_name)')
    .in('moto_id', ids)
    .in('status', BLOCKING_STATUSES)
    .gte('end_date', today)
    .order('start_date')
  return data || []
}

/** Pouze probíhající (aktivní) pronájmy — motorku, na které někdo právě jede, nelze servisovat/vyřadit. */
export async function fetchActiveBookings(motoIds) {
  const ids = (Array.isArray(motoIds) ? motoIds : [motoIds]).filter(Boolean)
  if (!ids.length) return []
  const today = new Date().toISOString().slice(0, 10)
  const { data } = await supabase
    .from('bookings')
    .select('id, moto_id, status, start_date, end_date, profiles(full_name)')
    .in('moto_id', ids)
    .eq('status', 'active')
    .gte('end_date', today)
    .order('start_date')
  return data || []
}

/** Rezervace překrývající zvolené období [from, to] (pro hromadnou blokaci termínu). */
export async function fetchOverlappingBookings(motoIds, from, to) {
  const ids = (Array.isArray(motoIds) ? motoIds : [motoIds]).filter(Boolean)
  if (!ids.length) return []
  const { data } = await supabase
    .from('bookings')
    .select('id, moto_id, status, start_date, end_date, profiles(full_name)')
    .in('moto_id', ids)
    .in('status', BLOCKING_STATUSES)
    .lte('start_date', to)
    .gte('end_date', from)
    .order('start_date')
  return data || []
}

/**
 * Srozumitelná hláška pro admina. Žádná rezervace se neruší — admin je má vyřešit
 * jednotlivě přes úpravu rezervace dle dohody se zákazníkem.
 * @param {object} opts.motosById  mapa { moto_id: { model, spz } } pro hromadné akce
 */
export function blockingBookingsMessage(bookings, { motosById = null, max = 10 } = {}) {
  const n = bookings.length
  const head =
    `Akci nelze provést — ${n} ${n === 1 ? 'rezervace brání' : 'rezervací brání'} této operaci.\n` +
    `Žádná rezervace se neruší ani nemaže. Vyřešte každou individuálně přes úpravu ` +
    `rezervace dle dohody se zákazníkem, teprve poté motorku vyřaďte / odešlete do servisu.\n\n`
  const lines = bookings.slice(0, max).map((b) => {
    const moto = motosById?.[b.moto_id]
    const motoLbl = moto ? `${moto.model || ''}${moto.spz ? ` (${moto.spz})` : ''} — ` : ''
    const cust = b.profiles?.full_name || '?'
    return `• ${motoLbl}${STATUS_LABEL[b.status] || b.status}: ${cust}, ${fmtD(b.start_date)} – ${fmtD(b.end_date)}`
  })
  const more = n > max ? `\n…a dalších ${n - max}` : ''
  return head + lines.join('\n') + more
}
