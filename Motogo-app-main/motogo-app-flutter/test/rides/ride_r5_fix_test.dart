@Timeout(Duration(minutes: 3))
library;

// Oprava logiky kolo 5 (2026-10-30): dvě motorky na jednom účtu nerozdělí
// jezdcovu cestu (W0 / R1), výpůjčka zaparkovaná v kóji kiosku vypne GPS
// po 16 h (R2), pojistka „dlouhá pauza" 48 h i pro výpůjčku (baterie)
// a otevření appky ji zase zapne samo.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_recorder_watcher.dart';
import 'package:motogo_app/features/routes/ride_server_seam.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

final _now = DateTime.now();
final _y = _now.subtract(const Duration(days: 1));
final _t = _now.add(const Duration(days: 1));

/// Rezervace motorky relativně k dnešku (hlídač počítá se skutečným datem).
Reservation res(String id, DateTime start, DateTime end, DateTime? pickup,
    {String kind = 'moto', String status = 'active', String? repl, bool sos = false, DateTime? ret}) {
  String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  return Reservation.fromJson({
    'id': id,
    'moto_id': kind == 'gear' ? null : 'm1',
    'status': status,
    'payment_status': 'paid',
    'start_date': d(start),
    'end_date': d(end),
    if (pickup != null) 'picked_up_at': pickup.toUtc().toIso8601String(),
    'created_at': start.subtract(const Duration(days: 3)).toIso8601String(),
    'booking_kind': kind,
    if (repl != null) 'replacement_for_booking_id': repl,
    'ended_by_sos': sos,
    if (ret != null) 'returned_at': ret.toUtc().toIso8601String(),
  });
}

class OffGeo extends FakeGeo {
  bool service = true;
  @override
  Future<bool> isLocationServiceEnabled() async => service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('W0 hlídač: nahrávaná výpůjčka má přednost, dokud běží', () {
    final a = res('A', _y, _t, _y); // jezdec, od včerejška do zítřka
    final b = res('B', _now, _t, _now.subtract(const Duration(hours: 1))); // kamarád dnes
    final g = res('G', _now, _t, _now.subtract(const Duration(minutes: 5)), kind: 'gear');

    test('R1 dvě motorky: zůstává A (bez přednosti by vyhrála B — pořadí seznamu)', () {
      expect(rideActiveBookingId([g, b, a], prefer: 'A'), 'A');
      expect(rideActiveBookingId([g, b, a]), 'B');
    });

    test('V5 navazující: A dnes končí (vrácení ještě nezapsané) → B', () {
      final a5 = res('A', _y, _now, _y);
      expect(rideActiveBookingId([b, a5], prefer: 'A'), 'B');
    });

    test('SOS výměna: B nahrazuje A (A v DB ještě aktivní) → B; zrušená náhrada nic', () {
      final bs = res('B', _now, _t, _now.subtract(const Duration(minutes: 5)), repl: 'A');
      expect(rideActiveBookingId([bs, a], prefer: 'A'), 'B');
      final bc = res('B', _now, _t, _now, repl: 'A', status: 'cancelled');
      expect(rideActiveBookingId([bc, a], prefer: 'A'), 'A');
    });

    test('A ukončená SOS / vrácená / dokončená → nahrává se další', () {
      final bs = res('B', _now, _t, _now, repl: 'A');
      expect(rideActiveBookingId([bs, res('A', _y, _t, _y, status: 'completed', sos: true)], prefer: 'A'), 'B');
      expect(rideActiveBookingId([b, res('A', _y, _t, _y, ret: _now)], prefer: 'A'), 'B');
      expect(rideActiveBookingId([b, res('A', _y, _t, _y, status: 'completed')], prefer: 'A'), 'B');
    });

    test('přednost nikdy pro výbavu, neznámé id ani nevydanou rezervaci', () {
      expect(rideActiveBookingId([b, a], prefer: 'G'), 'B');
      expect(rideActiveBookingId([b, a], prefer: 'X'), 'B');
      final r = res('R', _y, _t, null, status: 'reserved'); // nevydaná (bez převzetí)
      expect(rideActiveBookingId([b, r], prefer: 'R'), 'B');
    });
  });

