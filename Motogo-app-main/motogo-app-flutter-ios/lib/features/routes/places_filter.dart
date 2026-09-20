import 'dart:math' as math;

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
    this.sort = PoiSort.nearMe,
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
      // Výchozí řazení je „od mé polohy" (viz PlacesFilter()), takže se
      // NEPOČÍTÁ jako zapnutý filtr — jinak by odznak i tlačítko „Zrušit
      // filtry" svítily hned po otevření Míst, kde uživatel nic nenastavil.
      (sort == PoiSort.nearMe ? 0 : 1);

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
    if (sort != PoiSort.nearMe) out.add('↕');
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
  /// false = výsledek se NEŘADÍ (volající ho použije jen na počty kategorií).
  /// Řazení podle vzdálenosti nad desítkami tisíc bodů není zadarmo, a pro
  /// počty je pořadí k ničemu.
  bool ordered = true,
}) {
  const dist = Distance();
  final q = f.query.trim();

  // 1) Trasa + hledání.
  final sourceFiltered = base.where((e) {
    if (f.routeId != null && e.route?.id != f.routeId) return false;
    if (q.isEmpty) return true;
    return searchMatches(e.poi.searchBlob, q) ||
        (e.aliasBlob != null && searchMatches(e.aliasBlob!, q)) ||
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

  if (!ordered) return list;

  // 5) Řazení — „v okolí" má přednost (nejbližší návrhy nahoru).
  final from = anchor ??
      switch (f.sort) {
        PoiSort.nearMe => me,
        PoiSort.nearRoute => routeAnchor,
        PoiSort.random => null,
      };
  if (from != null) {
    sortByDistance(list, from);
  } else if (stableOrder != null) {
    // Bez kotvy (např. výchozí „od mé polohy" ještě bez povolené polohy)
    // se pořadí drží stabilně náhodné — jinak by se seznam přeskládal
    // pokaždé, když doběhne další zdroj bodů.
    list.sort((a, b) => stableOrder(a).compareTo(stableOrder(b)));
  }
  return list;
}

/// Seřadí místa podle vzdálenosti od [from] — vzdálenost se počítá JEDNOU
/// na bod (decorate–sort–undecorate). Naivní `sort` s výpočtem uvnitř
/// porovnání dělal nad katalogem desítek tisíc bodů miliony haversinů při
/// každém překreslení a seznam Míst kvůli tomu sekal.
void sortByDistance(List<PoiEntry> list, LatLng from) {
  const dist = Distance();
  final decorated = <({PoiEntry e, double d})>[
    for (final e in list)
      (
        e: e,
        d: e.latLng == null
            ? double.infinity
            : dist.as(LengthUnit.Meter, from, e.latLng!)
      ),
  ];
  decorated.sort((a, b) => a.d.compareTo(b.d));
  for (var i = 0; i < decorated.length; i++) {
    list[i] = decorated[i].e;
  }
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

/// Obecná (druhová) slova v názvech míst. O KONKRÉTNÍM místě neříkají nic, a
/// tak se zahazují jak ze začátku názvu, tak z množiny významových slov —
/// jinak „Hrad Křivoklát" a „Křivoklát" nebo „Rozhledna a televizní vysílač
/// Praděd" a „Praděd — vysílač a rozhledna" vypadají jako dvě různá místa.
const Set<String> _genericWords = {
  // stavby
  'hrad', 'hradu', 'hradby', 'zamek', 'zamku', 'zamecek', 'zricenina',
  'zriceniny', 'tvrz', 'pevnost', 'klaster', 'klastera', 'kostel', 'kostela',
  'kostelik', 'kaple', 'kaplicka', 'bazilika', 'katedrala', 'synagoga',
  'rozhledna', 'rozhledny', 'vyhlidka', 'vyhlidkova', 'vez', 'veze', 'vysilac',
  'muzeum', 'muzea', 'pamatnik', 'pomnik', 'skanzen', 'mlyn', 'mlyna',
  'burg', 'burgruine', 'schloss', 'castle', 'chateau', 'ruine', 'tower',
  // příroda
  'vrch', 'vrchol', 'hora', 'hory', 'kopec', 'sedlo', 'skala', 'skaly',
  'prehrada', 'prehradni', 'nadrz', 'rybnik', 'jezero', 'jezirko', 'vodopad',
  'jeskyne', 'jaskyna', 'propast', 'studanka', 'studna', 'pramen', 'prameny',
  'park', 'rezervace', 'udoli', 'les', 'louka', 'louky',
  // spojky a předložky
  'a', 'i', 'na', 'nad', 'pod', 'u', 'v', 've', 'se', 's', 'z', 'ze', 'do',
  'the', 'of', 'in', 'and', 'der', 'die', 'das', 'von', 'bei', 'am',
};

/// Název bez diakritiky a interpunkce, malými písmeny, jedním oddělovačem.
String _foldName(String raw) {
  const from = 'áäàâãåčćçďđéěèêëíìîïľĺłňñóöòôõøřšśşťúůüûýÿžźż';
  const to = 'aaaaaacccddeeeeeiiiilllnnoooooorsssstuuuuyyzzz';
  final b = StringBuffer();
  for (final ch in raw.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    final ok = (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0);
    b.write(ok ? c : ' ');
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Normalizovaný název místa pro slučování duplicit — bez diakritiky a bez
/// VEDOUCÍCH druhových slov, aby „Zámek Žirovnice" a „zámek Žirovnice"
/// (i „Zřícenina hradu Kumburk" vs „Kumburk") spadly na stejný klíč.
String _placeName(String raw) {
  final parts = _foldName(raw).split(' ');
  var i = 0;
  while (i < parts.length - 1 && _genericWords.contains(parts[i])) {
    i++;
  }
  return parts.sublist(i).join(' ');
}

/// Významová slova názvu (bez druhových a spojovacích). Když by nezbylo nic,
/// vrátí se všechna slova — jinak by „Kaple" odpovídala čemukoli.
Set<String> _sigWords(String raw) {
  final all = _foldName(raw).split(' ').where((w) => w.length > 1).toSet();
  final sig = all.difference(_genericWords);
  return sig.isEmpty ? all : sig;
}

/// Je jedna množina slov podmnožinou druhé? („Velký Blaník" ⊆ „Hradiště Velký
/// Blaník" → stejné místo.)
///
/// Jedno jediné společné slovo NESTAČÍ, pokud množiny nejsou shodné: po
/// vyhození druhových slov zbude z „Oświęcim Castle" jen „oswiecim", což je
/// podmnožina každé jiné pamětihodnosti v tomtéž městě — hrad by se slil se
/// synagogou. Proto: buď jsou množiny shodné, nebo mají obě aspoň dvě slova.
bool _subsetNames(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return false;
  final sub = a.length <= b.length ? b.containsAll(a) : a.containsAll(b);
  if (!sub) return false;
  return a.length == b.length || (a.length >= 2 && b.length >= 2);
}

/// Vzdálenost v metrech — rovinná aproximace. Katalog má desítky tisíc bodů
/// a počítá se tu statisíce vzdáleností; přesnost na metry bohatě stačí
/// a je to řádově rychlejší než haversine z `Distance()`.
double _metersApart(LatLng a, LatLng b) {
  const mPerDeg = 111320.0;
  final dy = (a.latitude - b.latitude) * mPerDeg;
  final dx = (a.longitude - b.longitude) *
      mPerDeg *
      math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

/// Shodný název = totéž místo, i když se souřadnice z různých zdrojů liší
/// o kilometry (tentýž zámek má u každé trasy trochu jinou značku; měřeno na
/// seedu: 90 % skupin do 53 m, ale Roštejn se u devíti tras liší o 4,8 km).
const double _kSameNameM = 5000;

/// Mezi DVĚMA katalogovými body ale platí přísný limit: katalog pochází
/// z Wikidat a má souřadnice na metry, takže dva stejně pojmenované body
/// kilometry od sebe jsou dva RŮZNÉ kopce („Ptačí vrch" je v Česku třikrát,
/// 7 km od sebe; „Holý vrch", „Komáří vrch"… stejně tak). Volný limit by je
/// slil do jednoho a významné kopce by ze seznamu zmizely.
const double _kSameNameCatalogM = 400;

/// Název jednoho je podmnožinou druhého („Hrad Křivoklát" ↔ „Křivoklát").
const double _kSubsetNameM = 150;

/// Dvě místa TÉŽE kategorie prakticky na jednom bodě — rozhledna Pípalka
/// stojí na vrcholu Křemešník (64 m), v seznamu i na mapě to musí být
/// JEDNO místo, ne dvě položky přes sebe.
const double _kSameCatM = 120;

/// Pořadí přednosti reprezentanta skupiny: bod s fotkou > katalogový >
/// s popisem > s konkrétnějším (delším) názvem > nejmenší klíč.
int _rank(PoiEntry e) =>
    (e.poi.cover != null ? 4 : 0) +
    (e.catalog ? 2 : 0) +
    ((e.poi.description ?? '').trim().isNotEmpty ? 1 : 0);

bool _better(PoiEntry a, PoiEntry b) {
  final ra = _rank(a), rb = _rank(b);
  if (ra != rb) return ra > rb;
  final la = a.poi.name.trim().length, lb = b.poi.name.trim().length;
  if (la != lb) return la > lb;
  return a.key.compareTo(b.key) < 0;
}

/// Sloučí body, které představují STEJNÉ fyzické místo, do JEDNÉ položky.
///
/// Slučuje se ve třech krocích (od nejjistějšího k nejvolnějšímu):
///   1. shodný normalizovaný název do 5 km — místo ležící na dvaceti trasách
///      („Čermákovy louky" je jako `route_poi` u 20 tras) se ukáže jednou,
///   2. název jednoho je podmnožinou druhého do 150 m,
///   3. stejná kategorie do 120 m — dva zápisy téhož kopce/rozhledny.
///
/// Data tras se NEMĚNÍ — jde čistě o zobrazení. Skupina se drží kolem prvního
/// bodu (kotvy), takže se řetězením nespojí půl kraje; reprezentanta vybírá
/// `_better` DETERMINISTICKY, aby seznam i mapa ukázaly tentýž klíč.
List<PoiEntry> dedupPlaces(List<PoiEntry> src) {
  const cellDeg = 0.0025; // ~278 m — na pravidla 2 a 3 stačí okolí 3×3
  final out = <PoiEntry>[];
  final anchor = <LatLng?>[]; // kotva skupiny (první viděný bod)
  final aSig = <Set<String>>[];
  final aCat = <String>[];
  final aCatalog = <bool>[];
  final onRouteOf = <bool>[];
  final byName = <String, List<int>>{}; // normalizovaný název → skupiny
  final byCell = <String, List<int>>{}; // buňka rastru → skupiny
  final namesOf = <List<String>>[];     // všechny názvy ve skupině (aliasy)

  String cellKey(int gy, int gx) => '$gy,$gx';

  for (final e in src) {
    final ll = e.latLng;
    final name = _placeName(e.poi.name);
    var at = -1;

    if (ll == null) {
      // Body bez GPS nikdy neslučuj (nedají se spolehlivě ztotožnit).
      at = -1;
    } else {
      // 1) shodný název do 5 km
      for (final g in name.isEmpty ? const <int>[] : (byName[name] ?? const <int>[])) {
        final a = anchor[g];
        final limit = (e.catalog && aCatalog[g])
            ? _kSameNameCatalogM
            : _kSameNameM;
        if (a != null && _metersApart(a, ll) <= limit) {
          at = g;
          break;
        }
      }
      if (at < 0) {
        // 2) + 3) blízké body v okolí 3×3 buněk
        final sig = _sigWords(e.poi.name);
        final cat = poiCategoryOf(e.poi);
        final gy = (ll.latitude / cellDeg).floor();
        final gx = (ll.longitude / cellDeg).floor();
        outer:
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            for (final g in byCell[cellKey(gy + dy, gx + dx)] ?? const <int>[]) {
              final a = anchor[g];
              if (a == null) continue;
              final d = _metersApart(a, ll);
              if (d <= _kSubsetNameM && _subsetNames(sig, aSig[g])) {
                at = g;
                break outer;
              }
              if (d <= _kSameCatM && cat == aCat[g]) {
                at = g;
                break outer;
              }
            }
          }
        }
      }
    }

    if (at < 0) {
      final g = out.length;
      out.add(e);
      anchor.add(ll);
      aSig.add(_sigWords(e.poi.name));
      aCat.add(poiCategoryOf(e.poi));
      aCatalog.add(e.catalog);
      onRouteOf.add(e.onRoute);
      namesOf.add(<String>[e.poi.name]);
      if (ll != null) {
        if (name.isNotEmpty) (byName[name] ??= <int>[]).add(g);
        (byCell[cellKey((ll.latitude / cellDeg).floor(),
                (ll.longitude / cellDeg).floor())] ??= <int>[])
            .add(g);
      }
    } else {
      onRouteOf[at] = onRouteOf[at] || e.onRoute;
      namesOf[at].add(e.poi.name);
      if (_better(e, out[at])) out[at] = e;
    }
  }

  for (var i = 0; i < out.length; i++) {
    final onRoute = onRouteOf[i] && !out[i].onRoute ? true : null;
    // Aliasy jen tam, kde se opravdu něco slilo a název se liší od toho,
    // který ve skupině zvítězil.
    final rep = out[i].poi.name;
    final others =
        namesOf[i].where((n) => n != rep).toSet().toList(growable: false);
    if (onRoute == null && others.isEmpty) continue;
    out[i] = out[i].copyWith(
      onRoute: onRoute,
      aliasBlob: others.isEmpty ? null : searchNorm(others.join(' ')),
    );
  }
  return out;
}

/// Jen místa, která leží na některé trase — základ pro MAPU TRAS.
List<PoiEntry> onlyRoutePlaces(List<PoiEntry> src) =>
    [for (final e in src) if (e.onRoute) e];

/// Sloučená místa — JEDEN zdroj pro seznam i mapu, aby obě pracovaly se
/// stejnými klíči a sdílený výběr si odpovídal. Riverpod ho přepočítá jen
/// při změně zdrojů, ne při každém překreslení (dřív mapa dedupovala
/// desítky tisíc bodů při každém klepnutí na marker).
final dedupedPlacesProvider = Provider<List<PoiEntry>>(
    (ref) => dedupPlaces(ref.watch(allPlacesProvider)));

/// Sloučená místa LEŽÍCÍ NA TRASE — zdroj pro mapu tras (uživatel na ní chce
/// vidět jen body tras, ne celý katalog 37 tis. míst).
final dedupedRoutePlacesProvider = Provider<List<PoiEntry>>(
    (ref) => onlyRoutePlaces(ref.watch(dedupedPlacesProvider)));

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

/// Okno sousedů kolem vybrané položky pro listování v detailu.
///
/// Předávat do detailu celý vyfiltrovaný katalog (desítky tisíc míst) nemá
/// smysl — nikdo jím neprolistuje a je to zbytečná alokace při každém otevření.
/// Vrátí se proto jen [radius] položek na každou stranu.
List<T> siblingWindow<T>(List<T> all, int at, {int radius = 150}) {
  if (all.length <= radius * 2 + 1) return all;
  var from = at - radius;
  var to = at + radius + 1;
  if (from < 0) {
    to -= from;
    from = 0;
  }
  if (to > all.length) {
    from -= to - all.length;
    to = all.length;
  }
  return all.sublist(from < 0 ? 0 : from, to);
}
