// Záznamník po opravách z ověření 2026-10-29 (fix:logic:r1): posun hodin
// telefonu, Pokračovat po pojistce, upozornění „u startu", dávka po
// částech, doposlání po studeném startu v ruční pauze, pauza při viselém
// spojení.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:motogo_app/features/routes/ride_server_seam.dart';
import 'package:motogo_app/features/routes/ride_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Server, jehož hodiny jdou jinak než telefon; odpověď startu může čekat.
class SkewServer extends FakeServer {
  Completer<void>? gate;
  bool hang = false;
  final List<int> batchSizes = [];

  @override
  Future<RideTripStart> startTrip(String? bookingId) async {
    final t0 = rideRecorderClock();
    final g = gate;
    if (g != null) await g.future;
    final r = await super.startTrip(bookingId);
    if (!r.ok) return r;
    return RideTripStart(r.kind,
        id: r.id,
        resumed: r.resumed,
        bookingId: r.bookingId,
        distanceKm: r.distanceKm,
        clockOffset: rideClockOffset(now(), t0, rideRecorderClock()),
        serverNow: now());
  }

  @override
  Future<RideAppendOutcome> append(String id, List<List<double>> points, {double? maxSpeedKmh}) {
    batchSizes.add(points.length);
    if (hang) return Completer<RideAppendOutcome>().future; // viselé spojení
    return super.append(id, points, maxSpeedKmh: maxSpeedKmh);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGeo geo;
  late SkewServer server;
  late Sim sim;
  final containers = <ProviderContainer>[];

  ProviderContainer boot() {
    final c = ProviderContainer(overrides: [rideServerSeamProvider.overrideWithValue(server)]);
    containers.add(c);
    return c;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    geo = FakeGeo();
    GeolocatorPlatform.instance = geo;
    server = SkewServer();
    sim = Sim(geo)..install(server);
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
    rideLogTestSink = null;
    rideRecorderClock = DateTime.now;
  });

  /// Fix s časem telefonu ([gps] = false) nebo se skutečným časem GPS.
  Future<void> fixAt(double kmh, {required bool gps, Duration skew = Duration.zero}) async {
    geo.ctrl.add(Position(
      latitude: sim.lat, longitude: 16.6, timestamp: gps ? sim.now.subtract(skew) : sim.now,
      accuracy: 8, altitude: 300, altitudeAccuracy: 5, heading: 0, headingAccuracy: 1,
      speed: kmh / 3.6, speedAccuracy: 0.5, hasAccuracy: true, hasAltitude: true,
      hasAltitudeAccuracy: true, hasSpeed: true, hasSpeedAccuracy: true,
    ));
    await sim.settle();
  }

