// Změna provozovatele (2026-11) — pojistka zdrojáků appky:
//  • údaje DNEŠNÍHO provozovatele (IČO, účet, IBAN, zápis v rejstříku) jsou
//    natvrdo JEN v `lib/core/operator_info.dart`, vše ostatní je z něj bere;
//  • DŘÍVĚJŠÍ provozovatel není v `lib/` nikde (už vystavené doklady ho
//    nesou v datech — `invoices.issuer_snapshot`), v `test/` jen ve vzorku
//    `test/operator/operator_fixtures.dart`.
// Běží i na kopii iOS stromu (stejný `lib/`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/operator_info.dart';

import 'operator_fixtures.dart';

List<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _rel(File f) => f.path.replaceAll('\\', '/');

void main() {
  const home = 'lib/core/operator_info.dart';
  final lib = _dartFiles('lib');

  test('lib/ se našel a obsahuje operator_info.dart', () {
    expect(lib.length, greaterThan(500));
    expect(lib.map(_rel), contains(home));
  });

  test('údaje dnešního provozovatele jsou natvrdo jen v operator_info.dart', () {
    final needles = <String>[
      OperatorInfo.ico,
      OperatorInfo.name,
      OperatorInfo.seat,
      OperatorInfo.account,
      OperatorInfo.account.split('/').first,
      OperatorInfo.iban,
      OperatorInfo.bic,
      OperatorInfo.bankName,
      'vložka 36876',
      'C 36876',
      'Nejsme plátci',
    ];
    final hits = <String>[];
    for (final f in lib) {
      if (_rel(f) == home) continue;
      final src = f.readAsStringSync();
      for (final n in needles) {
        if (src.contains(n)) hits.add('${_rel(f)}: $n');
      }
    }
    expect(hits, isEmpty, reason: 'údaje provozovatele patří jen do $home');
  });

  final oldNeedles = <String>[
    oldIco,
    oldName.split(' ').last.substring(0, 5), // příjmení (kmen)
    oldAccount.split('-').last.split('/').first, // číslo účtu
    oldBank,
    oldDataBox,
    oldTradeStem,
  ];

  test('dřívější provozovatel není v lib/ nikde', () {
    final hits = <String>[];
    for (final f in lib) {
      final src = f.readAsStringSync();
      for (final n in oldNeedles) {
        if (src.contains(n)) hits.add('${_rel(f)}: $n');
      }
    }
    expect(hits, isEmpty);
  });

  test('v test/ je dřívější provozovatel jen ve vzorku snapshotu', () {
    const allowed = 'test/operator/operator_fixtures.dart';
    final hits = <String>[];
    for (final f in _dartFiles('test')) {
      if (_rel(f) == allowed) continue;
      final src = f.readAsStringSync();
      for (final n in oldNeedles) {
        if (src.contains(n)) hits.add('${_rel(f)}: $n');
      }
    }
    expect(hits, isEmpty);
  });

  test('místa, která provozovatele ukazují, ho berou z operator_info', () {
    String src(String p) => File(p).readAsStringSync();
    expect(src('lib/features/documents/contracts_screen.dart'), contains('OperatorInfo.docVars()'));
    expect(src('lib/features/documents/invoice_issuer.dart'), contains('OperatorInfo.snapshot'));
    for (final p in ['lib/features/sos/sos_service_screen.dart', 'lib/features/sos/v2/sos_service_view_v2.dart']) {
      final s = src(p);
      for (final ref in ['OperatorInfo.name', 'OperatorInfo.icoVatLine', 'OperatorInfo.seat']) {
        expect(s, contains(ref), reason: '$p: $ref');
      }
    }
    // doklad nemá žádnou vlastní konstantu dodavatele
    final builder = src('lib/features/documents/invoice_html_builder.dart');
    expect(builder, contains('issuer.supplierRowsHtml'));
    expect(builder, contains('issuer.bankRowsHtml'));
    expect(builder, contains('issuer.footerHtml'));
    expect(builder, isNot(contains('static const _company')));
  });

  test('dotazy na doklady nevyjmenovávají sloupce (issuer_snapshot nesmí chybět ani shodit dotaz)', () {
    final re = RegExp(r"\.from\('invoices'\)\s*\.select\(([^)]*)\)");
    var n = 0;
    for (final f in lib) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        n++;
        expect(m[1]!.trim(), isEmpty, reason: '${_rel(f)}: select(${m[1]}) — použij select() (= všechny sloupce)');
      }
    }
    expect(n, greaterThanOrEqualTo(3), reason: 'Faktury, detail rezervace, podrobnosti o platbě');
  });
}
