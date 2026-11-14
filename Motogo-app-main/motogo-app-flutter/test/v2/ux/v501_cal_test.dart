// 5.0.1 step H (owner 2026-11-14: "jen změna barvy"): a calendar day of the
// new look is either free or ONE "Obsazeno" look (booked, pending, closed
// branch, out of limit, the customer's other booking, loading; past = the
// same with a muted number); what can be tapped is unchanged. Red only in
// the reservation edit, for days that leave the booking. Date-independent:
// every day used sits in the previous / next month or in a fixed date.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';
import 'package:motogo_app/features/reservations/v2/res_edit_calendar_v2.dart';
import 'package:motogo_app/features/reservations/v2/res_swap_date_sheet_v2.dart';

import '../support/v2_harness.dart';

final _now = DateTime.now();
final _next = DateTime(_now.year, _now.month + 1);
DateTime _day(int d) => DateTime(_next.year, _next.month, d);

Finder _cell(DateTime d) => find.byWidgetPredicate(
    (w) => w is TripDayCell && w.state.date.year == d.year && w.state.date.month == d.month && w.state.date.day == d.day);

TripDayState _stateOf(WidgetTester t, DateTime d) => t.widget<TripDayCell>(_cell(d)).state;

Future<Uint8List> _rgba(WidgetTester t, GlobalKey key) async {
  final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final b = await t.runAsync(() async => (await ro.toImage()).toByteData(format: ui.ImageByteFormat.rawRgba));
  return b!.buffer.asUint8List();
}

/// One 48 × 46 day cell of a FIXED date (the cell never reads the clock).
Future<Uint8List> _cellPixels(WidgetTester t, TripDayKind kind, TripSkin skin) async {
  final key = GlobalKey();
  await pumpV2(
      t,
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 48,
            child: TripDayCell(state: TripDayState(date: DateTime(2026, 10, 14), kind: kind, enabled: false), skin: skin),
          ),
        ),
      ));
  await t.pump();
  return _rgba(t, key);
}

/// Pixels of the err red (#B42318 stroke / number) in the pumped frame.
int _redPixels(Uint8List b) {
  var n = 0;
  for (var i = 0; i + 3 < b.length; i += 4) {
    if (b[i] >= 150 && b[i + 1] <= 90 && b[i + 2] <= 90 && b[i + 3] > 200) n++;
  }
  return n;
}

const _taken = [
  TripDayKind.busy,
  TripDayKind.pending,
  TripDayKind.yourOther,
  TripDayKind.closed,
  TripDayKind.outOfLimit,
  TripDayKind.loading,
];

