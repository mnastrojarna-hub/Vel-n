// ===== _tests/paid_change_customer_mail_test.ts =====
// Nezapsaná zaplacená změna (motorka mezitím obsazená — nová rezervace má přednost): zákazník
// dostane JEDEN e-mail v jazyce rezervace (co se stalo, rezervace beze změny, vratka, co dál),
// bez kontaktů; u nejednoznačného stavu (review) ne. Interní e-mail obsluze zůstává.
import { handlePaidChangeFailure } from '../_shared/paid-change-failure.ts'
import { paidChangeCustomerMail } from '../_shared/paid-change-customer-mail.ts'
import { FakeDb } from './fake-supabase.ts'

type Row = Record<string, unknown>
function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg: string) { if (!c) throw new Error(msg) }

function setup(lang = 'de', email: string | null = 'jan@example.com') {
  const d = new FakeDb({
    bookings: [{ id: 'b1234567-0000-0000-0000-00000000abcd', user_id: 'u1', language: lang, total_price: 3000, payment_status: 'paid',
      stripe_payment_intent_id: 'pi_orig' }],
    profiles: email ? [{ id: 'u1', email }] : [],
    debug_log: [],
  })
  const created: Row[] = []
  const stripe = { refunds: { create: (p: Row) => { created.push(p); return Promise.resolve({ id: 're_1' }) }, list: () => Promise.resolve({ data: [] }) } }
  return { d, stripe, created }
}
async function withFetch(fn: (mails: Row[]) => Promise<void>) {
  const mails: Row[] = []
  const orig = globalThis.fetch
  globalThis.fetch = ((url: string, init?: RequestInit) => {
    if (String(url).includes('/send-email')) mails.push(JSON.parse(String(init?.body || '{}')))
    return Promise.resolve(new Response(JSON.stringify({ success: true }), { status: 200 }))
  }) as typeof fetch
  try { await fn(mails) } finally { globalThis.fetch = orig }
}
const BID = 'b1234567-0000-0000-0000-00000000abcd'

Deno.test('zákaznický e-mail: obsazená motorka → jeden e-mail v jazyce rezervace, jednou na platbu', async () => {
  await withFetch(async (mails) => {
    const s = setup('de')
    const a = { bookingId: BID, payRef: 'pi_x', paidCzk: 15, code: 'change_failed', reason: 'new_moto_unavailable', via: 'test', stripe: s.stripe }
    eq(await handlePaidChangeFailure(s.d, a as never), 'auto')
    eq(await handlePaidChangeFailure(s.d, a as never), 'auto') // souběžný dokončovatel → nic dalšího
    const cust = mails.filter((m) => m.to === 'jan@example.com')
    eq(cust.length, 1, 'zákazník')
    eq(mails.filter((m) => m.to === 'info@motogo24.cz').length, 1, 'obsluha')
    eq(cust[0].language, 'de'); eq(cust[0].booking_id, BID)
    const html = String(cust[0].raw_html)
    ok(String(cust[0].subject).includes('#0000ABCD'), 'číslo rezervace v předmětu')
    ok(html.includes('15 Kč') && html.includes('neue Buchung hat Vorrang') && html.includes('bleibt unverändert'), 'obsah DE')
    ok(html.includes('/upravit-rezervaci?edit_booking=' + BID) && html.includes('https://motogo24.com'), 'odkaz na úpravu (mezinárodní doména)')
    ok(!/info@|\+420|774/.test(html), 'bez kontaktů (D5)')
  })
})

Deno.test('zákaznický e-mail: vratka přes obsluhu → text „vrátí obsluha"; review → žádný e-mail zákazníkovi', async () => {
  await withFetch(async (mails) => {
    const s = setup('cs')
    eq(await handlePaidChangeFailure(s.d, { bookingId: BID, payRef: 'pi_s', paidCzk: 200, code: 'change_failed', reason: 'new_moto_unavailable',
      via: 'test', autoRefund: false, stripe: s.stripe } as never), 'staff')
    const c1 = mails.filter((m) => m.to === 'jan@example.com')
    eq(c1.length, 1)
    ok(String(c1[0].raw_html).includes('vrátí naše obsluha do 2 pracovních dnů') && String(c1[0].raw_html).includes('200 Kč'), 'staff text CS')
    mails.length = 0
    eq(await handlePaidChangeFailure(s.d, { bookingId: BID, payRef: 'pi_r', paidCzk: 300, code: 'stale_payment', reason: 'stale_payment:old',
      via: 'test', review: true } as never), 'staff')
    eq(mails.filter((m) => m.to === 'jan@example.com').length, 0, 'review → jen obsluha')
    eq(mails.filter((m) => m.to === 'info@motogo24.cz').length, 1)
    mails.length = 0
    eq(await handlePaidChangeFailure(s.d, { bookingId: BID, payRef: 'pi_e', paidCzk: 300, code: 'apply_failed', reason: 'retry_exhausted:apply_failed',
      via: 'test', autoRefund: false } as never), 'staff')
    eq(mails.filter((m) => m.to === 'jan@example.com').length, 0, 'zápis po 3 dnech nedoběhl → rozhodne obsluha, zákazníkovi nic neslibovat')
  })
})

Deno.test('zákaznický e-mail: bez e-mailu v profilu se nic neposílá; neznámý jazyk → čeština', async () => {
  await withFetch(async (mails) => {
    const s = setup('cs', null)
    eq(await handlePaidChangeFailure(s.d, { bookingId: BID, payRef: 'pi_n', paidCzk: 50, code: 'change_failed', reason: 'swap_date_out_of_range',
      via: 'test', stripe: s.stripe } as never), 'auto')
    eq(mails.length, 1) // jen obsluha
  })
  const m = paidChangeCustomerMail({ lang: 'xx', bookingId: BID, amount: 7.5, taken: false, staff: false, site: 'https://www.motogo24.cz' })
  eq(m.lang, 'cs')
  ok(m.subject.startsWith('Rezervace #0000ABCD: změnu nešlo zapsat'), m.subject)
  ok(m.html.includes('7,50 Kč') && m.html.includes('rezervace mezitím změnila'), 'obecný důvod + částka s haléři (2 desetinná místa jako web)')
})
