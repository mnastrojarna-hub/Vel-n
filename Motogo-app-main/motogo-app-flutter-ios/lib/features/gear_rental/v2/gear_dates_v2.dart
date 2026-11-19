import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../booking/v2/booking_v2_parts.dart' show BkCard;
import '../gear_order_state.dart';
import '../gear_quote.dart';
import 'gear_branch_v2.dart' show GearNoteV2;

/// Krok 2 „Termín“: 1. klepnutí = 1 den, 2. klepnutí na pozdější den =
/// konec (jen volné dny, nejvýš `max_days`), „Zrušit výběr“; nad mřížkou
/// nápověda webu, varování oranžově.
class GearDatesV2 extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  const GearDatesV2({super.key, required this.state, required this.ctrl});

  TripDayState _day(DateTime d) {
    final st = state.dayState(d);
    final kind = switch (st) {
      GearDay.past => TripDayKind.past,
      GearDay.busy => TripDayKind.closed,
      GearDay.free => d.weekday >= 6 ? TripDayKind.freeWeekend : TripDayKind.free,
    };
    final s = state.start;
    final pending = state.open && s != null && tripSameDay(d, s);
    return TripDayState(
      date: d,
      kind: kind,
      selected: tripSelOf(d, s, state.open ? null : state.end),
      today: tripSameDay(d, state.data!.today) && st == GearDay.free,
      pendingStart: pending,
      enabled: st == GearDay.free,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final month = state.month ?? DateTime(state.data!.today.year, state.data!.today.month);
    final warn = state.calNote != null;
    return BkCard(
      key: const ValueKey('gear-step-dates'),
      icon: MgIcons.calendarCheck,
      title: tr.tr('groStepDates'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgEnter(
          trigger: state.hint.key,
          child: Semantics(
            liveRegion: true,
            child: GearNoteV2(
              state.hint.text(tr),
              key: const ValueKey('gear-date-hint'),
              color: warn ? MgColors.warn : null,
              icon: warn ? MgIcons.warn : MgIcons.info,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TripCalendar(
          month: month,
          dayStateOf: _day,
          onTapDay: ctrl.tapDay,
          onPrevMonth: ctrl.canShiftMonth(-1) ? () => ctrl.shiftMonth(-1) : null,
          onNextMonth: ctrl.canShiftMonth(1) ? () => ctrl.shiftMonth(1) : null,
          boxed: false,
          legend: const TripLegend(hatchBusy: true),
        ),
        if (state.start != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('gear-cal-clear'),
              onPressed: ctrl.clearDates,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: MgColors.link),
              child: Text(tr.tr('groCalClear'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
            ),
          ),
      ]),
    );
  }
}
