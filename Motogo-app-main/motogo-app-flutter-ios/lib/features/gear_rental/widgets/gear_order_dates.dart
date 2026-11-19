import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../../core/v2/calendar/trip_day_state.dart' show tripMonthTitle;
import '../../booking/booking_ui_helpers.dart' show bookingCard;
import '../gear_order_state.dart';
import '../gear_quote.dart';
import 'gear_order_branch.dart' show GearOldNote;

/// Krok 2 (starý vzhled): nápověda webu, měsíční mřížka (volné dny
/// zeleně, minulé / zavřené tmavě jako starý kalendář) a „Zrušit výběr“.
class GearOrderDates extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  const GearOrderDates({super.key, required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final today = state.data!.today;
    final m = state.month ?? DateTime(today.year, today.month);
    final days = DateTime(m.year, m.month + 1, 0).day;
    final offset = DateTime(m.year, m.month, 1).weekday - 1;
    return bookingCard(
      2,
      tr.tr('groStepDates'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GearOldNote(state.hint.text(tr), key: const ValueKey('gear-date-hint'), warn: state.calNote != null),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            tooltip: tr.tr('groPrev'),
            onPressed: ctrl.canShiftMonth(-1) ? () => ctrl.shiftMonth(-1) : null,
            icon: const Icon(Icons.chevron_left, color: MotoGoColors.black),
          ),
          Text(tripMonthTitle(tr, m),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          IconButton(
            tooltip: tr.tr('groNext'),
            onPressed: ctrl.canShiftMonth(1) ? () => ctrl.shiftMonth(1) : null,
            icon: const Icon(Icons.chevron_right, color: MotoGoColors.black),
          ),
        ]),
        Row(children: [
          for (var w = 1; w <= 7; w++)
            Expanded(
              child: Center(
                child: Text(tr.tr('v2CalWdAbbr$w'),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < offset; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++) _cell(DateTime(m.year, m.month, d), today),
          ],
        ),
        if (state.start != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('gear-cal-clear'),
              onPressed: ctrl.clearDates,
              child: Text(tr.tr('groCalClear'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
            ),
          ),
      ]),
    );
  }

  Widget _cell(DateTime d, DateTime today) {
    final st = state.dayState(d);
    final s = state.start, e = state.open ? state.start : state.end;
    bool same(DateTime? x) => x != null && x.year == d.year && x.month == d.month && x.day == d.day;
    final isStart = same(s), isEnd = same(e);
    final inRange = s != null && e != null && d.isAfter(s) && d.isBefore(e);
    final sel = isStart || isEnd || inRange;
    var radius = BorderRadius.circular(9);
    if (isStart && !isEnd) {
      radius = const BorderRadius.horizontal(left: Radius.circular(50));
    } else if (isEnd && !isStart) {
      radius = const BorderRadius.horizontal(right: Radius.circular(50));
    } else if (inRange) {
      radius = BorderRadius.zero;
    }
    final free = st == GearDay.free;
    final bg = sel || !free ? MotoGoColors.dark : MotoGoColors.green;
    final fg = sel ? Colors.white : (free ? Colors.black : Colors.white.withValues(alpha: 0.7));
    return GestureDetector(
      key: ValueKey('gear-day-${gearIso(d)}'),
      onTap: free ? () => ctrl.tapDay(d) : null,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: same(today) && !sel ? Border.all(color: MotoGoColors.greenDark, width: 2) : null,
        ),
        child: Center(
          child: Text('${d.day}',
              style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w900 : FontWeight.w600, color: fg)),
        ),
      ),
    );
  }
}
