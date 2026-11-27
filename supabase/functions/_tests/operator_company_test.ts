// ===== _tests/operator_company_test.ts =====
// Změna provozovatele (2026-11): _shared/company.ts — výchozí provozovatel, čtení
// app_settings.company_info (plné / částečné / chybějící), vystavitel dokladu ze snapshotu (issuerOf),
// blok DODAVATEL a banka na faktuře, hlavička dobropisu, QR platba (IBAN) a zamražené verze dokumentů.
// „Dřívější provozovatel“ je v testech smyšlený (Jan Novák, účet = vzorový účet ČNB).
// Bez import mapy: deno test --allow-all --no-check supabase/functions/_tests/operator_company_test.ts
// deno-lint-ignore-file no-explicit-any
import {
  bankLabel, COMPANY_DEFAULT, companyDocVars, companyFooterLine, companyFromInfo, companyIdLine, companyNow, czIban,
  emailFooterCompanyHtml, fmtIban, invoiceIssuer, issuerOf, loadCompany, parseRegister, registerInvoiceLine, registerLine,
} from '../_shared/company.ts'
import { generateInvoiceHtml } from '../generate-invoice/template.ts'
import { creditNoteIssuer, creditNoteIssuerHtml } from '../process-refund/credit-note-issuer.ts'
import { buildSpd, qrBankDetails } from '../qr-payment/spd.ts'
import { isFrozenVersion, splitOldVersions } from '../generate-document/versions.ts'
import { LooseDb } from './gear-fake.ts'
import { NEW_INFO, OLD_INFO, OLD_SNAPSHOT } from './operator-fixtures.ts'

function eq(a: unknown, b: unknown, msg = '') {
  const A = JSON.stringify(a), B = JSON.stringify(b)
  if (A !== B) throw new Error(`${msg} expected ${B}, got ${A}`)
}
function ok(c: unknown, msg = '') { if (!c) throw new Error(`assert failed ${msg}`) }

const settingsDb = (value?: unknown) => new LooseDb({ app_settings: value === undefined ? [] : [{ key: 'company_info', value }], invoices: [] })

