// ===== _tests/operator_company_test.ts =====
// Změna provozovatele (2026-11): _shared/company.ts — výchozí provozovatel, čtení
// app_settings.company_info (plné / částečné / chybějící), vystavitel dokladu ze snapshotu (issuerOf),
// patičky a proměnné dokumentů. Faktura, dobropis, QR platba a verze dokumentů: operator_docs_test.ts.
// „Dřívější provozovatel“ je v testech smyšlený (Jan Novák, účet = vzorový účet ČNB).
// Bez import mapy: deno test --allow-all --no-check supabase/functions/_tests/operator_company_test.ts
// deno-lint-ignore-file no-explicit-any
import {
  bankLabel, COMPANY_DEFAULT, companyDocVars, companyFooterLine, companyFromInfo, companyIdLine, companyNow, czIban,
  emailFooterCompanyHtml, fmtIban, issuerOf, loadCompany, parseRegister, registerInvoiceLine, registerLine,
} from '../_shared/company.ts'
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
  eq(companyNow().name, 'Jan Novák', 'synchronní pohled = poslední načtení')
  // chybějící řádek / řádek bez názvu / chyba dotazu / výjimka → VÝCHOZÍ provozovatel, nikdy dříve načtený
  for (const [label, db] of [
    ['chybí řádek', settingsDb()],
    ['bez názvu', settingsDb({ bank_account: '1/0100' })],
    ['chyba dotazu', (() => { const d = settingsDb(OLD_INFO); d.failSelect = () => ({ code: '57014', message: 'timeout' }); return d })()],
    ['výjimka', { from() { throw new Error('boom') } }],
  ] as Array<[string, any]>) {
    await loadCompany(settingsDb(OLD_INFO))
    const c = await loadCompany(db)
    eq([c.name, c.ico, c.iban], ['MotoGo24 s.r.o.', '29909864', 'CZ8320100000002303580494'], label)
    eq(companyNow().ico, '29909864', `${label}: ani patičky si nepodrží dřívějšího provozovatele`)
  }
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
