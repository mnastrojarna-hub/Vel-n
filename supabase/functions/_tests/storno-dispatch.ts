// ===== _tests/storno-dispatch.ts =====
// Volající storna pro flow testy (HOTFIX 2026-10-29) — přesná těla a pořadí jako v živém kódu.
// deno-lint-ignore-file no-explicit-any
import { ADMIN_ID, BID, EMAIL, bk, call, creditNotes, dbNow, deliver, insert, pgNow, rows, tier, world } from './storno-harness.ts'

/** DB trigger trg_notify_booking_cancelled_email → notify_booking_cancelled_email() → pg_net (service klíč). */
export const trigger = () => call('send-cancellation-email', { booking_id: BID, cancellation_reason: bk().cancellation_reason || '',
  cancelled_by_source: bk().cancelled_by_source || '', source: bk().booking_source || 'app' })

/** Kdy dorazí volání z triggeru vůči Velínu: před jeho process-refund / uvnitř (hned po refunds.create) / souběžně / po něm. */
export type TriggerMode = 'none' | 'before' | 'mid' | 'concurrent' | 'after'

/** Velín cancelBookingFromVelin (velin/src/pages/booking/bookingMessageHelpers.js) — admin JWT. */
export async function velinCancel(choice: number | 'full', mode: TriggerMode = 'none') {
  const b = bk()
  const wasPaid = b.payment_status === 'paid'
  const total = Math.max(0, Math.round(Number(b.total_price) || 0))
  let refundAmount = wasPaid ? total : 0
  if (wasPaid && choice !== 'full') refundAmount = Math.min(total, Math.max(0, Math.round(choice)))
  const refundPercent = wasPaid && total > 0 ? Math.round(refundAmount / total * 100) : 0
  const isFull = wasPaid && refundAmount >= total
  const noRefund = wasPaid && refundAmount === 0
  // UPDATE (commit → trigger); cancelled_at z hodin prohlížeče
  Object.assign(b, { status: 'cancelled', cancelled_by: ADMIN_ID, cancelled_by_source: 'velin', cancellation_reason: 'Storno (Velín)', cancelled_at: new Date().toISOString(),
    ...(wasPaid && !noRefund ? { payment_status: 'refund_pending' } : {}) })
  if (mode === 'before') await trigger()
  const t = mode === 'concurrent' ? trigger() : null
  if (wasPaid && b.total_price) {
    await insert('booking_cancellations', { booking_id: BID, cancelled_by: b.cancelled_by, reason: 'Storno (Velín)', refund_amount: refundAmount, refund_percent: refundPercent, created_at: dbNow() })
    if (!noRefund) {
      let hooked = false
      if (mode === 'mid') world().onRefundCreated = async () => { if (!hooked) { hooked = true; await trigger() } }
      await call('process-refund', { booking_id: BID, reason: 'cancellation', ...(isFull ? {} : { amount: refundAmount }) }, 'admin').catch(() => null)
      world().onRefundCreated = null
      if (mode === 'mid' && !hooked) await trigger()
    } else if (mode === 'mid') await trigger()
  }
  if (t) await t
  if (mode === 'after') await trigger()
  await call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, customer_name: 'Test Zákazník', motorcycle: b.booking_kind === 'gear' ? undefined : 'Test Moto',
    start_date: b.start_date, end_date: b.end_date, cancellation_reason: 'Storno (Velín)', cancelled_by_source: 'velin', source: 'app',
    ...(wasPaid ? { refund_amount: refundAmount, refund_percent: refundPercent } : {}) }, 'admin')
  return { refundAmount, refundPercent }
}

/** RPC cancel_booking_tracked (20261023e): pásmo k LEAST(refund_pickup_time, pickup_time), strop po posunu; UPDATE +
 *  INSERT booking_cancellations v JEDNÉ transakci (cancelled_at = created_at = now()), pak pg_net send-cancellation-email. */
export function rpcCancel(cap = 100) {
  const b = bk()
  const least = [b.refund_pickup_time, b.pickup_time].filter(Boolean).sort()[0]
  const pct = Math.min(tier.refundTierPercent(b.start_date, least), cap)
  const amt = Math.round(Number(b.total_price || 0) * pct / 100)
  const ts = pgNow()
  Object.assign(b, { status: 'cancelled', cancelled_at: ts, cancelled_by_source: 'customer', cancellation_reason: 'Stornováno zákazníkem' })
  rows('booking_cancellations').push({ id: crypto.randomUUID(), booking_id: BID, reason: null, refund_amount: amt, refund_percent: pct, created_at: ts })
  const R = () => call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, customer_name: 'Test Zákazník',
    motorcycle: b.booking_kind === 'gear' ? '' : 'Test Moto', start_date: b.start_date, end_date: b.end_date,
    cancellation_reason: 'Stornováno zákazníkem', cancelled_by_source: 'customer', refund_amount: amt, refund_percent: pct, source: 'app' })
  return { pct, amt, R }
}
export type CustMode = 'none' | 'rpcFirst' | 'triggerFirst' | 'concurrent'
export async function customerCancel(mode: CustMode, cap = 100) {
  const c = rpcCancel(cap)
  if (mode === 'none') await c.R()
  else if (mode === 'rpcFirst') { await c.R(); await trigger() }
  else if (mode === 'triggerFirst') { await trigger(); await c.R() }
  else await Promise.all([trigger(), c.R()])
  return c
}

/** Velín hromadné „Zrušit“ (BookingsBulkActionsModal) / AI copilot update_booking_status: jen stav, žádná vratka ani mail. */
export async function bulkCancel(withTrigger: boolean) {
  Object.assign(bk(), { status: 'cancelled', cancelled_at: new Date().toISOString(), cancelled_by_source: 'admin', cancellation_reason: 'Hromadné storno' })
  if (withTrigger) await trigger()
}

/** Velín „Potvrdit (částečné) vrácení“ u zrušené rezervace (BookingDetail confirmCancelledRefund). */
export async function velinConfirm(amt: number) {
  const total = Math.max(0, Math.round(Number(bk().total_price) || 0))
  const pct = total > 0 ? Math.round(amt / total * 100) : 0
  if (amt > 0 && !creditNotes().find((c) => Math.abs(Number(c.total) || 0) === amt)) {
    await call('process-refund', { booking_id: BID, reason: 'cancellation', ...(amt >= total ? {} : { amount: amt }) }, 'admin')
  }
  const last = rows('booking_cancellations').at(-1)
  if (last) Object.assign(last, { refund_amount: amt, refund_percent: pct })
  await call('send-cancellation-email', { booking_id: BID, customer_email: EMAIL, cancellation_reason: bk().cancellation_reason, cancelled_by_source: 'velin',
    source: 'app', refund_amount: amt, refund_percent: pct, skip_refund: true, force: true }, 'admin')
}

/** Plná vratka ručně v Stripe dashboardu u ŽIVÉ rezervace → webhook ji zruší (+ trigger po jeho UPDATE). */
export async function portalFullRefund(withTrigger: boolean) {
  await world().dashboardRefund('pi_orig')
  const ev = world().takeEvents()
  if (!withTrigger) return void await deliver(ev)
  const db = (globalThis as any).__STORNO_DB
  let t: Promise<any> | null = null, fired = false
  db.beforeUpdate = (tb: string, patch: any) => { if (!fired && tb === 'bookings' && patch.status === 'cancelled') { fired = true; queueMicrotask(() => { t = trigger() }) } }
  await deliver(ev); db.beforeUpdate = null
  await t
}
