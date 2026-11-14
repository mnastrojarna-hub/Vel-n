// 5.0.1 last repair: the Home photo is sized from the room left (FR-01);
// "Přejít na …" moves the Motorky calendar with dates picked too (FR-02);
// the Home filter card's calendar blocks closed days (FR-03); plural of the
// "volných motorek" line + Ukrainian rule (FR-04); closed days have their
// own tone and the date-filter legend drops "Obsazeno" (FR-05); the photo
// of a short card keeps its size while the nav hides (FR-06); "Zrušit"
// stays a word on narrow phones (FR-07); no profile button in the headers,
// the Profil tab keeps the unread badge (owner 2026-11-14).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_65_v501_final.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/availability_calendar_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_closed_days_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_dates_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_filter_strip_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_header_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/catalog/widgets/moto_filter_panel.dart';
import 'package:motogo_app/features/home/v2/home_funnel_photo.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_header_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/bars_harness.dart';
import '../support/fakes_catalog.dart' show catalogOverrides;
import '../support/fakes_home.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _cs(String k) => translations['cs']![k]!;

DateTime _d(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

String _month(DateTime d) => '${_cs('v2CalMonth${d.month}')} ${d.year}';

Finder _cell(DateTime d) => find.byWidgetPredicate(
    (w) => w is TripDayCell && w.state.date.year == d.year && w.state.date.month == d.month && w.state.date.day == d.day);

Future<void> _homeShell(WidgetTester t, Size size, double top, String lang, List<Override> extra) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.view.padding = FakeViewPadding(top: top * 2);
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/', routes: [
    ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreenV2()),
      GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('PAGE /profile'))),
    ]),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    overrides: [
      ...homeCases()['s0']!(),
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(6)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      ...extra,
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: Locale(lang),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  group('Home photo from the room left (FR-01)', () {
    for (final (size, top, lang) in const [
      (Size(360, 780), 0.0, 'cs'),
      (Size(360, 640), 24.0, 'nl'),
      (Size(360, 640), 24.0, 'cs'),
      (Size(320, 690), 24.0, 'uk'),
    ]) {
      testWidgets('$lang ${size.width.toInt()}x${size.height.toInt()}: as big as fits, REZERVOVAT above the menu',
          (t) async {
        await _homeShell(t, size, top, lang, const []);
        final photo = t.getSize(find.descendant(of: find.byType(HomeFunnelV2), matching: find.byType(PageView))).height;
        final cta = t.getRect(find.byWidgetPredicate((w) => w is MgCta && w.size == MgCtaSize.lg60).first).bottom;
        final nav = t.getRect(find.byType(V2NavBar)).top;
        expect(cta, lessThanOrEqualTo(nav), reason: 'REZERVOVAT above the menu');
        expect(photo, inInclusiveRange(kFunnelPhotoMin, kFunnelPhotoMax));
        if (photo < kFunnelPhotoMax && photo > kFunnelPhotoMin) {
          expect(nav - cta, lessThan(10), reason: 'no room left unused under the button (photo $photo)');
        }
        expect(t.takeException(), isNull);
        await _drain(t);
      });
    }
  });

  testWidgets('Home header has no profile button; the Profil tab shows the unread badge', (t) async {
    await _homeShell(t, const Size(360, 780), 0, 'cs', [adminUnreadCountProvider.overrideWithValue(3)]);
    expect(find.byKey(const ValueKey('home-menu')), findsNothing);
    expect(find.descendant(of: find.byType(HomeHeaderV2), matching: find.byType(MgIconButton)), findsNothing);
    expect(t.widget<V2NavBar>(find.byType(V2NavBar)).profileBadge, 3);
    expect(find.descendant(of: find.byType(V2NavBar), matching: find.text('3')), findsOneWidget);
    // The logo row has the whole width: the wordmark keeps its big size.
    final mark = t.widget<Text>(find.text('MOTO GO 24'));
    expect(mark.style?.fontSize, 21);
    await _drain(t);
  });

  testWidgets('Motorky header: no profile button, the back stays', (t) async {
    await pumpV2(t, SingleChildScrollView(child: MotorkyHeaderV2(mode: CatalogMode.find, onMode: (_) {}, onBack: () {})));
    expect(find.byKey(const ValueKey('motorky-menu')), findsNothing);
    expect(find.byKey(const ValueKey('motorky-back')), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is MgIconButton && w.icon == MgIcons.user), findsNothing);
  });

  group('Motorky "Přejít na" with dates (FR-02)', () {
    final closed = [BookedDateRange(start: _d(0), end: _d(130), status: 'branch_closed')];
    final next = _d(131);
    final jump = find.textContaining(_cs('homeSheetJumpTo').split('{').first.trim());
    final prev = find.byWidgetPredicate((w) => w is MgIconButton && w.icon == MgIcons.chevronLeft);

    testWidgets('carried dates: the month moves, the dates stay, the button returns when paged away', (t) async {
      await pumpV2(t, const SingleChildScrollView(child: MotorkyDatesCardV2()), size: const Size(360, 1400), overrides: [
        motorkyClosedDaysProvider.overrideWithValue(closed),
        catalogFilterProvider.overrideWith((ref) => CatalogFilter(startDate: _d(6), endDate: _d(8))),
      ]);
      await t.pump();
      await t.pump();
      expect(find.textContaining(_month(_d(6))), findsOneWidget, reason: 'opens on the carried start');
      expect(jump, findsOneWidget);
      await t.tap(jump);
      await t.pumpAndSettle();
      expect(find.textContaining(_month(next)), findsOneWidget, reason: 'calendar on the first free month');
      expect(jump, findsNothing);
      final c = ProviderScope.containerOf(t.element(find.byType(MotorkyDatesCardV2)));
      expect(c.read(catalogFilterProvider).startDate, _d(6), reason: 'the selection is untouched');
      expect(c.read(catalogFilterProvider).endDate, _d(8));
      await t.tap(prev);
      await t.pumpAndSettle();
      expect(jump, findsOneWidget, reason: 'not on that month any more → the button is back');
      await t.tap(jump);
      await t.pumpAndSettle();
      expect(find.textContaining(_month(next)), findsOneWidget);
    });

    testWidgets('a picked start (no end yet) survives the jump', (t) async {
      await pumpV2(t, const SingleChildScrollView(child: MotorkyDatesCardV2()),
          size: const Size(360, 1400), overrides: [motorkyClosedDaysProvider.overrideWithValue(closed)]);
      await t.pump();
      await t.pump();
      await t.tap(jump);
      await t.pumpAndSettle();
      await t.tap(_cell(next));
      // The picked start pulses (pending start): no settling from here on.
      await t.pump(const Duration(milliseconds: 600));
      expect(t.widget<AvailabilityCalendarV2View>(find.byType(AvailabilityCalendarV2View)).start, next);
      await t.tap(prev);
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(jump);
      await t.pump(const Duration(milliseconds: 600));
      final v = t.widget<AvailabilityCalendarV2View>(find.byType(AvailabilityCalendarV2View));
      expect(v.start, next, reason: 'the start the customer picked is kept');
      expect(v.step, 2);
    });
  });

  testWidgets('Home filter card calendar: closed days disabled, "Zavřeno" in the legend, no "Obsazeno" (FR-03/05)',
      (t) async {
    final closed = [BookedDateRange(start: _d(0), end: _d(10), status: 'branch_closed')];
    await pumpV2(t, const SingleChildScrollView(child: MotoFilterPanel(showDates: true)),
        size: const Size(360, 2400), overrides: [motorkyClosedDaysProvider.overrideWithValue(closed)]);
    await t.pump();
    motoFilterOpenRequest.value++;
    await t.pumpAndSettle();
    expect(find.byType(TripCalendar), findsOneWidget);
    final today = t.widget<TripDayCell>(_cell(_d(0)));
    expect(today.state.kind, TripDayKind.closed);
    expect(today.state.enabled, isFalse);
    expect(find.text(_cs('calLegClosed')), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-legend-closed')), findsOneWidget);
    expect(find.text(_cs('v2CalLegBusy')), findsNothing, reason: 'no bookings drawn here');
    await t.tap(_cell(_d(0)));
    await t.pump();
    final c = ProviderScope.containerOf(t.element(find.byType(MotoFilterPanel)));
    expect(c.read(catalogFilterProvider).startDate, isNull, reason: 'a closed day cannot be picked');
  });

  testWidgets('closed and booked days look different (FR-05)', (t) async {
    await pumpV2(
        t,
        SingleChildScrollView(
          child: AvailabilityCalendar(bookedDates: [
            BookedDateRange(start: _d(0), end: _d(0), status: 'branch_closed'),
            BookedDateRange(start: _d(1), end: _d(1), status: 'confirmed'),
          ]),
        ),
        size: const Size(360, 1400));
    await t.pump();
    expect(t.widget<TripDayCell>(_cell(_d(0))).state.kind, TripDayKind.closed);
    if (_d(1).month == _d(0).month) expect(t.widget<TripDayCell>(_cell(_d(1))).state.kind, TripDayKind.busy);
    // Busy = the hatch; closed = its own plain slate swatch.
    expect(find.byKey(const ValueKey('trip-legend-busy-hatch')), findsOneWidget);
    final sw = t.widget<Container>(find.byKey(const ValueKey('trip-legend-closed')));
    expect((sw.decoration as BoxDecoration).color, MgColors.closedCell);
    expect(MgColors.closedCell, isNot(MgColors.hatchA));
    expect(find.text(_cs('v2CalLegBusy')), findsOneWidget);
  });

  group('plural of the count lines (FR-04)', () {
    String tr(String lang, String k) => translations[lang]![k]!;
    test('cs 1 / 2–4 / 5+ with dates and without', () {
      String free(int n) => motoFreeCount('cs', (k) => tr('cs', k), n);
      expect(free(1), '1 volná motorka');
      expect(free(3), '3 volné motorky');
      expect(free(5), '5 volných motorek');
      expect(motoShownCount('cs', (k) => tr('cs', k), 4, 'searchShownMotorcycles'), 'Zobrazeno: 4 motorky');
    });
    test('uk: 21 is singular, 11 is many, 22 few, 12 many', () {
      String free(int n) => motoFreeCount('uk', (k) => tr('uk', k), n);
      expect(free(21), tr('uk', 'motoFreeOne').replaceAll('{n}', '21'));
      expect(free(11), tr('uk', 'searchAvailableMotorcycles').replaceAll('{n}', '11'));
      expect(free(22), tr('uk', 'motoFreeFew').replaceAll('{n}', '22'));
      expect(free(12), tr('uk', 'searchAvailableMotorcycles').replaceAll('{n}', '12'));
      expect(motoShownCount('uk', (k) => tr('uk', k), 31, 'searchShownMotorcycles'), 'Показано: 31 мотоцикл');
      expect(motoCountKey('pl', 21, 'o', 'f', 'm'), 'm', reason: 'pl: only 1 is singular');
    });
  });

  group('"Zrušit vše" keeps a word on narrow phones (FR-07)', () {
    for (final w in [320.0, 360.0]) {
      testWidgets('width ${w.toInt()}', (t) async {
        var reset = 0;
        await pumpV2(t, MotorkyFilterStripV2(active: 2, onShow: () {}, onReset: () => reset++), size: Size(w, 640));
        final btn = find.byKey(const ValueKey('motorky-filter-strip-clear'));
        final word = w < 360 ? _cs('motoFltClearShort') : _cs('motoFltClear');
        expect(find.descendant(of: btn, matching: find.text(word)), findsOneWidget);
        expect(t.getSize(find.descendant(of: btn, matching: find.text(word))).height, greaterThan(8));
        expect(find.bySemanticsLabel(_cs('motoFltClear')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(btn);
        expect(reset, 1);
      });
    }
  });

  testWidgets('short card: the photo keeps its size while the nav hides (FR-06)', (t) async {
    final bikes = [
      for (var i = 1; i <= 4; i++)
        Motorcycle(id: 'p$i', model: 'Photo bike $i', category: 'cestovni', images: ['https://x/$i.jpg']),
    ];
    await pumpBarsShell(t, '/search', {'/search': (_) => const MotorkyScreenV2()},
        size: const Size(360, 640), top: 24, bottom: 0, overrides: catalogOverrides(motos: bikes));
    await t.pump(const Duration(milliseconds: 500));
    final pad = find.byKey(const ValueKey('bike-photo-pad-0'));
    final scroll = t.state<ScrollableState>(
        find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first);
    // Down to the bike cards, bars shown.
    for (var i = 0; i < 40 && pad.evaluate().isEmpty; i++) {
      scroll.position.jumpTo(scroll.position.pixels + 300);
      await t.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Back up a little so the bars show again.
    final g0 = await t.startGesture(const Offset(180, 300));
    for (var i = 0; i < 4; i++) {
      await g0.moveBy(const Offset(0, 10));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g0.up();
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(navFolded(t), isFalse);
    expect(pad, findsWidgets);
    double padOf() => (t.widget<Padding>(pad.first).padding as EdgeInsets).bottom;
    final key = find.ancestor(of: pad.first, matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('mc-'))).first;
    final cardKey = t.widget(key).key!;
    double padOfCard() => (t
            .widget<Padding>(find.descendant(of: find.byKey(cardKey), matching: pad).first)
            .padding as EdgeInsets)
        .bottom;
    final shown = padOfCard();
    expect(padOf(), greaterThan(0), reason: 'a short card fits the photo above the caption');
    // Drag up (scroll down) → the bars fold; every frame of the animation.
    final g = await t.startGesture(const Offset(180, 400));
    final seen = <double>{};
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -8));
      await t.pump(const Duration(milliseconds: 16));
      if (find.byKey(cardKey).evaluate().isNotEmpty) seen.add(padOfCard());
    }
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (find.byKey(cardKey).evaluate().isNotEmpty) seen.add(padOfCard());
    }
    expect(navFolded(t), isTrue, reason: 'the bars folded during the drag');
    expect(seen, {shown}, reason: 'the photo area never resized while the nav hid');
    await g.up();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
