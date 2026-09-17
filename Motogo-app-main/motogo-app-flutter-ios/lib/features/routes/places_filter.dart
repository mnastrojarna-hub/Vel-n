import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'poi_categories.dart';
import 'routes_model.dart';
import 'routes_provider.dart';

/// Řazení seznamu míst. (Délka/čas se u samostatných míst neuplatní —
/// smysluplné je náhodně, od polohy a od zvolené trasy.)
enum PoiSort { random, nearMe, nearRoute }

/// Filtr míst SDÍLENÝ mezi seznamem a mapou.
///
/// Dřív žil celý ve stavu obrazovky, takže mapa o něm nevěděla a ukazovala
/// všechna místa bez ohledu na to, co měl uživatel zrovna nastavené. Teď je
/// to jeden zdroj pravdy: co je vidět v seznamu, je vidět i na mapě.
class PlacesFilter {
  final String query;
  final Set<String> cats; // klíče kategorií (prázdné = všechny)
  final Set<String> countries; // ISO kódy (prázdné = všechny)
  final double minRating; // 0 = bez omezení
  final bool nearbyOn;
  final double nearbyKm;
  final String? routeId; // jen body konkrétní trasy
  final PoiSort sort;

  const PlacesFilter({
    this.query = '',
    this.cats = const {},
    this.countries = const {},
    this.minRating = 0,
    this.nearbyOn = false,
    this.nearbyKm = 10,
    this.routeId,
    this.sort = PoiSort.random,
  });

  PlacesFilter copyWith({
    String? query,
    Set<String>? cats,
    Set<String>? countries,
    double? minRating,
    bool? nearbyOn,
    double? nearbyKm,
    String? routeId,
    bool clearRouteId = false,
    PoiSort? sort,
  }) =>
      PlacesFilter(
        query: query ?? this.query,
        cats: cats ?? this.cats,
        countries: countries ?? this.countries,
        minRating: minRating ?? this.minRating,
        nearbyOn: nearbyOn ?? this.nearbyOn,
        nearbyKm: nearbyKm ?? this.nearbyKm,
        routeId: clearRouteId ? null : (routeId ?? this.routeId),
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is PlacesFilter &&
      other.query == query &&
      other.minRating == minRating &&
      other.nearbyOn == nearbyOn &&
      other.nearbyKm == nearbyKm &&
      other.routeId == routeId &&
      other.sort == sort &&
      other.cats.length == cats.length &&
      other.cats.containsAll(cats) &&
      other.countries.length == countries.length &&
      other.countries.containsAll(countries);

  @override
  int get hashCode => Object.hash(query, minRating, nearbyOn, nearbyKm,
      routeId, sort, cats.length, countries.length);

  /// Kolik filtrů je aktivních — řídí odznak u „Řadit a filtrovat" i to,
  /// jestli se ukáže tlačítko „Zrušit filtry".
  int get activeCount =>
      (query.trim().isEmpty ? 0 : 1) +
      (cats.isEmpty ? 0 : 1) +
      (countries.isEmpty ? 0 : 1) +
      (minRating > 0 ? 1 : 0) +
      (nearbyOn ? 1 : 0) +
      (routeId == null ? 0 : 1) +
      (sort == PoiSort.random ? 0 : 1);

  /// Krátký popis aktivního filtru pro hlavičku mapy („CZ · 🏰 · do 25 km").
  List<String> summary() {
    final out = <String>[];
    if (query.trim().isNotEmpty) out.add('„${query.trim()}"');
    if (countries.isNotEmpty) out.add(countries.join(', '));
    for (final c in kPoiCats) {
      if (cats.contains(c.key)) out.add(c.emoji);
    }
    if (nearbyOn) out.add('${nearbyKm.round()} km');
    if (minRating > 0) out.add('★ $minRating+');
    if (routeId != null) out.add('🗺️');
    if (sort != PoiSort.random) out.add('↕');
    return out;
  }
}

/// Přepnutí klíče v množině na místě — drobná pomůcka pro chipy.
extension ToggleKey on Set<String> {
  Set<String> toggleKey(String k) {
    contains(k) ? remove(k) : add(k);
    return this;
  }
}

class PlacesFilterNotifier extends Notifier<PlacesFilter> {
  @override
  PlacesFilter build() => const PlacesFilter();

