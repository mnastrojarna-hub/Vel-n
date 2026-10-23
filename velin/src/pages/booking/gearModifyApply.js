// Uložení úpravy výpůjčky JEN výbavy (GearModifyModal). Pořadí zápisů je zvolené tak, aby DB trigger
// trg_booking_modified_email (AFTER UPDATE bookings) poslal zákazníkovi SPRÁVNÝ mail a in-app zprávu:
//  • DOPLATEK u zaplacené: mod_surcharge_due se zapíše PŘED admin_update_gear_booking → UPDATE ceny v RPC už
//    vidí dluh a trigger mail ODLOŽÍ (mod_email_payload; odejde po „Potvrdit doplatek“ = confirm_booking_surcharge).
//    Zápis až po RPC dřív znamenal okamžitý mail „Doplatek X Kč — doklad o platbě…“ a po potvrzení druhý.
//  • VRATKA, která ruší dřívější nezaplacený doplatek: mod_surcharge_due + mod_email_payload pryč PŘED RPC
//    (jako motorka v BookingModifyModal: dluh se vynuluje ve stejném kroku jako změna ceny, mail odejde hned).
//  • „ZDARMA“ (rozdíl neúčtovat): RPC by přepsalo total_price a trigger by ohlásil neexistující doplatek/vratku →
//    úprava jde JEDNÍM přímým UPDATE (admin; řádky, velikosti a cena/den z dry-runu serveru, total_price a sleva
//    beze změny). Trigger pak ohlásí jen termín/čas; změnu jen kusů ohlásí send-booking-email (gear diff).
// Selže-li RPC po předzápisu, vrátí se původní hodnoty doplatku. CONTRACT: až admin_update_gear_booking dostane
// p_charge (DB-A), nahradí všechny větve jedno volání RPC.
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import { GEAR_KEYS, gearErrorText } from '../../lib/bookingKind'
import { pragueDay } from './protocolGearOnly'

const SUR_COLS = 'mod_surcharge_due, mod_surcharge_requested_at, mod_surcharge_paid_at, mod_email_payload'
const SIZE_COLS = GEAR_KEYS.map(k => `${k}_size`).join(', ')
const hm = t => (t ? String(t).slice(0, 5) : '')
const asMap = v => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})
const sizesOf = b => Object.fromEntries(GEAR_KEYS.filter(k => b?.[`${k}_size`]).map(k => [k, String(b[`${k}_size`])]))
const sameMap = (a, b) => GEAR_KEYS.every(k => (a[k] ?? null) === (b[k] ?? null))

/** Co s rozdílem ceny: plain (bez peněz) | free (Zdarma) | surcharge (doplatek due) | refund (vratka refund). */
export function planGearCharge({ charge, origPaid, pending = 0, diff = 0 }) {
  const p = Number(pending) || 0, d = Number(diff) || 0
  if (!d) return { mode: 'plain', pending: p, due: 0, refund: 0 }
  if (!charge) return { mode: 'free', pending: p, due: 0, refund: 0 }
  if (!origPaid) return { mode: 'plain', pending: p, due: 0, refund: 0 }   // nezaplacená → zaplatí novou cenu
  const due = p + d
  if (due > 0) return { mode: 'surcharge', pending: p, due, refund: 0 }
  return { mode: 'refund', pending: p, due: 0, refund: Math.max(0, -due), clearPending: p > 0 }
}

async function upd(id, patch) {
  const { error } = await supabase.from('bookings').update(patch).eq('id', id)
  if (error) throw error
}

/**
 * Provede úpravu dle plánu. `rpcParams` = parametry admin_update_gear_booking (p_dry_run:false), `dry` = čerstvý
 * dry-run, `form` = {start, end, branchId, pickupTime, returnTime}. → { result, realDiff, surchargeDue, refund, alerts[] }
 */
export async function applyGearModify({ booking, rpcParams, dry, plan, form }) {
  if (plan.mode === 'free') return applyGearFree({ booking, dry, form })
  const id = booking.id
  let prev = null
  if (plan.mode === 'surcharge' || plan.clearPending) {
    const { data, error } = await supabase.from('bookings').select(SUR_COLS).eq('id', id).single()
    if (error || !data) throw error || new Error('Rezervace nenalezena')
    prev = data
    await upd(id, plan.mode === 'surcharge'
      ? { mod_surcharge_due: plan.due, mod_surcharge_requested_at: new Date().toISOString(), mod_surcharge_paid_at: null }
      : { mod_surcharge_due: null, mod_email_payload: null })
  }
  const res = await debugAction('booking.modify_gear', 'GearModifyModal', () => supabase.rpc('admin_update_gear_booking', rpcParams), rpcParams)
  const d = res?.data
  if (res?.error || !d || d.error || d.success === false) {
    const msg = res?.error?.message || gearErrorText(d || 'Uložení selhalo')
    if (prev) {
      try { await upd(id, prev) } catch (e) {
        throw new Error(`${msg} — úprava se neuložila a vrácení doplatku do původního stavu selhalo (${e.message || e}). Zkontrolujte doplatek v detailu rezervace.`)
      }
    }
    throw new Error(msg)
  }
  const realDiff = Number(d.diff ?? dry?.diff) || 0
  const alerts = []
  let surchargeDue = 0, refund = 0
  if (plan.mode === 'surcharge') {
    const due = plan.pending + realDiff
    surchargeDue = plan.due
    if (due !== plan.due) {
      // cena se mezi náhledem a uložením změnila (souběžná úprava) — dluh podle skutečného rozdílu
      if (due > 0) {
        try { await upd(id, { mod_surcharge_due: due }); surchargeDue = due } catch (e) { alerts.push(`Doplatek se nepodařilo opravit na ${due} Kč (${e.message || e}) — zkontrolujte ho v detailu rezervace.`) }
      } else alerts.push('Cena se mezi náhledem a uložením změnila a doplatek už nevychází — zkontrolujte doplatek / vratku v detailu rezervace.')
    }
  } else if (plan.mode === 'refund') {
    refund = Math.max(0, -(plan.pending + realDiff))
  }
  return { result: d, realDiff, surchargeDue, refund, alerts }
}

