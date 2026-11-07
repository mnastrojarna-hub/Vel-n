// fix:r2:core — (1) photo viewer: a pinch with one finger held still zooms
// and never closes / pages; a swipe-down under way springs back when a
// second finger lands; one finger works again after. (2) Domů bookings:
// each card opens that booking (as the old Home card), "VŠE" opens the
// tab; with an unpaid booking both paid bookings stay one tap. (3) Map tiles failing: v2 strip under the header / HUD,
// never under it; same retry; flag off = the old chip unchanged.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_map_tile_strip.dart';
import 'package:motogo_app/core/v2/widgets/mg_photo_viewer.dart';
import 'package:motogo_app/core/v2/widgets/mg_section.dart';
import 'package:motogo_app/core/widgets/map_tile_errors.dart';
import 'package:motogo_app/features/home/v2/home_bookings_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/home/widgets/home_reservations_section.dart';
import 'package:motogo_app/features/routes/places_map_screen.dart';
import 'package:motogo_app/features/routes/route_builder_screen.dart';
import 'package:motogo_app/features/routes/routes_map_screen.dart';
import 'package:motogo_app/features/routes/v2/builder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/route_map_full_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

List<String> _urls(int n) => [for (var i = 0; i < n; i++) 'https://img.test/p$i.jpg'];

double _scale(WidgetTester t) =>
    t.widget<InteractiveViewer>(find.byType(InteractiveViewer).first).transformationController!.value.getMaxScaleOnAxis();

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Finger A held still, finger B moves [by] in 16 steps (a frame each).
Future<void> _fixedPinch(WidgetTester t, Offset a, Offset b, Offset by) async {
  final ga = await t.startGesture(a, pointer: 11);
  await t.pump(const Duration(milliseconds: 16));
  final gb = await t.startGesture(b, pointer: 12);
  await t.pump(const Duration(milliseconds: 16));
  for (var i = 0; i < 16; i++) {
    await gb.moveBy(by / 16);
    await t.pump(const Duration(milliseconds: 16));
  }
  await gb.up();
  await ga.up();
  await _settle(t);
}

