// ===== _tests/pp_bank_modules_flow_test.ts =====
// process-payment — moduly platby převodem (bank-change.ts, bank-shop.ts, voucher-order.ts) nad in-memory DB:
//  • doplatek úpravy: naceněná změna se uloží jako čekající požadavek (60 min), rezervace se NEmění,
//    zákazník dostane QR (odpověď + e-mail), opakované odeslání nepošle druhý e-mail, žádné volání Stripe,
//  • poukaz: objednávka jako u karty (payment_method bank_transfer), požadavek 7 dní, ZF s VS požadavku,
//    e-mail s QR; POUKAZ NEVZNIKÁ; bez nasazeného SQL nevznikne nic (bank_unavailable).
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/pp_bank_modules_flow_test.ts
// deno-lint-ignore-file no-explicit-any
import { BankDb, BID, booking, edgeCalls, eq, FN, net, ok, type Row, UID, useDb } from './bank-helpers.ts'

const STRIPE = (() => { try { return import.meta.resolve('https://esm.sh/stripe@14').startsWith('file:') } catch { return false } })()
const chg: any = STRIPE ? await import(`${FN}process-payment/bank-change.ts`) : null
const shop: any = STRIPE ? await import(`${FN}process-payment/bank-shop.ts`) : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !STRIPE, sanitizeOps: false, sanitizeResources: false, fn })

function setup(tables: Record<string, Row[]> = {}, sql = true) {
  const db = new BankDb({ bookings: [], shop_orders: [], shop_order_items: [], vouchers: [], app_settings: [], debug_log: [], bank_payment_requests: [], ...tables })
  let seq = 10000700
  if (sql) {
    db.rpcs.create_bank_payment_request = (a: Row) => {  // jádro RPC z 20261130b1
      const rows = db.rows('bank_payment_requests')
      const col = a.p_kind === 'shop_order' ? 'order_id' : 'booking_id', id = a.p_kind === 'shop_order' ? a.p_order_id : a.p_booking_id
      const cur = rows.find((r) => r[col] === id && r.status === 'pending')
      if (cur && Number(cur.amount) === Number(a.p_amount) && cur.chg === a.p_chg) return { data: { success: true, reused: true, request_id: cur.id, vs: cur.vs, amount: cur.amount, expires_at: cur.expires_at }, error: null }
      if (cur) cur.status = 'cancelled'
      const r = { id: 'rq' + seq, kind: a.p_kind, vs: String(seq++), amount: a.p_amount, booking_id: a.p_booking_id, order_id: a.p_order_id, chg: a.p_chg, srv: a.p_srv, change_kind: a.p_change_kind,
        status: 'pending', language: a.p_language, created_by: a.p_created_by, expires_at: new Date(Date.parse('2026-12-01T09:00:00Z') + a.p_hold_minutes * 60000).toISOString() }
      rows.push(r)
      return { data: { success: true, reused: false, request_id: r.id, vs: r.vs, amount: r.amount, expires_at: r.expires_at }, error: null }
    }
    db.rpcs.cancel_bank_payment_request = (a: Row) => { const r = db.rows('bank_payment_requests').find((x) => x.id === a.p_request_id) as Row; r.status = 'cancelled'; r.note = a.p_note; return { data: { success: true }, error: null } }
  } else db.failSelect = (t) => (t === 'bank_payment_requests' ? { code: '42P01', message: 'relation "public.bank_payment_requests" does not exist' } : null)
  useDb(db)
  const n = net()
  n.edge['generate-invoice'] = () => ({ success: true, number: 'ZF-2026-0077', pdf_path: 'invoices/zf77.pdf' })
  return { db, n }
}
const change = { p_new_end: '2026-12-23', _base: { s: '2026-12-20', e: '2026-12-22', p: 3000 } }
const paid = () => booking({ status: 'reserved', payment_status: 'paid', payment_method: 'card', language: 'de' })
const mails = (n: any) => edgeCalls(n, 'send-email').map((c) => c.body as Row)
const voucher = (o: Row = {}) => ({ orderId: '99999999-2222-4333-8444-555555555555', customerName: 'Petra Malá', customerEmail: 'petra@example.com', customerPhone: '', shippingAddress: '', billingAddress: 'Dlouhá 1',
  customerCompany: '', customerIco: '', customerDic: '', amountCzk: 1062, voucherAmount: 1000, isPrint: true, printFee: 180, discount: 118,
  quote: { promo_code_id: 'p1', discount_codes: [{ code: 'PCT10' }] }, locale: 'cs', origin: 'https://www.motogo24.cz', ...o })

