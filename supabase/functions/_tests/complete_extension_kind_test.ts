// ===== _tests/complete_extension_kind_test.ts =====
// Web po návratu ze Stripe (complete_extension se session_id): u nezapsané změny server říká i
// DRUH změny (change_kind) — web podle něj nabídne „Vybrat jinou motorku" na správné záložce
// i bez lokálního záznamu prohlížeče (jiný prohlížeč / smazané úložiště, změna motorky v jádru).
import { FakeDb } from './fake-supabase.ts'

Deno.env.set('STRIPE_SECRET_KEY', Deno.env.get('STRIPE_SECRET_KEY') || 'sk_test_dummy')
const { changeKind, handleCompleteExtension } = await import('../process-payment/complete-extension.ts')

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}

Deno.test('changeKind: výměna / změna motorky / jiná úprava / nečitelný payload', () => {
  eq(changeKind({ chg: JSON.stringify({ _swap: { m: 'm2', d: '2026-11-11' } }) }), 'swap')
  eq(changeKind({ chg: JSON.stringify({ p_new_moto_id: 'm2' }) }), 'moto')
  eq(changeKind({ chg: JSON.stringify({ p_new_end: '2026-11-14' }) }), 'edit')
  eq(changeKind({ chg: '{"_swap":{"m":"m2",', chg_2: '"d":"2026-11-11"}}' }), 'swap', 'payload rozdělený do chg_2')
  eq(changeKind({}), null)
  eq(changeKind({ chg: '{nečitelné' }), null)
})

Deno.test('complete_extension (web session): už vyhodnocená obsazená výměna → failed + change_kind swap', async () => {
  const d = new FakeDb({
    bookings: [{ id: 'b1', user_id: 'u1', status: 'reserved', payment_status: 'paid', modification_history: [] }],
    debug_log: [{ id: 'l1', action: 'paid_change_failed', created_at: '2026-10-16T12:00:00Z',
      request_data: { payment_ref: 'pi_w', reason: 'new_moto_unavailable', expect_refund: 'auto' }, response_data: { refund: 'auto' } }],
  })
  const stripe = {
    checkout: { sessions: { retrieve: () => Promise.resolve({ id: 'cs_1', payment_status: 'paid', status: 'complete', payment_intent: 'pi_w', amount_total: 1500,
      metadata: { type: 'extension', booking_id: 'b1', chg: JSON.stringify({ _swap: { m: 'm2', d: '2026-11-11' } }) } }) } },
    paymentIntents: { retrieve: () => Promise.resolve({ id: 'pi_w', status: 'succeeded', metadata: {}, amount_received: 1500, created: Math.floor(Date.now() / 1000) - 60 }) },
    refunds: { list: () => Promise.resolve({ data: [] }) },
  }
  const res = await handleCompleteExtension(new Request('https://x'), { action: 'complete_extension', session_id: 'cs_1' }, d,
    { stripe, auth: () => Promise.resolve({ kind: 'user', userId: 'u1' }) })
  const j = await res.json()
  eq(j.state, 'failed'); eq(j.reason, 'new_moto_unavailable'); eq(j.refund, 'auto'); eq(j.amount, 15)
  eq(j.change_kind, 'swap')
})
