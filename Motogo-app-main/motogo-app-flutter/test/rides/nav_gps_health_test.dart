// Navigace: „Slabý GPS signál“ jen v pohybu — stojící jezdec (semafor,
// tankování) fixy nedostává (distanceFilter 4 m) a varování nesmí vidět.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/nav_gps_health.dart';

void main() {
  test('25 s without a fix while standing is not weak GPS', () {
    expect(navGpsWeak(sinceFix: const Duration(seconds: 25), lastSpeedKmh: 0), isFalse);
    expect(navGpsWeak(sinceFix: const Duration(minutes: 5), lastSpeedKmh: 3), isFalse);
  });
  test('25 s without a fix at 40 km/h is weak GPS', () {
    expect(navGpsWeak(sinceFix: const Duration(seconds: 25), lastSpeedKmh: 40), isTrue);
  });
  test('10 s without a fix at 40 km/h is not weak yet', () {
    expect(navGpsWeak(sinceFix: const Duration(seconds: 10), lastSpeedKmh: 40), isFalse);
    expect(navGpsWeak(sinceFix: const Duration(seconds: 20), lastSpeedKmh: 40), isFalse);
  });
  test('no fix yet is not weak GPS', () {
    expect(navGpsWeak(sinceFix: null, lastSpeedKmh: 40), isFalse);
    expect(navGpsWeak(sinceFix: null, lastSpeedKmh: 0), isFalse);
  });
}
