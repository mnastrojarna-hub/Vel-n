// ===== _tests/operator_docs_test.ts =====
// Změna provozovatele (2026-11): doklady a dokumenty z provozovatele / ze snapshotu vystavitele —
// blok DODAVATEL a banka na faktuře (generate-invoice/template.ts), QR platba (qr-payment/spd.ts),
// vystavitel a hlavička dobropisu (process-refund/credit-note-issuer.ts) a zamražené verze
// vygenerovaných dokumentů (generate-document/versions.ts). Data: operator-fixtures.ts.
// Bez import mapy: deno test --allow-all --no-check supabase/functions/_tests/operator_docs_test.ts
// deno-lint-ignore-file no-explicit-any
import { COMPANY_DEFAULT, companyFromInfo, invoiceIssuer, issuerOf } from '../_shared/company.ts'
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
  ok(creditNoteIssuerHtml(null).includes('MotoGo24 s.r.o.'), 'bez vystavitele = provozovatel z posledního načtení')
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
