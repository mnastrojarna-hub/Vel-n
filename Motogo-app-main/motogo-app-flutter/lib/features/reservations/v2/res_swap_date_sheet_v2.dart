import 'package:flutter/material.dart';

import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 single-day pick for the swap date (instead of the Material date
/// dialog): a light sheet with the trip calendar, only [first]..[last]
/// tappable (the old dialog's firstDate / lastDate), the current day
/// selected. A tap returns that day (= the dialog's OK) and closes; ✕ /
/// swipe-down / back return null (= Cancel). The caller runs the SAME
/// code path with the result as with the old dialog.
Future<DateTime?> showSwapDateSheetV2(
  BuildContext context, {
  required DateTime first,
  required DateTime last,
  required DateTime initial,
  required String title,
}) =>
    showMgSheet<DateTime>(
      context,
      title: title,
      builder: (c) => SwapDateCalendarV2(
        first: first,
        last: last,
        initial: initial,
        onPick: (d) => Navigator.of(c).pop(d),
      ),
    );

class SwapDateCalendarV2 extends StatefulWidget {
  final DateTime first;
  final DateTime last;
  final DateTime initial;
  final ValueChanged<DateTime> onPick;
  const SwapDateCalendarV2({super.key, required this.first, required this.last, required this.initial, required this.onPick});

  @override
  State<SwapDateCalendarV2> createState() => _SwapDateCalendarV2State();
}

class _SwapDateCalendarV2State extends State<SwapDateCalendarV2> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  bool _inRange(DateTime d) => !_d(d).isBefore(_d(widget.first)) && !_d(d).isAfter(_d(widget.last));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstMonth = DateTime(widget.first.year, widget.first.month);
    final lastMonth = DateTime(widget.last.year, widget.last.month);
    return TripCalendar(
      month: _month,
      dayStateOf: (day) {
        final d = _d(day);
        final ok = _inRange(d);
        return TripDayState(
          date: d,
          kind: ok ? TripDayKind.free : (d.isBefore(today) ? TripDayKind.past : TripDayKind.outOfLimit),
          selected: d == _d(widget.initial) ? TripSel.single : TripSel.none,
          today: d == today,
          enabled: ok,
        );
      },
      onTapDay: (day) {
        if (_inRange(day)) widget.onPick(_d(day));
      },
      onPrevMonth: _month.isAfter(firstMonth) ? () => setState(() => _month = DateTime(_month.year, _month.month - 1)) : null,
      onNextMonth: _month.isBefore(lastMonth) ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
    );
  }
}
