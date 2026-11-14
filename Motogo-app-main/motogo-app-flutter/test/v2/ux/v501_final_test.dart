// 5.0.1 final repair: Motorky calendar says why every day is struck through
// in winter (+ "Zavřeno" in the legend, jump to the first free day); the
// closed days follow the bikes Motorky lists; Home "Vybrat jiný termín"
// opens the filter card; the AI hint times out only once seen; the Home
// offer narrows by a branch like the list; the branch chip keeps the mode
// in two lines; Czech plural of the bike count.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_65_v501_final.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_coach.dart';
import 'package:motogo_app/core/v2/widgets/mg_branch_chip.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/motorky_closed_days_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_dates_card_v2.dart';
import 'package:motogo_app/features/catalog/widgets/moto_filter_panel.dart';
import 'package:motogo_app/features/home/v2/home_offer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart';
import '../support/shell_harness.dart';
import '../support/v2_harness.dart';

String _cs(String key) => translations['cs']![key]!;
String _tr(String key) => _cs(key);

DateTime _d(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + n);
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
  });

  group('closed days follow the bikes Motorky lists (FS-02)', () {
    final closures = [HomeClosure('b1', _d(-3), _d(10))];
    test('a trailer on an open branch keeps the days free', () {
      const bike = Motorcycle(id: 'a', model: 'A', branchId: 'b1');
      const trailer = Motorcycle(id: 't', model: 'T', branchId: 'b2', isTrailer: true);
      expect(motorkyClosedDays(const [bike], closures), hasLength(1));
      expect(motorkyClosedDays(const [bike, trailer], closures), isEmpty);
    });
    test('a listed bike without a branch is never closed', () {
      const bike = Motorcycle(id: 'a', model: 'A', branchId: 'b1');
      const free = Motorcycle(id: 'n', model: 'N');
      expect(motorkyClosedDays(const [bike, free], closures), isEmpty);
      const hidden = Motorcycle(id: 'h', model: 'H', branchIsOpen: false);
      expect(motorkyClosedDays(const [bike, hidden], closures), hasLength(1), reason: 'not listed = not counted');
    });
    test('first free day after today\'s closed block', () {
      final r = [BookedDateRange(start: _d(0), end: _d(10), status: 'branch_closed')];
      expect(motorkyClosedUntil(r, DateTime.now()), _d(11));
      expect(motorkyClosedUntil([BookedDateRange(start: _d(2), end: _d(5), status: 'branch_closed')], DateTime.now()),
          isNull);
    });
  });

  testWidgets('Motorky calendar in winter: why + "Přejít na" + "Zavřeno" (FV-01)', (t) async {
    final closed = [BookedDateRange(start: _d(0), end: _d(130), status: 'branch_closed')];
    await pumpV2(
      t,
      const SingleChildScrollView(child: MotorkyDatesCardV2()),
      overrides: [motorkyClosedDaysProvider.overrideWithValue(closed)],
    );
    await t.pump();
    final next = _d(131);
    expect(find.byKey(const ValueKey('motorky-closed-row')), findsOneWidget);
    expect(find.textContaining(_cs('motoCalClosedFreeFrom').split('{').first.trim()), findsOneWidget);
    // Own plain swatch, not the taken-day hatch (5.0.1 FR-05).
    expect(find.byKey(const ValueKey('trip-legend-closed')), findsOneWidget);
    expect(find.text(_cs('calLegClosed')), findsOneWidget);
    final jump = find.textContaining(_cs('homeSheetJumpTo').split('{').first.trim());
    expect(jump, findsOneWidget, reason: 'the first free day is months away');
    await t.ensureVisible(jump);
    await t.tap(jump);
    await t.pumpAndSettle();
    final month = _tr(const [
      'calJan', 'calFeb', 'calMar', 'calApr', 'calMay', 'calJun', //
      'calJul', 'calAug', 'calSep', 'calOct', 'calNov', 'calDec',
    ][next.month - 1]);
    expect(find.textContaining('$month ${next.year}'), findsOneWidget, reason: 'calendar on the free month');
    expect(jump, findsNothing);
  });

  testWidgets('no closed day: no row, no "Zavřeno" in the legend', (t) async {
    await pumpV2(t, const SingleChildScrollView(child: MotorkyDatesCardV2()),
        overrides: [motorkyClosedDaysProvider.overrideWithValue(const [])]);
    await t.pump();
    expect(find.byKey(const ValueKey('motorky-closed-row')), findsNothing);
    expect(find.text(_cs('calLegClosed')), findsNothing);
    expect(find.byType(TripLegend), findsOneWidget);
  });

  testWidgets('Home "Vybrat jiný termín" request opens the folded filter card (FS-01)', (t) async {
    await pumpV2(
      t,
      const SingleChildScrollView(child: MotoFilterPanel(showDates: true)),
      overrides: [motorkyClosedDaysProvider.overrideWithValue(const [])],
    );
    await t.pump();
    expect(find.byType(TripCalendar), findsNothing, reason: 'folded: no calendar');
    motoFilterOpenRequest.value++;
    await t.pump();
    expect(find.byType(TripCalendar), findsOneWidget);
  });

  test('Home offer: a branch alone narrows it like the list; the pill stays 0; values key the pager (FS-04/05)',
      () async {
    Future<HomeOffer> offer(CatalogFilter f) async {
      final c = ProviderContainer(overrides: [
        ...homeOverrides(),
        catalogFilterProvider.overrideWith((ref) => f),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(homeOfferProvider, (_, __) {});
      await c.read(motorcyclesProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return sub.read();
    }

    final all = await offer(const CatalogFilter());
    final branches = {for (final m in all.bikes) m.branchId};
    expect(branches.length, greaterThan(1), reason: 'fixture: bikes on more branches');
    final b = all.bikes.first.branchId!;
    final at = await offer(CatalogFilter(branch: b));
    expect(at.bikes, isNotEmpty);
    expect(at.bikes.every((m) => m.branchId == b), isTrue);
    expect(at.filters, 0, reason: 'a branch is not a filter: no pill');
    final cat = at.bikes.first.category!;
    final k1 = (await offer(CatalogFilter(branch: b, category: cat))).filterKey;
    final k2 = (await offer(CatalogFilter(branch: b, licenseGroup: 'A'))).filterKey;
    expect(k1, isNotNull);
    expect(k1, isNot(k2), reason: 'one filter swapped for another = another list, bike 1');
  });

  testWidgets('branch chip: no room for "name · mode" → two lines with the mode (FV-02)', (t) async {
    await pumpV2(
      t,
      const Center(
        child: MgBranchChip(label: 'Velké Němčice · samoobsluha', shortLabel: 'Velké Němčice', maxWidth: 140, wrap: true),
      ),
    );
    expect(find.text('Velké Němčice'), findsOneWidget);
    expect(find.text('samoobsluha'), findsOneWidget);
    await pumpV2(
      t,
      const Center(child: MgBranchChip(label: 'Velké Němčice · samoobsluha', shortLabel: 'Velké Němčice', maxWidth: 140)),
    );
    expect(find.text('Velké Němčice'), findsOneWidget);
    expect(find.text('samoobsluha'), findsNothing, reason: 'without wrap: the name only, as before');
  });

  test('bike count: Czech / Polish / Ukrainian plural, others unchanged (FV-08)', () {
    String cs(int n) => motoShownCount('cs', _cs, n, 'searchShownMotorcycles');
    expect(cs(1), 'Zobrazeno: 1 motorka');
    expect(cs(4), 'Zobrazeno: 4 motorky');
    expect(cs(5), 'Zobrazeno: 5 motorek');
    expect(cs(12), 'Zobrazeno: 12 motorek');
    String pl(int n) => motoShownCount('pl', (k) => translations['pl']![k]!, n, 'searchShownMotorcycles');
    expect(pl(22), 'Wyświetlono: 22 motocykle');
    expect(pl(12), 'Wyświetlono: 12 motocykli');
    String en(int n) => motoShownCount('en', (k) => translations['en']![k]!, n, 'homeMotorcycleCount');
    expect(en(3), 'Shown: 3 motorcycles');
  });

  group('AI hint timeout (FS-03)', () {
    const coach = 'Zeptej se kdykoli. Jsme tu pro tebe.';
    setUp(MgAiCoach.debugReset);

    testWidgets('shown → gone by itself after shownFor, marked seen', (t) async {
      await pumpShellV2(t, '/');
      await t.pump(MgAiCoach.delay);
      await t.pump();
      await t.pump();
      expect(find.text(coach), findsOneWidget);
      await t.pump(MgAiCoach.shownFor + const Duration(milliseconds: 100));
      await t.pump();
      expect(find.text(coach), findsNothing);
      expect((await SharedPreferences.getInstance()).getBool(MgAiCoach.prefKey), isTrue);
    });

    testWidgets('never shown (AI button hidden) → not marked seen', (t) async {
      await pumpShellV2(t, '/sos');
      await t.pump(MgAiCoach.delay + MgAiCoach.shownFor + const Duration(seconds: 1));
      await t.pump();
      expect(find.text(coach), findsNothing);
      expect((await SharedPreferences.getInstance()).getBool(MgAiCoach.prefKey), isNot(isTrue));
    });
  });
}
