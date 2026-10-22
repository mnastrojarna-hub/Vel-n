// ===== _tests/gear_paid_docs_test.ts =====
// EDGE-B (2026-10-23) výpůjčka JEN výbavy: doklady per rezervace po zaplacení (webhook Stripe,
// fio-sync, 0 Kč fallback) — gear = check_booking_docs_status_for (jen totožnost + 18+),
// motorka beze změny (check_booking_docs_status).
import { bookingDocsOk, bookingKindOf, paidMailType } from '../webhook-receiver/gear-docs.ts'
import { confirmBookingPayment } from '../webhook-receiver/payment-confirmers.ts'
import { FakeDb } from './fake-supabase.ts'
import { LooseDb, stubFetch } from './gear-fake.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
type Row = Record<string, unknown>
const BID = '11111111-2222-3333-4444-555566667777'

// ── doklady po zaplacení ─────────────────────────────────────────────────────
function docsDb(rows: Row[], o: { gearDocs?: unknown; gearErr?: boolean; motoDocs?: unknown; motoErr?: boolean } = {}) {
  const d = new FakeDb({ bookings: rows })
  if (!o.gearErr) d.rpcs.check_booking_docs_status_for = () => ({ data: o.gearDocs ?? null, error: null })
  d.rpcs.check_booking_docs_status = () => o.motoErr ? { data: null, error: { message: 'boom' } } : ({ data: o.motoDocs ?? null, error: null })
  return d
}
Deno.test('bookingDocsOk: gear = check_booking_docs_status_for(p_booking_id), motorka = check_booking_docs_status jako dřív', async () => {
  const g = docsDb([{ id: 'g1', booking_kind: 'gear' }], { gearDocs: 'Chybí doklad totožnosti' })
  eq(await bookingDocsOk(g, { id: 'g1', user_id: 'u1', end_date: '2026-11-12', moto_id: null }), false)
  eq(g.calls.filter((c) => c.op === 'rpc').map((c) => [c.fn, c.data]), [['check_booking_docs_status_for', { p_booking_id: 'g1' }]])
  eq(await bookingDocsOk(docsDb([{ id: 'g1', booking_kind: 'gear' }]), { id: 'g1' }), true, 'NULL = v pořádku')
  eq(await bookingDocsOk(docsDb([{ id: 'g1', booking_kind: 'gear' }], { gearErr: true }), { id: 'g1' }), false, 'gear: chybějící RPC = výzva k dokladu')
  const m = docsDb([{ id: 'm1', booking_kind: 'moto' }], { motoErr: true })
  eq(await bookingDocsOk(m, { id: 'm1', user_id: 'u1', end_date: '2026-11-12T00:00:00+00:00', moto_id: 'mm' }), true, 'motorka: chyba RPC = data null = OK (beze změny)')
  eq(m.calls.filter((c) => c.op === 'rpc').map((c) => [c.fn, c.data]), [['check_booking_docs_status', { p_user_id: 'u1', p_end_date: '2026-11-12', p_moto_id: 'mm' }]])
  const old = docsDb([{ id: 'm1', booking_kind: 'gear' }]); old.missingCols.add('booking_kind')
  eq(await bookingKindOf(old, 'm1'), 'moto', 'chybějící sloupec = motorka')
})

Deno.test('paidMailType: app vždy booking_reserved; web + doklady → reserved, bez dokladu → invoice_payment_receipt; docs_completed_at = hotovo', async () => {
  const miss = docsDb([{ id: 'g1', booking_kind: 'gear' }], { gearDocs: 'missing' })
  eq(await paidMailType(miss, { id: 'g1' }, 'app', 'gear'), 'booking_reserved')
  eq(await paidMailType(miss, { id: 'g1' }, 'web', 'gear'), 'invoice_payment_receipt')
  eq(await paidMailType(miss, { id: 'g1', docs_completed_at: '2026-11-01T10:00:00Z' }, 'web', 'gear'), 'booking_reserved')
  eq(await paidMailType(docsDb([{ id: 'g1', booking_kind: 'gear' }]), { id: 'g1' }, 'web', 'gear'), 'booking_reserved')
})

Deno.test('confirmBookingPayment: gear web bez dokladu → invoice_payment_receipt přes check_booking_docs_status_for; motorka beze změny', async () => {
  for (const [kind, docsRpc, docs, want] of [
    ['gear', 'check_booking_docs_status_for', 'missing', 'invoice_payment_receipt'],
    ['gear', 'check_booking_docs_status_for', null, 'booking_reserved'],
    ['moto', 'check_booking_docs_status', 'missing', 'invoice_payment_receipt'],
    ['moto', 'check_booking_docs_status', null, 'booking_reserved'],
  ] as const) {
    const db = new LooseDb({
      bookings: [{ id: BID, booking_kind: kind, booking_source: 'web', user_id: 'u1', moto_id: kind === 'gear' ? null : 'm1', start_date: '2026-11-10',
        end_date: '2026-11-12', total_price: 1470, language: 'cs', motorcycles: kind === 'gear' ? null : { model: 'BMW R 1250 GS', manual_url: '' },
        profiles: { full_name: 'Jana', email: 'jana@example.com' } }],
      debug_log: [],
    })
    db.rpcs.confirm_payment = () => ({ data: { success: true, was_already_paid: false }, error: null })
    db.rpcs[docsRpc] = () => ({ data: docs, error: null })
    db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
    const f = stubFetch(() => new Response('{}', { status: 200 }))
    try {
      eq(await confirmBookingPayment(db as never, BID, 'cs_1', 'pi_1'), 'ok')
    } finally { f.restore() }
    const mail = f.calls.find((c) => c.url.endsWith('/functions/v1/send-booking-email'))
    eq(mail?.body?.type, want, `${kind} docs=${docs}`)
    eq(db.callsOf('rpc', docsRpc).length, 1, `${kind}: ${docsRpc}`)
    eq(db.callsOf('rpc', kind === 'gear' ? 'check_booking_docs_status' : 'check_booking_docs_status_for').length, 0, `${kind}: druhá brána se nevolá`)
  }
})