  for (final gps in [false, true]) {
    test('telefon o 7 h napřed (čas fixu = ${gps ? 'GPS' : 'telefon'}), fix ještě před odpovědí serveru → jízda uložená v čase serveru', () async {
      const skew = Duration(hours: 7);
      server.now = () => sim.epoch - skew.inSeconds; // server = skutečný čas
      server.gate = Completer<void>();
      final c = boot();
      final n = c.read(rideRecorderProvider.notifier);
      await sim.settle();
      final start = n.startManualResult();
      await sim.settle();
      await fixAt(0, gps: gps, skew: skew); // P0 dorazí dřív než odpověď
      server.gate!.complete();
      expect(await start, RideStartResult.ok);
      await sim.settle();
      sim.now = sim.now.add(const Duration(minutes: 2));
      for (var i = 0; i < 150; i++) {
        sim.now = sim.now.add(const Duration(seconds: 5));
        sim.lat += 60 / 3.6 * 5 / 111194.93;
        await fixAt(60, gps: gps, skew: skew);
      }
      expect(await n.stop(), isTrue, reason: 'jízda se nesmí zahodit jako krátká');
      final pts = server.rides.single.pts;
      expect(pts.length, greaterThan(140));
      final real = sim.epoch - skew.inSeconds;
      expect(pts.first[2], closeTo(real - 14.5 * 60, 5), reason: 'P0 v čase serveru');
      expect(pts.last[2], closeTo(real, 10));
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i][2], greaterThanOrEqualTo(pts[i - 1][2]));
      }
    });
  }

  test('pojistka 48 h → Pokračovat → 10 min stání: GPS zůstane, rozjezd se nahraje', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.fix(0);
    await sim.ride(60, const Duration(minutes: 30));
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(minutes: 8), n);
    expect(c.read(rideRecorderProvider).phase, RidePhase.autoPaused);
    await sim.wait(const Duration(hours: 20), n, every: const Duration(minutes: 30));
    expect(geo.listening, isTrue, reason: 'noc (20 h) GPS nevypíná');
    await sim.wait(const Duration(hours: 29), n, every: const Duration(minutes: 30));
    expect(c.read(rideRecorderProvider).needsDecision, isTrue);
    expect(geo.listening, isFalse);
    expect(await n.resume(), RideStartResult.ok);
    await sim.wait(const Duration(minutes: 10), n);
    expect(geo.listening, isTrue, reason: 'pojistka hned znovu vypnula GPS');
    expect(c.read(rideRecorderProvider).isArmed, isTrue);
    final before = server.rides.single.pts.length;
    await sim.ride(60, const Duration(minutes: 10));
    await n.flush();
    final pts = server.rides.single.pts;
    expect(pts.length - before, greaterThan(100));
    expect(pts.where((p) => p[3] < 0).length, 1); // první bod po pojistce = značka pauzy
    expect(sim.count('long_pause'), 1);
  });

  test('vlastní okruh zpět ke startu: upozornění „u startu" (GPS běží), ráno se nahrává samo', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    final home = sim.lat;
    await sim.fix(0);
    await sim.ride(60, const Duration(minutes: 20));
    sim.lat = home + 0.001;
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(hours: 4), n, every: const Duration(minutes: 10));
    expect(sim.native.where((m) => m.method == 'notifyIdle').length, 1);
    expect(geo.listening, isTrue);
    expect(c.read(rideRecorderProvider).phase, RidePhase.autoPaused);
    await sim.wait(const Duration(hours: 12), n, every: const Duration(hours: 1));
    expect(sim.native.where((m) => m.method == 'notifyIdle').length, 1);
    await sim.ride(60, const Duration(minutes: 5));
    expect(c.read(rideRecorderProvider).phase, RidePhase.riding);
    expect(sim.native.where((m) => m.method == 'cancelIdle'), isNotEmpty);
  });

  test('studený start v ruční pauze: 10 000 neodeslaných bodů → doposlat hned, po částech ≤ 2000', () async {
    final pts = [
      for (var i = 0; i < 10000; i++) [49.2 + i * 0.0002, 16.6, 1791900000.0 + i * 5, 50.0],
    ];
    SharedPreferences.setMockInitialValues({
      kRideRecIdKey: 'ride1',
      kRideRecManualKey: true,
      kRideRecBufKey: jsonEncode(pts),
    });
    await const RideSessionMeta(
      ride: 'ride1', manual: true, proto: 'trip', phase: RidePhase.manualPaused,
      reason: RidePauseReason.manual, since: 1791950000,
    ).save();
    server.rides.add(FakeRide('ride1', null));
    final c = boot();
    c.read(rideRecorderProvider.notifier);
    for (var i = 0; i < 20; i++) {
      await sim.settle();
    }
    expect(c.read(rideRecorderProvider).isManualPaused, isTrue);
    expect(geo.listening, isFalse);
    expect(server.rides.single.pts.length, 10000);
    expect(server.batchSizes.every((b) => b <= 2000), isTrue);
    expect(server.batchSizes.length, 5);
    final p = await SharedPreferences.getInstance();
    expect(jsonDecode(p.getString(kRideRecBufKey)!), isEmpty);
  });

  test('ruční pauza při viselém spojení: GPS se vypne hned, ne až po odpovědi serveru', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    server.hang = true;
    await sim.fix(0);
    await sim.ride(60, const Duration(minutes: 5));
    await n.pause().timeout(const Duration(seconds: 2));
    expect(geo.listening, isFalse);
    expect(c.read(rideRecorderProvider).isManualPaused, isTrue);
  });

  test('časovač RPC dávky / ukončení je 30 s', () {
    expect(kRideRpcTimeout, const Duration(seconds: 30));
  });
}
