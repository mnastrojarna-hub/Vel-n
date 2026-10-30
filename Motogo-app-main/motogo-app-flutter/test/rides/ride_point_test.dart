// Fix → RideFix / bod stopy: 0,1 s, platnost Doppleru a výšky, posun hodin
// (SPEC §2.2, §5.5). Starší chování převodu hlídá test/ride_location_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_motion.dart';

Position _pos(DateTime t,
        {double speed = 15,
        double speedAcc = 1,
        bool hasSpeed = true,
        bool hasSpeedAcc = true,
        double alt = 500,
        double altAcc = 3,
        double acc = 8}) =>
    Position(
      latitude: 49.5,
      longitude: 15.3,
      timestamp: t,
      accuracy: acc,
      altitude: alt,
      altitudeAccuracy: altAcc,
      heading: 0,
      headingAccuracy: 1,
      speed: speed,
      speedAccuracy: speedAcc,
      hasAccuracy: true,
      hasAltitude: true,
      hasAltitudeAccuracy: true,
      hasSpeed: hasSpeed,
      hasSpeedAccuracy: hasSpeedAcc,
    );

void main() {
  final now = DateTime.utc(2026, 10, 22, 7, 0, 0);

  test('čas na 0,1 s', () {
    final f = rideFixFromPosition(_pos(now.subtract(const Duration(milliseconds: 1260))), now: now)!;
    expect(f.ts, (now.millisecondsSinceEpoch - 1300) / 1000);
  });

  test('Doppler: nepřesný (> 2,5 m/s) nebo neměřený = neznámý (bod má 0)', () {
    expect(rideFixFromPosition(_pos(now, speedAcc: 3), now: now)!.kmh, isNull);
    expect(rideFixFromPosition(_pos(now, speed: 0, hasSpeed: false), now: now)!.kmh, isNull);
    expect(rideFixFromPosition(_pos(now, speed: -1), now: now)!.kmh, isNull); // iOS neplatná
    expect(rideFixFromPosition(_pos(now, speed: 0), now: now)!.kmh, 0);
    expect(rideFixFromPosition(_pos(now), now: now)!.kmh, closeTo(54, 1e-9));
    final p = ridePointFromRideFix(rideFixFromPosition(_pos(now, speedAcc: 3), now: now)!, null)!;
    expect(p[3], 0);
  });

  test('výška s přesností > 20 m se nebere', () {
    final f = rideFixFromPosition(_pos(now, altAcc: 25), now: now)!;
    expect(f.alt, isNull);
    expect(ridePointFromRideFix(f, null)!.length, 4);
    expect(rideFixFromPosition(_pos(now), now: now)!.alt, 500);
  });

  test('přesnost v km → fix pryč', () {
    expect(rideFixFromPosition(_pos(now, acc: 900), now: now), isNull);
  });

  test('hodiny telefonu −2 h: fix s časem telefonu se posune, GPS čas zůstane', () {
    final local = now.subtract(const Duration(hours: 2)); // telefon jde pozadu
    const off = 7200.0;
    final phoneTime = rideFixFromPosition(_pos(local.subtract(const Duration(seconds: 5))), now: local, clockOffset: off)!;
    expect(phoneTime.ts, (now.millisecondsSinceEpoch - 5000) / 1000);
    final gpsTime = rideFixFromPosition(_pos(now.subtract(const Duration(seconds: 5))), now: local, clockOffset: off)!;
    expect(gpsTime.ts, (now.millisecondsSinceEpoch - 5000) / 1000);
  });

  test('hodiny telefonu +7 h: skutečný GPS čas se už NEzahodí jako „stará cache"', () {
    final local = now.add(const Duration(hours: 7)); // telefon jde napřed
    final gps = _pos(now.subtract(const Duration(seconds: 3)));
    expect(rideFixFromPosition(gps, now: local), isNull); // bez opravy = dřívější chyba
    final f = rideFixFromPosition(gps, now: local, clockOffset: -25200)!;
    expect(f.ts, (now.millisecondsSinceEpoch - 3000) / 1000);
  });
}
