// Převod GPS fixu na bod stopy záznamu jízdy (ride_location.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_location.dart';

Position _fix(double lat, double lng, DateTime t,
        {double acc = 8, double speedMs = 15, double alt = 500}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: t,
      accuracy: acc,
      altitude: alt,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 1,
      speed: speedMs,
      speedAccuracy: 1,
    );

void main() {
  final now = DateTime.utc(2026, 10, 4, 7, 31, 30);
  double sec(DateTime t) => (t.millisecondsSinceEpoch / 1000).roundToDouble();

  test('čas bodu = čas fixu, ne čas příjmu', () {
    final t = now.subtract(const Duration(minutes: 44));
    final p = ridePointFromFix(_fix(49.5454, 15.3442, t), null, now: now)!;
    expect(p[2], sec(t));
    expect(p[3], 54.0); // 15 m/s
    expect(p.length, 5); // s výškou
  });

  test('nastřádané fixy po probuzení appky mají každý svůj čas', () {
    // Systém doručil najednou fixy z 8:47, 9:10 a 9:30 → dřív všechny
    // dostaly tutéž sekundu příjmu a server počítal km „za 0 s".
    final times = [44, 21, 1].map((m) => now.subtract(Duration(minutes: m))).toList();
    List<double>? last;
    final out = <List<double>>[];
    for (var i = 0; i < times.length; i++) {
      final p = ridePointFromFix(_fix(49.5454 - i * 0.008, 15.3442, times[i]), last, now: now);
      expect(p, isNotNull);
      out.add(p!);
      last = p;
    }
    expect(out.map((p) => p[2]).toList(), times.map(sec).toList());
  });

  test('rozbité hodiny fixu (budoucnost / roky zpět) → čas příjmu', () {
    final future = ridePointFromFix(
        _fix(49.5, 15.3, now.add(const Duration(hours: 3))), null, now: now)!;
    expect(future[2], sec(now));
    final rollover = ridePointFromFix(
        _fix(49.5, 15.3, now.subtract(const Duration(days: 7168))), null, now: now)!;
    expect(rollover[2], sec(now));
  });

  test('hodiny stará poloha z cache se do stopy nebere', () {
    expect(
        ridePointFromFix(_fix(49.5, 15.3, now.subtract(const Duration(hours: 7))), null,
            now: now),
        isNull);
  });

  test('fix starší než poslední bod (znovupřipojení streamu) se zahodí', () {
    final last = ridePointFromFix(_fix(49.5297, 15.3230, now), null, now: now)!;
    final stale = _fix(49.5454, 15.3442, now.subtract(const Duration(seconds: 30)));
    expect(ridePointFromFix(stale, last, now: now), isNull);
  });

  test('posun pod 20 m se nebere (stream sdílený s navigací)', () {
    final last = ridePointFromFix(_fix(49.5, 15.3, now), null, now: now)!;
    final t2 = now.add(const Duration(seconds: 1));
    expect(ridePointFromFix(_fix(49.50005, 15.3, t2), last, now: t2), isNull); // ~6 m
    expect(ridePointFromFix(_fix(49.5003, 15.3, t2), last, now: t2), isNotNull); // ~33 m
  });

  test('nepřesný fix: pryč při stání, za jízdy zůstává; km přesnost vždy pryč', () {
    expect(ridePointFromFix(_fix(49.5, 15.3, now, acc: 80, speedMs: 0), null, now: now),
        isNull);
    expect(ridePointFromFix(_fix(49.5, 15.3, now, acc: 80, speedMs: 20), null, now: now),
        isNotNull);
    expect(ridePointFromFix(_fix(49.5, 15.3, now, acc: 900, speedMs: 20), null, now: now),
        isNull);
  });

  test('vzdálenost = haversine jako na serveru', () {
    // Start → cíl jízdy ze 4. 10. 2026: 2,32 km vzdušnou čarou.
    expect(rideDistanceM(49.5454, 15.3442, 49.5297, 15.3230), closeTo(2321, 5));
  });
}
