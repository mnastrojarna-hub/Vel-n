// ===== _tests/qr_bank_flow_test.ts =====
// qr-payment S NASAZENÝM SQL 20261130c/b: lhůta od volby QR v odpovědi, výpůjčka JEN výbavy end to end
// (vlastní šablona → běžná šablona → záložní mail ve znění pro výbavu), mail obsluze „potvrdí se
// automaticky“, a akce request / request_cancel (QR údaje existujícího požadavku pod tokenem volajícího).
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/qr_bank_flow_test.ts
// deno-lint-ignore-file no-explicit-any
import { BankDb, BID, booking, edgeCalls, eq, FN, MAPPED, net, OID, ok, order, post, request, RID, type Row, useDb } from './bank-helpers.ts'

const handle: any = MAPPED ? (await import(`${FN}qr-payment/handler.ts`)).handle : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })
const ANON = 'anon-bank-test', OWNER = 'own.jwt.token'

function setup(tables: Record<string, Row[]> = {}) {
  const db = new BankDb({ bookings: [], shop_orders: [], invoices: [], app_settings: [], admin_users: [], debug_log: [], bank_payment_requests: [], ...tables })
  let token = ''
  db.rpcs.set_booking_qr_payment = (a: Row) => {  // tělo po 20261130c: qr_requested_at + expires_at
    const b = db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row
    b.payment_vs = b.payment_vs || '10000600'
    b.qr_requested_at = b.qr_requested_at || '2026-12-01T09:00:00+00:00'
    Object.assign(b, { pay_channel: 'qr', payment_method: 'bank_transfer' })
    return { data: { success: true, booking_id: b.id, vs: b.payment_vs, amount: b.total_price, due_hours: 4, expires_at: '2026-12-01T13:00:00+00:00' }, error: null }
  }
  // RPC pod tokenem volajícího (pravidla z 20261130b2)
  db.rpcs.get_bank_payment_request = (a: Row) => {
    const rows = db.rows('bank_payment_requests')
    let r: Row | undefined
    if (a.p_request_id) r = rows.find((x) => x.id === a.p_request_id)
    else if (a.p_order_id) r = rows.find((x) => x.order_id === a.p_order_id)
    else if (a.p_booking_id) { if (token !== OWNER) return { data: { error: 'login_required' }, error: null }; r = rows.find((x) => x.booking_id === a.p_booking_id) }
    else return { data: { error: 'missing_identifier' }, error: null }
    if (!r) return { data: { status: 'none' }, error: null }
    return { data: { request_id: r.id, kind: r.kind, booking_id: r.booking_id, order_id: r.order_id, status: r.status, vs: r.vs, amount: r.amount, expires_at: r.expires_at,
      change_kind: r.change_kind ?? null, created_at: r.created_at, paid_at: r.paid_at ?? null, reason: r.status === 'failed' ? r.result?.reason : null }, error: null }
  }
  db.rpcs.cancel_bank_payment_request = (a: Row) => {
    const r = db.rows('bank_payment_requests').find((x) => x.id === a.p_request_id) as Row
    if (!r) return { data: { success: false, error: 'not_found' }, error: null }
    if (token !== OWNER) return { data: { success: false, error: 'forbidden' }, error: null }
    if (r.status !== 'pending') return { data: { success: false, error: 'wrong_status', status: r.status }, error: null }
    r.status = 'cancelled'
    return { data: { success: true }, error: null }
  }
  useDb(db)
  const n = net()
  n.edge['generate-invoice'] = () => ({ success: true, number: 'ZF-2026-0050', pdf_path: 'invoices/zf50.pdf' })
  const call = (body: Row, t = ANON) => { token = t; return post(handle, body, t) }
  return { db, n, call }
}
const mails = (n: any) => edgeCalls(n, 'send-email').map((c) => c.body as Row)

T('nové SQL: odpověď nese konec lhůty (4 h od volby QR) a druh rezervace; obsluze jde „potvrdí se automaticky“', async () => {
  const w = setup({ bookings: [booking({ payment_vs: null, pay_channel: null })] })
  try {
    const r = await w.call({ booking_id: BID, locale: 'cs' })
    eq([r.status, r.json.vs, r.json.expires_at, r.json.booking_kind, r.json.due_hours], [200, '10000600', '2026-12-01T13:00:00+00:00', 'moto', 4])
    const m = mails(w.n)
    eq(m.map((x) => x.template_slug || 'ops'), ['booking_qr_payment', 'ops'])
    ok(String(m[1].raw_html).includes('potvrdí AUTOMATICKY') && !String(m[1].raw_html).includes('potvrďte ve Velíně (rezervace'), 'nové znění mailu obsluze')
  } finally { w.n.restore() }
})

