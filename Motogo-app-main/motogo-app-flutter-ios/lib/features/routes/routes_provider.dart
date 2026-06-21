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

/// Sestaví uspořádaný seznam bodů pro routing/export:
/// start = pobočka (pokud má GPS), pak waypointy, u okruhu zpět na pobočku.
List<LatLng> orderedRoutePoints(RouteItem route, RouteBranch? branch) {
  final pts = <LatLng>[];
  final start = branch?.latLng;
  if (start != null) pts.add(start);
  pts.addAll(route.waypoints);
  if (route.isLoop && start != null) pts.add(start);
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
    final coords = data is Map
        ? (data['geometry']?['geometry']?['coordinates'] ??
            data['geometry']?['coordinates'] ??
            (data['features'] is List && (data['features'] as List).isNotEmpty
                ? data['features'][0]?['geometry']?['coordinates']
                : null))
        : null;
    if (coords is! List || coords.length < 2) return null;
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
