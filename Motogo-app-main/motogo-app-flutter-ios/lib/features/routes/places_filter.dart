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
  // SLOVENSKÉ tvary téhož — katalog vede slovenská místa česky i slovensky
  // („Bojnický zámek" × „Bojnický zámok", „Rozhľadňa Kloptaň" × „Kloptaň")
  // a seznam byl psaný jen česky, takže appka viděla dva různé názvy.
  // POZOR, co sem NEPATŘÍ: sakrální stavby (klastor, kostol, kaplnka)
  // a letiště. Po jejich odstranění zbude z názvu jen JMÉNO MĚSTA a slije
  // se, co nemá — změřeno: s „klastor" spadla „Synagoga v Malackách"
  // dohromady s „kláštor v Malackách", s anglickým „synagogue" dokonce
  // město „Wadowice" se svou synagogou.
  'zamok', 'zamocek', 'hradny', 'veza', 'rozhladna', 'vyhliadka',
  'vyhliadkova',
  // příroda
  'vrch', 'vrchol', 'hora', 'hory', 'kopec', 'sedlo', 'skala', 'skaly',
  'prehrada', 'prehradni', 'nadrz', 'rybnik', 'jezero', 'jezirko', 'vodopad',
  'jeskyne', 'jaskyna', 'propast', 'studanka', 'studna', 'pramen', 'prameny',
  'jaskyne', 'priepast', 'studnicka', 'pramene', 'jazero', 'jazierko',
  'priehrada', 'nadrze', 'vodopady',
  'park', 'rezervace', 'udoli', 'les', 'louka', 'louky',
  // spojky a předložky
  'a', 'i', 'na', 'nad', 'pod', 'u', 'v', 've', 'se', 's', 'z', 'ze', 'do',
  'the', 'of', 'in', 'and', 'der', 'die', 'das', 'von', 'bei', 'am',
};

/// Slova, která dvě jinak shodná jména ROZLIŠUJÍ. Když je jedno jméno
/// podmnožinou druhého jen o tohle, jde o dvě různá místa („Dračí štít"
/// vs. „Malý Dračí štít", „Nýznerovské vodopády I" vs. „… II").
const Set<String> _discriminators = {
  'maly', 'mala', 'male', 'velky', 'velka', 'velke', 'dolni', 'horni',
  'stary', 'stara', 'stare', 'novy', 'nova', 'nove', 'prvni', 'druhy',
  'horny', 'dolny', 'vychodni', 'zapadni', 'severni', 'jizni',
  'i', 'ii', 'iii', 'iv', 'v', 'vi',
};

