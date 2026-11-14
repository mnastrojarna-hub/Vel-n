import 'package:latlong2/latlong.dart';

/// Etapa (den) jedné jízdy — počítá ji server (`user_rides.stages`, SPEC
/// §3.5). Hranice = pauza ≥ 6 h nebo ≥ 30 min přes noc (00:00–05:00 Praha).
/// Vícedenní cesta je JEDNA jízda s více etapami, ne více jízd.
class RideStage {
  const RideStage({
    required this.from,
    required this.to,
    this.km = 0,
    this.movingSec = 0,
    this.gapSec = 0,
    this.pauseSec = 0,
    this.gain = 0,
    this.max,
    this.a,
    this.b,
  });

  final DateTime from;
  final DateTime to;
  final double km;
  final int movingSec; // čas v sedle
  final int gapSec; // bez signálu
  final int pauseSec; // kratší pauzy uvnitř etapy (oběd…)
  final int gain; // nastoupáno (m)
  final double? max;
  final LatLng? a; // začátek etapy
  final LatLng? b; // konec etapy

  /// Zastávky = zbytek (nikdy se nesčítají zvlášť, takže nejdou nafouknout).
  int get idleSec {
    final v = to.difference(from).inSeconds - movingSec - gapSec - pauseSec;
    return v > 0 ? v : 0;
  }

  /// Průměr z času v sedle (null = málo dat).
  double? get avgKmh {
    if (movingSec < 60 || km <= 0) return null;
    final v = km / (movingSec / 3600);
    return v.isFinite && v < 200 ? v : null;
  }

  static double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static LatLng? _ll(Object? v) {
    if (v is! List || v.length < 2) return null;
    final lat = _d(v[0]), lng = _d(v[1]);
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  static DateTime? _ts(Object? v) {
    final s = _d(v);
    return s == null ? null : DateTime.fromMillisecondsSinceEpoch((s * 1000).round(), isUtc: true);
  }

  /// `{"f","t","km","mv","gap","ps","gain","max","a","b"}`; vadný prvek → null.
  static RideStage? fromJson(Object? j) {
    if (j is! Map) return null;
    final f = _ts(j['f']), t = _ts(j['t']);
    if (f == null || t == null) return null;
    return RideStage(
      from: f,
      to: t.isBefore(f) ? f : t,
      km: _d(j['km']) ?? 0,
      movingSec: (_d(j['mv']) ?? 0).round(),
      gapSec: (_d(j['gap']) ?? 0).round(),
      pauseSec: (_d(j['ps']) ?? 0).round(),
      gain: (_d(j['gain']) ?? 0).round(),
      max: _d(j['max']),
      a: _ll(j['a']),
      b: _ll(j['b']),
    );
  }

  static List<RideStage> listFromJson(Object? j) {
    if (j is! List) return const [];
    return [
      for (final e in j)
        if (fromJson(e) case final s?) s,
    ];
  }
}

/// Počet dní cesty = různá MÍSTNÍ data začátků a konců etap, ve kterých se
/// opravdu jelo (≥ 5 min v sedle); aspoň 1.
int rideDaysOfStages(Iterable<RideStage> stages) {
  final days = <String>{};
  for (final s in stages) {
    if (s.movingSec < 300) continue;
    for (final t in [s.from.toLocal(), s.to.toLocal()]) {
      days.add('${t.year}-${t.month}-${t.day}');
    }
  }
  return days.isEmpty ? 1 : days.length;
}

/// Počet místních kalendářních dní mezi [a] a [b] (včetně).
int rideCalendarDays(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  final d0 = DateTime.utc(x.year, x.month, x.day);
  final d1 = DateTime.utc(y.year, y.month, y.day);
  final n = d1.difference(d0).inDays + 1;
  return n < 1 ? 1 : n;
}
