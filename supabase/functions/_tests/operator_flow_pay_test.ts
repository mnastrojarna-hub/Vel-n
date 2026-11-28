// ===== _tests/operator_flow_pay_test.ts =====
// Změna provozovatele (2026-11): flow testy celých handlerů qr-payment (účet / IBAN / banka pro QR platbu)
// a send-invoice-email (doklad vyrenderovaný v prohlížeči se nepošle, když nenese vystavitele uloženého
// u dokladu — záložka Velínu otevřená z doby před změnou provozovatele). Stavy nasazení jako
// v operator_flow_test.ts (nová DB / stará DB bez sloupce a bez bank_iban / nastavení chybí).
//   deno test --allow-all --no-check --import-map=supabase/functions/_tests/gear-flow-map.json supabase/functions/_tests/operator_flow_pay_test.ts
// Bez import mapy se přeskočí — spouští je operator_flow_runner_test.ts v podprocesu.
// deno-lint-ignore-file no-explicit-any
import { LooseDb, stubFetch } from './gear-fake.ts'
import { NEW_INFO, OLD_INFO, OLD_SNAPSHOT } from './operator-fixtures.ts'
import { BID, eq, MAPPED, noIssuerColumn, ok, post, type Row, settings, storedInvoice } from './operator-flow-helpers.ts'

// ── qr-payment ───────────────────────────────────────────────────────────────
function qrDb(info?: Row) {
  const db = new LooseDb({
    bookings: [{ id: BID, booking_source: 'web', payment_status: 'unpaid', total_price: 3000, payment_vs: null, pay_channel: null, language: 'cs',
      profiles: { full_name: 'Jana Nováková', email: 'jana@example.com' } }],
    invoices: [], app_settings: settings(info), debug_log: [],
  })
  db.rpcs.set_booking_qr_payment = () => ({ data: { success: true, vs: '2600000123', amount: 3000 }, error: null })
  return db
}
async function qr(info?: Row) {
  const db = qrDb(info)
  const f = stubFetch((url) => new Response(JSON.stringify(url.includes('/generate-invoice') ? { success: false, skipped: true } : { success: true }), { status: 200 }))
  try {
    const r = await post('../qr-payment/index.ts', db, { booking_id: BID, locale: 'cs' })
    const mail = f.calls.find((c) => c.url.endsWith('/send-email') && c.body?.template_slug === 'booking_qr_payment')
    return { ...r, vars: (mail?.body?.template_vars || {}) as Row, calls: f.calls }
  } finally { f.restore() }
}

Deno.test({ name: 'provozovatel · QR platba: nový účet z company_info — ACC:CZ8320100000002303580494, účet 2303580494/2010, Fio banka (odpověď i e-mail)', ignore: !MAPPED, fn: async () => {
  const r = await qr(NEW_INFO)
  eq([r.status, r.json?.success], [200, true], r.txt)
  eq([r.json.account, r.json.iban, r.json.bank, r.json.vs], ['2303580494/2010', 'CZ8320100000002303580494', 'Fio banka', '2600000123'])
  ok(String(r.json.spd).startsWith('SPD*1.0*ACC:CZ8320100000002303580494*AM:3000.00*CC:CZK*X-VS:2600000123'), r.json.spd)
  ok(decodeURIComponent(String(r.json.qr_url)).includes('ACC:CZ8320100000002303580494*'), 'QR obrázek kóduje nový IBAN')
  eq([r.vars.account, r.vars.iban, r.vars.bank], ['2303580494/2010', 'CZ83 2010 0000 0023 0358 0494', 'Fio banka'], 'proměnné e-mailu')
  ok(decodeURIComponent(String(r.vars.qr_url)).includes('ACC:CZ8320100000002303580494*'))
} })

Deno.test({ name: 'provozovatel · QR platba: nastavení chybí → výchozí účet (tentýž nový IBAN)', ignore: !MAPPED, fn: async () => {
  const r = await qr()
  eq([r.json.account, r.json.iban, r.json.bank], ['2303580494/2010', 'CZ8320100000002303580494', 'Fio banka'], r.txt)
  ok(String(r.json.spd).includes('ACC:CZ8320100000002303580494*'))
} })

Deno.test({ name: 'provozovatel · QR platba: NOVÝ KÓD + STARÁ DB (jen bank_account) — QR platí na TENTÝŽ účet, který ukazuje text; nikdy na nový IBAN', ignore: !MAPPED, fn: async () => {
  const r = await qr(OLD_INFO)
  eq([r.status, r.json?.success], [200, true], r.txt)
  eq([r.json.account, r.json.iban, r.json.bank], ['19-2000145399/0800', 'CZ6508000000192000145399', 'kód banky 0800'])
  ok(String(r.json.spd).startsWith('SPD*1.0*ACC:CZ6508000000192000145399*'), r.json.spd)
  ok(!JSON.stringify(r.json).includes('CZ8320100000002303580494') && !JSON.stringify(r.json).includes('Fio'), 'nic z nového účtu')
  // jen číslo nového účtu bez IBAN (ručně upravené nastavení) → IBAN dopočítán, QR i text souhlasí
  const half = await qr({ ...OLD_INFO, bank_account: '2303580494/2010' })
  eq([half.json.account, half.json.iban], ['2303580494/2010', 'CZ8320100000002303580494'])
} })