  void set(PlacesFilter next) => state = next;
  void update(PlacesFilter Function(PlacesFilter) fn) => state = fn(state);
  void clear() => state = const PlacesFilter();

  void toggleCat(String key) {
    final next = {...state.cats};
    next.contains(key) ? next.remove(key) : next.add(key);
    state = state.copyWith(cats: next);
  }

  void toggleCountry(String iso) {
    final next = {...state.countries};
    next.contains(iso) ? next.remove(iso) : next.add(iso);
    state = state.copyWith(countries: next);
  }
}

final placesFilterProvider =
    NotifierProvider<PlacesFilterNotifier, PlacesFilter>(PlacesFilterNotifier.new);

/// Vybraná místa (klíče `PoiEntry.key`) — sdílená mezi seznamem a mapou, aby
/// se dala trasa poskládat z obojího.
class PlacesSelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String key) {
    final next = {...state};
    next.contains(key) ? next.remove(key) : next.add(key);
    state = next;
  }

  void addAll(Iterable<String> keys) => state = {...state, ...keys};
  void clear() => state = const {};
}

final placesSelectionProvider =
    NotifierProvider<PlacesSelectionNotifier, Set<String>>(
        PlacesSelectionNotifier.new);

/// Kotva pro filtr „v okolí": primárně poloha jezdce, jinak první vybrané
/// místo s GPS. Vrací null, když filtr není zapnutý nebo není od čeho měřit.
LatLng? nearbyAnchorFor(
  PlacesFilter f,
  List<PoiEntry> all,
  Set<String> selected, {
  LatLng? me,
}) {
  if (!f.nearbyOn) return null;
  if (me != null) return me;
  for (final k in selected) {
    for (final e in all) {
      if (e.key == k && e.latLng != null) return e.latLng;
    }
  }
  return null;
}

/// Jediná filtrovací a řadicí pipeline pro místa — používá ji seznam i mapa,
/// takže obě vždy ukazují stejnou množinu.
///
/// [base] je už sloučený (deduplikovaný) seznam, [all] slouží jen k dohledání
/// kotvy podle vybraných klíčů. [routeAnchor] je start naposledy zvolené trasy
/// pro řazení „od zvolené trasy".
List<PoiEntry> applyPlacesFilter(
  List<PoiEntry> base,
  PlacesFilter f, {
  required List<PoiEntry> all,
  required Set<String> selected,
  LatLng? me,
  LatLng? routeAnchor,
  LatLng? nearbyAnchor,
  int Function(PoiEntry)? stableOrder,
}) {
  const dist = Distance();
  final q = f.query.trim();

  // 1) Trasa + hledání.
  final sourceFiltered = base.where((e) {
    if (f.routeId != null && e.route?.id != f.routeId) return false;
    if (q.isEmpty) return true;
    return searchMatches(e.poi.searchBlob, q) ||
        (e.route != null && searchMatches(e.route!.nameBlob, q));
  }).toList();

  // 2) „V okolí" — vybraná místa zůstávají vidět vždy, ať uživateli nezmizí
  //    z rozdělané trasy.
  final anchor =
      nearbyAnchor ?? nearbyAnchorFor(f, all, selected, me: me);
  double distTo(LatLng from, PoiEntry e) => e.latLng == null
      ? double.infinity
      : dist.as(LengthUnit.Meter, from, e.latLng!);
  final nearFiltered = anchor == null
      ? sourceFiltered
      : sourceFiltered
          .where((e) =>
              selected.contains(e.key) ||
              (e.latLng != null && distTo(anchor, e) <= f.nearbyKm * 1000))
          .toList();

  // 3) Kategorie.
  var list = f.cats.isEmpty
      ? nearFiltered
      : nearFiltered.where((e) => f.cats.contains(poiCategoryOf(e.poi))).toList();

  // 4) Hodnocení + země.
  if (f.minRating > 0 || f.countries.isNotEmpty) {
    list = list.where((e) {
      if (f.minRating > 0 &&
          (e.poi.avgRating == null || e.poi.avgRating! < f.minRating)) {
        return false;
      }
      return e.matchesCountries(f.countries);
    }).toList();
  }
  // Pozn.: `list` je vždy čerstvá instance — `sourceFiltered` vzniklo přes
  // where().toList(), takže následné list.sort() nikdy nemutuje `base`
  // (a tím ani memoizovanou deduplikaci v seznamu Míst).

  // 5) Řazení — „v okolí" má přednost (nejbližší návrhy nahoru).
  if (anchor != null) {
    list.sort((a, b) => distTo(anchor, a).compareTo(distTo(anchor, b)));
  } else {
    switch (f.sort) {
      case PoiSort.random:
        if (stableOrder != null) {
          list.sort((a, b) => stableOrder(a).compareTo(stableOrder(b)));
        }
        break;
      case PoiSort.nearMe:
        if (me != null) {
          list.sort((a, b) => distTo(me, a).compareTo(distTo(me, b)));
        }
        break;
      case PoiSort.nearRoute:
        if (routeAnchor != null) {
          list.sort(
              (a, b) => distTo(routeAnchor, a).compareTo(distTo(routeAnchor, b)));
        }
        break;
    }
  }
  return list;
}