/** „Zdarma“: zápis úpravy bez změny ceny (jedním UPDATE, tvar záznamu historie = RPC gear_admin_update). */
async function applyGearFree({ booking, dry, form }) {
  const { data: cur, error } = await supabase.from('bookings')
    .select(`id, status, user_id, booking_source, branch_id, start_date, end_date, original_start_date, original_end_date, total_price, pickup_time, return_time, modification_history, ${SIZE_COLS}, profiles(full_name, email)`)
    .eq('id', booking.id).single()
  if (error || !cur) throw error || new Error('Rezervace nenalezena')
  const fromStart = pragueDay(cur.start_date), fromEnd = pragueDay(cur.end_date)
  const datesChanged = form.start !== fromStart || form.end !== fromEnd
  const timesChanged = (!!form.pickupTime && form.pickupTime !== hm(cur.pickup_time)) || (!!form.returnTime && form.returnTime !== hm(cur.return_time))
  const from = sizesOf(cur), to = asMap(dry?.sizes)
  let uid = null
  try { uid = (await supabase.auth.getUser())?.data?.user?.id ?? null } catch { /* jen stopa v historii */ }
  const toBranch = form.branchId || cur.branch_id
  const hist = Array.isArray(cur.modification_history) ? cur.modification_history : []
  const patch = {
    branch_id: toBranch,
    ...Object.fromEntries(GEAR_KEYS.map(k => [`${k}_size`, to[k] ?? null])),
    gear_lines: dry.lines, gear_per_day: dry.per_day,
    modification_history: [...hist, {
      at: new Date().toISOString(), source: 'velin', type: 'gear_admin_update', by: uid,
      from_start: fromStart, from_end: fromEnd, to_start: form.start, to_end: form.end,
      from_branch: cur.branch_id, to_branch: toBranch, from, to,
      from_total: cur.total_price, to_total: cur.total_price, charged: false, free_diff: Number(dry?.diff) || 0,
    }],
  }
  if (form.start !== fromStart) patch.start_date = form.start
  if (form.end !== fromEnd) patch.end_date = form.end
  if (datesChanged && !cur.original_start_date) patch.original_start_date = fromStart
  if (datesChanged && !cur.original_end_date) patch.original_end_date = fromEnd
  if (form.pickupTime) patch.pickup_time = form.pickupTime
  if (form.returnTime) patch.return_time = form.returnTime
  const r = await debugAction('booking.modify_gear_free', 'GearModifyModal', () => supabase.from('bookings').update(patch).eq('id', booking.id).select('id'), patch)
  if (r?.error) throw r.error
  if (!r?.data?.length) throw new Error('Úprava se neuložila (rezervace nenalezena nebo chybí oprávnění).')

  const alerts = []
  // Jen kusy/velikosti: trigger úprav (žádné sledované pole) mail nepošle → stejný mail jako RPC (_gear_notify_modified).
  // source 'web' (jako RPC, FIX-R1): log slug web_booking_modified → 5min dedup triggeru ('booking_modified%')
  // tento mail nepočítá a následný posun termínu zákazníkovi svůj mail pošle.
  const email = cur.profiles?.email
  if (!sameMap(from, to) && !datesChanged && !timesChanged && ['reserved', 'active'].includes(cur.status) && email) {
    try {
      const { error: mErr } = await supabase.functions.invoke('send-booking-email', { body: {
        type: 'booking_modified', booking_id: cur.id, booking_kind: 'gear', customer_email: email, customer_name: cur.profiles?.full_name || '',
        source: 'web', motorcycle: '', start_date: cur.start_date, end_date: cur.end_date,
        total_price: cur.total_price, price_difference: 0, pickup_time: patch.pickup_time || cur.pickup_time || '', return_time: patch.return_time || cur.return_time || '',
        original_start_date: cur.start_date, original_end_date: cur.end_date, original_total_price: cur.total_price,
        changes: { gear: { from, to } },
      } })
      if (mErr) throw mErr
    } catch (e) { alerts.push(`Úprava je uložená, ale e-mail o změně výbavy se neodeslal (${e.message || e}).`) }
  }
  return { result: { ...dry, old_total: cur.total_price, new_total: cur.total_price }, realDiff: 0, surchargeDue: 0, refund: 0, alerts }
}

/** Volné kusy pro výběr velikostí: vlastní kusy upravované výpůjčky (stejná pobočka, překryv termínu) se vrací
 *  do „volno“ — get_gear_rental_availability je počítá jako obsazené (server dry-run je správně vyjímá). */
export function freeWithOwnItems(free, booking, { branchId, start, end }) {
  if (!free || !booking || booking.is_test || branchId !== booking.branch_id) return free
  const bs = pragueDay(booking.start_date), be = pragueDay(booking.end_date)
  if (!start || !end || !bs || !be || start > be || end < bs) return free
  const out = {}
  for (const [k, m] of Object.entries(free)) out[k] = { ...asMap(m) }
  for (const [k, size] of Object.entries(sizesOf(booking))) {
    if (out[k] && Object.prototype.hasOwnProperty.call(out[k], size)) out[k][size] = Math.min(9, (Number(out[k][size]) || 0) + 1)
  }
  return out
}