  late OffGeo geo;
  late FakeServer server;
  late Sim sim;
  final containers = <ProviderContainer>[];

  ProviderContainer boot() {
    final c = ProviderContainer(overrides: [rideServerSeamProvider.overrideWithValue(server)]);
    containers.add(c);
    return c;
  }

  void setUpWorld({bool trips = true}) {
    SharedPreferences.setMockInitialValues({});
    geo = OffGeo();
    GeolocatorPlatform.instance = geo;
    server = FakeServer(trips: trips);
    sim = Sim(geo)..install(server);
  }

  setUp(setUpWorld);

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

  /// Výpůjčka [b]: P0, 30 min jízdy, zastavení → auto-pauza.
  Future<RideRecorderNotifier> rentalParked(ProviderContainer c, String b) async {
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    await n.ensureRecording(b);
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(60, const Duration(minutes: 30));
    await sim.ride(8, const Duration(seconds: 10), dt: 10);
    await sim.wait(const Duration(minutes: 8), n);
    await n.flush();
    return n;
  }

  test('R1 kamarád převezme druhou motorku na stejném účtu → jezdcova jízda pokračuje, nic se nepřepne', () async {
    final c = boot();
    final n = c.read(rideRecorderProvider.notifier);
    await sim.settle();
    final a = res('A', _y, _t, _y);
    final b = res('B', _now, _t, _now.subtract(const Duration(hours: 1)));
    String? pick(List<Reservation> l) {
      final st = c.read(rideRecorderProvider);
      return rideActiveBookingId(l, prefer: st.manual ? null : st.bookingId);
    }

    n.setActiveBooking(pick([a]), pickedUpAt: sim.now.subtract(const Duration(hours: 20)));
    await n.ensureRecording(pick([a]));
    await sim.settle();
    await sim.fix(0);
    sim.now = sim.now.add(const Duration(minutes: 2));
    await sim.ride(70, const Duration(minutes: 40));
    final id = pick([b, a]);
    expect(id, 'A');
    n.setActiveBooking(id, pickedUpAt: sim.now.subtract(const Duration(hours: 20)));
    await n.ensureRecording(id);
    await sim.ride(70, const Duration(minutes: 40));
    await n.flush();
    expect(sim.count('rental_switch'), 0);
    expect(server.rides, hasLength(1));
    expect(server.rides.single.booking, 'A');
    expect(server.rides.single.km, closeTo(93.3, 3));
  });

  test('R2 kóje kiosku před posledním dnem (výpůjčka běží, jízdu uzavřel server) → GPS čeká 16 h, pak vypnuto', () async {
    final c = boot();
    final n = await rentalParked(c, 'B');
    final bay = sim.epoch;
    server.cronClose(server.rides.single, at: bay); // _ride_booking_end = kóje → úklid
    await sim.wait(const Duration(hours: 15, minutes: 30), n);
    expect(geo.listening, isTrue, reason: 'noc v kóji: ranní vyjetí se nahraje samo');
    expect(c.read(rideRecorderProvider).recording, isTrue);
    expect(sim.count('rental_parked'), 1);
    expect(sim.count('rental_parked_end'), 0);
    await sim.wait(const Duration(hours: 1), n);
    expect(geo.listening, isFalse, reason: 'předčasné vrácení: GPS nesvítí dny');
    expect(c.read(rideRecorderProvider).recording, isFalse);
    expect(sim.count('rental_parked_end'), 1);
    final r = server.rides.single;
    expect(r.open, isFalse);
    expect(r.closedBy, 'cron', reason: 'Ukončit uzavřenou jízdu nepřepíše (vyjetí ji znovu otevře)');
    expect(sim.native.where((m) => m.method == 'cancelIdle'), isNotEmpty);
  });

