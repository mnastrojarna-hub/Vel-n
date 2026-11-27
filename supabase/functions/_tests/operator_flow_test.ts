// ===== _tests/operator_flow_test.ts =====
// Změna provozovatele (2026-11): flow testy CELÝCH handlerů generate-invoice, generate-document a
// qr-payment nad LooseDb — ve třech stavech nasazení:
//   • nový kód + nová DB  (company_info = nový provozovatel, staré doklady mají issuer_snapshot),
//   • nový kód + stará DB (company_info = dosavadní provozovatel bez bank_iban / bank_name / register,
//     sloupec invoices.issuer_snapshot neexistuje → jmenovitý výběr by spadl 42703),
//   • nastavení chybí úplně (výchozí provozovatel z kódu).
// Potřebují import mapu (serve zachytí handler, supabase-js = LooseDb):
//   deno test --allow-all --no-check --import-map=supabase/functions/_tests/gear-flow-map.json supabase/functions/_tests/operator_flow_test.ts
// Bez ní (běžné `deno test _tests/`) se přeskočí — spouští je operator_flow_runner_test.ts v podprocesu.
// + send-invoice-email: doklad vyrenderovaný v prohlížeči (Velín) se nepošle, když nenese vystavitele
//   uloženého u dokladu (záložka Velínu otevřená z doby před změnou provozovatele).
// deno-lint-ignore-file no-explicit-any
import { LooseDb, stubFetch } from './gear-fake.ts'
import { NEW_INFO, OLD_INFO, OLD_SNAPSHOT } from './operator-fixtures.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }
type Row = Record<string, any>
type Handler = (req: Request) => Response | Promise<Response>

