import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/supabase_client.dart';
import '../reservations/reservation_models.dart';
import '../reservations/reservation_provider.dart';
import 'routes_cache.dart';
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

/// Všechny publikované trasy + mapa poboček. Payload RPC `get_branch_routes`
/// má jednotky MB, proto se stahuje a parsuje v isolate (routes_cache.dart)
/// a tělo se drží v diskové cache: otevření tabu zobrazí data OKAMŽITĚ z cache
/// a síť je jen tiše obnoví na pozadí (stale-while-revalidate).
final routesDataProvider =
    AsyncNotifierProvider<RoutesDataNotifier, RoutesData>(RoutesDataNotifier.new);

/// Do kdy je cache „čerstvá" = při startu se vůbec nestahuje ze sítě.
/// Explicitní invalidate (pull-to-refresh, nová recenze…) jde VŽDY na síť.
const _routesCacheTtl = Duration(minutes: 15);
const _catalogCacheTtl = Duration(hours: 12);

// Top-level flagy: přežijí i znovuvytvoření notifieru při invalidate.
// true = v tomto běhu appky už proběhl (nebo nebyl potřeba) síťový load,
// další rebuild provideru tedy jde rovnou na síť (čerstvá data po invalidate).
bool _routesNetworkDone = false;
bool _catalogNetworkDone = false;

class RoutesDataNotifier extends AsyncNotifier<RoutesData> {
  @override
  Future<RoutesData> build() async {
    if (!_routesNetworkDone) {
      final cached = await loadRoutesCache();
      if (cached != null && cached.isNotEmpty) {
        final age = await cacheAge(RoutesCacheFiles.routes);
        if (age != null && age < _routesCacheTtl) {
          _routesNetworkDone = true; // čerstvé — bez zbytečného stahování
        } else {
          _refreshInBackground(); // fire-and-forget, cache se mezitím zobrazí
        }
        return RoutesData(routes: cached, branches: await _branches());
      }
    }
    return _fetchFresh();
  }

  Future<RoutesData> _fetchFresh() async {
    final routes = await _fetchRoutes();
    _routesNetworkDone = true;
    return RoutesData(routes: routes, branches: await _branches());
  }

  Future<void> _refreshInBackground() async {
    try {
      state = AsyncData(await _fetchFresh());
    } catch (_) {} // cache zůstává zobrazená (i StateError po dispose)
  }

