import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'poi_categories.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'route_poi_sheet.dart';

/// Řazení seznamu bodů zájmu. (Délka/čas se u samostatných bodů neuplatní —
/// smysluplné je náhodně, od polohy a od zvolené trasy.)
enum _PoiSort { random, nearMe, nearRoute }

/// Katalog VŠECH bodů zájmu napříč trasami. Trasa je jen doporučení — tady si
/// zákazník vybere zastávky z různých tras (i ze dvou tras najednou) a sestaví
/// si vlastní vyjížďku, kterou pak naviguje přímo v appce.
class AllPoisScreen extends ConsumerStatefulWidget {
  /// Předvybrané body (klíče `routeId:poiId`) — např. „uprav tuto trasu".
  final Set<String>? initialSelected;
  /// Režim výběru pro editor trasy: spodní tlačítko vrátí vybrané body
  /// (Navigator.pop) místo přechodu na sestavení/navigaci.
  final bool pickMode;
  const AllPoisScreen({super.key, this.initialSelected, this.pickMode = false});

  @override
  ConsumerState<AllPoisScreen> createState() => _AllPoisScreenState();
}

class _AllPoisScreenState extends ConsumerState<AllPoisScreen> {
  final Set<String> _selected = {};
  String _query = '';
  String? _routeFilter; // null = všechny body, jinak id konkrétní zvolené trasy
  final Set<String> _cats = {}; // aktivní kategorie (prázdné = všechny)
  final Set<String> _precachedUrls = {}; // náhledy už poslané do precache

  // Debounce vyhledávání — filtr běží nad desítkami tisíc bodů, takže
  // přefiltrovat při KAŽDÉM stisku klávesy sekalo. Přefiltruje se až po
  // krátké pauze v psaní; napsaný text v poli zůstává responzivní hned.
  Timer? _searchDebounce;

  // Filtr „v okolí výběru" — nabídne další body do X km od PRVNÍHO vybraného
  // bodu (stabilní kotva, aby se okruh s přibývajícím výběrem nerozrůstal).
  bool _nearbyOn = false;
  double _nearbyKm = 10;
  static const List<double> _nearbyKmOptions = [5, 10, 25, 50];

  // Řazení + rozšířené filtry (kombinovatelné se zdrojem/kategorií/„v okolí").
  _PoiSort _sort = _PoiSort.random;
  final Set<String> _fCountry = {}; // ISO kódy zemí (z tras bodů)
  double _minRating = 0; // 0 = bez omezení, jinak minimální průměr hvězd
  bool _onlyPhoto = false; // jen body s fotkou

  int get _extraFilterCount =>
      (_fCountry.isEmpty ? 0 : 1) + (_minRating > 0 ? 1 : 0) + (_onlyPhoto ? 1 : 0);

  void _clearTools() => setState(() {
        _sort = _PoiSort.random;
        _fCountry.clear();
        _minRating = 0;
        _onlyPhoto = false;
      });

  // Náhodné pořadí bodů — losuje se jen JEDNOU za běh appky (static), takže se
  // nemění při návratu na obrazovku; nové promíchání až po restartu appky.
  // Použije se, když není známá poloha; se známou polohou vyhrává vzdálenost.
  static final int _shuffleSeed = Random().nextInt(0x7fffffff);

