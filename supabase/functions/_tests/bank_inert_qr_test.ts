// ===== _tests/bank_inert_qr_test.ts =====
// DŮKAZ „nový kód + dnešní databáze = dnešní chování“ pro qr-payment. Dnešní databáze = RPC
// set_booking_qr_payment nevrací `expires_at` (SQL 20261130c není nasazené). Každý scénář se pustí
// zmrazenou kopií dnešního handleru (_tests/legacy/qr_payment_legacy.ts) i novým (qr-payment/handler.ts)
// a porovná se VŠE: odpověď, zápisy do DB, volání RPC a všechna volání ven v přesném pořadí (zálohová
// faktura, e-mail zákazníkovi ze šablony i záložní, e-mail obsluze) včetně textů.
// Spuštění: deno test --allow-all --no-check --import-map=supabase/functions/_tests/storno-flow-map.json supabase/functions/_tests/bank_inert_qr_test.ts
// deno-lint-ignore-file no-explicit-any
import { BankDb, BID, booking, eq, FN, loadHandler, MAPPED, net, ok, post, type Row, SVC, useDb } from './bank-helpers.ts'

const legacy = MAPPED ? await loadHandler(`${FN}_tests/legacy/qr_payment_legacy.ts`) : null
const fresh: any = MAPPED ? (await import(`${FN}qr-payment/handler.ts`)).handle : null
const T = (name: string, fn: () => Promise<void>) => Deno.test({ name, ignore: !MAPPED, sanitizeOps: false, sanitizeResources: false, fn })

type Sc = { body: Row; token?: string; bookings?: Row[]; templateOk?: boolean; invoices?: Row[]; settings?: Row[] }
async function observe(handler: any, sc: Sc) {
  let vsSeq = 10000500
  const db = new BankDb({ bookings: (sc.bookings ?? [booking({ payment_vs: null, pay_channel: null })]).map((b) => ({ ...b })), invoices: (sc.invoices ?? []).map((i) => ({ ...i })),
    app_settings: sc.settings ?? [], admin_users: [], debug_log: [] })
  db.failSelect = (t) => (t === 'bank_payment_requests' ? { code: '42P01', message: 'relation "public.bank_payment_requests" does not exist' } : null)
  db.rpcs.set_booking_qr_payment = (a: Row) => {   // dnešní tělo (20260705): bez expires_at
    const b = db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row
    if (!b) return { data: { success: false, error: 'not_found' }, error: null }
    if (!b.payment_vs) b.payment_vs = String(vsSeq++)
    Object.assign(b, { pay_channel: 'qr', payment_method: 'bank_transfer' })
    return { data: { success: true, booking_id: b.id, vs: b.payment_vs, amount: b.total_price, due_hours: 4 }, error: null }
  }
  db.rpcs.set_booking_mod_surcharge = (a: Row) => {
    const b = db.rows('bookings').find((r) => r.id === a.p_booking_id) as Row
    if (!(Number(b.mod_surcharge_due) > 0)) return { data: { success: false, error: 'no_surcharge_pending' }, error: null }
    b.mod_surcharge_vs = b.mod_surcharge_vs || '10000900'
    return { data: { success: true, vs: b.mod_surcharge_vs, amount: b.mod_surcharge_due }, error: null }
  }
  useDb(db)
  const n = net()
  n.edge['send-email'] = (b) => (b?.template_slug && sc.templateOk === false ? { success: false, error: 'Template not found' } : { success: true })
  n.edge['generate-invoice'] = () => ({ success: true, number: 'ZF-2026-0042', pdf_path: 'invoices/zf42.pdf' })
  try {
    const res = await post(handler, sc.body, sc.token ?? 'anon-bank-test')
    return { status: res.status, body: res.json, writes: db.calls.filter((c) => c.op !== 'select' && c.op !== 'rpc').map((c) => ({ op: c.op, table: c.table, data: c.data })),
      rpcs: db.calls.filter((c) => c.op === 'rpc').map((c) => ({ fn: c.fn, args: c.data })),
      http: n.calls.filter((c) => !c.url.includes('/auth/v1/')).map((c) => ({ url: c.url, body: c.body })), bookings: db.rows('bookings') }
  } finally { n.restore() }
}
async function parity(name: string, sc: Sc) {
  const a: any = await observe(legacy, sc), b: any = await observe(fresh, sc)
  for (const k of ['status', 'body', 'rpcs', 'writes', 'http', 'bookings']) {
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) throw new Error(`${name}: rozdíl v „${k}“\n dnes: ${JSON.stringify(a[k])}\n nově: ${JSON.stringify(b[k])}`)
  }
  return b
}
const mailsOf = (r: any) => r.http.filter((h: Row) => h.url.endsWith('/send-email'))

