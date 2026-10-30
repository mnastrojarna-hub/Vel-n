import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../moto_model.dart' show DayPrices;

/// v2 look of `AvailabilityCalendar` (V-seam): the SAME State owns the
/// month, the selection step and every tap (`_onDayTap` with its occupied-
/// range snackbar, `_prevMonth`, `_nextMonth`); this view only maps that
/// state to `TripDayState`s and draws the uniform range band.
class AvailabilityCalendarV2View extends StatelessWidget {
  final int year;
  final int month;
  final DateTime? start;
  final DateTime? end;
  final int step;
  final bool readOnly;
  final bool showLegend;
  final bool Function(DateTime) isPast;
  final bool Function(DateTime) isOccupied;
  final bool Function(DateTime) isUnconfirmed;
  final bool Function(DateTime) isToday;
  final void Function(DateTime) onDayTap;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  /// Bike's list price per weekday (V22 §3.2: 10/700 under every free
  /// day) — display only, the pricing engine is untouched. Null = no bike
  /// (date filter of the list) → no prices.
  final DayPrices? dayPrices;

  const AvailabilityCalendarV2View({
    this.dayPrices,
    super.key,
    required this.year,
    required this.month,
    required this.start,
    required this.end,
    required this.step,
    required this.readOnly,
    required this.showLegend,
    required this.isPast,
    required this.isOccupied,
    required this.isUnconfirmed,
    required this.isToday,
    required this.onDayTap,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  TripDayState _state(DateTime d) {
    final past = isPast(d);
    final occupied = isOccupied(d);
    final kind = past
        ? TripDayKind.past
        : occupied
            ? (isUnconfirmed(d) ? TripDayKind.pending : TripDayKind.busy)
            : (d.weekday >= 6 ? TripDayKind.freeWeekend : TripDayKind.free);
    return TripDayState(
      date: d,
      kind: kind,
      price: _price(d),
      selected: tripSelOf(d, start, end),
      today: isToday(d),
      pendingStart: step == 2 && end == null && start != null && tripSameDay(d, start!),
      enabled: !readOnly && !past && !occupied,
    );
  }

  /// "3 514" (no-break group space; TripDayState hides it on non-free days).
  String? _price(DateTime d) {
    final v = dayPrices?.forWeekday(d.weekday) ?? 0;
    if (v <= 0) return null;
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('\u00A0');
      b.write(s[i]);
    }
    return b.toString();
  }

  bool get _hasPrices => dayPrices != null && dayPrices!.cheapest > 0;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // Same helper texts as the old step indicator.
    final helper = readOnly
        ? null
        : (step == 1
            ? (start == null
                ? tr.tr('calSelectPickup')
                : (end != null && tripSameDay(start!, end!)
                    ? tr.tr('calClickToReset')
                    : tr.tr('v2CalTapToChange')))
            : tr.tr('calSelectReturn'));
    return TripCalendar(
      month: DateTime(year, month),
      dayStateOf: _state,
      onTapDay: onDayTap,
      onPrevMonth: onPrevMonth,
      onNextMonth: onNextMonth,
      boxed: false,
      legend: showLegend
          ? const TripLegend(items: [
              TripLegendKind.free,
              TripLegendKind.yours,
              TripLegendKind.busy,
              TripLegendKind.pending,
            ])
          : null,
      note: !_hasPrices
          ? (helper == null ? null : TripCalendarNote(helper))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              if (helper != null) ...[TripCalendarNote(helper), const SizedBox(height: 6)],
              TripCalendarNote(tr.tr('v2CalPriceNote')),
            ]),
    );
  }
}
