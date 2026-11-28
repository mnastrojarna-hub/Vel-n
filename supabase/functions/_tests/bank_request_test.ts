// ===== _tests/bank_request_test.ts =====
// _shared/bank-request.ts + texty: požadavek na platbu převodem (VS z RPC, opakované odeslání = tentýž
// požadavek bez nového mailu), QR řetězec (SPD) a platební údaje VŽDY z app_settings.company_info,
// e-mail zákazníkovi ze šablony s proměnnými v jeho jazyce + záložní HTML, texty v 8 jazycích.
// Běží i bez import mapy (žádné vzdálené importy).
// deno-lint-ignore-file no-explicit-any
import { BankDb, eq, net, OID, ok, type Row } from './bank-helpers.ts'
import { bankDetails, bankRequestFallbackHtml, bankRequestsAvailable, bankSpdMessage, createBankRequest, deadlineText, sendBankRequestMail } from '../_shared/bank-request.ts'
import { BANK_TEXTS, deadlineLabel } from '../_shared/bank-request-texts.ts'
import { GEAR_QR, gearEmailHtml } from '../qr-payment/gear-texts.ts'
import { QR_LANGS } from '../qr-payment/texts.ts'

const ENV = { url: 'https://fake.supabase.test', key: 'svc' }
const company = (v: Row) => [{ key: 'company_info', value: v }]
function dbWith(rpc?: (a: Row) => any, settings: Row[] = []) {
  const db = new BankDb({ app_settings: settings, bank_payment_requests: [] })
  if (rpc) db.rpcs.create_bank_payment_request = rpc
  return db
}
const okRpc = (o: Row = {}) => (_a: Row) => ({ data: { success: true, reused: false, request_id: 'rq1', vs: '10000777', amount: 1062, expires_at: '2026-12-08T09:00:00+00:00', ...o }, error: null })