/// Trasy, které obsahují některé z [selectedKeys] míst.
///
/// Mapa míst ve výchozím stavu žádné trasy nekreslí — čáry se objeví teprve
/// po označení místa a jen u tras, které to místo mají mezi svými body.
/// Trasové body se poznají přímo podle id trasy v klíči; katalogová
/// a komunitní místa se párují podle polohy (do [tolerantM] metrů), protože
/// stejné fyzické místo je v katalogu i na trase pod jiným id.
List<RouteItem> routesContaining(
  List<RouteItem> routes,
  List<PoiEntry> shown,
  Set<String> selectedKeys, {
  double tolerantM = 600,
}) {
  if (selectedKeys.isEmpty) return const [];
  const dist = Distance();
  final picked = shown.where((e) => selectedKeys.contains(e.key)).toList();
  if (picked.isEmpty) return const [];
  final byRoute = picked.map((e) => e.route?.id).whereType<String>().toSet();
  final targets = picked.map((e) => e.latLng).whereType<LatLng>().toList();

  final out = <({RouteItem route, int hits})>[];
  for (final r in routes) {
    var hits = byRoute.contains(r.id) ? 1 : 0;
    for (final t in targets) {
      var near = false;
      for (final p in r.pois) {
        final pp = p.latLng;
        if (pp == null) continue;
        if (dist.as(LengthUnit.Meter, t, pp) <= tolerantM) {
          near = true;
          break;
        }
      }
      if (near) hits++;
    }
    if (hits > 0) out.add((route: r, hits: hits));
  }
  // Nejvíc sedící trasy první.
  out.sort((a, b) => b.hits.compareTo(a.hits));
  return out.map((e) => e.route).toList();
}

/// Čára trasy pro mapu — přednostně uložená geometrie, jinak aspoň zastávky.
List<LatLng> routeLine(RouteItem r) =>
    r.geometry.length >= 2 ? r.geometry : r.waypoints;

// ── Slučování duplicitních míst — sdílí seznam Míst i mapa míst, aby obě
// ukazovaly stejný počet a mapa nekreslila dva markery na jedno místo. ──

