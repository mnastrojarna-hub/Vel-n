// TripCalendar (DESIGN_V22 §3): one uniform band — start, every middle day
// and end share fill / number colour / weight and differ only by the cap;
// every day state renders in 8 languages × 2 sizes; the AvailabilityCalendar
// V-seam keeps its own tap logic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/widgets/availability_calendar.dart';

import 'support/v2_harness.dart';

final _month = DateTime(2026, 10);

TripDayState _states(DateTime d, {DateTime? start, DateTime? end, bool pending = false}) {
  final day = d.day;
  final kind = switch (day) {
    < 11 => TripDayKind.past,
    13 || 14 => TripDayKind.busy,
    15 => TripDayKind.pending,
    16 => TripDayKind.yourOther,
    30 || 31 => TripDayKind.outOfLimit,
    _ => d.weekday >= 6 ? TripDayKind.freeWeekend : TripDayKind.free,
  };
  final sel = tripSelOf(d, start, end);
  return TripDayState(
    date: d,
    kind: sel != TripSel.none ? TripDayKind.free : kind,
    selected: sel,
    today: day == 11,
    price: kind == TripDayKind.free || kind == TripDayKind.freeWeekend ? '3 514' : null,
    pendingStart: pending && sel == TripSel.single,
    editMark: day == 26 ? TripEditMark.added : (day == 28 ? TripEditMark.removed : TripEditMark.none),
  );
}

Widget _cal({DateTime? start, DateTime? end, bool pending = false, TripSkin skin = TripSkin.light, ValueChanged<DateTime>? onTap}) =>
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: TripCalendar(
        month: _month,
        dayStateOf: (d) => _states(d, start: start, end: end, pending: pending),
        onTapDay: onTap ?? (_) {},
        onPrevMonth: () {},
        onNextMonth: () {},
        skin: skin,
        summary: start == null ? null : TripSummaryRow(start: start, end: end, days: end == null ? null : end.difference(start).inDays + 1, skin: skin),
        banner: const TripAvailabilityBanner(error: true, onRetry: _noop),
        legend: TripLegend(items: TripLegendKind.values, skin: skin),
        note: const TripCalendarNote('Cena/den v Kč (ceník)'),
        currency: 'Kč',
      ),
    );

void _noop() {}

