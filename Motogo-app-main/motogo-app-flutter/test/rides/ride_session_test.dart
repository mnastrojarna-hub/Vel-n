// Relace rozjeté cesty (`mg_ride_session`) a schopnosti serveru (`mg_ride_caps`).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_flags.dart';
import 'package:motogo_app/features/routes/ride_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('JSON relace tam a zpět', () async {
    const m = RideSessionMeta(
      ride: 'r1',
      booking: 'b1',
      manual: true,
      proto: 'trip',
      phase: RidePhase.autoPaused,
      reason: RidePauseReason.walk,
      since: 1792000000.5,
      anchor: [49.2, 16.6, 1792000000.5, 0],
      last: [49.21, 16.6, 1792000100, 30],
      start: [49.1, 16.6, 1791990000, 0, 300],
      off: -7200,
      liveKm: 12.3,
      liveMov: 1234,
      liveStages: 2,
      liveAt: 1792000200,
      noticeKey: 'rpTripContinuedNew',
      noticeArgs: {'date': '6. 10. 2026'},
    );
    await m.save();
    final r = (await RideSessionMeta.load())!;
    expect(r.toJson(), m.toJson());
    expect(r.phase, RidePhase.autoPaused);
    expect(r.reason, RidePauseReason.walk);
    expect(r.start!.length, 5);
    await RideSessionMeta.clear();
    expect(await RideSessionMeta.load(), isNull);
  });

  test('neznámý / starší / poškozený formát → null bez pádu', () async {
    expect(RideSessionMeta.fromJson({'v': 2, 'ride': 'x'}), isNull);
    expect(RideSessionMeta.fromJson({'ride': 'x'}), isNull);
    expect(RideSessionMeta.fromJson('nesmysl'), isNull);
    final odd = RideSessionMeta.fromJson({'v': 1, 'ride': 'x', 'phase': 'warp', 'anchor': [1, 'a', 3]})!;
    expect(odd.phase, RidePhase.riding);
    expect(odd.anchor, isNull);
    SharedPreferences.setMockInitialValues({kRideSessionKey: '{nesmysl'});
    expect(await RideSessionMeta.load(), isNull);
  });

  test('caps: zastarání po 30 min, flag tam a zpět', () async {
    final c = RideServerCaps(trips: false, at: 1000, ap: const RideAutoPauseFlag(enabled: false, stopMin: 7).toJson());
    expect(c.stale(1000 + 1799), isFalse);
    expect(c.stale(1000 + 1801), isTrue);
    await c.save();
    final r = await RideServerCaps.load();
    expect(r.trips, isFalse);
    final f = RideAutoPauseFlag.fromJson(r.ap);
    expect(f.enabled, isFalse);
    expect(f.toConfig().stopPauseS, 420);
  });

  test('flag z řádku feature_flags: chybějící řádek = zapnuto', () {
    expect(RideAutoPauseFlag.fromRow(null).enabled, isTrue);
    final f = RideAutoPauseFlag.fromRow({
      'enabled': true,
      'conditions': {'stop_min': 6, 'walk_min': 4, 'resume_kmh': 25, 'home_h': 2, 'long_h': 12},
    });
    final c = f.toConfig();
    expect([c.stopPauseS, c.walkPauseS, c.resumeKmh, c.homeAfterS, c.longPauseOwnS],
        [360, 240, 25, 7200, 43200]);
    expect(RideAutoPauseFlag.fromRow({'enabled': false}).enabled, isFalse);
  });
}
