// ===== process-payment/pp-waiver.ts =====
// D1/D2 (2026-10-16): částka do 1 Kč se NEÚČTUJE — potvrzení bez platby (Stripe se
// nevolá) + záznam odpuštěné částky do card_rounding (−due). Odpověď má tvar
// úspěšné platby zdarma; pro požadavek s uloženou kartou navíc tvar
// „off-session succeeded", aby ji jakékoli směrování v appce vzalo jako úspěch.
// Navíc kontrola poukazů rezervace před platbou (voucher_unavailable).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { waiveBooking, waiveShop, round2 } from './card-minimum.ts'
import { CS, refuse, respond } from './refusals.ts'
import { confirmShopPayment } from '../webhook-receiver/payment-confirmers.ts'
import { applyPaidExtension } from '../_shared/extension-apply.ts'
import { chgHash } from './intent-guard.ts'

// deno-lint-ignore no-explicit-any
type Sb = any

const savedShape = (saved: boolean) => (saved ? { off_session: true, status: 'succeeded' } : {})

async function log(sb: Sb, action: string, status: string, data: Record<string, unknown>) {
  try { await sb.from('debug_log').insert({ source: 'process-payment', action, component: 'card_minimum', status, request_data: data }) } catch { /* ignore */ }
}

/** Rezervace / SOS: odpustit due ≤ 1 Kč a potvrdit jako zaplacenou (p_method 'free'). */
export async function waiveBookingFlow(sb: Sb, bookingId: string, due: number, saved: boolean): Promise<Response> {
  const cas = await waiveBooking(sb, bookingId, due)
  if (cas === 'unavailable') return refuse(409, 'rounding_unavailable', { waiver: true }, CS.rounding_unavailable_waiver)
  if (cas === 'error') return refuse(500, 'server_error')
  if (cas === 'raced') {
    const { data: bk } = await sb.from('bookings').select('total_price, payment_status').eq('id', bookingId).maybeSingle()
    if (bk?.payment_status === 'paid') return refuse(409, 'already_paid', { already_paid: true })
    if (!bk || Number(bk.total_price) > 0) return refuse(409, 'amount_mismatch', { server_total: Number(bk?.total_price ?? 0) })
  }
  const { error } = await sb.rpc('confirm_payment', { p_booking_id: bookingId, p_method: 'free' })
  if (error) {
    await log(sb, 'card_minimum_waive_confirm_failed', 'error', { booking_id: bookingId, due, error: error.message })
    return refuse(500, 'free_confirm_failed')
  }
  await log(sb, 'card_minimum_waived', 'ok', { booking_id: bookingId, due })
  return respond(200, { success: true, free: true, waived: true, due, card_rounding: round2(-due), charge: 0, booking_id: bookingId, ...savedShape(saved) })
}

/** E-shop: odpustit due ≤ 1 Kč a potvrdit objednávku (p_method 'free'). */
export async function waiveShopFlow(sb: Sb, orderId: string, due: number, saved: boolean, redirect?: string | null): Promise<Response> {
  const cas = await waiveShop(sb, orderId, due)
  if (cas === 'unavailable') return refuse(409, 'rounding_unavailable', { waiver: true }, CS.rounding_unavailable_waiver)
  if (cas === 'error') return refuse(500, 'server_error')
  if (cas === 'raced') {
    const { data: o } = await sb.from('shop_orders').select('total, payment_status').eq('id', orderId).maybeSingle()
    if (o?.payment_status === 'paid') return refuse(409, 'already_paid', { already_paid: true }, CS.already_paid_shop)
    if (!o || Number(o.total) > 0) return refuse(409, 'amount_mismatch', { server_total: Number(o?.total ?? 0) })
  }
  await confirmShopPayment(createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''),
    orderId, `waive:${orderId}`, null, 'free')
  await log(sb, 'card_minimum_waived_shop', 'ok', { order_id: orderId, due })
  return respond(200, { success: true, free: true, waived: true, due, card_rounding: round2(-due), charge: 0, order_id: orderId, ...savedShape(saved),
    ...(redirect ? { checkout_url: redirect, url: redirect } : {}) })
}

/** Značka odpuštěného doplatku: jedno klepnutí (attempt_id) = jedna značka. Opakování
 *  TÉHOŽ klepnutí (ztracená odpověď) se deduplikuje; stejná změna později (A→B, zpět,
 *  znovu A→B) je nové klepnutí = nová značka → zapíše se. Bez attempt_id = jednorázová. */
