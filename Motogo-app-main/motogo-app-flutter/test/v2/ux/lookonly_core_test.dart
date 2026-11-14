// lookonly-fix:core (owner 2026-11-07 "jen upgrade vzhledu"): the v2 shell
// and Domů show the SAME content, actions, defaults and order as the
// original app — nav on every shell route (hidden only with the keyboard),
// the AI button on Domů only, the unpaid-booking strip on Domů too; Domů =
// header (menu → Profil, pilot → nickname, search → Rezervovat), rank card,
// active bookings (≤ 2, each → detail, VŠE, empty row → Rezervovat) + SOS,
// the collapsed filter with the calendar, the count and the FULL list,
// scroll-to-top. Kept owner requests: funnel without a paid booking (V21
// #3), calculator row (V21 #2), "Zaznamenat jízdu" (R3).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/motion/mg_sticky_slide.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/shell_nav_map.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/catalog/widgets/moto_card.dart';
import 'package:motogo_app/features/catalog/widgets/moto_filter_panel.dart';
import 'package:motogo_app/features/home/home_screen.dart';
import 'package:motogo_app/features/home/v2/home_bookings_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_record_row_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import '../support/shell_harness.dart';
import '../support/v2_harness.dart';

const _pages = ['/profile', '/search', '/reservations', '/sos', '/messages', '/my-experiences'];

Future<GoRouter> _app(WidgetTester t, Widget home, List<Override> o, {bool v2 = true, bool reduced = true}) async {
  t.view.physicalSize = const Size(360, 780) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    for (final p in _pages) GoRoute(path: p, builder: (_, __) => Scaffold(body: Text('PAGE $p'))),
    GoRoute(path: '/reservations/:id', builder: (_, s) => Scaffold(body: Text('RES ${s.pathParameters['id']}'))),
    GoRoute(path: '/moto/:id', builder: (_, s) => Scaffold(body: Text('MOTO ${s.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      ...o,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2 ? v2TestTheme() : legacyTestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: reduced),
          child: child!,
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 2400));
  return router;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 1));
}

Future<void> _tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(f, warnIfMissed: false);
  await _settle(t);
}

