import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav, Routes;
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'collapsing_header.dart';
import 'community_submit.dart';
import 'country_codes.dart';
import 'places_filter.dart';
import 'places_map.dart';
import 'poi_categories.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'route_poi_sheet.dart';
import 'routes_quick_links.dart';


/// Katalog VŠECH bodů zájmu napříč trasami. Trasa je jen doporučení — tady si
/// zákazník vybere zastávky z různých tras (i ze dvou tras najednou) a sestaví
/// si vlastní vyjížďku, kterou pak naviguje přímo v appce.
class AllPoisScreen extends ConsumerStatefulWidget {
  /// Předvybrané body (klíče `routeId:poiId`) — např. „uprav tuto trasu".
  final Set<String>? initialSelected;
  /// Režim výběru pro editor trasy: spodní tlačítko vrátí vybrané body
  /// (Navigator.pop) místo přechodu na sestavení/navigaci.
  final bool pickMode;
  /// Obrazovka je kořenem 4. tabu (primární „Místa") — schová tlačítko zpět
  /// a přidá připnutý rozcestník Trasy / Mapa / Moje zážitky.
  final bool asTab;
  const AllPoisScreen({
    super.key,
    this.initialSelected,
    this.pickMode = false,
    this.asTab = false,
  });

  @override
  ConsumerState<AllPoisScreen> createState() => _AllPoisScreenState();
}

