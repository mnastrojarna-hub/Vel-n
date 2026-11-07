// Catalog fix round 2 (v2, Android): one trip across a tab remount and
// clears, a paid booking empties the calculator, past trips are dropped,
// a start-only booking stays local in the detail, busy carried dates are
// caught in the detail, the calculator's sticky REZERVOVAT, the detail's
// "VYBRAT TERMÍN" dock, info-only steps, the 12:00 info and the detail's
// loading / error states.
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
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_parts_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_dates_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_sticky_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_total_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_text.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_states_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_parts_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/payment/payment_provider.dart' show lastConfirmedBookingProvider;

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, String initial, List<Override> overrides) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking')),
    GoRoute(path: '/home', builder: (_, __) => const Text('home')),
  ]);
  final c = ProviderContainer(overrides: [
    rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
    rankArcPctProvider.overrideWithValue(50),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (ctx, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  await _settle(t);
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

Future<void> _top(WidgetTester t) async {
  t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
  await _settle(t);
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

Finder _tripOf(String id) => find.descendant(
    of: find.byWidgetPredicate((w) => w is MotoDetailPage && w.motoId == id), matching: find.byType(DetailTripCardV2));

Finder _ctaIn(Type t) => find.descendant(of: find.byType(t), matching: find.byType(MgCta));

(DateTime?, DateTime?) _dates(ProviderContainer c) =>
    (c.read(catalogFilterProvider).startDate, c.read(catalogFilterProvider).endDate);

(DateTime?, DateTime?) _calc(ProviderContainer c) => (c.read(calcStateProvider).start, c.read(calcStateProvider).end);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });
  setUp(MgMotion.resetSession);
  final (ws, we) = futureWeekend();
  final s2 = DateTime(ws.year, ws.month, ws.day + 7), e2 = DateTime(we.year, we.month, we.day + 7);
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true);
  final dated = CatalogFilter(startDate: ws, endDate: we);

  group('one trip', () {
    testWidgets('a calculator range is the shared trip at once and survives a tab remount', (t) async {
      final (r, c) = await _pump(t, '/search', [...catalogOverrides(), calcMode]);
      t.widget<AvailabilityCalendar>(find.byType(AvailabilityCalendar)).onRangeSelected!(ws, we);
      await _settle(t);
      expect(_dates(c), (ws, we));
      r.go('/home');
      await _settle(t);
      r.go('/search');
      await _settle(t);
      expect(c.read(catalogModeProvider), CatalogMode.find);
      expect(find.byType(CalcStepDatesV2), findsNothing);
      expect(_dates(c), (ws, we));
      await _unmount(t);
    });

    testWidgets('remount: calculator dates not yet in the list are carried; an entry with own dates wins', (t) async {
      final (r, c) = await _pump(t, '/search', [...catalogOverrides(), calcMode]);
      c.read(calcStateProvider.notifier).prefill(start: ws, end: we); // Home funnel, not written through
      await _settle(t);
      r.go('/home');
      await _settle(t);
      r.go('/search');
      await _settle(t);
      expect(_dates(c), (ws, we));
      await _unmount(t);

      final (r2, c2) = await _pump(t, '/search', [...catalogOverrides(), calcMode]);
      c2.read(calcStateProvider.notifier).prefill(start: ws, end: we);
      await _settle(t);
      r2.go('/home');
      await _settle(t);
      c2.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s2, endDate: e2); // Home pill
      r2.go('/search');
      await _settle(t);
      expect(_dates(c2), (s2, e2));
      await _unmount(t);
    });

    testWidgets('a clear is a choice: calculator "Smazat termín" ↔ list "Bez termínu"', (t) async {
      final (_, c) = await _pump(t, '/search', catalogOverrides(filter: dated));
      await _tap(t, find.text(_cs.tr('v2CatModeCalc')));
      expect(_calc(c), (ws, we));
      await _tap(t, find.descendant(of: find.byType(CalcStepDatesV2), matching: find.text(_cs.tr('v2CatDateClear'))));
      expect([_calc(c), _dates(c)], [(null, null), (null, null)]);
      await _top(t);
      await _tap(t, find.text(_cs.tr('v2CatModeFind')));
      expect(_dates(c), (null, null));
      c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: s2, endDate: e2);
      await _settle(t);
      await _tap(t, find.text(_cs.tr('v2CatModeCalc')));
      expect(_calc(c), (s2, e2));
      await _top(t);
      await _tap(t, find.text(_cs.tr('v2CatModeFind')));
      c.read(catalogFilterProvider.notifier).state = const CatalogFilter(); // "Bez termínu"
      await _settle(t);
      await _tap(t, find.text(_cs.tr('v2CatModeCalc')));
      expect(_calc(c), (null, null));
      await _unmount(t);
    });

    test('a paid booking empties the calculator\'s bike and dates (branch stays)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(calcStateProvider.notifier);
      n.setBranch('b-mezna');
      n.setMoto('m-bmw');
      n.setRange(ws, we);
      c.read(lastConfirmedBookingProvider.notifier).state = 'bk-1';
      final st = c.read(calcStateProvider);
      expect([st.branchId, st.motoId, st.start, st.end], ['b-mezna', null, null, null]);
    });

    testWidgets('a trip that already started is dropped in Motorky and never carried into a detail', (t) async {
      final now = DateTime.now();
      final ps = DateTime(now.year, now.month, now.day - 3), pe = DateTime(now.year, now.month, now.day - 1);
      final past = CatalogFilter(startDate: ps, endDate: pe);
      final (_, c) = await _pump(t, '/search', catalogOverrides(filter: past));
      expect(_dates(c), (null, null));
      await _unmount(t);
      await _pump(t, '/moto/m-bmw', catalogOverrides(filter: past));
      final trip = t.widget<DetailTripCardV2>(_tripOf('m-bmw'));
      expect([trip.selStart, trip.selEnd], [null, null]);
      await _unmount(t);
    });
  });

  group('detail', () {
    testWidgets('a start-only pick booked as one day leaves the catalog dates alone', (t) async {
      final (r, c) = await _pump(t, '/moto/m-bmw', catalogOverrides());
      t.widget<DetailTripCardV2>(_tripOf('m-bmw')).onStartSelected(ws);
      await _settle(t);
      await t.tap(_ctaIn(DetailDockV2));
      await _settle(t);
      expect(find.text('booking'), findsOneWidget);
      final d = c.read(bookingDraftProvider);
      expect([d.motoId, d.startDate, d.endDate], ['m-bmw', ws, ws]);
      expect(_dates(c), (null, null));
      r.pop();
      await _settle(t);
      final trip = t.widget<DetailTripCardV2>(_tripOf('m-bmw'));
      expect([trip.selStart, trip.selEnd], [ws, null]);
      expect(_dates(c), (null, null));
      await _unmount(t);
    });

    testWidgets('carried dates with a booked day: calendar open, warning, "Změnit termín" until a free range', (t) async {
      final (r, _) = await _pump(
          t,
          '/moto/m-husq',
          catalogOverrides(filter: dated, booked: {
            'm-husq': [BookedDateRange(start: we, end: we, status: 'confirmed')],
          }));
      var trip = t.widget<DetailTripCardV2>(_tripOf('m-husq'));
      expect([trip.busy, trip.calendarExpanded], [true, true]);
      expect(find.text(_cs.tr('v2CalcRangeBusy')), findsOneWidget);
      expect(t.widget<MgCta>(_ctaIn(DetailDockV2)).label, _cs.tr('psChangeDates'));
      await t.tap(_ctaIn(DetailDockV2));
      await _settle(t);
      expect(r.routerDelegate.currentConfiguration.uri.path, '/moto/m-husq'); // never the booking form
      trip.onRangeSelected(s2, e2);
      await _settle(t);
      trip = t.widget<DetailTripCardV2>(_tripOf('m-husq'));
      expect([trip.busy, trip.calendarExpanded], [false, false]);
      final cta = t.widget<MgCta>(_ctaIn(DetailDockV2));
      expect([cta.label, cta.onTap != null], [_cs.tr('v2CatCtaBook'), true]);
      await _unmount(t);
    });

    testWidgets('no date: dock "VYBRAT TERMÍN · od …/den" opens the date step', (t) async {
      await _pump(t, '/moto/m-bmw', catalogOverrides());
      t.widget<DetailTripCardV2>(_tripOf('m-bmw')).onToggleCalendar();
      await _settle(t);
      expect(t.widget<DetailTripCardV2>(_tripOf('m-bmw')).calendarExpanded, isFalse);
      final cta = t.widget<MgCta>(_ctaIn(DetailDockV2));
      expect(cta.label, _cs.tr('v2CalcPickDatesCta'));
      expect(cta.price, _cs.trArgs('v2CatGridFrom', {'amount': catMoney(catFromPerDay(kBmw, kLoyalty3.percent))}));
      await t.tap(_ctaIn(DetailDockV2));
      await _settle(t);
      expect(t.widget<DetailTripCardV2>(_tripOf('m-bmw')).calendarExpanded, isTrue);
      await _unmount(t);
    });

    testWidgets('② is an info row with the 12:00 saving for 2+ days', (t) async {
      await _pump(t, '/moto/m-bmw', catalogOverrides(filter: dated));
      final info = find.byType(DetailHandoverInfoV2);
      expect(find.descendant(of: info, matching: find.byType(CalcInfoBadge)), findsOneWidget);
      expect(find.descendant(of: info, matching: find.text(_cs.tr('v2LpCalcTitle'))), findsOneWidget);
      expect(find.descendant(of: info, matching: find.byType(CalcHalfInfo)), findsOneWidget);
      await _unmount(t);
      await _pump(t, '/moto/m-bmw', catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: ws)));
      expect(find.descendant(of: find.byType(DetailHandoverInfoV2), matching: find.byType(CalcHalfInfo)), findsNothing);
      await _unmount(t);
    });

    testWidgets('error names the bike; loading is a skeleton', (t) async {
      await _pump(t, '/moto/m-bmw', catalogOverrides(motosError: Exception('net')));
      expect(find.text(_cs.tr('v2DetLoadFail')), findsOneWidget);
      await _unmount(t);
      await _pump(t, '/moto/m-bmw', catalogOverrides(motosLoading: true));
      expect(find.byType(DetailLoadingV2), findsOneWidget);
      await _unmount(t);
    });
  });

  group('calculator', () {
    testWidgets('sticky REZERVOVAT while the total CTA is below the edge — the same booking', (t) async {
      final (_, c) = await _pump(t, '/search', [
        ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we)),
        calcMode,
      ]);
      expect(find.byType(CalcStickyV2), findsOneWidget);
      expect(find.byType(CalcInfoBadge), findsOneWidget); // ④ info only
      await t.ensureVisible(_ctaIn(CalcTotalV2));
      await _settle(t);
      expect(find.byType(CalcStickyV2), findsNothing);
      await _top(t);
      expect(find.byType(CalcStickyV2), findsOneWidget);
      await t.tap(_ctaIn(CalcStickyV2));
      await _settle(t);
      expect(find.text('booking'), findsOneWidget);
      final d = c.read(bookingDraftProvider);
      expect([d.motoId, d.startDate, d.endDate, d.pickupTime], ['m-bmw', ws, we, null]);
      await _unmount(t);
    });

    testWidgets('no sticky dock while REZERVOVAT is disabled (busy day)', (t) async {
      await _pump(t, '/search', [
        ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), booked: {
          'm-bmw': [BookedDateRange(start: we, end: we, status: 'confirmed')],
        }),
        calcMode,
      ]);
      expect(find.byType(CalcStickyV2), findsNothing);
      await _unmount(t);
    });
  });
}