/// Název bez diakritiky a interpunkce, malými písmeny, jedním oddělovačem.
///
/// POZOR na tabulky: `from` a `to` MUSÍ být stejně dlouhé a `to` se čte podle
/// indexu z `from`. Dřívější verze měla o jedno „s" navíc, takže se od indexu
/// 35 všechno posunulo a `ť` se překládalo na `s`, `ú` na `t`, `ý` na `u`
/// a `ž` na `y` („Žižkovo" → „yiykovo").
String _foldName(String raw) {
  const from = 'áäàâãåąăčćçďđéěèêëęėēíìîïīľĺłňñńóöòôõøőřŕšśşșťțúůüûűùūýÿžźż';
  const to = 'aaaaaaaacccddeeeeeeeeiiiiilllnnnooooooorrssssttuuuuuuuyyzzz';
  assert(from.length == to.length,
      'fold tabulky se rozešly — každý znak `from` musí mít protějšek v `to`');
  final b = StringBuffer();
  var space = true; // vedoucí mezery rovnou zahodíme
  for (final ch in raw.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    final ok = (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
        (c.compareTo('0') >= 0 && c.compareTo('9') <= 0);
    if (ok) {
      b.write(c);
      space = false;
    } else if (!space) {
      b.write(' ');
      space = true;
    }
  }
  final s = b.toString();
  return space && s.isNotEmpty ? s.substring(0, s.length - 1) : s;
}

/// Rozpad názvu na to, podle čeho se slučuje: normalizovaný název (bez
/// VEDOUCÍCH druhových slov) a množina významových slov. Fold se dělá JEDNOU
/// — dřív běžel dvakrát na každý bod, což je při 50 tis. bodech 100 tis.
/// průchodů znak po znaku.
({String name, Set<String> sig}) _nameKeys(String raw) {
  final folded = _foldName(raw);
  final parts = folded.isEmpty ? const <String>[] : folded.split(' ');
  var i = 0;
  while (i < parts.length - 1 && _genericWords.contains(parts[i])) {
    i++;
  }
  final all = <String>{};
  for (final w in parts) {
    if (w.length > 1) all.add(w);
  }
  final sig = all.difference(_genericWords);
  return (
    name: parts.isEmpty ? '' : parts.sublist(i).join(' '),
    sig: sig.isEmpty ? all : sig,
  );
}

/// Je jedna množina slov podmnožinou druhé? („Velký Blaník" ⊆ „Hradiště Velký
/// Blaník" → stejné místo.)
///
/// Obě množiny musí mít aspoň DVĚ slova: po vyhození druhových slov zbude
/// z „Obří hrad" i z „Obří zámek" jen „obri", a to jsou dvě různá místa
/// (hradiště a skalní útvar 18 m od sebe). Jednoslovné shody řeší pravidlo 1
/// přes normalizovaný název. A rozdíl nesmí být jen ROZLIŠUJÍCÍ slovo —
/// „Dračí štít" a „Malý Dračí štít" jsou dva různé vrcholy.
bool _subsetNames(Set<String> a, Set<String> b) {
  if (a.length < 2 || b.length < 2) return false;
  final small = a.length <= b.length ? a : b;
  final big = a.length <= b.length ? b : a;
  if (!big.containsAll(small)) return false;
  for (final w in big.difference(small)) {
    if (_discriminators.contains(w) || RegExp(r'^[0-9]+$').hasMatch(w)) {
      return false;
    }
  }
  return true;
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

/// Dva body prakticky na jednom místě — na mapě by to byl jeden špendlík
/// a v seznamu dva řádky téhož. Název se tu NEŘEŠÍ vůbec, a právě v tom je
/// síla pravidla: „Dukliansky priesmyk" × „Dukelský průsmyk", „Bezodná
/// ľadnica" × „Bezedná lednice" nebo „Diviačia priepasť" × „Kančí propast"
/// jsou dvojjazyčné zápisy TÉHOŽ místa a žádné pravidlo nad názvy je nikdy
/// nespojí — nesdílejí ani písmeno. Spojí je jedině poloha.
///
/// Proč 14 a ne 35 metrů: všech 513 katalogových dvojic do 35 m, jejichž
/// názvy spolu nijak nesouvisejí, bylo posouzeno kus po kuse. Podíl dvojic,
/// které jsou ve skutečnosti DVĚ RŮZNÁ místa, se láme kolem 14 m:
///     0,0–0,7 m  27 %      14,5–21,5 m  77 %
///     0,7–6,7 m  30 %      21,5–28,8 m  79 %
///     7,0–14,5 m 26 %      28,9–34,9 m  83 %
/// Nad tou hranicí tedy pravidlo slučovalo převážně různá místa (hrad
/// a vedlejší kostel, dva tatranské štíty, dvě synagogy) a mazalo je tím
/// z appky. Snížení na 14 m vrátí do seznamu a na mapu 275 míst a žádný
/// z kontrolních případů nerozbije (Sněžka × KNP i Macocha jsou na 0 m).
///
/// Pod 14 m zbývá ~27 % dvojic, které jsou taky dvě různá místa — těm
/// Wikidata daly stejné souřadnice („Šugovský vrch" × „Ďurkova skala",
/// „Stará" × „Nová synagoga v Liberci"). Ty vzdálenost nerozliší a pojistka
/// na druhové slovo v názvu (sedlo × štít, zámek × klášter) se NEOSVĚDČILA:
/// nad ručními štítky rozdělila 7 správných sloučení a jen 2 chybná,
/// protože věž patřící k hradu a klášter v zámeckém areálu jsou pro
/// uživatele jeden cíl. Zbytek je práce pro člověka ve Velíně (záložka
/// „Duplicitní místa", kde se řadí od nejbližších).
const double _kSamePlaceM = 14;

/// Shodný název = totéž místo, i když se souřadnice z různých zdrojů liší
/// o kilometry (tentýž zámek má u každé trasy trochu jinou značku; měřeno na
/// seedu: 90 % skupin do 53 m, ale Roštejn se u devíti tras liší o 4,8 km).
const double _kSameNameM = 5000;

/// Mezi KATALOGOVÝMI body ale platí přísný limit: katalog pochází z Wikidat
/// a má souřadnice na metry, takže dva stejně pojmenované body kilometry od
/// sebe jsou dva RŮZNÉ kopce („Ptačí vrch" je v Česku třikrát, 7 km od sebe).
const double _kSameNameCatalogM = 400;

/// Trasový bod × katalogový bod: volných 5 km je moc. Reprezentantem skupiny
/// se stane katalogový bod (má fotku) a skupina se kreslí na JEHO
/// souřadnicích — u 71 zastávek to znamenalo špendlík přes kilometr od
/// skutečné zastávky (hrad Landštejn 4 km). 1,5 km stačí: rozptyl souřadnic
/// téhož místa napříč trasami je v 90 % případů do 53 m.
const double _kSameNameMixedM = 1500;

/// Název jednoho je podmnožinou druhého („Hradiště Velký Blaník" ↔ „Velký Blaník").
const double _kSubsetNameM = 150;

/// Dvě místa TÉŽE kategorie prakticky na jednom bodě — rozhledna Pípalka
/// stojí na vrcholu Křemešník (64 m). Mezi dvěma katalogovými body platí
/// přísnějších 70 m, jinak by v každém historickém centru splynula celá
/// ulice (pět synagog na Kazimierzu je 22–84 m od sebe).
const double _kSameCatM = 120;
const double _kSameCatCatalogM = 70;

/// Dva KATALOGOVÉ body se shodným názvem, u kterých je jasné, že popisují
/// týž objekt — buď mají i STEJNOU KATEGORII, nebo se jmenují doslova
/// stejně. Přísných 400 m tu nestačí: „Lysá hora" je v katalogu jako vrchol
/// i jako přírodní rezervace 621 m od sebe a v seznamu i na mapě to byly dvě
/// položky (takových dvojic je 81). Naopak „Katedrála Uppsala" × „Hrad
/// Uppsala" (511 m, obojí normalizovaně „uppsala") tímhle NEPROJDE — jiná
/// kategorie i jiný doslovný název, takže zůstanou dvě různé památky.
const double _kSameNameCatalogSameCatM = 1200;

/// Kategorie, u kterých „stojí to na sobě" opravdu znamená „je to totéž":
/// rozhledna na vrcholu, zřícenina na kopci, přehrada a její jezero.
/// U památek, techniky, jídla a vojenských objektů je hustý shluk RŮZNÝCH
/// objektů normální stav (synagogy, kostely, muzea, řopíky v linii).
///
/// STUDÁNKY sem SCHVÁLNĚ nepatří, ačkoli by se to nabízelo: lázeňská
/// kolonáda má deset pojmenovaných pramenů vedle sebe (Karlovy Vary:
/// Rusalka, Libuše, Kníže Václav, Mlýnský pramen) a ty patří do seznamu
/// každý zvlášť. To, co je opravdu na jednom bodě, sloučí pravidlo 0
/// (do 35 m) — a tam se dvě jména na mapě stejně nevejdou.
const Set<String> _mergeableByCategory = {
  'lookout', 'castle', 'water', 'nature'
};

/// Dvojice kategorií, které o jednom bodě mluví jen jinými slovy. `nature`
/// je sběrná kategorie přírodních cílů, takže tentýž kopec je v katalogu
/// jednou jako vrchol (`lookout`) a podruhé jako přírodní rezervace
/// (`nature`) — přesně případ ze screenshotu uživatele: „Pípalka" (lookout)
/// a „Křemešník" (nature) 64 m od sebe. Hrady, památky ani technika tu
/// schválně nejsou: tam je hustý shluk RŮZNÝCH objektů normální stav.
const Set<String> _compatibleCats = {
  'nature|lookout', 'nature|water',
};

bool _catsMergeable(String a, String b) {
  if (!_mergeableByCategory.contains(a) || !_mergeableByCategory.contains(b)) {
    return false;
  }
  if (a == b) return true;
  return _compatibleCats.contains(a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a');
}

/// Kolik informací bod nese — fotka > katalogový > popis. První kritérium
/// výběru reprezentanta (celé pořadí je u `_pickRepresentative`), protože
/// právě tohle uživatel na kartě a na špendlíku uvidí.
int _rank(PoiEntry e) =>
    (e.poi.cover != null ? 4 : 0) +
    (e.catalog ? 2 : 0) +
    ((e.poi.description ?? '').trim().isNotEmpty ? 1 : 0);

/// Má název aspoň jedno VLASTNÍ slovo? Holá „Rozhledna" ani „studna" skupinu
/// nepojmenují — reprezentantem má být „Rozhledna Bohdanka".
bool _hasIdentity(String raw) {
  for (final w in _foldName(raw).split(' ')) {
    if (w.length > 1 && !_genericWords.contains(w)) return true;
  }
  return false;
}

/// Mluví ta dvě jména o TÉMŽE objektu? („Velký Blaník" × „rozhledna Velký
/// Blaník" × „Hradiště Velký Blaník" ano; „Sněžka" × „Krkonošský národní
/// park" ne — ty jen leží na jednom bodě.)
bool _relatedNames(
        ({String name, Set<String> sig}) a, ({String name, Set<String> sig}) b) =>
    (a.name.isNotEmpty && a.name == b.name) || _subsetNames(a.sig, b.sig);

/// Jak KONKRÉTNÍ je kategorie. Rozhoduje u bodů na jednom místě: na vrcholu
/// Sněžky leží wikidatový bod „Krkonošský národní park" s TOTOŽNÝMI
/// souřadnicemi — obojí má fotku i popis, takže bez tohohle kritéria
/// rozhodovala délka názvu a skupina se jmenovala po národním parku.
/// Sněžka tím z chipu „Rozhledny a vrcholy" zmizela hned poté, co ji tam
/// data doplnila; totéž potkalo Ještěd, Macochu i Karlštejn.
const Map<String, int> _catSpecificity = {
  'lookout': 3, 'castle': 3, 'spring': 3, 'military': 3, 'aviation': 3,
  'moto': 3, 'water': 2, 'tech': 2, 'food': 2, 'sights': 1,
  'nature': 0, 'other': 0,
};

/// Jméno, pod kterým se sloučená skupina ukáže.
///
/// Rozhoduje se AŽ NAD CELOU skupinou, ne postupně při přidávání — bez
/// znalosti ostatních členů nejde poznat, které jméno je to SPOLEČNÉ:
/// u Macochy („Macocha", „Propast Macocha", „Horní macošské jezírko")
/// mluví o témže dva členy ze tří a právě jejich jméno má skupinu zastupovat.
///
/// Pořadí kritérií:
///   1. víc informací (fotka > katalogový > popis) — to je, co uvidí uživatel,
///   2. jméno musí mít vlastní slovo (holá „Rozhledna" nikdy),
///   3. CENTRALITA — o kolika RŮZNÝCH jménech ve skupině to jméno mluví,
///   4. u NESOUVISEJÍCÍCH jmen konkrétnější kategorie (vrchol > národní park),
///   5. kratší normalizované jméno („Hrad Karlštejn" → „karlstejn" je kratší
///      než „Mariánská věž" → „marianska vez"), pak kratší původní
///      („Velký Blaník" před „rozhledna Velký Blaník"),
///   6. klíč — aby byl výsledek deterministický.
///
/// Kritérium 4 se ptá na dvojici (souvisí ta jména?), takže porovnání není
/// úplné uspořádání a výsledek závisí na pořadí členů. To je v pořádku:
/// vstup `dedupPlaces` si srovnává sám, takže pořadí je dané daty, ne tím,
/// jak je zrovna vrátil Postgres.
PoiEntry _pickRepresentative(List<PoiEntry> members) {
  if (members.length == 1) return members.first;
  final keys = [for (final m in members) _nameKeys(m.poi.name)];
  final ident = [for (final m in members) _hasIdentity(m.poi.name)];
  // Centralita se počítá přes RŮZNÁ jména, ne přes členy: jinak vyhraje to,
  // které je v katalogu dvakrát — na vrcholu Sněžky leží „Krkonošský národní
  // park" hned ve dvou řádcích a Sněžka by z chipu vypadla znovu.
  final firstOf = <String, int>{};
  for (var i = 0; i < members.length; i++) {
    firstOf.putIfAbsent(members[i].poi.name, () => i);
  }
  final central = List<int>.filled(members.length, 0);
  for (var i = 0; i < members.length; i++) {
    for (final j in firstOf.values) {
      if (_relatedNames(keys[i], keys[j])) central[i]++;
    }
  }

  bool better(int a, int b) {
    final ra = _rank(members[a]), rb = _rank(members[b]);
    if (ra != rb) return ra > rb;
    if (ident[a] != ident[b]) return ident[a];
    if (central[a] != central[b]) return central[a] > central[b];
    if (!_relatedNames(keys[a], keys[b])) {
      final sa = _catSpecificity[poiCategoryOf(members[a].poi)] ?? 0;
      final sb = _catSpecificity[poiCategoryOf(members[b].poi)] ?? 0;
      if (sa != sb) return sa > sb;
    }
    if (keys[a].name.length != keys[b].name.length) {
      return keys[a].name.length < keys[b].name.length;
    }
    final la = members[a].poi.name.trim().length;
    final lb = members[b].poi.name.trim().length;
    if (la != lb) return la < lb;
    return members[a].key.compareTo(members[b].key) < 0;
  }

  var best = 0;
  for (var i = 1; i < members.length; i++) {
    if (better(i, best)) best = i;
  }
  return members[best];
}

/// Sloučí body, které představují STEJNÉ fyzické místo, do JEDNÉ položky.
///
/// Pravidla (od nejjistějšího k nejvolnějšímu), vždy proti NEJBLIŽŠÍMU členu
/// skupiny (ne jen proti prvnímu — „Hradiště Velký Blaník" je 133 m od jednoho
/// člena, ale 429 m od toho, kdo skupinu založil):
///   0. do 35 m — jeden bod na mapě, ať se jmenuje jakkoli,
///   1. shodný normalizovaný název do 5 km (mezi katalogovými do 400 m) —
///      místo ležící na dvaceti trasách se ukáže jednou,
///   2. významová slova jednoho názvu jsou podmnožinou druhého do 150 m,
///   3. mezi KATALOGOVÝMI shodný název + shodná kategorie (nebo doslova
///      shodný název) do 1,2 km — tentýž kopec vedený jednou jako vrchol
///      a podruhé jako rezervace,
///   4. slučitelná (nebo příbuzná) kategorie do 120 m, mezi katalogovými
///      do 70 m.
/// Skupina se navíc nesmí roztáhnout přes limit pravidla, které ji drží
/// pohromadě, takže se řetězením nespojí půl kraje.
///
/// Data tras se NEMĚNÍ — jde čistě o zobrazení. Reprezentanta vybírá
/// `_pickRepresentative` DETERMINISTICKY nad celou skupinou a vstup se před
/// slučováním srovná, aby seznam i mapa ukázaly tentýž klíč bez ohledu na
/// pořadí, v jakém data dorazila z DB.
List<PoiEntry> dedupPlaces(List<PoiEntry> src) {
  const cellDeg = 0.0025; // ~278 m na výšku; na šířku se okno dopočítá dle zeměpisné šířky

  // Katalogové body (souřadnice na metry) zakládají skupiny jako první —
  // `get_pois_catalog()` nemá ORDER BY, takže bez tohohle srovnání by se
  // výsledek měnil podle toho, jak zrovna Postgres vrátil řádky.
  final ordered = List<PoiEntry>.of(src)
    ..sort((a, b) {
      final pa = a.catalog ? 0 : (a.route == null ? 2 : 1);
      final pb = b.catalog ? 0 : (b.route == null ? 2 : 1);
      return pa != pb ? pa - pb : a.key.compareTo(b.key);
    });

  final out = <PoiEntry>[];
  final gPts = <List<LatLng>>[];
  final gSig = <List<Set<String>>>[];
  final gCat = <List<String>>[];
  final gCatalog = <bool>[];
  final gOnRoute = <bool>[];
  final gNames = <List<String>>[];   // normalizované názvy (rejstřík)
  final gMemName = <List<String>>[]; // normalizovaný název PO ČLENECH
  final gRaw = <List<String>>[];     // původní názvy (aliasy pro hledání)
  final gMem = <List<PoiEntry>>[];   // členové skupiny (výběr reprezentanta)
  final byName = <Object, List<int>>{};
  final byCell = <Object, List<int>>{};

  void index(Map<Object, List<int>> m, Object k, int g) {
    final l = m[k] ??= <int>[];
    if (!l.contains(g)) l.add(g);
  }

  for (final e in ordered) {
    final ll = e.latLng;
    final keys = _nameKeys(e.poi.name);
    final name = keys.name;
    final sig = keys.sig;
    final cat = poiCategoryOf(e.poi);
    var at = -1;

    if (ll != null) {
      // Kandidátní skupiny: podle názvu (pravidlo 1) a z okolních buněk.
      // Na šířku je buňka jen `cellDeg * cos(lat)` široká, takže nad ~57° by
      // okno 3×3 přestalo stačit — počet sloupců se proto dopočítá.
      final gy = (ll.latitude / cellDeg).floor();
      final gx = (ll.longitude / cellDeg).floor();
      final rx = (1 / math.max(math.cos(ll.latitude * math.pi / 180), 0.05))
          .ceil()
          .clamp(1, 8)
          .toInt();
      final seen = <int>{};
      final cands = <int>[];
      void addAll(List<int>? l) {
        if (l == null) return;
        for (final g in l) {
          if (seen.add(g)) cands.add(g);
        }
      }

      if (name.isNotEmpty) addAll(byName[name]);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -rx; dx <= rx; dx++) {
          addAll(byCell[(gy + dy) * 4194304 + (gx + dx)]);
        }
      }

      // Ze VŠECH vyhovujících skupin se bere ta NEJBLIŽŠÍ. Kdyby se brala
      // první nalezená, spadl by trasový bod „Hrad Karlštejn" do skupiny
      // stejnojmenné VESNICE 3,3 km daleko jen proto, že ta skupina vznikla
      // dřív — a hrad by ze seznamu zmizel.
      var best = double.infinity;
      for (final g in cands) {
        // Vzdálenost k nejbližšímu i nejvzdálenějšímu členu skupiny.
        var near = double.infinity, far = 0.0;
        var nearIdx = 0;
        final pts = gPts[g];
        for (var i = 0; i < pts.length; i++) {
          final d = _metersApart(pts[i], ll);
          if (d < near) {
            near = d;
            nearIdx = i;
          }
          if (d > far) far = d;
        }
        if (near >= best) continue;

        final bothCatalog = e.catalog && gCatalog[g];
        final nameLimit = bothCatalog
            ? _kSameNameCatalogM
            : (e.catalog || gCatalog[g])
                ? _kSameNameMixedM
                : _kSameNameM;
        final catLimit = bothCatalog ? _kSameCatCatalogM : _kSameCatM;
        // `far` = průměr skupiny po přidání bodu; drží ji pohromadě, aby se
        // řetězením nespojil půl kraje.
        // Týž katalogový objekt pod dvěma záznamy: shodný název A kategorie,
        // nebo doslova shodný název. Prochází se po ČLENECH, protože
        // stejnojmenný člen nemusí být ten nejbližší.
        bool sameObject() {
          if (!bothCatalog || far > _kSameNameCatalogSameCatM) return false;
          final names = gMemName[g], cats = gCat[g], raws = gRaw[g];
          for (var i = 0; i < names.length; i++) {
            if (name.isNotEmpty && names[i] == name && cats[i] == cat) {
              return true;
            }
            if (raws[i] == e.poi.name) return true;
          }
          return false;
        }

        final match = near <= _kSamePlaceM
            || (name.isNotEmpty && far <= nameLimit && gNames[g].contains(name))
            || sameObject()
            || (far <= _kSubsetNameM && _subsetNames(sig, gSig[g][nearIdx]))
            || (far <= catLimit && _catsMergeable(cat, gCat[g][nearIdx]));
        if (match) {
          at = g;
          best = near;
        }
      }
    }

    if (at < 0) {
      // Bod bez GPS nikdy neslučujeme (nedá se spolehlivě ztotožnit) — dostane
      // vlastní skupinu a do rejstříků se nezapíše.
      final g = out.length;
      out.add(e);
      gPts.add(ll == null ? <LatLng>[] : <LatLng>[ll]);
      gSig.add(<Set<String>>[sig]);
      gCat.add(<String>[cat]);
      gNames.add(<String>[name]);
      gMemName.add(<String>[name]);
      gRaw.add(<String>[e.poi.name]);
      gMem.add(<PoiEntry>[e]);
      gCatalog.add(e.catalog);
      gOnRoute.add(e.onRoute);
      if (ll != null) {
        if (name.isNotEmpty) index(byName, name, g);
        index(byCell, (ll.latitude / cellDeg).floor() * 4194304 +
            (ll.longitude / cellDeg).floor(), g);
      }
    } else {
      // Do skupiny se přidává jen bod se souřadnicemi — `at >= 0` může nastat
      // pouze uvnitř větve `ll != null` výš.
      final p = ll!;
      gPts[at].add(p);
      gSig[at].add(sig);
      gCat[at].add(cat);
      if (!gNames[at].contains(name)) gNames[at].add(name);
      gMemName[at].add(name);
      gRaw[at].add(e.poi.name);
      gMem[at].add(e);
      gCatalog[at] = gCatalog[at] || e.catalog;
      gOnRoute[at] = gOnRoute[at] || e.onRoute;
      // Skupina musí být dohledatelná i podle názvu a buňky PŘIDANÉHO bodu,
      // jinak další stejnojmenné místo založí druhou skupinu na témže místě.
      if (name.isNotEmpty) index(byName, name, at);
      index(byCell, (p.latitude / cellDeg).floor() * 4194304 +
          (p.longitude / cellDeg).floor(), at);
    }
  }

  for (var i = 0; i < out.length; i++) {
    if (gMem[i].length > 1) out[i] = _pickRepresentative(gMem[i]);
    final onRoute = gOnRoute[i] && !out[i].onRoute ? true : null;
    // Aliasy jen tam, kde se opravdu něco slilo a název se liší od toho,
    // který ve skupině zvítězil — jinak by hledání na „Pípalka" po sloučení
    // do „Křemešníku" nenašlo nic.
    final rep = out[i].poi.name;
    final others = <String>{};
    for (final n in gRaw[i]) {
      if (n != rep) others.add(n);
    }
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
