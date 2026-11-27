// ===== _tests/operator_flow_test.ts =====
// Změna provozovatele (2026-11): flow testy CELÝCH handlerů generate-invoice a generate-document
// nad LooseDb (qr-payment a send-invoice-email: operator_flow_pay_test.ts) — ve třech stavech nasazení:
//   • nový kód + nová DB  (company_info = nový provozovatel, staré doklady mají issuer_snapshot),
//   • nový kód + stará DB (company_info = dosavadní provozovatel bez bank_iban / bank_name / register,
//     sloupec invoices.issuer_snapshot neexistuje → jmenovitý výběr by spadl 42703),
//   • nastavení chybí úplně (výchozí provozovatel z kódu).
// Potřebují import mapu (serve zachytí handler, supabase-js = LooseDb):
//   deno test --allow-all --no-check --import-map=supabase/functions/_tests/gear-flow-map.json supabase/functions/_tests/operator_flow_test.ts
// Bez ní (běžné `deno test _tests/`) se přeskočí — spouští je operator_flow_runner_test.ts v podprocesu.
// deno-lint-ignore-file no-explicit-any
import { LooseDb } from './gear-fake.ts'
import { NEW_INFO, OLD_INFO, OLD_SNAPSHOT } from './operator-fixtures.ts'
import { BID, eq, fileText, has, hasNot, MAPPED, NEW_MARKS, noIssuerColumn, ok, OLD_MARKS, post, type Row, settings, storedInvoice } from './operator-flow-helpers.ts'

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