Deno.test('texty požadavku na platbu: 8 jazyků, žádný prázdný text, lhůta obsahuje čas / datum, QR zpráva jen ASCII', () => {
  eq([...QR_LANGS], ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'])
  for (const lang of QR_LANGS) {
    const t = BANK_TEXTS[lang], g = GEAR_QR[lang]
    for (const s of [t.orderSubject('MG-1'), t.orderIntro('<b>MG-1</b>'), t.orderDeadline('8. 12. 2026'), t.orderAfter, t.changeDeadline('14:35'), t.changeNote, t.changeAfter,
      g.subject('AB12'), g.intro('<b>#AB12</b>'), g.deadline, g.after]) ok(typeof s === 'string' && s.trim().length > 10, `${lang}: prázdný text`)
    ok(t.orderSubject('MG-1').includes('MG-1') && t.orderIntro('<b>MG-1</b>').includes('<b>MG-1</b>') && g.subject('AB12').includes('#AB12'), `${lang}: číslo v textu`)
    ok(t.changeDeadline('14:35').includes('14:35') && t.changeDeadline('14:35').includes('60') && t.orderDeadline('X-DATE').includes('X-DATE') && t.orderDeadline('X').includes('7'), `${lang}: lhůta`)
    for (const kind of ['shop_order', 'booking_change'] as const) {
      const m = bankSpdMessage(kind, lang, 'MG-2026-0042')
      ok(/^[\x20-\x29\x2B-\x7E]+$/.test(m) && m.includes('MG-2026-0042') && m.startsWith('MotoGo24 '), `${lang}/${kind}: ${m}`)
    }
    ok(gearEmailHtml({ custName: 'Jan', amount: 500, account: 'A', iban: 'CZ00', bank: 'B', vs: '1', qrUrl: 'u', bookingNumber: 'AB12', invoiceNumber: 'ZF-1' }, lang).includes('#AB12'), `${lang}: gear html`)
  }
  eq(new Set(QR_LANGS.map((l) => BANK_TEXTS[l].changeNote)).size, 8, 'každý jazyk má vlastní text')
  eq([deadlineLabel('cs', '2026-12-01T13:35:00Z', 'time'), deadlineLabel('en', '2026-12-01T13:35:00Z', 'time'), deadlineLabel('cs', '2026-12-08T09:00:00Z', 'date'), deadlineLabel('de', '2026-12-08T09:00:00Z', 'date')],
    ['14:35', '14:35', '8. 12. 2026', '8.12.2026'])
  eq(deadlineLabel('cs', 'nonsense', 'time'), '')
})

Deno.test('platební údaje a QR (SPD) jdou z company_info; bez nastavení výchozí provozovatel; nikdy jiný IBAN než vypsaný účet', async () => {
  const d = await bankDetails(dbWith(undefined, company({ name: 'MotoGo24 s.r.o.', ico: '29909864', bank_account: '2303580494/2010', bank_iban: 'CZ8320100000002303580494', bank_name: 'Fio banka' })),
    { vs: '10000777', amount: 1062.5, message: 'MotoGo24 objednavka MG-1', expiresAt: '2026-12-08T09:00:00+00:00' })
  eq(d, { vs: '10000777', amount: 1062.5, currency: 'czk', account: '2303580494/2010', iban: 'CZ8320100000002303580494', bank: 'Fio banka',
    spd: 'SPD*1.0*ACC:CZ8320100000002303580494*AM:1062.50*CC:CZK*X-VS:10000777*MSG:MotoGo24 objednavka MG-1',
    qr_url: 'https://api.qrserver.com/v1/create-qr-code/?size=280x280&data=' + encodeURIComponent('SPD*1.0*ACC:CZ8320100000002303580494*AM:1062.50*CC:CZK*X-VS:10000777*MSG:MotoGo24 objednavka MG-1'),
    expires_at: '2026-12-08T09:00:00+00:00' })
  const other = await bankDetails(dbWith(undefined, company({ name: 'Jiná s.r.o.', ico: '12345678', bank_account: '19-2000145399/0800' })), { vs: '1', amount: 10, message: 'm' })
  eq([other.account, other.iban, other.bank], ['19-2000145399/0800', 'CZ6508000000192000145399', 'kód banky 0800'])
  const none = await bankDetails(dbWith(), { vs: '1', amount: 10, message: 'm' })
  eq([none.account, none.iban], ['2303580494/2010', 'CZ8320100000002303580494'])
})

Deno.test('createBankRequest: parametry RPC, opakování (reused), odmítnutí, SQL nenasazené = bank_unavailable', async () => {
  let args: Row = {}
  const db = dbWith((a) => { args = a; return okRpc()(a) })
  const r: any = await createBankRequest(db, { kind: 'shop_order', orderId: OID, amount: 1062, holdMinutes: 10080, lang: 'de', number: 'MG-2026-0042' })
  eq(args, { p_kind: 'shop_order', p_amount: 1062, p_booking_id: null, p_order_id: OID, p_hold_minutes: 10080, p_chg: null, p_srv: null, p_change_kind: null, p_language: 'de', p_created_by: null })
  eq([r.ok, r.reused, r.requestId, r.details.vs, r.details.amount, r.details.expires_at], [true, false, 'rq1', '10000777', 1062, '2026-12-08T09:00:00+00:00'])
  ok(r.details.spd.includes('X-VS:10000777') && r.details.spd.endsWith('MSG:MotoGo24 Bestellung MG-2026-0042') && r.deadlineText.includes('8.12.2026'), r.deadlineText)
  eq(((await createBankRequest(dbWith(okRpc({ reused: true })), { kind: 'booking_change', bookingId: 'b', amount: 5, holdMinutes: 60, lang: 'cs', number: 'AB12', chg: '{}' })) as any).reused, true)
  eq(await createBankRequest(dbWith(() => ({ data: { success: false, error: 'wrong_status' }, error: null })), { kind: 'booking_change', bookingId: 'b', amount: 5, holdMinutes: 60, lang: 'cs', number: 'x' }), { ok: false, code: 'wrong_status' })
  eq(((await createBankRequest(dbWith(), { kind: 'shop_order', orderId: OID, amount: 5, holdMinutes: 60, lang: 'cs', number: 'x' })) as any), { ok: false, code: 'bank_unavailable', detail: 'sql_missing' })
  eq(((await createBankRequest(dbWith(() => { throw new Error('net') }), { kind: 'shop_order', orderId: OID, amount: 5, holdMinutes: 60, lang: 'cs', number: 'x' })) as any).code, 'bank_unavailable')
  eq(await bankRequestsAvailable(dbWith()), true)
  const missing = dbWith(); missing.failSelect = (t) => (t === 'bank_payment_requests' ? { code: '42P01', message: 'relation does not exist' } : null)
  eq(await bankRequestsAvailable(missing), false)
  eq(deadlineText('booking_change', 'en', null), '')
})

Deno.test('e-mail zákazníkovi: šablona s proměnnými v jeho jazyce + příloha ZF; když neodejde, záložní HTML se stejnými údaji', async () => {
  const details = await bankDetails(dbWith(), { vs: '10000777', amount: 1062, message: 'm', expiresAt: '2026-12-08T09:00:00+00:00' })
  const base = { lang: 'en' as const, details, email: 'k@example.com', name: 'Kate', env: ENV }
  const n = net()
  try {
    eq(await sendBankRequestMail({ ...base, kind: 'shop_order', deadline: 'DL', number: 'MG-2026-0042', orderId: OID, invoice: { number: 'ZF-2026-0042', path: 'invoices/zf.pdf' } }), true)
    const m = n.calls[0].body as Row
    eq([m.to, m.template_slug, m.language, m.order_id, m.attachment_paths], ['k@example.com', 'shop_qr_payment', 'en', OID, [{ filename: 'ZF-2026-0042.pdf', path: 'invoices/zf.pdf' }]])
    eq(m.template_vars, { lead: 'Kate, thank you', order_number: 'MG-2026-0042', qr_url: details.qr_url, amount: '1062.00 Kč', account: '2303580494/2010',
      iban: 'CZ83 2010 0000 0023 0358 0494', bank: 'Fio banka', vs: '10000777', deadline: 'DL', invoice_suffix: ' (No. ZF-2026-0042)' })
    n.edge['send-email'] = (b) => (b?.template_slug ? { success: false, error: 'Template not found' } : { success: true })
    eq(await sendBankRequestMail({ ...base, lang: 'cs', kind: 'booking_change', deadline: 'Doplatek prosím uhraďte do 14:35', number: 'AB12CD34', bookingId: 'bk1' }), true)
    const t = n.calls[1].body as Row, f = n.calls[2].body as Row
    eq([t.template_slug, t.booking_id, t.template_vars.booking_number, t.template_vars.lead, t.attachment_paths], ['booking_change_qr_payment', 'bk1', 'AB12CD34', 'Kate, k úpravě vaší rezervace', []])
    eq([f.subject, f.booking_id, 'template_slug' in f], ['Doplatek k rezervaci #AB12CD34 — QR / bankovní převod', 'bk1', false])
    for (const s of ['#AB12CD34', '10000777', '1062.00 Kč', '2303580494/2010', 'CZ83 2010 0000 0023 0358 0494', 'Doplatek prosím uhraďte do 14:35', 'Úpravu provedeme, jakmile platbu připíšeme', 'doplatek vám vrátíme']) ok(String(f.raw_html).includes(s), `záložní mail: chybí „${s}“`)
    eq(await sendBankRequestMail({ ...base, email: '', kind: 'shop_order', deadline: 'x', number: 'n' }), false)
    ok(bankRequestFallbackHtml({ ...base, lang: 'uk', kind: 'shop_order', deadline: 'DL', number: 'MG-1', invoice: { number: 'ZF-1', path: null } }).includes('№ ZF-1'), 'uk fallback s číslem ZF')
  } finally { n.restore() }
})
