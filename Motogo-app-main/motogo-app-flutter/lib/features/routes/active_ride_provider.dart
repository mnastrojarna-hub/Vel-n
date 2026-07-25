import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_client.dart';
import 'routes_model.dart';
import 'routes_provider.dart' show CustomNavArgs;
import 'my_experiences_provider.dart' show profileFromString;

/// Rozjetá jízda (aktivní navigace) + lokální historie jízd.
///
/// Aktivní trasa PŘEŽIJE zavření appky i přepnutí jinam — ukládá se do
/// SharedPreferences (klíče jsou v whitelistu CacheCleanupService, jinak by je
/// úklid při přechodu do pozadí smazal). Ruší se VÝHRADNĚ křížkem: v navigaci
/// nebo na FAB panelu „Pokračovat v trase". Ukončená jízda se přesune do
/// historie (Moje zážitky → Historie), odkud jde kdykoli pokračovat.

const String kActiveRidePrefsKey = 'mg_active_ride';
const String kRideHistoryPrefsKey = 'mg_ride_history';
const int _kHistoryMax = 30;

/// Jedna jízda — aktivní nebo v historii.
class ActiveRide {
  final String id; // unikátní id jízdy (epocha startu v ms)
  final String key; // routeId NEBO podpis vlastní trasy (souřadnice zastávek)
  final String name;
  final String? routeId; // trasa z DB; null = vlastní trasa
  final String profile; // recommended / fastest / shortest
  final List<int> reached; // indexy dojetých zastávek
  final int totalStops;
  final bool done;
  final DateTime startedAt;
  final DateTime updatedAt;
  /// Vlastní trasa: {waypoints:[{lat,lng,label}], pois:[{id,kind,name,lat,lng,
  /// image_url}], distance_km, duration_min} — stejné tvary jako uložené trasy.
  final Map<String, dynamic>? custom;

  const ActiveRide({
    required this.id,
    required this.key,
    required this.name,
    this.routeId,
    this.profile = 'recommended',
    this.reached = const [],
    this.totalStops = 0,
    this.done = false,
    required this.startedAt,
    required this.updatedAt,
    this.custom,
  });

  ActiveRide copyWith({
    List<int>? reached,
    int? totalStops,
    bool? done,
    DateTime? updatedAt,
    String? id,
    DateTime? startedAt,
  }) =>
      ActiveRide(
        id: id ?? this.id,
        key: key,
        name: name,
        routeId: routeId,
        profile: profile,
        reached: reached ?? this.reached,
        totalStops: totalStops ?? this.totalStops,
        done: done ?? this.done,
        startedAt: startedAt ?? this.startedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        custom: custom,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'name': name,
        'route_id': routeId,
        'profile': profile,
        'reached': reached,
        'total_stops': totalStops,
        'done': done,
        'started_at': startedAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (custom != null) 'custom': custom,
      };

