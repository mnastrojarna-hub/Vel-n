// 5.0.1 bike filter (owner brief): the dates (when) and the branch (where)
// are not a filter; the collapsed card is calm without filters and loud
// with them (removable chips, "Zrušit vše" = exactly what it counts); the
// Motorky list is never capped and its count line stays truthful. The old
// look keeps its own badge (activeCount, dates included).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/calendar/trip_day_state.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_moto_v2.dart' show calcStatus;
import 'package:motogo_app/features/catalog/v2/moto_filter_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_chips_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/moto_filter_panel.dart';
import 'package:motogo_app/features/home/v2/home_offer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

/// 12 bikes on two branches (copies of the fake fleet with new ids).
List<Motorcycle> fleet12() => [
      for (var i = 0; i < 12; i++)
        Motorcycle(
          id: 'f-$i',
          model: 'Bike $i',
          category: kMotos[i % 4].category,
          branchId: kMotos[i % 2].branchId,
          branchName: kMotos[i % 2].branchName,
          status: 'active',
          branchIsOpen: true,
          prices: kBmw.prices,
        ),
    ];

Future<ProviderContainer> _motorky(WidgetTester t, CatalogFilter f, {List<Override>? extra, List<Motorcycle>? motos}) async {
  await t.pumpWidget(const SizedBox());
  await pumpV2(t, const MotorkyScreenV2(),
      size: const Size(412, 3000),
      reducedMotion: true,
      overrides: [...catalogOverrides(filter: f, motos: motos), ...?extra]);
  await t.pump(const Duration(milliseconds: 600));
  return ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
}

/// Closures / next free days: none (no network in tests).
final _noReasonData = <Override>[
  homeClosuresProvider.overrideWith((ref) async => const <HomeClosure>[]),
  homeNextFreeProvider.overrideWith((ref) async => const <String, DateTime>{}),
];

