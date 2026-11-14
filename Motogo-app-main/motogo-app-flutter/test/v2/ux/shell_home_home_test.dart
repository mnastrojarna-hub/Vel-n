// Home v2 fidelity (board Main): SH-18 Hero, SH-20 Ken Burns, SH-21
// eyebrow, SH-23 skeleton, SH-24 record row, SH-40. (Ticket / offer /
// routes / Moje zážitky / club blocks left Domů with the "jen vzhled"
// restore — lookonly-fix:core; see test/v2/ux/lookonly_core_test.dart.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/v2/funnel_carousel_v2.dart';
import 'package:motogo_app/features/home/v2/home_bike_list_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import '../support/hero_tags.dart';
import '../support/v2_harness.dart';

Future<void> _home(WidgetTester t, List<Override> o, {bool reduced = true, Size size = const Size(360, 780), String lang = 'cs'}) async {
  // A fresh ProviderScope per state (Riverpod keeps the first overrides).
  await t.pumpWidget(const SizedBox());
  await pumpV2(t, const HomeScreenV2(), overrides: o, reducedMotion: reduced, size: size, lang: lang);
  // Home's warm-up timer (2 s) + one-shot reveals.
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 1600));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  testWidgets('SH-18 Hero tags unique on every Home state; centred funnel card = moto-img, list heroes off beside it', (tester) async {
    for (final e in homeCases().entries) {
      await _home(tester, e.value(), reduced: false);
      expectUniqueHeroTags(tester);
    }
    // Old Domů booking cards had no shared photo; the list cards fly to the detail.
    await _home(tester, homeCases()['s6']!(), reduced: false);
    expect(find.byWidgetPredicate((w) => w is Hero && '${w.tag}'.startsWith('res-img-')), findsNothing);
    expect(tester.widget<HomeBikeListV2>(find.byType(HomeBikeListV2, skipOffstage: false)).heroes, isTrue);
    await _home(tester, homeCases()['s0']!(), reduced: false);
    expect(find.byWidgetPredicate((w) => w is Hero && '${w.tag}'.startsWith('moto-img-')), findsWidgets);
    expect(tester.widget<HomeBikeListV2>(find.byType(HomeBikeListV2, skipOffstage: false)).heroes, isFalse);
  });
  testWidgets('SH-21 cs/en 360: the funnel eyebrow is shown (not only the icon)', (tester) async {
    for (final (lang, text) in [('cs', 'TVOJE PŘÍŠTÍ JÍZDA'), ('en', 'YOUR NEXT RIDE')]) {
      await _home(tester, homeCases()['s0']!(), lang: lang);
      expect(find.textContaining(text.split(' ').first), findsWidgets, reason: lang);
    }
  });

  // v5.0.1 (owner): the branch is the neon chip on the photo's top-right
  // corner; the line under the name keeps only the category.
  testWidgets('SH-40: branch chip on the funnel photo, category line; the calculator row names the centred bike', (tester) async {
    await _home(tester, homeCases()['s0-dates']!());
    final card = find.byType(FunnelBikeCard).first;
    expect(find.descendant(of: card, matching: find.byKey(const ValueKey('mg-branch-chip'))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('Mezná')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('funnel-meta')).first).data, isNot(contains('Mezná')));
    expect(find.textContaining('BMW R 1200 GS Adventure ·'), findsWidgets);
  });

  testWidgets('SH-23 bookings skeleton in the funnel geometry (±10 %)', (tester) async {
    await _home(tester, homeCases()['res-loading']!());
    final sk = tester.getSize(find.byKey(const ValueKey('home-hero-skeleton'))).height;
    await _home(tester, homeCases()['s0']!());
    final real = tester.getSize(find.byType(HomeFunnelV2)).height;
    expect(sk, inInclusiveRange(real * 0.9, real * 1.1), reason: 'skeleton $sk vs funnel $real');
  });

  testWidgets('SH-24 record row: 360 cs uses the 44 tile row (measured, not < 300)', (tester) async {
    await _home(tester, homeCases()['manual-rec']!());
    final tiles = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 44 && w.constraints?.maxHeight == 44);
    expect(tiles, findsWidgets);
  });

  testWidgets('SH-20 a card leaving the centre eases back (no scale jump > .01 per frame)', (tester) async {
    await _home(tester, homeCases()['s0']!(), reduced: false);
    await tester.pump(const Duration(seconds: 2));
    double scaleOf(Finder f) => tester.widget<Transform>(f).transform.getMaxScaleOnAxis();
    final first = find.byKey(const ValueKey('funnel-kb')).first;
    final before = scaleOf(first);
    expect(before, greaterThan(1.0));
    await tester.tap(find.bySemanticsLabel('Další motorka'));
    var last = before;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final kb = find.byKey(const ValueKey('funnel-kb'));
      if (kb.evaluate().isEmpty) break;
      final s = scaleOf(kb.first);
      expect((s - last).abs(), lessThan(0.01));
      last = s;
    }
  });


}
