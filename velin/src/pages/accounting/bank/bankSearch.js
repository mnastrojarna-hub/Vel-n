// Finance → Banka: ruční hledání cíle pro spárování, když žádný návrh nesedí. Kontrakt hledání nenabízí,
// proto se čtou tabulky, které obsluha Velína už vidí (bookings, shop_orders, bank_payment_requests);
// vybrané id se pak pošle akci pair. Nic se tu nezapisuje.
import { supabase } from '../../../lib/supabase'
import { shortId, fmtDate } from './bankFormat'

const BOOKING_COLS = 'id, status, payment_status, total_price, payment_vs, mod_surcharge_due, mod_surcharge_vs, start_date, end_date, booking_kind, created_at, profiles(full_name, email)'
const ORDER_COLS = 'id, order_number, customer_name, customer_email, total, status, payment_status, created_at'
const REQUEST_COLS = 'id, kind, vs, amount, status, change_kind, expires_at, booking_id, order_id, created_at'

async function rows(fn) {
  try { const { data, error } = await fn(); return error ? [] : (data || []) } catch { return [] }
}

function bookingTargets(b) {
  const number = shortId(b.id)
  const base = {
    booking_id: b.id, number, customer_name: b.profiles?.full_name || null, customer_email: b.profiles?.email || null,
    created_at: b.created_at, info: `${fmtDate(b.start_date)} – ${fmtDate(b.end_date)}`,
    state: b.status === 'cancelled' ? 'cancelled' : 'waiting',
  }
  const out = []
  const due = Number(b.mod_surcharge_due) || 0
  if (b.payment_status !== 'paid') {
    out.push({ ...base, target_type: 'booking', target_id: b.id, kind: b.booking_kind === 'gear' ? 'gear' : 'booking',
      label: `${b.booking_kind === 'gear' ? 'Výpůjčka výbavy' : 'Rezervace'} #${number}`, amount: Number(b.total_price) || 0, vs: b.payment_vs || null })
  }
  if (due > 0) {
    out.push({ ...base, target_type: 'surcharge', target_id: b.id, kind: 'surcharge', label: `Doplatek rezervace #${number}`, amount: due, vs: b.mod_surcharge_vs || null })
  }
  if (!out.length) out.push({ ...base, target_type: 'booking', target_id: b.id, kind: 'booking', label: `Rezervace #${number}`, amount: Number(b.total_price) || 0, disabled: 'už zaplaceno, bez doplatku' })
  return out
}

function orderTarget(o) {
  return {
    target_type: 'order', target_id: o.id, kind: 'shop_order', label: `Objednávka ${o.order_number}`, number: o.order_number, order_id: o.id,
    amount: Number(o.total) || 0, vs: null, customer_name: o.customer_name || null, customer_email: o.customer_email || null, created_at: o.created_at,
    state: o.status === 'cancelled' ? 'cancelled' : 'waiting', disabled: o.payment_status === 'paid' ? 'už zaplaceno' : null,
  }
}

function requestTarget(r) {
  if (r.kind !== 'booking_change' || !['pending', 'expired', 'cancelled'].includes(r.status)) return null
  const late = r.status === 'pending' && r.expires_at && Date.parse(r.expires_at) < Date.now()
  return {
    target_type: 'request', target_id: r.id, kind: 'booking_change', label: `Úprava rezervace #${shortId(r.booking_id)}`, number: shortId(r.booking_id),
    booking_id: r.booking_id, request_id: r.id, amount: Number(r.amount) || 0, vs: r.vs, created_at: r.created_at, expires_at: r.expires_at,
    state: late ? 'expired' : r.status === 'pending' ? 'waiting' : r.status,
  }
}

/** Hledá rezervace (číslo, VS, zákazník), objednávky (číslo, zákazník) a čekající úpravy (VS). */
export async function searchTargets(raw) {
  const text = String(raw || '').replace(/[,()"\\*%]/g, ' ').replace(/\s+/g, ' ').trim()
  if (text.length < 2) return []
  const like = `%${text}%`
  const digits = /^[\d\s]+$/.test(text) ? text.replace(/\s/g, '') : ''
  const compact = text.replace(/[#\s-]/g, '').toLowerCase()
  const hex = /^[0-9a-f]{4,8}$/.test(compact) ? compact : ''
  const bookings = (apply) => rows(() => apply(supabase.from('bookings').select(BOOKING_COLS)))

  const [byVs, byName, byNumber, orders, requests] = await Promise.all([
    digits.length >= 4 ? bookings(q => q.or(`payment_vs.eq.${digits},mod_surcharge_vs.eq.${digits}`).limit(10)) : [],
    (async () => {
      const ids = (await rows(() => supabase.from('profiles').select('id').or(`full_name.ilike.${like},email.ilike.${like}`).limit(50))).map(p => p.id)
      return ids.length ? bookings(q => q.in('user_id', ids).order('created_at', { ascending: false }).limit(30)) : []
    })(),
    (async () => {
      if (!hex) return []
      // číslo rezervace = konec jejího id; PostgREST konec uuid hledat neumí → poslední nezaplacené / s doplatkem a filtr tady
      const ids = (await rows(() => supabase.from('bookings').select('id').or('payment_status.neq.paid,mod_surcharge_due.gt.0')
        .order('created_at', { ascending: false }).limit(1000))).map(b => b.id).filter(id => String(id).replace(/-/g, '').endsWith(hex))
      return ids.length ? bookings(q => q.in('id', ids.slice(0, 20))) : []
    })(),
    rows(() => supabase.from('shop_orders').select(ORDER_COLS)
      .or(`order_number.ilike.${like},customer_name.ilike.${like},customer_email.ilike.${like}`).order('created_at', { ascending: false }).limit(20)),
    digits.length >= 4 ? rows(() => supabase.from('bank_payment_requests').select(REQUEST_COLS).eq('vs', digits).limit(5)) : [],
  ])

  const seen = new Set()
  const out = []
  const push = (t) => {
    if (!t) return
    const key = `${t.target_type}:${t.target_id}`
    if (!seen.has(key)) { seen.add(key); out.push({ ...t, source: 'manual' }) }
  }
  requests.forEach(r => push(requestTarget(r)))
  ;[...byVs, ...byNumber, ...byName].forEach(b => bookingTargets(b).forEach(push))
  orders.forEach(o => push(orderTarget(o)))
  return out
}
