import 'package:flutter/material.dart';

import '../../../core/date_days.dart' show nextCalendarDay;
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
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

  /// CB-24: the first booked day of a refused range (null = none) and the
  /// attempt counter that shakes the note again.
  final DateTime? blockedDay;
  final int blockedTry;

  /// Days every branch is closed are drawn (`branch_closed`): the legend
  /// gets "Zavřeno" (5.0.1 FV-01) — its own cell tone, not the taken-day
  /// hatch (FR-05).
  final bool closedLegend;
  final bool Function(DateTime)? isClosed;

  /// "Obsazeno" in the legend (off = no bookings drawn, FR-05).
  final bool legendBusy;

  const AvailabilityCalendarV2View({
    this.dayPrices,
    this.closedLegend = false,
    this.isClosed,
    this.legendBusy = true,
    this.blockedDay,
    this.blockedTry = 0,
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

  /// V22 §3.3 "Range crosses a busy day": a range over a booked day (only a
  /// CARRIED one — the detail / calculator opened with dates from the list,
  /// Home or a draft; the State's own tap refuses it) draws NO band, so a
  /// cell never reads "selected" and "busy" at once. Only the start stays
  /// (pending-start capsule); the owner's amber note + "Změnit termín" say
  /// why. Computed once per build.
  bool get _crossesBusy {
    if (start == null || end == null) return false;
    var d = tripDay(start!);
    final e = tripDay(end!);
    while (!d.isAfter(e)) {
      if (isOccupied(d)) return true;
      d = nextCalendarDay(d);
    }
    return false;
  }

  TripDayState _state(DateTime d, bool crosses) {
    final past = isPast(d);
    final occupied = isOccupied(d);
    final kind = past
        ? TripDayKind.past
        : occupied
            ? (isClosed?.call(d) ?? false)
                ? TripDayKind.closed
                : (isUnconfirmed(d) ? TripDayKind.pending : TripDayKind.busy)
            : (d.weekday >= 6 ? TripDayKind.freeWeekend : TripDayKind.free);
    // A busy start stays a busy cell — nothing selected is drawn then.
    final startOnly = crosses && !occupied && tripSameDay(d, start!);
    return TripDayState(
      date: d,
      kind: kind,
      price: _price(d),
      selected: crosses ? (startOnly ? TripSel.single : TripSel.none) : tripSelOf(d, start, end),
      // A booked / closed today gets no green outline (it read as a picked day).
      today: isToday(d) && !occupied,
      pendingStart: startOnly || (step == 2 && end == null && start != null && tripSameDay(d, start!)),
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
                ? tr.tr('v2UxCbCalPickStart')
                : (end != null && tripSameDay(start!, end!)
                    ? tr.tr('efoCalReset')
                    : tr.tr('v2CalTapToChange')))
            : tr.tr('v2UxCbCalPickEnd'));
    final crosses = _crossesBusy;
    return TripCalendar(
      month: DateTime(year, month),
      dayStateOf: (d) => _state(d, crosses),
      onTapDay: onDayTap,
      onPrevMonth: onPrevMonth,
      onNextMonth: onNextMonth,
      boxed: false,
      banner: blockedDay == null
          ? null
          : MgShake(
              trigger: blockedTry,
              child: MgStateBanner(
                tone: MgTone.warn,
                title: tr.trArgs('v2UxCbRangeBusy', {'date': tripShortDate(tr, blockedDay!)}),
              ),
            ),
      legend: showLegend
          // Hatched swatch: the taken cells are hatched too.
          ? TripLegend(hatchBusy: true, items: [
              TripLegendKind.free,
              TripLegendKind.yours,
              if (legendBusy) TripLegendKind.busy,
              TripLegendKind.pending,
              if (closedLegend) TripLegendKind.closed,
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
