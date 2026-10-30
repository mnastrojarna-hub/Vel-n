// Zapomenutý Stop po vícedenní vlastní cestě (ověření kola 3, H1 / X19):
// další jízda se NIKDY tiše nepřidá ke staré cestě a GPS nesvítí dny —
// po ≥ 20 h stání se appka při otevření zeptá „Pokračovat v cestě /
// Ukončit a uložit". Noc na cestě (≤ 20 h) se neptá, výpůjčka nikdy.
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

  /// Jízda [kmh] po dobu [d]; [dir] −1 = na jih (zpátky domů).
  Future<void> go(double kmh, Duration d, {double dir = 1}) async {
    for (var i = 0; i < d.inSeconds ~/ 5; i++) {
      sim.now = sim.now.add(const Duration(seconds: 5));
      sim.lat += dir * kmh / 3.6 * 5 / 111194.93;
      await sim.fix(kmh);
    }
  }

  Future<void> park(RideRecorderNotifier n) async {
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(minutes: 8), n);
  }

  Future<void> waitUntil(DateTime t, RideRecorderNotifier n) =>
      sim.wait(t.difference(sim.now), n, every: const Duration(minutes: 30));

  int notifyIdle() => sim.native.where((m) => m.method == 'notifyIdle').length;

  test('H1 2denní cesta končí doma, Stop zapomenut, appka otevřená každý večer → otázka, dojíždění se nepřidá', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    final home = sim.lat;
    await sim.fix(0); // P0 doma
    sim.now = sim.now.add(const Duration(minutes: 2));
    await go(60, const Duration(hours: 3)); // den 1 tam
    await park(n);
    expect(c.read(rideRecorderProvider).phase, RidePhase.autoPaused);
    final d0 = DateTime.utc(sim.now.year, sim.now.month, sim.now.day);
    await waitUntil(d0.add(const Duration(hours: 19)), n);
    n.onAppResumed(); // večer v hotelu: 10 h → neptá se
    await sim.settle();
    expect(c.read(rideRecorderProvider).needsDecision, isFalse);
    expect(geo.listening, isTrue);
    await waitUntil(d0.add(const Duration(days: 1, hours: 7)), n);
    sim.lat += 0.0002;
    await go(60, const Duration(hours: 3), dir: -1); // den 2 zpátky domů
    sim.lat = home + 0.0005;
    await park(n);
    final tripKm = server.rides.single.km;
    expect(tripKm, greaterThan(300));
    // 3 h doma → jen připomínka „jsi u startu" (vícedenní cesta taky)
    await sim.wait(const Duration(hours: 4), n, every: const Duration(minutes: 30));
    expect(notifyIdle(), 1);
    expect(geo.listening, isTrue);
    n.onAppResumed(); // večer téhož dne (9 h) → ještě ne
    await sim.settle();
    expect(c.read(rideRecorderProvider).needsDecision, isFalse);
    await waitUntil(d0.add(const Duration(days: 2, hours: 19)), n);
    n.onAppResumed(); // další večer (33 h) → zeptat se, GPS vypnout
    await sim.settle();
    final st = c.read(rideRecorderProvider);
    expect(st.needsDecision, isTrue);
    expect(st.pauseReason, RidePauseReason.long);
    expect(geo.listening, isFalse);
    expect(st.notice, 'rpTripIdleAsk');
    expect(st.noticeArgs?['date'], isNotEmpty);
    expect(sim.count('long_pause', 'open'), 1);
    expect(notifyIdle(), 1, reason: 'jezdec appku vidí → hláška, ne notifikace');
    for (var d = 3; d <= 5; d++) {
      await waitUntil(d0.add(Duration(days: d, hours: 19)), n);
      n.onAppResumed();
      await sim.settle();
      expect(c.read(rideRecorderProvider).needsDecision, isTrue);
    }
    // 6. den ráno dojíždění 20 km — GPS je vypnuté, ke staré cestě nic
    await waitUntil(d0.add(const Duration(days: 6, hours: 6, minutes: 30)), n);
    await go(60, const Duration(minutes: 20));
    await n.flush();
    expect(server.rides.length, 1);
    expect(server.rides.single.km, closeTo(tripKm, 0.5));
    // jezdec klepne „Ukončit a uložit"
    expect(await n.stop(), isTrue);
    expect(server.rides.single.open, isFalse);
  });

  test('X19 appka zabitá v noci, otevřená po 4 dnech (cron cestu uložil) → otázka, ne tiché nahrávání; Pokračovat → stejná cesta', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(70, const Duration(hours: 2));
    await park(n);
    await sim.wait(const Duration(hours: 1), n);
    await n.flush();
    await sim.settle();
    final km = server.rides.single.km;
    c.dispose();
    containers.remove(c);
    sim.now = sim.now.add(const Duration(days: 4));
    server.cronClose(server.rides.single); // úklid po 72 h
    final listens = geo.listens;
    final c2 = boot();
    final n2 = c2.read(rideRecorderProvider.notifier);
    await sim.settle();
    final st = c2.read(rideRecorderProvider);
    expect(st.recording, isTrue);
    expect(st.needsDecision, isTrue);
    expect(st.notice, 'rpTripIdleAsk');
    expect(geo.listens, listens, reason: 'GPS se po restartu nesmí tiše zapnout');
    expect(sim.count('long_pause', 'open'), 1);
    // jezdec klepne „Pokračovat v cestě" a jede dál
    expect(await n2.resume(), RideStartResult.ok);
    await sim.settle();
    expect(geo.listening, isTrue);
    await sim.ride(70, const Duration(hours: 1));
    await n2.flush();
    await sim.settle();
    expect(server.rides.length, 1, reason: 'cesta se znovu otevřela, nerozdělila');
    expect(server.rides.single.km, closeTo(km + 70, 3));
    expect(await n2.stop(), isTrue);
  });

  test('výpůjčka: 30 h stání a otevření appky → žádná otázka, GPS čeká na rozjezd', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await n.ensureRecording('B1');
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await park(n);
    await sim.wait(const Duration(hours: 30), n, every: const Duration(minutes: 30));
    n.onAppResumed();
    await sim.settle();
    final st = c.read(rideRecorderProvider);
    expect(st.needsDecision, isFalse);
    expect(st.phase, RidePhase.autoPaused);
    expect(geo.listening, isTrue);
    expect(sim.count('long_pause'), 0);
  });
}
