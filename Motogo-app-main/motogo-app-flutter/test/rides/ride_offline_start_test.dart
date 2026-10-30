// Start a konec bez dat (ověření kola 3): výpůjčka nahraná offline od
// převzetí se nesmí ztratit (`start_user_trip_from` založí jízdu prvním
// bodem relace, i zpětně po vrácení); neuložený Stop (offline) se dořeší
// dřív, než začne nová jízda — jinak by ji server přilepil ke staré.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_seam.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGeo geo;
  late FakeServer server;
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
    server = FakeServer();
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

  /// Výpůjčka převzatá bez dat: P0 + [d] jízdy 80 km/h, server nedostupný.
  Future<(RideRecorderNotifier, ProviderContainer, double)> offlineRental(Duration d) async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    server.offline = true;
    n.setActiveBooking('B');
    await n.ensureRecording('B');
    await sim.settle();
    final t0 = sim.epoch;
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(80, d);
    for (var i = 0; i < 3; i++) {
      n.debugTick();
      await sim.settle();
    }
    expect(server.rides, isEmpty);
    return (n, c, t0);
  }

  Future<void> settleLong() async {
    for (var i = 0; i < 10; i++) {
      await sim.settle();
    }
  }

  for (final from in [true, false]) {
    test('start bez dat, 3 h jízdy, data se vrátí (výpůjčka běží) → nic se neořízne (from=$from)', () async {
      server.fromSupported = from;
      final (n, _, t0) = await offlineRental(const Duration(hours: 3));
      server.offline = false;
      n.onAppResumed();
      await settleLong();
      await n.flush();
      await settleLong();
      expect(server.rides.length, 1);
      expect(server.rides.single.km, closeTo(240, 240 * 0.03), reason: 'body z doby offline patří k jízdě');
      expect(sim.count('buffer_stale_cut'), 0);
      if (from) {
        expect(server.fromCalls.single, closeTo(t0, 5), reason: 'jízda začíná prvním bodem relace');
        expect(server.rides.single.startedAt, closeTo(t0, 5));
      } else {
        expect(sim.count('caps', 'trip_from'), 1); // starý server → start_user_trip
      }
    });
  }

  test('výpůjčka celá bez dat, vrácená dřív, než šlo jízdu založit → zpětně založená, body do vrácení uložené', () async {
    final (n, c, _) = await offlineRental(const Duration(hours: 2));
    server.inactive.add('B');
    server.returns['B'] = sim.epoch;
    server.offline = false;
    sim.now = sim.now.add(const Duration(minutes: 30));
    n.setActiveBooking(null);
    expect(await n.stop(), isTrue);
    await settleLong();
    expect(server.rides.length, 1);
    expect(server.rides.single.booking, 'B');
    expect(server.rides.single.open, isFalse);
    expect(server.rides.single.km, closeTo(160, 160 * 0.03));
    expect(c.read(rideRecorderProvider).rideId, isNull);
    expect(n.stopPending, isFalse);
  });

  test('…server zpětné založení neumí → nic tiše: ride_points_lost s počtem bodů, žádné opakování', () async {
    server.fromSupported = false;
    final (n, _, _) = await offlineRental(const Duration(hours: 2));
    server.inactive.add('B');
    server.offline = false;
    sim.now = sim.now.add(const Duration(minutes: 30));
    n.setActiveBooking(null);
    expect(await n.stop(), isFalse);
    expect(server.rides, isEmpty);
    final lost = sim.logs.where((l) => l.action == 'ride_points_lost').toList();
    expect(lost.length, 1);
    expect(lost.single.data?['n'], greaterThan(1000));
    expect(n.stopPending, isFalse);
  });

  test('…a při vrácení pořád bez dat → Stop čeká (stopPending), po návratu signálu se doručí', () async {
    final (n, _, _) = await offlineRental(const Duration(hours: 2));
    server.inactive.add('B');
    server.returns['B'] = sim.epoch;
    sim.now = sim.now.add(const Duration(minutes: 30));
    n.setActiveBooking(null);
    expect(await n.stop(), isNull);
    expect(n.stopPending, isTrue);
    sim.now = sim.now.add(const Duration(minutes: 3));
    server.offline = false;
    n.onAppResumed();
    await settleLong();
    expect(server.rides.length, 1);
    expect(server.rides.single.km, closeTo(160, 160 * 0.03));
    expect(server.rides.single.open, isFalse);
    expect(n.stopPending, isFalse);
  });

  Future<RideRecorderNotifier> ownRideStoppedOffline(ProviderContainer c) async {
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await n.flush();
    server.offline = true;
    expect(await n.stop(), isNull);
    expect(n.stopPending, isTrue);
    return n;
  }

  test('Stop offline, za 5 h nový ruční start s daty → nejdřív se uloží stará jízda, nová je zvlášť', () async {
    final c = boot();
    final n = await ownRideStoppedOffline(c);
    sim.now = sim.now.add(const Duration(hours: 5));
    server.offline = false;
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await n.flush();
    expect(server.rides.length, 2);
    expect(server.rides.first.open, isFalse);
    expect(server.rides.first.km, closeTo(30, 1.5));
    expect(server.rides.last.km, closeTo(30, 1.5));
  });

  test('Stop offline a nový start pořád offline → „nepodařilo se", stará jízda čeká; návrat signálu ji uloží', () async {
    final c = boot();
    final n = await ownRideStoppedOffline(c);
    sim.now = sim.now.add(const Duration(minutes: 10));
    expect(await n.startManualResult(), RideStartResult.failed);
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(n.stopPending, isTrue);
    expect(server.rides.single.open, isTrue);
    sim.now = sim.now.add(const Duration(minutes: 3));
    server.offline = false;
    n.onAppResumed(); // jen otevření appky — bez dalšího klepnutí
    await settleLong();
    expect(server.rides.single.open, isFalse);
    expect(n.stopPending, isFalse);
  });
}
