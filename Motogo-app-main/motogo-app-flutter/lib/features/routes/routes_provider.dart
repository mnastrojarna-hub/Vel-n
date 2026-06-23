import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/supabase_client.dart';
import 'routes_model.dart';

const String mapyApiKey = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': mapyApiKey,
};

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

/// Sestaví uspořádaný seznam bodů pro routing/export.
/// - Okruh (loop): start = pobočka, waypointy, zpět na pobočku.
/// - Za body zájmu (poi): start = aktuální poloha (`currentPos`, pokud je
///   povolená v appce), jinak pobočka (kde je motorka); pak waypointy.
List<LatLng> orderedRoutePoints(RouteItem route, RouteBranch? branch, {LatLng? currentPos}) {
  final pts = <LatLng>[];
  final branchStart = branch?.latLng;
  final start = route.isLoop ? branchStart : (currentPos ?? branchStart);
  if (start != null) pts.add(start);
  pts.addAll(route.waypoints);
  if (route.isLoop && branchStart != null) pts.add(branchStart);
  // Odfiltruj duplicitní sousedy
  final out = <LatLng>[];
  for (final p in pts) {
    if (out.isEmpty || out.last.latitude != p.latitude || out.last.longitude != p.longitude) {
      out.add(p);
    }
  }
  return out;
}

/// Geometrie pro vykreslení v appce: použij uloženou (cache z Velína),
/// jinak ji dopočítej živě přes Mapy.com routing API. Když i to selže,
/// vrátí rovné spojnice mezi body (ať se vždy něco vykreslí).
final routeGeometryProvider =
    FutureProvider.family<List<LatLng>, String>((ref, routeId) async {
  final data = await ref.watch(routesDataProvider.future);
  final route = data.routes.firstWhere(
    (r) => r.id == routeId,
    orElse: () => const RouteItem(id: '', name: ''),
  );
  if (route.id.isEmpty) return <LatLng>[];
  if (route.geometry.length >= 2) return route.geometry;

  final branch = route.branchId != null ? data.branches[route.branchId] : null;
  final pts = orderedRoutePoints(route, branch);
  if (pts.length < 2) return pts;

  final live = await fetchMapyRoute(pts);
  return live ?? pts;
});

/// Volání Mapy.com routing API. Vrací dekódovanou polyline nebo null.
Future<List<LatLng>?> fetchMapyRoute(List<LatLng> points) async {
  if (points.length < 2) return null;
  final start = points.first;
  final end = points.last;
  final middle = points.sublist(1, points.length - 1);
  final params = <String, String>{
    'apikey': mapyApiKey,
    'lang': 'cs',
    'start': '${start.longitude},${start.latitude}',
    'end': '${end.longitude},${end.latitude}',
    'routeType': 'car_fast',
    'avoidHighways': 'true',
    'format': 'geojson',
  };
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
