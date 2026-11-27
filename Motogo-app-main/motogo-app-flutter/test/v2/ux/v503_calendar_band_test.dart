// 5.0.3 (owner 2026-11-27, "obecně v jakémkoliv kalendáři": the days
// between the first and the last one must glow exactly as strongly as the
// ends, matching the legend "Tvůj termín"): every v2 range calendar is the
// shared `TripCalendar` — this guards its PAINT: start, every middle day and
// end have the same fill and the same number colour, on both skins, also
// where the band wraps a week row and during reduced motion. (The app
// needed no change here; the old look is out of scope.)
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';

import '../support/v2_harness.dart';

final _month = DateTime(2026, 12);
// Thu 3. – Tue 8. 12. 2026: wraps from the first week row to the second.
final _start = DateTime(2026, 12, 3), _end = DateTime(2026, 12, 8);

Widget _cal(TripSkin skin) => ColoredBox(
      color: skin == TripSkin.dark ? MgColors.night : MgColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TripCalendar(
          month: _month,
          dayStateOf: (d) => TripDayState(
            date: d,
            kind: d.weekday >= 6 ? TripDayKind.freeWeekend : TripDayKind.free,
            selected: tripSelOf(d, _start, _end),
            price: '3 514',
          ),
          onTapDay: (_) {},
          onPrevMonth: () {},
          onNextMonth: () {},
          skin: skin,
          legend: TripLegend(items: TripLegendKind.values, skin: skin),
        ),
      ),
    );

Future<(ByteData, int)> _pixels(WidgetTester t, GlobalKey key) async {
  late ByteData data;
  late int width;
  await t.runAsync(() async {
    final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image img = await ro.toImage(pixelRatio: 1);
    width = img.width;
    data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    img.dispose();
  });
  return (data, width);
}

Color _at((ByteData, int) px, Offset o) {
  final i = (o.dy.round() * px.$2 + o.dx.round()) * 4;
  return Color.fromARGB(px.$1.getUint8(i + 3), px.$1.getUint8(i), px.$1.getUint8(i + 1), px.$1.getUint8(i + 2));
}

void main() {
  setUpAll(loadMontserrat);

  for (final skin in TripSkin.values) {
    testWidgets('${skin.name} skin: start, middle and end days are painted with the SAME band fill', (t) async {
      final key = GlobalKey();
      await pumpV2(t, _cal(skin), reducedMotion: true, boundaryKey: key, dpr: 1);
      await t.pump(const Duration(milliseconds: 400));
      final px = await _pixels(t, key);
      final fills = <int, Color>{};
      for (var d = _start.day; d <= _end.day; d++) {
        final cell = find.ancestor(of: find.text('$d'), matching: find.byType(TripDayCell)).first;
        final r = t.getRect(cell);
        // Inside the band, clear of the number, the price, the caps and the
        // contour: a little under the cell's top edge, at its centre.
        fills[d] = _at(px, Offset(r.center.dx, r.top + 6));
        // The same a little above the bottom edge.
        expect(_at(px, Offset(r.center.dx, r.bottom - 6)), fills[d], reason: 'day $d bottom');
        final text = t.widget<Text>(find.text('$d').first);
        expect(text.style!.color, MgColors.onNeon, reason: 'day $d number colour');
        expect(text.style!.fontWeight, FontWeight.w900, reason: 'day $d number weight');
      }
      for (final e in fills.entries) {
        expect(e.value, MgColors.calBand, reason: 'day ${e.key} fill (start ${_start.day}, end ${_end.day})');
      }
      // A free day next to the band is NOT the band.
      final free = t.getRect(find.ancestor(of: find.text('9'), matching: find.byType(TripDayCell)).first);
      expect(_at(px, Offset(free.center.dx, free.top + 6)), isNot(MgColors.calBand));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('with motion: once the band has grown, the middle days are as strong as the ends', (t) async {
    final key = GlobalKey();
    await pumpV2(t, _cal(TripSkin.light), boundaryKey: key, dpr: 1);
    await t.pump(const Duration(seconds: 2));
    final px = await _pixels(t, key);
    for (var d = _start.day; d <= _end.day; d++) {
      final r = t.getRect(find.ancestor(of: find.text('$d'), matching: find.byType(TripDayCell)).first);
      expect(_at(px, Offset(r.center.dx, r.top + 6)), MgColors.calBand, reason: 'day $d');
    }
  });
}
