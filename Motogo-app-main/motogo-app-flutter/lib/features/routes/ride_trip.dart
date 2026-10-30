import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/i18n_provider.dart';
import 'ride_model.dart';
import 'ride_provider.dart';

/// Cesty = zobrazovací skupiny jízd (SPEC §8). Server drží jen sloupce
/// `trip_id` / `trip_name`; seskupení, součty a výchozí názvy jsou tady.
///   explicitní cesta: jezdec sloučil jízdy (`trip_id` = klíč cesty)
///   výpůjčka: jízdy se stejnou rezervací (i starší, rozdělené nocí)
/// Jedna vícedenní jízda NENÍ cesta — je to jízda s více etapami.

/// Mezera mezi jízdami cesty se počítá jako pauza (noc mezi dvěma částmi
/// jedné cesty) jen do 36 h. Delší (dva víkendy sloučené do jedné cesty)
/// není pauza — ani čas, ani počet; na mapě je jen přerušení stopy.
const int kRideTripJoinPauseMaxSec = 36 * 3600;

/// Klíč skupiny: explicitní cesta > výpůjčka > samostatná jízda.
String rideTripKey(UserRide r) => r.tripId != null
    ? 't:${r.tripId}'
    : (r.bookingId != null ? 'b:${r.bookingId}' : 'r:${r.id}');

/// Položka seznamu „Mých jízd": jízda, nebo cesta (≥ 2 jízdy).
sealed class RideListItem {
  const RideListItem();
  DateTime get newest;
}

class RideListItemRide extends RideListItem {
  const RideListItemRide(this.ride);
  final UserRide ride;
  @override
  DateTime get newest => ride.startedAt;
}

class RideListItemTrip extends RideListItem {
  const RideListItemTrip(this.trip);
  final RideTrip trip;
  @override
  DateTime get newest => trip.rides.last.startedAt;
}

/// Seskupí jízdy do položek seznamu (nejnovější první).
List<RideListItem> groupRides(List<UserRide> rides) {
  final groups = <String, List<UserRide>>{};
  for (final r in rides) {
    groups.putIfAbsent(rideTripKey(r), () => []).add(r);
  }
  final out = <RideListItem>[
    for (final e in groups.entries)
      e.value.length >= 2 ? RideListItemTrip(RideTrip(e.key, e.value)) : RideListItemRide(e.value.first),
  ];
  out.sort((a, b) => b.newest.compareTo(a.newest));
  return out;
}

/// Smí se nabízet slučování? Jen když server cesty zná a je co slučovat.
bool rideTripsAvailable(List<UserRide> rides, [List<RideListItem>? items]) =>
    rides.any((r) => r.serverV2) && (items ?? groupRides(rides)).length >= 2;

/// Seznam „Mých jízd" seskupený do cest.
final myRideItemsProvider = Provider<AsyncValue<List<RideListItem>>>(
    (ref) => ref.watch(myRidesProvider).whenData(groupRides));

class RideTrip {
  RideTrip(this.key, List<UserRide> members)
      : rides = List.unmodifiable([...members]..sort((a, b) => a.startedAt.compareTo(b.startedAt)));

  final String key;
  /// Jízdy cesty od nejstarší.
  final List<UserRide> rides;

  UserRide get leader => rides.first;
  /// Klíč explicitní cesty (null = implicitní skupina výpůjčky).
  String? get explicitTripId => key.startsWith('t:') ? key.substring(2) : null;
  String? get name {
    for (final r in rides) {
      if (r.tripName != null) return r.tripName;
    }
    return null;
  }

  String? get commonBookingId {
    final b = leader.bookingId;
    return b != null && rides.every((r) => r.bookingId == b) ? b : null;
  }

  bool get isRental => key.startsWith('b:') || commonBookingId != null;
  bool get isRecording => rides.any((r) => r.isRecording);
  bool get isPublic => rides.every((r) => r.isPublic);
  DateTime get from => leader.startedAt;
  DateTime get to {
    final l = rides.last;
    return l.endedAt ?? l.lastFixAt ?? l.startedAt;
  }

  /// Dny na cestě přes všechny jízdy (etapy, jinak kalendářní dny jízd).
  int get days {
    final set = <String>{};
    void add(DateTime t) {
      final l = t.toLocal();
      set.add('${l.year}-${l.month}-${l.day}');
    }
    for (final r in rides) {
      if (r.stages.isNotEmpty) {
        for (final s in r.stages) {
          if (s.movingSec < 300) continue;
          add(s.from);
          add(s.to);
        }
      } else if (r.movingSec >= 300) {
        final end = r.endedAt ?? r.lastFixAt ?? r.startedAt;
        var d = r.startedAt.toLocal();
        final e = end.toLocal();
        while (!DateTime(d.year, d.month, d.day).isAfter(e)) {
          add(d);
          d = DateTime(d.year, d.month, d.day + 1);
        }
      }
    }
    return set.isEmpty ? 1 : set.length;
  }

  late final UserRide aggregate = _aggregate();

