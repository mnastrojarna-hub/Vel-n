// Změna provozovatele (2026-11): údaje DŘÍVĚJŠÍHO provozovatele smí v appce
// zůstat jen tady — jako vzorek `invoices.issuer_snapshot`, který backend
// doplnil dokladům vystaveným před změnou (migrace
// `invoices_issuer_snapshot`). Testy na něm ověřují, že už vystavený doklad
// drží původního vystavitele. Hlídá `operator_guard_test.dart`.

/// Snapshot dokladu vystaveného dřívějším provozovatelem (tvar z živé DB).
const Map<String, dynamic> oldIssuerSnapshot = {
  'name': 'Bc. Petra Semorádová',
  'ico': '21874263',
  'dic': null,
  'vat_payer': false,
  'address': 'Mezná 9, 393 01 Pelhřimov',
  'bank_account': '670100-2225851630/6210',
  'bank_name': 'mBank',
  'phone': '+420 774 256 271',
  'email': 'info@motogo24.cz',
  'web': 'https://motogo24.com',
};

/// Snapshot dokladu vystaveného dnešním provozovatelem (tvar `company_info`
/// po přepnutí — vše vyplněno).
const Map<String, dynamic> newIssuerSnapshot = {
  'name': 'MotoGo24 s.r.o.',
  'ico': '29909864',
  'dic': null,
  'vat_payer': false,
  'address': 'Mezná 9, 393 01 Mezná',
  'register':
      'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
  'register_short': 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
  'bank_account': '2303580494/2010',
  'bank_iban': 'CZ8320100000002303580494',
  'bank_name': 'Fio banka',
  'bank_bic': 'FIOBCZPPXXX',
  'data_box': '2xfihrd',
  'phone': '+420 774 256 271',
  'email': 'info@motogo24.cz',
  'web': 'https://motogo24.com',
  'valid_from': '2026-11-29T10:00:00+00:00',
};

/// Řádek `invoices` pro testy (volitelně s vystavitelem).
Map<String, dynamic> invoiceRow({String type = 'final', Object? issuer, bool withIssuerKey = true}) => {
      'id': 'inv-$type',
      'number': 'KF-2026-0042',
      'type': type,
      'status': 'paid',
      'total': type == 'credit_note' ? -1500 : 12027,
      'booking_id': '0a1b2c3d-0000-0000-0000-00001234abcd',
      'variable_symbol': '20260042',
      'issue_date': '2026-09-30',
      'due_date': '2026-10-07',
      'created_at': '2026-09-30T10:00:00Z',
      'items': [
        {'description': 'BMW R 1300 GS — 3 dny', 'qty': 1, 'unit_price': 12027},
      ],
      if (withIssuerKey) 'issuer_snapshot': issuer,
    };