T('parita: první volba QR (motorka) — VS, zálohová faktura, mail ze šablony, mail obsluze; všech 8 jazyků', async () => {
  const r = await parity('cs', { body: { booking_id: BID, locale: 'cs' } })
  eq([r.status, r.body.success, r.body.vs, r.body.due_hours, 'expires_at' in r.body, 'booking_kind' in r.body], [200, true, '10000500', 4, false, false])
  eq(mailsOf(r).map((m: Row) => m.body.template_slug || 'ops'), ['booking_qr_payment', 'ops'])
  ok(String(mailsOf(r)[1].body.raw_html).includes('potvrďte ve Velíně'), 'mail obsluze v dnešním znění')
  for (const lang of ['en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) await parity(lang, { body: { booking_id: BID, locale: lang } })
})

T('parita: šablona nedostupná → záložní mail; opakované volání bez mailů; důvěryhodný volající posílá vždy', async () => {
  const f = await parity('záložní', { body: { booking_id: BID, locale: 'de' }, templateOk: false })
  eq(mailsOf(f).length, 3)
  const quiet = await parity('opakování', { body: { booking_id: BID }, bookings: [booking()] })
  eq([quiet.http.length, quiet.body.vs], [0, '10000123'])
  const trusted = await parity('admin / server', { body: { booking_id: BID }, bookings: [booking()], token: SVC, invoices: [{ booking_id: BID, type: 'proforma', status: 'issued', number: 'ZF-2026-0001', pdf_path: 'invoices/x.pdf' }] })
  eq(mailsOf(trusted).length, 2)
})

T('parita: výpůjčka jen výbavy bez nového SQL = stejné jako motorka; doplatek z Velínu; jiný účet v nastavení', async () => {
  const g = await parity('výbava', { body: { booking_id: BID, locale: 'cs' }, bookings: [booking({ payment_vs: null, pay_channel: null, moto_id: null, booking_kind: 'gear', motorcycles: null })] })
  eq(mailsOf(g)[0].body.template_slug, 'booking_qr_payment')
  const s = await parity('doplatek', { body: { booking_id: BID, surcharge: true }, token: SVC, bookings: [booking({ status: 'reserved', payment_status: 'paid', mod_surcharge_due: 450 })] })
  eq([s.body.amount, mailsOf(s)[0].body.template_slug], [450, 'booking_qr_payment_surcharge'])
  const o = await parity('jiný účet', { body: { booking_id: BID }, settings: [{ key: 'company_info', value: { name: 'Jiná s.r.o.', ico: '12345678', bank_account: '19-2000145399/0800' } }] })
  eq([o.body.account, o.body.iban.slice(0, 2)], ['19-2000145399/0800', 'CZ'])
})

T('parita: odmítnutí — chybí id, neexistuje, není z webu, už zaplaceno, doplatek od nedůvěryhodného, RPC chyba', async () => {
  eq((await parity('bez id', { body: {} })).status, 400)
  eq((await parity('neexistuje', { body: { booking_id: 'nope' } })).status, 404)
  eq((await parity('appka', { body: { booking_id: BID }, bookings: [booking({ booking_source: 'app' })] })).body.error, 'not_web_booking')
  eq((await parity('zaplaceno', { body: { booking_id: BID }, bookings: [booking({ payment_status: 'paid' })] })).body.error, 'already_paid')
  eq((await parity('doplatek anon', { body: { booking_id: BID, surcharge: true } })).status, 403)
  eq((await parity('doplatek bez dluhu', { body: { booking_id: BID, surcharge: true }, token: SVC })).body.error, 'no_surcharge_pending')
})
