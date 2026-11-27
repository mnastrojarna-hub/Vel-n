// ===== _tests/operator-fixtures.ts =====
// Společná data testů změny provozovatele (operator_*_test.ts).
// NEW_INFO = app_settings.company_info po migraci; OLD_INFO = „dřívější provozovatel“ před ní —
// záměrně SMYŠLENÝ (Jan Novák, vzorový účet ČNB), bez rejstříku, IBAN a názvu banky, tedy ve tvaru,
// jaký má company_info před migrací. OLD_SNAPSHOT = tvar zpětně doplněného invoices.issuer_snapshot.
export const NEW_INFO = {
  name: 'MotoGo24 s.r.o.', ico: '29909864', dic: null, vat_payer: false, address: 'Mezná 9, 393 01 Mezná',
  register: 'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
  register_short: 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
  bank_account: '2303580494/2010', bank_iban: 'CZ8320100000002303580494', bank_name: 'Fio banka', bank_bic: 'FIOBCZPPXXX',
  data_box: '2xfihrd', valid_from: '2026-11-29T10:00:00.000000+00:00',
  phone: '+420 774 256 271', email: 'info@motogo24.cz', web: 'https://motogo24.com',
}
export const OLD_INFO = {
  name: 'Jan Novák', ico: '12345678', dic: null, vat_payer: false, address: 'Dlouhá 1, 110 00 Praha',
  bank_account: '19-2000145399/0800', phone: '+420 774 256 271', email: 'info@motogo24.cz', web: 'https://motogo24.com',
}
export const OLD_SNAPSHOT = { ...OLD_INFO, bank_name: 'Stará banka' }
