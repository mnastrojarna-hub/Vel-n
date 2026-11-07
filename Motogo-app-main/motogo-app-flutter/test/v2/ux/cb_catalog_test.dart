// catalog_booking package · catalog items: CB-01 filter sheet (v2 content
// writes the SAME filter as the old panel), CB-02 fullscreen gallery →
// v2 viewer (same route / pop / index), CB-06 branch · type line, CB-07
// compact bar, CB-08 skeleton geometry, CB-18 pull-to-refresh, CB-21 list
// error card.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_tech_details.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_photo_viewer.dart';
import 'package:motogo_app/core/v2/widgets/mg_skeleton.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_text.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_panel_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_compact_bar_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_error_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_loading_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/fullscreen_gallery.dart';
import 'package:motogo_app/features/catalog/widgets/moto_filter_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');

Future<ProviderContainer> _panel(WidgetTester t, {required bool v2}) async {
  // A fresh ProviderScope per run (the same position would keep its state).
  await t.pumpWidget(const SizedBox());
  await pumpV2(
    t,
    const SingleChildScrollView(child: MotoFilterPanel(initiallyOpen: true, embedded: true)),
    size: const Size(412, 1600),
    overrides: catalogOverrides(),
    v2: v2,
    reducedMotion: true,
  );
  await t.pump(const Duration(milliseconds: 300));
  return ProviderScope.containerOf(t.element(find.byType(MotoFilterPanel)));
}

Future<void> _tapText(WidgetTester t, String s) async {
  await t.tap(find.text(s).first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 200));
}

