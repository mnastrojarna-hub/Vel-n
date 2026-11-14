// v5.0.1 Home offer card (owner brief after installing 5.0.0): nothing is
// preselected — without dates the card shows EVERY bike the customer may
// ride with its photo, "od X Kč/den" (catCardPrice, rank included) and
// "Volná dnes / od …", and "Vybrat termín" opens THAT bike's calendar; with
// dates every free bike (no cap of 5); nothing free = the bikes stay with
// "Volná od", a short heading why (closed / booked out) and "Vybrat jiný
// termín"; a new order on every visit of Domů (Back from a detail keeps
// it); the three rows under "Aktivní rezervace" share the dark neon tile.
// Weekday / time independent (all dates relative to today).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/v2/widgets/mg_icon_tile.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/home/v2/funnel_carousel_v2.dart';
import 'package:motogo_app/features/home/v2/funnel_dates.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_funnel_cta.dart';
import 'package:motogo_app/features/home/v2/home_funnel_parts.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_offer_provider.dart';
import 'package:motogo_app/features/home/v2/home_record_row_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart';
import '../support/v2_harness.dart';
import 'home_test.dart' show homeCases, homeOfferOverrides;

String _cs(String key) => translations['cs']![key]!;
const _funnel = SingleChildScrollView(child: HomeFunnelV2());

/// A fleet of [n] bikes on two branches (all licence A, free today).
List<Motorcycle> fleet(int n) => [
      for (var i = 0; i < n; i++)
        Motorcycle(
          id: 'f$i',
          model: 'Bike $i',
          category: 'naked',
          licenseGroups: const ['A'],
          branchId: i.isEven ? '11111111-1111-1111-1111-111111111111' : '22222222-2222-2222-2222-222222222222',
          branchName: i.isEven ? 'Mezná' : 'Velké Němčice',
          branchType: i.isEven ? 'obslužná' : 'samoobslužná',
          branchIsOpen: true,
          prices: kMotos.first.prices,
          availableToday: true,
        ),
    ];

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