  @override
  void initState() {
    super.initState();
    if (widget.initialSelected != null) _selected.addAll(widget.initialSelected!);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Stabilní pseudonáhodné pořadí bodu (nezávislé na tom, kdy dorazí který
  /// zdroj) — seznam se pak při postupném načítání zdrojů nepřeskládává.
  int _stableOrder(PoiEntry e) => (e.key.hashCode ^ _shuffleSeed) & 0x7fffffff;

  // Memoizace sloučeného seznamu bodů. Sloučit tři zdroje (~desítky tisíc
  // katalogových bodů) a stabilně je seřadit je O(n log n) — bez cache by se to
  // dělo při KAŽDÉM build() (i při každém setState z hledání/filtrů) a obrazovka
  // by „zamrzala" už při otevření i při psaní. Přepočítá se jen když se některý
  // zdroj (referenčně) změní — providery vrací stejné instance, dokud se nezmění
  // data, takže identical() spolehlivě rozliší „nové načtení" od překreslení.
  List<PoiEntry>? _mergedCache;
  List<PoiEntry>? _mergedRouteSrc;
  List<RoutePoi>? _mergedCatalogSrc;
  List<RoutePoi>? _mergedUserSrc;

  List<PoiEntry> _mergedAll(List<PoiEntry> routePois,
      List<RoutePoi> catalogPois, List<RoutePoi> userPois) {
    if (_mergedCache != null &&
        identical(_mergedRouteSrc, routePois) &&
        identical(_mergedCatalogSrc, catalogPois) &&
        identical(_mergedUserSrc, userPois)) {
      return _mergedCache!;
    }
    final merged = <PoiEntry>[
      ...routePois,
      ...catalogPois.map((p) => PoiEntry(p, null, null, catalog: true)),
      ...userPois.map((p) => PoiEntry(p, null, null)),
    ]..sort((a, b) => _stableOrder(a).compareTo(_stableOrder(b)));
    _mergedCache = merged;
    _mergedRouteSrc = routePois;
    _mergedCatalogSrc = catalogPois;
    _mergedUserSrc = userPois;
    return merged;
  }

  // Memoizace sloučeného (deduplikovaného) seznamu pro pohled „vše" — stejně
  // jako _mergedAll běží jen když se zdrojový seznam (referenčně) změní, ať se
  // O(n) průchod přes desítky tisíc bodů neopakuje při každém build() (hledání,
  // přepínání filtrů). `all` je stabilní instance z _mergedAll, takže identical
  // spolehlivě pozná „nová data" vs. pouhé překreslení.
  List<PoiEntry>? _dedupCache;
  List<PoiEntry>? _dedupSrc;

  List<PoiEntry> _dedupAll(List<PoiEntry> all) {
    if (_dedupCache != null && identical(_dedupSrc, all)) return _dedupCache!;
    final deduped = _dedupPlaces(all);
    _dedupCache = deduped;
    _dedupSrc = all;
    return deduped;
  }

  /// Vzdálenost bodu od zadaného místa (∞ pro body bez GPS — spadnou dolů).
  double _distTo(Distance dist, LatLng from, PoiEntry e) {
    final ll = e.latLng;
    return ll == null ? double.infinity : dist.as(LengthUnit.Meter, from, ll);
  }

  /// Normalizovaný název místa pro slučování duplicit — malá písmena, sloučené
  /// mezery a bez vedoucího druhového slova (zámek/hrad/…), aby „Zámek Žirovnice"
  /// a „zámek Žirovnice" (i „Zámek Kamenice nad Lipou" vs „Kamenice nad Lipou")
  /// spadly na stejný klíč.
  static String _placeName(String raw) {
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
  static List<PoiEntry> _dedupPlaces(List<PoiEntry> src) {
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
        final cur = out[at];
        final curCover = cur.poi.cover != null;
        final candCover = e.poi.cover != null;
        final replace = curCover != candCover
            ? candCover // bod s fotkou vyhrává
            : (cur.catalog != e.catalog ? e.catalog : false); // katalog je kanonický
        if (replace) out[at] = e;
      }
    }
    return out;
  }

  /// Kotva (start / první bod) naposledy zvolené trasy — pro řazení „od zvolené
  /// trasy". null = žádná trasa dosud otevřená / trasy nenačteny.
  LatLng? _selectedRouteAnchor() {
    final lastId = ref.read(lastOpenedRouteProvider);
    if (lastId == null) return null;
    final data = ref.read(routesDataProvider).valueOrNull;
    if (data == null) return null;
    for (final r in data.routes) {
      if (r.id == lastId) return routeAnchor(r);
    }
    return null;
  }

  /// Přednačte náhledy prvních bodů v seznamu, ať se při scrollu nezobrazují
  /// „jak se načítají". Dedup přes _precachedUrls, jen prvních ~18.
  void _precacheThumbs(BuildContext context, List<PoiEntry> list) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var n = 0;
      for (final e in list) {
        if (n >= 18) break;
        final c = e.poi.cover;
        if (c == null) continue;
        n++;
        if (_precachedUrls.add(c)) {
          precacheRouteImage(context, c, targetWidth: 300);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    // Body z tras + komunitní (uživatelské) body zájmu.
    final routePois = ref.watch(allPoisProvider);
    final catalogAsync = ref.watch(catalogPoisProvider);
    final userAsync = ref.watch(userPoisProvider);
    final catalogPois = catalogAsync.valueOrNull ?? const <RoutePoi>[];
    final userPois = userAsync.valueOrNull ?? const <RoutePoi>[];
    // Dokud se katalog / komunitní body teprve načítají, NErenderuj seznam
    // „po dávkách" — jinak se po otevření několikrát přeskládá (uživatel viděl
    // 3 rychlé změny po sobě). Počkej na zdroje a zobraz je naráz.
    final sourcesLoading = catalogAsync.isLoading || userAsync.isLoading;
    final all = _mergedAll(routePois, catalogPois, userPois);
    final me = ref.watch(currentLocationProvider).valueOrNull;

    // Filtr + řazení (podle vzdálenosti od jezdce, jinak dle názvu trasy).
    final q = _query.trim();
    // V pohledu „vše" (bez filtru na konkrétní trasu) sluč body, které jsou
    // stejné fyzické místo opakující se přes více tras, do jedné položky — aby
    // se místo ležící na více trasách neukazovalo vícekrát. Data tras se NEMĚNÍ,
    // jde čistě o zobrazení; filtr na konkrétní trasu necháváme kompletní.
    final base = _routeFilter == null ? _dedupAll(all) : all;
    // 1) Volitelný filtr podle konkrétní trasy + hledání — základ pro počty
    //    kategorií. (Zdrojové rozlišení „katalog / komunitní / trasa" se
    //    nefiltruje — pro uživatele je bod jen bod; všechny se zobrazí spolu.)
    final sourceFiltered = base.where((e) {
      if (_routeFilter != null && e.route?.id != _routeFilter) return false;
      if (q.isEmpty) return true;
      // Hloubkové hledání: název, popis i překlady bodu (bez diakritiky),
      // případně název trasy, ke které bod patří.
      return searchMatches(e.poi.searchBlob, q) ||
          (e.route != null && searchMatches(e.route!.nameBlob, q));
    }).toList();
    // 2) „V okolí výběru" — nabídne další body do X km od PRVNÍHO vybraného bodu
    //    (stabilní střed vyjížďky). Dřív se okruh počítal od VŠECH vybraných, takže
    //    s každým přidaným návrhem se oblast rozrůstala (sjednocení kruhů) a filtr
    //    přestal zužovat. Kotva = první stále vybraný bod → okruh drží na místě.
    //    Vybrané body zůstávají vidět vždy; kategorie se filtrují až nad tím.
    const dist = Distance();
    LatLng? nearbyAnchor;
    if (_nearbyOn && _selected.isNotEmpty) {
      final anchorKey = _selected.first; // Set literál = pořadí vkládání
      for (final e in all) {
        if (e.key == anchorKey) {
          nearbyAnchor = e.latLng;
          break;
        }
      }
    }
    double distToAnchor(PoiEntry e) => (nearbyAnchor == null || e.latLng == null)
        ? double.infinity
        : dist.as(LengthUnit.Meter, nearbyAnchor!, e.latLng!);
    final nearFiltered = nearbyAnchor == null
        ? sourceFiltered
        : sourceFiltered
            .where((e) =>
                _selected.contains(e.key) ||
                (e.latLng != null && distToAnchor(e) <= _nearbyKm * 1000))
            .toList();
    // 3) Kategorie.
    var list = _cats.isEmpty
        ? nearFiltered
        : nearFiltered.where((e) => _cats.contains(poiCategoryOf(e.poi))).toList();
    // 4) Rozšířené filtry (jen s fotkou / minimální hodnocení / země).
    if (_onlyPhoto || _minRating > 0 || _fCountry.isNotEmpty) {
      list = list.where((e) {
        if (_onlyPhoto && e.poi.cover == null) return false;
        if (_minRating > 0 &&
            (e.poi.avgRating == null || e.poi.avgRating! < _minRating)) return false;
        if (_fCountry.isNotEmpty) {
          final cs = e.route?.countries ?? const <String>[];
          if (!cs.any(_fCountry.contains)) return false;
        }
        return true;
      }).toList();
    }
    // 5) Řazení. „V okolí výběru" má přednost (návrhy od vybraných bodů nahoře),
    //    jinak dle zvoleného řazení.
    final selRouteAnchor = _selectedRouteAnchor();
    if (nearbyAnchor != null) {
      list.sort((a, b) => distToAnchor(a).compareTo(distToAnchor(b)));
    } else {
      switch (_sort) {
        case _PoiSort.random:
          break; // stabilní pseudonáhodné pořadí zůstává zachováno
        case _PoiSort.nearMe:
          if (me != null) {
            list.sort((a, b) =>
                _distTo(dist, me, a).compareTo(_distTo(dist, me, b)));
          }
          break;
        case _PoiSort.nearRoute:
          if (selRouteAnchor != null) {
            list.sort((a, b) => _distTo(dist, selRouteAnchor, a)
                .compareTo(_distTo(dist, selRouteAnchor, b)));
          }
          break;
      }
    }
    _precacheThumbs(context, list);

    // Trasy, které mají aspoň jeden POI (pro filtr).
    final routesWithPois = <String, RouteItem>{};
    for (final e in routePois) {
      if (e.route != null) routesWithPois[e.route!.id] = e.route!;
    }
    // Země přítomné v datech (z tras, ke kterým body patří) — pro filtr země.
    final availableCountries = <String>{
      for (final e in all)
        if (e.route != null) ...e.route!.countries
    }.toList()
      ..sort();

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            _filters(context, lang, routesWithPois.values.toList(), all, nearFiltered,
                me != null, selRouteAnchor != null, availableCountries),
            Expanded(
              child: sourcesLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: MotoGoColors.greenDark))
                  : list.isEmpty
                      ? _empty(context)
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, _selected.isEmpty ? 24 : 110),
                          itemCount: list.length,
                          itemBuilder: (context, i) =>
                              _poiCard(context, list[i], lang, me),
                        ),
            ),
          ],
        ),
      ),
      bottomSheet: _selected.isEmpty ? null : _navBar(context, all, me),
    );
  }

  // ── Header ──
  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => widget.pickMode
                    ? Navigator.of(context).pop()
                    : context.backOr('/routes'),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 4),
              const Text('📍', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context).tr('poiBrowseAll'),
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeH1,
                    fontWeight: MotoGoTypo.w900,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2),
            child: Text(
              t(context).tr('poiBrowseSub'),
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w600,
                color: Color(0xFF8AAB99),
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Hledání
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: MotoGoColors.g400),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 280),
                        () {
                          if (mounted) setState(() => _query = v);
                        },
                      );
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: t(context).tr('poiSearch'),
                      hintStyle: const TextStyle(color: MotoGoColors.g400, fontSize: MotoGoTypo.sizeBase),
                    ),
                    style: const TextStyle(fontSize: MotoGoTypo.sizeLg, color: MotoGoColors.black),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filtry: řádek nástrojů (řazení/filtry, „v okolí", trasa) + řádek kategorií ──
  Widget _filters(BuildContext context, String lang, List<RouteItem> routes,
      List<PoiEntry> all, List<PoiEntry> sourceFiltered,
      bool meAvail, bool routeAvail, List<String> availableCountries) {
    if (routes.length < 2 && all.isEmpty && _selected.isEmpty) {
      return const SizedBox(height: 8);
    }

    // Počty kategorií z aktuálního zdroje (bez zapnutých kategorií).
    final catCounts = <String, int>{};
    for (final e in sourceFiltered) {
      final c = poiCategoryOf(e.poi);
      catCounts[c] = (catCounts[c] ?? 0) + 1;
    }

    RouteItem? selRoute;
    if (_routeFilter != null) {
      for (final r in routes) {
        if (r.id == _routeFilter) {
          selRoute = r;
          break;
        }
      }
    }

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            children: [
              // Řazení + rozšířené filtry (země / hodnocení / jen s fotkou).
              _srcChip(
                _sortLabel(context, _sort),
                Icons.tune,
                _sort != _PoiSort.random || _extraFilterCount > 0,
                _extraFilterCount > 0 ? _extraFilterCount : null,
                () => _openPoiToolsSheet(context, meAvail, routeAvail, availableCountries),
                trailing: Icons.arrow_drop_down,
              ),
              // „V okolí výběru" — objeví se, jakmile je vybraný aspoň 1 bod.
              if (_selected.isNotEmpty)
                _srcChip(
                  '${t(context).tr('poiNearby')} ${_nearbyKm.round()} km',
                  Icons.radar,
                  _nearbyOn,
                  null,
                  () => setState(() => _nearbyOn = !_nearbyOn),
                ),
              if (_selected.isNotEmpty && _nearbyOn)
                for (final km in _nearbyKmOptions)
                  _srcChip('${km.round()} km', Icons.circle_outlined,
                      _nearbyKm == km, null,
                      () => setState(() => _nearbyKm = km)),
              // Výběr konkrétní trasy — otevře sheet s hledáním (923 bodů ≠ řada chipů).
              _srcChip(
                selRoute != null ? selRoute.nameFor(lang) : t(context).tr('poiRoutePick'),
                Icons.route,
                selRoute != null,
                selRoute != null
                    ? all.where((e) => e.route?.id == selRoute!.id).length
                    : null,
                () => _openRoutePicker(context, lang, routes, all),
                trailing: Icons.arrow_drop_down,
              ),
            ],
          ),
        ),
        // Kategorie (jen ty, co mají v aktuálním zdroji aspoň 1 bod).
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            children: [
              for (final c in kPoiCats)
                if ((catCounts[c.key] ?? 0) > 0 || _cats.contains(c.key))
                  _catChip(context, c, catCounts[c.key] ?? 0),
            ],
          ),
        ),
      ],
    );
  }

  String _sortLabel(BuildContext context, _PoiSort s) {
    switch (s) {
      case _PoiSort.random:
        return t(context).tr('sortRandom');
      case _PoiSort.nearMe:
        return t(context).tr('sortNearMe');
      case _PoiSort.nearRoute:
        return t(context).tr('sortNearRoute');
    }
  }

  /// Vlaječka + kód země (jazykově neutrální).
  String _countryLabel(String code) {
    const flags = {
      'CZ': '🇨🇿', 'DE': '🇩🇪', 'AT': '🇦🇹', 'PL': '🇵🇱', 'SK': '🇸🇰',
      'HU': '🇭🇺', 'IT': '🇮🇹', 'CH': '🇨🇭', 'SI': '🇸🇮', 'HR': '🇭🇷',
      'FR': '🇫🇷', 'ES': '🇪🇸', 'PT': '🇵🇹', 'NL': '🇳🇱', 'BE': '🇧🇪',
      'LU': '🇱🇺', 'DK': '🇩🇰', 'SE': '🇸🇪', 'NO': '🇳🇴', 'FI': '🇫🇮',
      'GB': '🇬🇧', 'IE': '🇮🇪', 'RO': '🇷🇴', 'BG': '🇧🇬', 'RS': '🇷🇸',
      'GR': '🇬🇷', 'ME': '🇲🇪', 'BA': '🇧🇦', 'MK': '🇲🇰', 'AL': '🇦🇱',
      'AD': '🇦🇩', 'LI': '🇱🇮', 'IS': '🇮🇸', 'MD': '🇲🇩', 'LT': '🇱🇹',
      'LV': '🇱🇻', 'EE': '🇪🇪',
    };
    return '${flags[code] ?? '🏳️'} $code';
  }

  // ── Bottom sheet: řazení + rozšířené filtry bodů zájmu ──
  void _openPoiToolsSheet(BuildContext context, bool meAvail, bool routeAvail,
      List<String> availableCountries) {
    // Pracovní kopie (potvrdí se tlačítkem).
    var tSort = _sort;
    final tCountry = {..._fCountry};
    var tMin = _minRating;
    var tPhoto = _onlyPhoto;
    const ratingOptions = <double>[3, 4, 4.5];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Widget chip(String label, bool active, VoidCallback? onTap) {
              final enabled = onTap != null;
              return PressableScale(
                pressedScale: 0.94,
                onTap: onTap ?? () {},
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: active ? MotoGoColors.greenDark : Colors.white,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    border: Border.all(
                      color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeBase,
                      fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
                      color: active
                          ? Colors.white
                          : (enabled ? MotoGoColors.black : MotoGoColors.g400),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              );
            }

            Widget section(String label) => Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 4),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                );

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            t(sheetCtx).tr('poiFilterTitle'),
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeH2,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setSheet(() {
                              tSort = _PoiSort.random;
                              tCountry.clear();
                              tMin = 0;
                              tPhoto = false;
                            }),
                            child: Text(
                              t(sheetCtx).tr('poiFilterClear'),
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeBase,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.greenDark,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        children: [
                          // Řazení
                          section(t(sheetCtx).tr('sortTitle')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            chip(_sortLabel(sheetCtx, _PoiSort.random),
                                tSort == _PoiSort.random,
                                () => setSheet(() => tSort = _PoiSort.random)),
                            chip(_sortLabel(sheetCtx, _PoiSort.nearMe),
                                tSort == _PoiSort.nearMe,
                                meAvail ? () => setSheet(() => tSort = _PoiSort.nearMe) : null),
                            chip(_sortLabel(sheetCtx, _PoiSort.nearRoute),
                                tSort == _PoiSort.nearRoute,
                                routeAvail ? () => setSheet(() => tSort = _PoiSort.nearRoute) : null),
                          ]),
                          const SizedBox(height: 18),
                          // Jen s fotkou
                          section(t(sheetCtx).tr('poiFilterMinRating')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            chip(t(sheetCtx).tr('poiFilterAny'), tMin == 0,
                                () => setSheet(() => tMin = 0)),
                            for (final r in ratingOptions)
                              chip('★ ${r % 1 == 0 ? r.toStringAsFixed(0) : r.toStringAsFixed(1)}+',
                                  tMin == r, () => setSheet(() => tMin = r)),
                          ]),
                          const SizedBox(height: 18),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            chip('📷 ${t(sheetCtx).tr('poiFilterOnlyPhoto')}', tPhoto,
                                () => setSheet(() => tPhoto = !tPhoto)),
                          ]),
                          // Země
                          if (availableCountries.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            section(t(sheetCtx).tr('poiFilterCountry')),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final c in availableCountries)
                                chip(_countryLabel(c), tCountry.contains(c), () {
                                  setSheet(() =>
                                      tCountry.contains(c) ? tCountry.remove(c) : tCountry.add(c));
                                }),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    // Potvrzení
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                      child: PressableScale(
                        pressedScale: 0.98,
                        onTap: () {
                          setState(() {
                            _sort = tSort;
                            _fCountry
                              ..clear()
                              ..addAll(tCountry);
                            _minRating = tMin;
                            _onlyPhoto = tPhoto;
                          });
                          Navigator.of(sheetCtx).pop();
                        },
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: MotoGoColors.green,
                            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                  color: MotoGoColors.green.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              t(sheetCtx).tr('poiFilterApply'),
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeXl,
                                fontWeight: MotoGoTypo.w800,
                                color: MotoGoColors.black,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _srcChip(String label, IconData icon, bool active, int? count, VoidCallback onTap,
      {IconData? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenDark : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(color: active ? MotoGoColors.greenDark : MotoGoColors.g200, width: 1.5),
            boxShadow: active ? MotoGoShadows.cardSmall : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : MotoGoColors.greenDark),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
                    color: active ? Colors.white : MotoGoColors.black,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: active ? Colors.white.withValues(alpha: 0.22) : MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeSm,
                      fontWeight: MotoGoTypo.w800,
                      color: active ? Colors.white : MotoGoColors.greenDark,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
              if (trailing != null)
                Icon(trailing, size: 18, color: active ? Colors.white : MotoGoColors.g500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catChip(BuildContext context, PoiCat c, int count) {
    final active = _cats.contains(c.key);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: () => setState(() => active ? _cats.remove(c.key) : _cats.add(c.key)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenPale : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(
                color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
                width: active ? 1.6 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                t(context).tr(c.i18nKey),
                style: TextStyle(
                  fontSize: MotoGoTypo.sizeBase,
                  fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
                  color: active ? MotoGoColors.greenDarker : MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: MotoGoTypo.sizeSm,
                  fontWeight: MotoGoTypo.w800,
                  color: active ? MotoGoColors.greenDarker : MotoGoColors.g400,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sheet s výběrem trasy (hledání + počty bodů) ──
  void _openRoutePicker(
      BuildContext context, String lang, List<RouteItem> routes, List<PoiEntry> all) {
    final sorted = List<RouteItem>.from(routes)
      ..sort((a, b) => a.nameFor(lang).compareTo(b.nameFor(lang)));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        var q = '';
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final qq = q.trim();
            // Hloubkové hledání trasy — i podle měst na cestě a bodů zájmu.
            final filtered = qq.isEmpty
                ? sorted
                : sorted.where((r) => searchMatches(r.searchBlob, qq)).toList();
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Row(
                        children: [
                          Text(
                            t(sheetCtx).tr('poiRoutePickTitle'),
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeH2,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: MotoGoColors.g100,
                          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 18, color: MotoGoColors.g400),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                autofocus: false,
                                onChanged: (v) => setSheet(() => q = v),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: t(sheetCtx).tr('poiRouteSearch'),
                                  hintStyle: const TextStyle(
                                      color: MotoGoColors.g400, fontSize: MotoGoTypo.sizeBase),
                                ),
                                style: const TextStyle(
                                    fontSize: MotoGoTypo.sizeLg, color: MotoGoColors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        children: [
                          _routePickTile(sheetCtx, Icons.apps, t(sheetCtx).tr('poiAllRoutes'),
                              all.length, _routeFilter == null, () {
                            setState(() => _routeFilter = null);
                            Navigator.of(sheetCtx).pop();
                          }),
                          for (final r in filtered)
                            _routePickTile(
                              sheetCtx,
                              Icons.route,
                              r.nameFor(lang),
                              all.where((e) => e.route?.id == r.id).length,
                              _routeFilter == r.id,
                              () {
                                setState(() => _routeFilter = r.id);
                                Navigator.of(sheetCtx).pop();
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _routePickTile(BuildContext context, IconData icon, String label, int count,
      bool active, VoidCallback onTap) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(icon, size: 20, color: active ? MotoGoColors.greenDark : MotoGoColors.g500),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: MotoGoTypo.sizeLg,
          fontWeight: active ? MotoGoTypo.w900 : MotoGoTypo.w600,
          color: MotoGoColors.black,
          decoration: TextDecoration.none,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeSm,
                fontWeight: MotoGoTypo.w800,
                color: MotoGoColors.greenDark,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check, size: 18, color: MotoGoColors.greenDark),
          ],
        ],
      ),
    );
  }

  // ── Karta POI ──
  Widget _poiCard(BuildContext context, PoiEntry e, String lang, LatLng? me) {
    final selected = _selected.contains(e.key);
    String? distTxt;
    if (me != null && e.latLng != null) {
      final m = const Distance().as(LengthUnit.Meter, me, e.latLng!);
      distTxt = m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableScale(
        pressedScale: 0.98,
        onTap: () => setState(() {
          if (selected) {
            _selected.remove(e.key);
          } else {
            _selected.add(e.key);
          }
        }),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            border: Border.all(
              color: selected ? MotoGoColors.greenDark : MotoGoColors.g200,
              width: selected ? 2 : 1,
            ),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Náhled
              SizedBox(
                width: 84,
                height: 84,
                child: e.poi.cover != null
                    ? RouteImage(
                        url: e.poi.cover!,
                        targetWidth: 300,
                        placeholder: (_) => _thumbFallback(e.poi),
                        error: (_) => _thumbFallback(e.poi),
                      )
                    : _thumbFallback(e.poi),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.poi.nameFor(lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                              e.route != null
                                  ? Icons.route
                                  : (e.catalog ? Icons.place : Icons.groups),
                              size: 12,
                              color: MotoGoColors.greenDark),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              e.route?.nameFor(lang) ??
                                  (e.catalog
                                      ? t(context).tr('poiCatalog')
                                      : t(context).tr('poiCommunityPoint')),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w600,
                                color: MotoGoColors.g500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          if (e.poi.ratingCount > 0) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star, size: 12, color: Color(0xFFF5B301)),
                            const SizedBox(width: 2),
                            Text(
                              '${(e.poi.avgRating ?? 0).toStringAsFixed(1)} (${e.poi.ratingCount})',
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.g500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                          if (distTxt != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.near_me, size: 12, color: MotoGoColors.g400),
                            const SizedBox(width: 2),
                            Text(
                              distTxt,
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w700,
                                color: MotoGoColors.g500,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Detail (i) + výběr
              GestureDetector(
                onTap: () => showRoutePoiSheet(context, e.poi, lang),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.info_outline, size: 20, color: MotoGoColors.g400),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10, left: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: selected ? MotoGoColors.greenDark : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? MotoGoColors.greenDark : MotoGoColors.g200,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback([RoutePoi? poi]) => Container(
        color: MotoGoColors.greenPale,
        child: Center(
          child: Text(poi != null ? poiCatEmoji(poi) : '📍',
              style: const TextStyle(fontSize: 26)),
        ),
      );

  // ── Spodní lišta „Navigovat přes vybrané" ──
  Widget _navBar(BuildContext context, List<PoiEntry> all, LatLng? me) {
    final n = _selected.length;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: MotoGoShadows.stickyBar),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(_selected.clear),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Text(
                '$n ${t(context).tr('poiSelectedSuffix')}  ✕',
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PressableScale(
              pressedScale: 0.97,
              onTap: () => _navigate(context, all, me),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  boxShadow: [
                    BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.pickMode ? Icons.add : Icons.navigation, size: 18, color: MotoGoColors.black),
                      const SizedBox(width: 8),
                      Text(
                        t(context).tr(widget.pickMode ? 'poiAddToRoute' : 'poiContinue'),
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, List<PoiEntry> all, LatLng? me) {
    final pois = all.where((e) => _selected.contains(e.key)).map((e) => e.poi).toList();
    if (pois.isEmpty) return;
    // Režim výběru → vrať body do editoru trasy.
    if (widget.pickMode) {
      Navigator.of(context).pop(pois);
      return;
    }
    // Jinak sestav trasu (greedy od polohy) a otevři editor pro doladění.
    final route = buildCustomRoute(pois, from: me, name: t(context).tr('poiCustomRouteTitle'));
    context.push('/route-build', extra: route);
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🗺️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            t(context).tr('poiEmpty'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
