@Timeout(Duration(minutes: 3))
library;

// Oprava logiky kolo 4 (2026-10-30): připomínka místo vypnutí GPS po 20 h
// (V7), výměna výpůjčky za jízdy (SOS / navazující, V3–V5), Ukončit offline
// přežije zabití appky (VC4-A), restart bez polohy cestu neukončí (VC4-B),
// výpůjčka vrácená během auto-pauzy vypne GPS (VC4-C).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_seam.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class OffGeo extends FakeGeo {
  bool service = true;
  @override
  Future<bool> isLocationServiceEnabled() async => service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OffGeo geo;
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
    geo = OffGeo();
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

  Future<void> settleLong() async {
    for (var i = 0; i < 8; i++) {
      await sim.settle();
    }
  }

  /// Stejné rozhodnutí jako `RideRecorderWatcher` (post-frame).
  Future<void> watch(ProviderContainer c, String? b, {DateTime? pickup}) async {
    final n = c.read(rideRecorderProvider.notifier);
    final st = c.read(rideRecorderProvider);
    n.setActiveBooking(b, pickedUpAt: pickup);
    if (b != null) {
      if (n.stopPending) {
        if (n.canRetryStop) await n.stop();
      } else if (st.recording && st.manual && st.bookingId != b && st.isPaused) {
        await n.finishOwnForRental(b);
      } else if (!st.manual && st.bookingId != null && st.bookingId != b && (st.recording || st.rideId != null)) {
        await n.switchRental(b);
      } else {
        await n.ensureRecording(b);
      }
    } else if (st.manual && n.stopPending && n.canRetryStop) {
      await n.stop();
    } else if (!st.manual && (st.recording || st.rideId != null || n.stopPending) && n.canRetryStop) {
      await n.stop();
    }
    await settleLong();
  }

  Future<void> park(RideRecorderNotifier n) async {
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(minutes: 8), n);
  }

  DateTime at(double s) => DateTime.fromMillisecondsSinceEpoch((s * 1000).round(), isUtc: true);

  test('V7a vlastní 2denní cesta, appka otevřená po 20,25 h u snídaně, bez klepnutí → den 2 se nahraje', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(75, const Duration(hours: 5));
    await park(n);
    await n.flush();
    final day1 = server.rides.single.km;
    await sim.wait(const Duration(hours: 20, minutes: 15), n, every: const Duration(minutes: 30));
    n.onAppResumed(); // u snídaně plánuje trasu
    await sim.settle();
    await sim.wait(const Duration(minutes: 3), n);
    final st = c.read(rideRecorderProvider);
    expect(st.needsDecision, isFalse);
    expect(st.notice, 'rpTripIdleRemind');
    expect(geo.listening, isTrue, reason: 'GPS běží — rozjezd se nahraje sám');
    expect(sim.native.where((m) => m.method == 'notifyIdle'), isNotEmpty);
    await sim.ride(75, const Duration(hours: 2)); // vyrazí bez klepnutí
    await n.flush();
    expect(server.rides, hasLength(1));
    expect(server.rides.single.km, closeTo(day1 + 150, 4));
    expect(sim.native.where((m) => m.method == 'cancelIdle'), isNotEmpty, reason: 'připomínka po rozjezdu zmizí');
  });

  test('pojistka 48 h na pozadí: GPS vypnuto + hláška rpTripIdleAsk (i bez otevření appky)', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 40));
    await park(n);
    await sim.wait(const Duration(hours: 49), n, every: const Duration(minutes: 30));
    final st = c.read(rideRecorderProvider);
    expect(st.needsDecision, isTrue);
    expect(st.notice, 'rpTripIdleAsk');
    expect(geo.listening, isFalse);
  });

  test('VC4-A Ukončit offline, appka zabitá, restart → jízda se NErozjede, uloží se po návratu signálu', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await n.flush();
    server.offline = true;
    await sim.ride(60, const Duration(minutes: 10));
    expect(await n.stop(), isNull);
    expect(n.stopPending, isTrue);
    c.dispose();
    containers.remove(c);
    final c2 = boot();
    final n2 = c2.read(rideRecorderProvider.notifier);
    await settleLong();
    expect(c2.read(rideRecorderProvider).recording, isFalse, reason: 'jezdec dal Ukončit');
    expect(geo.listening, isFalse);
    expect(n2.stopPending, isTrue);
    expect(sim.count('stop_pending_restored'), 1);
    sim.now = sim.now.add(const Duration(hours: 1));
    server.offline = false;
    await watch(c2, null);
    expect(n2.stopPending, isFalse);
    expect(server.rides.single.open, isFalse);
    expect(server.rides.single.km, closeTo(40, 2), reason: 'i body z doby offline');
    final p = await SharedPreferences.getInstance();
    expect(p.getString(kRideStopReqKey), isNull);
    expect(p.getString(kRideRecIdKey), isNull);
  });

  test('VC4-A2 start i Ukončit bez dat, zabití → po restartu jízdu založí a uloží', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    server.offline = true;
    n.setActiveBooking(null);
    expect(await n.startManualResult(), RideStartResult.failed, reason: 'ruční start offline se nezaloží');
    // výpůjčka převzatá bez dat
    await n.ensureRecording('B');
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(70, const Duration(minutes: 30));
    expect(await n.stop(), isNull);
    c.dispose();
    containers.remove(c);
    final c2 = boot();
    final n2 = c2.read(rideRecorderProvider.notifier);
    await settleLong();
    expect(n2.stopPending, isTrue);
    expect(c2.read(rideRecorderProvider).recording, isFalse);
    server.offline = false;
    await watch(c2, null);
    expect(n2.stopPending, isFalse);
    expect(server.rides, hasLength(1));
    expect(server.rides.single.km, closeTo(35, 2));
    expect(server.rides.single.open, isFalse);
  });

  test('VC4-B auto-pauza, restart s vypnutou polohou → cesta běží dál (bez GPS), po zapnutí pokračuje stejná', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    expect(await n.startManualResult(), RideStartResult.ok);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await park(n);
    await n.flush();
    c.dispose();
    containers.remove(c);
    geo.service = false;
    sim.now = sim.now.add(const Duration(hours: 9));
    final c2 = boot();
    final n2 = c2.read(rideRecorderProvider.notifier);
    await settleLong();
    var st = c2.read(rideRecorderProvider);
    expect(n2.stopPending, isFalse, reason: 'hlídač by cestu ukončil a rozdělil');
    expect(st.recording, isTrue);
    expect(st.gpsLost, isTrue);
    await watch(c2, null);
    expect(server.rides.single.open, isTrue);
    geo.service = true;
    n2.onAppResumed();
    await settleLong();
    expect(geo.listening, isTrue);
    await sim.ride(60, const Duration(minutes: 30));
    await n2.flush();
    st = c2.read(rideRecorderProvider);
    expect(st.gpsLost, isFalse);
    expect(server.rides, hasLength(1));
    expect(server.rides.single.km, closeTo(60, 3));
  });

  test('VC4-C výpůjčka vrácená v auto-pauze, appka na pozadí → do ~1 h ukončeno, GPS vypnuto', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await n.ensureRecording('B');
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await park(n);
    await n.flush();
    server.inactive.add('B');
    server.returns['B'] = sim.epoch;
    await sim.wait(const Duration(hours: 1, minutes: 5), n);
    expect(geo.listening, isFalse);
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(sim.count('rental_ended'), 1);
    expect(server.rides.single.open, isFalse);
  });

  test('VC4-C2 noc v boxu samoobsluhy (výpůjčka běží) → kontrola nic neukončí', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await n.ensureRecording('B');
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await park(n);
    await sim.wait(const Duration(hours: 10), n);
    expect(server.rentalChecks, greaterThan(10));
    expect(geo.listening, isTrue);
    expect(c.read(rideRecorderProvider).isArmed || c.read(rideRecorderProvider).isPaused, isTrue);
    expect(sim.count('rental_ended'), 0);
  });

  test('V5 navazující výpůjčka: A stojí na pobočce, B převzatá a jede → A uložena, B ve vlastní jízdě', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await watch(c, 'A', pickup: sim.now.subtract(const Duration(minutes: 5)));
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(70, const Duration(hours: 1, minutes: 30));
    await park(n);
    await n.flush();
    final kmA = server.rides.single.km;
    sim.now = sim.now.add(const Duration(minutes: 10));
    final pickupB = sim.now;
    server.pickups['B'] = sim.epoch;
    await watch(c, 'B', pickup: pickupB); // A v databázi ještě nevrácená
    expect(sim.count('rental_switch'), 1);
    expect(server.rides, hasLength(2));
    expect(server.rides.first.booking, 'A');
    expect(server.rides.first.open, isFalse);
    expect(server.rides.first.km, closeTo(kmA, 0.1));
    expect(c.read(rideRecorderProvider).bookingId, 'B');
    await sim.fix(0);
    await sim.ride(70, const Duration(minutes: 40));
    await n.flush();
    expect(server.rides.last.booking, 'B');
    expect(server.rides.last.km, closeTo(46.7, 2));
    await watch(c, 'B', pickup: pickupB);
    expect(sim.count('rental_switch'), 1, reason: 'jen jednou');
  });

  test('dvě souběžné výpůjčky jednoho účtu (převzaté před jízdou) → nepřepíná se', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    final pk = sim.now.subtract(const Duration(minutes: 30));
    await watch(c, 'X', pickup: pk);
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(70, const Duration(minutes: 20));
    await watch(c, 'Y', pickup: pk); // seznam teď ukazuje druhou motorku
    await sim.ride(70, const Duration(minutes: 20));
    await n.flush();
    expect(sim.count('rental_switch'), 0);
    expect(server.rides, hasLength(1));
    expect(server.rides.single.booking, 'X');
    expect(server.rides.single.km, closeTo(46.7, 2));
  });

  test('V4 SOS výměna bez signálu: body náhradní motorky nejdou do porouchané, náhradní jízda je má', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await watch(c, 'A', pickup: sim.now.subtract(const Duration(minutes: 5)));
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(80, const Duration(hours: 1));
    await n.flush();
    server.offline = true;
    await sim.ride(80, const Duration(hours: 1)); // A bez signálu
    await park(n); // porucha
    // obsluha: A dokončena (SOS), B převzatá; server A uzavře úklidem
    server.inactive.add('A');
    server.ended.add('A');
    server.rides.single.open = false;
    await sim.wait(const Duration(minutes: 40), n);
    server.pickups['B'] = sim.epoch;
    final pickupB = sim.now;
    await sim.wait(const Duration(minutes: 30), n); // dodávka s náhradní motorkou
    await sim.ride(8, const Duration(seconds: 20), dt: 5);
    await sim.ride(80, const Duration(hours: 2)); // B bez signálu (appka stále „A")
    await park(n);
    server.offline = false; // hotelová Wi-Fi; seznam rezervací ještě starý
    n.onAppResumed();
    await settleLong();
    await n.flush();
    await settleLong();
    expect(c.read(rideRecorderProvider).recording, isFalse, reason: 'A skončila');
    await watch(c, 'B', pickup: pickupB); // seznam se načetl
    await settleLong();
    await n.flush();
    await settleLong();
    final rb = server.rides.where((r) => r.booking == 'B').toList();
    expect(rb, hasLength(1));
    expect(sim.count('rental_carry'), 1);
    expect(rb.single.pts.every((p) => p[2] >= server.pickups['B']! - 600), isTrue, reason: 'žádné body porouchané motorky');
    expect(rb.single.km, greaterThan(0.95 * 160));
    expect(rb.single.km, lessThan(170));
  });

  test('výměna, když Ukončit staré jízdy selže (offline) → body nové motorky počkají, pak jdou do nové', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await watch(c, 'A', pickup: sim.now.subtract(const Duration(minutes: 5)));
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(80, const Duration(minutes: 30));
    await n.flush();
    server.offline = true;
    final pickupB = sim.now.add(const Duration(minutes: 1));
    server.pickups['B'] = pickupB.millisecondsSinceEpoch / 1000;
    sim.now = sim.now.add(const Duration(minutes: 15));
    await sim.ride(80, const Duration(minutes: 30)); // už na B, appka ještě „A"
    await watch(c, 'B', pickup: pickupB); // seznam z cache, Ukončit offline
    expect(n.stopPending, isTrue);
    server.offline = false;
    sim.now = sim.now.add(const Duration(minutes: 3));
    await watch(c, 'B', pickup: pickupB); // uloží A
    await watch(c, 'B', pickup: pickupB); // rozjede B s převzatými body
    await n.flush();
    await settleLong();
    final ra = server.rides.firstWhere((r) => r.booking == 'A');
    final rb = server.rides.firstWhere((r) => r.booking == 'B');
    expect(ra.open, isFalse);
    expect(ra.km, closeTo(40, 2));
    expect(rb.km, closeTo(40, 2));
    final cut = pickupB.millisecondsSinceEpoch / 1000 - 600;
    expect(rb.startedAt, greaterThanOrEqualTo(cut));
    expect(rb.pts.every((p) => p[2] >= cut), isTrue, reason: 'žádné body staré motorky');
    expect(at(rb.startedAt!).isBefore(sim.now), isTrue, reason: 'jízda B začíná body z doby offline');
  });
}