T('výpůjčka jen výbavy: vlastní šablona; bez ní běžná šablona; bez obou záložní mail ve znění pro výbavu (jazyk zákazníka)', async () => {
  const gear = () => booking({ payment_vs: null, pay_channel: null, moto_id: null, booking_kind: 'gear', motorcycles: null, total_price: 890 })
  const a = setup({ bookings: [gear()] })
  try {
    const r = await a.call({ booking_id: BID, locale: 'cs' })
    eq([r.json.booking_kind, r.json.amount, r.json.spd.includes('AM:890.00')], ['gear', 890, true])
    eq(mails(a.n).map((x) => x.template_slug || 'ops'), ['booking_qr_payment_gear', 'ops'])
    eq(edgeCalls(a.n, 'generate-invoice').map((c) => [c.body?.type, c.body?.variable_symbol]), [['advance', '10000600']])
  } finally { a.n.restore() }
  const b = setup({ bookings: [gear()] })
  try {
    b.n.edge['send-email'] = (m) => (m?.template_slug === 'booking_qr_payment_gear' ? { success: false, error: 'Template not found' } : { success: true })
    await b.call({ booking_id: BID, locale: 'cs' })
    eq(mails(b.n).map((x) => x.template_slug || 'ops'), ['booking_qr_payment_gear', 'booking_qr_payment', 'ops'])
  } finally { b.n.restore() }
  const c = setup({ bookings: [gear()] })
  try {
    c.n.edge['send-email'] = (m) => (m?.template_slug ? { success: false } : { success: true })
    await c.call({ booking_id: BID, locale: 'de' })
    const raw = mails(c.n)[2]
    eq(raw.subject, 'Zahlungsdaten zur Ausrüstungsmiete #' + BID.slice(-8).toUpperCase() + ' — QR / Banküberweisung')
    ok(String(raw.raw_html).includes('Ausrüstungsmiete') && String(raw.raw_html).includes('ZF-2026-0050') && String(raw.raw_html).includes('10000600'), 'záložní mail pro výbavu')
  } finally { c.n.restore() }
})

T('akce request: QR údaje požadavku (poukaz podle objednávky bez přihlášení; doplatek úpravy jen vlastník); nic neposílá', async () => {
  const w = setup({ shop_orders: [order({ language: 'en' })], bookings: [booking()],
    bank_payment_requests: [request(), request({ id: 'rq-chg', kind: 'booking_change', vs: '10000400', amount: 450.5, booking_id: BID, order_id: null, change_kind: 'edit', expires_at: '2026-12-01T10:30:00+00:00' })],
    app_settings: [{ key: 'company_info', value: { name: 'MotoGo24 s.r.o.', ico: '29909864', bank_account: '2303580494/2010', bank_iban: 'CZ8320100000002303580494', bank_name: 'Fio banka' } }] })
  try {
    const o = await w.call({ action: 'request', order_id: OID })
    eq([o.status, o.json.success, o.json.request_id, o.json.kind, o.json.status, o.json.vs, o.json.amount, o.json.account, o.json.iban, o.json.bank],
      [200, true, RID, 'shop_order', 'pending', '10000200', 1000, '2303580494/2010', 'CZ8320100000002303580494', 'Fio banka'])
    ok(o.json.spd === 'SPD*1.0*ACC:CZ8320100000002303580494*AM:1000.00*CC:CZK*X-VS:10000200*MSG:MotoGo24 order MG-2026-0042' && o.json.deadline_text.includes('7 days'), JSON.stringify(o.json))
    eq((await w.call({ action: 'request', booking_id: BID })).status, 401)
    const c = await w.call({ action: 'request', booking_id: BID, locale: 'cs' }, OWNER)
    eq([c.json.kind, c.json.amount, c.json.change_kind, c.json.expires_at], ['booking_change', 450.5, 'edit', '2026-12-01T10:30:00+00:00'])
    ok(c.json.spd.includes('AM:450.50') && c.json.spd.endsWith('MSG:MotoGo24 doplatek ' + BID.slice(-8).toUpperCase()) && c.json.deadline_text.includes('11:30'), c.json.deadline_text)
    eq((await w.call({ action: 'request', request_id: '00000000-0000-4000-8000-000000000000' })).json, { success: true, status: 'none' })
    eq((await w.call({ action: 'request' })).status, 400)
    eq(w.n.calls.filter((x: any) => x.url.includes('/functions/v1/')).length, 0, 'žádný e-mail ani doklad')
    eq(w.db.callsOf('rpc', 'set_booking_qr_payment').length, 0)
  } finally { w.n.restore() }
})

T('akce request_cancel: vlastník zruší čekající požadavek; cizí / zrušený / neexistující odmítnuto; bez SQL 503', async () => {
  const w = setup({ bookings: [booking()], bank_payment_requests: [request({ id: 'rq-chg', kind: 'booking_change', booking_id: BID, order_id: null })] })
  try {
    eq((await w.call({ action: 'request_cancel', request_id: 'rq-chg' })).status, 403)
    eq((await w.call({ action: 'request_cancel', request_id: 'rq-chg' }, OWNER)).json, { success: true })
    eq((await w.call({ action: 'request_cancel', request_id: 'rq-chg' }, OWNER)).status, 409)
    eq((await w.call({ action: 'request_cancel', request_id: 'nope' }, OWNER)).status, 404)
    eq((await w.call({ action: 'request_cancel' }, OWNER)).status, 400)
    delete w.db.rpcs.get_bank_payment_request; delete w.db.rpcs.cancel_bank_payment_request
    eq([(await w.call({ action: 'request', order_id: OID })).status, (await w.call({ action: 'request_cancel', request_id: 'rq-chg' }, OWNER)).status], [503, 503])
  } finally { w.n.restore() }
})
