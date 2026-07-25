import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Plynulý pohyb polohy v navigaci.
///
/// GPS chodí po ~1 s fixech → marker nesmí „teleportovat". Princip:
/// 1. fix se PROMÍTNE na polyline trasy (snap) a uloží se jeho pozice PO TRASE,
/// 2. mezi fixy se poloha PREDIKUJE — posouvá se po polyline aktuální
///    rychlostí (jízda pokračuje po trase, dokud ji další fix nepotvrdí),
/// 3. další fix predikci jen potvrdí / zkoriguje a zobrazená poloha se k ní
///    plynule doanimuje (exponenciální vyhlazení v [expSmooth]).
///
/// [RouteGeoCache] drží délky segmentů + kumulativy, takže projekce s oknem
/// kolem posledního segmentu i bod „X metrů po trase" jsou levné pro každý
/// snímek animace.

/// Výsledek projekce polohy na polyline trasy.
class RouteProgress {
  final int segIndex; // index počátku segmentu, na který poloha spadla
  final LatLng snapped; // nejbližší bod na trase
  final double remainingM; // metry do cíle PO TRASE
  final double totalM; // celková délka trasy
  final double distM; // vzdálenost polohy od trasy (off-route detekce)
  const RouteProgress(
      this.segIndex, this.snapped, this.remainingM, this.totalM, this.distM);
  double get alongM => totalM - remainingM;
}

/// Cache geometrie trasy pro levné opakované výpočty.
class RouteGeoCache {
  final List<LatLng> pts;
  final List<double> segLen; // délka segmentu i (pts[i] → pts[i+1])
  final List<double> cum; // kumulativní metry do pts[i]
  final double totalM;
  RouteGeoCache._(this.pts, this.segLen, this.cum, this.totalM);

  static RouteGeoCache? build(List<LatLng> pts) {
    if (pts.length < 2) return null;
    const dist = Distance();
    final segLen = <double>[];
    final cum = <double>[0];
    var total = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final l = dist.as(LengthUnit.Meter, pts[i], pts[i + 1]);
      segLen.add(l);
      total += l;
      cum.add(total);
    }
    return RouteGeoCache._(pts, segLen, cum, total);
  }

  /// Projekce polohy na trasu. [hintSeg] = poslední známý segment — hledá se
  /// jen v okně kolem něj; mimo okno (odchylka) se projede celá trasa.
  RouteProgress project(LatLng me, {int? hintSeg}) {
    if (hintSeg != null && hintSeg >= 0 && hintSeg < segLen.length) {
      final lo = math.max(0, hintSeg - 25);
      final hi = math.min(segLen.length, hintSeg + 60);
      final p = _projectRange(me, lo, hi);
      if (p.distM <= 120) return p;
    }
    return _projectRange(me, 0, segLen.length);
  }

  RouteProgress _projectRange(LatLng me, int lo, int hi) {
    const dist = Distance();
    double best = double.infinity;
    var bestSeg = lo;
    LatLng bestSnap = pts[lo];
    for (var i = lo; i < hi; i++) {
      final snap = closestOnSeg(pts[i], pts[i + 1], me);
      final d = dist.as(LengthUnit.Meter, me, snap);
      if (d < best) {
        best = d;
        bestSeg = i;
        bestSnap = snap;
      }
    }
    final along =
        cum[bestSeg] + dist.as(LengthUnit.Meter, pts[bestSeg], bestSnap);
    return RouteProgress(bestSeg, bestSnap, totalM - along, totalM, best);
  }

  /// Bod ve vzdálenosti [alongM] metrů po trase (predikce mezi GPS fixy).
  LatLng pointAt(double alongM) {
    final m = alongM.clamp(0.0, totalM);
    var lo = 0, hi = segLen.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cum[mid] <= m) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final l = segLen[lo];
    final t = l <= 0 ? 0.0 : ((m - cum[lo]) / l).clamp(0.0, 1.0);
    final a = pts[lo], b = pts[lo + 1];
    return LatLng(a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t);
  }

  /// Směr jízdy (bearing ve stupních) segmentu [seg] — stabilnější než GPS
  /// heading, když jedu po trase.
  double segBearing(int seg) {
    final i = seg.clamp(0, pts.length - 2);
    final a = pts[i], b = pts[i + 1];
    final dLng =
        (b.longitude - a.longitude) * math.cos(a.latitude * math.pi / 180);
    final dLat = b.latitude - a.latitude;
    return (math.atan2(dLng, dLat) * 180 / math.pi + 360) % 360;
  }
}

/// Nejbližší bod na úsečce a-b k bodu p (lokální rovinná aproximace v metrech).
LatLng closestOnSeg(LatLng a, LatLng b, LatLng p) {
  const mPerLat = 111320.0;
  final mPerLng = 111320.0 * math.cos(a.latitude * math.pi / 180);
  final bx = (b.longitude - a.longitude) * mPerLng;
  final by = (b.latitude - a.latitude) * mPerLat;
  final px = (p.longitude - a.longitude) * mPerLng;
  final py = (p.latitude - a.latitude) * mPerLat;
  final len2 = bx * bx + by * by;
  double t = len2 == 0 ? 0 : (px * bx + py * by) / len2;
  t = t.clamp(0.0, 1.0);
  final sx = t * bx, sy = t * by;
  return LatLng(a.latitude + sy / mPerLat, a.longitude + sx / mPerLng);
}

/// Vyhlazení úhlu nejkratší cestou (zamezí skoku 359°→0°).
double lerpAngle(double a, double b, double t) {
  double d = (b - a) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return a + d * t;
}

/// Faktor exponenciálního vyhlazení nezávislý na frameratu:
/// hodnota se blíží cíli rychlostí [rate] za sekundu.
double expSmooth(double dtSeconds, double rate) =>
    1 - math.exp(-dtSeconds * rate);

/// Lineární interpolace mezi dvěma souřadnicemi.
LatLng lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t);
