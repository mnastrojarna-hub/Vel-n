// Skener dokladů: zákazník nikdy znovu nefotí stranu, kterou už nahrál
// (majitel 2026-10-22, audit „no double entry“ — area profile). Plán skenu
// podle brány dokladů + skener v režimech missing* (8 jazyků); staré režimy
// (celý tok, dl_only) beze změny.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/documents/doc_scan_plan.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_scanner_screen.dart';

import '../support/fakes_docs_scan.dart';
import '../support/v2_harness.dart';

const _allId = {'id_front', 'id_back', 'passport_front', 'passport_back'};

Future<void> _pumpScanner(WidgetTester t, String? mode, DocsScreenStatus? s, {String lang = 'cs'}) async {
  await pumpV2(t, DocumentScannerScreen(scanMode: mode), lang: lang, overrides: [
    docsScreenStatusProvider.overrideWith((ref) async {
      if (s == null) throw Exception('timeout');
      return s;
    }),
  ]);
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  group('resolveDocScanPlan', () {
    test('today\'s modes stay the full flow', () {
      for (final m in [null, 'all', 'dl_only']) {
        final p = resolveDocScanPlan(m, st(gate(idF: true, idB: true, dlF: true)));
        expect([p.idType, p.only, p.offerDlOnly], [null, null, true], reason: '$m');
      }
    });

    test('missing: only the ŘP back when everything else is uploaded', () {
      final p = resolveDocScanPlan('missing', st(gate(idF: true, idB: true, dlF: true)));
      expect(p.idType, 'dl_only');
      expect(p.only, {'dl_back'});
    });

    test('missing: OP back + whole ŘP, no ID choice (the OP front is known)', () {
      final p = resolveDocScanPlan('missing', st(gate(idF: true)));
      expect(p.idType, 'op');
      expect(p.only, {'id_back', 'dl_front', 'dl_back'});
    });

    test('missing: no ID → OP / pas choice, "only ŘP" only while the ŘP is missing', () {
      final both = resolveDocScanPlan('missing', st(gate(dlB: true)));
      expect(both.idType, isNull);
      expect(both.only, {..._allId, 'dl_front'});
      expect(both.offerDlOnly, isTrue);
      final idOnly = resolveDocScanPlan('missing', st(gate(dlF: true, dlB: true)));
      expect(idOnly.only, _allId);
      expect(idOnly.offerDlOnly, isFalse);
    });

    test('missing_id / missing_dl scan just their document\'s missing sides', () {
      expect(resolveDocScanPlan('missing_id', st(gate(idB: true, dlF: true))).only, {'id_front'});
      final noId = resolveDocScanPlan('missing_id', st(gate()));
      expect([noId.idType, noId.only, noId.offerDlOnly], [null, _allId, false]);
      final dlBack = resolveDocScanPlan('missing_dl', st(gate(idF: true, idB: true, dlF: true)));
      expect([dlBack.idType, dlBack.only], ['dl_only', {'dl_back'}]);
      expect(resolveDocScanPlan('missing_dl', st(gate())).only, {'dl_front', 'dl_back'});
    });

    test('without the gate: whole documents from the profile; unknown status → everything', () {
      final p = resolveDocScanPlan('missing', st(null, id: true));
      expect([p.idType, p.only], ['dl_only', {'dl_front', 'dl_back'}]);
      final u = resolveDocScanPlan('missing', null);
      expect([u.idType, u.only, u.offerDlOnly], [null, {..._allId, 'dl_front', 'dl_back'}, true]);
      // Complete docs never yield an empty scan.
      final c = resolveDocScanPlan('missing', st(gate(idF: true, idB: true, dlF: true, dlB: true)));
      expect([c.idType, c.only], [null, null]);
    });

    test('nothing uploaded vs. partial', () {
      expect(docsNothingUploaded(st(gate())), isTrue);
      expect(docsNothingUploaded(st(gate(dlB: true))), isFalse);
      expect(docsNothingUploaded(st(null)), isTrue);
      expect(docsNothingUploaded(st(null, dl: true)), isFalse);
    });
  });

  group('scanner', () {
    for (final lang in kV2Langs) {
      testWidgets('$lang: missing ŘP back → camera straight on that one side (1/1)', (t) async {
        await _pumpScanner(t, 'missing', st(gate(idF: true, idB: true, dlF: true)), lang: lang);
        final tr = AppTranslations(lang);
        expect(find.text('🏍️ ${tr.tr('driversLicense')}'), findsOneWidget);
        expect(find.text('${tr.tr('backSide')}  1/1'), findsOneWidget);
        expect(find.text(tr.tr('selectIdDocument')), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('missing OP back + ŘP → 3 steps starting with the OP back', (t) async {
      await _pumpScanner(t, 'missing', st(gate(idF: true)));
      final tr = AppTranslations('cs');
      expect(find.text('🪪 ${tr.tr('idCard')}'), findsOneWidget);
      expect(find.text('${tr.tr('backSide')}  1/3'), findsOneWidget);
    });

    testWidgets('missing_id with no ID → OP / pas choice without "only ŘP"', (t) async {
      await _pumpScanner(t, 'missing_id', st(gate(dlF: true, dlB: true)));
      final tr = AppTranslations('cs');
      expect(find.text(tr.tr('selectIdDocument')), findsOneWidget);
      expect(find.text(tr.tr('passport')), findsOneWidget);
      expect(find.text(tr.tr('dlOnly')), findsNothing);
    });

    testWidgets('status unavailable → the full flow (choice incl. "only ŘP")', (t) async {
      await _pumpScanner(t, 'missing', null);
      expect(find.text(AppTranslations('cs').tr('dlOnly')), findsOneWidget);
    });

    testWidgets('today\'s modes unchanged: full flow choice, dl_only = 2 steps', (t) async {
      final tr = AppTranslations('cs');
      await _pumpScanner(t, null, st(gate(idF: true, idB: true, dlF: true)));
      expect(find.text(tr.tr('dlOnly')), findsOneWidget);
      await _pumpScanner(t, 'dl_only', st(gate(idF: true, idB: true, dlF: true)));
      expect(find.text('${tr.tr('frontSide')}  1/2'), findsOneWidget);
    });
  });
}
