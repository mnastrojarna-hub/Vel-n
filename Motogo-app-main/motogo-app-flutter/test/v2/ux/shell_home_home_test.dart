// Home v2 fidelity (board Main): SH-06/25 S2 ring + cancel link, SH-09
// meta, SH-10 club disclosure, SH-18 Hero, SH-19 snap, SH-20 Ken Burns,
// SH-21 eyebrow, SH-22 offer copy, SH-23 skeleton, SH-24 record row,
// SH-26 pills, SH-27 S8 ring, SH-30 count-up, SH-39 tier preview, SH-40.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_count_up.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_dialog.dart';
import 'package:motogo_app/features/home/v2/home_club_card_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_ticket_pay_v2.dart';
import 'package:motogo_app/features/home/v2/home_tier_preview_v2.dart';
import 'package:motogo_app/features/routes/ride_recorder_state.dart';
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

  testWidgets('SH-25/06 S2: ring + texts, ZAPLATIT, cancel link → the T6 confirm', (tester) async {
    await _home(tester, homeCases()['s2']!());
    expect(find.byType(TkCountdownRing), findsOneWidget);
    expect(find.text('Zbývá na zaplacení'), findsOneWidget);
    expect(find.text('Motorku ti držíme. Platební okno je 30 minut.'), findsOneWidget);
    expect(find.text('TÝM PRO TEBE'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('tk-pay-cancel')));
    await tester.tap(find.byKey(const ValueKey('tk-pay-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MgDialogFrame), findsOneWidget);
    expect(find.text('Zrušit rezervaci?'), findsOneWidget);
    await tester.tap(find.text('Zpět'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MgDialogFrame), findsNothing);
  });

  testWidgets('SH-25 ring drains with the existing countdown value', (tester) async {
    final p = PendingBooking(id: 'x', totalPrice: 1, createdAt: DateTime.now().subtract(const Duration(minutes: 15)));
    expect(TkCountdownRing.fraction(p), closeTo(0.5, 0.01));
  });

  testWidgets('SH-09 meta: branch · type; booking number VISIBLE on its own line (old Domů card parity)', (tester) async {
    await _home(tester, homeCases()['s6']!());
    expect(find.text('Velké Němčice · samoobsluha nonstop'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tk-short-id')), matching: find.text('#55556666')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('#55556666')), findsWidgets);
    await _home(tester, homeCases()['s4']!());
    expect(find.text('Mezná · s obsluhou'), findsOneWidget);
    expect(find.byKey(const ValueKey('tk-short-id')), findsOneWidget);
    await _home(tester, homeCases()['s5']!());
    expect(find.text('Masarykova 12, 602 00 Brno'), findsOneWidget);
    // Never cut: the longest type name (uk) at 320 dp still shows the whole number.
    await _home(tester, homeCases()['s6']!(), size: const Size(320, 690), lang: 'uk');
    final id = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byKey(const ValueKey('tk-short-id')), matching: find.byType(RichText)));
    expect(id.didExceedMaxLines, isFalse);
    expect(id.size.width, greaterThanOrEqualTo(id.textSize.width - 0.5));
  });

  testWidgets('SH-26 S6 "PŘIPRAVENO" + n/m hotovo; S7 "DNES · VÝDEJ OD 12:00"', (tester) async {
    await _home(tester, homeCases()['s6']!());
    expect(find.text('PŘIPRAVENO'), findsOneWidget);
    // SH-37: "3 dny" / "12 027 Kč" never break (NBSP, display only).
    expect(find.textContaining('3\u00a0dny'), findsWidgets);
    expect(find.textContaining('027\u00a0Kč'), findsWidgets);
    expect(find.byKey(const ValueKey('tk-done-of')), findsOneWidget);
    expect(find.text('2/4 hotovo'), findsOneWidget);
    await _home(tester, homeCases()['s7']!());
    expect(find.text('DNES · VÝDEJ OD 12:00'), findsOneWidget);
  });

  testWidgets('SH-27 S8: day ring "2/3" + return line + recording line with km', (tester) async {
    await _home(tester, homeCases()['s8-rec']!());
    expect(find.byKey(const ValueKey('tk-day-ring')), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.textContaining('Vrať do'), findsOneWidget);
    expect(find.textContaining('Záznam jízdy z výpůjčky běží ·'), findsOneWidget);
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

  testWidgets('SH-18 Hero tags unique on every Home state; ticket = res-img, centred funnel card = moto-img', (tester) async {
    for (final e in homeCases().entries) {
      await _home(tester, e.value(), reduced: false);
      expectUniqueHeroTags(tester);
    }
    await _home(tester, homeCases()['s6']!(), reduced: false);
    expect(find.byWidgetPredicate((w) => w is Hero && '${w.tag}'.startsWith('res-img-')), findsOneWidget);
    await _home(tester, homeCases()['s0']!(), reduced: false);
    expect(find.byWidgetPredicate((w) => w is Hero && '${w.tag}'.startsWith('moto-img-')), findsOneWidget);
  });

  testWidgets('SH-21 cs/en 360: the funnel eyebrow is shown (not only the icon)', (tester) async {
    for (final (lang, text) in [('cs', 'TVOJE PŘÍŠTÍ JÍZDA'), ('en', 'YOUR NEXT RIDE')]) {
      await _home(tester, homeCases()['s0']!(), lang: lang);
      expect(find.textContaining(text.split(' ').first), findsWidgets, reason: lang);
    }
  });

  testWidgets('SH-40 + SH-22: funnel meta keeps the branch; offer rows show the board copy', (tester) async {
    await _home(tester, homeCases()['s0']!());
    expect(tester.widget<Text>(find.byKey(const ValueKey('funnel-meta')).first).data, 'Mezná');
    expect(find.text('Celá nabídka s tvým termínem'), findsOneWidget);
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

  testWidgets('SH-30 Moje zážitky values count up once (700 ms), reduced → final at once', (tester) async {
    await _home(tester, homeCases()['s0']!());
    expect(find.byType(MgCountUp), findsWidgets);
    expect(tester.binding.transientCallbackCount, 0);
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

  testWidgets('SH-19 routes carousel: a fling settles on a card edge', (tester) async {
    await _home(tester, homeCases()['s0']!(), reduced: false);
    final list = find.byKey(const ValueKey('home-routes-list'));
    await tester.scrollUntilVisible(list, 300, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.fling(list.first, const Offset(-200, 0), 900);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final pos = tester.state<ScrollableState>(find.descendant(of: list.first, matching: find.byType(Scrollable))).position;
    final extent = (360 - 16 - 12 - 44).clamp(240.0, 296.0) + 12;
    final k = pos.pixels / extent;
    expect((k - k.round()).abs() < 0.01 || pos.pixels == pos.maxScrollExtent, isTrue, reason: 'offset ${pos.pixels}');
  });

  testWidgets('SH-27 recording line only for the automatic recording', (tester) async {
    await _home(tester, homeOverrides(
        reservations: [res('b8', status: 'active', from: -1, to: 1)],
        recorder: const RideRecorderState(recording: true, manual: true, points: 5)));
    expect(find.textContaining('Záznam jízdy z výpůjčky běží'), findsNothing);
  });
}