  Future<List<RouteItem>> _fetchRoutes() async {
    // Primárně REST RPC v isolate (bez zámrazu UI). Fallback na přímý select
    // přes klienta, kdyby RPC/REST selhalo.
    final viaIsolate = await fetchRoutesRemote();
    if (viaIsolate != null) return viaIsolate;
    debugPrint('[routes] REST get_branch_routes selhalo, fallback na select');
    final res = await MotoGoSupabase.client
        .from('routes')
        .select('*, pois:route_pois(*)')
        .eq('is_active', true)
        .order('sort_order');
    return (res as List)
        .whereType<Map>()
        .map((e) => RouteItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Pobočky (jen ty, na které trasy odkazují — ale načteme všechny aktivní,
  /// je to levné a pokryje to i budoucí přiřazení).
  Future<Map<String, RouteBranch>> _branches() async {
    final branches = <String, RouteBranch>{};
    try {
      final bRes = await MotoGoSupabase.client
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
    return branches;
  }
}

/// Naposledy otevřená (zvolená) trasa — jen její id. Slouží řazení „od zvolené
/// trasy" v seznamu tras i bodů zájmu (bez polohy jezdce). Nastavuje se při
/// otevření detailu trasy.
final lastOpenedRouteProvider = StateProvider<String?>((ref) => null);

/// PLNÁ data jedné trasy (popis, galerie, geometry, POI s popisy a překlady).
/// Seznam jede odlehčeně přes `get_branch_routes_lite`, detail se dotáhne
/// per trasa přes RPC `get_route_detail` až při otevření. Fallback: položka
/// ze seznamu (ta je plná, dokud lite RPC není nasazená / při chybě).
final routeFullProvider =
    FutureProvider.family<RouteItem?, String>((ref, id) async {
  final data = await ref.watch(routesDataProvider.future);
  RouteItem? listItem;
  for (final r in data.routes) {
    if (r.id == id) {
      listItem = r;
      break;
    }
  }
  // Plná položka (fallback režim) → detail netahej.
  if (listItem != null &&
      (listItem.description != null ||
          listItem.images.isNotEmpty ||
          listItem.geometry.isNotEmpty)) {
    return listItem;
  }
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_route_detail', params: {'p_id': id});
    if (res is Map && res.isNotEmpty) {
      return RouteItem.fromJson(Map<String, dynamic>.from(res));
    }
  } catch (e) {
    debugPrint('[routes] get_route_detail selhalo: $e');
  }
  return listItem;
});

/// Plný detail trasového bodu (popis, okolí, galerie, překlady) — RPC
/// `get_route_poi_detail`. Odlehčený seznam tras tato pole u POI neposílá,
/// dotahují se až při otevření bodu. Best-effort: při chybě null.
Future<RoutePoi?> fetchRoutePoiDetail(String id) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_route_poi_detail', params: {'p_id': id});
    if (res is Map && res.isNotEmpty) {
      return RoutePoi.fromJson(Map<String, dynamic>.from(res));
    }
  } catch (_) {}
  return null;
}

/// Jeden bod zájmu + odkaz na trasu a pobočku, ke které patří. Slouží katalogu
/// všech POI v appce (zákazník si skládá vlastní vyjížďku napříč trasami).
class PoiEntry {
  final RoutePoi poi;
  final RouteItem? route; // null = bod bez trasy (katalog / komunitní)
  final RouteBranch? branch;
  final bool catalog; // samostatný bod z katalogu „zajímavá místa" (ne od uživatele)
  const PoiEntry(this.poi, this.route, this.branch, {this.catalog = false});
  LatLng? get latLng => poi.latLng;
  /// Komunitní = navržený uživatelem (bez trasy a mimo katalog).
  bool get isCommunity => route == null && !catalog;
  String get key => route != null
      ? '${route!.id}:${poi.id}'
      : (catalog ? 'catalog:${poi.id}' : 'user:${poi.id}');
}

/// Katalog samostatných bodů zájmu (přehrady, jezera, hrady, rozhledny,
/// památky, přírodní rezervace…) — nezávislé na trasách. RPC `get_pois_catalog`
/// (desítky tisíc bodů) — stejný režim jako trasy: isolate + disková cache,
/// zobrazí se okamžitě a obnoví na pozadí. Best-effort: při selhání [].
final catalogPoisProvider =
    AsyncNotifierProvider<CatalogPoisNotifier, List<RoutePoi>>(
        CatalogPoisNotifier.new);

class CatalogPoisNotifier extends AsyncNotifier<List<RoutePoi>> {
  @override
  Future<List<RoutePoi>> build() async {
    if (!_catalogNetworkDone) {
      final cached = await loadCatalogPoisCache();
      if (cached != null && cached.isNotEmpty) {
        final age = await cacheAge(RoutesCacheFiles.catalogPois);
        if (age != null && age < _catalogCacheTtl) {
          _catalogNetworkDone = true;
        } else {
          _refreshInBackground();
        }
        return cached;
      }
    }
    final list = await fetchCatalogPoisRemote();
    _catalogNetworkDone = true;
    return list ?? const [];
  }