// ── send-invoice-email (pojistka vystavitele u dokladu vyrenderovaného v prohlížeči) ──────────────
const clientDoc = (name: string, ico: string) => `<!DOCTYPE html><html lang="cs"><body><h1>FAKTURA ZF-2026-0007</h1><p>Dodavatel: ${name}, IČO: ${ico}</p></body></html>`
async function sendInvoice(db: LooseDb, html: string) {
  const f = stubFetch(() => new Response(JSON.stringify({ id: 'em_1' }), { status: 200 }))
  try {
    const r = await post('../send-invoice-email/index.ts', db, { invoice_id: 'inv-1', html_content: html, customer_email: 'jana@example.com', invoice_number: 'ZF-2026-0007', language: 'cs' })
    return { ...r, sent: f.calls.filter((c) => c.url.includes('api.resend.com')).length }
  } finally { f.restore() }
}
const mailDb = (o: { info?: Row; snapshot?: unknown } = {}) => {
  const db = new LooseDb({ invoices: [storedInvoice(o.snapshot === undefined ? {} : { issuer_snapshot: o.snapshot })], app_settings: settings(o.info), sent_emails: [], message_log: [], debug_log: [] })
  noIssuerColumn(db)
  return db
}

Deno.test({ name: 'provozovatel · odeslání faktury z Velínu: náhled s JINÝM dodavatelem, než je uložen u dokladu, se NEPOŠLE (issuer_mismatch)', ignore: !MAPPED, fn: async () => {
  // nový doklad (vystavila společnost) + stará záložka Velínu (dřívější provozovatel v náhledu)
  const a = mailDb({ info: NEW_INFO, snapshot: NEW_INFO })
  const r1 = await sendInvoice(a, clientDoc('Jan Novák', '12345678'))
  eq([r1.status, r1.json?.success, r1.json?.code, r1.sent], [409, false, 'issuer_mismatch', 0], r1.txt)
  ok(String(r1.json.error).includes('obnovte stránku Velínu'), r1.txt)
  eq(a.rows('debug_log').map((d) => d.action), ['issuer_mismatch'])
  eq(a.rows('sent_emails').length, 0)
  // starý doklad + náhled s novým provozovatelem → také ne
  const b = mailDb({ info: NEW_INFO, snapshot: OLD_SNAPSHOT })
  const r2 = await sendInvoice(b, clientDoc('MotoGo24 s.r.o.', '29909864'))
  eq([r2.status, r2.json?.code, r2.sent], [409, 'issuer_mismatch', 0], r2.txt)
} })

Deno.test({ name: 'provozovatel · odeslání faktury z Velínu: náhled se správným dodavatelem odejde (nový doklad, starý doklad, stará DB, doklad nenalezen)', ignore: !MAPPED, fn: async () => {
  const cases: Array<[string, LooseDb, string]> = [
    ['nový doklad + nový náhled', mailDb({ info: NEW_INFO, snapshot: NEW_INFO }), clientDoc('MotoGo24 s.r.o.', '29909864')],
    ['starý doklad + původní dodavatel', mailDb({ info: NEW_INFO, snapshot: OLD_SNAPSHOT }), clientDoc('Jan Novák', '12345678')],
    ['stará DB bez sloupce (aktuální = dosavadní provozovatel)', mailDb({ info: OLD_INFO }), clientDoc('Jan Novák', '12345678')],
    ['bez snapshotu = aktuální provozovatel', mailDb({ info: NEW_INFO, snapshot: null }), clientDoc('MotoGo24 s.r.o.', '29909864')],
  ]
  for (const [label, db, html] of cases) {
    const r = await sendInvoice(db, html)
    eq([r.status, r.json?.success, r.sent], [200, true, 1], `${label}: ${r.txt}`)
    eq(db.rows('sent_emails').map((m) => m.status), ['sent'], label)
  }
  // řádek dokladu nenalezen → bez kontroly (chování jako dosud)
  const none = new LooseDb({ invoices: [], app_settings: settings(NEW_INFO), sent_emails: [], message_log: [], debug_log: [] })
  const r = await sendInvoice(none, clientDoc('Kdokoli', '00000000'))
  eq([r.status, r.json?.success, r.sent], [200, true, 1], r.txt)
} })
