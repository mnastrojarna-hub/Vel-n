import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/supabase_client.dart';
import '../reservations/reservation_models.dart';
import '../reservations/reservation_provider.dart';
import 'routes_model.dart';

const String mapyApiKey = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': mapyApiKey,
};

/// Profil trasy pro routing (Mapy.com):
/// - [recommended] = nejrychlejší autem BEZ dálnic (zážitková jízda na motorce),
/// - [fastest] = nejrychlejší (i dálnice),
/// - [shortest] = nejkratší.
enum RouteProfile { recommended, fastest, shortest }

({String routeType, bool avoidHighways}) _profileParams(RouteProfile p) {
  switch (p) {
    case RouteProfile.recommended:
      return (routeType: 'car_fast', avoidHighways: true);
    case RouteProfile.fastest:
      return (routeType: 'car_fast', avoidHighways: false);
    case RouteProfile.shortest:
      return (routeType: 'car_short', avoidHighways: false);
  }
}

/// Reverzní geokódování bodu na mapě → název místa (Mapy.com rgeocode).
/// Best-effort: při chybě vrátí null a volající použije obecný popisek.
Future<String?> reverseGeocode(LatLng p) async {
  try {
    final uri = Uri.https('api.mapy.cz', '/v1/rgeocode', {
      'lon': p.longitude.toString(),
      'lat': p.latitude.toString(),
      'lang': 'cs',
      'apikey': mapyApiKey,
    });
    final res = await http.get(uri, headers: _mapyHeaders)
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    final items = data is Map ? data['items'] : null;
    if (items is List && items.isNotEmpty) {
      final it = items.first;
      if (it is Map) {
        final name = it['name'] ?? it['label'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
    }
  } catch (_) {}
  return null;
}

/// Všechny publikované trasy + mapa poboček. Jedno volání RPC `get_branch_routes`
/// (vrací trasy se zanořenými body zájmu) + lehký dotaz na pobočky kvůli názvu
/// a GPS startu.
final routesDataProvider = FutureProvider<RoutesData>((ref) async {
  final client = MotoGoSupabase.client;

  // 1) Trasy přes RPC (public, vrací jsonb pole). Fallback na přímý select,
  //    kdyby RPC ještě nebyla nasazená.
  List rawRoutes;
  try {
    final res = await client.rpc('get_branch_routes');
    rawRoutes = res is List ? res : (res == null ? const [] : List.from(res as Iterable));
  } catch (e) {
    debugPrint('[routes] RPC get_branch_routes selhalo, fallback na select: $e');
    final res = await client
        .from('routes')
        .select('*, pois:route_pois(*)')
        .eq('is_active', true)
        .order('sort_order');
    rawRoutes = res as List;
  }

  final routes = rawRoutes
      .whereType<Map>()
      .map((e) => RouteItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  // 2) Pobočky (jen ty, na které trasy odkazují — ale načteme všechny aktivní,
  //    je to levné a pokryje to i budoucí přiřazení).
  final branches = <String, RouteBranch>{};
  try {
    final bRes = await client
        .from('branches')
        .select('id, name, city, gps_lat, gps_lng')
        .eq('active', true);
    for (final b in (bRes as List)) {
      final rb = RouteBranch.fromJson(Map<String, dynamic>.from(b as Map));
      branches[rb.id] = rb;
    }
  } catch (e) {
    debugPrint('[routes] načtení poboček selhalo: $e');
  }

  return RoutesData(routes: routes, branches: branches);
});

/// Jeden bod zájmu + odkaz na trasu a pobočku, ke které patří. Slouží katalogu
/// všech POI v appce (zákazník si skládá vlastní vyjížďku napříč trasami).
class PoiEntry {
  final RoutePoi poi;
  final RouteItem route;
  final RouteBranch? branch;
  const PoiEntry(this.poi, this.route, this.branch);
  LatLng? get latLng => poi.latLng;
  String get key => '${route.id}:${poi.id}';
}

/// Všechny body zájmu napříč všemi (aktivními) trasami — pro katalog v appce.
/// Trasa je jen doporučení; přes tento katalog si zákazník vybere zastávky
/// z různých tras, případně dvě trasy spojí v jednu vlastní vyjížďku.
final allPoisProvider = Provider<List<PoiEntry>>((ref) {
  final data = ref.watch(routesDataProvider).valueOrNull;
  if (data == null) return const [];
  final out = <PoiEntry>[];
  for (final r in data.routes) {
    final b = r.branchId != null ? data.branches[r.branchId] : null;
    for (final p in r.pois) {
      if (p.latLng != null) out.add(PoiEntry(p, r, b));
    }
  }
  return out;
});

/// Sestaví „vlastní" trasu z vybraných bodů zájmu (spojení bodů z více tras).
/// Pořadí = hladový nejbližší soused od startu `from` (poloha jezdce / pobočka),
/// jinak se zachová vstupní pořadí. Výsledek se naviguje jako běžná POI trasa.
RouteItem buildCustomRoute(List<RoutePoi> pois, {LatLng? from, String name = ''}) {
  final pts = pois.where((p) => p.latLng != null).toList();
  final ordered = from != null ? _greedyOrder(pts, from) : pts;
  return RouteItem(
    id: 'custom',
    name: name,
    routeType: 'poi',
    waypoints: ordered.map((p) => p.latLng!).toList(),
    pois: ordered,
  );
}

/// Argumenty pro navigaci přes vlastní složenou trasu (route + profil routingu).
class CustomNavArgs {
  final RouteItem route;
  final RouteProfile profile;
  const CustomNavArgs(this.route, this.profile);
}

List<RoutePoi> _greedyOrder(List<RoutePoi> pts, LatLng from) {
  const dist = Distance();
  final remaining = [...pts];
  final out = <RoutePoi>[];
  var cur = from;
  while (remaining.isNotEmpty) {
    var bi = 0;
    var bd = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final d = dist.as(LengthUnit.Meter, cur, remaining[i].latLng!);
      if (d < bd) {
        bd = d;
        bi = i;
      }
    }
    final n = remaining.removeAt(bi);
    out.add(n);
    cur = n.latLng!;
  }
  return out;
}

/// Sestaví uspořádaný seznam bodů pro routing/export:
/// start = pobočka (pokud má GPS), pak waypointy, u okruhu zpět na pobočku.
List<LatLng> orderedRoutePoints(RouteItem route, RouteBranch? branch) {
  final pts = <LatLng>[];
  final start = branch?.latLng;
  if (start != null) pts.add(start);
  pts.addAll(route.waypoints);
  if (route.isLoop && start != null) pts.add(start);
  return _dedupeNeighbours(pts);
}

/// Body pro routing OD zadaného startu (poloha jezdce / pobočka vyzvednutí)
/// přes waypointy trasy. `loopBack` = bod, na který se má trasa vrátit (u okruhu
/// pobočka), jinak null = trasa končí v posledním bodě.
List<LatLng> navPointsFrom(LatLng start, RouteItem route, LatLng? loopBack) {
  final pts = <LatLng>[start];
  if (route.waypoints.isNotEmpty) {
    pts.addAll(route.waypoints);
  } else {
    for (final p in route.pois) {
      final ll = p.latLng;
      if (ll != null) pts.add(ll);
    }
  }
  if (loopBack != null) pts.add(loopBack);
  return _dedupeNeighbours(pts);
}

List<LatLng> _dedupeNeighbours(List<LatLng> pts) {
  final out = <LatLng>[];
  for (final p in pts) {
    if (out.isEmpty ||
        out.last.latitude != p.latitude ||
        out.last.longitude != p.longitude) {
      out.add(p);
    }
  }
  return out;
}

/// Výchozí start trasy podle stavu:
/// - `currentLocation` = od aktuální polohy jezdce (poloha už povolena),
/// - `pickupBranch` = od pobočky, ze které zákazník vyzvedl motorku (rezervace),
/// - `routeBranch` = od pobočky, ke které trasa patří (výchozí).
enum RouteOrigin { routeBranch, pickupBranch, currentLocation }

/// Vykreslitelná trasa + její efektivní start a původ startu.
class RouteDisplay {
  final List<LatLng> geometry;
  final LatLng? start;
  final RouteOrigin origin;
  const RouteDisplay({
    required this.geometry,
    this.start,
    this.origin = RouteOrigin.routeBranch,
  });
}

/// Aktuální poloha — JEN pokud je oprávnění už uděleno (bez vyžádání systémového
/// dialogu). Vrací null, když poloha není povolená/dostupná → výchozí náhled trasy
/// pak vychází z pobočky vyzvednutí, ne z polohy.
final currentLocationProvider = FutureProvider<LatLng?>((ref) async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
});

/// Pobočka, ze které má zákazník vyzvednout (nebo vyzvedl) motorku — vybere
/// nejrelevantnější rezervaci (aktivní → nejbližší nadcházející zaplacenou).
/// U přistavení (delivery) použije GPS místa přistavení. Výchozí start pro
/// trasy „za body zájmu" bez povolené polohy.
final pickupOriginProvider = Provider<LatLng?>((ref) {
  final list = ref.watch(reservationsProvider).valueOrNull ?? const [];
  Reservation? best;
  for (final r in list) {
    final s = r.displayStatus;
    if (s == ResStatus.aktivni) {
      best = r;
      break;
    }
    if (s == ResStatus.nadchazejici && r.paymentStatus == 'paid') {
      best ??= r;
    }
  }
  if (best == null) return null;
  if (best.pickupMethod == 'delivery' &&
      best.pickupLat != null &&
      best.pickupLng != null) {
    return LatLng(best.pickupLat!, best.pickupLng!);
  }
  if (best.branchLat != null && best.branchLng != null) {
    return LatLng(best.branchLat!, best.branchLng!);
  }
  return null;
});

/// Geometrie + start pro vykreslení trasy v appce.
///
/// Trasy „za body zájmu" (route_type='poi'):
///   1) pokud je poloha povolená → nejrychlejší trasa BEZ DÁLNIC od aktuální polohy,
///   2) jinak od pobočky vyzvednutí (z rezervace zákazníka),
///   3) jinak od pobočky, ke které trasa patří.
/// Okruhy (loop) zůstávají od pobočky trasy (cache geometrie z Velína / živý dopočet).
final routeDisplayProvider =
    FutureProvider.family<RouteDisplay, String>((ref, routeId) async {
  final data = await ref.watch(routesDataProvider.future);
  final route = data.routes.firstWhere(
    (r) => r.id == routeId,
    orElse: () => const RouteItem(id: '', name: ''),
  );
  if (route.id.isEmpty) return const RouteDisplay(geometry: []);

  final routeBranch =
      route.branchId != null ? data.branches[route.branchId] : null;
  final routeBranchLatLng = routeBranch?.latLng;

  if (route.routeType == 'poi') {
    // 1) Od aktuální polohy (jen když už je povolená) — nejrychleji bez dálnic.
    final myLoc = await ref.watch(currentLocationProvider.future);
    if (myLoc != null) {
      final pts = navPointsFrom(myLoc, route, null);
      if (pts.length >= 2) {
        final geo = await fetchMapyRoute(pts, profile: RouteProfile.recommended);
        return RouteDisplay(
          geometry: geo ?? pts,
          start: myLoc,
          origin: RouteOrigin.currentLocation,
        );
      }
    }
    // 2) Od pobočky vyzvednutí (z rezervace), jinak od pobočky trasy.
    final pickup = ref.watch(pickupOriginProvider);
    final start = pickup ?? routeBranchLatLng;
    if (start != null) {
      final isRouteBranch = routeBranchLatLng != null &&
          start.latitude == routeBranchLatLng.latitude &&
          start.longitude == routeBranchLatLng.longitude;
      final origin = (pickup != null && !isRouteBranch)
          ? RouteOrigin.pickupBranch
          : RouteOrigin.routeBranch;
      // Start = pobočka trasy a máme předpočítanou geometrii → použij cache.
      if (isRouteBranch && route.geometry.length >= 2) {
        return RouteDisplay(
            geometry: route.geometry, start: start, origin: origin);
      }
      final pts = navPointsFrom(start, route, null);
      if (pts.length >= 2) {
        final geo = await fetchMapyRoute(pts, profile: RouteProfile.recommended);
        return RouteDisplay(geometry: geo ?? pts, start: start, origin: origin);
      }
    }
  }

  // Okruh / fallback: stávající chování (start = pobočka trasy).
  if (route.geometry.length >= 2) {
    return RouteDisplay(geometry: route.geometry, start: routeBranchLatLng);
  }
  final pts = orderedRoutePoints(route, routeBranch);
  if (pts.length < 2) {
    return RouteDisplay(geometry: pts, start: routeBranchLatLng);
  }
  final live = await fetchMapyRoute(pts);
  return RouteDisplay(geometry: live ?? pts, start: routeBranchLatLng);
});

/// Volání Mapy.com routing API. Vrací dekódovanou polyline nebo null.
/// `profile` určuje typ trasy (doporučené bez dálnic / nejrychlejší / nejkratší).
Future<List<LatLng>?> fetchMapyRoute(List<LatLng> points,
    {RouteProfile profile = RouteProfile.recommended}) async {
  if (points.length < 2) return null;
  final start = points.first;
  final end = points.last;
  final middle = points.sublist(1, points.length - 1);
  final pp = _profileParams(profile);
  final params = <String, String>{
    'apikey': mapyApiKey,
    'lang': 'cs',
    'start': '${start.longitude},${start.latitude}',
    'end': '${end.longitude},${end.latitude}',
    'routeType': pp.routeType,
    'format': 'geojson',
  };
  if (pp.avoidHighways) params['avoidHighways'] = 'true';
  if (middle.isNotEmpty) {
    params['waypoints'] =
        middle.map((p) => '${p.longitude},${p.latitude}').join(';');
  }
  try {
    final uri = Uri.https('api.mapy.cz', '/v1/routing/route', params);
    final res = await http.get(uri, headers: _mapyHeaders)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    final coords = data is Map ? _extractGeoCoords(data, start) : null;
    if (coords == null || coords.length < 2) return null;
    final out = <LatLng>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        final lng = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        out.add(LatLng(lat, lng));
      }
    }
    return out.length >= 2 ? out : null;
  } catch (e) {
    debugPrint('[routes] Mapy routing selhalo: $e');
    return null;
  }
}

