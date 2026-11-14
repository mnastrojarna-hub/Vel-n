// SOS: bez čerstvého GPS fixu (i po vypršení 20 s limitu) se hlášení pošle
// s poslední známou polohou jako ve 4.1.3; vypnutá poloha zůstává hlášená.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/core/native/gps_service.dart';
import 'package:motogo_app/features/sos/sos_location.dart';

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 11, 12),
      accuracy: 50,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  final last = _pos(49.4, 15.59);

  test('locate never completes + last known position → that position after the limit', () async {
    final never = Completer<({Position? pos, GpsStatus status})>();
    final r = await sosLocate(
        limit: const Duration(milliseconds: 50), locate: () => never.future, lastKnown: () async => last);
    expect(r.pos, same(last));
    expect(r.status, GpsStatus.ok);
  });

  test('locate returns noFix + last known position → the position', () async {
    final r = await sosLocate(locate: () async => (pos: null, status: GpsStatus.noFix), lastKnown: () async => last);
    expect(r.pos, same(last));
    expect(r.status, GpsStatus.ok);
  });

  test('no last known position → no position, noFix', () async {
    final r = await sosLocate(locate: () async => (pos: null, status: GpsStatus.noFix), lastKnown: () async => null);
    expect(r.pos, isNull);
    expect(r.status, GpsStatus.noFix);
    final e = await sosLocate(
        locate: () async => (pos: null, status: GpsStatus.noFix), lastKnown: () async => throw Exception('x'));
    expect([e.pos, e.status], [null, GpsStatus.noFix]);
    final slow = await sosLocate(
        locate: () async => (pos: null, status: GpsStatus.noFix),
        lastKnownLimit: const Duration(milliseconds: 20),
        lastKnown: () => Completer<Position?>().future);
    expect([slow.pos, slow.status], [null, GpsStatus.noFix]);
  });

  test('serviceOff and denied stay as they are (last known is not used)', () async {
    var asked = 0;
    Future<Position?> lk() async {
      asked++;
      return last;
    }

    final off = await sosLocate(locate: () async => (pos: null, status: GpsStatus.serviceOff), lastKnown: lk);
    expect([off.pos, off.status], [null, GpsStatus.serviceOff]);
    final den = await sosLocate(locate: () async => (pos: null, status: GpsStatus.denied), lastKnown: lk);
    expect([den.pos, den.status], [null, GpsStatus.denied]);
    expect(asked, 0);
  });

  test('a fresh fix is returned as is', () async {
    final fresh = _pos(49.2, 16.6);
    final r = await sosLocate(locate: () async => (pos: fresh, status: GpsStatus.ok), lastKnown: () async => last);
    expect(r.pos, same(fresh));
  });
}
