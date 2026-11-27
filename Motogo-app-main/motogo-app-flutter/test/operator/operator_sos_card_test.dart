// Změna provozovatele (2026-11): karta „Fakturační údaje" v SOS — servis na
// vlastní pěst (na tyto údaje si zákazník nechá vystavit fakturu za opravu).
// Starý i nový vzhled, všech 8 jazyků: identifikace se nepřekládá.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/sos/sos_service_screen.dart';
import 'package:motogo_app/features/sos/v2/sos_service_view_v2.dart';

import '../v2/support/asm_harness.dart';
import '../v2/support/v2_harness.dart' show kV2Langs;
import 'operator_fixtures.dart';

const _lines = ['MotoGo24 s.r.o.', 'IČO: 29909864 · neplátce DPH', 'Mezná 9, 393 01 Mezná'];

void _expectCard(WidgetTester tester) {
  for (final l in _lines) {
    expect(find.text(l), findsOneWidget, reason: l);
  }
  // tři řádky pod sebou ve stejném pořadí jako dosud
  final ys = [for (final l in _lines) tester.getTopLeft(find.text(l)).dy];
  expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: '$ys');
  // dřívější provozovatel ani adresa pobočky místo sídla
  final all = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('\n');
  for (final old in [oldName, oldIco, '393 01 Pelhřimov']) {
    expect(all, isNot(contains(old)), reason: old);
  }
}

void main() {
  const tall = Size(412, 2600);

  for (final lang in kV2Langs) {
    testWidgets('starý vzhled · $lang', (tester) async {
      await pumpAsmRouted(tester, const SosServiceScreen(), v2: false, lang: lang, size: tall);
      expect(find.byType(SosServiceViewV2), findsNothing);
      _expectCard(tester);
    });

    testWidgets('nový vzhled (v2) · $lang', (tester) async {
      await pumpAsmRouted(tester, const SosServiceScreen(), v2: true, lang: lang, size: tall);
      expect(find.byType(SosServiceViewV2), findsOneWidget);
      _expectCard(tester);
    });
  }
}
