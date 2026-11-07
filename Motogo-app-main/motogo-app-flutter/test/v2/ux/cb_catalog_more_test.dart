// catalog_booking package · P2 items: CB-12 pager pill ‹ › (tap = swipe),
// CB-13 "Volná v tvém termínu", CB-14 Hero tags, CB-17 dock "Rozpis",
// CB-19 date sheet footer, CB-20 category chips, CB-23 video chrome,
// CB-26 weekend presets, CB-27 mode fade (reduced = instant).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_skeleton.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/catalog_date_sheet_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_text.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_hero_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/video_chrome_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/hero_tags.dart';
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
Finder _pill() => find.descendant(of: find.byType(DetailHeroV2), matching: find.text(_cs.tr('v2CatFreeInRange')));

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 11));
}

Future<void> _pager(WidgetTester t, {bool reduced = true}) async {
  final (ws, we) = futureWeekend();
  await pumpV2(t, const MotoDetailScreen(motoId: 'm-husq'),
      overrides: [
        ...catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we)),
        filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq', 'm-shot']),
      ],
      reducedMotion: reduced,
      size: const Size(412, 915));
  await t.pump(const Duration(milliseconds: 500));
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

  testWidgets('CB-12: ‹ / › in the pager pill move to the previous / next bike (tap twin of the swipe)', (t) async {
    await _pager(t);
    expect(find.text('2 / 3'), findsOneWidget);
    await t.tap(find.bySemanticsLabel(_cs.tr('v2UxCbNextBike')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('3 / 3'), findsOneWidget);
    await t.tap(find.bySemanticsLabel(_cs.tr('v2UxCbPrevBike')));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.bySemanticsLabel(_cs.tr('v2UxCbPrevBike')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('1 / 3'), findsOneWidget);
    // Hit area ≥ 44.
    expect(t.getSize(find.bySemanticsLabel(_cs.tr('v2UxCbNextBike'))).height, greaterThanOrEqualTo(44));
    await _drain(t);
  });

  testWidgets('CB-12: with motion the pill animates the page (300 ms) and lands on the next bike', (t) async {
    await _pager(t, reduced: false);
    await t.tap(find.bySemanticsLabel(_cs.tr('v2UxCbNextBike')));
    await t.pump(const Duration(milliseconds: 150));
    expect(find.text('2 / 3'), findsOneWidget); // still on the way
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('3 / 3'), findsOneWidget);
    await _drain(t);
  });

  testWidgets('CB-13: dates + loaded + free → "Volná v tvém termínu"', (t) async {
    final (ws, we) = futureWeekend();
    await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
        overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we)), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    expect(_pill(), findsOneWidget);
    await _drain(t);
  });

  testWidgets('CB-13: busy range → no "Volná v tvém termínu" pill', (t) async {
    final (ws, we) = futureWeekend();
    await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
        overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), booked: {
          'm-bmw': [BookedDateRange(start: we, end: we, status: 'confirmed')],
        }),
        reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    expect(_pill(), findsNothing);
    await _drain(t);
  });

  testWidgets('CB-14: card / detail photos carry unique Hero tags (motion on)', (t) async {
    final (ws, we) = futureWeekend();
    await pumpV2(t, const MotorkyScreenV2(),
        overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), filtered: [kBmw, kHusq, kKids]));
    await t.pump(const Duration(milliseconds: 600));
    expectUniqueHeroTags(t);
    await _drain(t);
  });

  testWidgets('CB-17: dock "Rozpis" opens the trip card\'s breakdown', (t) async {
    final (ws, we) = futureWeekend();
    await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
        overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we)), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    final rozpis = find.widgetWithText(MgBtnText, _cs.tr('v2Breakdown'));
    expect(rozpis, findsOneWidget);
    await t.tap(rozpis);
    await t.pump(const Duration(milliseconds: 600));
    final state = t.state(find.byType(DetailTripCardV2));
    expect(state, isNotNull);
    expect(t.widget<DetailTripCardV2>(find.byType(DetailTripCardV2)).breakdown!.value, isTrue);
    await _drain(t);
  });

  testWidgets('CB-19: date sheet footer "POUŽÍT TERMÍN · 3 DNY" + "Zrušit termín" (= clear), "Hotovo" without', (t) async {
    final (ws, we) = futureWeekend();
    await pumpV2(t, const MotorkyScreenV2(),
        overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), filtered: [kBmw]), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 400));
    final ctx = t.element(find.byType(MotorkyScreenV2));
    showCatalogDateSheet(ctx);
    await t.pump(const Duration(milliseconds: 500));
    final use = _cs.trArgs('v2UxCbUseDates', {'days': catDays(_cs, catDayCount(ws, we))}).toUpperCase();
    expect(find.text(use), findsOneWidget);
    await t.tap(find.text(_cs.tr('v2CatDateClear')).last);
    await t.pump(const Duration(milliseconds: 300));
    final c = ProviderScope.containerOf(ctx);
    expect(c.read(catalogFilterProvider).startDate, isNull);
    expect(find.text(_cs.tr('v2CatDone')), findsOneWidget);
    await _drain(t);
  });

  testWidgets('CB-20: header category chips = the panel write (toggle) with exact counts', (t) async {
    await pumpV2(t, const MotorkyScreenV2(), overrides: catalogOverrides(filtered: [kBmw, kHusq, kKids]), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 400));
    final c = ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
    final label = _cs.tr(MotoCategory.labelKey(kBmw.category));
    final chip = find.bySemanticsLabel('$label, ${[kBmw, kHusq, kKids].where((m) => m.category == kBmw.category).length}');
    expect(chip, findsOneWidget);
    await t.tap(chip);
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(catalogFilterProvider).category, kBmw.category);
    await t.tap(find.bySemanticsLabel(label));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(catalogFilterProvider).category, isNull);
    await _drain(t);
  });

  testWidgets('CB-23: video chrome — skeleton while loading, 44 mute disc calls the player toggle, pill counter', (t) async {
    var toggles = 0;
    await pumpV2(t, SizedBox(
      width: 320,
      height: 180,
      child: VideoChromeV2(ready: false, muted: true, index: 0, count: 2, onToggleMute: () => toggles++, video: const SizedBox()),
    ));
    expect(find.byType(MgSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    final mute = find.bySemanticsLabel(_cs.tr('v2UxCbUnmute'));
    expect(t.getSize(mute), const Size(44, 44));
    await t.tap(mute);
    expect(toggles, 1);
  });

  testWidgets('CB-26: no dates → free weekend presets; a tap = the calendar\'s onRangeSelected', (t) async {
    await pumpV2(t, const MotoDetailPage(motoId: 'm-bmw', showBackButton: true), overrides: catalogOverrides(), reducedMotion: true,
        size: const Size(412, 915));
    await t.pump(const Duration(milliseconds: 500));
    final chip = find.widgetWithText(MgChoiceChip, _cs.tr('v2CatPresetWeekend'));
    await Scrollable.ensureVisible(t.element(chip), alignment: 0.4);
    await t.pump();
    await t.tap(chip);
    await t.pump(const Duration(milliseconds: 400));
    // The detail's own range state (what the calendar's onRangeSelected sets).
    final (s, e) = catWeekend(DateTime.now());
    final card = t.widget<DetailTripCardV2>(find.byType(DetailTripCardV2));
    expect([card.selStart, card.selEnd], [s, e]);
    expect(find.widgetWithText(MgChoiceChip, _cs.tr('v2CatPresetWeekend')), findsNothing);
    await _drain(t);
  });

  testWidgets('CB-27: mode switch — reduced motion shows the new content at once', (t) async {
    await pumpV2(t, const MotorkyScreenV2(), overrides: catalogOverrides(filtered: [kBmw]), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 300));
    final c = ProviderScope.containerOf(t.element(find.byType(MotorkyScreenV2)));
    c.read(catalogModeProvider.notifier).state = CatalogMode.calc;
    await t.pump();
    await t.pump();
    final fade = t.widget<SliverFadeTransition>(find.byType(SliverFadeTransition));
    expect(fade.opacity.value, 1.0);
    await _drain(t);
  });
}