/// Motorky with nothing in the list for [f] (+ [extra]).
Future<void> _empty(WidgetTester t, CatalogFilter f, List<Override> extra) async {
  await t.pumpWidget(const SizedBox());
  await pumpV2(t, const MotorkyScreenV2(),
      size: const Size(412, 3000),
      reducedMotion: true,
      overrides: [...catalogOverrides(filter: f, filtered: const []), ...extra]);
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 100)); // the closures / next free days arrive
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
    registerCatalogStrings();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  final (ws, we) = futureWeekend();

  group('F1 what counts as a filter', () {
    test('dates and branch are not counted in the new look; the old count is unchanged', () {
      final trip = CatalogFilter(branch: 'b-mezna', startDate: ws, endDate: we);
      expect(trip.filterCount, 0);
      expect(trip.activeCount, 2, reason: 'old look keeps its badge');
      final f = CatalogFilter(
          category: 'naked', licenseGroup: 'A2', minPowerKw: 30, maxSeatMm: 800, minTorqueNm: 50, maxWeightKg: 200,
          availableTodayOnly: true, branch: 'b-mezna', startDate: ws, endDate: we, usageTags: const ['x']);
      expect(f.filterCount, 7);
      final c = f.withoutFilters();
      expect(c.filterCount, 0);
      expect([c.branch, c.startDate, c.endDate, c.usageTags], ['b-mezna', ws, we, ['x']]);
    });

    test('one chip per counted filter (+ the branch as a place chip); ✕ drops exactly one', () {
      CatalogFilter? got;
      final f = CatalogFilter(category: 'naked', licenseGroup: 'A2', minPowerKw: 35, maxPowerKw: 70, branch: 'b', startDate: ws, endDate: we);
      final chips = motoFilterChips(_cs, f, set: (n) => got = n, branchName: 'MotoGo24 Mezná');
      expect(chips.where((c) => !c.place).length, f.filterCount);
      expect([for (final c in chips) c.label], [_cs.tr(MotoCategory.labelKey('naked')), 'ŘP A2', 'Výkon 35–70 kW', 'Mezná']);
      chips[2].onRemove();
      expect([got!.minPowerKw, got!.maxPowerKw, got!.category, got!.licenseGroup, got!.startDate], [null, null, 'naked', 'A2', ws]);
      chips[3].onRemove();
      expect([got!.branch, got!.filterCount], [null, 3]);
    });
  });

  test('two ✕ taps before a rebuild both stick (the chips read the live filter)', () {
    var cur = const CatalogFilter(category: 'naked', licenseGroup: 'A2');
    final chips = motoFilterChips(_cs, cur, set: (n) => cur = n, live: () => cur);
    chips[0].onRemove();
    chips[1].onRemove();
    expect([cur.category, cur.licenseGroup], [null, null]);
  });

  group('F2 + F3 the collapsed card', () {
    testWidgets('only a branch: the calm card says "Motorky na pobočce" next to its chip', (t) async {
      await _motorky(t, const CatalogFilter(branch: 'b-mezna'));
      expect(find.text(_cs.tr('motoFltAtBranch')), findsOneWidget);
      expect(find.text(_cs.tr('motoFltAll')), findsNothing);
      expect(find.text('Mezná'), findsWidgets);
    });

    testWidgets('a tap on a chip label opens the panel and keeps the filter', (t) async {
      final c = await _motorky(t, const CatalogFilter(licenseGroup: 'A2'));
      await t.tap(find.text('ŘP A2'));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2)).open, isTrue);
      expect(c.read(catalogFilterProvider).licenseGroup, 'A2');
    });

    testWidgets('dates only: calm card, no count, no reset (the dead "Resetovat" is gone)', (t) async {
      await _motorky(t, CatalogFilter(startDate: ws, endDate: we));
      final card = t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2));
      expect([card.open, card.active], [false, 0]);
      expect(find.text(_cs.tr('homeFilterTitle')), findsOneWidget);
      expect(find.text(_cs.tr('motoFltAll')), findsOneWidget);
      expect(find.text(_cs.tr('motoFltFilter')), findsOneWidget, reason: 'the calm card invites: "Filtrovat"');
      expect(find.byKey(const ValueKey('motorky-filter-strip')), findsNothing, reason: 'dates are not a filter');
      expect(find.text(_cs.tr('motoFltClear')), findsNothing);
      expect(find.text(_cs.tr('homeFilterReset')), findsNothing);
    });

    testWidgets('filters on: loud heading + chips; ✕ drops one, "Zrušit vše" keeps dates + branch', (t) async {
      final c = await _motorky(t, CatalogFilter(category: 'naked', licenseGroup: 'A2', branch: 'b-mezna', startDate: ws, endDate: we));
      final card = find.byType(MotoFilterCardV2);
      expect(find.descendant(of: card, matching: find.text(_cs.trArgs('motoFltOn', {'n': 2}))), findsOneWidget);
      expect(find.text(_cs.tr('motoFltOnHint')), findsOneWidget);
      expect(find.text('Mezná'), findsOneWidget, reason: 'branch = place chip');
      await t.tap(find.byKey(const ValueKey('moto-filter-x-ŘP A2')));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(catalogFilterProvider).licenseGroup, isNull);
      expect(find.descendant(of: card, matching: find.text(_cs.trArgs('motoFltOn', {'n': 1}))), findsOneWidget);
      expect(t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2)).open, isFalse, reason: 'a chip ✕ does not open');
      await t.tap(find.byKey(const ValueKey('moto-filter-clear')));
      await t.pump(const Duration(milliseconds: 300));
      final f = c.read(catalogFilterProvider);
      expect([f.filterCount, f.category, f.branch, f.startDate, f.endDate], [0, null, 'b-mezna', ws, we]);
      expect(find.text(_cs.tr('motoFltClear')), findsNothing);
      expect(find.text(_cs.tr('homeFilterTitle')), findsOneWidget);
      expect(find.text('Mezná'), findsWidgets, reason: 'the branch chip stays (not a filter)');
    });

    testWidgets('a tap on the heading opens the panel; open, the chips hide (the panel shows them)', (t) async {
      await _motorky(t, const CatalogFilter(category: 'naked'));
      await t.tap(find.descendant(of: find.byType(MotoFilterCardV2), matching: find.text(_cs.trArgs('motoFltOn', {'n': 1}))));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2)).open, isTrue);
      expect(t.widget<MotoFilterCardV2>(find.byType(MotoFilterCardV2)).active, 1);
      expect(find.byKey(const ValueKey('moto-filter-clear')), findsOneWidget, reason: '"Zrušit vše" stays while open');
    });

    testWidgets('the old look is unchanged: dates still count, "Resetovat" keeps them', (t) async {
      await t.pumpWidget(const SizedBox());
      await pumpV2(t, const SingleChildScrollView(child: MotoFilterPanel()),
          v2: false, overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(MotoFilterCardV2), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.text(_cs.tr('homeFilterReset')), findsOneWidget);
    });
  });

  group('Motorky says filters are on and why the list is empty', () {
    testWidgets('filters on: a strip ABOVE the calendar; its "Zrušit vše" keeps dates + branch', (t) async {
      final c = await _motorky(t, CatalogFilter(category: 'naked', minPowerKw: 30, branch: 'b-mezna', startDate: ws, endDate: we));
      final strip = find.byKey(const ValueKey('motorky-filter-strip'));
      expect(strip, findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text(_cs.trArgs('motoFltOn', {'n': 2}))), findsOneWidget);
      expect(t.getTopLeft(strip).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('motorky-dates'))).dy));
      await t.tap(find.byKey(const ValueKey('motorky-filter-strip-clear')));
      await t.pump(const Duration(milliseconds: 300));
      final f = c.read(catalogFilterProvider);
      expect([f.filterCount, f.branch, f.startDate, f.endDate], [0, 'b-mezna', ws, we]);
      expect(strip, findsNothing);
    });

    testWidgets('filters hide every bike: "Filtrům nic neodpovídá" + "Zrušit filtry (n)"', (t) async {
      await _empty(t, CatalogFilter(category: 'naked', availableTodayOnly: true, startDate: ws, endDate: we), _noReasonData);
      final c2 = ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
      expect(find.text(_cs.tr('motoFltNoneTitle')), findsOneWidget);
      expect(find.text(_cs.tr('searchNoMotorcycles')), findsNothing, reason: 'the dates are not blamed');
      await t.tap(find.text(_cs.trArgs('motoFltClearN', {'n': 2})));
      await t.pump(const Duration(milliseconds: 300));
      expect([c2.read(catalogFilterProvider).filterCount, c2.read(catalogFilterProvider).startDate], [0, ws]);
    });

    testWidgets('dates, no filter, every branch closed: the reason + the next free day', (t) async {
      final next = DateTime(we.year, we.month, we.day + 40);
      await _empty(t, CatalogFilter(startDate: ws, endDate: we), [
        homeClosuresProvider.overrideWith((ref) async => [
              HomeClosure('b-mezna', ws.subtract(const Duration(days: 3)), next),
              HomeClosure('b-vn', ws, we),
            ]),
        homeNextFreeProvider.overrideWith((ref) async => {for (final m in kMotos) m.id: next}),
      ]);
      expect(find.text(_cs.tr('motoFltClosedTitle')), findsOneWidget);
      expect(find.text(_cs.trArgs('motoFltFreeFrom', {'date': tripShortDate(_cs, next)})), findsOneWidget);
      expect(find.text(_cs.tr('motoFltPickDates')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('motorky-empty-action')));
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull, reason: 'scrolls up to the calendar');
      expect(find.byKey(const ValueKey('motorky-dates')), findsOneWidget);
    });

    testWidgets('dates, no filter, nothing closed: "vše obsazené"; a free day inside the dates is not offered', (t) async {
      await _empty(t, CatalogFilter(startDate: ws, endDate: we), [
        ..._noReasonData.take(1),
        homeNextFreeProvider.overrideWith((ref) async => {for (final m in kMotos) m.id: we}),
      ]);
      expect(find.text(_cs.tr('motoFltBookedTitle')), findsOneWidget);
      expect(find.textContaining(_cs.tr('motoFltFreeFrom').split('{').first), findsNothing);
    });
  });

  test('calculator: one "free today" wording with the list', () {
    final m = Motorcycle(id: 'x', model: 'X', status: 'active', availableToday: true);
    expect(calcStatus(_cs, m)?.$1, _cs.tr('v2CatFreeToday'));
  });

  group('F4 the list', () {
    testWidgets('12 bikes on two branches: every one is listed, the count says 12', (t) async {
      final motos = fleet12();
      await _motorky(t, const CatalogFilter(), motos: motos);
      expect(find.text(_cs.tr('searchShownMotorcycles').replaceAll('{n}', '12')), findsOneWidget);
      expect(t.widget<BikeScreenList>(find.byType(BikeScreenList)).ids, [for (final m in motos) m.id]);
    });

    testWidgets('while the list recounts for new dates the old number is not shown', (t) async {
      final pending = Completer<List<Motorcycle>>();
      final c = await _motorky(t, const CatalogFilter(), extra: [
        filteredMotorcyclesProvider.overrideWith((ref) {
          final f = ref.watch(catalogFilterProvider);
          return f.startDate == null ? Future.value(kMotos) : pending.future;
        }),
      ]);
      expect(find.text(_cs.tr('searchShownMotorcycles').replaceAll('{n}', '${kMotos.length}')), findsOneWidget);
      c.read(catalogFilterProvider.notifier).state = CatalogFilter(startDate: ws, endDate: we);
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text(_cs.tr('searchShownMotorcycles').replaceAll('{n}', '${kMotos.length}')), findsNothing);
      expect(find.text(_cs.tr('searchSearching')), findsOneWidget);
      pending.complete([kBmw]);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(_cs.tr('searchAvailableMotorcycles').replaceAll('{n}', '1')), findsOneWidget);
    });
  });
}
