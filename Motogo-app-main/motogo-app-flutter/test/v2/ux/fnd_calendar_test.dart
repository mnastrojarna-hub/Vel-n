// FND-9: month fling (off inside a swipeable pager — the pager keeps the
// swipe, owner parity rule), month slide, band timing,
// reduced motion = band painted at once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';

import '../support/v2_harness.dart';

TripDayState _state(DateTime d, DateTime start, DateTime end) =>
    TripDayState(date: d, selected: tripSelOf(d, start, end), price: '3 514');

class _Cal extends StatefulWidget {
  final ValueChanged<DateTime>? onMonth;
  const _Cal({this.onMonth});
  @override
  State<_Cal> createState() => _CalState();
}

class _CalState extends State<_Cal> {
  DateTime month = DateTime(2026, 10);

  void _go(int d) {
    setState(() => month = DateTime(month.year, month.month + d));
    widget.onMonth?.call(month);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: TripCalendar(
          month: month,
          dayStateOf: (d) => _state(d, DateTime(month.year, month.month, 8), DateTime(month.year, month.month, 12)),
          onTapDay: (_) {},
          onPrevMonth: () => _go(-1),
          onNextMonth: () => _go(1),
        ),
      );
}

void main() {
  setUpAll(loadMontserrat);

  testWidgets('fling ← = next month, → = previous (no pager around)', (tester) async {
    final months = <DateTime>[];
    await pumpV2(tester, _Cal(onMonth: months.add));
    await tester.fling(find.text('15'), const Offset(-220, 0), 1200);
    await tester.pumpAndSettle();
    expect(months, [DateTime(2026, 11)]);
    await tester.fling(find.text('15'), const Offset(220, 0), 1200);
    await tester.pumpAndSettle();
    expect(months.last, DateTime(2026, 10));
  });

  testWidgets('inside a swipeable pager (moto detail): a swipe over the calendar pages, months stay', (tester) async {
    for (final fast in [false, true]) {
      final pc = PageController();
      final months = <DateTime>[];
      await pumpV2(tester, PageView(key: ValueKey(fast), controller: pc, children: [_Cal(onMonth: months.add), const Text('page 2')]));
      if (fast) {
        await tester.fling(find.text('15'), const Offset(-220, 0), 1200);
      } else {
        await tester.drag(find.text('15'), const Offset(-260, 0));
      }
      await tester.pumpAndSettle();
      expect(pc.page, 1, reason: 'fast=$fast');
      expect(months, isEmpty, reason: 'fast=$fast');
    }
  });

  testWidgets('a pager that cannot be swiped keeps the month fling', (tester) async {
    final months = <DateTime>[];
    await pumpV2(
      tester,
      PageView(physics: const NeverScrollableScrollPhysics(), children: [_Cal(onMonth: months.add), const Text('page 2')]),
    );
    await tester.fling(find.text('15'), const Offset(-220, 0), 1200);
    await tester.pumpAndSettle();
    expect(months, [DateTime(2026, 11)]);
  });

  testWidgets('‹ › taps still switch months', (tester) async {
    final months = <DateTime>[];
    await pumpV2(tester, _Cal(onMonth: months.add));
    await tester.tap(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.chevronRight));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.chevronLeft));
    await tester.pumpAndSettle();
    expect(months, [DateTime(2026, 11), DateTime(2026, 10)]);
  });

  test('band grows 20 ms per day, capped at 200 ms', () {
    expect(TripDayCell.bandDelay(0), Duration.zero);
    expect(TripDayCell.bandDelay(3), const Duration(milliseconds: 60));
    expect(TripDayCell.bandDelay(30), const Duration(milliseconds: 200));
  });

  testWidgets('band animates normally; reduced motion paints it at once', (tester) async {
    await pumpV2(tester, const _Cal());
    expect(find.byType(MgProgressOnce), findsWidgets);
    await tester.pumpAndSettle();
    await pumpV2(tester, const _Cal(), reducedMotion: true);
    await tester.pump();
    expect(find.byType(MgProgressOnce), findsNothing);
    expect(find.text('10'), findsOneWidget);
  });
}