List<String> _models(WidgetTester t) =>
    t.widgetList<FunnelBikeCard>(find.byType(FunnelBikeCard, skipOffstage: false)).map((c) => c.moto.id).toList();

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  test('H4 shuffle: same seed = same order, other seeds change it; focus bike first', () {
    final f = fleet(12);
    expect(homeOfferShuffle(f, 5).map((m) => m.id), homeOfferShuffle(f, 5).map((m) => m.id));
    final orders = {for (var s = 0; s < 8; s++) homeOfferShuffle(f, s).map((m) => m.id).join(',')};
    expect(orders.length, greaterThan(1));
    expect(homeOfferShuffle(f, 3).toSet(), f.toSet(), reason: 'nothing dropped');
    expect(homeOfferFocusFirst(f, 'f7').first.id, 'f7');
    expect(homeOfferFocusFirst(f, 'nope'), f);
  });

  test('H3 closed: every bike on a branch closed on some day of the range', () {
    final f = fleet(4);
    final r = FunnelRange(day(9), day(11));
    final both = [
      HomeClosure('11111111-1111-1111-1111-111111111111', day(11), day(40)),
      HomeClosure('22222222-2222-2222-2222-222222222222', day(0), day(9)),
    ];
    expect(homeOfferAllClosed(f, both, r), isTrue);
    expect(homeOfferAllClosed(f, both.take(1).toList(), r), isFalse, reason: 'one branch open = booked out');
    expect(homeOfferAllClosed(f, [HomeClosure('11111111-1111-1111-1111-111111111111', day(12), day(40))], r), isFalse);
  });

  testWidgets('H1 no dates: nothing ticked, every allowed bike, "od" price, availability, "Vybrat termín" → that bike\'s calendar',
      (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeCases()['s0']!());
    await _frames(t);
    final c = _c(t);
    expect(c.read(funnelRangeProvider), isNull);
    expect(find.byType(FunnelDateLine), findsNothing);
    expect(find.text('1 / 3'), findsOneWidget, reason: 'the 3 bikes licence A allows, not a weekend list');
    final card = t.widget<FunnelBikeCard>(find.byWidgetPredicate((w) => w is FunnelBikeCard && w.center));
    expect(card.priceLabel, _cs('v2CatPriceFrom'));
    expect(card.unit, _cs('pricePerDay'));
    final shot = kMotos.firstWhere((m) => m.id == 'm-shot');
    final tr = AppTranslations('cs');
    final (avail, live) = homeOfferAvail(tr, c.read(homeOfferProvider), shot, {'m-shot': day(6)}, day(0));
    expect(avail, tr.trArgs('homeOfferFreeFrom', {'date': funnelDate(tr, day(6))}));
    expect(live, isFalse);
    expect(homeOfferAvail(tr, c.read(homeOfferProvider), kMotos.first, const {}, day(0)).$1, _cs('v2CatFreeToday'));
    final cta = find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('homeOfferPickDates'));
    expect(cta, findsOneWidget);
    expect(t.widget<MgCta>(cta).price, isNull, reason: 'no total without dates');
    await t.ensureVisible(cta);
    await t.pump();
    await t.tap(cta);
    await _frames(t);
    expect(find.text(_cs('v2HomeDateTitle')), findsOneWidget);
    expect(find.text(card.moto.model), findsWidgets, reason: 'the calendar of the bike in the photo');
    await _end(t);
  });

  testWidgets('H2 dates: every free bike, no cap; first batch shown while the rest loads ("+")', (t) async {
    final r = FunnelRange(day(9), day(11));
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: [
      ...homeOverrides(funnel: fleet(12)),
      ...homeOfferOverrides(given: r),
    ]);
    await _frames(t);
    expect(find.text('1 / 12'), findsOneWidget);
    expect(t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 12);
    await _end(t);

    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: [
      ...homeOverrides(funnel: fleet(12), funnelLoading: true),
      ...homeOfferOverrides(given: r),
    ]);
    await _frames(t);
    final c = _c(t);
    c.read(funnelPartialProvider((r, 1)).notifier).state = fleet(3);
    await _frames(t);
    expect(find.text('1 / 3+'), findsOneWidget);
    expect(find.byType(FunnelBikeCard), findsWidgets);
    await _end(t);
  });

  for (final (state, title) in [('s0-nonefree', 'homeOfferNoneTitle'), ('s0-closed', 'homeOfferClosedTitle')]) {
    testWidgets('H3 nothing free ($state): photos stay, "Volná od", heading, "Vybrat jiný termín"', (t) async {
      await pumpV2(t, _funnel, size: const Size(412, 915), overrides: homeCases()[state]!());
      await _frames(t);
      expect(find.byType(FunnelEmptySlot), findsNothing, reason: 'never a card without a photo');
      expect(find.byType(FunnelBikeCard), findsWidgets);
      expect(find.text(_cs(title)), findsOneWidget);
      expect(find.text(_cs('v2HomeFnNoneTitle')), findsNothing, reason: 'the licence text is gone');
      expect(find.byWidgetPredicate((w) => w is MgCta && w.label == _cs('v2HomeFnPickOther')), findsOneWidget);
      final card = t.widget<FunnelBikeCard>(find.byWidgetPredicate((w) => w is FunnelBikeCard && w.center));
      expect(card.priceLabel, _cs('v2CatPriceFrom'));
      if (state == 's0-closed') expect(card.avail, startsWith(_cs('homeOfferFreeFrom').split(' {').first));
      await _end(t);
    });
  }

  testWidgets('H4 a new order on a new visit, the same order while Domů stays mounted; "Znovu" not forced first', (t) async {
    final show = ValueNotifier(true);
    await pumpV2(t, ValueListenableBuilder<bool>(valueListenable: show, builder: (_, v, __) => v ? _funnel : const SizedBox()),
        size: const Size(412, 915),
        overrides: [
          ...homeOverrides(reservations: [res('old', status: 'completed', from: -30, to: -28)]),
          motorcyclesProvider.overrideWith((ref) => Stream.value(fleet(12))),
        ]);
    await _frames(t);
    final seeds = <int>{_c(t).read(homeOfferSeedProvider)};
    final first = _c(t).read(homeOfferProvider).bikes.map((m) => m.id).toList();
    await t.pump(const Duration(seconds: 1));
    expect(_c(t).read(homeOfferProvider).bikes.map((m) => m.id).toList(), first, reason: 'stays while mounted');
    for (var i = 0; i < 4; i++) {
      show.value = false;
      await _frames(t);
      show.value = true;
      await _frames(t);
      seeds.add(_c(t).read(homeOfferSeedProvider));
    }
    expect(seeds.length, greaterThan(1), reason: 'every visit of Domů = a new shuffle');
    // App back after a pause → a new order too.
    final before = _c(t).read(homeOfferSeedProvider);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await _frames(t);
    expect(_c(t).read(homeOfferSeedProvider), isNot(before));
    expect(_models(t), isNotEmpty);
    await _end(t);
  });

  testWidgets('H4 the last ridden bike keeps "Znovu" wherever the shuffle puts it', (t) async {
    await pumpV2(t, _funnel, size: const Size(412, 915), overrides: [
      ...homeOverrides(reservations: [res('old', status: 'completed', from: -30, to: -28)]),
      ...homeOfferOverrides(),
    ]);
    await _frames(t);
    final c = _c(t);
    final bikes = c.read(homeOfferProvider).bikes;
    expect(bikes.map((m) => m.id).toSet(), {'m-bmw', 'm-husq', 'm-shot'});
    final i = bikes.indexWhere((m) => m.id == 'm-husq');
    for (var k = 0; k < i; k++) {
      await t.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == _cs('v2HomeFnNext')).first);
      await _frames(t);
    }
    final card = t.widget<FunnelBikeCard>(find.byWidgetPredicate((w) => w is FunnelBikeCard && w.center));
    expect(card.moto.id, 'm-husq');
    expect(card.badge, _cs('v2HomeFnAgain'));
    await _end(t);
  });

  testWidgets('H5/H6/H7 dark neon tiles in all three rows; branch chip on the photo; calculator row without dates', (t) async {
    await pumpV2(t, const HomeScreenV2(), size: const Size(412, 915), overrides: homeCases()['s0']!(), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 1600));
    final row = find.byKey(const ValueKey('home-no-booking'));
    expect(find.descendant(of: row, matching: find.byType(MgIconTileLight)), findsNothing);
    final tile = t.widget<MgIconTileDark>(find.descendant(of: row, matching: find.byType(MgIconTileDark)));
    final calc = t.widget<MgIconTileDark>(
        find.descendant(of: find.byKey(const ValueKey('home-calc-row')), matching: find.byType(MgIconTileDark)));
    final rec = t.widget<MgIconTileDark>(find.descendant(of: find.byType(HomeRecordRowV2), matching: find.byType(MgIconTileDark)));
    expect([tile.size, rec.size], [calc.size, calc.size]);
    final card = find.byWidgetPredicate((w) => w is FunnelBikeCard && w.center);
    expect(find.descendant(of: card, matching: find.byKey(const ValueKey('mg-branch-chip'))), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(HomeScreenV2)));
    final moto = t.widget<FunnelBikeCard>(card).moto;
    expect(find.descendant(of: find.byKey(const ValueKey('home-calc-row')), matching: find.text(moto.model)), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('home-calc-row')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('home-calc-row')));
    await t.pump();
    final st = c.read(calcStateProvider);
    expect([st.motoId, st.start, st.end], [moto.id, null, null]);
    await _end(t);
  });
}
