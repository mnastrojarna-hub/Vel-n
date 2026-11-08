// catalog_booking package: CB-22 time sheet (every value of the old two
// dropdowns is one tap away and yields the same "HH:MM"; ✕ / swipe-down
// keep the value) and CB-24 calendar feedback (busy day → toast; a range
// over a busy day → inline note that shakes, start kept, nothing set).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/calendar/trip_day_state.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_sheet.dart';
import 'package:motogo_app/core/widgets/time_dropdown_field.dart';
import 'package:motogo_app/features/booking/v2/time_sheet_v2.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';

import '../support/v2_harness.dart';

final _cs = AppTranslations.of('cs');
Finder _inSheet(String s) => find.descendant(of: find.byType(MgSheetFrame), matching: find.text(s));

Future<List<String>> _time(WidgetTester t, String value, {bool reduced = true}) async {
  final out = <String>[];
  await pumpV2(t, Center(child: TimeDropdownField(value: value, onChanged: out.add, sheetTitle: 'Čas')),
      reducedMotion: reduced);
  await t.tap(find.byType(TimeFieldV2));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return out;
}

void main() {
  setUpAll(loadMontserrat);
  setUp(MgMotion.resetSession);

  testWidgets('CB-22: every hour × minute of the old dropdowns is a chip; a tap = the same "HH:MM"', (t) async {
    final out = await _time(t, '09:00');
    expect(find.byType(MgSheetFrame), findsOneWidget);
    for (var h = 0; h <= 23; h++) {
      for (final m in [0, 15, 30, 45]) {
        expect(_inSheet(TimeFieldV2.fmt(h, m)), findsOneWidget, reason: '$h:$m');
      }
    }
    final pick = _inSheet('13:45');
    await t.ensureVisible(pick);
    await t.pump();
    await t.tap(pick);
    await t.pump(const Duration(milliseconds: 400));
    expect(out, ['13:45']);
    expect(find.byType(MgSheetFrame), findsNothing);
  });

  testWidgets('CB-22: an off-step current minute stays offered (old rule), selected and in view', (t) async {
    final out = await _time(t, '23:59');
    expect(_inSheet('23:59'), findsOneWidget);
    expect(_inSheet('07:59'), findsOneWidget);
    final r = t.getRect(_inSheet('23:59'));
    expect(r.top, lessThan(780));
    // Swipe-down from the header (the body is scrolled to 23:00) keeps the value.
    await t.dragFrom(t.getTopLeft(find.byType(MgSheetFrame)) + const Offset(120, 20), const Offset(0, 700));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(MgSheetFrame), findsNothing);
    expect(out, isEmpty);
  });

  testWidgets('CB-22: flag OFF keeps the two old dropdowns', (t) async {
    await pumpV2(t, Center(child: TimeDropdownField(value: '09:00', onChanged: (_) {})), v2: false);
    expect(find.byType(TimeFieldV2), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(2));
  });

  group('CB-24 calendar feedback', () {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month + 1, 1);
    DateTime day(int d) => DateTime(base.year, base.month, d);

    Future<List<(DateTime, DateTime)>> pump(WidgetTester t, {bool v2 = true}) async {
      final out = <(DateTime, DateTime)>[];
      await pumpV2(
        t,
        SingleChildScrollView(
          child: AvailabilityCalendar(
            selectedStart: day(2),
            selectedEnd: day(3),
            bookedDates: [BookedDateRange(start: day(10), end: day(10), status: 'confirmed')],
            onRangeSelected: (s, e) => out.add((s, e)),
          ),
        ),
        v2: v2,
        reducedMotion: true,
        size: const Size(412, 915),
      );
      await t.pump(const Duration(milliseconds: 300));
      return out;
    }

    Future<void> tapDay(WidgetTester t, int d) async {
      await t.tap(find.text('$d').first, warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
    }

    // lookonly-fix (owner 2026-11-07 "jen upgrade vzhledu"): a busy day
    // does not react, exactly as the original calendar (no toast).
    testWidgets('busy day tap → no reaction (no toast), nothing selected', (t) async {
      final out = await pump(t);
      await tapDay(t, 10);
      expect(find.text(_cs.tr('v2UxCbBusyDay')), findsNothing);
      expect(out, isEmpty);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('range over a busy day → inline note + shake, start kept, range not set', (t) async {
      final out = await pump(t);
      await tapDay(t, 8);
      await tapDay(t, 12);
      final note = _cs.trArgs('v2UxCbRangeBusy', {'date': tripShortDate(_cs, day(10))});
      expect(find.text(note), findsOneWidget);
      expect(find.ancestor(of: find.byType(MgStateBanner), matching: find.byType(MgShake)), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(out, isEmpty);
      // Start kept: a valid end now completes the range and clears the note.
      await tapDay(t, 9);
      expect(out, [(day(8), day(9))]);
      expect(find.text(note), findsNothing);
    });

    testWidgets('helper copy is tykání: "Vyber datum vrácení" while picking the end', (t) async {
      await pump(t);
      await tapDay(t, 8);
      expect(find.text(_cs.tr('v2UxCbCalPickEnd')), findsOneWidget);
    });

    testWidgets('flag OFF keeps the old SnackBar', (t) async {
      final out = await pump(t, v2: false);
      await tapDay(t, 8);
      await tapDay(t, 12);
      expect(find.text(_cs.tr('calRangeOccupied')), findsOneWidget);
      expect(out, isEmpty);
      await t.pump(const Duration(seconds: 3));
    });
  });
}
