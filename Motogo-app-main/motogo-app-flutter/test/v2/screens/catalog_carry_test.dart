// Owner 2026-10-22 "nikdy nic vyplňovat dvakrát" — the Motorky tab keeps
// ONE trip: "Najít motorku" ↔ "Spočítat cenu" carry dates + branch (never
// dropping the calculator's bike), the calculator's "Detail ›" opens the
// detail with its dates, dates picked in a detail follow to the next bike
// of the pager, the list and back into the calculator; the calculator's
// date step folds a given range into summary + "Změnit". Flag OFF: the old
// detail keeps its dates local.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_dates_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode_sync.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester t, String initial, List<Override> overrides, {bool v2 = true}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/search', builder: (_, __) => const MotorkyScreenV2()),
    GoRoute(path: '/moto/:id', builder: (_, s) => MotoDetailScreen(motoId: s.pathParameters['id']!)),
    GoRoute(path: '/booking', builder: (_, __) => const Text('booking')),
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
        enabled: v2,
        child: MediaQuery(data: MediaQuery.of(ctx).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  await (v2 ? _settle(t) : _frames(t));
  return (router, c);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

Future<void> _frames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 800));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _settle(t);
}

/// Back to the top of the Motorky page (the mode switch scrolls away).
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

(DateTime?, DateTime?) _dates(ProviderContainer c) =>
    (c.read(catalogFilterProvider).startDate, c.read(catalogFilterProvider).endDate);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });
  setUp(MgMotion.resetSession);
  final (ws, we) = futureWeekend();
  final s2 = DateTime(ws.year, ws.month, ws.day + 7), e2 = DateTime(we.year, we.month, we.day + 7);
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true);

  testWidgets('list → calculator: dates + branch carried, date step folded, "Změnit" reopens it', (t) async {
    final (_, c) = await _pump(t, '/search',
        catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we, branch: 'b-mezna')));
    await _tap(t, find.text(_cs.tr('v2CatModeCalc')));
    final st = c.read(calcStateProvider);
    expect([st.start, st.end, st.branchId], [ws, we, 'b-mezna']);
    final step = find.byType(CalcStepDatesV2);
    expect(find.descendant(of: step, matching: find.byType(TripSummaryRow)), findsOneWidget);
    expect(find.descendant(of: step, matching: find.byType(AvailabilityCalendar)), findsNothing);
    await _tap(t, find.descendant(of: step, matching: find.text(_cs.tr('v2DetChange'))));
    expect(find.descendant(of: step, matching: find.byType(AvailabilityCalendar)), findsOneWidget);
    // A new range picked in the reopened calendar folds it again.
    t.widget<AvailabilityCalendar>(find.byType(AvailabilityCalendar)).onRangeSelected!(s2, e2);
    await _settle(t);
    expect([c.read(calcStateProvider).start, c.read(calcStateProvider).end], [s2, e2]);
    expect(find.descendant(of: step, matching: find.byType(AvailabilityCalendar)), findsNothing);
    // …and back in the list the calculator's newer dates are shown.
    await _top(t);
    await _tap(t, find.text(_cs.tr('v2CatModeFind')));
    expect(_dates(c), (s2, e2));
    await _unmount(t);
  });

  testWidgets('calculator → list: its dates + branch become the list filter', (t) async {
    final (_, c) = await _pump(t, '/search', [
      ...catalogOverrides(calc: CalcState(branchId: 'b-vn', start: s2, end: e2)),
      calcMode,
    ]);
    expect(find.byType(CalcStepDatesV2), findsOneWidget);
    await _tap(t, find.text(_cs.tr('v2CatModeFind')));
    final f = c.read(catalogFilterProvider);
    expect([f.startDate, f.endDate, f.branch], [s2, e2, 'b-vn']);
    await _unmount(t);
  });

  testWidgets('list branch never drops the bike picked in the calculator', (t) async {
    final (_, c) = await _pump(t, '/search', [
      ...catalogOverrides(
        calc: const CalcState(motoId: 'm-bmw'), // Mezná
        filter: CatalogFilter(startDate: ws, endDate: we, branch: 'b-vn'),
      ),
    ]);
    await _tap(t, find.text(_cs.tr('v2CatModeCalc')));
    var st = c.read(calcStateProvider);
    expect([st.motoId, st.branchId, st.start, st.end], ['m-bmw', null, ws, we]);
    // Same branch as the bike → taken over, bike kept.
    await _tap(t, find.text(_cs.tr('v2CatModeFind')));
    c.read(catalogFilterProvider.notifier).state = c.read(catalogFilterProvider).copyWith(branch: () => 'b-mezna');
    await _tap(t, find.text(_cs.tr('v2CatModeCalc')));
    st = c.read(calcStateProvider);
    expect([st.motoId, st.branchId], ['m-bmw', 'b-mezna']);
    await _unmount(t);
  });

  testWidgets('calculator "Detail ›" → detail with its dates; a new pick there comes back to the calculator', (t) async {
    final (r, c) = await _pump(t, '/search', [
      ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we)),
      calcMode,
    ]);
    await _tap(t, find.text('${_cs.tr('v2CalcDetail')} ›'));
    expect(_dates(c), (ws, we));
    var trip = t.widget<DetailTripCardV2>(_tripOf('m-bmw'));
    expect([trip.selStart, trip.selEnd, trip.calendarExpanded], [ws, we, false]);
    trip.onRangeSelected(s2, e2);
    await _settle(t);
    expect(_dates(c), (s2, e2));
    r.pop();
    await _settle(t);
    expect([c.read(calcStateProvider).start, c.read(calcStateProvider).end], [s2, e2]);
    await _unmount(t);
  });

  testWidgets('detail pager: dates picked on one bike are already set on the next; reset clears both', (t) async {
    final (_, c) = await _pump(t, '/moto/m-bmw', [
      ...catalogOverrides(),
      filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq']),
    ]);
    t.widget<DetailTripCardV2>(_tripOf('m-bmw')).onRangeSelected(ws, we);
    await _settle(t);
    expect(_dates(c), (ws, we));
    await t.fling(find.byType(PageView).first, const Offset(-380, 0), 1500);
    await _settle(t);
    final trip = t.widget<DetailTripCardV2>(_tripOf('m-husq'));
    expect([trip.selStart, trip.selEnd, trip.calendarExpanded], [ws, we, false]);
    trip.onReset();
    await _settle(t);
    expect(_dates(c), (null, null));
    await _unmount(t);
  });

  testWidgets('flag OFF: the old detail keeps a picked range local', (t) async {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(412, 3200) * 2;
    await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
        v2: false, size: const Size(412, 3200), overrides: catalogOverrides());
    await _frames(t);
    t.widget<AvailabilityCalendar>(find.byType(AvailabilityCalendar)).onRangeSelected!(ws, we);
    await _frames(t);
    final c = ProviderScope.containerOf(t.element(find.byType(MotoDetailPage)));
    expect(_dates(c), (null, null));
    await _unmount(t);
  });

  test('filterFromCalc: only given values, nothing cleared', () {
    final f = CatalogFilter(startDate: ws, endDate: we, branch: 'b-mezna', category: 'cestovni');
    expect(filterFromCalc(const CalcState(), f), isNull);
    expect(filterFromCalc(CalcState(start: ws), f), isNull); // end still pending
    final n = filterFromCalc(CalcState(branchId: 'b-vn', start: s2, end: e2), f)!;
    expect([n.startDate, n.endDate, n.branch, n.category], [s2, e2, 'b-vn', 'cestovni']);
  });
}