class _AllPoisScreenState extends ConsumerState<AllPoisScreen>
    with SingleTickerProviderStateMixin {
  // Pořadí dlaždic rozcestníku (Trasy / Mapa / Moje zážitky) — swipe po liště
  // je cyklicky posune.
  static const int _quickCount = 3;
  late final AnimationController _quickOrder = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  // Pořadí drží CELÉ číslo; controller je jen 0→1 přechod mezi starým
  // a novým pořadím. Dřív se cíl počítal ze SUROVÉ hodnoty controlleru,
  // takže druhý swipe během animace (value např. 1.4) zanesl do pořadí
  // desetinnou část a dlaždice zůstaly natrvalo rozjeté mezi sloty.
  int _quickIndex = 0;

  void _cycleQuickLinks() {
    if (_quickOrder.isAnimating) return; // swipe během přechodu ignoruj
    setState(() => _quickIndex = (_quickIndex + 1) % _quickCount);
    _quickOrder.forward(from: 0);
  }

  // Filtr i výběr míst žijí ve SDÍLENÉM stavu (places_filter.dart), aby
  // seznam a mapa ukazovaly vždy totéž a šlo trasu poskládat z obojího.
  /// V režimu výběru pro editor trasy je filtr LOKÁLNÍ — editor si nemá co
  /// vzít filtr, který uživatel nechal zapnutý v Místech (a naopak).
  PlacesFilter _ownFilter = const PlacesFilter();
  PlacesFilter get _f =>
      _localSel ? _ownFilter : ref.read(placesFilterProvider);
  void _setFilter(PlacesFilter Function(PlacesFilter) fn) {
    if (_localSel) {
      setState(() => _ownFilter = fn(_ownFilter));
      return;
    }
    ref.read(placesFilterProvider.notifier).update(fn);
  }
  /// Výběr míst. V režimu tabu je SDÍLENÝ s mapou (dá se tak poskládat trasa
  /// z obojího), ale v režimu výběru pro editor trasy (pickMode / předvybrané
  /// body) je LOKÁLNÍ — editor má vlastní zastávky a globální výběr by mu do
  /// nich zanesl body vybrané někde jinde.
  bool get _localSel => widget.pickMode || widget.initialSelected != null;
  final Set<String> _own = {};
  Set<String> get _selected =>
      _localSel ? _own : ref.read(placesSelectionProvider);
  void _toggleSel(String key) {
    if (_localSel) {
      setState(() => _own.contains(key) ? _own.remove(key) : _own.add(key));
      return;
    }
    ref.read(placesSelectionProvider.notifier).toggle(key);
  }

  void _clearSel() {
    if (_localSel) {
      setState(_own.clear);
      return;
    }
    ref.read(placesSelectionProvider.notifier).clear();
  }

  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Set<String> _precachedUrls = {}; // náhledy už poslané do precache

  /// Je panel filtrů rozbalený? Ve výchozím stavu NE — na telefonu zabíral
  /// filtr s kategoriemi půlku obrazovky a na místa samotná nezbylo místo.
  bool _filtersOpen = false;
  /// Pozice scrollu v okamžiku rozbalení filtru. Sbalení se počítá RELATIVNĚ
  /// od ní: absolutní práh zavíral panel i při scrollu, kterým se k jeho
  /// spodním chipům uživatel teprve snažil dostat.
  double _filtersOpenAt = 0;
  /// Klíč panelu filtrů — po rozbalení se na něj doscrolluje, aby byly
  /// kategorie vidět i na malém displeji.
  final GlobalKey _filtersKey = GlobalKey();

  // Debounce vyhledávání — filtr běží nad desítkami tisíc bodů, takže
  // přefiltrovat při KAŽDÉM stisku klávesy sekalo. Přefiltruje se až po
  // krátké pauze v psaní; napsaný text v poli zůstává responzivní hned.
  Timer? _searchDebounce;

  // Filtr „v okolí" — poloměr kolem kotvy. Kotva je PRIMÁRNĚ aktuální poloha
  // jezdce; teprve když poloha není k dispozici, použije se první vybraný bod
  // s GPS (stabilní střed vyjížďky). Dřív byla kotva VÝHRADNĚ první vybraný
  // bod, takže filtr nešlo zapnout bez zaškrtnutí a nikdy neměřil od jezdce.
  static const List<double> _nearbyKmOptions = [5, 10, 25, 50];

  /// Vynuluje ÚPLNĚ VŠECHNY filtry obrazovky včetně hledání, kategorií,
  /// „v okolí" a výběru trasy. Dřív tahle metoda pokrývala jen čtyři z nich
  /// a nikde se nevolala (mrtvý kód), takže „zrušit filtry" fakticky
  /// neexistovalo.
  void clearAllFilters() {
    _searchDebounce?.cancel();
    _searchCtl.clear();
    ref.read(placesSearchProvider.notifier).state = '';
    _setFilter((_) => const PlacesFilter());
  }

  int get _allFilterCount => _f.activeCount;

  // Náhodné pořadí bodů — losuje se jen JEDNOU za běh appky (static), takže se
  // nemění při návratu na obrazovku; nové promíchání až po restartu appky.
  // Použije se, když není známá poloha; se známou polohou vyhrává vzdálenost.
  static final int _shuffleSeed = Random().nextInt(0x7fffffff);

  @override
  void initState() {
    super.initState();
    final pre = widget.initialSelected;
    if (pre != null) _own.addAll(pre);
    // Scrollem se rozbalený filtr sbalí sám — uživatel chce při procházení
    // míst co nejvíc prostoru pro seznam.
    _scroll.addListener(_onScroll);
    // Výchozí řazení je „od mé polohy", takže si o polohu řekneme hned při
    // otevření Míst (jen v režimu tabu — v pick-mode z editoru trasy by
    // systémový dialog přišel z ničeho nic).
    if (widget.asTab && !widget.pickMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) requestLocationQuietly(ref);
      });
    }
  }

  void _onScroll() {
    if (!_filtersOpen || !_scroll.hasClients) return;
    // Sbalit až při odscrollování DOLŮ od místa, kde se filtr otevřel —
    // scroll nahoru ani dolaďování pozice panel nezavře.
    if (_scroll.position.pixels - _filtersOpenAt > 140) {
      setState(() => _filtersOpen = false);
    }
  }

  void _toggleFilters() {
    setState(() {
      _filtersOpen = !_filtersOpen;
      _filtersOpenAt = _scroll.hasClients ? _scroll.position.pixels : 0;
    });
    if (!_filtersOpen) return;
    // Rozbalený panel je vysoký; na telefonu by zůstal pod okrajem, tak na
    // něj rovnou doscrollujeme.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _filtersKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.05);
      if (_scroll.hasClients) _filtersOpenAt = _scroll.position.pixels;
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _quickOrder.dispose();
    super.dispose();
  }

  /// Stabilní pseudonáhodné pořadí bodu (nezávislé na tom, kdy dorazí který
  /// zdroj) — seznam se pak při postupném načítání zdrojů nepřeskládává.
  int _stableOrder(PoiEntry e) => (e.key.hashCode ^ _shuffleSeed) & 0x7fffffff;



  // Počet bodů na trasu — spočítá se JEDNÍM průchodem a memoizuje stejně jako
  // _mergedAll. Dřív se pro každou z ~1 200 tras procházel celý sloučený seznam
  // (~45 tis. položek), takže otevření výběru trasy znamenalo desítky milionů
  // porovnání na UI vlákně a appka na několik sekund ztuhla.
  Map<String, int>? _routeCountCache;
  List<PoiEntry>? _routeCountSrc;

  // Země přítomné v datech — memoizace přes identitu zdroje, stejně jako
  // _mergedAll. Bez ní se při každém setState procházel celý katalog.
  List<String>? _countriesCache;
  List<PoiEntry>? _countriesSrc;

  List<String> _countriesIn(List<PoiEntry> all) {
    if (_countriesCache != null && identical(_countriesSrc, all)) {
      return _countriesCache!;
    }
    final out = <String>{
      for (final e in all)
        if (e.countryCode != null)
          e.countryCode!
        else
          ...(e.route?.countries ?? const <String>[])
    }.toList();
    _countriesCache = out;
    _countriesSrc = all;
    return out;
  }

  // Memoizace CELÉ filtrovací pipeline. Bez ní se při každém překreslení
  // (i při pouhém klepnutí na „+" u místa) znovu filtrovaly a řadily desítky
  // tisíc bodů a znovu se počítaly kategorie.
  List<PoiEntry>? _resList;
  List<PoiEntry>? _resSource;
  List<PoiEntry>? _resBase;
  PlacesFilter? _resFilter;
  LatLng? _resMe;
  LatLng? _resNear;
  LatLng? _resRoute;
  Set<String>? _resSel;

  static bool _sameSet(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.length == b.length && a.containsAll(b);
  }

  /// Vrátí (vyfiltrovaný seznam, podklad pro počty kategorií) — přepočítá se
  /// jen při skutečné změně vstupů. Výběr je součástí klíče jen se zapnutým
  /// „v okolí" (jen tam ovlivňuje, co se zobrazí).
  ({List<PoiEntry> list, List<PoiEntry> source}) _filtered(
    List<PoiEntry> base,
    List<PoiEntry> all,
    PlacesFilter f,
    LatLng? me,
    LatLng? routeAnchor,
    LatLng? nearbyAnchor,
  ) {
    final selKey = f.nearbyOn ? _selected : null;
    if (_resList != null &&
        identical(_resBase, base) &&
        _resFilter == f &&
        _resMe == me &&
        _resNear == nearbyAnchor &&
        _resRoute == routeAnchor &&
        _sameSet(_resSel, selKey)) {
      return (list: _resList!, source: _resSource!);
    }
    final source = applyPlacesFilter(
      base,
      f.copyWith(cats: const {}),
      all: all,
      selected: _selected,
      me: me,
      routeAnchor: routeAnchor,
      nearbyAnchor: nearbyAnchor,
      // Jen podklad pro počty u kategorií — pořadí je tu k ničemu.
      ordered: false,
    );
    final list = applyPlacesFilter(
      base,
      f,
      all: all,
      selected: _selected,
      me: me,
      routeAnchor: routeAnchor,
      nearbyAnchor: nearbyAnchor,
      stableOrder: _stableOrder,
    );
    _resList = list;
    _resSource = source;
    _resBase = base;
    _resFilter = f;
    _resMe = me;
    _resNear = nearbyAnchor;
    _resRoute = routeAnchor;
    _resSel = selKey == null ? null : {...selKey};
    return (list: list, source: source);
  }

  // Počty kategorií nad aktuálním zdrojem — memoizace jako výše.
  Map<String, int>? _catCountCache;
  List<PoiEntry>? _catCountSrc;

  Map<String, int> _catCounts(List<PoiEntry> src) {
    if (_catCountCache != null && identical(_catCountSrc, src)) {
      return _catCountCache!;
    }
    final counts = <String, int>{};
    for (final e in src) {
      final c = poiCategoryOf(e.poi);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    _catCountCache = counts;
    _catCountSrc = src;
    return counts;
  }

  Map<String, int> _routePoiCounts(List<PoiEntry> all) {
    if (_routeCountCache != null && identical(_routeCountSrc, all)) {
      return _routeCountCache!;
    }
    final counts = <String, int>{};
    for (final e in all) {
      final id = e.route?.id;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    _routeCountCache = counts;
    _routeCountSrc = all;
    return counts;
  }




  /// Kotva (start / první bod) naposledy zvolené trasy — pro řazení „od zvolené
  /// trasy". null = žádná trasa dosud otevřená / trasy nenačteny.
  LatLng? _selectedRouteAnchor() {
    final lastId = _f.routeId ?? ref.watch(lastOpenedRouteProvider);
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
    // Sdílený filtr a výběr — bez watch by se obrazovka nepřekreslila,
    // když je změní mapa míst.
    ref.watch(placesFilterProvider);
    ref.watch(placesSelectionProvider);
    // Text v poli musí sledovat i vymazání filtru odjinud (z mapy nebo
    // z Tras) — jinak by tam zůstal viset dotaz, který už nefiltruje.
    if (!_localSel && _searchCtl.text != _f.query) {
      _searchDebounce?.cancel();
      _searchCtl.text = _f.query;
    }
    // Sdílený dotaz mezi Místy a Trasami — hlídá se v obou směrech, aby se
    // napsaný text přenesl i při NÁVRATU na už existující obrazovku
    // (initState by se podruhé nespustil).
    ref.listen<String>(placesSearchProvider, (prev, next) {
      // V pick-mode (výběr bodů pro editor trasy) je filtr LOKÁLNÍ — dotaz
      // napsaný v Místech sem nesmí propadnout a naopak.
      if (!mounted || _localSel || next == _f.query) return;
      _searchDebounce?.cancel();
      _searchCtl.text = next;
      _setFilter((f) => f.copyWith(query: next));
    });
    final shared = _localSel ? _f.query : ref.read(placesSearchProvider);
    if (shared != _f.query) {
      _searchCtl.text = shared;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setFilter((f) => f.copyWith(query: shared));
      });
    }
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
    // Spinner JEN dokud nemáme co ukázat. `isLoading` je v Riverpodu true
    // i při obnově s daty v ruce, takže dřív po přidání místa (invalidate)
    // zmizel celý seznam i pozice scrollu.
    final sourcesLoading = (catalogAsync.isLoading && catalogPois.isEmpty) ||
        (userAsync.isLoading && userPois.isEmpty);
    // Stejný zdroj jako mapa míst — klíče výběru si tak odpovídají.
    final all = ref.watch(allPlacesProvider);
    final me = ref.watch(currentLocationProvider).valueOrNull;

    // Filtr + řazení běží JEDNOU sdílenou funkcí (places_filter.dart), takže
    // seznam i mapa míst ukazují přesně stejnou množinu.
    final q = _f.query.trim();
    // V pohledu „vše" (bez filtru na konkrétní trasu) sluč body, které jsou
    // stejné fyzické místo opakující se přes více tras, do jedné položky.
    final base =
        _f.routeId == null ? ref.watch(dedupedPlacesProvider) : all;
    final selRouteAnchor = _selectedRouteAnchor();
    final nearbyAnchor = nearbyAnchorFor(_f, all, _selected, me: me);
    // Základ pro počty kategorií = po trase, hledání I „v okolí", jen bez
    // kategorií samotných. Jinak chip hlásí desítky míst a po zaškrtnutí
    // se ukáže prázdno.
    final res =
        _filtered(base, all, _f, me, selRouteAnchor, nearbyAnchor);
    final sourceFiltered = res.source;
    final list = res.list;
    _precacheThumbs(context, list);

    // Kolik tras odpovídá stejnému dotazu — pro pruh jednotného hledání.
    var routeHits = 0;
    if (q.isNotEmpty) {
      final allRoutes = ref.watch(routesDataProvider).valueOrNull?.routes ??
          const <RouteItem>[];
      for (final r in allRoutes) {
        if (searchMatches(r.searchBlob, q)) routeHits++;
      }
    }

    // Trasy, které mají aspoň jeden POI (pro filtr).
    final routesWithPois = <String, RouteItem>{};
    for (final e in routePois) {
      if (e.route != null) routesWithPois[e.route!.id] = e.route!;
    }
    // Země přítomné v datech (z tras, ke kterým body patří) — pro filtr země.
    final availableCountries = _countriesIn(all);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            // Hlavička se při scrollu SBALÍ (nadpis zůstane, podtitulek
            // i pole hledání se sroluje pryč) — na telefonu jinak na seznam
            // míst pod filtrem a mapou nezbývalo místo.
            SliverPersistentHeader(
              pinned: true,
              delegate: CollapsingSearchHeader(
                leading: const Text('📍', style: TextStyle(fontSize: 22)),
                title: t(context).tr('poiBrowseAll'),
                subtitle: t(context).tr('poiBrowseSub'),
                search: _searchField(context),
                onBack: (!widget.asTab || widget.pickMode)
                    ? () => widget.pickMode
                        ? Navigator.of(context).pop()
                        : context.backOr(Routes.routes)
                    : null,
                onSearchTap: _scrollToTop,
              ),
            ),
            // Rozcestník jen v režimu tabu — v pick-mode z editoru
            // trasy by odvedl pozornost od výběru bodů.
            if (widget.asTab && !widget.pickMode)
              SliverPersistentHeader(
                pinned: true,
                delegate: QuickLinksHeaderDelegate(
                  order: _quickOrder,
                  index: _quickIndex,
                  onCycle: _cycleQuickLinks,
                  links: [
                    QuickLink.light(
                      emoji: '🗺️',
                      titleKey: 'routesEntryTitle',
                      subtitleKey: 'routesEntrySub',
                      onTap: () => context.push(Routes.routesList),
                    ),
                    QuickLink.light(
                      emoji: '🧭',
                      titleKey: 'placesMapTitle',
                      subtitleKey: 'placesMapSub',
                      onTap: () => context.push(Routes.placesMap),
                    ),
                    QuickLink.dark(
                      emoji: '🏍️',
                      titleKey: 'myExpEntryTitle',
                      subtitleKey: 'myExpEntrySub',
                      onTap: () => context.push('/my-experiences'),
                    ),
                  ],
                ),
              ),
            if (sourcesLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: CircularProgressIndicator(
                        color: MotoGoColors.greenDark)),
              )
            else ...[
              // Bez povolené polohy se místa řadit „od tebe" nedají — řekneme
              // si o ni viditelně, ne jen schovaným chipem ve filtru.
              if (widget.asTab && !widget.pickMode && me == null)
                SliverToBoxAdapter(child: _locationPrompt(context)),
              // Mapa míst nad seznamem: ukazuje PRÁVĚ vyfiltrovaná místa,
              // tapem do mapy se otevře na celou obrazovku, tapem na místo
              // se přepne výběr a podržením (či dvojklikem) se otevře detail.
              if (widget.asTab && !widget.pickMode)
                SliverToBoxAdapter(child: _mapPreview(context, lang, list, me)),
              // Filtr: ve výchozím stavu SBALENÝ (jen tlačítko), rozbalí se
              // klepnutím a při scrollu seznamu se zase sbalí sám.
              SliverToBoxAdapter(
                child: _filters(context, lang, routesWithPois.values.toList(),
                    all, base, sourceFiltered, me != null,
                    selRouteAnchor != null, availableCountries, nearbyAnchor),
              ),
              // Jednotné hledání: když dotaz sedí i na trasy, nabídneme
              // přechod do jejich seznamu se stejným dotazem.
              if (q.isNotEmpty && routeHits > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: PressableScale(
                      pressedScale: 0.98,
                      onTap: () => context.push(Routes.routesList),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: MotoGoColors.greenPale,
                          borderRadius:
                              BorderRadius.circular(MotoGoRadius.card),
                          border: Border.all(
                              color: MotoGoColors.green, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Text('🗺️', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${t(context).tr('searchAlsoRoutes')} · '
                                '$routeHits',
                                style: const TextStyle(
                                  fontSize: MotoGoTypo.sizeBase,
                                  fontWeight: MotoGoTypo.w800,
                                  color: MotoGoColors.black,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios,
                                size: 13, color: MotoGoColors.greenDark),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (list.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: _empty(context),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, _selected.isEmpty ? 24 : 110),
                  sliver: SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        _poiCard(context, list[i], lang, me, list),
                  ),
                ),
            ],
          ],
        ),
      ),
      bottomSheet: _selected.isEmpty ? null : _navBar(context, all, me),
    );
  }

  /// Vrátí obsah na začátek (a tím zase rozbalí hlavičku s hledáním).
  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  /// Výzva k povolení polohy — výchozí řazení „od mé polohy" jinak tiše
  /// spadne na náhodné pořadí a uživatel neví proč.
  Widget _locationPrompt(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: PressableScale(
        pressedScale: 0.98,
        onTap: () => ensureLocation(ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            border: Border.all(color: MotoGoColors.green, width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.my_location, size: 18, color: MotoGoColors.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t(context).tr('poiLocationPrompt'),
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: MotoGoTypo.w700,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t(context).tr('poiLocationEnable'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeBase,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.greenDark,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mapa míst nad seznamem ──
  Widget _mapPreview(
      BuildContext context, String lang, List<PoiEntry> list, LatLng? me) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        child: SizedBox(
          height: 160,
          child: Stack(
            children: [
              Positioned.fill(
                child: PlacesMapView(
                  places: list,
                  lang: lang,
                  selected: _selected,
                  // Trasy až po označení místa, a jen ty, které ho obsahují.
                  routeLines: [
                    for (final r in routesContaining(
                        ref.watch(routesDataProvider).valueOrNull?.routes ??
                            const <RouteItem>[],
                        list,
                        _selected))
                      routeLine(r),
                  ],
                  me: me,
                  initialCenter: me,
                  initialZoom: me == null ? 7.2 : 10.5,
                  // Uvnitř scrollovaného seznamu se mapou neposouvá — jinak
                  // by si vzala svislý drag a seznamem by přes ni nešlo
                  // scrollovat. Posun a přiblížení až po rozbalení.
                  allowDrag: false,
                  // Klepnutí do mapy (mimo místo) ji otevře přes celou
                  // obrazovku — dřív to uměla jen malá ikonka v rohu.
                  onMapTap: () => context.push(Routes.placesMap),
                  onPlaceTap: (e) => _toggleSel(e.key),
                  // Podržení / dvojklik na místě = jeho detail.
                  onPlaceLongPress: (e) => _openPoiDetail(context, e, lang, list),
                  onLongPress: (p) async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PoiSubmitScreen(initialPoint: p)));
                    if (mounted) ref.invalidate(userPoisProvider);
                  },
                ),
              ),
              // Rozbalení na celou obrazovku.
              Positioned(
                right: 8,
                top: 8,
                child: PressableScale(
                  pressedScale: 0.92,
                  onTap: () => context.push(Routes.placesMap),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.open_in_full,
                        size: 18, color: MotoGoColors.greenDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
        // Nápověda ke gestům — bez ní se o klepnutí do mapy ani o podržení
        // místa nikdo nedozví (překlad existoval, ale nikde se nezobrazoval).
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 6),
          child: Text(
            t(context).tr('placesMapOpenHint'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeSm,
              fontWeight: MotoGoTypo.w600,
              color: MotoGoColors.g400,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  /// Detail místa + tlačítko „Přidat do mé cesty" přímo v něm.
  void _openPoiDetail(BuildContext context, PoiEntry e, String lang,
      List<PoiEntry> siblings) {
    final window = siblingWindow(siblings, siblings.indexOf(e));
    // Klíč výběru podle bodu — detail listuje mezi sousedy, takže se musí
    // dohledat pro každý zobrazený bod zvlášť.
    final keyOf = <String, String>{for (final x in window) x.poi.id: x.key};
    showRoutePoiSheet(
      context,
      e.poi,
      lang,
      siblings: [for (final x in window) x.poi],
      isSelected: (p) {
        final k = keyOf[p.id];
        return k != null && _selected.contains(k);
      },
      onToggleSelect: (p) {
        final k = keyOf[p.id];
        if (k != null) _toggleSel(k);
      },
    );
  }

  // ── Pole hledání (v hlavičce) ──
  Widget _searchField(BuildContext context) {
    return Container(
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
              controller: _searchCtl,
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 280),
                  () {
                    if (!mounted) return;
                    _setFilter((f) => f.copyWith(query: v));
                    ref.read(placesSearchProvider.notifier).state = v;
                  },
                );
              },
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: t(context).tr('poiSearch'),
                hintStyle: const TextStyle(
                    color: MotoGoColors.g400, fontSize: MotoGoTypo.sizeBase),
              ),
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg, color: MotoGoColors.black),
            ),
          ),
          // Křížek — bez něj šel napsaný text smazat jen mazáním po písmenech.
          if (_f.query.isNotEmpty || _searchCtl.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _searchDebounce?.cancel();
                _searchCtl.clear();
                _setFilter((f) => f.copyWith(query: ''));
                ref.read(placesSearchProvider.notifier).state = '';
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Icon(Icons.close, size: 18, color: MotoGoColors.g400),
              ),
            ),
        ],
      ),
    );
  }

  // ── Filtry: sbalitelný panel (tlačítko „Filtry a řazení") ──
  //
  // Dřív byl celý filtr (řádek nástrojů + 11 kategorií) natvrdo nad seznamem
  // a zabíral půlku obrazovky, takže na samotná místa nezbylo místo. Teď je
  // ve výchozím stavu SBALENÝ, rozbaluje se tlačítkem a při scrollu seznamu
  // se zase sbalí. „Zrušit filtry" je vidět vždy, když je něco zapnuté.
  Widget _filters(BuildContext context, String lang, List<RouteItem> routes,
      List<PoiEntry> all, List<PoiEntry> base, List<PoiEntry> sourceFiltered,
      bool meAvail, bool routeAvail, List<String> availableCountries,
      LatLng? nearAnchor) {
    if (routes.length < 2 && all.isEmpty && _selected.isEmpty) {
      return const SizedBox(height: 8);
    }

    // Počty kategorií z aktuálního zdroje (bez zapnutých kategorií).
    final catCounts = _catCounts(sourceFiltered);

    RouteItem? selRoute;
    if (_f.routeId != null) {
      for (final r in routes) {
        if (r.id == _f.routeId) {
          selRoute = r;
          break;
        }
      }
    }
    final active = _allFilterCount;

    return Column(
      key: _filtersKey,
      children: [
        // Ovládací řádek — vždy vidět.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Row(
            children: [
              Expanded(
                child: _srcChip(
                  _filtersOpen
                      ? t(context).tr('poiFiltersClose')
                      : t(context).tr('poiFiltersOpen'),
                  Icons.tune,
                  _filtersOpen || active > 0,
                  active > 0 ? active : null,
                  _toggleFilters,
                  trailing: _filtersOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  expand: true,
                ),
              ),
              // Zrušit všechny filtry — výrazně a na stálém místě, aby se
              // zapnutá kategorie dala odznačit bez hledání.
              if (active > 0)
                _srcChip(
                  t(context).tr('routesFilterClear'),
                  Icons.close,
                  false,
                  null,
                  clearAllFilters,
                  danger: true,
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_filtersOpen
              ? const SizedBox(width: double.infinity, height: 4)
              : Column(
                  children: [
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                        children: [
                          // Řazení + rozšířené filtry (země / hodnocení).
                          _srcChip(
                            _sortLabel(context, _f.sort),
                            Icons.swap_vert,
                            _f.sort != PoiSort.nearMe,
                            null,
                            () => _openPoiToolsSheet(context, meAvail,
                                routeAvail, availableCountries, base, nearAnchor),
                            trailing: Icons.arrow_drop_down,
                          ),
                          // „V okolí" — dostupné HNED, měří od aktuální polohy.
                          // Když poloha ještě není povolená, tap si o ni řekne.
                          _srcChip(
                            '${t(context).tr('poiNearby')} ${_f.nearbyKm.round()} km',
                            Icons.radar,
                            _f.nearbyOn,
                            null,
                            () async {
                              if (!_f.nearbyOn && !meAvail && _selected.isEmpty) {
                                final ok = await ensureLocation(ref);
                                if (!ok || !mounted) return;
                              }
                              _setFilter((f) => f.copyWith(nearbyOn: !f.nearbyOn));
                            },
                          ),
                          if (_f.nearbyOn)
                            for (final km in _nearbyKmOptions)
                              _srcChip('${km.round()} km', Icons.circle_outlined,
                                  _f.nearbyKm == km, null,
                                  () => _setFilter((f) => f.copyWith(nearbyKm: km))),
                          // Výběr konkrétní trasy — sheet s hledáním.
                          _srcChip(
                            selRoute != null
                                ? selRoute.nameFor(lang)
                                : t(context).tr('poiRoutePick'),
                            Icons.route,
                            selRoute != null,
                            selRoute != null
                                ? _routePoiCounts(all)[selRoute.id]
                                : null,
                            () => _openRoutePicker(context, lang, routes, all),
                            trailing: Icons.arrow_drop_down,
                          ),
                        ],
                      ),
                    ),
                    // Kategorie (jen ty, co mají v aktuálním zdroji aspoň 1 bod).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in kPoiCats)
                            if ((catCounts[c.key] ?? 0) > 0 ||
                                _f.cats.contains(c.key))
                              _catChip(context, c, catCounts[c.key] ?? 0),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  String _sortLabel(BuildContext context, PoiSort s) {
    switch (s) {
      case PoiSort.random:
        return t(context).tr('sortRandom');
      case PoiSort.nearMe:
        return t(context).tr('sortNearMe');
      case PoiSort.nearRoute:
        return t(context).tr('sortNearRoute');
    }
  }


  // ── Bottom sheet: řadit a filtrovat místa ──
  //
  // Přepracováno 2026-09-16 (zadání uživatele): přibylo hledání a filtr
  // kategorií, zrušeno „jen s fotkou", hodnocení je schované pod rozbalovačem,
  // vlajky států mají stejné pořadí jako u tras (CZ/SK/AT/HU/IT/HR/SI první,
  // zbytek pod „Další státy"), řazení začíná vzdáleností a přibyl reset
  // i živý počet výsledků na potvrzovacím tlačítku.
  void _openPoiToolsSheet(BuildContext context, bool meAvail, bool routeAvail,
      List<String> availableCountries, List<PoiEntry> base, LatLng? nearAnchor) {
    final lang = ref.read(localeProvider).languageCode;
    // Pracovní kopie (potvrdí se tlačítkem).
    var tSort = _f.sort;
    final tCountry = {..._f.countries};
    final tCats = {..._f.cats};
    var tMin = _f.minRating;
    var tQuery = _f.query;
    const ratingOptions = <double>[3, 4, 4.5];
    final split = splitByPriority(availableCountries);
    final qCtl = TextEditingController(text: _f.query);
    var moreCountries = tCountry.any(split.rest.contains);
    var showRating = tMin > 0; // hodnocení je ve výchozím stavu schované
    Timer? deb;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            // Živý počet výsledků pro zvolenou kombinaci.
            final qq = tQuery.trim();
            const dist = Distance();
            var count = 0;
            for (final e in base) {
              // „V okolí" se v sheetu nenastavuje, ale výsledek ovlivňuje — bez
              // něj tlačítko slibovalo jiné číslo, než se pak v seznamu ukázalo.
              if (nearAnchor != null) {
                final p = e.latLng;
                if (p == null ||
                    dist.as(LengthUnit.Meter, nearAnchor, p) > _f.nearbyKm * 1000) {
                  continue;
                }
              }
              if (_f.routeId != null && e.route?.id != _f.routeId) continue;
              if (qq.isNotEmpty &&
                  !(searchMatches(e.poi.searchBlob, qq) ||
                      (e.route != null && searchMatches(e.route!.nameBlob, qq)))) {
                continue;
              }
              if (tCats.isNotEmpty && !tCats.contains(poiCategoryOf(e.poi))) continue;
              if (tMin > 0 && (e.poi.avgRating == null || e.poi.avgRating! < tMin)) {
                continue;
              }
              if (!e.matchesCountries(tCountry)) continue;
              count++;
            }

            Widget chip(String label, bool active, VoidCallback? onTap) {
              final enabled = onTap != null;
              return PressableScale(
                pressedScale: 0.94,
                onTap: onTap,
                enabled: enabled,
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
                  padding: const EdgeInsets.only(bottom: 10),
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
                          color: MotoGoColors.g200,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            t(sheetCtx).tr('poiToolsTitle'),
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeH2,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          PressableScale(
                            pressedScale: 0.94,
                            onTap: () {
                              clearAllFilters();
                              Navigator.of(sheetCtx).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.close,
                                      size: 16, color: MotoGoColors.greenDark),
                                  const SizedBox(width: 4),
                                  Text(
                                    t(sheetCtx).tr('routesFilterClear'),
                                    style: const TextStyle(
                                      fontSize: MotoGoTypo.sizeBase,
                                      fontWeight: MotoGoTypo.w700,
                                      color: MotoGoColors.greenDark,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        children: [
                          // ── Hledání ──
                          Container(
                            decoration: BoxDecoration(
                              color: MotoGoColors.g100,
                              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                const Icon(Icons.search,
                                    size: 18, color: MotoGoColors.g400),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: qCtl,
                                    onChanged: (v) {
                                      deb?.cancel();
                                      deb = Timer(
                                        const Duration(milliseconds: 220),
                                        () => setSheet(() => tQuery = v),
                                      );
                                    },
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      hintText: t(sheetCtx).tr('poiSearch'),
                                      hintStyle: const TextStyle(
                                          color: MotoGoColors.g400,
                                          fontSize: MotoGoTypo.sizeBase),
                                    ),
                                    style: const TextStyle(
                                        fontSize: MotoGoTypo.sizeLg,
                                        color: MotoGoColors.black),
                                  ),
                                ),
                                if (tQuery.isNotEmpty)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      deb?.cancel();
                                      qCtl.clear();
                                      setSheet(() => tQuery = '');
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 10),
                                      child: Icon(Icons.close,
                                          size: 18, color: MotoGoColors.g400),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          // ── Řazení (vzdálenost první) ──
                          section(t(sheetCtx).tr('sortTitle')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            chip(_sortLabel(sheetCtx, PoiSort.nearMe),
                                tSort == PoiSort.nearMe, () async {
                              if (!meAvail) {
                                final ok = await ensureLocation(ref);
                                // Sheet mohl mezitím zmizet — setSheet na
                                // odpojeném StatefulBuilderu shodí appku.
                                if (!ok || !sheetCtx.mounted) return;
                              }
                              setSheet(() => tSort = PoiSort.nearMe);
                            }),
                            chip(_sortLabel(sheetCtx, PoiSort.nearRoute),
                                tSort == PoiSort.nearRoute,
                                routeAvail
                                    ? () => setSheet(() => tSort = PoiSort.nearRoute)
                                    : null),
                            chip(_sortLabel(sheetCtx, PoiSort.random),
                                tSort == PoiSort.random,
                                () => setSheet(() => tSort = PoiSort.random)),
                          ]),
                          const SizedBox(height: 18),
                          // ── Kategorie ──
                          section(t(sheetCtx).tr('poiFilterCategory')),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final c in kPoiCats)
                              chip('${c.emoji} ${t(sheetCtx).tr(c.i18nKey)}',
                                  tCats.contains(c.key), () {
                                setSheet(() => tCats.contains(c.key)
                                    ? tCats.remove(c.key)
                                    : tCats.add(c.key));
                              }),
                          ]),
                          // ── Země ──
                          if (split.top.isNotEmpty || split.rest.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            section(t(sheetCtx).tr('poiFilterCountry')),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final c in split.top)
                                chip(countryChipLabel(c), tCountry.contains(c), () {
                                  setSheet(() => tCountry.contains(c)
                                      ? tCountry.remove(c)
                                      : tCountry.add(c));
                                }),
                              if (split.rest.isNotEmpty)
                                chip(
                                  '${moreCountries ? '▲' : '▼'} ${t(sheetCtx).tr('routesFilterMoreCountries')} (${split.rest.length})',
                                  false,
                                  () => setSheet(() => moreCountries = !moreCountries),
                                ),
                            ]),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: moreCountries
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                                        for (final c in split.rest)
                                          chip(countryFullLabel(c, lang),
                                              tCountry.contains(c), () {
                                            setSheet(() => tCountry.contains(c)
                                                ? tCountry.remove(c)
                                                : tCountry.add(c));
                                          }),
                                      ]),
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                          ],
                          // ── Hodnocení (ve výchozím stavu schované) ──
                          const SizedBox(height: 18),
                          chip(
                            '${showRating ? '▲' : '▼'} ${t(sheetCtx).tr('poiFilterMinRating')}',
                            false,
                            () => setSheet(() => showRating = !showRating),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: showRating
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                                      chip(t(sheetCtx).tr('poiFilterAny'), tMin == 0,
                                          () => setSheet(() => tMin = 0)),
                                      for (final r in ratingOptions)
                                        chip(
                                            '★ ${r % 1 == 0 ? r.toStringAsFixed(0) : r.toStringAsFixed(1)}+',
                                            tMin == r,
                                            () => setSheet(() => tMin = r)),
                                    ]),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: MotoGoColors.g200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                      child: PressableScale(
                        pressedScale: 0.98,
                        onTap: () {
                          _searchDebounce?.cancel();
                          if (_searchCtl.text != tQuery) _searchCtl.text = tQuery;
                          _setFilter((f) => f.copyWith(
                                sort: tSort,
                                countries: {...tCountry},
                                cats: {...tCats},
                                minRating: tMin,
                                query: tQuery,
                              ));
                          ref.read(placesSearchProvider.notifier).state = tQuery;
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
                              '${t(sheetCtx).tr('poiFilterApply')} ($count)',
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
    ).whenComplete(() {
      deb?.cancel();
      qCtl.dispose();
    });
  }

  Widget _srcChip(String label, IconData icon, bool active, int? count, VoidCallback onTap,
      {IconData? trailing, bool expand = false, bool danger = false}) {
    final fg = danger
        ? MotoGoColors.red
        : (active ? Colors.white : MotoGoColors.black);
    final iconFg = danger
        ? MotoGoColors.red
        : (active ? Colors.white : MotoGoColors.greenDark);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active && !danger ? MotoGoColors.greenDark : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(
                color: danger
                    ? MotoGoColors.red
                    : (active ? MotoGoColors.greenDark : MotoGoColors.g200),
                width: 1.5),
            boxShadow: active ? MotoGoShadows.cardSmall : null,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconFg),
              const SizedBox(width: 6),
              // Roztažený chip (tlačítko filtrů) nechá text zabrat celý
              // zbytek řádku; úzké chipy se drží do 180 px.
              if (expand)
                Expanded(child: _chipLabel(label, active, fg))
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: _chipLabel(label, active, fg),
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
                Icon(trailing,
                    size: 18, color: active ? Colors.white : MotoGoColors.g500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipLabel(String label, bool active, Color fg) => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: MotoGoTypo.sizeBase,
          fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
          color: fg,
          decoration: TextDecoration.none,
        ),
      );

  Widget _catChip(BuildContext context, PoiCat c, int count) {
    final active = _f.cats.contains(c.key);
    // Bez vlastního odsazení — rozestupy řeší Wrap (spacing/runSpacing).
    return PressableScale(
        pressedScale: 0.94,
        onTap: () => _setFilter((f) => f.copyWith(cats: {...f.cats}..toggleKey(c.key))),
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
      );
  }

  // ── Sheet s výběrem trasy (hledání + počty bodů) ──
  void _openRoutePicker(
      BuildContext context, String lang, List<RouteItem> routes, List<PoiEntry> all) {
    final sorted = List<RouteItem>.from(routes)
      ..sort((a, b) => a.nameFor(lang).compareTo(b.nameFor(lang)));
    final counts = _routePoiCounts(all);
    // Držáky MIMO builder sheetu: builder se volá znovu při každé změně
    // viewInsets (vyjetí klávesnice), takže lokální `var q` se pokaždé
    // vynulovalo — uživatel psal a seznam se nefiltroval.
    final qCtl = TextEditingController();
    var q = '';
    Timer? deb;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
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
                                controller: qCtl,
                                // Debounce jako na hlavní obrazovce — bez něj se
                                // celý seznam tras přestavoval na každé písmeno.
                                onChanged: (v) {
                                  deb?.cancel();
                                  deb = Timer(
                                    const Duration(milliseconds: 220),
                                    () => setSheet(() => q = v),
                                  );
                                },
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
                      // ListView.builder = líné stavění. Dřív se stavěly všechny
                      // dlaždice (~1 200) najednou ještě před prvním snímkem.
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: filtered.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i == 0) {
                            // POZOR: počet u „Všechny trasy" musí být počet
                            // TRAS. Dřív se tu posílal `all.length`, což je
                            // počet MÍST (desítky tisíc) — u popisku „trasy"
                            // to vypadalo, že tras je 45 000.
                            return _routePickTile(
                                sheetCtx, Icons.apps, t(sheetCtx).tr('poiAllRoutes'),
                                sorted.length, _f.routeId == null, () {
                              _setFilter((f) => f.copyWith(clearRouteId: true));
                              Navigator.of(sheetCtx).pop();
                            });
                          }
                          final r = filtered[i - 1];
                          return _routePickTile(
                            sheetCtx,
                            Icons.route,
                            r.nameFor(lang),
                            counts[r.id] ?? 0,
                            _f.routeId == r.id,
                            () {
                              _setFilter((f) => f.copyWith(routeId: r.id));
                              Navigator.of(sheetCtx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      deb?.cancel();
      qCtl.dispose();
    });
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
  /// Minuty na „1 h 20 m" / „45 m" — u vzdálenosti místa od jezdce.
  static String _fmtMin(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _poiCard(BuildContext context, PoiEntry e, String lang, LatLng? me,
      List<PoiEntry> siblings) {
    final selected = _selected.contains(e.key);
    String? distTxt;
    if (me != null && e.latLng != null) {
      final m = const Distance().as(LengthUnit.Meter, me, e.latLng!);
      distTxt = m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
      // Vzdálenost propojená s časem — kolik je to zhruba jízdy. Vzdušná čára
      // se přepočte koeficientem 1,3 (klikatost silnic) a průměrem 60 km/h,
      // stejně jako odhad dojezdu k trase (approachEstimate).
      if (m >= 1500) {
        final min = (m / 1000 * 1.3 / 60 * 60).round();
        if (min >= 1) distTxt = '$distTxt · ${_fmtMin(min)}';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // Podržení karty = přidat/odebrat z vyjížďky (druhá cesta k témuž,
      // co dělá kolečko vpravo). PressableScale dlouhý stisk sám neumí.
      child: GestureDetector(
        onLongPress: () => _toggleSel(e.key),
        child: PressableScale(
        pressedScale: 0.98,
        // Klepnutí = DETAIL místa (to uživatel chce nejčastěji), přidání do
        // vyjížďky je na kolečku vpravo nebo podržením karty. Dřív tap místo
        // rovnou přidával a detail se otevíral jen z malé ikonky (i).
        onTap: () => _openPoiDetail(context, e, lang, siblings),
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
                          // U katalogového místa ukazujeme KATEGORII (ikonku
                          // i popisek) — dřív tu u všech 40 tis. míst stálo
                          // jen „Z katalogu", takže z karty nešlo poznat, jestli
                          // je to rozhledna, studánka, nebo bunkr. Kategorie je
                          // přitom jediné, podle čeho se dá v seznamu filtrovat.
                          if (e.route == null && e.catalog)
                            Text(poiCatEmoji(e.poi),
                                style: const TextStyle(
                                    fontSize: 11,
                                    decoration: TextDecoration.none))
                          else
                            Icon(
                                e.route != null ? Icons.route : Icons.groups,
                                size: 12,
                                color: MotoGoColors.greenDark),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              e.route?.nameFor(lang) ??
                                  (e.catalog
                                      ? _catLabel(context, e.poi)
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
              // Přidat do vyjížďky / odebrat — jediné tlačítko na kartě
              // (klepnutí na kartu otevírá detail).
              Padding(
                padding: const EdgeInsets.only(right: 10, left: 4),
                child: PressableScale(
                  pressedScale: 0.9,
                  onTap: () => _toggleSel(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: selected ? MotoGoColors.greenDark : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? MotoGoColors.greenDark
                            : MotoGoColors.green,
                        width: 2,
                      ),
                    ),
                    child: Icon(selected ? Icons.check : Icons.add,
                        size: 20,
                        color:
                            selected ? Colors.white : MotoGoColors.greenDark),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// Lokalizovaný název kategorie místa (chip „Rozhledny a vrcholy",
  /// „Studánky a prameny"…) — používá se jako podtitulek karty.
  String _catLabel(BuildContext context, RoutePoi poi) {
    final k = poiCategoryOf(poi);
    for (final c in kPoiCats) {
      if (c.key == k) return t(context).tr(c.i18nKey);
    }
    return t(context).tr('poiCatOther');
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
            onTap: _clearSel,
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
    final pois = resolveSelected(
        ref.read(dedupedPlacesProvider), all, _selected);
    if (pois.isEmpty) return;
    // Režim výběru → vrať body do editoru trasy.
    if (widget.pickMode) {
      Navigator.of(context).pop(pois);
      return;
    }
    // Jinak sestav trasu (greedy od polohy) a otevři editor pro doladění.
    final route = buildCustomRoute(pois, from: me, name: t(context).tr('poiCustomRouteTitle'));
    if (!_localSel) ref.read(placesSelectionProvider.notifier).clear();
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
