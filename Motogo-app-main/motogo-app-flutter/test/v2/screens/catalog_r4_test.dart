// Catalog fix round 4 (v2, Android): a CARRIED range over a booked day
// (detail opened with dates over a busy day, calculator "busy_in_range")
// draws NO band across the hatched / struck day (DESIGN_V22 §3.3 "Range
// crosses a busy day") — only the start stays as the pending-start
// capsule; the amber note + "Změnit termín" of the owner stay. The
// calendar's own tap logic (`_onDayTap`) is untouched: a tapped range
// over a busy day is still refused with the snackbar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/calc/calc_state.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];
const _langs = ['cs', 'de', 'uk'];

List<TripDayState> _cells(WidgetTester t) =>
    t.widgetList<TripDayCell>(find.byType(TripDayCell, skipOffstage: false)).map((c) => c.state).toList();

TripDayState _cell(WidgetTester t, DateTime d) => _cells(t).singleWhere((s) => tripSameDay(s.date, d));

/// The band is one uniform fill: a busy / pending cell can never be inside
/// it; with a range over a booked day only the start is drawn, as the
/// pending-start capsule.
void _expectNoBandOverBusy(WidgetTester t, DateTime start) {
  final cells = _cells(t);
  expect(cells, isNotEmpty);
  for (final s in cells) {
    expect(s.isSelected && (s.kind == TripDayKind.busy || s.kind == TripDayKind.pending), isFalse,
        reason: '${s.date} selected and busy at once');
  }
  final selected = cells.where((s) => s.isSelected).toList();
  expect(selected.map((s) => s.date), [start]);
  expect([selected.single.selected, selected.single.pendingStart], [TripSel.single, true]);
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });
  setUp(MgMotion.resetSession);
  final (ws, we) = futureWeekend();
  final sat = DateTime(ws.year, ws.month, ws.day + 1);
  final dated = CatalogFilter(startDate: ws, endDate: we);
  final calcMode = catalogCalcRequestProvider.overrideWith((ref) => true);

  group('AvailabilityCalendar v2 view', () {
    Future<void> pump(WidgetTester t, {required List<BookedDateRange> booked, DateTime? s, DateTime? e}) =>
        pumpV2(t, SingleChildScrollView(child: AvailabilityCalendar(bookedDates: booked, selectedStart: s, selectedEnd: e)));

    testWidgets('carried range over a busy end day: no band, start = pending capsule', (t) async {
      await pump(t, booked: [BookedDateRange(start: we, end: we, status: 'confirmed')], s: ws, e: we);
      _expectNoBandOverBusy(t, ws);
      expect(_cell(t, sat).selected, TripSel.none);
      expect([_cell(t, we).kind, _cell(t, we).selected], [TripDayKind.busy, TripSel.none]);
      expect(t.takeException(), isNull);
    });

    testWidgets('busy day in the middle (pending booking) — same rule', (t) async {
      await pump(t, booked: [BookedDateRange(start: sat, end: sat, status: 'pending')], s: ws, e: we);
      _expectNoBandOverBusy(t, ws);
      expect([_cell(t, sat).kind, _cell(t, we).selected], [TripDayKind.pending, TripSel.none]);
    });

    testWidgets('busy START day: nothing is drawn selected', (t) async {
      await pump(t, booked: [BookedDateRange(start: ws, end: ws, status: 'confirmed')], s: ws, e: we);
      expect(_cells(t).where((s) => s.isSelected), isEmpty);
      expect([_cell(t, ws).kind, _cell(t, ws).enabled], [TripDayKind.busy, false]);
    });

    testWidgets('free range: the uniform band stays (start / mid / end)', (t) async {
      await pump(t, booked: [BookedDateRange(start: DateTime(we.year, we.month, we.day + 3), end: DateTime(we.year, we.month, we.day + 4), status: 'confirmed')], s: ws, e: we);
      expect([_cell(t, ws).selected, _cell(t, sat).selected, _cell(t, we).selected], [TripSel.start, TripSel.mid, TripSel.end]);
      expect(_cells(t).any((s) => s.pendingStart), isFalse);
    });

    testWidgets('start chosen by tap, end pending: ring as before; a tapped range over a busy day is refused', (t) async {
      await pump(t, booked: [BookedDateRange(start: sat, end: sat, status: 'confirmed')]);
      await t.tap(find.byWidgetPredicate((w) => w is TripDayCell && tripSameDay(w.state.date, ws), skipOffstage: false));
      await t.pump(const Duration(milliseconds: 300));
      expect([_cell(t, ws).selected, _cell(t, ws).pendingStart], [TripSel.single, true]);
      await t.tap(find.byWidgetPredicate((w) => w is TripDayCell && tripSameDay(w.state.date, we), skipOffstage: false));
      await t.pump(const Duration(milliseconds: 300));
      // CB-24: inline note (V22 §3.3) instead of the old SnackBar.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MgStateBanner), findsOneWidget);
      expect([_cell(t, ws).selected, _cell(t, we).selected], [TripSel.single, TripSel.none]);
    });
  });

  // Render check of both owners of a carried busy range (cs / de / uk ×
  // 320–412): the calendar is open, no band over the busy day, no overflow.
  for (final lang in _langs) {
    for (final size in _sizes) {
      final tag = '$lang ${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('detail dates_busy $tag', (t) async {
        await pumpV2(t, MotoDetailPage(motoId: 'm-bmw', showBackButton: true), lang: lang, size: size, overrides: catalogOverrides(filter: dated, booked: {
          'm-bmw': [BookedDateRange(start: we, end: we, status: 'confirmed')],
        }));
        await t.pump(const Duration(milliseconds: 400));
        await t.scrollUntilVisible(find.byType(AvailabilityCalendar, skipOffstage: false), 150, scrollable: find.byType(Scrollable).first);
        await t.pump(const Duration(milliseconds: 400));
        _expectNoBandOverBusy(t, ws);
        await expectCleanFrames(t);
      });

      testWidgets('calc busy_in_range $tag', (t) async {
        await pumpV2(t, const MotorkyScreenV2(), lang: lang, size: size, overrides: [
          ...catalogOverrides(calc: CalcState(motoId: 'm-bmw', start: ws, end: we), booked: {
            'm-bmw': [BookedDateRange(start: we, end: DateTime(we.year, we.month, we.day + 2), status: 'confirmed')],
          }),
          calcMode,
        ]);
        await t.pump(const Duration(milliseconds: 400));
        await t.scrollUntilVisible(find.byType(AvailabilityCalendar, skipOffstage: false), 150, scrollable: find.byType(Scrollable).first);
        await t.pump(const Duration(milliseconds: 400));
        _expectNoBandOverBusy(t, ws);
        await expectCleanFrames(t);
      });
    }
  }
}