Future<(CatalogFilter, String)> _script(WidgetTester t, {required bool v2}) async {
  final c = await _panel(t, v2: v2);
  await _tapText(t, _cs.tr(MotoCategory.labelKey('naked')));
  await _tapText(t, _cs.tr('homeFilterLicenseA2'));
  await _tapText(t, _cs.tr('homeFilterShowAvailableToday'));
  final f = c.read(catalogFilterProvider);
  return (f, c.read(catalogSortProvider));
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 11));
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

  testWidgets('CB-01: the same tap script writes the same filter in the v2 sheet as in the old panel', (t) async {
    final (old, oldSort) = await _script(t, v2: false);
    expect(find.byType(MotoFilterPanelV2View), findsNothing);
    final (neu, newSort) = await _script(t, v2: true);
    expect(find.byType(MotoFilterPanelV2View), findsOneWidget);
    expect([neu.category, neu.licenseGroup, neu.availableTodayOnly, newSort],
        [old.category, old.licenseGroup, old.availableTodayOnly, oldSort]);
    expect([neu.category, neu.licenseGroup, neu.availableTodayOnly], ['naked', 'A2', true]);
  });

  testWidgets('CB-01: v2 branch / sort chips and "Resetovat" = the old setters', (t) async {
    final c = await _panel(t, v2: true);
    final branches = c.read(branchesProvider);
    expect(branches, isNotEmpty);
    await _tapText(t, branches.first['name'] as String);
    expect(c.read(catalogFilterProvider).branch, branches.first['id']);
    await _tapText(t, _cs.tr('homeFilterSortPriceAsc'));
    expect(c.read(catalogSortProvider), 'price_asc');
    await _tapText(t, _cs.tr(MotoCategory.labelKey('naked')));
    // Tapping the chosen category again clears it (old toggle).
    await _tapText(t, _cs.tr(MotoCategory.labelKey('naked')));
    expect(c.read(catalogFilterProvider).category, isNull);
    await _tapText(t, _cs.tr(MotoCategory.labelKey('naked')));
    final reset = find.widgetWithText(MgBtnText, _cs.tr('homeFilterReset'));
    expect(reset, findsOneWidget);
    await t.tap(reset);
    await t.pump();
    final f = c.read(catalogFilterProvider);
    expect([f.category, f.branch, f.activeCount], [null, null, 0]);
    expect(c.read(catalogSortProvider), 'default');
    expect(reset, findsNothing);
  });

  testWidgets('CB-01: ink slider — a drag commits on release with the old "end = no limit" rule', (t) async {
    final c = await _panel(t, v2: true);
    final slider = find.byType(RangeSlider).first;
    final r = t.getRect(slider);
    // Left thumb dragged to the middle → a lower bound; right untouched → null.
    await t.dragFrom(Offset(r.left + 24, r.center.dy), Offset(r.width / 2, 0));
    await t.pump();
    final f = c.read(catalogFilterProvider);
    expect(f.minPowerKw, isNotNull);
    expect(f.maxPowerKw, isNull);
  });

  testWidgets('CB-02: gallery opens the v2 viewer at the tapped photo; ✕ and swipe-down pop', (t) async {
    final urls = ['https://img.test/a.jpg', 'https://img.test/b.jpg', 'https://img.test/c.jpg'];
    await pumpV2(t, Builder(builder: (ctx) {
      return Center(
        child: TextButton(onPressed: () => FullscreenGallery.open(ctx, images: urls, initialIndex: 1), child: const Text('OPEN')),
      );
    }), reducedMotion: true);
    await t.tap(find.text('OPEN'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final v = t.widget<MgPhotoViewerView>(find.byType(MgPhotoViewerView));
    expect([v.urls, v.initial], [urls, 1]);
    await t.tap(find.byType(MgV2Back));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(MgPhotoViewerView), findsNothing);
    // Swipe-down closes too.
    await t.tap(find.text('OPEN'));
    await t.pump(const Duration(milliseconds: 300));
    await t.drag(find.byType(InteractiveViewer).first, const Offset(0, 220));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(MgPhotoViewerView), findsNothing);
    await _drain(t);
  });

  testWidgets('CB-02: zoomed photo pans vertically without closing', (t) async {
    final urls = ['https://img.test/a.jpg', 'https://img.test/b.jpg'];
    await pumpV2(t, Builder(builder: (ctx) {
      return Center(child: TextButton(onPressed: () => FullscreenGallery.open(ctx, images: urls), child: const Text('OPEN')));
    }), reducedMotion: true);
    await t.tap(find.text('OPEN'));
    await t.pump(const Duration(milliseconds: 300));
    final c = t.getCenter(find.byType(InteractiveViewer).first);
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 60));
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 400));
    await t.drag(find.byType(InteractiveViewer).first, const Offset(0, 220));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(MgPhotoViewerView), findsOneWidget);
    await _drain(t);
  });

  for (final lang in kV2Langs) {
    testWidgets('CB-06: branch · type line, both branch types ($lang)', (t) async {
      final tr = AppTranslations.of(lang);
      expect(catBranchLine(tr, kBmw), 'Mezná · ${tr.tr('v2CalcBranchStaffed')}');
      final self = kMotos.firstWhere((m) => m.branchType == 'samoobslužná');
      expect(catBranchLine(tr, self), endsWith(tr.tr('v2CalcBranchSelf')));
    });
  }

  testWidgets('CB-07: compact bar hidden at the top, shown past the header; discs call their actions', (t) async {
    final (ws, we) = futureWeekend();
    await pumpV2(t, const MotorkyScreenV2(),
        overrides: catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), filtered: [kBmw, kHusq]),
        reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    final bar = find.byType(MotorkyCompactBarV2);
    double barBottom() => t.getRect(bar).bottom;
    expect(barBottom(), lessThanOrEqualTo(0.5));
    await t.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await t.pump(const Duration(milliseconds: 400));
    expect(barBottom(), greaterThan(40));
    final c = ProviderScope.containerOf(t.element(bar));
    await t.tap(find.descendant(of: bar, matching: find.byType(MgIconButton)).last);
    await t.pump(const Duration(milliseconds: 400));
    expect(c.read(catalogModeProvider), CatalogMode.calc);
    await _drain(t);
  });

  testWidgets('CB-08: full-card skeleton = the real card height (±10 %), slow state after 15 s', (t) async {
    var retries = 0;
    await pumpV2(t, SingleChildScrollView(child: MotorkyLoadingV2(grid: false, cardHeight: 560, onRetry: () => retries++)),
        reducedMotion: true);
    final h = t.getSize(find.byType(MgSkeletonPhotoCard).first).height;
    expect((h - 560).abs() / 560, lessThan(0.1));
    expect(find.text(_cs.tr('v2UxCbLoadingMotos').toUpperCase()), findsOneWidget);
    await t.pump(const Duration(seconds: 16));
    expect(find.text(_cs.tr('eoSlowTitle')), findsOneWidget);
    await t.tap(find.text(_cs.tr('eoRetry')));
    expect(retries, 1);
  });

  testWidgets('CB-18: pull-to-refresh on the list reloads the catalogue', (t) async {
    var loads = 0;
    await pumpV2(t, const MotorkyScreenV2(), overrides: [
      ...catalogOverrides(filtered: [kBmw, kHusq]),
      filteredMotorcyclesProvider.overrideWith((ref) async {
        loads++;
        return [kBmw, kHusq];
      }),
    ], reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    final before = loads;
    await t.fling(find.byType(CustomScrollView), const Offset(0, 400), 1200);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(loads, greaterThan(before));
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await _drain(t);
  });

  testWidgets('CB-21: list error = Stavy 8.6 card; ZKUSIT ZNOVU = the reload; raw error only in Technické detaily', (t) async {
    var retries = 0;
    await pumpV2(t, SingleChildScrollView(child: MotorkyErrorV2(error: Exception('socket closed'), onRetry: () => retries++)));
    expect(find.text(_cs.tr('v2UxCbErrTitle')), findsOneWidget);
    expect(find.text(_cs.tr('v2UxCbErrWhy')), findsOneWidget);
    expect(find.textContaining('socket closed'), findsNothing);
    expect(find.byType(MgTechDetails), findsOneWidget);
    await t.tap(find.text(_cs.tr('eoRetry').toUpperCase()));
    expect(retries, 1);
  });
}