  UserRide _aggregate() {
    final l = leader;
    var km = 0.0, moving = 0, idle = 0, gap = 0, pause = 0, gain = 0, dur = 0;
    double? max;
    final track = <LatLng>[];
    final segs = <RideSegment>[];
    final points = <RidePoint>[];
    final stages = <RideStage>[];
    UserRide? prev;
    for (final r in rides) {
      km += r.distanceKm;
      moving += r.movingSec;
      idle += r.idleSec;
      gap += r.gapSec;
      pause += r.pauseSec;
      gain += r.elevationGainM;
      dur += r.totalMin;
      if (r.maxSpeedKmh != null && (max == null || r.maxSpeedKmh! > max)) max = r.maxSpeedKmh;
      stages.addAll(r.stages);
      RideGap? join;
      if (prev != null) {
        final end = prev.endedAt ?? prev.lastFixAt ?? prev.startedAt;
        final dt = r.startedAt.difference(end).inSeconds;
        final night = dt <= kRideTripJoinPauseMaxSec;
        if (dt > 0 && night) pause += dt; // mezi jízdami cesty = pauza (noc…)
        final a = prev.mapPoints.isNotEmpty ? prev.mapPoints.last : null;
        final b = r.mapPoints.isNotEmpty ? r.mapPoints.first : null;
        if (a != null && b != null && night) {
          const d = Distance(roundResult: false, calculator: Haversine());
          final jkm = d.as(LengthUnit.Kilometer, a, b);
          final through = dt > 0 && dt <= kRideBadDtSec && jkm / dt * 3600 >= 15 && jkm > kRideStillKm;
          join = RideGap(from: a, to: b, sec: dt < 0 ? 0 : dt, km: jkm,
              kind: through ? RideGapKind.gap : RideGapKind.pause);
        }
      }
      final rs = r.segments.isNotEmpty ? r.segments : [RideSegment(r.mapPoints)];
      for (var i = 0; i < rs.length; i++) {
        segs.add(i == 0 ? RideSegment(rs[i].points, gapBefore: join) : rs[i]);
      }
      track.addAll(r.track);
      final first = identical(r, rides.first), last = identical(r, rides.last);
      points.addAll(r.points.where((p) => p.isStop || (p.isStart && first) || (p.isEnd && last)));
      prev = r;
    }
    final avg = moving >= 60 && km > 0 ? km / (moving / 3600) : null;
    final lastR = rides.last;
    return UserRide(
      id: l.id,
      bookingId: commonBookingId,
      motoId: l.motoId,
      motoName: rides.map((r) => r.motoName).firstWhere((m) => m != null, orElse: () => null),
      name: name ?? l.name,
      description: l.description,
      source: l.source,
      track: track,
      segments: List.unmodifiable(segs),
      startedAt: l.startedAt,
      endedAt: lastR.endedAt,
      distanceKm: km,
      durationMin: dur,
      movingSec: moving,
      idleSec: idle,
      gapSec: gap,
      pauseSec: pause,
      pauseAware: rides.every((r) => r.pauseAware),
      tripId: explicitTripId,
      tripName: name,
      stages: stages,
      serverV2: rides.any((r) => r.serverV2),
      // Součty cesty jsou „bez pauz" jen když tak počítá každá jízda.
      statsV2: rides.every((r) => r.statsV2),
      lastFixAt: lastR.lastFixAt,
      avgSpeedKmh: avg != null && avg.isFinite && avg < 200 ? avg : null,
      maxSpeedKmh: max,
      elevationGainM: gain,
      isRecording: isRecording,
      visibility: isPublic ? 'public' : 'private',
      status: rides.any((r) => r.isHidden) ? 'hidden' : 'approved',
      coverImage: rides.map((r) => r.coverImage).firstWhere((c) => c != null && c.isNotEmpty, orElse: () => null),
      points: points,
    );
  }
}

/// Rozsah dat jako jinde v „Mých jízdách": „6. 10. 2026", „6.–11. 10. 2026",
/// „28. 9. – 3. 10. 2026", „28. 12. 2025 – 3. 1. 2026".
String rideDateRange(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  if (x.year == y.year && x.month == y.month && x.day == y.day) {
    return '${x.day}. ${x.month}. ${x.year}';
  }
  if (x.year == y.year && x.month == y.month) return '${x.day}.–${y.day}. ${y.month}. ${y.year}';
  if (x.year == y.year) return '${x.day}. ${x.month}. – ${y.day}. ${y.month}. ${y.year}';
  return '${x.day}. ${x.month}. ${x.year} – ${y.day}. ${y.month}. ${y.year}';
}

/// Název cesty: jezdcův, jinak „Výpůjčka {moto}" / „Cesta {dates}".
String rideTripDefaultName(RideTrip t, AppTranslations tr) {
  final n = t.name;
  if (n != null) return n;
  final moto = t.aggregate.motoName;
  if (t.isRental && moto != null) return tr.trArgs('rpTripRental', {'moto': moto});
  return tr.trArgs('rpTripDefault', {'dates': rideDateRange(t.from, t.to)});
}