  Future<void> _refreshInBackground() async {
    try {
      final list = await fetchCatalogPoisRemote();
      if (list != null) {
        _catalogNetworkDone = true;
        state = AsyncData(list);
      }
    } catch (_) {}
  }
}

/// Donačte PLNÝ detail katalogového bodu (popis, okolí, galerie, kompletní
/// překlady) — RPC `get_poi_detail`. Katalog se do seznamu posílá odlehčený
/// (bez těchto polí kvůli velikosti payloadu), detail se tak dotáhne až při
/// otevření konkrétního bodu. Best-effort: při chybě/neexistenci vrátí null
/// a UI zůstane u toho, co má z odlehčeného seznamu.
Future<RoutePoi?> fetchCatalogPoiDetail(String id) async {
  try {
    final res = await MotoGoSupabase.client
        .rpc('get_poi_detail', params: {'p_id': id});
    if (res is Map && res.isNotEmpty) {
      return RoutePoi.fromJson(Map<String, dynamic>.from(res));
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Schválené uživatelské body zájmu (komunitní) — RPC `get_user_pois`.
final userPoisProvider = FutureProvider<List<RoutePoi>>((ref) async {
  try {
    final res = await MotoGoSupabase.client.rpc('get_user_pois');
    final list = res is List ? res : const [];
    return list
        .whereType<Map>()
        .map((e) => RoutePoi.fromUserJson(Map<String, dynamic>.from(e)))
        .where((p) => p.latLng != null)
        .toList();
  } catch (_) {
    return const [];
  }
});

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

/// Pobočka / poloha / pobočka vyzvednutí se jako start trasy použije jen
/// když leží do [kStartNearRouteKm] od prvního bodu trasy. Vzdálené trasy
/// (zahraniční seedy patřící domovské pobočce) jinak startují od svého
/// prvního waypointu — bez limitu by se kreslil a navigoval i přejezd
/// z pobočky přes půl Evropy.
const double kStartNearRouteKm = 50;

/// První bod trasy (waypoint, jinak první bod zájmu s GPS).
LatLng? routeAnchor(RouteItem route) {
  if (route.waypoints.isNotEmpty) return route.waypoints.first;
  for (final p in route.pois) {
    final ll = p.latLng;
    if (ll != null) return ll;
  }
  return null;
}

bool startIsNearRoute(RouteItem route, LatLng? start) {
  if (start == null) return false;
  final anchor = routeAnchor(route);
  if (anchor == null) return true; // trasa bez bodů — chovej se postaru
  return const Distance().as(LengthUnit.Kilometer, start, anchor) <=
      kStartNearRouteKm;
}

/// Sestaví uspořádaný seznam bodů pro routing/export:
/// start = pobočka (pokud má GPS a je poblíž trasy), pak waypointy,
/// u okruhu zpět na pobočku.
List<LatLng> orderedRoutePoints(RouteItem route, RouteBranch? branch) {
  final pts = <LatLng>[];
  final start =
      startIsNearRoute(route, branch?.latLng) ? branch?.latLng : null;
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
  // Plná trasa kvůli geometry (odlehčený seznam ji neposílá).
  final route = await ref.watch(routeFullProvider(routeId).future) ??
      const RouteItem(id: '', name: '');
  if (route.id.isEmpty) return const RouteDisplay(geometry: []);

  final routeBranch =
      route.branchId != null ? data.branches[route.branchId] : null;
  final routeBranchLatLng = routeBranch?.latLng;

  if (route.routeType == 'poi') {
    // 1) Od aktuální polohy (jen když už je povolená a je poblíž trasy) —
    //    nejrychleji bez dálnic.
    final myLoc = await ref.watch(currentLocationProvider.future);
    if (myLoc != null && startIsNearRoute(route, myLoc)) {
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
    // 2) Od pobočky vyzvednutí (z rezervace), jinak od pobočky trasy —
    //    jen pokud je start poblíž trasy (vzdálené trasy kreslíme samotné).
    final pickup = ref.watch(pickupOriginProvider);
    final start0 = pickup ?? routeBranchLatLng;
    final start = startIsNearRoute(route, start0) ? start0 : null;
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

  // Okruh / fallback: start = pobočka trasy, u vzdálené trasy její první bod.
  final displayStart = startIsNearRoute(route, routeBranchLatLng)
      ? routeBranchLatLng
      : routeAnchor(route);
  if (route.geometry.length >= 2) {
    return RouteDisplay(geometry: route.geometry, start: displayStart);
  }
  final pts = orderedRoutePoints(route, routeBranch);
  if (pts.length < 2) {
    return RouteDisplay(geometry: pts, start: displayStart);
  }
  final live = await fetchMapyRoute(pts);
  return RouteDisplay(geometry: live ?? pts, start: displayStart);
});

/// Výsledek Mapy.com routingu: geometrie + reálná délka/čas po silnici z API.
class MapyRouteInfo {
  final List<LatLng> geometry;
  final double? lengthM; // reálná délka po silnici v metrech (pole `length`)
  final int? durationS; // čas jízdy v sekundách (pole `duration`)
  const MapyRouteInfo(this.geometry, {this.lengthM, this.durationS});
}

/// Délka polyline v metrech (součet úseků). Nad geometrií z routingu je to
/// reálná délka po silnici — na rozdíl od vzdušné čáry mezi zastávkami.
double polylineLengthM(List<LatLng> g) {
  const d = Distance();
  double s = 0;
  for (var i = 0; i < g.length - 1; i++) {
    s += d.as(LengthUnit.Meter, g[i], g[i + 1]);
  }
  return s;
}

/// Reálná délka trasy po silnici v km (místo odhadu `distance_km` z DB):
/// 1) z předpočítané geometrie trasy (reálná polyline z Velína) bez volání API,
/// 2) jinak živý dopočet přes Mapy.com routing nad body trasy samotné
///    (bez polohy jezdce — délka trasy se nemění podle toho, kdo se dívá).
/// null = nejde spočítat → UI ukáže `distance_km` z DB jako fallback.
final routeRealLengthKmProvider =
    FutureProvider.family<double?, String>((ref, routeId) async {
  final data = await ref.watch(routesDataProvider.future);
  // Plná trasa kvůli geometry (odlehčený seznam ji neposílá).
  final route = await ref.watch(routeFullProvider(routeId).future) ??
      const RouteItem(id: '', name: '');
  if (route.id.isEmpty) return null;

  if (route.geometry.length >= 2) {
    return polylineLengthM(route.geometry) / 1000;
  }

  final branch = route.branchId != null ? data.branches[route.branchId] : null;
  var pts = orderedRoutePoints(route, branch);
  if (pts.length < 2) {
    // Trasa bez waypointů — body zájmu v uloženém pořadí.
    pts = _dedupeNeighbours([
      for (final p in route.pois)
        if (p.latLng != null) p.latLng!,
    ]);
  }
  if (pts.length < 2) return null;
  final info = await fetchMapyRouteInfo(pts);
  if (info == null) return null;
  return (info.lengthM ?? polylineLengthM(info.geometry)) / 1000;
});

/// Volání Mapy.com routing API — jen geometrie (pro vykreslení trasy).
Future<List<LatLng>?> fetchMapyRoute(List<LatLng> points,
    {RouteProfile profile = RouteProfile.recommended}) async {
  final info = await fetchMapyRouteInfo(points, profile: profile);
  return info?.geometry;
}

/// Volání Mapy.com routing API. Vrací dekódovanou polyline + reálnou délku
/// a čas po silnici (pole `length`/`duration` z odpovědi), nebo null.
/// `profile` určuje typ trasy (doporučené bez dálnic / nejrychlejší / nejkratší).
Future<MapyRouteInfo?> fetchMapyRouteInfo(List<LatLng> points,
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
    if (out.length < 2) return null;
    return MapyRouteInfo(
      out,
      lengthM: _numField(data, 'length'),
      durationS: _numField(data, 'duration')?.round(),
    );
  } catch (e) {
    debugPrint('[routes] Mapy routing selhalo: $e');
    return null;
  }
}

/// Číselné pole z odpovědi routingu — přímo v kořeni nebo v `summary`
/// (délka v metrech / čas v sekundách). Vrací null, když chybí nebo je 0.
double? _numField(dynamic data, String key) {
  if (data is! Map) return null;
  var v = data[key];
  if (v == null && data['summary'] is Map) v = (data['summary'] as Map)[key];
  return (v is num && v > 0) ? v.toDouble() : null;
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