/// Normalizovaný název místa pro slučování duplicit — malá písmena, sloučené
/// mezery a bez vedoucího druhového slova (zámek/hrad/…), aby „Zámek Žirovnice"
/// a „zámek Žirovnice" (i „Zámek Kamenice nad Lipou" vs „Kamenice nad Lipou")
/// spadly na stejný klíč.
String _placeName(String raw) {
  var s = raw.trim().toLowerCase();
  const prefixes = [
    'zřícenina hradu ', 'zřícenina ', 'zámek ', 'hrad ', 'klášter ',
    'burgruine ', 'schloss ', 'burg ', 'château ', 'castle ',
  ];
  for (final p in prefixes) {
    if (s.startsWith(p)) {
      s = s.substring(p.length);
      break;
    }
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Sloučí body, které představují STEJNÉ fyzické místo (shodný normalizovaný
/// název + poloha v ~5 km rastru), do JEDNÉ položky. V katalogu „napříč
/// trasami" se tak místo ležící na více trasách (Kamenice nad Lipou, zámek
/// Žirovnice, Orlík…) ukáže jen jednou. Data tras se NEMĚNÍ — jde čistě o
/// zobrazení. Jako reprezentanta upřednostní bod s fotkou, pak katalogový.
/// Pořadí přednosti reprezentanta: bod s fotkou > katalogový > ostatní.
int _rank(PoiEntry e) =>
    (e.poi.cover != null ? 2 : 0) + (e.catalog ? 1 : 0);

List<PoiEntry> dedupPlaces(List<PoiEntry> src) {
  String bucket(double v) => (v / 0.05).round().toString();
  final index = <String, int>{};
  final out = <PoiEntry>[];
  for (final e in src) {
    final ll = e.latLng;
    // Body bez GPS nikdy neslučuj (nedají se spolehlivě ztotožnit).
    final key = ll == null
        ? 'id:${e.key}'
        : 'p:${_placeName(e.poi.name)}@${bucket(ll.latitude)},${bucket(ll.longitude)}';
    final at = index[key];
    if (at == null) {
      index[key] = out.length;
      out.add(e);
    } else {
      // Reprezentanta skupiny vybíráme DETERMINISTICKY — dřív rozhodovalo
      // pořadí vstupu, takže seznam (pseudonáhodně přeskládaný) a mapa
      // (přirozené pořadí) zvolily pro totéž místo jiný bod, a tím i jiný
      // klíč. Vybrané místo se pak na druhé obrazovce tvářilo jako nevybrané.
      final cur = out[at];
      if (_rank(e) > _rank(cur) ||
          (_rank(e) == _rank(cur) && e.key.compareTo(cur.key) < 0)) {
        out[at] = e;
      }
    }
  }
  return out;
}

/// Sloučená místa — JEDEN zdroj pro seznam i mapu, aby obě pracovaly se
/// stejnými klíči a sdílený výběr si odpovídal. Riverpod ho přepočítá jen
/// při změně zdrojů, ne při každém překreslení (dřív mapa dedupovala
/// desítky tisíc bodů při každém klepnutí na marker).
final dedupedPlacesProvider = Provider<List<PoiEntry>>(
    (ref) => dedupPlaces(ref.watch(allPlacesProvider)));

/// Dohledá body podle klíčů výběru. Hledá nejdřív ve sloučeném seznamu,
/// pak v úplném (klíč může pocházet z pohledu s filtrem na trasu, kde se
/// nededuplikuje), a výsledek zbaví opakování téhož bodu.
List<RoutePoi> resolveSelected(
  List<PoiEntry> deduped,
  List<PoiEntry> all,
  Set<String> keys,
) {
  if (keys.isEmpty) return const [];
  final byKey = <String, PoiEntry>{};
  for (final e in all) {
    byKey[e.key] = e;
  }
  for (final e in deduped) {
    byKey[e.key] = e;
  }
  final out = <RoutePoi>[];
  final seen = <String>{};
  for (final k in keys) {
    final e = byKey[k];
    if (e == null) continue;
    if (seen.add(e.poi.id)) out.add(e.poi);
  }
  return out;
}