T('doplatek úpravy převodem: čekající požadavek 60 min s celým payloadem, rezervace beze změny, QR v odpovědi i e-mailem v jazyce zákazníka', async () => {
  const w = setup({ bookings: [paid()] })
  try {
    const before = JSON.stringify(w.db.rows('bookings')[0])
    const res: Response = await chg.bankChangeFlow(w.db, { bookingId: BID, userId: UID, change, srv: '{"t":4500}', due: 1500, locale: undefined })
    const j = await res.json()
    eq([res.status, j.success, j.pay_method, j.status, j.reused, j.vs, j.amount, j.hold_minutes, j.booking_number, j.account, 'checkout_url' in j],
      [200, true, 'bank', 'pending', false, '10000700', 1500, 60, BID.slice(-8).toUpperCase(), '2303580494/2010', false])
    ok(j.spd.includes('X-VS:10000700') && j.spd.includes('AM:1500.00') && j.qr_url.includes(encodeURIComponent(j.spd)) && j.expires_at === '2026-12-01T10:00:00.000Z' && j.deadline_text.includes('11:00'), JSON.stringify(j))
    const r = w.db.rows('bank_payment_requests')[0]
    eq([r.kind, r.booking_id, r.amount, r.chg, r.srv, r.change_kind, r.language, r.created_by], ['booking_change', BID, 1500, JSON.stringify(change), '{"t":4500}', 'edit', 'de', UID])
    eq(JSON.stringify(w.db.rows('bookings')[0]), before, 'rezervace se nezměnila')
    const m = mails(w.n)
    eq([m.length, m[0].template_slug, m[0].language, m[0].booking_id, m[0].to, m[0].template_vars.vs], [1, 'booking_change_qr_payment', 'de', BID, 'jan@example.com', '10000700'])
    // totéž znovu (obnovení stránky) → stejný požadavek, žádný druhý e-mail
    const again = await (await chg.bankChangeFlow(w.db, { bookingId: BID, userId: UID, change, srv: '{"t":4500}', due: 1500, locale: 'de' })).json()
    eq([again.reused, again.vs, mails(w.n).length, w.db.rows('bank_payment_requests').length], [true, '10000700', 1, 1])
    // jiná změna → nový požadavek a nový VS, starý zrušen
    const other = await (await chg.bankChangeFlow(w.db, { bookingId: BID, userId: UID, change: { ...change, p_new_end: '2026-12-24' }, srv: null, due: 3000, locale: 'de' })).json()
    eq([other.vs, w.db.rows('bank_payment_requests').map((x: Row) => x.status), mails(w.n).length], ['10000701', ['cancelled', 'pending'], 2])
    eq(w.n.calls.filter((c: any) => c.url.includes('stripe')).length, 0, 'žádné volání Stripe')
  } finally { w.n.restore() }
})

T('doplatek 1–15 Kč se platí přesně (bez dorovnání karty); druh změny; platba kartou čekající požadavek zruší', async () => {
  const w = setup({ bookings: [paid()] })
  try {
    const j = await (await chg.bankChangeFlow(w.db, { bookingId: BID, userId: UID, change: { _swap: { m: 'm2', d: '2026-12-21' } }, srv: null, due: 7.4, locale: 'cs' })).json()
    eq([j.amount, j.spd.includes('AM:7.40'), w.db.rows('bank_payment_requests')[0].change_kind], [7.4, true, 'swap'])
    eq([chg.bankChangeKind({ _gear: { sizes: {} } }), chg.bankChangeKind({ p_new_moto_id: 'x' }), chg.bankChangeKind({ p_new_start: 'x' })], ['gear', 'moto', 'edit'])
    await chg.cancelPendingBankChange(w.db, BID)
    eq([w.db.rows('bank_payment_requests')[0].status, w.db.rows('bank_payment_requests')[0].note], ['cancelled', 'zákazník zvolil platbu kartou'])
    await chg.cancelPendingBankChange(w.db, BID) // nic čekajícího → nic
    eq(w.db.callsOf('rpc', 'cancel_bank_payment_request').length, 1)
  } finally { w.n.restore() }
})

