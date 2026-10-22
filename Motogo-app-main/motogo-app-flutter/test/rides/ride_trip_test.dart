// Cesty (SPEC §8): seskupení, součty, výchozí názvy, undo mapy operací;
// model: pauza vs. mezera ve stopě, etapy, dny.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_trip.dart';
import 'package:motogo_app/features/routes/ride_trip_api.dart';

UserRide ride(String id,
    {String? booking,
    String? trip,
    String? tripName,
    required DateTime start,
    DateTime? end,
    double km = 100,
    int moving = 3600,
    int pause = 0,
    double? max,
    String? moto,
    List<List<num>> track = const [],
    List<Map<String, Object?>>? stages,
    bool v2 = true}) {
  final j = <String, dynamic>{
    'id': id,
    'booking_id': booking,
    'moto_name': moto,
    'trip_id': trip,
    'trip_name': tripName,
    'started_at': start.toUtc().toIso8601String(),
    'ended_at': (end ?? start.add(const Duration(hours: 3))).toUtc().toIso8601String(),
    'distance_km': km,
    'duration_min': 180,
    'moving_sec': moving,
    'idle_sec': 600,
    'gap_sec': 0,
    'pause_sec': pause,
    'max_speed_kmh': max,
    'track': track,
    if (stages != null) 'stages': stages,
  };
  if (v2) j['pause_aware'] = true;
  return UserRide.fromJson(j)!;
}