void main() {
  setUpAll(loadMontserrat);

  for (final skin in TripSkin.values) {
    testWidgets('every not-free kind is drawn the same "Obsazeno" (${skin.name})', (t) async {
      final busy = await _cellPixels(t, TripDayKind.busy, skin);
      for (final k in _taken) {
        expect(await _cellPixels(t, k, skin), busy, reason: '$k looks like busy');
      }
      expect(await _cellPixels(t, TripDayKind.free, skin), isNot(busy), reason: 'free stays its own look');
      // Past = the same hatched box, only the number is muted.
      final past = await _cellPixels(t, TripDayKind.past, skin);
      const top = 10 * 48 * 4; // rows above the number
      expect(past.sublist(0, top), busy.sublist(0, top), reason: 'past: the same box');
      expect(past, isNot(busy), reason: 'past: a muted number');
    });
  }

  testWidgets('not-free days stay not selectable (catalog, past, swap sheet)', (t) async {
    final starts = <DateTime>[];
    await pumpV2(
        t,
        SingleChildScrollView(
          child: AvailabilityCalendar(showMonth: _next, onStartSelected: starts.add, bookedDates: [
            BookedDateRange(start: _day(10), end: _day(10), status: 'branch_closed'),
            BookedDateRange(start: _day(11), end: _day(11), status: 'confirmed'),
            BookedDateRange(start: _day(12), end: _day(12), status: 'pending'),
          ]),
        ),
        size: const Size(360, 1400),
        reducedMotion: true);
    await t.pump();
    for (final d in [10, 11, 12]) {
      expect(_stateOf(t, _day(d)).enabled, isFalse, reason: 'day $d');
      await t.tap(_cell(_day(d)));
      await t.pump();
    }
    expect(starts, isEmpty, reason: 'closed / booked / pending cannot be picked');
    await t.tap(_cell(_day(15)));
    await t.pump();
    expect(starts.single, _day(15), reason: 'a free day still can');

    final prev = DateTime(_now.year, _now.month - 1);
    final past = DateTime(prev.year, prev.month, 10);
    await pumpV2(t, SingleChildScrollView(child: AvailabilityCalendar(showMonth: prev, onStartSelected: starts.add)),
        size: const Size(360, 1400), reducedMotion: true);
    await t.pump();
    expect(_stateOf(t, past).kind, TripDayKind.past);
    await t.tap(_cell(past));
    await t.pump();
    expect(starts, hasLength(1), reason: 'a past day cannot be picked');

    final picks = <DateTime>[];
    await pumpV2(t, SwapDateCalendarV2(first: _day(5), last: _day(20), initial: _day(10), onPick: picks.add),
        reducedMotion: true);
    await t.pump();
    expect(_stateOf(t, _day(25)).kind, TripDayKind.outOfLimit);
    await t.tap(_cell(_day(25)));
    await t.pump();
    expect(picks, isEmpty, reason: 'out of limit cannot be picked');
    await t.tap(_cell(_day(15)));
    expect(picks.single, _day(15));
  });

  group('red only in the reservation edit', () {
    Future<Uint8List> edit(WidgetTester t, String mode, DateTime ns, DateTime ne) async {
      final key = GlobalKey();
      await pumpV2(
          t,
          SingleChildScrollView(
            child: EditReservationCalendarV2View(
              year: _next.year,
              month: _next.month,
              mode: mode,
              origStart: _day(10),
              origEnd: _day(14),
              newStart: ns,
              newEnd: ne,
              isOccupied: (d) => tripSameDay(d, _day(24)),
              onDayTap: (_) {},
              onPrevMonth: () {},
              onNextMonth: () {},
            ),
          ),
          size: const Size(360, 1400),
          reducedMotion: true,
          boundaryKey: key);
      await t.pump();
      return _rgba(t, key);
    }

    List<TripLegendKind> legend(WidgetTester t) => t.widget<TripLegend>(find.byType(TripLegend)).items;

    testWidgets('shorten and move: days that leave the booking are red', (t) async {
      final short = await edit(t, 'shorten', _day(10), _day(12));
      expect([for (final d in [12, 13, 14]) _stateOf(t, _day(d)).editMark],
          [TripEditMark.none, TripEditMark.removed, TripEditMark.removed]);
      expect(_redPixels(short), greaterThan(40));
      expect(legend(t), contains(TripLegendKind.removed));
      final moved = await edit(t, 'move', _day(17), _day(21));
      expect(_stateOf(t, _day(10)).editMark, TripEditMark.removed);
      expect(_stateOf(t, _day(17)).isSelected, isTrue, reason: 'the new days are the selection');
      expect(_redPixels(moved), greaterThan(40));
      expect(legend(t), [TripLegendKind.free, TripLegendKind.yours, TripLegendKind.removed, TripLegendKind.busy]);
      expect(_stateOf(t, _day(24)).enabled, isFalse, reason: 'a booked day stays not selectable');
    });

    testWidgets('extend: added days are just the selection, no red', (t) async {
      final px = await edit(t, 'extend', _day(10), _day(16));
      expect(_stateOf(t, _day(16)).isSelected, isTrue);
      expect(_redPixels(px), 0);
      expect(legend(t), [TripLegendKind.free, TripLegendKind.yours, TripLegendKind.busy]);
    });

    testWidgets('booking calendar and swap sheet: never red', (t) async {
      final key = GlobalKey();
      await pumpV2(
          t,
          SingleChildScrollView(
            child: AvailabilityCalendar(showMonth: _next, selectedStart: _day(3), selectedEnd: _day(5), bookedDates: [
              BookedDateRange(start: _day(10), end: _day(10), status: 'branch_closed'),
              BookedDateRange(start: _day(11), end: _day(11), status: 'confirmed'),
              BookedDateRange(start: _day(12), end: _day(12), status: 'pending'),
            ]),
          ),
          size: const Size(360, 1400),
          reducedMotion: true,
          boundaryKey: key);
      await t.pump();
      expect(_redPixels(await _rgba(t, key)), 0);
      expect(legend(t), [TripLegendKind.free, TripLegendKind.yours, TripLegendKind.busy]);
      final key2 = GlobalKey();
      await pumpV2(t, SwapDateCalendarV2(first: _day(5), last: _day(20), initial: _day(10), onPick: (_) {}),
          reducedMotion: true, boundaryKey: key2);
      await t.pump();
      expect(_redPixels(await _rgba(t, key2)), 0);
      expect(find.byType(TripLegend), findsNothing);
    });
  });
}
