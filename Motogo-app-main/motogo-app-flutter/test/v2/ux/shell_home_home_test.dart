// Home v2 fidelity (board Main): SH-25 countdown ring value, SH-10 club
// disclosure, SH-18 Hero, SH-20 Ken Burns, SH-21 eyebrow, SH-23 skeleton,
// SH-24 record row, SH-39 tier preview, SH-40. (Ticket / offer / routes /
// Moje zážitky blocks left Domů with the "jen vzhled" restore —
// lookonly-fix:core; see test/v2/ux/lookonly_core_test.dart.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/v2/home_bike_list_v2.dart';
import 'package:motogo_app/features/home/v2/home_club_card_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_ticket_pay_v2.dart';
import 'package:motogo_app/features/home/v2/home_tier_preview_v2.dart';
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

  testWidgets('SH-25 ring drains with the existing countdown value', (tester) async {
    final p = PendingBooking(id: 'x', totalPrice: 1, createdAt: DateTime.now().subtract(const Duration(minutes: 15)));
    expect(TkCountdownRing.fraction(p), closeTo(0.5, 0.01));
  });

  testWidgets('SH-10 club: collapsed shows points total, app-only note, all ranks (old Domů card); tap opens perks + rail', (tester) async {
    await pumpV2(tester, const SingleChildScrollView(child: HomeClubCardV2()), overrides: homeOverrides(), reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(HomeClubCardV2)).height, lessThanOrEqualTo(380));
    expect(find.text('TVŮJ KLUB · LEVEL 3 Z 20'), findsOneWidget);
    // Never behind the disclosure: total points, app-only rule, all ranks.
    expect(find.text('5 b. · rezervace z appky i webu'), findsOneWidget);
    final tr = AppTranslations.of('cs');
    expect(find.text(tr.tr('loyaltyAppOnly')), findsOneWidget);
    expect(find.text(tr.tr('v2HomeClubAll')), findsOneWidget);
    for (final k in ['loyaltyAppOnly', 'v2HomeClubAll']) {
      expect(find.descendant(of: find.byKey(const ValueKey('home-club-more')), matching: find.text(tr.tr(k))), findsNothing,
          reason: '$k outside the disclosure');
    }
    expect(find.text('na každou jízdu v appce'), findsNothing);
    await tester.tap(find.text('Výhody a ligy'));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('Skrýt výhody'), findsOneWidget);
    expect(find.byKey(const ValueKey('club-tier-0')), findsOneWidget);
  });

  testWidgets('SH-39 league disc → tier preview sheet (no data, inert CTA)', (tester) async {
    await pumpV2(tester, const SingleChildScrollView(child: HomeClubCardV2()), overrides: homeOverrides(), reducedMotion: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Výhody a ligy'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('club-tier-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TierPreviewV2), findsOneWidget);
    expect(find.text('Takhle bude vypadat tvoje appka'), findsOneWidget);
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

  testWidgets('SH-40: funnel meta keeps the branch; the calculator row names the centred bike', (tester) async {
    await _home(tester, homeCases()['s0']!());
    expect(tester.widget<Text>(find.byKey(const ValueKey('funnel-meta')).first).data, 'Mezná');
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
