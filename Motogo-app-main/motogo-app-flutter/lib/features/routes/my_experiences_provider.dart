import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/supabase_client.dart';
import 'routes_model.dart';
import 'routes_provider.dart' show RouteProfile;

/// „Moje zážitky" — vlastní uložené trasy (`user_saved_routes`) a objevená
/// místa (`user_visited_places`). Vše přes RPC (server-side ověření vlastníka).

double? _toD(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int? _toI(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

RouteProfile profileFromString(String? s) => switch (s) {
      'fastest' => RouteProfile.fastest,
      'shortest' => RouteProfile.shortest,
      _ => RouteProfile.recommended,
    };

String profileToString(RouteProfile p) => switch (p) {
      RouteProfile.fastest => 'fastest',
      RouteProfile.shortest => 'shortest',
      RouteProfile.recommended => 'recommended',
    };

/// Uložená vlastní trasa („Moje trasy").
class SavedRoute {
  final String id;
  final String name;
  final String? description;
  final String? sourceRouteId;
  final List<LatLng> waypoints;
  final List<String?> waypointNames; // popisek zastávky (align s waypoints)
  final List<RoutePoi> pois; // snapshot bodů zájmu (poi_refs)
  final Map<int, RoutePoi> poiByOrder; // order zastávky → bod zájmu
  final RouteProfile profile;
  final double? distanceKm;
  final int? durationMin;
  final DateTime? createdAt;

  const SavedRoute({
    required this.id,
    required this.name,
    this.description,
    this.sourceRouteId,
    this.waypoints = const [],
    this.waypointNames = const [],
    this.pois = const [],
    this.poiByOrder = const {},
    this.profile = RouteProfile.recommended,
    this.distanceKm,
    this.durationMin,
    this.createdAt,
  });

  factory SavedRoute.fromJson(Map<String, dynamic> j) {
    final wps = <LatLng>[];
    final names = <String?>[];
    final w = j['waypoints'];
    if (w is List) {
      for (final p in w) {
        if (p is Map) {
          final lat = _toD(p['lat']);
          final lng = _toD(p['lng']);
          if (lat != null && lng != null) {
            wps.add(LatLng(lat, lng));
            final label = p['label'];
            names.add(label is String && label.trim().isNotEmpty ? label.trim() : null);
          }
        }
      }
    }
    final pois = <RoutePoi>[];
    final byOrder = <int, RoutePoi>{};
    final refs = j['poi_refs'];
    if (refs is List) {
      for (final r in refs) {
        if (r is! Map) continue;
        final kind = r['kind']?.toString();
        final poi = RoutePoi(
          id: r['id']?.toString() ?? '',
          name: r['name']?.toString() ?? '',
          lat: _toD(r['lat']),
          lng: _toD(r['lng']),
          imageUrl: r['image_url']?.toString(),
          isUserPoi: kind == 'user',
          isCatalogPoi: kind == 'catalog',
        );
        pois.add(poi);
        final order = _toI(r['order']);
        if (order != null) byOrder[order] = poi;
      }
    }
    return SavedRoute(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      sourceRouteId: j['source_route_id']?.toString(),
      waypoints: wps,
      waypointNames: names,
      pois: pois,
      poiByOrder: byOrder,
      profile: profileFromString(j['profile']?.toString()),
      distanceKm: _toD(j['distance_km']),
      durationMin: _toI(j['duration_min']),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
    );
  }

  /// Trasa pro navigaci / mapu (stejný tvar jako vlastní vyjížďka z builderu).
  RouteItem toRouteItem() => RouteItem(
        id: 'custom',
        name: name,
        routeType: 'poi',
        waypoints: waypoints,
        pois: pois,
        distanceKm: distanceKm,
        durationMin: durationMin,
      );
}

/// Objevené místo („Moje místa").
class VisitedPlace {
  final String id;
  final String? routePoiId;
  final String? userPoiId;
  final String? poiId;
  final String name;
  final double? lat;
  final double? lng;
  final String? imageUrl;
  final String? routeId;
  final String? routeName;
  final DateTime? firstVisitedAt;
  final DateTime? lastVisitedAt;
  final int visitCount;

  const VisitedPlace({
    required this.id,
    this.routePoiId,
    this.userPoiId,
    this.poiId,
    required this.name,
    this.lat,
    this.lng,
    this.imageUrl,
    this.routeId,
    this.routeName,
    this.firstVisitedAt,
    this.lastVisitedAt,
    this.visitCount = 1,
  });

  LatLng? get latLng => (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

  factory VisitedPlace.fromJson(Map<String, dynamic> j) => VisitedPlace(
        id: j['id']?.toString() ?? '',
        routePoiId: j['route_poi_id']?.toString(),
        userPoiId: j['user_poi_id']?.toString(),
        poiId: j['poi_id']?.toString(),
        name: j['name']?.toString() ?? '',
        lat: _toD(j['lat']),
        lng: _toD(j['lng']),
        imageUrl: j['image_url']?.toString(),
        routeId: j['route_id']?.toString(),
        routeName: j['route_name']?.toString(),
        firstVisitedAt: DateTime.tryParse(j['first_visited_at']?.toString() ?? ''),
        lastVisitedAt: DateTime.tryParse(j['last_visited_at']?.toString() ?? ''),
        visitCount: _toI(j['visit_count']) ?? 1,
      );
}

/// Moje uložené trasy. Nepřihlášený → prázdný seznam (UI ukáže výzvu k loginu).
final mySavedRoutesProvider = FutureProvider<List<SavedRoute>>((ref) async {
  if (MotoGoSupabase.currentUser == null) return const [];
  try {
    final res = await MotoGoSupabase.client.rpc('get_my_saved_routes');
    final list = res is List ? res : const [];
    return list
        .whereType<Map>()
        .map((e) => SavedRoute.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (e) {
    debugPrint('[myexp] get_my_saved_routes selhalo: $e');
    return const [];
  }
});

/// Moje objevená místa.
final myPlacesProvider = FutureProvider<List<VisitedPlace>>((ref) async {
  if (MotoGoSupabase.currentUser == null) return const [];
  try {
    final res = await MotoGoSupabase.client.rpc('get_my_places');
    final list = res is List ? res : const [];
    return list
        .whereType<Map>()
        .map((e) => VisitedPlace.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (e) {
    debugPrint('[myexp] get_my_places selhalo: $e');
    return const [];
  }
});

/// Uloží vlastní trasu (RPC `save_user_route`). Vrací true při úspěchu.
Future<bool> saveUserRoute({
  required String name,
  String? description,
  String? sourceRouteId,
  required List<Map<String, dynamic>> waypoints,
  List<Map<String, dynamic>> poiRefs = const [],
  RouteProfile profile = RouteProfile.recommended,
  double? distanceKm,
  int? durationMin,
}) async {
  try {
    final res = await MotoGoSupabase.client.rpc('save_user_route', params: {
      'p_name': name,
      'p_description': description,
      'p_source_route_id': sourceRouteId,
      'p_waypoints': waypoints,
      'p_poi_refs': poiRefs,
      'p_profile': profileToString(profile),
      'p_distance_km': distanceKm,
      'p_duration_min': durationMin,
    });
    return res is Map && res['success'] == true;
  } catch (e) {
    debugPrint('[myexp] save_user_route selhalo: $e');
    return false;
  }
}

/// Smaže vlastní trasu.
Future<bool> deleteUserRoute(String id) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('delete_user_route', params: {'p_id': id});
    return res is Map && res['success'] == true;
  } catch (e) {
    debugPrint('[myexp] delete_user_route selhalo: $e');
    return false;
  }
}

/// Výsledek označení místa jako objeveného.
class VisitResult {
  final bool firstVisit;
  final int totalPlaces;
  const VisitResult({required this.firstVisit, required this.totalPlaces});
}

/// Označí bod zájmu jako navštívený (RPC `mark_place_visited`). Best-effort:
/// nepřihlášený / chyba sítě → null (navigace jede dál, nic nespadne).
Future<VisitResult?> markPlaceVisited(RoutePoi poi, {String? routeId}) async {
  if (MotoGoSupabase.currentUser == null || poi.id.isEmpty) return null;
  try {
    final res = await MotoGoSupabase.client.rpc('mark_place_visited', params: {
      'p_route_poi_id': (!poi.isUserPoi && !poi.isCatalogPoi) ? poi.id : null,
      'p_user_poi_id': poi.isUserPoi ? poi.id : null,
      'p_poi_id': poi.isCatalogPoi ? poi.id : null,
      'p_route_id': routeId,
    });
    if (res is Map && res['success'] == true) {
      return VisitResult(
        firstVisit: res['first_visit'] == true,
        totalPlaces: _toI(res['total_places']) ?? 0,
      );
    }
  } catch (e) {
    debugPrint('[myexp] mark_place_visited selhalo: $e');
  }
  return null;
}

/// Zastávka pro předání do editoru trasy (round-trip uložené trasy).
class BuilderStopSpec {
  final LatLng point;
  final String? name;
  final RoutePoi? poi;
  const BuilderStopSpec(this.point, {this.name, this.poi});
}

/// Argumenty pro otevření editoru s explicitními zastávkami (uložená trasa).
class RouteBuilderArgs {
  final RouteItem route;
  final List<BuilderStopSpec> stops;
  final String? savedRouteId; // odkud se editovalo (pro info)
  const RouteBuilderArgs(this.route, this.stops, {this.savedRouteId});
}

/// Sestaví BuilderStopSpec seznam z uložené trasy (zastávky + přiřazené body).
List<BuilderStopSpec> savedRouteStops(SavedRoute r) {
  final out = <BuilderStopSpec>[];
  for (var i = 0; i < r.waypoints.length; i++) {
    final poi = r.poiByOrder[i];
    out.add(BuilderStopSpec(
      r.waypoints[i],
      name: poi?.name ?? (i < r.waypointNames.length ? r.waypointNames[i] : null),
      poi: poi,
    ));
  }
  return out;
}
