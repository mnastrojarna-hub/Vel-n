// v2 catalog screens (PLAN §5.3, area "catalog"): Motorky (find / grid /
// empty / error / loading / banner), the calculator in every board state,
// the date + filter sheets and the bike detail (dates / no dates / loading /
// error / gone / availability loading + error / loyalty failure / pager) —
// all 8 languages × 360×780 and 412×915, failing on any exception or
// overflow; PNGs into MG_SHOTS_DIR when set.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/catalog_date_sheet_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_filter_sheet_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

typedef _Case = ({String name, Widget Function() build, List<Override> Function() overrides, Future<void> Function(WidgetTester)? after});

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });
  setUp(MgMotion.resetSession);

  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);
  final available = [kBmw, kHusq, kKids];
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true); // Home funnel request → calculator
  const banner = BannerData(
    enabled: true,
    text: 'V zimním období od 1. 11. 2026 do 25. 3. 2027 zavřeno.',
    bg: Color(0xFF74FB71),
    color: Color(0xFF000000),
  );
  Widget motorky() => const MotorkyScreenV2();
  Widget detail([String id = 'm-bmw']) => MotoDetailPage(motoId: id, showBackButton: true);

  Future<void> openSheet(WidgetTester t, Future<void> Function(BuildContext) open) async {
    open(t.element(find.byType(MotorkyScreenV2)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> expandCalendar(WidgetTester t) async {
    // Detail with dates starts collapsed; "Změnit" expands the calendar.
    await t.pump(const Duration(milliseconds: 50));
    final change = find.byWidgetPredicate((w) => w is MgBtnText && w.icon == MgIcons.edit);
    await t.ensureVisible(change);
    await t.pump();
    await t.tap(change);
    await t.pump(const Duration(milliseconds: 400));
  }

  final List<_Case> cases = [
    (name: 'motorky__find_nodates', build: motorky, overrides: () => catalogOverrides(), after: null),
    (name: 'motorky__find_banner', build: motorky, overrides: () => catalogOverrides(banner: banner), after: null),
    (
      name: 'motorky__find_dates',
      build: motorky,
      overrides: () => catalogOverrides(filter: dated, filtered: available),
      after: null,
    ),
    (
      name: 'motorky__grid',
      build: motorky,
      overrides: () => catalogOverrides(filter: dated, filtered: available),
      after: (t) async {
        await t.tap(find.byWidgetPredicate((w) => w is CatPathIcon && w.d == CatPathIcon.grid));
        await t.pump(const Duration(milliseconds: 300));
      },
    ),
    (name: 'motorky__empty', build: motorky, overrides: () => catalogOverrides(filter: dated, filtered: const []), after: null),
    (name: 'motorky__error', build: motorky, overrides: () => catalogOverrides(filteredError: Exception('net')), after: null),
    (name: 'motorky__loading', build: motorky, overrides: () => catalogOverrides(filteredLoading: true), after: null),
    (
      name: 'sheet__dates',
      build: motorky,
      overrides: () => catalogOverrides(filter: dated, filtered: available),
      after: (t) => openSheet(t, showCatalogDateSheet),
    ),
    (
      name: 'sheet__filters',
      build: motorky,
      overrides: () => catalogOverrides(),
      after: (t) => openSheet(t, showCatalogFilterSheet),
    ),
    (name: 'calc__none', build: motorky, overrides: () => [...catalogOverrides(), calcMode], after: null),
    (
      name: 'calc__all_selected',
      build: motorky,
      overrides: () => [...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we)), calcMode],
      after: null,
    ),
    (
      // 1-day trip: the ½ card gives way to the general 12:00 note.
      name: 'calc__one_day',
      build: motorky,
      overrides: () => [
        ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: ws)),
        calcMode,
      ],
      after: null,
    ),
    (
      name: 'calc__no_bike_dates',
      build: motorky,
      overrides: () => [...catalogOverrides(calc: CalcState(start: ws, end: we)), calcMode],
      after: null,
    ),
    (
      name: 'calc__free_none',
      build: motorky,
      overrides: () => [...catalogOverrides(calc: CalcState(start: ws, end: we), free: const []), calcMode],
      after: null,
    ),
    (
      name: 'calc__bike_no_dates',
      build: motorky,
      overrides: () => [...catalogOverrides(calc: const CalcState(motoId: 'm-husq')), calcMode],
      after: null,
    ),
    (
      name: 'calc__start_only',
      build: motorky,
      overrides: () => [...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws)), calcMode],
      after: null,
    ),
    (
      name: 'calc__busy_in_range',
      build: motorky,
      overrides: () => [
        ...catalogOverrides(
          calc: CalcState(motoId: 'm-bmw', start: ws, end: we),
          booked: {
            'm-bmw': [BookedDateRange(start: we, end: DateTime(we.year, we.month, we.day + 2), status: 'confirmed')],
          },
        ),
        calcMode,
      ],
      after: null,
    ),
    (
      name: 'calc__over_limit',
      build: motorky,
      overrides: () => [
        ...catalogOverrides(calc: CalcState(motoId: 'm-shot', start: ws, end: DateTime(ws.year, ws.month, ws.day + 34))),
        calcMode,
      ],
      after: null,
    ),
    (
      name: 'calc__booked_loading',
      build: motorky,
      overrides: () => [...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), bookedLoading: true), calcMode],
      after: null,
    ),
    (
      name: 'calc__booked_error',
      build: motorky,
      overrides: () => [
        ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), bookedError: Exception('net')),
        calcMode,
      ],
      after: null,
    ),
    (
      name: 'calc__loyalty_fail',
      build: motorky,
      overrides: () => [
        ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), loyaltyError: Exception('rpc')),
        calcMode,
      ],
      after: null,
    ),
    (name: 'detail__nodates', build: detail, overrides: () => catalogOverrides(), after: null),
    (name: 'detail__dates', build: detail, overrides: () => catalogOverrides(filter: dated), after: null),
    (name: 'detail__dates_calendar', build: detail, overrides: () => catalogOverrides(filter: dated), after: expandCalendar),
    (name: 'detail__loading', build: detail, overrides: () => catalogOverrides(motosLoading: true), after: null),
    (name: 'detail__error', build: detail, overrides: () => catalogOverrides(motosError: Exception('net')), after: null),
    (name: 'detail__gone', build: () => detail('m-gone'), overrides: () => catalogOverrides(), after: null),
    (name: 'detail__booked_loading', build: detail, overrides: () => catalogOverrides(bookedLoading: true), after: null),
    (name: 'detail__booked_error', build: detail, overrides: () => catalogOverrides(bookedError: Exception('x')), after: null),
    (
      name: 'detail__loyalty_fail',
      build: detail,
      overrides: () => catalogOverrides(filter: dated, loyaltyError: Exception('rpc')),
      after: null,
    ),
    (name: 'detail__guest_rank0', build: detail, overrides: () => catalogOverrides(filter: dated, loyalty: null), after: null),
    (
      name: 'detail__pager',
      build: () => const MotoDetailScreen(motoId: 'm-husq'),
      overrides: () => [
        ...catalogOverrides(),
        filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq', 'm-shot']),
      ],
      after: null,
    ),
  ];

  for (final c in cases) {
    group(c.name, () {
      for (final lang in kV2Langs) {
        for (final size in kV2Sizes) {
          testWidgets('$lang ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
            final key = GlobalKey();
            await pumpV2(tester, c.build(), lang: lang, size: size, overrides: c.overrides(), boundaryKey: key);
            await tester.pump();
            if (c.after != null) await c.after!(tester);
            await expectCleanFrames(tester);
            // One more frame: staggered reveals that started late are drawn.
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull);
            await maybeShot(tester, key, 'catalog__${c.name}__${lang}__${size.width.toInt()}x${size.height.toInt()}');
          });
        }
      }
    });
  }

  group('reduced motion settles', () {
    for (final c in cases.where((c) => !c.name.contains('loading') && !c.name.startsWith('sheet'))) {
      testWidgets(c.name, (tester) async {
        await pumpV2(tester, c.build(), overrides: c.overrides(), reducedMotion: true);
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
