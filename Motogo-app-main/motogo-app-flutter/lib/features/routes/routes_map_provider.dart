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
/// (sahalo se po `waypoints`, protože odlehčený seznam tras geometrii vůbec
/// neposílá a v DB je u drtivé většiny tras null). Tady se
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
/// je kreslí VŠECHNY (každou jinou barvou) a dole nabídne kartu pro každou,
/// aby si jezdec vybral, kterou pojede — zadání z 2026-10-04: „když vyberu
/// místo, přes které vedou dvě trasy, ukáže mi to jen jednu a nemůžu si
/// vybrat". [limit] drží počet volání routingu v rozumných mezích.
List<RouteItem> routesForSelection(
  List<RouteItem> all,
  List<PoiEntry> shown,
  Set<String> selected, {
  int limit = 5,
}) {
  final matched = routesContaining(all, shown, selected);
  return matched.length <= limit ? matched : matched.sublist(0, limit);
}

/// Trasa PO SILNICI přes místa, která si uživatel naklikal na mapě míst —
/// v pořadí, v jakém je klikal.
///
/// Zadání uživatele (2026-10-04): mapa míst nemá kreslit žádné trasy
/// z katalogu (byly to jen rovné spojnice zastávek — odlehčený seznam tras
/// geometrii neposílá), ale má POČÍTAT trasu podle naklikaných míst: „jsem
/// v mapě, klikám postupně po jednotlivých místech a ukazuje mi to trasu".
/// Výběr (`placesSelectionProvider`) je LinkedHashSet, takže pořadí klikání
/// drží; stejné pořadí pak dostane i editor trasy („Pokračovat").
@immutable
class SelectionRoute {
  /// Vybraná místa s GPS v pořadí klikání.
  final List<LatLng> stops;

  /// Čára po silnici (Mapy.com). Prázdná = routing selhal → nekreslí se nic
  /// (rovné spojnice uživatel výslovně nechce).
  final List<LatLng> geometry;
  final double? lengthM;
  final int? durationS;

  const SelectionRoute({
    required this.stops,
    required this.geometry,
    this.lengthM,
    this.durationS,
  });

  bool get hasLine => geometry.length >= 2;
}

/// Klíč rodiny [selectionRoadRouteProvider]: klíče výběru v pořadí klikání.
/// Rodina provideru potřebuje parametr s hodnotovou rovností, a String ji má;
/// každá obrazovka si tak může poslat vlastní výběr (seznam Míst v režimu
/// výběru pro editor má výběr lokální, ne sdílený).
String selectionRouteKey(Iterable<String> keys) => keys.join('\n');

final selectionRoadRouteProvider = FutureProvider.autoDispose
    .family<SelectionRoute?, String>((ref, keysJoined) async {
  if (keysJoined.isEmpty) return null;
  // Set literál = LinkedHashSet → pořadí klíčů (= klikání) zůstává.
  final keys = <String>{...keysJoined.split('\n')};
  final pois = resolveSelected(
    ref.watch(dedupedPlacesProvider),
    ref.watch(allPlacesProvider),
    keys,
  );
  final stops = <LatLng>[
    for (final p in pois)
      if (p.latLng != null) p.latLng!,
  ];
  if (stops.length < 2) return null;
  // Debounce: rychlé klikání po mapě nemá sypat na routing dotaz za dotazem.
  // Každá změna výběru provider přestaví (nový klíč rodiny), starý běh se po
  // zrušení jen tiše ukončí — na API se tak ptá až ustálený výběr.
  var alive = true;
  ref.onDispose(() => alive = false);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (!alive) return null;
  // Stejný profil jako editor (doporučené = bez dálnic); odpověď drží
  // paměťová cache ve `fetchMapyRouteInfo`, opakované zobrazení API nevolá.
  final info =
      await fetchMapyRouteInfo(stops, profile: RouteProfile.recommended);
  if (info == null) return SelectionRoute(stops: stops, geometry: const []);
  return SelectionRoute(
    stops: stops,
    geometry: info.geometry,
    lengthM: info.lengthM ?? polylineLengthM(info.geometry),
    durationS: info.durationS,
  );
});

/// Odhad času jízdy z délky po silnici (km/h jako editor trasy u profilu
/// „doporučené"). Mapy.com `duration` v odpovědi někdy chybí.
int selectionRouteMinutes(SelectionRoute r) {
  if (r.durationS != null) return (r.durationS! / 60).round();
  final km = (r.lengthM ?? 0) / 1000;
  return (km / 55 * 60).round();
}

/// „45 min" / „2 h 10 min" — stejný formát jako karty v seznamu tras.
String fmtRideMinutes(int min) {
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}
