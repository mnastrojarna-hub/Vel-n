// verify:render cases — catalog v2 (ported from catalog_test.dart):
// Motorky (find / grid with + without dates / empty / error / loading /
// banner), the date and filter sheets, the calculator in every board state
// + its bike picker sheet, the bike detail (dates / calendar / loading /
// error / gone / availability states / loyalty failure / guest / pager;
// "more_open" lives in cases_extra.dart). Release gate = both text scales:
// MG_VERIFY_RENDER=1 MG_VERIFY_SCALE=1.0|1.3 flutter test
// test/v2/render/render_catalog_test.dart (+ the always-on component
// matrix test/v2/screens/catalog_fit_matrix_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_step_moto_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_date_sheet_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_filter_sheet_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../support/fakes_catalog.dart';
import 'render_harness.dart';

Future<void> _openSheet(WidgetTester t, Future<void> Function(BuildContext) open) async {
  open(t.element(find.byType(MotorkyScreenV2)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _toGrid(WidgetTester t) async {
  await t.tap(find.byWidgetPredicate((w) => w is CatPathIcon && w.d == CatPathIcon.grid));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _expandCalendar(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 50));
  final change = find.byWidgetPredicate((w) => w is MgBtnText && w.icon == MgIcons.edit);
  await t.ensureVisible(change);
  await t.pump();
  await t.tap(change);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _openBikePicker(WidgetTester t) async {
  final f = find.descendant(of: find.byType(CalcStepMotoV2), matching: find.byType(MgPress)).first;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

List<RenderCase> catalogRenderCases() {
  final (ws, we) = futureWeekend();
  final dated = CatalogFilter(startDate: ws, endDate: we);
  final available = [kBmw, kHusq, kKids];
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true); // Home funnel request → calculator
  const banner = BannerData(
      enabled: true, text: 'V zimním období od 1. 11. 2026 do 25. 3. 2027 zavřeno.', bg: Color(0xFF74FB71), color: Color(0xFF000000));
  Widget motorky() => const MotorkyScreenV2();
  Widget detail([String id = 'm-bmw']) => MotoDetailPage(motoId: id, showBackButton: true);
  RenderCase m(String state, List<Override> Function() o, {Future<void> Function(WidgetTester)? after, bool loading = false}) =>
      RenderCase('catalog', 'motorky', state, motorky, o, after: after, loading: loading);
  RenderCase calc(String state, CalcState? s, {Map<String, List<BookedDateRange>> booked = const {}, List<Motorcycle>? free,
          bool bookedLoading = false, Object? bookedError, Object? loyaltyError, Future<void> Function(WidgetTester)? after}) =>
      RenderCase('catalog', 'calc', state, motorky, () => [
            ...catalogOverrides(calc: s, booked: booked, free: free, bookedLoading: bookedLoading, bookedError: bookedError, loyaltyError: loyaltyError),
            calcMode,
          ], after: after, loading: bookedLoading);
  RenderCase d(String state, List<Override> Function() o, {Widget Function()? build, Future<void> Function(WidgetTester)? after, bool loading = false}) =>
      RenderCase('catalog', 'detail', state, build ?? detail, o, after: after, loading: loading);
  return [
    m('find_nodates', () => catalogOverrides()),
    m('find_banner', () => catalogOverrides(banner: banner)),
    m('find_dates', () => catalogOverrides(filter: dated, filtered: available)),
    m('grid', () => catalogOverrides(filter: dated, filtered: available), after: _toGrid),
    // Grid without dates: "Dnes volná" badge + "od … /den" prices.
    m('grid_nodates', () => catalogOverrides(), after: _toGrid),
    m('empty', () => catalogOverrides(filter: dated, filtered: const [])),
    m('error', () => catalogOverrides(filteredError: Exception('net'))),
    m('loading', () => catalogOverrides(filteredLoading: true), loading: true),
    m('sheet_dates', () => catalogOverrides(filter: dated, filtered: available), after: (t) => _openSheet(t, showCatalogDateSheet)),
    m('sheet_filters', () => catalogOverrides(), after: (t) => _openSheet(t, showCatalogFilterSheet)),
    calc('none', null),
    calc('all_selected', CalcState(motoId: 'm-bmw', start: ws, end: we)),
    calc('one_day', CalcState(motoId: 'm-bmw', start: ws, end: ws)),
    calc('no_bike_dates', CalcState(start: ws, end: we)),
    calc('free_none', CalcState(start: ws, end: we), free: const []),
    calc('bike_no_dates', const CalcState(motoId: 'm-husq')),
    calc('start_only', CalcState(motoId: 'm-bmw', start: ws)),
    calc('busy_in_range', CalcState(motoId: 'm-bmw', start: ws, end: we), booked: {
      'm-bmw': [BookedDateRange(start: we, end: DateTime(we.year, we.month, we.day + 2), status: 'confirmed')],
    }),
    calc('over_limit', CalcState(motoId: 'm-shot', start: ws, end: DateTime(ws.year, ws.month, ws.day + 34))),
    calc('booked_loading', CalcState(motoId: 'm-bmw', start: ws, end: we), bookedLoading: true),
    calc('booked_error', CalcState(motoId: 'm-bmw', start: ws, end: we), bookedError: Exception('net')),
    calc('loyalty_fail', CalcState(motoId: 'm-bmw', start: ws, end: we), loyaltyError: Exception('rpc')),
    calc('bike_picker_sheet', CalcState(start: ws, end: we), after: _openBikePicker),
    d('nodates', () => catalogOverrides()),
    d('dates', () => catalogOverrides(filter: dated)),
    d('dates_calendar', () => catalogOverrides(filter: dated), after: _expandCalendar),
    d('loading', () => catalogOverrides(motosLoading: true), loading: true),
    d('error', () => catalogOverrides(motosError: Exception('net'))),
    d('gone', () => catalogOverrides(), build: () => detail('m-gone')),
    // Carried dates over a booked day (r2): open calendar, warning, CTA off.
    d('dates_busy', () => catalogOverrides(filter: dated, booked: {
          'm-bmw': [BookedDateRange(start: we, end: we, status: 'confirmed')],
        })),
    d('booked_loading', () => catalogOverrides(bookedLoading: true), loading: true),
    d('booked_error', () => catalogOverrides(bookedError: Exception('x'))),
    d('loyalty_fail', () => catalogOverrides(filter: dated, loyaltyError: Exception('rpc'))),
    d('guest_rank0', () => catalogOverrides(filter: dated, loyalty: null)),
    d('pager', () => [...catalogOverrides(), filteredMotoIdsProvider.overrideWith((ref) => ['m-bmw', 'm-husq', 'm-shot'])],
        build: () => const MotoDetailScreen(motoId: 'm-husq')),
  ];
}