  test('R2 starý server (bez closed_by) → beze změny, GPS dál čeká', () async {
    setUpWorld(trips: false);
    final c = boot();
    final n = await rentalParked(c, 'B');
    server.cronClose(server.rides.single, at: sim.epoch);
    await sim.wait(const Duration(hours: 17), n);
    expect(server.parkChecks, greaterThan(10));
    expect(geo.listening, isTrue);
    expect(sim.count('rental_parked_end'), 0);
  });

  test('výpůjčka 48 h bez jízdy i bez otevření appky → GPS vypnuto; otevření appky ho zapne samo', () async {
    final c = boot();
    final n = await rentalParked(c, 'B');
    await sim.wait(const Duration(hours: 47), n, every: const Duration(minutes: 30));
    expect(geo.listening, isTrue);
    await sim.wait(const Duration(hours: 2), n, every: const Duration(minutes: 30));
    var st = c.read(rideRecorderProvider);
    expect(geo.listening, isFalse);
    expect(st.recording, isTrue);
    expect(st.isManualPaused, isTrue);
    expect(st.pauseReason, RidePauseReason.long);
    expect(st.notice, isNull, reason: 'výpůjčka nemá „Pokračovat / Ukončit"');
    final idle = sim.native.where((m) => m.method == 'notifyIdle').toList();
    expect(idle, isNotEmpty);
    expect('${(idle.last.arguments as Map)['text']}', contains('stačí otevřít appku'));
    n.onAppResumed();
    await settleLong();
    st = c.read(rideRecorderProvider);
    expect(geo.listening, isTrue);
    expect(st.isArmed, isTrue);
    expect(st.notice, 'rpRentGuardWoke');
    expect(sim.count('rental_guard_wake'), 1);
    await sim.ride(60, const Duration(minutes: 30));
    await n.flush();
    expect(server.rides, hasLength(1), reason: 'stejná jízda výpůjčky');
    expect(server.rides.single.km, closeTo(60, 3));
  });

  test('výpůjčka: otevření appky posune pojistku (48 h od posledního otevření)', () async {
    final c = boot();
    final n = await rentalParked(c, 'B');
    await sim.wait(const Duration(hours: 30), n, every: const Duration(minutes: 30));
    n.onAppResumed();
    await settleLong();
    await sim.wait(const Duration(hours: 47), n, every: const Duration(minutes: 30));
    expect(geo.listening, isTrue);
    expect(sim.count('long_pause'), 0);
    await sim.wait(const Duration(hours: 2), n, every: const Duration(minutes: 30));
    expect(geo.listening, isFalse);
    expect(sim.count('long_pause'), 1);
  });

  test('hlídač probudí výpůjčku po pojistce jen v popředí a s povolenou polohou', () async {
    final c = boot();
    final n = await rentalParked(c, 'B');
    await sim.wait(const Duration(hours: 49), n, every: const Duration(minutes: 30));
    expect(c.read(rideRecorderProvider).pauseReason, RidePauseReason.long);
    await n.ensureRecording('B'); // zavřená appka (bez popředí) → nic
    await settleLong();
    expect(geo.listening, isFalse);
    final wb = WidgetsBinding.instance;
    wb.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() => wb.handleAppLifecycleStateChanged(AppLifecycleState.paused));
    geo.service = false; // poloha vypnutá → o polohu se neříká, UI nabídne Pokračovat
    await n.ensureRecording('B');
    await settleLong();
    expect(geo.listening, isFalse);
    expect(c.read(rideRecorderProvider).isManualPaused, isTrue);
    expect(c.read(rideRecorderProvider).needsDecision, isFalse, reason: 'výpůjčka: jen Pokračovat, bez Ukončit');
    geo.service = true;
    await n.ensureRecording('B');
    await settleLong();
    expect(geo.listening, isTrue);
    expect(c.read(rideRecorderProvider).isArmed, isTrue);
    expect(c.read(rideRecorderProvider).notice, 'rpRentGuardWoke');
  });
}
