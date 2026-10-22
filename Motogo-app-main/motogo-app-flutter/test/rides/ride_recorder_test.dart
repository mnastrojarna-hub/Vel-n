// Záznamník jízd s falešným serverem a GPS (SPEC §16.2 „Recorder
// integration"): 7denní cesta = 1 jízda, konec výpůjčky, starý server,
// offline start, ruční pauza přes restart, pauza vs. hlídač, smazání.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/core/i18n/translations.dart';
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

  Future<RideRecorderNotifier> started(ProviderContainer c, {String? booking}) async {
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    if (booking == null) {
      expect(await n.startManualResult(), RideStartResult.ok);
    } else {
      await n.ensureRecording(booking);
    }
    await sim.settle();
    return n;
  }

  test('7denní vlastní cesta = 1 jízda, 6 nočních pauz, žádné navázání', () async {
    final c = boot();
    final n = await started(c);
    for (var day = 0; day < 7; day++) {
      if (day > 0) {
        sim.now = DateTime.utc(2026, 10, 5 + day, 6, 0);
      }
      await sim.fix(0); // u motorky (1. den = P0)
      sim.now = sim.now.add(const Duration(minutes: 2));
      await sim.ride(60, const Duration(minutes: 30));
      if (day == 6) break;
      await sim.ride(8, const Duration(seconds: 10), dt: 10);
      await sim.wait(const Duration(minutes: 8), n);
      expect(c.read(rideRecorderProvider).phase, RidePhase.autoPaused, reason: 'den $day');
      await sim.wait(const Duration(hours: 12), n, every: const Duration(hours: 1));
    }
    expect(c.read(rideRecorderProvider).liveKm, closeTo(210, 210 * 0.03));
    expect(await n.stop(), isTrue);
    expect(server.rides.length, 1);
    final pts = server.rides.single.pts;
    expect(pts.where((p) => p[3] < 0).length, 7); // 1. rozjezd + 6 rán
    expect(sim.count('pause', 'stop'), 6);
    expect(sim.count('resume', 'auto'), 7);
    expect(sim.count('trip_continue'), 0);
    expect(server.rides.single.km, closeTo(210, 210 * 0.03));
  });

  test('výpůjčka: server uzavře po vrácení → booking_inactive → konec, žádná nová jízda', () async {
    final c = boot();
    await started(c, booking: 'B');
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(50, const Duration(minutes: 3));
    final r = server.rides.single;
    r
      ..open = false
      ..bookingEnded = true;
    server.inactive.add('B');
    await sim.ride(50, const Duration(minutes: 3));
    await sim.settle();
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(server.rides.length, 1);
    expect(sim.count('ride_continue_no_booking'), 1);
  });

  test('starý server: start_user_trip chybí → start_user_ride; uzavřená vlastní → nová jízda + hláška', () async {
    server.trips = false;
    final c = boot();
    await started(c);
    expect(server.legacyCalls, 1);
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(50, const Duration(minutes: 3));
    server.rides.single.open = false; // úklid 3 h / 36 h
    await sim.ride(50, const Duration(minutes: 3));
    await sim.settle();
    final st = c.read(rideRecorderProvider);
    expect(st.recording, isTrue);
    expect(server.rides.length, 2);
    expect(st.rideId, server.rides.last.id);
    expect(st.notice, 'rpTripContinuedNewOld');
    expect(server.tripCalls, 1); // caps: starý server se neptá znovu
  });

  test('offline start NENÍ starý server (žádný fallback)', () async {
    server.offline = true;
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.failed);
    expect(server.legacyCalls, 0);
    expect(c.read(rideRecorderProvider).recording, isFalse);
  });

  test('ruční pauza: GPS vypnuté, přežije restart bez připojení; Pokračovat → značka', () async {
    final c = boot();
    final n = await started(c);
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(50, const Duration(minutes: 5));
    await n.pause();
    await sim.settle();
    expect(c.read(rideRecorderProvider).isManualPaused, isTrue);
    expect(geo.listening, isFalse);
    final listens = geo.listens;
    c.dispose();
    containers.remove(c);
    // Restart appky.
    final c2 = boot();
    final n2 = c2.read(rideRecorderProvider.notifier);
    await sim.settle();
    final st = c2.read(rideRecorderProvider);
    expect(st.recording, isTrue);
    expect(st.isManualPaused, isTrue);
    expect(geo.listens, listens); // nic se nepřipojilo
    sim.now = sim.now.add(const Duration(hours: 1));
    expect(await n2.resume(), RideStartResult.ok);
    await sim.settle();
    expect(geo.listening, isTrue);
    expect(c2.read(rideRecorderProvider).isArmed, isTrue);
    await sim.ride(50, const Duration(minutes: 2));
    await n2.flush();
    await sim.settle();
    expect(server.rides.single.pts.where((p) => p[3] < 0).length, 2);
    expect(server.rides.length, 1);
  });

  test('hlídač: ensureRecording během pauzy nic nedělá', () async {
    final c = boot();
    final n = await started(c, booking: 'B');
    await n.pause();
    await sim.settle();
    final calls = server.tripCalls;
    await n.ensureRecording('B');
    await sim.settle();
    expect(server.tripCalls, calls);
    expect(c.read(rideRecorderProvider).isManualPaused, isTrue);
  });

  test('smazání nahrávané jízdy: discardCurrent, pak „gone" → žádné navázání', () async {
    final c = boot();
    final n = await started(c);
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(50, const Duration(minutes: 3));
    await n.discardCurrent();
    server.rides.single.gone = true;
    final calls = server.tripCalls + server.legacyCalls;
    await sim.ride(50, const Duration(minutes: 1));
    await n.flush();
    await sim.settle();
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(server.tripCalls + server.legacyCalls, calls);
  });

  test('ruční start během výpůjčky, kterou server už ukončil → vlastní jízda', () async {
    server.inactive.add('B');
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    n.setActiveBooking('B');
    expect(await n.startManualResult(), RideStartResult.ok);
    expect(c.read(rideRecorderProvider).bookingId, isNull);
    expect(server.rides.single.booking, isNull);
  });

  test('vlastní cesta stojí a zákazník převezme výpůjčku → vlastní uložit, nahrávat výpůjčku', () async {
    final c = boot();
    final n = await started(c);
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 3));
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(minutes: 8), n);
    expect(c.read(rideRecorderProvider).isPaused, isTrue);
    await n.finishOwnForRental('B');
    await sim.settle();
    final st = c.read(rideRecorderProvider);
    expect(st.recording, isTrue);
    expect(st.manual, isFalse);
    expect(st.bookingId, 'B');
    expect(st.notice, 'rpOwnSavedForRental');
    expect(server.rides.length, 2);
    expect(server.rides.first.open, isFalse);
    expect(server.rides.last.booking, 'B');
  });

  test('aktualizace serveru za jízdy: legacy jízda se převezme jako cesta', () async {
    server.trips = false;
    final c = boot();
    final n = await started(c);
    final id = c.read(rideRecorderProvider).rideId;
    server.trips = true;
    n.onAppResumed();
    await sim.settle();
    expect(sim.logs.any((l) => l.action == 'caps' && l.detail == 'upgrade'), isTrue);
    expect(c.read(rideRecorderProvider).rideId, id);
  });

  test('notifikace podle stavu (Android): připraveno → nahrávám → stojíš', () async {
    final keys = {
      'rpNotifArmedTitle': 'ARMED',
      'rpNotifArmed': 'a',
      'rpNotifRidingTitle': 'RIDING',
      'rpNotifRiding': '{km} km · {time}',
      'rpNotifPausedTitle': 'PAUSED',
      'rpNotifPaused': 'od {time}',
    };
    final cs = translations['cs']!;
    final had = {for (final k in keys.keys) k: cs[k]};
    cs.addAll(keys);
    addTearDown(() {
      for (final e in had.entries) {
        if (e.value == null) {
          cs.remove(e.key);
        } else {
          cs[e.key] = e.value!;
        }
      }
    });
    final c = boot();
    final n = await started(c);
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(50, const Duration(minutes: 1));
    expect(c.read(rideRecorderProvider).isRidingLive, isTrue);
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(minutes: 8), n);
    final titles = [
      for (final m in sim.native)
        if (m.method == 'notify') (m.arguments as Map)['title'],
    ];
    expect(titles, containsAllInOrder(['ARMED', 'RIDING', 'PAUSED']));
    expect(sim.count('phase'), greaterThanOrEqualTo(2));
  });
}
