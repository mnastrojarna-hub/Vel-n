import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places_filter.dart';
import 'routes_model.dart';
import 'routes_provider.dart';

/// Silniční čára JEDNÉ trasy pro mapu tras.
///
/// Trasy se dřív na mapě kreslily jako rovné spojnice mezi zastávkami
/// (`routeLine()` sahá po `waypoints`, protože odlehčený seznam tras
/// geometrii vůbec neposílá a v DB je u drtivé většiny tras null). Tady se
/// proto vezme plný detail trasy a když geometrii nemá, dopočítá se živě přes
/// Mapy.com routing — výsledek drží paměťová cache v `fetchMapyRouteInfo`,
/// takže druhé zobrazení téže trasy už API nevolá.
final routeRoadLineProvider =
    FutureProvider.family<List<LatLng>, String>((ref, routeId) async {
  final data = await ref.watch(routesDataProvider.future);
  final route = await ref.watch(routeFullProvider(routeId).future);
  if (route == null || route.id.isEmpty) return const <LatLng>[];

  // 1) Předpočítaná geometrie z Velína — bez volání API.
  if (route.geometry.length >= 2) return route.geometry;

  // 2) Živý dopočet po silnici nad body trasy (bez polohy jezdce — čára
  //    trasy se nemění podle toho, kdo se dívá).
  final branch = route.branchId != null ? data.branches[route.branchId] : null;
  var pts = orderedRoutePoints(route, branch);
  if (pts.length < 2) {
    pts = [
      for (final p in route.pois)
        if (p.latLng != null) p.latLng!,
    ];
  }
  if (pts.length < 2) return const <LatLng>[];
  final geo = await fetchMapyRoute(pts);
  // Když routing selže, radši NIC než rovné čáry — uživatel výslovně chtěl
  // vidět trasu po silnici, ne vzdušné spojnice.
  return geo ?? const <LatLng>[];
});

/// Trasa právě poskládaná v editoru („Tvoje trasa").
///
/// Zadání uživatele: když si trasu navolím, vyberu profil (doporučené /
/// nejrychlejší / nejkratší) a dám ZPĚT, musí se ta trasa zobrazit na mapě —
/// a po silnici. Editor ji proto publikuje sem při každém přepočtu; mapa ji
/// pak kreslí, dokud ji jezdec nezruší, nespustí navigaci nebo neuloží.
@immutable
class DraftRoute {
  final String name;
  final List<LatLng> stops;
  final List<LatLng> geometry; // po silnici (z Mapy.com routingu)
  final String profile; // recommended / fastest / shortest
  final double? lengthM;
  final int? durationS;

  const DraftRoute({
    required this.name,
    required this.stops,
    required this.geometry,
    required this.profile,
    this.lengthM,
    this.durationS,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'stops': [for (final p in stops) [p.latitude, p.longitude]],
        'geometry': [for (final p in geometry) [p.latitude, p.longitude]],
        'profile': profile,
        if (lengthM != null) 'len': lengthM,
        if (durationS != null) 'dur': durationS,
      };

  static DraftRoute? fromJson(Map<String, dynamic> j) {
    List<LatLng> pts(dynamic raw) => [
          if (raw is List)
            for (final e in raw)
              if (e is List && e.length >= 2 && e[0] is num && e[1] is num)
                LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()),
        ];
    final geo = pts(j['geometry']);
    if (geo.length < 2) return null;
    return DraftRoute(
      name: (j['name'] as String?) ?? '',
      stops: pts(j['stops']),
      geometry: geo,
      profile: (j['profile'] as String?) ?? 'recommended',
      lengthM: (j['len'] as num?)?.toDouble(),
      durationS: (j['dur'] as num?)?.toInt(),
    );
  }
}

const String kDraftRouteKey = 'mg_draft_route_v1';

class DraftRouteNotifier extends Notifier<DraftRoute?> {
  @override
  DraftRoute? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(kDraftRouteKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) {
        final d = DraftRoute.fromJson(j);
        // Nepřepisovat trasu, kterou uživatel mezitím poskládal znovu.
        if (d != null && state == null) state = d;
      }
    } catch (_) {/* poškozený cache → nic */}
  }

  Future<void> set(DraftRoute route) async {
    state = route;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kDraftRouteKey, jsonEncode(route.toJson()));
    } catch (_) {}
  }

  Future<void> clear() async {
    state = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(kDraftRouteKey);
    } catch (_) {}
  }
}

final draftRouteProvider =
    NotifierProvider<DraftRouteNotifier, DraftRoute?>(DraftRouteNotifier.new);

/// Trasy, které obsahují vybraná místa, seřazené od nejlépe sedící. Mapa tras
/// z nich kreslí JEN JEDNU (zadání: „nemá tam být změť všech tras"); ostatní
/// slouží k přepínání čipem „1/3".
List<RouteItem> routesForSelection(
  List<RouteItem> all,
  List<PoiEntry> shown,
  Set<String> selected, {
  int limit = 5,
}) {
  final matched = routesContaining(all, shown, selected);
  return matched.length <= limit ? matched : matched.sublist(0, limit);
}