  static ActiveRide? fromJson(dynamic j) {
    if (j is! Map) return null;
    final key = j['key']?.toString();
    if (key == null || key.isEmpty) return null;
    return ActiveRide(
      id: j['id']?.toString() ?? '',
      key: key,
      name: j['name']?.toString() ?? '',
      routeId: j['route_id']?.toString(),
      profile: j['profile']?.toString() ?? 'recommended',
      reached: (j['reached'] as List? ?? const [])
          .map((e) => e is num ? e.toInt() : int.tryParse('$e') ?? -1)
          .where((e) => e >= 0)
          .toList(),
      totalStops: (j['total_stops'] as num?)?.toInt() ?? 0,
      done: j['done'] == true,
      startedAt:
          DateTime.tryParse(j['started_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? DateTime.now(),
      custom: j['custom'] is Map
          ? Map<String, dynamic>.from(j['custom'] as Map)
          : null,
    );
  }

  /// Zpětná rekonstrukce vlastní trasy pro navigaci (stejný tvar jako
  /// `SavedRoute.toRouteItem`). U DB trasy vrací null (naviguje se přes id).
  RouteItem? customRouteItem() {
    final c = custom;
    if (c == null) return null;
    final wps = <LatLng>[];
    final w = c['waypoints'];
    if (w is List) {
      for (final p in w) {
        if (p is Map) {
          final lat = (p['lat'] as num?)?.toDouble();
          final lng = (p['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) wps.add(LatLng(lat, lng));
        }
      }
    }
    final pois = <RoutePoi>[];
    final ps = c['pois'];
    if (ps is List) {
      for (final r in ps) {
        if (r is! Map) continue;
        final kind = r['kind']?.toString();
        pois.add(RoutePoi(
          id: r['id']?.toString() ?? '',
          name: r['name']?.toString() ?? '',
          lat: (r['lat'] as num?)?.toDouble(),
          lng: (r['lng'] as num?)?.toDouble(),
          imageUrl: r['image_url']?.toString(),
          isUserPoi: kind == 'user',
          isCatalogPoi: kind == 'catalog',
        ));
      }
    }
    if (wps.isEmpty && pois.isEmpty) return null;
    return RouteItem(
      id: 'custom',
      name: name,
      routeType: 'poi',
      waypoints: wps,
      pois: pois,
      distanceKm: (c['distance_km'] as num?)?.toDouble(),
      durationMin: (c['duration_min'] as num?)?.toInt(),
    );
  }
}

/// Podpis vlastní trasy — stabilní klíč z pořadí a souřadnic zastávek.
String customRideKey(RouteItem route) {
  final sb = StringBuffer('c:');
  for (final w in route.waypoints) {
    sb
      ..write(w.latitude.toStringAsFixed(4))
      ..write(',')
      ..write(w.longitude.toStringAsFixed(4))
      ..write(';');
  }
  if (route.waypoints.isEmpty) {
    for (final p in route.pois) {
      sb..write(p.lat?.toStringAsFixed(4))..write(',')
        ..write(p.lng?.toStringAsFixed(4))..write(';');
    }
  }
  return sb.toString();
}

/// Stav: aktivní jízda (max 1) + historie ukončených/odložených jízd.
class RideState {
  final ActiveRide? active;
  final List<ActiveRide> history;
  final bool loaded;
  const RideState({this.active, this.history = const [], this.loaded = false});
}

class ActiveRideNotifier extends StateNotifier<RideState> {
  ActiveRideNotifier() : super(const RideState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final active = ActiveRide.fromJson(
          jsonDecode(prefs.getString(kActiveRidePrefsKey) ?? 'null'));
      final rawH = prefs.getString(kRideHistoryPrefsKey);
      final history = <ActiveRide>[];
      if (rawH != null) {
        final list = jsonDecode(rawH);
        if (list is List) {
          for (final e in list) {
            final r = ActiveRide.fromJson(e);
            if (r != null) history.add(r);
          }
        }
      }
      if (!mounted) return;
      state = RideState(active: active, history: history, loaded: true);
    } catch (_) {
      if (mounted) state = const RideState(loaded: true);
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final a = state.active;
      if (a == null) {
        await prefs.remove(kActiveRidePrefsKey);
      } else {
        await prefs.setString(kActiveRidePrefsKey, jsonEncode(a.toJson()));
      }
      await prefs.setString(kRideHistoryPrefsKey,
          jsonEncode(state.history.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  List<ActiveRide> _historyWithout(String key) =>
      state.history.where((h) => h.key != key).toList();

  /// Start jízdy z navigace. Existující aktivní jízda po JINÉ trase se
  /// odloží do historie (jde v ní pokračovat později).
  void startRide(ActiveRide ride) {
    final prev = state.active;
    var history = _historyWithout(ride.key);
    if (prev != null && prev.key != ride.key) {
      history = [prev, ...history];
    }
    if (history.length > _kHistoryMax) history = history.sublist(0, _kHistoryMax);
    state = RideState(active: ride, history: history, loaded: state.loaded);
    _persist();
  }

  /// Průběžný zápis postupu (dojeté zastávky / dokončení).
  void updateProgress({
    required List<int> reached,
    required int totalStops,
    required bool done,
  }) {
    final a = state.active;
    if (a == null) return;
    state = RideState(
      active: a.copyWith(
          reached: reached,
          totalStops: totalStops,
          done: done,
          updatedAt: DateTime.now()),
      history: state.history,
      loaded: state.loaded,
    );
    _persist();
  }

  /// Ukončení křížkem — jízda se přesune do historie.
  void endRide() {
    final a = state.active;
    if (a == null) return;
    var history = [a.copyWith(updatedAt: DateTime.now()), ..._historyWithout(a.key)];
    if (history.length > _kHistoryMax) history = history.sublist(0, _kHistoryMax);
    state = RideState(active: null, history: history, loaded: state.loaded);
    _persist();
  }

  /// Pokračování v jízdě z historie — stane se znovu aktivní.
  void resume(ActiveRide ride, {bool fresh = false}) {
    final r = fresh
        ? ride.copyWith(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            reached: const [],
            done: false,
            startedAt: DateTime.now(),
            updatedAt: DateTime.now())
        : ride.copyWith(updatedAt: DateTime.now());
    startRide(r);
  }

  void removeFromHistory(String id) {
    state = RideState(
      active: state.active,
      history: state.history.where((h) => h.id != id).toList(),
      loaded: state.loaded,
    );
    _persist();
  }
}

final activeRideProvider =
    StateNotifierProvider<ActiveRideNotifier, RideState>(
        (ref) => ActiveRideNotifier());

/// Otevře navigaci dané jízdy (FAB / historie / start appky).
void openRide(BuildContext context, ActiveRide ride) {
  if (ride.routeId != null && ride.routeId!.isNotEmpty) {
    context.push('/route-nav/${ride.routeId}');
    return;
  }
  final item = ride.customRouteItem();
  if (item != null) {
    context.push('/route-nav-custom',
        extra: CustomNavArgs(item, profileFromString(ride.profile)));
  }
}

/// Po startu appky: dokud jezdec trasu nezavře křížkem, appka se otevře
/// zpátky na jeho rozjeté navigaci. Volá main.dart po prvním framu.
Future<void> maybeResumeActiveRideOnLaunch(
    GlobalKey<NavigatorState> navKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kActiveRidePrefsKey);
    if (raw == null) return;
    final ride = ActiveRide.fromJson(jsonDecode(raw));
    if (ride == null || ride.done) return; // dokončenou neotvírej automaticky
    // Router se po startu ustálí (redirect na login/home) — chvíli počkej.
    await Future.delayed(const Duration(milliseconds: 700));
    if (MotoGoSupabase.currentSession == null) return; // vrátí se přes FAB
    final ctx = navKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    openRide(ctx, ride);
  } catch (_) {}
}
