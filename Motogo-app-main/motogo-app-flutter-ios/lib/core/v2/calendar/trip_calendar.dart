import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import 'trip_calendar_parts.dart';
import 'trip_day_cell.dart';
import 'trip_day_state.dart';

export 'trip_calendar_parts.dart';
export 'trip_day_cell.dart' show TripDayCell, tripBandRadii;
export 'trip_day_state.dart';

/// The ONE range calendar of the v2 look (DESIGN_V22 §3): month header,
/// weekdays, a 7-column grid with 0 horizontal gap (so the range is a single
/// uniform band per row), optional summary row / helper / banner above and
/// legend / note below. PRESENTATIONAL ONLY — selection rules stay with the
/// existing logic owner, which maps its state through [dayStateOf] and
/// handles [onTapDay] exactly as today.
class TripCalendar extends StatelessWidget {
  final DateTime month;
  final TripDayState Function(DateTime day) dayStateOf;
  final ValueChanged<DateTime>? onTapDay;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;
  final Widget? summary;
  final Widget? helper;
  final Widget? banner;
  final Widget? legend;
  final Widget? note;
  final TripSkin skin;

  /// Draw the white r18 calendar box (light skin) around the grid.
  final bool boxed;

  /// Currency label appended to day prices for screen readers ("Kč").
  final String? currency;

  const TripCalendar({
    super.key,
    required this.month,
    required this.dayStateOf,
    this.onTapDay,
    this.onPrevMonth,
    this.onNextMonth,
    this.summary,
    this.helper,
    this.banner,
    this.legend,
    this.note,
    this.skin = TripSkin.light,
    this.boxed = true,
    this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final cells = offset + daysInMonth;
    final rows = (cells / 7).ceil();
    final states = <int, TripDayState>{
      for (var d = 1; d <= daysInMonth; d++) d: dayStateOf(DateTime(month.year, month.month, d)),
    };
    var order = 0;
    final bandOrder = <int, int>{};
    for (var d = 1; d <= daysInMonth; d++) {
      if (states[d]!.isSelected) bandOrder[d] = order++;
    }

    final grid = Column(children: [
      for (var r = 0; r < rows; r++)
        Padding(
          padding: EdgeInsets.only(top: r == 0 ? 0 : 4),
          child: Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(child: _cell(tr, r * 7 + c - offset + 1, daysInMonth, states, bandOrder, c)),
          ]),
        ),
    ]);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TripCalendarHeader(month: month, onPrev: onPrevMonth, onNext: onNextMonth, skin: skin),
        if (summary != null) ...[const SizedBox(height: MgSpace.s8), summary!],
        if (banner != null) ...[const SizedBox(height: MgSpace.s8), banner!],
        if (helper != null) ...[const SizedBox(height: MgSpace.s8), helper!],
        const SizedBox(height: MgSpace.s12),
        TripWeekdays(skin: skin),
        const SizedBox(height: MgSpace.s6),
        grid,
        if (legend != null) ...[const SizedBox(height: MgSpace.s12), legend!],
        if (note != null) ...[const SizedBox(height: MgSpace.s8), note!],
      ],
    );
    if (!boxed || skin == TripSkin.dark) return body;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.receipt),
        border: Border.all(color: MgColors.line),
      ),
      child: body,
    );
  }

  Widget _cell(AppTranslations tr, int day, int daysInMonth, Map<int, TripDayState> states,
      Map<int, int> bandOrder, int col) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: TripDayCell.height);
    final s = states[day]!;
    return TripDayCell(
      state: s,
      rowStart: col == 0 || day == 1,
      rowEnd: col == 6 || day == daysInMonth,
      skin: skin,
      bandOrder: bandOrder[day] ?? 0,
      semanticLabel: tripDayA11y(tr, s, currency: currency),
      onTap: onTapDay == null ? null : () => onTapDay!(s.date),
    );
  }
}