double _dy(WidgetTester t, Finder f) => t.getTopLeft(f.first).dy;

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

  group('shell = old AppShell', () {
    const focused = ['/moto/abc', '/booking', '/payment', '/sos/payment', '/reservations/x/edit', '/ai-agent', '/messages/abc', '/checkout'];
    for (final p in focused) {
      testWidgets('$p keeps the nav (one tap to Domů)', (t) async {
        await pumpShellV2(t, p, paths: [...kShellTestPaths, p], prefs: const {'mg_v2_ai_coach_seen': true});
        final slot = find.ancestor(of: find.byType(V2NavBar), matching: find.byType(MgStickySlide));
        expect(t.widget<MgStickySlide>(slot).visible, isTrue);
        expect(t.getSize(slot).height, greaterThan(60));
        await t.tap(find.text(t.element(slot).tr('v2TabHome')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('PAGE /'), findsOneWidget);
      });
    }

    for (final reduced in [false, true]) {
      testWidgets('the keyboard hides the nav, closing it brings it back (reduced=$reduced)', (t) async {
        await pumpShellV2(t, '/search', reducedMotion: reduced);
        final slot = find.ancestor(of: find.byType(V2NavBar), matching: find.byType(MgStickySlide));
        expect(t.getSize(slot).height, greaterThan(60));
        t.view.viewInsets = const FakeViewPadding(bottom: 600);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(t.widget<MgStickySlide>(slot).visible, isFalse);
        expect(t.getSize(slot).height, 0);
        t.view.resetViewInsets();
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(t.widget<MgStickySlide>(slot).visible, isTrue);
        expect(t.getSize(slot).height, greaterThan(60));
      });
    }

    test('AI button only on Domů (old app: the Home FAB only)', () {
      expect(v2FabHiddenFor('/'), isFalse);
      expect(v2FabHiddenFor('/?x=1'), isFalse);
      for (final p in ['/search', '/reservations', '/reservations/x', '/profile', '/messages', '/pobocky', '/invoices', '/routes', '/sos']) {
        expect(v2FabHiddenFor(p), isTrue, reason: p);
      }
    });

    for (final at in ['/', '/search', '/profile']) {
      testWidgets('AI button visible ${at == '/' ? 'on' : 'NOT on'} $at', (t) async {
        await pumpShellV2(t, at, prefs: const {'mg_v2_ai_coach_seen': true});
        expect(t.widget<MgAiFab>(find.byType(MgAiFab)).hidden, at != '/');
      });
    }

    testWidgets('unpaid booking: the payment strip shows on Domů too (pay + cancel live there only)', (t) async {
      final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
      await pumpShellV2(t, '/', pending: pending, prefs: const {'mg_v2_ai_coach_seen': true});
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(MgStatusStrip), findsOneWidget);
      expect(find.text('Zaplatit rezervaci'), findsOneWidget); // P2-04 (was "Dokončit rezervaci")
    });
  });

  group('Domů v2 = old Domů', () {
    testWidgets('block order: header → rank → bookings → SOS → filter → count → full list (both looks)', (t) async {
      final o = homeCases()['s8-rec']!();
      await _app(t, const HomeScreenV2(), o);
      final ys = [
        _dy(t, find.byKey(const ValueKey('home-menu'))),
        _dy(t, find.byKey(const ValueKey('home-rank-card'))),
        _dy(t, find.text('Aktivní rezervace')),
        _dy(t, find.byType(HomeBookingCardV2)),
        _dy(t, find.byKey(const ValueKey('home-sos-card'))),
        _dy(t, find.byType(MotoFilterPanel)),
        _dy(t, find.byKey(const ValueKey('home-bike-count'))),
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: 'block $i');
      }
      // No v2-only Home blocks (ticket, funnel with a paid booking).
      expect(find.byType(HomeFunnelV2), findsNothing);

      await t.pumpWidget(const SizedBox());
      await _app(t, const HomeScreen(), homeCases()['s8-rec']!(), v2: false);
      final old = [
        _dy(t, find.text('Aktivní rezervace')),
        _dy(t, find.textContaining('NEHODA')),
        _dy(t, find.text('Filtr motorek')),
        _dy(t, find.textContaining('Zobrazeno:')),
      ];
      for (var i = 1; i < old.length; i++) {
        expect(old[i], greaterThan(old[i - 1]), reason: 'old block $i');
      }
    });

    testWidgets('header: menu → Profil, search → Rezervovat, pilot → nickname dialog', (t) async {
      var r = await _app(t, const HomeScreenV2(), homeCases()['s6']!());
      expect(find.text('PILOT: Jan'), findsOneWidget);
      await _tapVisible(t, find.byKey(const ValueKey('home-menu')));
      expect(r.routerDelegate.currentConfiguration.uri.path, '/profile');
      r.go('/');
      await _settle(t);
      await _tapVisible(t, find.byKey(const ValueKey('home-search')));
      expect(r.routerDelegate.currentConfiguration.uri.path, '/search');
      r.go('/');
      await _settle(t);
      await _tapVisible(t, find.byKey(const ValueKey('home-pilot')));
      expect(find.byType(Dialog).evaluate().isNotEmpty || find.byType(AlertDialog).evaluate().isNotEmpty, isTrue);
      await t.pumpWidget(const SizedBox());
      r = await _app(t, const HomeScreen(), homeCases()['s6']!(), v2: false);
      expect(find.text('Jan'), findsOneWidget);
    });

    testWidgets('bookings: ≤ 2 paid cards, each → its detail; VŠE → Rezervace (both looks)', (t) async {
      final o = homeCases()['s2-paid2']!();
      for (final v2 in [true, false]) {
        await t.pumpWidget(const SizedBox());
        final r = await _app(t, v2 ? const HomeScreenV2() : const HomeScreen(), o, v2: v2);
        // The unpaid booking is not a Home card (it lives on the shell strip).
        expect(find.textContaining('Zaplatit'), findsNothing, reason: 'v2=$v2');
        final cards = v2 ? find.byType(HomeBookingCardV2) : find.textContaining(' · ');
        expect(cards.evaluate().length, greaterThanOrEqualTo(2), reason: 'v2=$v2');
        if (v2) expect(find.byType(HomeBookingCardV2), findsNWidgets(2));
        final second = res('b7', status: 'reserved', from: 12, to: 14);
        await _tapVisible(t, v2 ? find.byType(HomeBookingCardV2).at(1) : find.textContaining(second.dateRange).first);
        expect(find.textContaining('RES b7'), findsOneWidget, reason: 'v2=$v2');
        r.go('/');
        await _settle(t);
        await _tapVisible(t, find.text('VŠE'));
        expect(r.routerDelegate.currentConfiguration.uri.path, '/reservations', reason: 'v2=$v2');
      }
    });

    testWidgets('no paid booking: "Žádná aktivní rezervace" row → Rezervovat, plus the funnel (V21 #3)', (t) async {
      final r = await _app(t, const HomeScreenV2(), homeCases()['s0']!());
      expect(find.byType(HomeFunnelV2), findsOneWidget);
      expect(find.byKey(const ValueKey('home-sos-card')), findsNothing);
      await _tapVisible(t, find.byKey(const ValueKey('home-no-booking')));
      expect(r.routerDelegate.currentConfiguration.uri.path, '/search');
    });

    testWidgets('SOS card while a booking allows SOS → SOS (push)', (t) async {
      final r = await _app(t, const HomeScreenV2(), homeCases()['s8-rec']!());
      await _tapVisible(t, find.byKey(const ValueKey('home-sos-card')));
      expect(find.text('PAGE /sos'), findsOneWidget);
      r.pop();
      await _settle(t);
      expect(find.byKey(const ValueKey('home-sos-card')), findsOneWidget);
    });

    testWidgets('filter: collapsed by default (both looks), the header opens it with the calendar', (t) async {
      for (final v2 in [true, false]) {
        await t.pumpWidget(const SizedBox());
        await _app(t, v2 ? const HomeScreenV2() : const HomeScreen(), homeCases()['s6']!(), v2: v2);
        expect(find.byType(AvailabilityCalendar), findsNothing, reason: 'v2=$v2');
        await _tapVisible(t, find.text('Filtr motorek'));
        await t.pump(const Duration(milliseconds: 600));
        expect(find.byType(AvailabilityCalendar), findsOneWidget, reason: 'v2=$v2');
      }
      // v2 (5.0.1, owner): "Zrušit vše" on the collapsed card clears exactly
      // the real filters it counts — the dates (when I ride) and the sort stay.
      await t.pumpWidget(const SizedBox());
      await _app(t, const HomeScreenV2(), homeCases()['s6']!());
      final c = ProviderScope.containerOf(t.element(find.byType(HomeScreenV2)));
      c.read(catalogFilterProvider.notifier).state = CatalogFilter(category: 'naked', startDate: day(3), endDate: day(5));
      c.read(catalogSortProvider.notifier).state = 'price_asc';
      await _settle(t);
      expect(find.byType(AvailabilityCalendar), findsNothing);
      await _tapVisible(t, find.text(t.element(find.byType(HomeScreenV2)).tr('motoFltClear')));
      expect(c.read(catalogFilterProvider).filterCount, 0);
      expect(c.read(catalogFilterProvider).category, isNull);
      expect(c.read(catalogFilterProvider).startDate, day(3));
      expect(c.read(catalogSortProvider), 'price_asc');
    });

    testWidgets('count line + the FULL list (every bike), card → detail with the pager order', (t) async {
      for (final v2 in [true, false]) {
        await t.pumpWidget(const SizedBox());
        await _app(t, v2 ? const HomeScreenV2() : const HomeScreen(), homeCases()['s6']!(), v2: v2);
        expect(find.text('Zobrazeno: ${kMotos.length} motorek'), findsOneWidget, reason: 'v2=$v2');
        final last = kMotos.last;
        final card = v2 ? find.byKey(ValueKey('home-mc-${last.id}')) : find.byType(MotoCard).last;
        await t.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 80);
        await t.pump(const Duration(milliseconds: 400));
        expect(card, findsOneWidget, reason: 'v2=$v2');
        if (!v2) continue;
        await t.tap(find.descendant(of: card, matching: find.text(last.model)).first, warnIfMissed: false);
        await _settle(t);
        expect(find.text('MOTO ${last.id}'), findsOneWidget);
        final c = ProviderScope.containerOf(t.element(find.textContaining('MOTO')));
        expect(c.read(filteredMotoIdsProvider).length, kMotos.length);
      }
    });

    for (final reduced in [false, true]) {
      testWidgets('scroll-to-top once the first bike is left (v5.0.1), tap → top (reduced=$reduced)', (t) async {
        await _app(t, const HomeScreenV2(), homeCases()['s6']!(), reduced: reduced);
        final btn = find.byKey(const ValueKey('mg-to-top'));
        double opacity() => t.widget<AnimatedOpacity>(find.ancestor(of: btn, matching: find.byType(AnimatedOpacity))).opacity;
        expect(opacity(), 0);
        // v5.0.1 (`MgToTopLayer`): shown once the first bike is left (the
        // old 600 px rule only on pages without a bike list); it folds with
        // the hide-on-scroll chrome like before — a little scroll up brings
        // the bars and it back.
        final z = t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;
        t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(z.offsetOf(1) + 60);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.drag(find.byType(Scrollable).first, const Offset(0, 40));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(opacity(), 1);
        await t.tap(btn);
        await t.pump();
        await t.pump(Duration(milliseconds: reduced ? 16 : 600));
        final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
        expect(pos.pixels, 0);
        await t.pump(const Duration(milliseconds: 400));
        expect(opacity(), 0);
      });
    }

    testWidgets('kept owner requests in every state: calculator row (V21 #2) + Zaznamenat jízdu (R3)', (t) async {
      for (final s in ['s0', 's6']) {
        await t.pumpWidget(const SizedBox());
        await _app(t, const HomeScreenV2(), homeCases()[s]!());
        expect(find.byKey(const ValueKey('home-calc-row')), findsOneWidget, reason: s);
        expect(find.byType(HomeRecordRowV2), findsOneWidget, reason: s);
        expect(find.byType(HomeFunnelV2), s == 's0' ? findsOneWidget : findsNothing, reason: s);
      }
    });

    testWidgets('rank card = old card facts: MŮJ RANK, %, level line, next rank, rules sheet', (t) async {
      await _app(t, const HomeScreenV2(), homeCases()['s6']!());
      expect(find.text(t.element(find.byType(HomeScreenV2)).tr('loyaltyMyRank').toUpperCase()), findsOneWidget);
      expect(find.byKey(const ValueKey('home-rank-pct')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-rank-level')), findsOneWidget);
      await _tapVisible(t, find.byKey(const ValueKey('home-rank-info')));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(t.element(find.byType(HomeScreenV2)).tr('loyaltyRuleCombo')), findsOneWidget);
    });
  });
}

extension on BuildContext {
  String tr(String key) => t(this).tr(key);
}
