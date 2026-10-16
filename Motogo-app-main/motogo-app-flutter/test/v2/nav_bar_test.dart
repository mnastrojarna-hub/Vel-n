// V2NavBar in every language at 320 / 360 / 412 px: no overflow, no label
// clipped or touching its neighbour, badges, taps, semantics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';

import 'support/v2_harness.dart';

Widget _bar({int active = 0, ValueChanged<int>? onTap, int badge = 0, bool needs = false}) => Align(
      alignment: Alignment.bottomCenter,
      child: V2NavBar(
        activeIndex: active,
        onTap: onTap ?? (_) {},
        profileBadge: badge,
        bookingsNeedAction: needs,
      ),
    );

void main() {
  setUpAll(loadMontserrat);

  test('Montserrat is available for real label widths', () {
    // The pub cache ships flutter_gallery_assets (fonts); without it the
    // overlap checks below would be meaningless.
    expect(montserratLoaded, isTrue);
  });

  for (final lang in kV2Langs) {
    for (final width in [320.0, 360.0, 412.0]) {
      testWidgets('$lang @ $width: labels fit without overlap', (tester) async {
        await pumpV2(tester, _bar(active: 2, badge: 3, needs: true),
            lang: lang, size: Size(width, 780), rank: RankTokens.forLevel(10));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        final rects = <Rect>[];
        for (var i = 0; i < 5; i++) {
          final full = translations[lang]![V2NavBar.tabKeys[i]]!;
          final shortKey = V2NavBar.shortKeys[i];
          final short = shortKey == null ? null : translations[lang]![shortKey];
          var f = find.text(full);
          if (f.evaluate().isEmpty && short != null) f = find.text(short);
          expect(f, findsOneWidget, reason: '$lang tab $i label');
          rects.add(tester.getRect(f));
        }
        if (!montserratLoaded) return; // widths need the real font
        for (var i = 0; i < 4; i++) {
          final gap = rects[i + 1].left - rects[i].right;
          expect(gap, greaterThanOrEqualTo(5.99), reason: '$lang gap between tab $i and ${i + 1} = $gap');
        }
        expect(rects.first.left, greaterThanOrEqualTo(3.99));
        expect(rects.last.right, lessThanOrEqualTo(width - 3.99));
      });
    }
  }

  testWidgets('tap reports the tab index; active tab is selected in semantics', (tester) async {
    final taps = <int>[];
    final h = tester.ensureSemantics();
    await pumpV2(tester, _bar(active: 1, onTap: taps.add));
    await tester.tap(find.text('Trasy'));
    await tester.tap(find.text('Profil'));
    expect(taps, [3, 4]);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Motorky')),
      matchesSemantics(
          isButton: true, hasSelectedState: true, isSelected: true, hasTapAction: true, label: 'Motorky'),
    );
    h.dispose();
  });

  testWidgets('badges: Profil count (9+) and Rezervace needs-action dot in semantics', (tester) async {
    final h = tester.ensureSemantics();
    await pumpV2(tester, _bar(badge: 12, needs: true));
    expect(find.text('9+'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Profil, nepřečtené zprávy: 12')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Rezervace, vyžaduje akci')), findsOneWidget);
    h.dispose();
  });

  for (final level in [0, 1, 6, 10, 15, 17, 19, 20]) {
    testWidgets('rank $level renders (incl. reduced motion settles)', (tester) async {
      await pumpV2(tester, _bar(active: 4), rank: RankTokens.forLevel(level), reducedMotion: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }
}
