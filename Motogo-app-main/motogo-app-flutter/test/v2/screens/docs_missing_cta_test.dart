// Moje doklady v2: hlavní výzva skenuje jen chybějící strany („Doplnit
// chybějící“ + co přesně se vyfotí), karta OP / ŘP jen svůj doklad, po
// kompletních dokladech jen vedlejší „Naskenovat znovu“ (majitel
// 2026-10-22). 8 jazyků × 2 velikosti bez přetečení, PNG do MG_SHOTS_DIR.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/v2/docs_parts_v2.dart';
import 'package:motogo_app/features/documents/v2/docs_view_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_docs_scan.dart';
import '../support/v2_harness.dart';

class _Calls {
  final list = <String>[];
  DocsViewV2 view(DocsScreenStatus s) => DocsViewV2(
        verifiedAsync: AsyncValue.data(s),
        onBack: () {},
        onScan: () => list.add('full'),
        onScanMissing: () => list.add('missing'),
        onScanId: () => list.add('id'),
        onScanDl: () => list.add('dl'),
        onUpload: () {},
        onReset: (_) {},
        onRetry: () {},
      );
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
}

void main() {
  setUpAll(loadMontserrat);
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  final partial = st(gate(idF: true, idB: true, dlF: true));
  for (final lang in kV2Langs) {
    for (final size in kV2Sizes) {
      testWidgets('$lang ${size.width.toInt()}: partial → "Doplnit chybějící" + what', (t) async {
        final key = GlobalKey();
        final c = _Calls();
        await pumpV2(t, c.view(partial), lang: lang, size: size, boundaryKey: key);
        await t.pump(const Duration(milliseconds: 50));
        await expectCleanFrames(t);
        final tr = AppTranslations(lang);
        expect(find.text(tr.tr('v2DocsScanMissing').toUpperCase()), findsOneWidget);
        expect(find.text(tr.tr('v2DocsScanMissingHint').replaceAll('{what}', tr.tr('gmDlBack'))), findsOneWidget);
        expect(find.text(tr.tr('scanDlOnly')), findsNothing, reason: 'the duplicate ŘP-only button is gone');
        await maybeShot(t, key, 'profile__docs__cta_partial__${lang}__${size.width.toInt()}x${size.height.toInt()}');
        await _tap(t, find.byType(MgCta));
        expect(c.list, ['missing']);
      });

      testWidgets('$lang ${size.width.toInt()}: complete → only "Naskenovat znovu"', (t) async {
        final key = GlobalKey();
        final c = _Calls();
        await pumpV2(t, c.view(st(gate(idF: true, idB: true, dlF: true, dlB: true))), lang: lang, size: size, boundaryKey: key);
        await t.pump(const Duration(milliseconds: 50));
        await expectCleanFrames(t);
        final rescan = find.text(AppTranslations(lang).tr('v2DocsRescan'));
        expect(rescan, findsOneWidget);
        expect(find.byType(MgCta), findsNothing, reason: 'no looping CTA once the docs are complete');
        await maybeShot(t, key, 'profile__docs__cta_complete__${lang}__${size.width.toInt()}x${size.height.toInt()}');
        await _tap(t, rescan);
        expect(c.list, ['full']);
      });
    }
  }

  testWidgets('nothing uploaded → today\'s full scan CTA', (t) async {
    final c = _Calls();
    await pumpV2(t, c.view(st(gate())));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text(AppTranslations('cs').tr('scanDocsCamera')), findsOneWidget);
    await _tap(t, find.byType(MgCta));
    expect(c.list, ['full']);
  });

  testWidgets('card buttons scan only their own document', (t) async {
    final c = _Calls();
    await pumpV2(t, c.view(st(gate(idF: true))), size: const Size(412, 915));
    await t.pump(const Duration(milliseconds: 50));
    final scan = find.text(AppTranslations('cs').tr('scan'));
    expect(scan, findsNWidgets(2));
    await _tap(t, scan.at(0));
    await _tap(t, scan.at(1));
    expect(c.list, ['id', 'dl']);
    expect(find.byType(DocCardV2), findsNWidgets(2));
  });
}
