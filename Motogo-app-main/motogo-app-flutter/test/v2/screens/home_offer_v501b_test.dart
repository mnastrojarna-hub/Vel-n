// v5.0.1 Home offer card, repair round 2: the real batch check (first
// bikes, then the rest), a new order re-sorts without new checks, a failed
// check is "Zkusit znovu" (never "vše obsazené"), the pill never says
// "free" next to "all booked", a second tap on the ticked weekend clears
// the dates, and a bike's calendar opens with nothing ticked (+ a jump to
// its first free day). Weekday / time independent (dates relative to today).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/home/v2/funnel_carousel_v2.dart';
import 'package:motogo_app/features/home/v2/funnel_dates.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_date_sheet_v2.dart';
import 'package:motogo_app/features/home/v2/home_funnel_cta.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_offer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart';
import '../support/v2_harness.dart';
import 'home_offer_v501_test.dart' show fleet;
import 'home_test.dart' show homeCases, homeOfferOverrides;

String _cs(String key) => translations['cs']![key]!;
const _funnel = SingleChildScrollView(child: HomeFunnelV2());

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

ProviderContainer _c(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(HomeFunnelV2)));

List<String> _ids(WidgetTester t) =>
    t.widgetList<FunnelBikeCard>(find.byType(FunnelBikeCard, skipOffstage: false)).map((c) => c.moto.id).toList();

Finder _ring() => find.byKey(const ValueKey('funnel-pager-more'));

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  final r = FunnelRange(day(9), day(11));

  testWidgets('batches: the first 6 show with a ring, then the real count; a new order needs no new check', (t) async {
    final gate = Completer<void>();
    var calls = 0;
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: [
      ...homeOverrides(motos: fleet(12), realFunnel: true),
      ...homeOfferOverrides(given: r),
      homeRangeCheckProvider.overrideWithValue((id, range) async {
        calls++;
        if (calls > 6) await gate.future;
        return MotoAvailability.free;
      }),
    ]);
    await _frames(t);
    expect(find.text('1 / 6'), findsOneWidget);
    expect(_ring(), findsOneWidget);
    gate.complete();
    await _frames(t);
    expect(find.text('1 / 12'), findsOneWidget);
    expect(_ring(), findsNothing);
    expect(calls, 12);
    final before = _ids(t);
    _c(t).read(homeOfferSeedProvider.notifier).state = 7;
    await _frames(t);
    expect(calls, 12, reason: 'availability does not depend on the order');
    expect(find.text('1 / 12'), findsOneWidget);
    expect(_ids(t), isNot(before));
    await _end(t);
  });

  for (final (name, answer) in [
    ('every check failed', (int i) => MotoAvailability.unknown),
    ('some busy, the rest failed', (int i) => i.isEven ? MotoAvailability.busy : MotoAvailability.unknown),
  ]) {
    testWidgets('$name → "Zkusit znovu", never "vše obsazené"', (t) async {
      var i = 0;
      await pumpV2(t, _funnel, size: const Size(412, 915), overrides: [
        ...homeOverrides(motos: fleet(8), realFunnel: true),
        ...homeOfferOverrides(given: r),
        homeRangeCheckProvider.overrideWithValue((id, range) async => answer(i++)),
      ]);
      await _frames(t);
      expect(find.byType(FunnelEmptySlot), findsOneWidget);
      expect(find.text(_cs('homeOfferNoneTitle')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is MgBtnGhostDark && w.label == _cs('eoRetry')), findsOneWidget);
      await _end(t);
    });
  }

  test('pill with dates and nothing free: "Volná od" only after the first chosen day', () {
    final tr = AppTranslations('cs');
    final m = fleet(1).first;
    final none = HomeOffer(HomeOfferMode.noneFree, bikes: [m], range: r);
    expect(homeOfferAvail(tr, none, m, {m.id: day(3)}, day(0)).$1, _cs('homeOfferBusyInRange'));
    expect(homeOfferBusy(none, m, {m.id: day(3)}), isTrue);
    expect(homeOfferAvail(tr, none, m, const {}, day(0)).$1, _cs('homeOfferBusyInRange'), reason: 'free today ≠ free then');
    expect(homeOfferAvail(tr, none, m, {m.id: day(9)}, day(0)).$1, _cs('homeOfferBusyInRange'));
    expect(homeOfferAvail(tr, none, m, {m.id: day(40)}, day(0)).$1,
        tr.trArgs('homeOfferFreeFrom', {'date': funnelDate(tr, day(40))}));
    expect(homeOfferBusy(none, m, {m.id: day(40)}), isFalse);
    final noDates = HomeOffer(HomeOfferMode.noDates, bikes: [m]);
    expect(homeOfferAvail(tr, noDates, m, const {}, day(0)).$1, _cs('v2CatFreeToday'), reason: 'without dates unchanged');
    expect(homeOfferBusy(noDates, m, const {}), isFalse);
  });

  test('bike name: no lone 1–2 letter last word; booked-day hit test', () {
    expect(homeNoOrphan('Benelli TRK 502 X'), 'Benelli TRK 502 X');
    expect(homeNoOrphan('Kawasaki Z 900'), 'Kawasaki Z 900');
    expect(homeNoOrphan('Shotgun'), 'Shotgun');
    final b = [BookedDateRange(start: day(10), end: day(10), status: 'confirmed')];
    expect(homeRangeHitsBooked(b, r), isTrue);
    expect(homeRangeHitsBooked(b, FunnelRange(day(11), day(12))), isFalse);
  });

  testWidgets('a second tap on the ticked weekend chip clears the dates', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeCases()['s0']!());
    await _frames(t);
    final chip = find.text(_cs('v2HomeFnPreset1')).first;
    await t.ensureVisible(chip);
    await t.tap(chip);
    await _frames(t);
    expect(_c(t).read(funnelRangeProvider), funnelPresets(DateTime.now()).$1);
    await t.tap(chip);
    await _frames(t);
    expect(_c(t).read(funnelRangeProvider), isNull);
    expect(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('homeOfferPickDates')), findsOneWidget);
    await _end(t);
  });

  Future<void> openOther(WidgetTester t) async {
    final cta = find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('v2HomeFnPickOther'));
    await t.ensureVisible(cta);
    await t.pump();
    await t.tap(cta);
    await _frames(t);
  }

  MgBtnInk apply(WidgetTester t) =>
      t.widget<MgBtnInk>(find.byWidgetPredicate((w) => w is MgBtnInk && w.label == _cs('v2HomeDateUse')));

  testWidgets('"Vybrat jiný termín": nothing ticked, apply off until a free range', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeCases()['s0-nonefree']!());
    await _frames(t);
    await openOther(t);
    expect(find.text(_cs('v2HomeDateTitle')), findsOneWidget);
    expect(find.byType(TripSummaryRow), findsNothing, reason: 'the failed dates are not offered again');
    expect(apply(t).onTap, isNull);
    await _end(t);
  });

  testWidgets('closed for months: the bike calendar says "Volná od" and jumps there', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeCases()['s0-closed']!());
    await _frames(t);
    await openOther(t);
    final row = find.byKey(const ValueKey('home-sheet-next-free'));
    expect(row, findsOneWidget);
    final tr = AppTranslations('cs');
    final jump = find.text(tr.trArgs('homeSheetJumpTo', {'date': funnelDate(tr, day(131))}));
    await t.ensureVisible(jump);
    await t.tap(jump);
    await _frames(t);
    expect(row, findsNothing);
    expect(find.byType(TripSummaryRow), findsOneWidget);
    expect(apply(t).onTap, isNotNull);
    await _end(t);
  });
}