T('bez nasazeného SQL: bank_unavailable (503), nic nevznikne, žádný e-mail; zrušení čekajícího požadavku nic nedělá', async () => {
  const w = setup({ bookings: [paid()] }, false)
  try {
    const res: Response = await chg.bankChangeFlow(w.db, { bookingId: BID, userId: UID, change, srv: null, due: 1500, locale: 'cs' })
    eq([res.status, (await res.json()).code, w.n.calls.length], [503, 'bank_unavailable', 0])
    await chg.cancelPendingBankChange(w.db, BID)
    const v: Response = await shop.bankVoucherCheckout(w.db, voucher())
    eq([v.status, (await v.json()).code, w.db.rows('shop_orders').length, w.db.rows('shop_order_items').length, w.n.calls.length], [503, 'bank_unavailable', 0, 0, 0])
    eq((await (chg.bankNotAllowed() as Response).json()).code, 'bank_not_allowed')
  } finally { w.n.restore() }
})

T('poukaz převodem: objednávka jako u karty (bank_transfer, sleva dle kódu), požadavek 7 dní, ZF s VS požadavku, e-mail s QR; poukaz nevzniká', async () => {
  const w = setup()
  try {
    const res: Response = await shop.bankVoucherCheckout(w.db, voucher())
    const j = await res.json()
    const so = w.db.rows('shop_orders')[0]
    eq([res.status, j.success, j.pay_method, j.order_id, j.vs, j.amount, j.hold_days, j.invoice_number, j.confirm_url],
      [200, true, 'bank', so.id, '10000700', 1062, 7, 'ZF-2026-0077', `https://www.motogo24.cz/potvrzeni?order_id=${so.id}&flow=qr`])
    eq([so.status, so.payment_status, so.payment_method, so.total, so.subtotal, so.discount, so.promo_code_id, so.discount_codes[0].code, so.language, so.notes],
      ['new', 'pending', 'bank_transfer', 1062, 1000, 118, 'p1', 'PCT10', 'cs', 'Fyzický poukaz (tisk + poštovné)'])
    eq(w.db.rows('shop_order_items').map((i: Row) => [i.product_name, i.total_price]), [['Dárkový poukaz', 1000], ['Tisk a poštovné', 180]])
    const r = w.db.rows('bank_payment_requests')[0]
    eq([r.kind, r.order_id, r.amount, r.expires_at], ['shop_order', so.id, 1062, '2026-12-08T09:00:00.000Z'])
    eq(edgeCalls(w.n, 'generate-invoice').map((c) => c.body), [{ type: 'shop_proforma', order_id: so.id, send_email: false, language: 'cs', variable_symbol: '10000700', due_note: 'do 7 dnů od vystavení' }])
    const m = mails(w.n)
    eq([m.length, m[0].template_slug, m[0].to, m[0].order_id, m[0].attachment_paths[0].path, m[0].template_vars.amount, m[0].template_vars.invoice_suffix], [1, 'shop_qr_payment', 'petra@example.com', so.id, 'invoices/zf77.pdf', '1062.00 Kč', ' (č. ZF-2026-0077)'])
    ok(String(m[0].template_vars.deadline).includes('8. 12. 2026') && j.deadline_text === m[0].template_vars.deadline, m[0].template_vars.deadline)
    eq([w.db.rows('vouchers').length, w.db.callsOf('rpc', 'confirm_shop_payment').length, w.n.calls.filter((c: any) => c.url.includes('stripe')).length], [0, 0, 0], 'poukaz ani potvrzení platby před připsáním peněz; žádný Stripe')
  } finally { w.n.restore() }
})

T('poukaz převodem: požadavek se nepodaří založit → objednávka nezůstane viset (zrušena) a zákazník dostane bank_unavailable; chyba vložení objednávky = 500', async () => {
  const w = setup()
  try {
    w.db.rpcs.create_bank_payment_request = () => ({ data: null, error: { message: 'deadlock detected' } })
    const res: Response = await shop.bankVoucherCheckout(w.db, voucher({ locale: 'pl' }))
    eq([res.status, (await res.json()).code, w.db.rows('shop_orders')[0].status, edgeCalls(w.n, 'send-email').length], [503, 'bank_unavailable', 'cancelled', 0])
  } finally { w.n.restore() }
})