Future<void> _routerApp(WidgetTester t, Widget home, List<Override> o, {bool v2 = true}) async {
  t.view.physicalSize = const Size(360, 780) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(path: '/reservations', builder: (_, __) => const Scaffold(body: Text('TAB /reservations'))),
    GoRoute(path: '/reservations/:id', builder: (_, s) => Scaffold(body: Text('PAGE ${s.pathParameters['id']}'))),
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
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 2400));
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

  group('photo viewer: pinch with one finger held still', () {
    Future<(List<int>, List<int>)> viewer(WidgetTester t, {bool reduced = false}) async {
      final closes = <int>[], pages = <int>[];
      await pumpV2(t, MgPhotoViewerView(urls: _urls(3), onClose: () => closes.add(1), onPage: pages.add),
          scaffold: false, reducedMotion: reduced);
      await t.pump();
      return (closes, pages);
    }

    testWidgets('B moves 160 px down → zooms, never closes', (t) async {
      final (closes, pages) = await viewer(t);
      final c = t.getCenter(find.byType(PageView));
      // B moves across the line between the fingers: the drag slop is hit
      // long before the pinch span changes (the reported failure).
      await _fixedPinch(t, c + const Offset(-60, 0), c + const Offset(60, 0), const Offset(0, 160));
      expect(_scale(t), greaterThan(1.2));
      expect(closes, isEmpty);
      expect(pages, isEmpty);
      await t.pump(const Duration(seconds: 11));
    });

    testWidgets('B moves 140 px sideways → zooms, never pages', (t) async {
      final (closes, pages) = await viewer(t);
      final c = t.getCenter(find.byType(PageView));
      await _fixedPinch(t, c + const Offset(0, -60), c + const Offset(0, 60), const Offset(-140, 0));
      expect(_scale(t), greaterThan(1.2));
      expect(pages, isEmpty);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(closes, isEmpty);
      await t.pump(const Duration(seconds: 11));
    });

    testWidgets('two fingers lifted → one-finger swipe-down closes again, swipe pages again', (t) async {
      final (closes, pages) = await viewer(t);
      final c = t.getCenter(find.byType(PageView));
      await _fixedPinch(t, c + const Offset(-60, 0), c + const Offset(60, 0), Offset.zero);
      expect(_scale(t), closeTo(1, 0.01));
      await t.fling(find.byType(PageView), const Offset(-250, 0), 1000);
      await _settle(t);
      expect(pages, [1]);
      await t.timedDrag(find.byType(PageView), const Offset(0, 150), const Duration(milliseconds: 500));
      await _settle(t);
      expect(closes, [1]);
      await t.pump(const Duration(seconds: 11));
    });

    testWidgets('page swipe under way + second finger → still settles on a whole page', (t) async {
      final (closes, _) = await viewer(t);
      final c = t.getCenter(find.byType(PageView));
      final ga = await t.startGesture(c, pointer: 31);
      for (var i = 0; i < 8; i++) {
        await ga.moveBy(const Offset(-12, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      final gb = await t.startGesture(c + const Offset(60, 80), pointer: 32);
      await t.pump(const Duration(milliseconds: 16));
      await ga.up();
      await gb.up();
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final page = t.widget<PageView>(find.byType(PageView)).controller!.page!;
      expect(page, closeTo(page.roundToDouble(), 0.001));
      expect(closes, isEmpty);
      await t.pump(const Duration(seconds: 11));
    });

    for (final reduced in [false, true]) {
      testWidgets('swipe-down under way + second finger → springs back, no close (reduced=$reduced)', (t) async {
        final (closes, _) = await viewer(t, reduced: reduced);
        final c = t.getCenter(find.byType(PageView));
        final ga = await t.startGesture(c, pointer: 21);
        for (var i = 0; i < 6; i++) {
          await ga.moveBy(const Offset(0, 10));
          await t.pump(const Duration(milliseconds: 16));
        }
        final gb = await t.startGesture(c + const Offset(80, 80), pointer: 22);
        await t.pump(const Duration(milliseconds: 16));
        for (var i = 0; i < 10; i++) {
          await ga.moveBy(const Offset(0, 12));
          await t.pump(const Duration(milliseconds: 16));
        }
        await ga.up();
        await gb.up();
        await _settle(t);
        expect(closes, isEmpty);
        // Background back to full black (the drag offset is gone).
        final m = t.widget<Material>(
            find.descendant(of: find.byType(MgPhotoViewerView), matching: find.byType(Material)).first);
        expect(m.color, MgColors.black(1));
        await t.pump(const Duration(seconds: 11));
      });
    }
  });

  group('Domů bookings — each booking one tap (old Home cards, lookonly-fix:core)', () {
    testWidgets('s6: second card → its detail; "VŠE" → Rezervace tab', (t) async {
      final o = homeCases()['s6']!();
      await _routerApp(t, const HomeScreenV2(), o);
      final cards = find.byType(HomeBookingCardV2);
      expect(cards, findsNWidgets(2));
      final r = t.widget<HomeBookingCardV2>(cards.at(1)).reservation;
      await t.ensureVisible(cards.at(1));
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(cards.at(1));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('PAGE ${r.id}'), findsOneWidget);
    });

    testWidgets('s6: "VŠE" → Rezervace tab (44 px hit)', (t) async {
      await _routerApp(t, const HomeScreenV2(), homeCases()['s6']!());
      final all = find.ancestor(of: find.text('VŠE'), matching: find.byType(MgTextLink));
      await t.ensureVisible(all);
      await t.pump(const Duration(milliseconds: 600));
      expect(t.getSize(all).height, greaterThanOrEqualTo(44));
      await t.tap(all);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('TAB /reservations'), findsOneWidget);
    });

    testWidgets('s2 (unpaid) + 2 paid → the 2 paid cards, each opens its booking; no unpaid card', (t) async {
      for (final second in [false, true]) {
        await t.pumpWidget(const SizedBox());
        await _routerApp(t, const HomeScreenV2(), homeCases()['s2-paid2']!());
        final cards = find.byType(HomeBookingCardV2);
        expect(cards, findsNWidgets(2));
        final f = cards.at(second ? 1 : 0);
        final r = t.widget<HomeBookingCardV2>(f).reservation;
        expect(r.paymentStatus, 'paid');
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 600));
        expect(t.getSize(f).height, greaterThanOrEqualTo(44));
        await t.tap(f);
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        expect(find.text('PAGE ${r.id}'), findsOneWidget, reason: 'second=$second');
      }
    });

    testWidgets('v1 parity: the second old Home card opens the same route', (t) async {
      final a = res('b6', status: 'reserved', from: 5, to: 7);
      final b = res('b7', status: 'reserved', from: 12, to: 14);
      await _routerApp(t, SingleChildScrollView(child: HomeReservationsSection(activeReservations: [a, b])), const [],
          v2: false);
      await t.tap(find.textContaining(b.dateRange));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('PAGE ${b.id}'), findsOneWidget);
    });
  });

  group('map tiles failing', () {
    setUpAll(() => HttpOverrides.global = RtFakeHttpOverrides());
    setUp(() => MapTileErrors.failingSince.value = DateTime(2026, 11, 7));
    tearDown(MapTileErrors.retry);

    Widget card(Widget chip) => SizedBox(height: 200, child: Stack(children: [const SizedBox.expand(), chip]));

    testWidgets('card map: v2 strip at the top (8), same text; retry = MapTileErrors.retry', (t) async {
      // 320: the narrow layout (link under the text) never stretches either.
      await pumpV2(t, card(const MapTileErrorChip()), size: const Size(320, 690));
      expect(t.getSize(find.byType(MgMapTileStrip)).height, lessThan(120), reason: 'never stretched to the map');
      await pumpV2(t, card(const MapTileErrorChip()));
      expect(find.byType(MgMapTileStrip), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(t.getSize(find.byType(MgMapTileStrip)).height, lessThan(120), reason: 'never stretched to the map');
      final box = t.getTopLeft(find.byType(MgMapTileStrip)).dy - t.getTopLeft(find.byType(Stack).first).dy;
      expect(box, closeTo(8, 0.5));
      expect(find.textContaining('Mapové podklady'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('map-tiles-retry-v2')));
      await t.pump();
      expect(MapTileErrors.failingSince.value, isNull);
      expect(find.byType(MgMapTileStrip), findsNothing);
    });

    testWidgets('inset: strip at its top; inset without top = chip stays out (chrome shows it)', (t) async {
      await pumpV2(t, card(const MapTileErrorInset(top: 70, child: MapTileErrorChip())));
      expect(find.byType(MgMapTileStrip), findsOneWidget, reason: 'drawn over the map, the chip stays out');
      final dy = t.getTopLeft(find.byType(MgMapTileStrip)).dy - t.getTopLeft(find.byType(Stack).first).dy;
      expect(dy, closeTo(70, 0.5));
      expect(t.getSize(find.byType(MgMapTileStrip)).height, lessThan(120), reason: 'never stretched to the map');
      await pumpV2(t, card(const MapTileErrorInset(child: MapTileErrorChip())));
      expect(find.byType(MgMapTileStrip), findsNothing);
    });

    testWidgets('flag off: the old chip (dark pill + TextButton), inset ignored', (t) async {
      await pumpV2(t, card(const MapTileErrorInset(child: MapTileErrorChip())), v2: false);
      expect(find.byType(MgMapTileStrip), findsNothing);
      expect(find.byType(TextButton), findsOneWidget);
      await t.tap(find.byType(TextButton));
      await t.pump();
      expect(MapTileErrors.failingSince.value, isNull);
    });

    Future<void> belowBack(WidgetTester t, Widget screen) async {
      await pumpV2(t, screen, overrides: routesOverrides(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(MgMapTileStrip), findsOneWidget, reason: '$screen: exactly one strip');
      final strip = t.getRect(find.byType(MgMapTileStrip));
      final back = t.getRect(find.byType(MgV2Back).first);
      expect(strip.top, greaterThanOrEqualTo(back.bottom), reason: '$screen: strip under the header');
      await rtEnd(t);
      MapTileErrors.failingSince.value = DateTime(2026, 11, 7);
    }

    testWidgets('places map / routes map: one strip, under the header', (t) async {
      await belowBack(t, const PlacesMapScreen());
      await belowBack(t, const RoutesMapScreen());
    });

    testWidgets('planner: strip under the top bar (title not covered)', (t) async {
      await belowBack(t, RouteBuilderScreen(route: kRtRoutes.first));
      await pumpV2(t, RouteBuilderScreen(route: kRtRoutes.first),
          overrides: routesOverrides(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 600));
      final bar = t.getRect(find.byType(BuilderTopBarV2));
      final strip = t.getRect(find.byType(MgMapTileStrip));
      final title = t.getRect(find.descendant(of: find.byType(BuilderTopBarV2), matching: find.byType(Text)).last);
      expect(strip.top, greaterThanOrEqualTo(title.bottom));
      expect(strip.top, closeTo(bar.bottom, 0.5));
      await rtEnd(t);
    });

    testWidgets('full route map: strip under the title header', (t) async {
      await pumpV2(
          t,
          RouteFullMapV2(
              map: const Stack(children: [SizedBox.expand(), MapTileErrorChip()]),
              title: 'Rajhrad a Židlochovicko',
              sub: '5 míst · Okruh · 40 km',
              onClose: () {}),
          scaffold: false);
      expect(find.byType(MgMapTileStrip), findsOneWidget);
      final strip = t.getRect(find.byType(MgMapTileStrip));
      expect(strip.top, greaterThanOrEqualTo(t.getRect(find.text('5 míst · Okruh · 40 km')).bottom));
    });
  });
}
