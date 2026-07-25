import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/supabase_client.dart';
import 'routes_model.dart';

/// Těžké payloady tras a katalogu POI: HTTP stažení, jsonDecode i mapování na
/// modely běží v isolate (`compute`) — hlavní vlákno se při otevření tabu
/// „Trasy" nezasekne. Tělo úspěšné odpovědi se ukládá na disk, takže další
/// otevření zobrazí data okamžitě z cache a síť je jen tiše obnoví.
///
/// Trasy jdou primárně přes ODLEHČENOU RPC `get_branch_routes_lite`
/// (bez popisů/geometry/galerie — plný payload měl ~59 MB a stará RPC padala
/// na statement timeout); fallback je stará RPC a nakonec přímý REST select.

class RoutesCacheFiles {
  static const routes = 'routes_cache_v1.json';
  static const catalogPois = 'pois_catalog_cache_v1.json';
}

Future<String?> _cachePath(String name) async {
  try {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$name';
  } catch (_) {
    return null;
  }
}

/// Stáří cache souboru; null = soubor neexistuje / nejde přečíst.
Future<Duration?> cacheAge(String name) async {
  final p = await _cachePath(name);
  if (p == null) return null;
  try {
    final f = File(p);
    if (!await f.exists()) return null;
    return DateTime.now().difference(await f.lastModified());
  } catch (_) {
    return null;
  }
}

/// Parametry stažení pro isolate (jen jednoduché typy).
/// [postUrls] = RPC kandidáti v pořadí preference; [getUrl] = poslední
/// záchrana přímým REST selectem (může být výrazně větší payload).
class _FetchJob {
  final List<String> postUrls;
  final String? getUrl;
  final Map<String, String> headers;
  final String? savePath;
  const _FetchJob(this.postUrls, this.getUrl, this.headers, this.savePath);
}

Map<String, String> _rpcHeaders() {
  final token = MotoGoSupabase.currentSession?.accessToken;
  return {
    'apikey': MotoGoSupabase.anonKey,
    'Authorization': 'Bearer ${token ?? MotoGoSupabase.anonKey}',
    'Content-Type': 'application/json',
  };
}

// ── Top-level funkce pro compute (běží v isolate) ──

Future<String?> _saveBody(_FetchJob job, String body) async {
  final path = job.savePath;
  if (path != null) {
    try {
      await File(path).writeAsString(body, flush: true);
    } catch (_) {}
  }
  return body;
}

Future<String?> _fetchBody(_FetchJob job) async {
  for (final u in job.postUrls) {
    try {
      final res = await http
          .post(Uri.parse(u), headers: job.headers, body: '{}')
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        return _saveBody(job, utf8.decode(res.bodyBytes));
      }
    } catch (_) {}
  }
  final g = job.getUrl;
  if (g != null) {
    try {
      final res = await http
          .get(Uri.parse(g), headers: job.headers)
          .timeout(const Duration(seconds: 90)); // fallback může mít desítky MB
      if (res.statusCode == 200) {
        return _saveBody(job, utf8.decode(res.bodyBytes));
      }
    } catch (_) {}
  }
  return null;
}

List<RouteItem>? _parseRoutes(String body) {
  final data = jsonDecode(body);
  if (data is! List) return null;
  return data
      .whereType<Map>()
      .map((e) => RouteItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

/// Cache/fallback katalogu nemusí nést `is_catalog` — soubor i RPC obsahují
/// VÝHRADNĚ katalogové body, takže se flag doplní vždy.
List<RoutePoi>? _parseCatalog(String body) {
  final data = jsonDecode(body);
  if (data is! List) return null;
  return data
      .whereType<Map>()
      .map((e) {
        final m = Map<String, dynamic>.from(e);
        m['is_catalog'] = true;
        return RoutePoi.fromJson(m);
      })
      .where((p) => p.latLng != null)
      .toList();
}

Future<List<RouteItem>?> _fetchRoutesJob(_FetchJob job) async {
  final body = await _fetchBody(job);
  return body == null ? null : _parseRoutes(body);
}

Future<List<RoutePoi>?> _fetchCatalogJob(_FetchJob job) async {
  final body = await _fetchBody(job);
  return body == null ? null : _parseCatalog(body);
}

Future<List<RouteItem>?> _readRoutesCacheJob(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return _parseRoutes(await f.readAsString());
  } catch (_) {
    return null;
  }
}

Future<List<RoutePoi>?> _readCatalogCacheJob(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return _parseCatalog(await f.readAsString());
  } catch (_) {
    return null;
  }
}

// ── Veřejné API ──

/// Trasy ze sítě: lite RPC → stará RPC → přímý select. Vše v isolate,
/// tělo úspěšné odpovědi se uloží do diskové cache. null = vše selhalo.
Future<List<RouteItem>?> fetchRoutesRemote() async {
  const b = MotoGoSupabase.url;
  final job = _FetchJob(
    const [
      '$b/rest/v1/rpc/get_branch_routes_lite',
      '$b/rest/v1/rpc/get_branch_routes',
    ],
    '$b/rest/v1/routes?select=*,pois:route_pois(*)'
        '&is_active=eq.true&status=eq.approved&order=sort_order.asc',
    _rpcHeaders(),
    await _cachePath(RoutesCacheFiles.routes),
  );
  try {
    return await compute(_fetchRoutesJob, job);
  } catch (e) {
    debugPrint('[routes] isolate fetch tras selhal: $e');
    return null;
  }
}

/// Trasy z diskové cache (parsování v isolate); null = cache není.
Future<List<RouteItem>?> loadRoutesCache() async {
  final p = await _cachePath(RoutesCacheFiles.routes);
  if (p == null) return null;
  try {
    return await compute(_readRoutesCacheJob, p);
  } catch (_) {
    return null;
  }
}

/// Katalog samostatných POI: RPC `get_pois_catalog` → fallback přímý lite
/// select (bez překladů — jen dokud RPC není dostupná). V isolate + cache.
Future<List<RoutePoi>?> fetchCatalogPoisRemote() async {
  const b = MotoGoSupabase.url;
  final job = _FetchJob(
    const ['$b/rest/v1/rpc/get_pois_catalog'],
    '$b/rest/v1/points_of_interest'
        '?select=id,name,lat,lng,image_url,category,country&is_active=eq.true',
    _rpcHeaders(),
    await _cachePath(RoutesCacheFiles.catalogPois),
  );
  try {
    return await compute(_fetchCatalogJob, job);
  } catch (e) {
    debugPrint('[routes] isolate fetch katalogu selhal: $e');
    return null;
  }
}

/// Katalog POI z diskové cache (parsování v isolate); null = cache není.
Future<List<RoutePoi>?> loadCatalogPoisCache() async {
  final p = await _cachePath(RoutesCacheFiles.catalogPois);
  if (p == null) return null;
  try {
    return await compute(_readCatalogCacheJob, p);
  } catch (_) {
    return null;
  }
}
