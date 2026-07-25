import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

import 'route_nav_motion.dart';
import 'routes_provider.dart'
    show MapyRouteInfo, RouteProfile, fetchMapyRouteInfo, polylineLengthM;

/// „Nikdy dvakrát po stejné silnici" — smyčky místo otoček.
///
/// Mapy.com routing mezi zastávkami vede po NEJRYCHLEJŠÍ cestě, takže od bodu
/// často vrací jezdce zpátky stejnou silnicí, kterou přijel (tam a zpět).
/// Tenhle modul plánovanou trasu POST-PROCESUJE:
/// 1. u každého úseku detekuje, jak dlouho se vrací po právě projeté cestě
///    (koridor ±[_kCorridorM] + kontrola PROTISMĚRU, ať serpentiny nejsou
///    falešný poplach),
/// 2. u zpátečních úseků si vyžádá alternativy přes pomocný via-bod stranou /
///    rovně za bod (router ho přichytí na jinou silnici → vznikne okruh),
/// 3. přijme jen alternativu, která otočku skutečně odstraní a není nesmyslně
///    dlouhá; když jiná silnice fyzicky neexistuje (slepá cesta), zůstane
///    původní vedení.
///
/// První úsek (od aktuální polohy) se porovnává s PROJETOU cestou jezdce —
/// po dojezdu na bod tak navigace nevede zpátky po silnici, po které přijel.

const double _kStepM = 40; // krok vzorkování polyline
const double _kScanM = 3000; // jak daleko od bodu se otočka zkoumá
const double _kCorridorM = 28; // „stejná silnice" = do této vzdálenosti
const double _kMinRetraceM = 300; // kratší souběh se neřeší (křižovatky)
const double _kNearStopSkipM = 130; // okolí bodu se nepočítá (nájezd nutný)
const double _kViaDistM = 600; // vzdálenost pomocného via-bodu od zastávky
const int _kMaxLegFixes = 3; // max opravených úseků na jeden výpočet

/// Bod koridoru projeté/příjezdové cesty + směr jízdy v něm.
class _CorrPt {
  final LatLng p;
  final double brg;
  const _CorrPt(this.p, this.brg);
}

/// Výpočet navigační trasy s potlačením otoček. Vrací upravenou trasu,
/// nebo výsledek základního routingu (fallback při chybě je vždy základ).
Future<MapyRouteInfo?> fetchNavRouteInfo(
  List<LatLng> points, {
  RouteProfile profile = RouteProfile.recommended,
  List<LatLng> traveled = const [],
}) async {
  final base = await fetchMapyRouteInfo(points, profile: profile);
  if (base == null) return null;
  try {
    return await _deloop(base, points, profile, traveled) ?? base;
  } catch (_) {
    return base;
  }
}

