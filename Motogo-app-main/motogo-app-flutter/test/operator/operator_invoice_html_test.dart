// Změna provozovatele (2026-11): blok DODAVATEL, platební údaje a patička
// dokladu vykresleného v appce (InvoiceHtmlBuilder) — nový doklad nese
// MotoGo24 s.r.o., doklad vystavený dřív se tiskne v původní podobě.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/documents/document_models.dart';
import 'package:motogo_app/features/documents/invoice_html_builder.dart';

import 'operator_fixtures.dart';

const _l = 'color:#16a34a;padding-right:18px;vertical-align:top';
const _v = 'color:#0f1a14;font-weight:700';
String _row(String label, String value) => '<tr><td style="$_l">$label</td><td style="$_v">$value</td></tr>';
String _pay(String label, String value) => '''
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">$label</span>
      <span style="color:#0f1a14;font-weight:700">$value</span>
    </div>''';
const _sep = '<span style="color:#9ca3af"> &nbsp;|&nbsp; </span>';

String _build(Map<String, dynamic> row) => InvoiceHtmlBuilder.build(
      UserInvoice.fromJson(row),
      customerName: 'Jan Novák',
      customerAddress: 'Dlouhá 1, Praha',
      customerEmail: 'jan@example.com',
      customerPhone: '+420 600 000 000',
    );

/// Blok DODAVATEL (od nadpisu po konec jeho tabulky).
String _supplier(String html) {
  final from = html.indexOf('>DODAVATEL</div>');
  return html.substring(from, html.indexOf('</table>', from));
}

/// Sloupec PLATBA.
String _payment(String html) {
  final from = html.indexOf('>PLATBA</div>');
  return html.substring(from, html.indexOf('<!-- POLOŽKY -->', from));
}

String _footer(String html) {
  final from = html.indexOf('<!-- FOOTER -->');
  return html.substring(from, html.indexOf('<script>', from));
}

const _types = ['advance', 'proforma', 'payment_receipt', 'final', 'shop_final', 'shop_proforma', 'credit_note'];

void main() {
  group('doklad dnešního provozovatele (bez snapshotu i se snapshotem)', () {
    for (final type in _types) {
      for (final (label, row) in [
        ('bez snapshotu', invoiceRow(type: type, withIssuerKey: false)),
        ('snapshot null', invoiceRow(type: type, issuer: null)),
        ('snapshot nové společnosti', invoiceRow(type: type, issuer: newIssuerSnapshot)),
        ('snapshot jen název + IČO', invoiceRow(type: type, issuer: const {'name': 'MotoGo24 s.r.o.', 'ico': '29909864'})),
      ]) {
        test('$type · $label', () {
          final html = _build(row);
          expect(
              _supplier(html),
              contains([
                _row('Název', 'MotoGo24 s.r.o.'),
                _row('Sídlo', 'Mezná 9, 393 01 Mezná'),
                _row('IČO', '29909864'),
                _row('Zápis', 'obchodní rejstřík, Krajský soud v Českých Budějovicích, oddíl C, vložka 36876'),
                '<tr><td colspan="2" style="$_v">Nejsme plátci DPH.</td></tr>',
                _row('E-mail', 'info@motogo24.cz'),
                _row('Telefon', '+420 774 256 271'),
              ].join('\n            ')));
          expect(_supplier(html), isNot(contains('>DIČ<')));
          expect(
              _payment(html),
              contains([
                _pay('Bankovní účet', '2303580494/2010'),
                _pay('Banka', 'Fio banka'),
                _pay('IBAN', 'CZ83 2010 0000 0023 0358 0494'),
              ].join('\n')));
          expect(
              _footer(html),
              contains('''
    <strong style="color:#ffffff">MotoGo24 s.r.o.</strong>
    ${_sep}Mezná 9, 393 01 Mezná
    ${_sep}IČO: 29909864
    $_sep<span style="color:#74FB71">+420 774 256 271</span>
    $_sep<span style="color:#74FB71">info@motogo24.cz</span>
    $_sep<span style="color:#74FB71">www.motogo24.cz</span>
  </div>'''));
          // dřívější provozovatel se na novém dokladu neobjeví nikde
          for (final old in [oldIssuerSnapshot['name'], oldIssuerSnapshot['ico'], oldIssuerSnapshot['bank_account'], oldIssuerSnapshot['bank_name'], 'Pelhřimov']) {
            expect(html, isNot(contains(old as String)), reason: '$old');
          }
        });
      }
    }
  });

  group('doklad vystavený dřívějším provozovatelem = původní podoba', () {
    for (final type in _types) {
      test(type, () {
        final html = _build(invoiceRow(type: type, issuer: oldIssuerSnapshot));
        // přesně řádky, které appka tiskla při vystavení (bez „Zápis", bez poznámky o DPH)
        expect(
            _supplier(html),
            endsWith('''
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            ${_row('Název', 'Bc. Petra Semorádová')}
            ${_row('Adresa', 'Mezná 9, 393 01 Pelhřimov')}
            ${_row('IČO', '21874263')}
            ${_row('E-mail', 'info@motogo24.cz')}
            ${_row('Telefon', '+420 774 256 271')}
          '''));
        final pay = _payment(html);
        expect(pay, contains(_pay('Bankovní účet', '670100-2225851630/6210')));
        expect(pay, isNot(contains('>Banka<')));
        expect(pay, isNot(contains('>IBAN<')));
        expect(
            _footer(html),
            contains('''
    <strong style="color:#ffffff">Bc. Petra Semorádová</strong>
    ${_sep}Mezná 9, 393 01 Pelhřimov
    ${_sep}IČO: 21874263
    $_sep<span style="color:#74FB71">+420 774 256 271</span>
    $_sep<span style="color:#74FB71">info@motogo24.cz</span>
    $_sep<span style="color:#74FB71">www.motogo24.cz</span>
  </div>'''));
        // nic z nové společnosti
        for (final fresh in ['MotoGo24 s.r.o.', '29909864', '2303580494', 'Fio', 'CZ83', '36876', 'Nejsme plátci', '393 01 Mezná', '>Sídlo<', '>Zápis<']) {
          // „Sídlo" smí být jen u odběratele-firmy (tady žádná není)
          expect(html, isNot(contains(fresh)), reason: fresh);
        }
      });
    }
  });

  test('údaje vystavitele z DB se v HTML escapují', () {
    final html = _build(invoiceRow(issuer: const {
      'name': 'A & B <script>"x"</script>',
      'ico': '11111111',
      'address': 'Ulice <1>',
      'bank_account': '1/0100',
    }));
    expect(html, contains('A &amp; B &lt;script&gt;&quot;x&quot;&lt;/script&gt;'));
    expect(html, contains('Ulice &lt;1&gt;'));
    expect(html, isNot(contains('<script>"x"')));
  });

  test('plátce DPH se zápisem: DIČ místo poznámky „Nejsme plátci DPH."', () {
    final html = _build(invoiceRow(issuer: {...newIssuerSnapshot, 'vat_payer': true, 'dic': 'CZ29909864'}));
    expect(_supplier(html), contains(_row('DIČ', 'CZ29909864')));
    expect(html, isNot(contains('Nejsme plátci DPH.')));
  });
}
