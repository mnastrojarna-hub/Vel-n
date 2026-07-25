import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/supabase_client.dart';
import 'routes_model.dart';

/// Těžké payloady tras a katalogu POI (jednotky MB): HTTP stažení, jsonDecode
/// i mapování na modely běží v isolate (`compute`) — hlavní vlákno se při
/// otevření tabu „Trasy" nezasekne. Tělo odpovědi se navíc ukládá na disk,
/// takže další otevření zobrazí data okamžitě z cache a síť je jen tiše obnoví.

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

/// Parametry RPC volání předávané do isolate (jen jednoduché typy).
class _RpcJob {
  final String url;
  final Map<String, String> headers;
  final String? savePath;
  const _RpcJob(this.url, this.headers, this.savePath);
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

Future<String?> _httpRpc(_RpcJob job) async {
  final res = await http
      .post(Uri.parse(job.url), headers: job.headers, body: '{}')
      .timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) return null;
  final body = utf8.decode(res.bodyBytes);
  final path = job.savePath;
  if (path != null) {
    try {
      await File(path).writeAsString(body, flush: true);
    } catch (_) {}
  }
  return body;
}

List<RouteItem>? _parseRoutes(String body) {
  final data = jsonDecode(body);
  if (data is! List) return null;
  return data
      .whereType<Map>()
      .map((e) => RouteItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

List<RoutePoi>? _parseCatalog(String body) {
  final data = jsonDecode(body);
  if (data is! List) return null;
  return data
      .whereType<Map>()
      .map((e) => RoutePoi.fromJson(Map<String, dynamic>.from(e)))
      .where((p) => p.latLng != null)
      .toList();
}

Future<List<RouteItem>?> _fetchRoutesJob(_RpcJob job) async {
  final body = await _httpRpc(job);
  return body == null ? null : _parseRoutes(body);
}

Future<List<RoutePoi>?> _fetchCatalogJob(_RpcJob job) async {
  final body = await _httpRpc(job);
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

/// Trasy ze sítě (RPC `get_branch_routes` přes REST) — vše v isolate,
/// tělo odpovědi se po úspěchu uloží do diskové cache. null = selhání.
Future<List<RouteItem>?> fetchRoutesRemote() async {
  final job = _RpcJob(
    '${MotoGoSupabase.url}/rest/v1/rpc/get_branch_routes',
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

/// Katalog samostatných POI ze sítě (RPC `get_pois_catalog`) — v isolate + cache.
Future<List<RoutePoi>?> fetchCatalogPoisRemote() async {
  final job = _RpcJob(
    '${MotoGoSupabase.url}/rest/v1/rpc/get_pois_catalog',
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
