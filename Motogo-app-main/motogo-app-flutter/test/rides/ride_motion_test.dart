// Pravidla detektoru (SPEC §6.3) jednotlivě + klasifikace dvojic (§3.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_motion.dart';

RideFix fx(double ts, double northM, {double? kmh, double? acc = 8}) =>
    RideFix(ts: ts, lat: 49.2 + northM / 111194.93, lng: 16.6, acc: acc, kmh: kmh);

void main() {
  const d = RideMotionDetector(RideMotionConfig());

  test('pomalý fix: Doppler ≤ 12, bez Doppleru odvozená rychlost', () {
    expect(d.isSlow(fx(10, 0, kmh: 12), null), isTrue);
    expect(d.isSlow(fx(10, 0, kmh: 13), null), isFalse);
    expect(d.isSlow(fx(10, 10), fx(0, 0)), isTrue); // 3,6 km/h
    expect(d.isSlow(fx(10, 100), fx(0, 0)), isFalse); // 36 km/h
    expect(d.isSlow(fx(10, 10), null), isFalse); // neznámá rychlost ≠ 0
  });

  test('uvolnění: dva rychlé fixy po sobě (≤ 15 s), bez Doppleru dva rychlé úseky', () {
    expect(d.released(fx(10, 0, kmh: 20), fx(5, 0, kmh: 20), null), isTrue);
    expect(d.released(fx(30, 0, kmh: 20), fx(5, 0, kmh: 20), null), isFalse);
    expect(d.released(fx(10, 0, kmh: 20), fx(5, 0, kmh: 8), null), isFalse);
    expect(d.released(fx(10, 100), fx(5, 50), fx(0, 0)), isTrue);
  });

  test('poloměr stání 40–100 m', () {
    expect(d.stillRadius([5, 8, 10]), 40);
    expect(d.stillRadius([40, 45, 50]), closeTo(67.5, 1e-9));
    expect(d.stillRadius([]), 40);
  });

  test('obnova (a) Doppler, (b) bez Doppleru, (c) pomalý rozjezd', () {
    final anchor = [49.2, 16.6, 0.0, 0.0];
    expect(d.resumeTrigger([fx(100, 90, kmh: 25), fx(105, 130, kmh: 25)], anchor), 0);
    expect(d.resumeTrigger([fx(100, 30, kmh: 25), fx(105, 60, kmh: 25)], anchor), isNull); // u kotvy
    expect(d.resumeTrigger([fx(100, 0, acc: 40), fx(140, 350, acc: 15)], anchor), isNull); // nepřesný fix
    expect(d.resumeTrigger([fx(100, 10, acc: 15), fx(140, 360, acc: 15)], anchor), 0);
    final slow = [for (var i = 0; i < 6; i++) fx(100 + i * 10.0, 260 + i * 10.0, kmh: 13)];
    expect(d.resumeTrigger(slow, anchor), 0);
    expect(d.resumeTrigger([fx(100, 600, kmh: 0, acc: 10)], anchor), isNull); // skok GPS
  });

  test('předjezd od souvislého běhu ≥ 8 km/h', () {
    final ring = [fx(0, 0, kmh: 0), fx(5, 10, kmh: 9), fx(10, 30, kmh: 15), fx(15, 70, kmh: 25)];
    expect(d.preRollStart(ring, 2), 1);
    expect(d.preRollStart([fx(0, 0), fx(5, 400)], 0), 0);
  });

  test('bod: filtr přesnosti, vzdálenosti a času', () {
    expect(ridePointFromRideFix(fx(0, 0, acc: 80, kmh: 1), null), isNull);
    expect(ridePointFromRideFix(fx(0, 0, acc: 80, kmh: 40), null), isNotNull);
    final a = ridePointFromRideFix(fx(0, 0, kmh: 30), null)!;
    expect(ridePointFromRideFix(fx(1, 10, kmh: 30), a), isNull);
    expect(ridePointFromRideFix(fx(-1, 50, kmh: 30), a), isNull);
    expect(ridePointFromRideFix(fx(2, 50, kmh: 30), a)!.length, 4);
  });

  test('klasifikace: značka −1 = pauza i přes velký posun (trajekt)', () {
    final p = [49.2, 16.6, 0.0, 30.0];
    final q = [49.5, 16.6, 3600.0, -1.0];
    final c = rideClassifyPair(p, q);
    expect(c.kind, RidePairKind.pause);
    expect(c.km, 0);
    expect(rideIsMovingPair(p, [49.201, 16.6, 8.0, 50.0]), isTrue);
  });
}