void main() {
  final d0 = DateTime(2026, 10, 6, 9);
  const tr = AppTranslations('cs');

  test('klíč: explicitní cesta > výpůjčka > jízda', () {
    expect(rideTripKey(ride('a', booking: 'b', trip: 't', start: d0)), 't:t');
    expect(rideTripKey(ride('a', booking: 'b', start: d0)), 'b:b');
    expect(rideTripKey(ride('a', start: d0)), 'r:a');
    expect(rideTripKey(ride('a', booking: 'b', trip: 'a', start: d0)), 't:a'); // samostatná
  });

  test('seskupení: výpůjčka rozdělená nocí = jedna cesta, nejnovější první', () {
    final items = groupRides([
      ride('r1', booking: 'B', start: d0),
      ride('own', start: d0.add(const Duration(days: 3))),
      ride('r2', booking: 'B', start: d0.add(const Duration(days: 1))),
    ]);
    expect(items.length, 2);
    expect((items.first as RideListItemRide).ride.id, 'own');
    final t = (items.last as RideListItemTrip).trip;
    expect(t.rides.map((r) => r.id), ['r1', 'r2']);
    expect(t.isRental, isTrue);
    expect(t.explicitTripId, isNull);
  });

  test('součty cesty vč. pauzy mezi jízdami', () {
    final a = ride('a', trip: 'T', start: d0, end: d0.add(const Duration(hours: 8)),
        km: 300, moving: 18000, pause: 1800, max: 120, moto: 'BMW');
    final b = ride('b', trip: 'T', start: d0.add(const Duration(hours: 22)),
        end: d0.add(const Duration(hours: 30)), km: 250, moving: 15000, pause: 600, max: 140);
    final t = RideTrip('t:T', [b, a]);
    final g = t.aggregate;
    expect(g.id, 'a');
    expect(g.distanceKm, 550);
    expect(g.movingSec, 33000);
    expect(g.pauseSec, 1800 + 600 + 14 * 3600);
    expect(g.maxSpeedKmh, 140);
    expect(g.avgSpeedKmh, closeTo(550 / (33000 / 3600), 1e-9));
    expect(t.days, 2);
    expect(g.motoName, 'BMW');
  });

  test('výchozí názvy a rozsah dat', () {
    final rent = RideTrip('b:B', [
      ride('a', booking: 'B', moto: 'Tiger', start: d0),
      ride('b', booking: 'B', start: d0.add(const Duration(days: 1))),
    ]);
    final named = RideTrip('t:T', [ride('a', trip: 'T', tripName: 'Alpy', start: d0), ride('b', trip: 'T', start: d0)]);
    expect(rideTripDefaultName(named, tr), 'Alpy');
    expect(rideTripDefaultName(rent, tr), isNot(contains('{moto}')));
    expect(rideDateRange(d0, d0), '6. 10. 2026');
    expect(rideDateRange(d0, DateTime(2026, 10, 11)), '6.–11. 10. 2026');
    expect(rideDateRange(DateTime(2026, 9, 28), DateTime(2026, 10, 3)), '28. 9. – 3. 10. 2026');
    expect(rideDateRange(DateTime(2025, 12, 28), DateTime(2026, 1, 3)), '28. 12. 2025 – 3. 1. 2026');
  });

  group('undo mapy vrací přesně předchozí stav', () {
    final r1 = ride('r1', booking: 'B', start: d0);
    final r2 = ride('r2', booking: 'B', start: d0.add(const Duration(days: 1)));
    final own = ride('own', trip: 'X', tripName: 'Stará', start: d0.add(const Duration(days: 5)));
    final own2 = ride('own2', trip: 'X', tripName: 'Stará', start: d0.add(const Duration(days: 6)));
    final rent = RideTrip('b:B', [r1, r2]);
    final ex = RideTrip('t:X', [own, own2]);

    void undoRestores(RideTripPlan p, List<UserRide> before) {
      final u = rideTripUndoPlan(p.undo).items;
      for (final r in before) {
        final i = u.firstWhere((x) => x.id == r.id);
        expect((i.tripId, i.tripName), (r.tripId, r.tripName), reason: r.id);
      }
    }

    test('sloučit implicitní výpůjčku s explicitní cestou → klíč explicitní cesty', () {
      final p = rideTripMergePlan([RideListItemTrip(rent), RideListItemTrip(ex)], '  Alpy ');
      expect(p.items.map((i) => i.tripId).toSet(), {'X'});
      expect(p.items.map((i) => i.tripName).toSet(), {'Alpy'});
      undoRestores(p, [r1, r2, own, own2]);
    });

    test('sloučit samostatné jízdy → klíč = nejstarší jízda, prázdný název = null', () {
      final a = ride('a', start: d0.add(const Duration(days: 2)));
      final b = ride('b', start: d0);
      final p = rideTripMergePlan([RideListItemRide(a), RideListItemRide(b)], '');
      expect(p.items.map((i) => i.tripId).toSet(), {'b'});
      expect(p.items.every((i) => i.tripName == null), isTrue);
      undoRestores(p, [a, b]);
    });

    test('rozdělit / přejmenovat / přidat / vyjmout', () {
      final s = rideTripSplitPlan(rent);
      expect(s.items.map((i) => (i.id, i.tripId)), [('r1', 'r1'), ('r2', 'r2')]);
      undoRestores(s, [r1, r2]);
      final rn = rideTripRenamePlan(rent, 'Víkend');
      expect(rn.items.map((i) => i.tripId).toSet(), {'r1'});
      undoRestores(rn, [r1, r2]);
      final extra = ride('z', start: d0.add(const Duration(days: 9)));
      final ad = rideTripAddPlan(rent, extra);
      expect(ad.items.length, 3); // implicitní skupina → klíč dostanou všichni
      undoRestores(ad, [r1, r2, extra]);
      final ad2 = rideTripAddPlan(ex, extra);
      expect(ad2.items.single.tripId, 'X');
      expect(ad2.items.single.tripName, 'Stará');
      final rm = rideTripRemovePlan(own);
      expect((rm.items.single.tripId, rm.items.single.tripName), ('own', null));
      undoRestores(rm, [own]);
    });
  });

  test('slučování jen s novým serverem a aspoň dvěma položkami', () {
    final old = [ride('a', start: d0, v2: false), ride('b', start: d0, v2: false)];
    expect(rideTripsAvailable(old), isFalse);
    expect(rideTripsAvailable([ride('a', start: d0), ride('b', start: d0)]), isTrue);
    expect(rideTripsAvailable([ride('a', start: d0)]), isFalse);
  });

  test('stopa: značka −1 = pauza, ticho s posunem rychle = mezera, noc s posunem pomalu = pauza', () {
    const t0 = 1792000000;
    final r = ride('a', start: d0, track: [
      [49.2, 16.6, t0, 50],
      [49.201, 16.6, t0 + 8, 50],
      [49.202, 16.6, t0 + 3600, -1], // značka
      [49.203, 16.6, t0 + 3608, 50],
      [49.25, 16.6, t0 + 3608 + 240, 60], // 5,2 km za 4 min = mezera
      [49.251, 16.6, t0 + 3856, 60],
      [49.26, 16.6, t0 + 3856 + 36000, 30], // 1 km za 10 h = pauza (noc)
    ]);
    final kinds = [for (final s in r.segments) s.gapBefore?.kind];
    expect(kinds, [null, RideGapKind.pause, RideGapKind.gap, RideGapKind.pause]);
    expect(r.pauseCount, 2);
    expect(r.hasGaps, isTrue);
  });

  test('etapy a dny', () {
    double ts(DateTime t) => t.millisecondsSinceEpoch / 1000;
    final r = ride('a', start: d0, stages: [
      {'f': ts(d0), 't': ts(d0.add(const Duration(hours: 9))), 'km': 300, 'mv': 18000, 'ps': 1800},
      {'f': ts(d0.add(const Duration(hours: 24))), 't': ts(d0.add(const Duration(hours: 30))), 'km': 200, 'mv': 12000},
      {'f': 'vadné'},
    ]);
    expect(r.stages.length, 2);
    expect(r.days, 2);
    expect(r.stages.first.idleSec, 9 * 3600 - 18000 - 1800);
    expect(r.stages.first.avgKmh, closeTo(60, 1e-9));
    expect(ride('b', start: d0).days, 1);
    expect(ride('c', start: d0, end: d0.add(const Duration(days: 2)), v2: false).days, 3);
  });
}
