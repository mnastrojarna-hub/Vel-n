// Výpůjčka, telefon offline v den vrácení (fix:logic:r2): úklid jízdu po
// vrácení uzavře, appka pak doposílá velkou dávku po částech (≤ 2000). Server
// (SQL 03c `_ride_append_late`) pozdní body do uzavřené výpůjčky uloží a
// odpoví `ride_finished` + `booking_ended` → zbytek musí jít do TÉŽE jízdy,
// ne do navázání (to po vrácení skončí `booking_inactive` a dávku zahodí).
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:motogo_app/features/routes/ride_server_seam.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Server podle SQL 03c: body po vrácení (+30 s) se nepřijmou; uzavřená
/// výpůjčka přijme pozdní body (novější než poslední uložený, ≤ vrácení
/// + 30 s) a odpoví `booking_ended`, jen když něco uložila.
class LateServer extends FakeServer {
  double? returnedAt;
  bool loseNext = false; // uloží, ale odpověď se ztratí (časovač)
  int? offlineAfter; // po tolika dávkách vypadne síť
  final List<int> batches = [];

  @override
  Future<RideAppendOutcome> append(String id, List<List<double>> points, {double? maxSpeedKmh}) async {
    batches.add(points.length);
    final left = offlineAfter;
    if (left != null) {
      offlineAfter = left > 0 ? left - 1 : null;
      if (left <= 0) offline = true;
    }
    if (offline) return RideAppendOutcome.retry;
    final r = rides.where((x) => x.id == id).firstOrNull;
    if (r == null || r.gone) return const RideAppendOutcome(RideAppendResult.gone);
    final ret = returnedAt;
    final last = r.pts.isEmpty ? double.negativeInfinity : r.pts.last[2];
    final keep = [
      for (final p in points)
        if (p[2] > last && (ret == null || p[2] <= ret + 30)) List<double>.from(p),
    ];
    r.pts.addAll(keep);
    if (loseNext) {
      loseNext = false;
      return RideAppendOutcome.retry;
    }
    if (!r.open) return RideAppendOutcome(RideAppendResult.closed, bookingEnded: keep.isNotEmpty);
    if (keep.isEmpty && ret != null && points.any((p) => p[2] > ret + 30)) {
      r.open = false; // jen body po vrácení → uzavřít k vrácení
      return const RideAppendOutcome(RideAppendResult.closed, bookingEnded: true);
    }
    return RideAppendOutcome(RideAppendResult.ok, distanceKm: r.km, serverNow: now());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGeo geo;
  late LateServer server;
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
    server = LateServer();
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
    for (var i = 0; i < 30; i++) {
      await sim.settle();
    }
  }

  /// Výpůjčka: 30 min online, pak [offline] jízdy bez signálu (fix à 5 s),
  /// vrácení na pobočce, úklid jízdu uzavře; telefon se připojí o 3 h později.
  Future<(RideRecorderNotifier, ProviderContainer, int)> offlineReturnDay(Duration offline) async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    n.setActiveBooking('B');
    await n.ensureRecording('B');
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(80, const Duration(minutes: 30));
    await n.flush();
    server.offline = true;
    await sim.ride(80, offline);
    final r = server.rides.single;
    server.returnedAt = sim.epoch;
    r.open = false; // úklid (closed_by = cron)
    server.inactive.add('B');
    sim.now = sim.now.add(const Duration(hours: 3));
    return (n, c, offline.inSeconds ~/ 5);
  }

  test('> 2000 offline bodů: všechny části do TÉŽE uzavřené jízdy, nic se neztratí', () async {
    final (n, c, fixes) = await offlineReturnDay(const Duration(hours: 4, minutes: 40));
    expect(fixes, greaterThan(3000));
    final before = server.rides.single.pts.length;
    server.offline = false;
    n.onAppResumed();
    await settleLong();
    final r = server.rides.single;
    expect(server.rides, hasLength(1), reason: 'žádná jízda po vrácení');
    expect(r.pts.length - before, greaterThanOrEqualTo(fixes - 2), reason: 'batches ${server.batches}');
    expect(r.km, closeTo(80 * (5 + 10 / 60), 4)); // 30 min + 4 h 40 min při 80 km/h
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(c.read(rideRecorderProvider).rideId, isNull);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(kRideRecBufKey), isNull);
  });

  test('ztracená odpověď na 1. pozdní část: duplicita → „uzavřeno" bez důvodu → zbytek přesto doručen', () async {
    final (n, c, fixes) = await offlineReturnDay(const Duration(hours: 4, minutes: 40));
    final before = server.rides.single.pts.length;
    server.offline = false;
    server.loseNext = true;
    await n.flush(); // část 1 uložena, odpověď ztracena
    n.onAppResumed(); // znovu: část 1 = duplicity, pak zbytek
    await settleLong();
    final r = server.rides.single;
    expect(server.rides, hasLength(1));
    expect(r.pts.length - before, greaterThanOrEqualTo(fixes - 2), reason: 'batches ${server.batches}');
    expect(c.read(rideRecorderProvider).recording, isFalse);
  });

  test('restart appky offline + start po vrácení (booking_inactive): uložené body do jízdy, ne do koše', () async {
    final t0 = sim.epoch - 6 * 3600;
    final pts = [
      for (var i = 0; i < 2500; i++) [49.2 + i * 0.0011, 16.6, t0 + i * 5, 80.0],
    ];
    SharedPreferences.setMockInitialValues({
      kRideRecIdKey: 'ride1',
      kRideRecBufKey: jsonEncode(pts),
    });
    server.rides.add(FakeRide('ride1', 'B')..open = false);
    server.returnedAt = t0 + 2500 * 5 + 60;
    server.offline = true;
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await settleLong();
    await n.ensureRecording('B'); // hlídač: výpůjčka ještě „běží", síť není
    await sim.settle();
    expect(c.read(rideRecorderProvider).recording, isTrue);
    server.offline = false;
    server.inactive.add('B');
    sim.now = sim.now.add(const Duration(minutes: 2));
    n.debugTick(); // založení jízdy znovu → booking_inactive
    await settleLong();
    expect(server.rides, hasLength(1));
    expect(server.byId('ride1').pts.length, 2500);
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(sim.logs.where((l) => l.action == 'ride_continue_no_booking' && l.data?['late'] == 2500), hasLength(1));
  });

  test('offline během doručování: body zůstanou a doručí se při dalším pokusu', () async {
    final (n, c, fixes) = await offlineReturnDay(const Duration(hours: 4, minutes: 40));
    final before = server.rides.single.pts.length;
    server.offline = false;
    server.loseNext = true;
    await n.flush(); // část 1 uložena, odpověď ztracena
    server.offlineAfter = 2; // duplicita, navázání → doručování, pak síť pryč
    n.onAppResumed();
    await settleLong();
    expect(server.offline, isTrue);
    expect(c.read(rideRecorderProvider).recording, isTrue, reason: 'nic se nezahodilo');
    expect(c.read(rideRecorderProvider).rideId, isNotNull);
    server.offline = false;
    sim.now = sim.now.add(const Duration(minutes: 2));
    n.debugTick();
    await settleLong();
    expect(server.byId(server.rides.single.id).pts.length - before, greaterThanOrEqualTo(fixes - 2));
    expect(c.read(rideRecorderProvider).recording, isFalse);
  });
}