void main() {
  setUpAll(loadMontserrat);

  test('band radii: caps only on the ends, r6 on row wraps, square inside', () {
    const cap = Radius.circular(11), wrap = Radius.circular(6);
    expect(tripBandRadii(TripSel.start), (cap, Radius.zero));
    expect(tripBandRadii(TripSel.mid), (Radius.zero, Radius.zero));
    expect(tripBandRadii(TripSel.end), (Radius.zero, cap));
    expect(tripBandRadii(TripSel.single), (cap, cap));
    expect(tripBandRadii(TripSel.mid, rowEnd: true), (Radius.zero, wrap));
    expect(tripBandRadii(TripSel.mid, rowStart: true), (wrap, Radius.zero));
    expect(tripBandRadii(TripSel.start, rowEnd: true), (cap, wrap));
    expect(tripBandRadii(TripSel.end, rowStart: true), (wrap, cap));
  });

  test('selection of a range', () {
    final s = DateTime(2026, 10, 23), e = DateTime(2026, 10, 27);
    expect(tripSelOf(DateTime(2026, 10, 23), s, e), TripSel.start);
    expect(tripSelOf(DateTime(2026, 10, 25), s, e), TripSel.mid);
    expect(tripSelOf(DateTime(2026, 10, 27), s, e), TripSel.end);
    expect(tripSelOf(DateTime(2026, 10, 28), s, e), TripSel.none);
    expect(tripSelOf(s, s, s), TripSel.single);
    expect(tripSelOf(s, s, null), TripSel.single);
  });

  testWidgets('start, middle and end days look identical (fill, colour, weight)', (tester) async {
    // 23.–27. 10. 2026 = pá–út: wraps from row 4 to row 5.
    await pumpV2(tester, _cal(start: DateTime(2026, 10, 23), end: DateTime(2026, 10, 27)), reducedMotion: true);
    await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    for (final d in [23, 24, 25, 26, 27]) {
      final text = tester.widget<Text>(find.text('$d').first);
      expect(text.style!.color, MgColors.onNeon, reason: 'day $d colour');
      expect(text.style!.fontWeight, FontWeight.w900, reason: 'day $d weight');
    }
    final free = tester.widget<Text>(find.text('20').first);
    expect(free.style!.fontWeight, FontWeight.w800);
    expect(free.style!.color, MgColors.ink);
    expect(tester.takeException(), isNull);
  });

  for (final lang in kV2Langs) {
    for (final size in kV2Sizes) {
      testWidgets('all day states $lang ${size.width.toInt()}', (tester) async {
        final key = GlobalKey();
        await pumpV2(tester, _cal(start: DateTime(2026, 10, 23), end: DateTime(2026, 10, 27)),
            lang: lang, size: size, boundaryKey: key);
        await expectCleanFrames(tester);
        await maybeShot(tester, key, 'core__calendar__range__${lang}__${size.width.toInt()}x${size.height.toInt()}');
      });
    }
  }

  testWidgets('start chosen / end pending + dark skin + single day render', (tester) async {
    await pumpV2(tester, Column(children: [
      Expanded(child: _cal(start: DateTime(2026, 10, 20), pending: true)),
      Expanded(child: Container(color: MgColors.panel, child: _cal(start: DateTime(2026, 10, 22), end: DateTime(2026, 10, 22), skin: TripSkin.dark))),
    ]));
    await expectCleanFrames(tester);
  });

  testWidgets('tap reports the date; semantics name the day', (tester) async {
    final taps = <DateTime>[];
    final h = tester.ensureSemantics();
    await pumpV2(tester, _cal(onTap: taps.add), reducedMotion: true);
    await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    await tester.tap(find.text('21').first);
    expect(taps.single.day, 21);
    expect(find.bySemanticsLabel(RegExp(r'^středa 21\. 10\. 2026, 3 514 Kč')), findsOneWidget);
    h.dispose();
  });

  group('AvailabilityCalendar V-seam', () {
    testWidgets('v2: same selection flow (start → end) through the old State', (tester) async {
      DateTime? s, e;
      final start = DateTime.now().add(const Duration(days: 40));
      await pumpV2(tester, SingleChildScrollView(
        child: AvailabilityCalendar(
          selectedStart: start,
          onRangeSelected: (a, b) {
            s = a;
            e = b;
          },
        ),
      ), reducedMotion: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(find.byType(TripCalendar), findsOneWidget);
      final d1 = DateTime(start.year, start.month, start.day < 20 ? 20 : 10);
      final d2 = DateTime(start.year, start.month, d1.day + 3);
      await tester.tap(find.text('${d1.day}').first);
      await tester.pump();
      await tester.tap(find.text('${d2.day}').first);
      await tester.pump();
      expect(s?.day, d1.day);
      expect(e?.day, d2.day);
    });

    testWidgets('v2: occupied range still shows the old snackbar', (tester) async {
      final base = DateTime.now().add(const Duration(days: 40));
      final m = DateTime(base.year, base.month, 1);
      await pumpV2(tester, SingleChildScrollView(
        child: AvailabilityCalendar(
          selectedStart: m,
          bookedDates: [BookedDateRange(start: DateTime(m.year, m.month, 12), end: DateTime(m.year, m.month, 13), status: 'confirmed')],
          onRangeSelected: (_, __) {},
        ),
      ), reducedMotion: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      await tester.tap(find.text('10').first);
      await tester.pump();
      await tester.tap(find.text('15').first);
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('flag OFF: the old calendar', (tester) async {
      await pumpV2(tester, const SingleChildScrollView(child: AvailabilityCalendar()), v2: false);
      await tester.pump();
      expect(find.byType(TripCalendar), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
    });
  });
}
