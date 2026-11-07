// ===== _tests/f3-helpers.ts =====
// Sdílené pomůcky testů opravy f3 (f3_refund_test.ts, f3_webhook_cn_test.ts): falešný Stripe s vratkami
// a idempotency klíči, rezervace ve FakeDb a brána process-refund/index.ts (recovery / idempotentní / vratka).
import { isRecoveryOnlyReason } from '../_shared/refund-recovery.ts'
import { FakeDb } from './fake-supabase.ts'

export function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
export function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }
export type Row = Record<string, unknown>
export const BID = '11111111-2222-4333-8444-555555555555'
export const NOW = Date.UTC(2026, 9, 22, 12, 0, 0)
export type Pi = { id: string; status: string; amount_received: number; created: number; metadata: Record<string, string> }
export const pi = (id: string, h: number, created: number, md: Record<string, string> = { booking_id: BID, type: 'booking' }): Pi =>
  ({ id, status: 'succeeded', amount_received: h, created, metadata: md })
export const ext = (id: string, h: number, created: number, more: Record<string, string> = {}) =>
  pi(id, h, created, { booking_id: BID, type: 'extension', ...more })

export function fakeStripe(intents: Pi[]) {
  const refunds: Record<string, Array<{ id: string; amount: number; status: string; metadata: Record<string, string> }>> = {}
  const byKey = new Map<string, { id: string; amount: number; status: string }>()
  let n = 0
  const left = (id: string) => (intents.find((x) => x.id === id)?.amount_received || 0) - (refunds[id] || []).reduce((s, r) => s + r.amount, 0)
  const stripe = {
    paymentIntents: {
      search: () => Promise.resolve({ data: intents.filter((x) => x.metadata.booking_id === BID && x.status === 'succeeded') }),
      retrieve: (id: string) => { const x = intents.find((p) => p.id === id); return x ? Promise.resolve(x) : Promise.reject(new Error('missing')) },
    },
    refunds: {
      list: (p: Row) => Promise.resolve({ data: refunds[String(p.payment_intent)] || [] }),
      create: (p: Row, o: Row = {}) => {
        const key = String(o.idempotencyKey || '')
        if (key && byKey.has(key)) return Promise.resolve(byKey.get(key)!)
        const id = String(p.payment_intent)
        const amt = p.amount != null ? Number(p.amount) : left(id)
        if (amt <= 0 || amt > left(id)) return Promise.reject(new Error('charge_already_refunded'))
        const r = { id: `re_${++n}`, amount: amt, status: 'succeeded', metadata: (p.metadata || {}) as Record<string, string> }
        ;(refunds[id] ||= []).push(r); if (key) byKey.set(key, r)
        return Promise.resolve(r)
      },
    },
  }
  return { stripe, refunds, left, count: () => n }
}
export const db = (o: Row = {}, more: Record<string, Row[]> = {}) => new FakeDb({
  bookings: [{ id: BID, status: 'cancelled', payment_status: 'refund_pending', total_price: 3115, modification_history: [],
    stripe_payment_intent_id: 'pi_ext', stripe_refund_id: null, ...o }],
  debug_log: [], ...more,
})

/** Brána process-refund/index.ts pro rezervaci (bez zákaznických kontrol): co se s voláním stane. */
export function gate(body: Row, paymentStatus: string): 'recovery' | 'idempotent' | 'refund' | 'not_paid' {
  if (isRecoveryOnlyReason(body.reason)) return 'recovery'
  const wantsNewPartial = paymentStatus === 'partial_refund' && Number(body.amount) > 0
  if (paymentStatus === 'refunded' || (paymentStatus === 'partial_refund' && !wantsNewPartial)) return 'idempotent'
  if (paymentStatus !== 'paid' && paymentStatus !== 'refund_pending' && !wantsNewPartial) return 'not_paid'
  return 'refund'
}
