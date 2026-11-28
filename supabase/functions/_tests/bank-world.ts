// ===== _tests/bank-world.ts =====
// Svět flow testů Fio synchronizace: in-memory DB se stavem synchronizace (emulace SQL 20261130a1) a
// emulací potvrzovacích RPC (confirm_payment vč. obnovení zrušené rezervace, confirm_booking_surcharge,
// confirm_shop_payment + DB trigger vystavení poukazu) + náhrada fetch (Fio API, volání mezi funkcemi).
// deno-lint-ignore-file no-explicit-any
import { BankDb, clock, net, OID, type Row, useDb, withState } from './bank-helpers.ts'

export function world(tables: Record<string, Row[]> = {}, state: Row = {}) {
  clock.t = Date.parse('2026-12-01T10:00:00Z')
  const db = new BankDb({ fio_transactions: [], bookings: [], shop_orders: [], shop_order_items: [{ order_id: OID, product_name: 'Dárkový poukaz' }], vouchers: [], invoices: [],
    debug_log: [], admin_audit_log: [], message_threads: [], messages: [], bank_payment_requests: [], app_settings: [], ...tables })
  const st = withState(db, state)
  const flags = { taken: false, confirmFails: false }
  db.rpcs.confirm_payment = (a: Row) => {
    const b = db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row
    if (flags.confirmFails) return { data: null, error: { message: 'connection reset' } }
    if (!b) return { data: { success: false, error: 'Rezervace nenalezena' }, error: null }
    if (b.payment_status === 'paid') return { data: { success: true, was_already_paid: true }, error: null }
    if (b.status === 'cancelled' && flags.taken) return { data: { success: false, error: 'Potvrzení platby selhalo: Překrývající se rezervace' }, error: null }
    const revived = b.status === 'cancelled'
    Object.assign(b, { payment_status: 'paid', payment_method: a.p_method, status: 'reserved', cancelled_by_source: null })
    return { data: { success: true, was_already_paid: false, revived }, error: null }
  }
  db.rpcs.confirm_booking_surcharge = (a: Row) => {
    const b = db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row
    b.mod_surcharge_due = 0
    return { data: { success: true }, error: null }
  }
  db.rpcs.confirm_shop_payment = (a: Row) => {
    const o = db.rows('shop_orders').find((r) => r.id === a.p_order_id) as Row
    if (o.payment_status === 'paid') return { data: { success: true, was_already_paid: true }, error: null }
    Object.assign(o, { payment_status: 'paid', payment_method: a.p_method, status: 'confirmed' })
    db.rows('vouchers').push({ id: 'v1', order_id: o.id, code: 'MG-TEST-1', amount: 1000, valid_until: '2027-12-01' }) // DB trigger
    return { data: { success: true, was_already_paid: false }, error: null }
  }
  db.rpcs.check_booking_docs_status = () => ({ data: null, error: null })
  db.rpcs.check_booking_docs_status_for = () => ({ data: null, error: null })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  db.rpcs._late_pickup_discount = () => ({ data: 0, error: null })
  useDb(db)
  const n = net()
  return { db, st, n, flags }
}