Future<MapyRouteInfo?> _deloop(
  MapyRouteInfo base,
  List<LatLng> stops,
  RouteProfile profile,
  List<LatLng> traveled,
) async {
  final cache = RouteGeoCache.build(base.geometry);
  if (cache == null || stops.length < 2) return null;

  // Pozice zastávek PO TRASE (jen ty, co na polyline reálně leží).
  final alongs = <double?>[];
  for (final s in stops) {
    final p = cache.project(s);
    alongs.add(p.distM <= 150 ? p.alongM : null);
  }

  final fixes = <int, MapyRouteInfo>{};
  for (var j = 0; j + 1 < stops.length && fixes.length < _kMaxLegFixes; j++) {
    final aj = alongs[j];
    final aj1 = alongs[j + 1];
    if (aj == null || aj1 == null || aj1 <= aj + 250) continue;

    // Koridor příjezdu k bodu: první úsek = reálně projetá cesta jezdce,
    // další úseky = trasa PŘED bodem. Seřazeno od bodu směrem ven.
    final corridor = j == 0
        ? _travelCorridor(traveled, stops[0])
        : _inboundCorridor(cache, aj);
    if (corridor.length < 4) continue;

    final baseOverlap =
        _overlapRange(cache, aj, math.min(aj1, aj + _kScanM), corridor, stops[j]);
    if (baseOverlap < _kMinRetraceM) continue;

    final legLenBase = aj1 - aj;
    final cands = _viaCandidates(stops[j], corridor.first.brg);
    // Alternativy paralelně — max 3 dotazy na úsek.
    final results = await Future.wait([
      for (final v in cands)
        fetchMapyRouteInfo([stops[j], v, stops[j + 1]], profile: profile),
    ]);
    MapyRouteInfo? best;
    var bestOv = double.infinity;
    var bestLen = double.infinity;
    for (final r in results) {
      if (r == null || r.geometry.length < 2) continue;
      final len = r.lengthM ?? polylineLengthM(r.geometry);
      // Okruh smí být delší než otočka, ale ne nesmyslně.
      if (len > legLenBase * 2.2 + 1500) continue;
      final lc = RouteGeoCache.build(r.geometry);
      if (lc == null) continue;
      final ov = _overlapRange(
          lc, 0, math.min(lc.totalM, _kScanM), corridor, stops[j]);
      // Alternativa musí otočku SKUTEČNĚ odstranit, ne jen zmenšit.
      if (ov > math.max(120.0, baseOverlap * 0.35)) continue;
      if (ov < bestOv || (ov == bestOv && len < bestLen)) {
        best = r;
        bestOv = ov;
        bestLen = len;
      }
    }
    if (best != null) fixes[j] = best;
  }
  if (fixes.isEmpty) return null;

  // Sešití: opravené úseky se vlepí do základní geometrie. Odzadu — indexy
  // v nezměněném prefixu základní trasy zůstávají platné.
  var geo = base.geometry;
  final baseDur = base.durationS?.toDouble();
  var durDelta = 0.0;
  final order = fixes.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final j in order) {
    final leg = fixes[j]!;
    final startSeg = cache.segAt(alongs[j]!);
    final endSeg = cache.segAt(alongs[j + 1]!);
    geo = [
      ...geo.sublist(0, startSeg + 1),
      ...leg.geometry,
      ...geo.sublist(math.min(endSeg + 1, geo.length)),
    ];
    if (baseDur != null) {
      final legLenBase = alongs[j + 1]! - alongs[j]!;
      final legDurBase = baseDur * legLenBase / cache.totalM;
      final legLenNew = leg.lengthM ?? polylineLengthM(leg.geometry);
      final legDurNew =
          leg.durationS?.toDouble() ?? legDurBase * legLenNew / legLenBase;
      durDelta += legDurNew - legDurBase;
    }
  }
  return MapyRouteInfo(
    geo,
    lengthM: polylineLengthM(geo),
    durationS: baseDur == null ? null : (baseDur + durDelta).round(),
  );
}

/// Koridor trasy PŘED zastávkou (příjezd) — body + směr jízdy, od bodu ven.
List<_CorrPt> _inboundCorridor(RouteGeoCache cache, double alongM) {
  final out = <_CorrPt>[];
  for (var m = alongM - _kStepM; m > 0 && m > alongM - _kScanM; m -= _kStepM) {
    out.add(_CorrPt(cache.pointAt(m), cache.bearingAt(m)));
  }
  return out;
}

/// Koridor z reálně projeté cesty jezdce (od aktuální polohy zpět). Okolí
/// startu se vynechá — pár metrů po stejné silnici je při odjezdu nevyhnutelné.
List<_CorrPt> _travelCorridor(List<LatLng> traveled, LatLng start) {
  const dist = Distance();
  final out = <_CorrPt>[];
  for (var i = traveled.length - 1; i > 0 && out.length < 80; i--) {
    final p = traveled[i];
    if (dist.as(LengthUnit.Meter, p, start) < _kNearStopSkipM) continue;
    out.add(_CorrPt(p, bearingBetween(traveled[i - 1], p)));
  }
  return out;
}

/// Kolik metrů z úseku [fromM]–[toM] trasy [cache] vede po koridoru
/// V PROTISMĚRU (= zpátky po stejné silnici). Kontrola směru odfiltruje
/// serpentiny a souběžné silnice; okolí zastávky [stop] se nepočítá.
double _overlapRange(RouteGeoCache cache, double fromM, double toM,
    List<_CorrPt> corridor, LatLng stop) {
  const dist = Distance();
  var overlap = 0.0;
  for (var m = fromM; m < toM; m += _kStepM) {
    final p = cache.pointAt(m);
    if (dist.as(LengthUnit.Meter, p, stop) < _kNearStopSkipM) continue;
    final brg = cache.bearingAt(m);
    for (final c in corridor) {
      if (dist.as(LengthUnit.Meter, p, c.p) > _kCorridorM) continue;
      if (angleDiff(brg, c.brg + 180) > 50) continue;
      overlap += _kStepM;
      break;
    }
  }
  return overlap;
}

/// Pomocné via-body pro objezd otočky: rovně ZA bod (ve směru příjezdu)
/// a kolmo do obou stran. Router si je přichytí na nejbližší silnici —
/// když jiná silnice neexistuje, alternativa se shoduje s otočkou a neprojde.
List<LatLng> _viaCandidates(LatLng stop, double inboundBrg) => [
      offsetLatLng(stop, inboundBrg, _kViaDistM),
      offsetLatLng(stop, (inboundBrg + 90) % 360, _kViaDistM),
      offsetLatLng(stop, (inboundBrg + 270) % 360, _kViaDistM),
    ];