Deno.test('výchozí provozovatel = MotoGo24 s.r.o. (IČO, sídlo, rejstřík, účet Fio, IBAN, datová schránka)', () => {
  const d = COMPANY_DEFAULT
  eq([d.name, d.ico, d.address, d.dic, d.vatPayer], ['MotoGo24 s.r.o.', '29909864', 'Mezná 9, 393 01 Mezná', null, false])
  eq(d.register, 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876')
  eq(d.registerShort, 'C 36876 vedená u Krajského soudu v Českých Budějovicích')
  eq([d.account, d.iban, d.bank, d.bic, d.dataBox], ['2303580494/2010', 'CZ8320100000002303580494', 'Fio banka', 'FIOBCZPPXXX', '2xfihrd'])
  eq([d.phone, d.email], ['+420 774 256 271', 'info@motogo24.cz'], 'kontakty beze změny')
  eq(czIban(d.account), d.iban, 'IBAN odpovídá číslu účtu')
  eq(parseRegister(d.register), { court: d.registerCourt, file: d.registerFile })
  eq(registerLine(d), 'C 36876, Krajský soud v Českých Budějovicích')
  eq(registerInvoiceLine(d), 'obchodní rejstřík, Krajský soud v Českých Budějovicích, oddíl C, vložka 36876')
  eq(companyFooterLine(d), 'MotoGo24 s.r.o. · IČO: 29909864 · Mezná 9, 393 01 Mezná · C 36876 vedená u Krajského soudu v Českých Budějovicích')
  eq(companyIdLine(d), 'MotoGo24 s.r.o., IČO: 29909864')
})

Deno.test('czIban / fmtIban: předčíslí, doplnění nul, nečitelný vstup', () => {
  eq(czIban('2303580494/2010'), 'CZ8320100000002303580494')
  eq(czIban('19-2000145399/0800'), 'CZ6508000000192000145399', 'vzorový účet ČNB')
  eq(czIban(' 19 - 2000145399 / 0800 '), 'CZ6508000000192000145399')
  eq([czIban(''), czIban('abc'), czIban('123/20')], ['', '', ''])
  eq(fmtIban('CZ8320100000002303580494'), 'CZ83 2010 0000 0023 0358 0494')
})

Deno.test('companyFromInfo: plné nastavení nového provozovatele', () => {
  const c = companyFromInfo(NEW_INFO)!
  eq([c.name, c.ico, c.address, c.account, c.iban, c.bank, c.dataBox], ['MotoGo24 s.r.o.', '29909864', 'Mezná 9, 393 01 Mezná', '2303580494/2010', 'CZ8320100000002303580494', 'Fio banka', '2xfihrd'])
  eq([c.registerCourt, c.registerFile, c.validFrom], ['Krajský soud v Českých Budějovicích', 'C 36876', '2026-11-29T10:00:00.000000+00:00'])
  eq(companyFromInfo(JSON.stringify(NEW_INFO))!.ico, '29909864', 'jsonb doručené jako text')
})

Deno.test('companyFromInfo: částečné nastavení TÉHOŽ subjektu doplní výchozí (rejstřík, účet, IBAN, banka)', () => {
  const c = companyFromInfo({ name: 'MotoGo24 s.r.o.', ico: '29909864' })!
  eq([c.address, c.register, c.registerShort, c.account, c.iban, c.bank], [COMPANY_DEFAULT.address, COMPANY_DEFAULT.register, COMPANY_DEFAULT.registerShort, '2303580494/2010', 'CZ8320100000002303580494', 'Fio banka'])
  const spaced = companyFromInfo({ ...NEW_INFO, bank_iban: 'cz83 2010 0000 0023 0358 0494' })!
  eq(spaced.iban, 'CZ8320100000002303580494', 'IBAN s mezerami / malými písmeny')
})

Deno.test('companyFromInfo: JINÝ subjekt (stará DB / snapshot) nikdy nedostane cizí rejstřík, IBAN ani banku', () => {
  const c = companyFromInfo(OLD_INFO)!
  eq([c.name, c.ico, c.address], ['Jan Novák', '12345678', 'Dlouhá 1, 110 00 Praha'])
  eq([c.register, c.registerShort, c.registerCourt, c.registerFile, c.dataBox], ['', '', '', '', ''])
  eq([c.account, c.iban, c.bank], ['19-2000145399/0800', 'CZ6508000000192000145399', ''], 'IBAN dopočítán z účtu, banka neznámá')
  eq(bankLabel(c), 'kód banky 0800')
  eq(registerLine(c), ''); eq(registerInvoiceLine(c), '')
  eq(companyFromInfo(OLD_SNAPSHOT)!.bank, 'Stará banka', 'název banky ze snapshotu')
  eq([companyFromInfo(null), companyFromInfo({}), companyFromInfo({ ico: '1' }), companyFromInfo('x'), companyFromInfo([NEW_INFO])], [null, null, null, null, null])
})

Deno.test('loadCompany: plné / staré / chybějící nastavení a chyba dotazu (nikdy nevyhodí)', async () => {
  eq((await loadCompany(settingsDb(NEW_INFO))).ico, '29909864')
  eq(companyNow().name, 'MotoGo24 s.r.o.')
  const old = await loadCompany(settingsDb(OLD_INFO))
  eq([old.name, old.iban, old.register], ['Jan Novák', 'CZ6508000000192000145399', ''], 'nový kód + stará DB = dosavadní provozovatel')
  eq(companyNow().name, 'Jan Novák', 'synchronní pohled = naposledy načtené')
  eq((await loadCompany(settingsDb(NEW_INFO))).name, 'MotoGo24 s.r.o.')
  // chybějící řádek / řádek bez názvu / chyba / výjimka → naposledy načtená hodnota (zde nový provozovatel)
  eq((await loadCompany(settingsDb())).ico, '29909864')
  eq((await loadCompany(settingsDb({ bank_account: '1/0100' }))).ico, '29909864')
  const failing = settingsDb(OLD_INFO); failing.failSelect = () => ({ code: '57014', message: 'timeout' })
  eq((await loadCompany(failing)).ico, '29909864')
  eq((await loadCompany({ from() { throw new Error('boom') } })).ico, '29909864')
})

Deno.test('issuerOf: snapshot řádku má přednost; bez snapshotu / bez sloupce = aktuální provozovatel', () => {
  const cur = companyFromInfo(NEW_INFO)!
  eq(issuerOf({ id: 'a', issuer_snapshot: OLD_SNAPSHOT }, cur).name, 'Jan Novák')
  eq(issuerOf({ id: 'a', issuer_snapshot: JSON.stringify(OLD_SNAPSHOT) }, cur).ico, '12345678')
  eq(issuerOf({ id: 'a', issuer_snapshot: null }, cur).name, 'MotoGo24 s.r.o.', 'NULL')
  eq(issuerOf({ id: 'a' }, cur).name, 'MotoGo24 s.r.o.', 'sloupec ještě neexistuje')
  eq(issuerOf({ id: 'a', issuer_snapshot: {} }, cur).name, 'MotoGo24 s.r.o.', 'prázdný snapshot')
  eq([issuerOf(null, cur).ico, issuerOf(undefined, cur).ico, issuerOf([{ id: 1 }], cur).ico], ['29909864', '29909864', '29909864'])
})

const inv = (company: any, o: Record<string, unknown> = {}) => generateInvoiceHtml({
  title: 'ZÁLOHOVÁ FAKTURA', number: 'ZF-2026-0001', accent: '#2563eb', issueDate: '2026-11-29', dueDate: '2026-11-29', total: 3000,
  company, customer: { full_name: 'Jana Nováková', email: 'jana@example.com' }, items: [{ description: 'Pronájem — test', qty: 1, unit_price: 3000 }],
  isProforma: true, isPaymentReceipt: false, isShopFinal: false, variableSymbol: '20260001', ...o,
} as any)

Deno.test('faktura: nový provozovatel — Sídlo, Zápis, „Nejsme plátci DPH.“, účet Fio + banka + IBAN', () => {
  const h = inv(companyFromInfo(NEW_INFO))
  for (const s of ['>Název</td>', 'MotoGo24 s.r.o.', '>Sídlo</td>', 'Mezná 9, 393 01 Mezná', '29909864', '>Zápis</td>',
    'obchodní rejstřík, Krajský soud v Českých Budějovicích, oddíl C, vložka 36876', 'Nejsme plátci DPH.',
    '2303580494/2010', '>Banka</span>', 'Fio banka', '>IBAN</span>', 'CZ83 2010 0000 0023 0358 0494',
    '<div style="color:#9ca3af">C 36876, Krajský soud v Českých Budějovicích</div>']) ok(h.includes(s), `chybí: ${s}`)
  ok(!h.includes('>Adresa</td><td style="color:#0f1a14;font-weight:700">Mezná 9, 393 01 Mezná'), 'dodavatel má „Sídlo“, ne „Adresa“')
  ok(!/DIČ/.test(h.split('ODBĚRATEL')[0]), 'neplátce: žádné DIČ dodavatele')
})

Deno.test('faktura: doklad dřívějšího provozovatele (snapshot) vypadá jako při vystavení — bez zápisu, bez věty o DPH, bez IBAN', () => {
  const h = inv(issuerOf({ issuer_snapshot: OLD_SNAPSHOT }, companyFromInfo(NEW_INFO)!))
  for (const s of ['Jan Novák', 'Dlouhá 1, 110 00 Praha', '12345678', '19-2000145399/0800', 'Stará banka']) ok(h.includes(s), `chybí: ${s}`)
  ok(h.includes('>Adresa</td><td style="color:#0f1a14;font-weight:700">Dlouhá 1, 110 00 Praha'), 'původní popisek „Adresa“')
  for (const s of ['MotoGo24 s.r.o.', '29909864', '2303580494', 'Fio banka', '>Zápis</td>', 'Nejsme plátci DPH.', '>IBAN</span>', '>Sídlo</td><td style="color:#0f1a14;font-weight:700">Dlouhá', 'C 36876']) ok(!h.includes(s), `nesmí být: ${s}`)
})

Deno.test('faktura: neznámá banka = bez řádku „Banka“ (nikdy cizí název); platba kartou = bez bankovního bloku', () => {
  const old = inv(companyFromInfo(OLD_INFO))
  ok(old.includes('19-2000145399/0800') && !old.includes('>Banka</span>') && !old.includes('Fio banka'))
  const card = inv(companyFromInfo(NEW_INFO), { cardInfo: { brand: 'card', last4: '' }, stripePaymentIntentId: 'pi_1', isProforma: false, isPaymentReceipt: true })
  ok(card.includes('MotoGo24 s.r.o.') && card.includes('pi_1') && !card.includes('2303580494/2010') && !card.includes('>IBAN</span>'))
})

Deno.test('patička e-mailu a patička dokumentu z provozovatele (nic natvrdo)', () => {
  const n = emailFooterCompanyHtml(companyFromInfo(NEW_INFO)!)
  eq(n.replace(/\s*\n\s*/g, ''), '<div style="font-size:14px;font-weight:800;color:#ffffff;margin-bottom:6px">MotoGo24 s.r.o.</div>'
    + '<div style="color:#9ca3af">Mezná 9, 393 01 Mezná</div><div style="color:#9ca3af">IČO: 29909864</div>'
    + '<div style="color:#9ca3af">C 36876, Krajský soud v Českých Budějovicích</div>')
  const o = emailFooterCompanyHtml(companyFromInfo(OLD_INFO)!)
  ok(o.includes('Jan Novák') && o.includes('IČO: 12345678') && !o.includes('36876') && (o.match(/<div/g) || []).length === 3, 'bez zápisu jen 3 řádky')
  ok(emailFooterCompanyHtml(companyFromInfo({ name: 'A & <B>', ico: '1' })!).includes('A &amp; &lt;B&gt;'), 'HTML escapováno')
  eq(companyIdLine(companyFromInfo(NEW_INFO)!, true), 'MotoGo24 s.r.o., IČO: 29909864, Mezná 9, 393 01 Mezná')
})

Deno.test('proměnné dokumentů {{company_*}}: z nastavení vč. zápisu, účtu, banky a IBAN', () => {
  eq(companyDocVars(companyFromInfo(NEW_INFO)!), {
    company_name: 'MotoGo24 s.r.o.', company_address: 'Mezná 9, 393 01 Mezná', company_ico: '29909864', company_dic: '',
    company_register: 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
    company_register_short: 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
    company_phone: '+420 774 256 271', company_email: 'info@motogo24.cz',
    company_bank: 'Fio banka', company_account: '2303580494/2010', company_iban: 'CZ83 2010 0000 0023 0358 0494', company_bic: 'FIOBCZPPXXX',
  })
  const o = companyDocVars(companyFromInfo(OLD_INFO)!)
  eq([o.company_name, o.company_register, o.company_bank, o.company_account, o.company_iban], ['Jan Novák', '', 'kód banky 0800', '19-2000145399/0800', 'CZ65 0800 0000 1920 0014 5399'])
})

Deno.test('QR platba: ACC = nový IBAN z nastavení; bez nastavení výchozí; IBAN vždy z TÉHOŽ účtu jako text', () => {
  const n = qrBankDetails(companyFromInfo(NEW_INFO)!)
  eq(n, { iban: 'CZ8320100000002303580494', account: '2303580494/2010', bank: 'Fio banka' })
  const spd = buildSpd(n.iban, 3000, '1234567890', 'MotoGo24 rezervace ABCD1234')
  eq(spd, 'SPD*1.0*ACC:CZ8320100000002303580494*AM:3000.00*CC:CZK*X-VS:1234567890*MSG:MotoGo24 rezervace ABCD1234')
  // chybějící nastavení → výchozí provozovatel
  eq(qrBankDetails(COMPANY_DEFAULT), n)
  ok(buildSpd(qrBankDetails(COMPANY_DEFAULT).iban, 1, '1', '').startsWith('SPD*1.0*ACC:CZ8320100000002303580494*AM:1.00*CC:CZK*X-VS:1'))
  // stará DB (účet bez bank_iban / bank_name): QR míří na TENTÝŽ účet, který se vypíše — nikdy na výchozí IBAN
  const o = qrBankDetails(companyFromInfo(OLD_INFO)!)
  eq(o, { iban: 'CZ6508000000192000145399', account: '19-2000145399/0800', bank: 'kód banky 0800' })
  // jen číslo účtu nového provozovatele (bez IBAN a banky) → dopočítaný IBAN = nový
  eq(qrBankDetails(companyFromInfo({ name: 'X', ico: '1', bank_account: '2303580494/2010' })!), n)
  // rozbité nastavení bez účtu → celé trio výchozího provozovatele
  eq(qrBankDetails(companyFromInfo({ name: 'X', ico: '1' })!), n)
})

Deno.test('dobropis: vystavitel = snapshot dobropisu → snapshot původního dokladu → aktuální provozovatel', async () => {
  const db = settingsDb(NEW_INFO)
  db.rows('invoices').push(
    { id: 'old-dp', type: 'payment_receipt', issuer_snapshot: OLD_SNAPSHOT },
    { id: 'new-dp', type: 'payment_receipt', issuer_snapshot: NEW_INFO },
    { id: 'cn-stamped', type: 'credit_note', original_invoice_id: 'new-dp', issuer_snapshot: OLD_SNAPSHOT },
    { id: 'cn-plain', type: 'credit_note', original_invoice_id: 'old-dp' },
    { id: 'legacy-dp', type: 'payment_receipt' },
  )
  // jmenovitý výběr issuer_snapshot by na staré DB spadl (42703) — helper smí použít jen select('*')
  db.failSelect = (t, cols) => t === 'invoices' && cols.includes('issuer_snapshot') ? { code: '42703', message: 'column invoices.issuer_snapshot does not exist' } : null
  eq((await creditNoteIssuer(db, { creditNoteId: 'cn-stamped', originalInvoiceId: 'new-dp' })).name, 'Jan Novák', 'řádek dobropisu (trigger)')
  eq((await creditNoteIssuer(db, { creditNoteId: 'cn-plain', originalInvoiceId: 'old-dp' })).name, 'Jan Novák', 'dobropis ke starému dokladu = starý vystavitel')
  eq((await creditNoteIssuer(db, { creditNoteId: 'cn-plain', originalInvoiceId: 'new-dp' })).ico, '29909864', 'dobropis k novému dokladu = nový')
  eq((await creditNoteIssuer(db, { creditNoteId: null, originalInvoiceId: 'legacy-dp' })).ico, '29909864', 'bez snapshotu (sloupec chybí) = aktuální')
  eq((await creditNoteIssuer(db, {})).ico, '29909864')
  eq((await invoiceIssuer(db, 'nope')), null)
  const h = creditNoteIssuerHtml(await creditNoteIssuer(db, { originalInvoiceId: 'old-dp' }))
  ok(h.includes('>Jan Novák<') && h.includes('Dlouhá 1, 110 00 Praha') && h.includes('IČO: 12345678') && !h.includes('s.r.o.') && !h.includes('36876'), h)
  const n = creditNoteIssuerHtml(await creditNoteIssuer(db, { originalInvoiceId: 'new-dp' }))
  ok(n.includes('>MotoGo24 s.r.o.<') && n.includes('Mezná 9, 393 01 Mezná') && n.includes('IČO: 29909864') && n.includes('C 36876, Krajský soud v Českých Budějovicích'), n)
  ok(creditNoteIssuerHtml(null).includes('MotoGo24 s.r.o.'), 'bez vystavitele = naposledy načtený / výchozí provozovatel')
})

Deno.test('verze dokumentů: jiný provozovatel nebo vznik před valid_from = zamraženo (nemazat)', () => {
  const cur = { ico: '29909864', name: 'MotoGo24 s.r.o.', validFrom: '2026-11-29T10:00:00+00:00' }
  ok(isFrozenVersion({ id: '1', pdf_path: 'a', created_at: '2026-12-01T00:00:00Z', filled_data: { company_ico: '12345678', company_name: 'Jan Novák' } }, cur), 'jiné IČO')
  ok(isFrozenVersion({ id: '2', pdf_path: 'a', created_at: '2026-12-01T00:00:00Z', filled_data: { company_name: 'Jan Novák, MotoGo24' } }, cur), 'el. protokol bez IČO, jiný název')
  ok(isFrozenVersion({ id: '3', pdf_path: 'a', created_at: '2026-11-29T09:59:59+00:00', filled_data: { company_ico: '29909864' } }, cur), 'před valid_from')
  ok(isFrozenVersion({ id: '4', pdf_path: 'a', created_at: '2026-11-01T00:00:00Z', filled_data: null }, cur), 'bez dat, před valid_from')
  ok(!isFrozenVersion({ id: '5', pdf_path: 'a', created_at: '2026-11-29T10:00:01+00:00', filled_data: { company_ico: '29909864', company_name: 'MotoGo24 s.r.o.' } }, cur), 'současný provozovatel po změně')
  ok(!isFrozenVersion({ id: '6', pdf_path: 'a', created_at: '2026-11-01T00:00:00Z', filled_data: { company_ico: '12345678' } }, { ico: '12345678', name: 'Jan Novák', validFrom: null }), 'stará DB (bez valid_from, týž provozovatel) = dosavadní přemazání')
  ok(!isFrozenVersion({ id: '7', pdf_path: 'a', filled_data: {} }, cur), 'bez data vzniku a bez firemních údajů')
  const parts = splitOldVersions([
    { id: 'old', pdf_path: 'generated/old.pdf', created_at: '2026-10-01T00:00:00Z', filled_data: { company_ico: '12345678' } },
    { id: 'new', pdf_path: 'generated/new.pdf', created_at: '2026-11-30T00:00:00Z', filled_data: { company_ico: '29909864' } },
  ], cur)
  eq([parts.frozen.map((d) => d.id), parts.removable.map((d) => d.id)], [['old'], ['new']])
})