export async function waiveRef(attemptId: string | null | undefined, bookingId: string, change: unknown): Promise<string> {
  const h = (await chgHash({ b: bookingId, c: change })) || bookingId
  return `waive:${attemptId || crypto.randomUUID()}:${h}`
}

/** Doplatek úpravy / výměny ≤ 1 Kč: změnu zapíše server hned, bez platby (r = −due).
 *  `redirect` = web (hosted Checkout): úspěch vrátí i checkout_url → web pokračuje jako po platbě. */
export async function waiveExtensionFlow(sb: Sb, a: {
  bookingId: string; change: Record<string, unknown>; srv: string | null; due: number; saved: boolean
  attemptId?: string | null; redirect?: string | null
}): Promise<Response> {
  const chg = JSON.stringify(a.change)
  const ref = await waiveRef(a.attemptId, a.bookingId, a.change)
  const r = await applyPaidExtension(sb, { bookingId: a.bookingId, chg, srv: a.srv, paidCzk: 0, payRef: ref, rounding: round2(-a.due) })
  await log(sb, 'card_minimum_waived_extension', r.state === 'applied' || r.state === 'already_applied' ? 'ok' : 'error',
    { booking_id: a.bookingId, due: a.due, state: r.state, ...(r.state === 'retry' || r.state === 'failed' ? { code: r.code } : {}) })
  if (r.state === 'applied' || r.state === 'already_applied') {
    return respond(200, {
      success: true, free: true, waived: true, applied: true, state: r.state, due: a.due, card_rounding: round2(-a.due), charge: 0,
      booking_id: a.bookingId, total_price: r.totalPrice ?? null, new_booking_id: r.newBookingId ?? null, ...savedShape(a.saved),
      ...(a.redirect ? { checkout_url: a.redirect, url: a.redirect } : {}),
    })
  }
  if (r.state === 'retry') {
    return r.code === 'rounding_unavailable' ? refuse(409, 'rounding_unavailable', { waiver: true }, CS.rounding_unavailable_waiver) : refuse(503, 'server_error')
  }
  if (r.state === 'failed') return refuse(409, 'change_not_applicable', { reason: r.reason })
  return refuse(409, 'change_too_large')
}

/** Poukaz rezervace mezitím použitý jinde / vypršelý → kód poukazu, jinak null.
 *  Chyba dotazu platbu neblokuje (kontrola je pojistka). */
export async function voucherProblem(sb: Sb, bookingId: string): Promise<string | null> {
  try {
    const { data, error } = await sb.from('booking_discounts')
      .select('code, voucher_id, vouchers(code, status, booking_id, valid_until)')
      .eq('booking_id', bookingId).eq('kind', 'voucher')
    if (error || !Array.isArray(data)) return null
    const today = new Date().toISOString().slice(0, 10)
    for (const row of data as Array<Record<string, unknown>>) {
      const v = (Array.isArray(row.vouchers) ? row.vouchers[0] : row.vouchers) as Record<string, unknown> | null
      if (!v) continue
      const expired = !!v.valid_until && String(v.valid_until).slice(0, 10) < today
      const ok = !expired && (v.status === 'active' || (v.status === 'redeemed' && v.booking_id === bookingId))
      if (!ok) return String(v.code || row.code || '')
    }
    return null
  } catch { return null }
}

/** Proč pojistka v DB odmítla obnovení zrušené rezervace (stará appka obnovuje přímým
 *  zápisem) — jen záznam po posledním zrušení. {reason, code?} nebo null. */
export async function restoreRefusal(sb: Sb, bookingId: string, cancelledAt?: string | null): Promise<{ reason: string; code?: string } | null> {
  try {
    let q = sb.from('debug_log').select('request_data, created_at').eq('action', 'customer_restore_refused')
      .eq('request_data->>booking_id', bookingId)
    if (cancelledAt) q = q.gte('created_at', cancelledAt)
    const { data } = await q.order('created_at', { ascending: false }).limit(1)
    const rd = (Array.isArray(data) && data[0]?.request_data) || null
    if (!rd || !rd.error) return null
    return { reason: String(rd.error), ...(rd.code ? { code: String(rd.code) } : {}) }
  } catch { return null }
}