const MAPPED = (() => { try { return import.meta.resolve('https://esm.sh/@supabase/supabase-js@2').endsWith('gear-flow-stubs.ts') } catch { return false } })()
const SVC = 'svc-test-key'
if (MAPPED) {
  Deno.env.set('SUPABASE_URL', 'https://fake.supabase.test')
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SVC)
  Deno.env.delete('PDFSHIFT_API_KEY') // doklady se ukládají jako HTML (čitelné v testu)
  Deno.env.set('RESEND_API_KEY', 're_test') // send-invoice-email (odeslání zachytí stubFetch)
}
const g = globalThis as unknown as { __gearHandlers?: Handler[]; __gearFakeDb?: unknown }
const handlers: Record<string, Handler> = {}
async function handlerOf(path: string): Promise<Handler> {
  if (handlers[path]) return handlers[path]
  const before = (g.__gearHandlers || []).length
  await import(path)
  const h = (g.__gearHandlers || [])[before]
  if (!h) throw new Error(`handler ${path} se nezaregistroval`)
  return (handlers[path] = h)
}
async function post(path: string, db: LooseDb, body: Row) {
  g.__gearFakeDb = db
  const h = await handlerOf(path)
  const res = await h(new Request('http://x/fn', { method: 'POST', headers: { Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }))
  const txt = await res.text()
  let json: any = null
  try { json = JSON.parse(txt) } catch { /* text */ }
  return { status: res.status, json, txt }
}
const fileText = async (db: LooseDb, path: string) => { const b = db.files[path]; if (!b) throw new Error(`soubor ${path} není ve storage: ${Object.keys(db.files)}`); return await (b as Blob).text() }

const BID = '11111111-2222-3333-4444-555566667777'
const settings = (v?: Row) => (v ? [{ key: 'company_info', value: v }] : [])
/** jmenovitý výběr neexistujícího sloupce = chyba PostgREST 42703 (stará DB) */
const noIssuerColumn = (db: LooseDb) => {
  db.failSelect = (t, cols) => t === 'invoices' && cols.includes('issuer_snapshot') ? { code: '42703', message: 'column invoices.issuer_snapshot does not exist' } : null
}
const NEW_MARKS = ['MotoGo24 s.r.o.', '29909864', 'Mezná 9, 393 01 Mezná', '2303580494/2010', 'Fio banka', 'oddíl C, vložka 36876', 'Nejsme plátci DPH.']
const OLD_MARKS = ['Jan Novák', '12345678', 'Dlouhá 1, 110 00 Praha', '19-2000145399/0800']
const has = (h: string, marks: string[], label: string) => { for (const m of marks) ok(h.includes(m), `${label}: chybí „${m}“`) }
const hasNot = (h: string, marks: string[], label: string) => { for (const m of marks) ok(!h.includes(m), `${label}: nesmí obsahovat „${m}“`) }

// ── generate-invoice ─────────────────────────────────────────────────────────
function invoiceDb(o: { info?: Row; invoices?: Row[] } = {}) {
  const db = new LooseDb({
    bookings: [{ id: BID, booking_kind: 'moto', user_id: 'u1', moto_id: 'm1', total_price: 3000, discount_amount: 0, delivery_fee: 0,
      start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', stripe_payment_intent_id: null, // převod → bankovní blok
      motorcycles: { model: 'BMW R 1250 GS', spz: '1AB 2345', price_mon: 1000, price_tue: 1000, price_wed: 1000, price_thu: 1000, price_fri: 1000, price_sat: 1000, price_sun: 1000 },
      profiles: { id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' } }],
    booking_extras: [], booking_discounts: [], invoices: o.invoices || [], payment_methods: [], app_settings: settings(o.info), debug_log: [],
  })
  db.rpcs.next_document_number = () => ({ data: 'ZF-2026-0042', error: null })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  return db
}
const storedInvoice = (o: Row = {}): Row => ({ id: 'inv-1', number: 'ZF-2026-0007', type: 'proforma', booking_id: BID, source: 'booking', status: 'issued',
  customer_id: 'u1', items: [{ description: 'Pronájem BMW R 1250 GS — 10. 11. 2026 – 12. 11. 2026', qty: 2, unit_price: 1500 }], subtotal: 3000, total: 3000,
  issue_date: '2026-10-01', due_date: '2026-10-01', created_at: '2026-10-01T08:00:00+00:00', paid_date: null, pdf_path: null, variable_symbol: '20260007', customer_snapshot: null, ...o })

Deno.test({ name: 'provozovatel · faktura: NOVÝ doklad nese nového provozovatele z company_info (sídlo, zápis, účet Fio, banka)', ignore: !MAPPED, fn: async () => {
  const db = invoiceDb({ info: NEW_INFO })
  const r = await post('../generate-invoice/index.ts', db, { type: 'proforma', booking_id: BID, send_email: false })
  eq([r.status, r.json?.success, r.json?.number], [200, true, 'ZF-2026-0042'], r.txt)
  const h = await fileText(db, r.json.pdf_path)
  has(h, NEW_MARKS, 'nová ZF'); has(h, ['CZ83 2010 0000 0023 0358 0494', '>Sídlo</td>'], 'nová ZF'); hasNot(h, OLD_MARKS, 'nová ZF')
} })

Deno.test({ name: 'provozovatel · faktura: starý doklad se snapshotem — samoléčba chybějícího souboru i „Přegenerovat“ drží PŮVODNÍHO vystavitele', ignore: !MAPPED, fn: async () => {
  for (const regenerate of [false, true]) {
    const db = invoiceDb({ info: NEW_INFO, invoices: [storedInvoice({ issuer_snapshot: OLD_SNAPSHOT })] })
    noIssuerColumn(db) // i s existujícím sloupcem smí kód číst jen select('*')
    const r = await post('../generate-invoice/index.ts', db, { type: 'proforma', booking_id: BID, send_email: false, regenerate })
    eq([r.status, r.json?.success, r.json?.number], [200, true, 'ZF-2026-0007'], `regenerate=${regenerate}: ${r.txt}`)
    eq(db.rows('invoices').length, 1, 'žádný nový řádek')
    const h = await fileText(db, r.json.pdf_path)
    has(h, [...OLD_MARKS, 'Stará banka', '>Adresa</td><td style="color:#0f1a14;font-weight:700">Dlouhá 1'], `regenerate=${regenerate}`)
    hasNot(h, [...NEW_MARKS, 'CZ83 2010', '>IBAN</span>'], `regenerate=${regenerate}`)
    eq(db.rows('invoices')[0].issuer_snapshot, OLD_SNAPSHOT, 'snapshot se přegenerováním nemění')
    ok(!db.callsOf('update', 'invoices').some((c) => 'issuer_snapshot' in (c.data as Row)), 'kód do issuer_snapshot nikdy nezapisuje')
  }
} })

Deno.test({ name: 'provozovatel · faktura: dorenderování KF bez PDF (render_existing) — se snapshotem původní, bez snapshotu aktuální', ignore: !MAPPED, fn: async () => {
  const kf = (o: Row) => storedInvoice({ id: 'kf-1', number: 'KF-2026-0003', type: 'final', ...o })
  const old = invoiceDb({ info: NEW_INFO, invoices: [kf({ issuer_snapshot: OLD_SNAPSHOT })] })
  noIssuerColumn(old)
  const r1 = await post('../generate-invoice/index.ts', old, { render_existing: true, booking_id: BID, type: 'final' })
  eq([r1.status, r1.json?.success, r1.json?.number], [200, true, 'KF-2026-0003'], r1.txt)
  const h1 = await fileText(old, r1.json.pdf_path)
  has(h1, OLD_MARKS.slice(0, 3), 'KF starého vystavitele'); hasNot(h1, ['MotoGo24 s.r.o.', '29909864', 'vložka 36876'], 'KF starého vystavitele')

  const cur = invoiceDb({ info: NEW_INFO, invoices: [kf({ issuer_snapshot: null })] })
  const r2 = await post('../generate-invoice/index.ts', cur, { render_existing: true, booking_id: BID, type: 'final' })
  const h2 = await fileText(cur, r2.json.pdf_path)
  has(h2, ['MotoGo24 s.r.o.', '29909864', 'vložka 36876', 'Nejsme plátci DPH.'], 'KF bez snapshotu'); hasNot(h2, OLD_MARKS, 'KF bez snapshotu')
} })

Deno.test({ name: 'provozovatel · faktura: NOVÝ KÓD + STARÁ DB (sloupec issuer_snapshot chybí, company_info starý) — nespadne, doklad = dosavadní provozovatel', ignore: !MAPPED, fn: async () => {
  // nový doklad
  const a = invoiceDb({ info: OLD_INFO }); noIssuerColumn(a)
  const r1 = await post('../generate-invoice/index.ts', a, { type: 'proforma', booking_id: BID, send_email: false })
  eq([r1.status, r1.json?.success], [200, true], r1.txt)
  const h1 = await fileText(a, r1.json.pdf_path)
  has(h1, OLD_MARKS, 'stará DB, nová ZF')
  hasNot(h1, [...NEW_MARKS, '>Banka</span>', '>IBAN</span>', '>Zápis</td>', 'CZ8320100000002303580494'], 'stará DB, nová ZF')
  // existující řádek bez sloupce: přegenerování i render_existing
  const b = invoiceDb({ info: OLD_INFO, invoices: [storedInvoice()] }); noIssuerColumn(b)
  const r2 = await post('../generate-invoice/index.ts', b, { type: 'proforma', booking_id: BID, send_email: false, regenerate: true })
  eq([r2.status, r2.json?.success, r2.json?.number], [200, true, 'ZF-2026-0007'], r2.txt)
  has(await fileText(b, r2.json.pdf_path), OLD_MARKS, 'stará DB, přegenerování')
  const c = invoiceDb({ info: OLD_INFO, invoices: [storedInvoice({ id: 'kf-1', number: 'KF-2026-0003', type: 'final' })] }); noIssuerColumn(c)
  const r3 = await post('../generate-invoice/index.ts', c, { render_existing: true, booking_id: BID, type: 'final' })
  eq([r3.status, r3.json?.success], [200, true], r3.txt)
  has(await fileText(c, r3.json.pdf_path), OLD_MARKS.slice(0, 3), 'stará DB, render_existing')
} })

Deno.test({ name: 'provozovatel · faktura: nastavení company_info chybí / dotaz selže → výchozí (nový) provozovatel', ignore: !MAPPED, fn: async () => {
  const a = invoiceDb()
  const r1 = await post('../generate-invoice/index.ts', a, { type: 'proforma', booking_id: BID, send_email: false })
  has(await fileText(a, r1.json.pdf_path), NEW_MARKS, 'bez nastavení')
  // dotaz na nastavení selže → výchozí provozovatel, i když předchozí požadavek načetl jiného
  await post('../generate-invoice/index.ts', invoiceDb({ info: OLD_INFO }), { type: 'proforma', booking_id: BID, send_email: false })
  const b = invoiceDb({ info: OLD_INFO })
  b.failSelect = (t) => t === 'app_settings' ? { code: '57014', message: 'timeout' } : null
  const r2 = await post('../generate-invoice/index.ts', b, { type: 'proforma', booking_id: BID, send_email: false })
  eq([r2.status, r2.json?.success], [200, true], r2.txt)
  const h2 = await fileText(b, r2.json.pdf_path)
  has(h2, NEW_MARKS, 'chyba dotazu'); hasNot(h2, OLD_MARKS, 'chyba dotazu')
} })

// ── generate-document ────────────────────────────────────────────────────────
const TPL = '<p id="party">{{company_name}} | {{company_address}} | IČO: {{company_ico}} | {{company_register}} | Bankovní spojení: {{company_account}} ({{company_bank}}), IBAN {{company_iban}} | {{company_phone}} | {{company_email}}</p><p>Nájemce {{customer_name}}</p>'
function docDb(o: { info?: Row; docs?: Row[] } = {}) {
  const db = new LooseDb({
    bookings: [{ id: BID, booking_kind: 'moto', user_id: 'u1', moto_id: 'm1', branch_id: null, total_price: 3000, extras_price: 0, delivery_fee: 0, discount_amount: 0,
      start_date: '2026-11-10T00:00:00+00:00', end_date: '2026-11-12T00:00:00+00:00', pickup_time: '10:00', pickup_method: 'branch',
      motorcycles: { model: 'BMW R 1250 GS', spz: '1AB 2345', vin: 'VIN123' } }],
    profiles: [{ id: 'u1', full_name: 'Jana Nováková', email: 'jana@example.com' }], motorcycles: [{ id: 'm1', branch_id: null }], branches: [],
    booking_extras: [], documents: [], admin_audit_log: [], debug_log: [], app_settings: settings(o.info),
    document_templates: [{ id: 'tpl-contract', type: 'rental_contract', name: 'Smlouva o pronájmu motocyklu', active: true, version: 12, content_html: TPL, content_translations: {}, translation_src: {} }],
    generated_documents: o.docs || [],
  })
  db.rpcs.detect_customer_language = () => ({ data: 'cs', error: null })
  for (const d of o.docs || []) if (d.pdf_path) db.files[d.pdf_path] = new Blob([`<p>${d.id}</p>`])
  return db
}
const oldDoc = (id: string, at: string, fd: Row): Row => ({ id, template_id: 'tpl-contract', booking_id: BID, customer_id: 'u1', pdf_path: `generated/${id}.html`, created_at: at, filled_data: fd })

Deno.test({ name: 'provozovatel · dokument: smlouva nese nového provozovatele; verze z doby PŘED změnou se NEMAŽE (řádek i soubor), novější ano', ignore: !MAPPED, fn: async () => {
  const db = docDb({ info: NEW_INFO, docs: [
    oldDoc('g-before', '2026-10-01T09:00:00+00:00', { company_name: 'Jan Novák', company_ico: '12345678' }), // dřívější provozovatel
    oldDoc('g-signed', '2026-11-28T09:00:00+00:00', { company_name: 'Jan Novák, MotoGo24', _signed_html: '<p>podepsáno</p>' }), // bez IČO, jiný název
    oldDoc('g-same-before', '2026-11-29T09:59:00+00:00', { company_name: 'MotoGo24 s.r.o.', company_ico: '29909864' }), // před valid_from
    oldDoc('g-after', '2026-11-30T09:00:00+00:00', { company_name: 'MotoGo24 s.r.o.', company_ico: '29909864' }), // současný provozovatel → nahradit
  ] })
  const r = await post('../generate-document/index.ts', db, { template_slug: 'rental_contract', booking_id: BID, language: 'cs' })
  eq([r.status, r.json?.success], [200, true], r.txt)
  const h = await fileText(db, r.json.path)
  ok(h.includes('MotoGo24 s.r.o. | Mezná 9, 393 01 Mezná | IČO: 29909864 | zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876 | '
    + 'Bankovní spojení: 2303580494/2010 (Fio banka), IBAN CZ83 2010 0000 0023 0358 0494 | +420 774 256 271 | info@motogo24.cz'), h)
  const ids = db.rows('generated_documents').map((d) => d.id).sort()
  eq(ids, ['g-before', 'g-same-before', 'g-signed', r.json.document_id].sort(), 'zůstaly všechny verze před změnou + nová')
  for (const keep of ['generated/g-before.html', 'generated/g-signed.html', 'generated/g-same-before.html']) ok(db.files[keep], `soubor ${keep} musí zůstat`)
  ok(!db.files['generated/g-after.html'], 'novější verze téhož provozovatele je nahrazena')
  eq(db.callsOf('remove').map((c) => c.data), [['generated/g-after.html']], 'ze storage se maže jen nahrazená verze')
  const fd = db.rows('generated_documents').find((d) => d.id === r.json.document_id)!.filled_data
  eq([fd.company_name, fd.company_ico, fd.company_account, fd.company_bank], ['MotoGo24 s.r.o.', '29909864', '2303580494/2010', 'Fio banka'])
  eq(db.rows('generated_documents').find((d) => d.id === 'g-before')!.filled_data, { company_name: 'Jan Novák', company_ico: '12345678' }, 'stará verze beze změny')
} })

Deno.test({ name: 'provozovatel · dokument: NOVÝ KÓD + STARÁ DB (bez valid_from, týž provozovatel) — přemazání verzí jako dosud, proměnné ze starého nastavení', ignore: !MAPPED, fn: async () => {
  const db = docDb({ info: OLD_INFO, docs: [oldDoc('g-prev', '2026-10-01T09:00:00+00:00', { company_name: 'Jan Novák', company_ico: '12345678' })] })
  const r = await post('../generate-document/index.ts', db, { template_slug: 'rental_contract', booking_id: BID, language: 'cs' })
  eq([r.status, r.json?.success], [200, true], r.txt)
  const h = await fileText(db, r.json.path)
  ok(h.includes('Jan Novák | Dlouhá 1, 110 00 Praha | IČO: 12345678 |  | Bankovní spojení: 19-2000145399/0800 (kód banky 0800), IBAN CZ65 0800 0000 1920 0014 5399'), h)
  ok(!h.includes('MotoGo24 s.r.o.') && !h.includes('2303580494') && !h.includes('Fio banka') && !h.includes('36876'), 'nic z nového provozovatele')
  eq(db.rows('generated_documents').map((d) => d.id), [r.json.document_id], 'předchozí verze nahrazena (chování před změnou)')
  ok(!db.files['generated/g-prev.html'])
} })

Deno.test({ name: 'provozovatel · dokument: nastavení chybí → výchozí provozovatel; cizí starší verze se i tak nemaže', ignore: !MAPPED, fn: async () => {
  const db = docDb({ docs: [oldDoc('g-before', '2026-10-01T09:00:00+00:00', { company_name: 'Jan Novák', company_ico: '12345678' })] })
  const r = await post('../generate-document/index.ts', db, { template_slug: 'rental_contract', booking_id: BID, language: 'cs' })
  eq([r.status, r.json?.success], [200, true], r.txt)
  ok((await fileText(db, r.json.path)).includes('MotoGo24 s.r.o. | Mezná 9, 393 01 Mezná | IČO: 29909864'))
  ok(db.rows('generated_documents').some((d) => d.id === 'g-before') && db.files['generated/g-before.html'], 'verze jiného provozovatele zůstává')
} })

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