/// Vytáhne geometrii trasy z odpovědi Mapy routing (GeoJSON i polyline string).
/// Vrací List bodů `[lng, lat]` nebo null. `ref` = orientační bod pro výběr
/// přesnosti polyline.
List? _extractGeoCoords(Map data, LatLng ref) {
  // 1) GeoJSON varianty
  final g = data['geometry'];
  if (g is Map) {
    final gg = g['geometry'];
    if (gg is Map && gg['coordinates'] is List) return gg['coordinates'] as List;
    if (g['coordinates'] is List) return g['coordinates'] as List;
  }
  final feats = data['features'];
  if (feats is List && feats.isNotEmpty) {
    final f0 = feats[0];
    if (f0 is Map && f0['geometry'] is Map &&
        (f0['geometry'] as Map)['coordinates'] is List) {
      return (f0['geometry'] as Map)['coordinates'] as List;
    }
  }
  // 2) Zakódovaný polyline string
  String? str;
  if (g is String) {
    str = g;
  } else if (g is Map && g['geometry'] is String) {
    str = g['geometry'] as String;
  } else if (data['shape'] is String) {
    str = data['shape'] as String;
  }
  if (str != null) {
    for (final factor in <double>[1e5, 1e6]) {
      final dec = _decodePolyline(str, factor);
      if (dec.length >= 2 &&
          (dec[0][0] - ref.longitude).abs() < 1.5 &&
          (dec[0][1] - ref.latitude).abs() < 1.5) {
        return dec;
      }
    }
  }
  return null;
}

/// Standardní polyline dekodér → List bodů `[lng, lat]`.
List<List<double>> _decodePolyline(String str, double factor) {
  int index = 0, lat = 0, lng = 0;
  final coords = <List<double>>[];
  while (index < str.length) {
    int b, shift = 0, result = 0;
    do {
      b = str.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = str.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    coords.add([lng / factor, lat / factor]);
  }
  return coords;
}
