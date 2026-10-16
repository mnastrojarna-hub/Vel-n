import 'package:flutter/material.dart';

import '../../../core/v2/calendar/trip_calendar.dart';

/// v2 look of `EditReservationCalendar` (V-seam, V22 §3.4): the SAME State
/// owns the month, every tap rule (`_onDayTap`: extend / shorten / move,
/// occupied and past checks with their messages) and the month steps; this
/// view only maps that state to `TripDayState`s — the resulting range is
/// one uniform band, added days carry "+", removed days are red dashed.
class EditReservationCalendarV2View extends StatelessWidget {
  final int year;
  final int month;
  final String mode;
  final DateTime origStart;
  final DateTime origEnd;
  final DateTime? newStart;
  final DateTime? newEnd;
  final bool Function(DateTime) isOccupied;
  final void Function(DateTime) onDayTap;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const EditReservationCalendarV2View({
    super.key,
    required this.year,
    required this.month,
    required this.mode,
    required this.origStart,
    required this.origEnd,
    required this.newStart,
    required this.newEnd,
    required this.isOccupied,
    required this.onDayTap,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  bool _within(DateTime d, DateTime s, DateTime e) => !d.isBefore(tripDay(s)) && !d.isAfter(tripDay(e));

  TripDayState _state(DateTime date) {
    final d = tripDay(date);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inOrig = _within(d, origStart, origEnd);
    final hasNew = newStart != null && newEnd != null;
    final ns = hasNew ? newStart! : origStart;
    final ne = hasNew ? newEnd! : origEnd;
    final inNew = _within(d, ns, ne);
    final past = d.isBefore(today);
    final busy = isOccupied(d) && !inOrig;
    final kind = past
        ? TripDayKind.past
        : busy
            ? TripDayKind.busy
            : (d.weekday >= 6 ? TripDayKind.freeWeekend : TripDayKind.free);
    final mark = switch (mode) {
      'extend' when inNew && !inOrig => TripEditMark.added,
      'shorten' when inOrig && !inNew => TripEditMark.removed,
      _ => TripEditMark.none,
    };
    return TripDayState(
      date: d,
      kind: kind,
      selected: tripSelOf(d, ns, ne),
      today: d == today,
      editMark: mark,
      enabled: !past && !busy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final legend = switch (mode) {
      'shorten' => const [TripLegendKind.yours, TripLegendKind.removed, TripLegendKind.busy],
      'move' => const [TripLegendKind.free, TripLegendKind.yours, TripLegendKind.busy],
      _ => const [TripLegendKind.yours, TripLegendKind.added, TripLegendKind.busy],
    };
    return TripCalendar(
      month: DateTime(year, month),
      dayStateOf: _state,
      onTapDay: onDayTap,
      onPrevMonth: onPrevMonth,
      onNextMonth: onNextMonth,
      boxed: false,
      legend: TripLegend(items: legend),
    );
  }
}
