import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart' show MotoGoBackNav, Routes;
import '../../core/widgets/moto_fx.dart';
import 'country_codes.dart';
import 'places_filter.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'route_reviews.dart';
import 'community_submit.dart';
import 'animated_route_icon.dart';
import 'routes_quick_links.dart';

/// Řazení seznamu tras.
enum _RouteSort { random, length, duration, nearMe, nearRoute }

/// Obrazovka „Trasy" — doporučené motorkářské trasy od poboček.
/// Nahrazuje tab E-shop ve spodní liště.
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen>
    with SingleTickerProviderStateMixin {
  // Pořadí připnutých rychlých vstupů (body zájmu / moje zážitky) — swipe po
  // liště je prohodí (0 = body zájmu první, 1 = moje zážitky první).
  late final AnimationController _quickOrder = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  static const int _quickCount = 3; // Místa / Mapa / Moje zážitky

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

  // Hloubkové vyhledávání — název, popis, města na cestě i body zájmu trasy.
  String _query = '';
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  final Set<String> _precachedCovers = {}; // covers už poslané do precache

  // Rozšířené filtry (prázdné = bez omezení).
  //
  // ZRUŠENO 2026-09-16 (zadání uživatele): filtr typu trasy (okruh /
  // za body zájmu), filtr obtížnosti a samostatný filtr „dojezd od tebe".
  // Sloupce `route_type` a `difficulty` v DB ZŮSTÁVAJÍ — `route_type` řídí
  // ve Velíně uzavření okruhu při výpočtu geometrie a detail trasy je dál
  // zobrazuje. Dojezd od polohy je nově volitelně započítaný do délky trasy.
  /// Výběr států je SDÍLENÝ s Místy (places_filter.dart) — je to jeden a týž
  /// filtr pro celou sekci, takže mapa míst otevřená z Tras ukáže právě to,
  /// co má uživatel nastavené tady.
  Set<String> get _fCountry => ref.read(placesFilterProvider).countries;
  RangeValues? _fDist; // km (volitelně včetně dojezdu od mé polohy)
  RangeValues? _fDur; // minuty — drží se s _fDist přes průměrnou rychlost
  /// Počítat do délky i cestu od mojí polohy na start trasy.
  bool _withApproach = false;

  // Náhodné pořadí tras — losuje se jen JEDNOU za běh appky (static), takže se
  // pořadí nemění při přepínání tabů ani při návratu na obrazovku. Nové
  // promíchání až po restartu appky.
  static final int _shuffleSeed = Random().nextInt(0x7fffffff);

  // Řazení seznamu tras (výchozí náhodně = stabilní seed za běh).
  _RouteSort _sort = _RouteSort.random;

  /// Kolik filtrů je aktivních. Počítá i hledání a řazení — bez toho se
  /// tlačítko „Zrušit filtry" nezobrazilo, když byl seznam zúžený jen
  /// napsaným textem, a uživatel neměl čím filtr zrušit.
  int get _activeFilterCount =>
      (_fCountry.isEmpty ? 0 : 1) +
      (_fDist == null ? 0 : 1) +
      (_withApproach ? 1 : 0) +
      (_query.trim().isEmpty ? 0 : 1) +
      (_sort == _RouteSort.random ? 0 : 1);

  void _clearFilters() {
    // Z Tras se ruší jen to, co Trasy samy nastavují — státy a hledání.
    // Kategorie, „v okolí" ani hodnocení patří Místům a nesmí tím zmizet.
    ref.read(placesFilterProvider.notifier).update(
          (f) => f.copyWith(countries: const {}, query: ''),
        );
    setState(() {
        _fDist = null;
        _fDur = null;
        _withApproach = false;
        _sort = _RouteSort.random;
      _query = '';
      _searchCtl.clear();
      _searchDebounce?.cancel();
      ref.read(placesSearchProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _quickOrder.dispose();
    super.dispose();
  }

  /// Přednačte náhledové fotky prvních tras, ať se v seznamu nezobrazují
  /// „jak se načítají". Dedup přes _precachedCovers, jen prvních ~8.
  void _precacheCovers(BuildContext context, List<RouteItem> routes) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var n = 0;
      for (final r in routes) {
        if (n >= 8) break;
        final c = r.cover;
        if (c == null) continue;
        n++;
        if (_precachedCovers.add(c)) {
          precacheRouteImage(context, c, targetWidth: 800);
        }
      }
    });
  }

  /// Celková délka trasy pro filtr — volitelně včetně odhadu cesty od mojí
  /// polohy na start. Nahrazuje zrušený samostatný filtr „Dojezd od tebe":
  /// zákazníka zajímá, kolik toho dneska najezdí CELKEM, ne dva rozpojené údaje.
  static double? _totalKm(RouteItem r, LatLng? me, bool withApproach) {
    final base = r.distanceKm;
    if (base == null) return null;
    if (!withApproach || me == null) return base;
    final est = approachEstimate(me, r);
    // Tam i zpět — jezdec se na start musí dostat a pak se vrátit domů.
    return est == null ? base : base + est.km * 2;
  }

  /// Celkový čas jízdy pro filtr — volitelně včetně cesty od mojí polohy
  /// (tam i zpět), aby čas odpovídal stejné trase jako délka. Bez toho
  /// měkké OR na času vždy přebilo prodlouženou délku a přepínač „počítat
  /// i cestu od mé polohy" neměl na výsledky žádný vliv.
  static int? _totalMin(RouteItem r, LatLng? me, bool withApproach) {
    final base = r.durationMin;
    if (base == null) return null;
    if (!withApproach || me == null) return base;
    final est = approachEstimate(me, r);
    return est == null ? base : base + est.min * 2;
  }

  /// Vyhovuje trasa zadané kombinaci filtrů? (statické parametry — sdílí seznam i náhled v sheetu)
  ///
  /// Délka a čas jsou v UI svázané přes průměrnou rychlost, ale filtruje se
  /// MĚKCE: stačí, aby trasa vyhověla délce NEBO času. Poměr km/min je totiž
  /// napříč daty nekonzistentní (část tras má přepočtených 42 km/h, starší
  /// ruční ~33 km/h včetně zastávek), takže tvrdé AND by u stejně dlouhých
  /// tras vyhazovalo ty „pomalejší" bez zjevného důvodu.
  static bool _routeMatches(
    RouteItem r,
    Set<String> countries,
    RangeValues? dist,
    RangeValues? dur,
    LatLng? me,
    bool withApproach,
  ) {
    if (dist != null || dur != null) {
      final km = _totalKm(r, me, withApproach);
      final min = _totalMin(r, me, withApproach);
      // Neznámé hodnoty nevyřazujeme — trasa bez km/min projde vždy.
      final kmChecked = dist != null && km != null;
      final minChecked = dur != null && min != null;
      if (kmChecked || minChecked) {
        final okKm = dist != null &&
            km != null &&
            km >= dist.start - 0.5 &&
            km <= dist.end + 0.5;
        final okMin = dur != null &&
            min != null &&
            min >= dur.start - 0.5 &&
            min <= dur.end + 0.5;
        if (!okKm && !okMin) return false;
      }
    }
    if (countries.isNotEmpty && !r.countries.any(countries.contains)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Sdílený filtr států — změna z Míst nebo z mapy musí překreslit i tady.
    ref.watch(placesFilterProvider);
    // Sdílený dotaz mezi Místy a Trasami — hlídá se v obou směrech, aby se
    // napsaný text přenesl i při NÁVRATU na už existující obrazovku
    // (initState by se podruhé nespustil).
    ref.listen<String>(placesSearchProvider, (prev, next) {
      if (!mounted || next == _query) return;
      _searchDebounce?.cancel();
      _searchCtl.text = next;
      setState(() => _query = next);
    });
    final shared = ref.read(placesSearchProvider);
    if (shared != _query) {
      _query = shared;
      _searchCtl.text = shared;
    }
    final lang = ref.watch(localeProvider).languageCode;
    final dataAsync = ref.watch(routesDataProvider);

    return Material(
      color: MotoGoColors.bg,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _header(
                  context,
                  dataAsync.valueOrNull?.routes.length,
                  ref.watch(catalogPoisProvider).valueOrNull?.length,
                ),
                Expanded(
                  child: dataAsync.when(
                    data: (data) => _body(context, data, lang),
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: MotoGoColors.greenDark),
                    ),
                    error: (e, _) => _errorState(context, e),
                  ),
                ),
              ],
            ),
            // „+" — navrhnout trasu / bod zájmu (komunitní obsah)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'routes-add',
                backgroundColor: MotoGoColors.green,
                foregroundColor: MotoGoColors.black,
                onPressed: () => showCommunityAddMenu(context),
                child: const Icon(Icons.add, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// „Marketingové" číslo do hlavičky: skutečný počet zaokrouhlený DOLŮ na hezké
  /// číslo, ale nikdy méně než zaručené minimum (ať to zákazníka upoutá a přitom
  /// zůstane pravdivé — počty katalogu i tras jen rostou). Tisíce se oddělují
  /// pevnou mezerou (např. „37 000").
  static String _fmtCount(int? actual, int floor, int round) {
    var n = floor;
    if (actual != null && actual > floor) n = (actual ~/ round) * round;
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _header(BuildContext context, int? routeCount, int? poiCount) {
    // Dynamický, poutavější podtitulek — počet tras i zajímavých míst, ať čísla
    // zákazníka upoutají (např. „Přes 1 370 tras a 37 000 zajímavých míst").
    final subtitle = (routeCount != null && routeCount > 0)
        ? t(context).tr('routesDiscoverStats')
            .replaceFirst('{routes}', _fmtCount(routeCount, 1370, 10))
            .replaceFirst('{pois}', _fmtCount(poiCount, 37000, 1000))
        : t(context).tr('routesSubtitle');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (Navigator.of(context).canPop()) ...[
                GestureDetector(
                  onTap: () => context.backOr(Routes.routes),
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8, top: 4, bottom: 4),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
              ],
              const AnimatedRouteIcon(size: 28),
              const SizedBox(width: 10),
              Text(
                t(context).tr('routesTitle'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeH1,
                  fontWeight: MotoGoTypo.w900,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeBase,
              fontWeight: MotoGoTypo.w600,
              color: Color(0xFF8AAB99),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 12),
          // Hloubkové hledání — trasa, místo, město na cestě, bod zájmu…
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
                    controller: _searchCtl,
                    // Debounce: bez něj se při psaní přefiltrovávalo přes
                    // 1 300 tras na každé písmeno.
                    onChanged: (v) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 280),
                        () {
                          if (!mounted) return;
                          setState(() => _query = v);
                          ref.read(placesSearchProvider.notifier).state = v;
                        },
                      );
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: t(context).tr('routesSearch'),
                      hintStyle: const TextStyle(color: MotoGoColors.g400, fontSize: MotoGoTypo.sizeBase),
                    ),
                    style: const TextStyle(fontSize: MotoGoTypo.sizeLg, color: MotoGoColors.black),
                  ),
                ),
                if (_query.isNotEmpty || _searchCtl.text.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _searchDebounce?.cancel();
                      _searchCtl.clear();
                      setState(() => _query = '');
                      ref.read(placesSearchProvider.notifier).state = '';
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      child: Icon(Icons.close, size: 18, color: MotoGoColors.g400),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, RoutesData data, String lang) {
    if (data.routes.isEmpty) return _emptyState(context);

    // Filtr poboček zrušen — trasy se neváží na pobočku, poloha jezdce je GPS.
    final byBranch = data.routes;
    // Náhodné pořadí (stálé po dobu života obrazovky) → hledání → filtr.
    final shuffled = List<RouteItem>.from(byBranch)..shuffle(Random(_shuffleSeed));
    final q = _query.trim();
    // Poloha jezdce — pro dojezd „od tebe" na kartách, filtr i řazení.
    final me = ref.watch(currentLocationProvider).valueOrNull;
    final routes = shuffled
        .where((r) => (q.isEmpty || searchMatches(r.searchBlob, q)) &&
            _routeMatches(r, _fCountry, _fDist, _fDur, me, _withApproach))
        .toList();

    // Řazení (poloha jezdce / od zvolené trasy).
    final lastId = ref.watch(lastOpenedRouteProvider);
    LatLng? selAnchor;
    if (lastId != null) {
      for (final r in data.routes) {
        if (r.id == lastId) {
          selAnchor = routeAnchor(r);
          break;
        }
      }
    }
    _sortRoutes(routes, me, selAnchor);
    _precacheCovers(context, routes);

    return RefreshIndicator(
      color: MotoGoColors.greenDark,
      onRefresh: () async => ref.invalidate(routesDataProvider),
      child: CustomScrollView(
        slivers: [
          // Připnuté rychlé vstupy. Trasy jsou nově SEKUNDÁRNÍ obrazovka,
          // takže odtud se odkazuje zpět na Místa (primární), na mapu míst
          // a na Moje zážitky. Při scrollování zůstávají vidět (plné karty →
          // kompaktní lišta), swipe do strany posune pořadí, tap otevře.
          SliverPersistentHeader(
            pinned: true,
            delegate: QuickLinksHeaderDelegate(
              order: _quickOrder,
              index: _quickIndex,
              onCycle: _cycleQuickLinks,
              links: [
                QuickLink.light(
                  emoji: '📍',
                  titleKey: 'poiBrowseAll',
                  subtitleKey: 'poiBrowseSub',
                  onTap: () => context.backOr(Routes.routes),
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
          // Rozšířené filtry (typ, obtížnost, délka, čas, země, dojezd) + řazení
          SliverToBoxAdapter(child: _filterBar(context, data, me, selAnchor != null)),
          if (routes.isEmpty)
            SliverToBoxAdapter(child: _filterEmpty(context))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              sliver: SliverList.builder(
                itemCount: routes.length,
                itemBuilder: (context, i) {
                  final r = routes[i];
                  return StaggeredReveal(
                    // Zpoždění jen pro prvních pár karet (90 ms na index).
                    // Bez stropu čekala karta s indexem 50 přes čtyři
                    // sekundy a po odscrollování zůstal seznam prázdný.
                    index: i < 6 ? i : 0,
                    baseDelay: const Duration(milliseconds: 60),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _RouteCard(
                        route: r,
                        branch: r.branchId != null ? data.branches[r.branchId] : null,
                        lang: lang,
                        // Dojezd od aktuální polohy (odhad) — původní délka/čas
                        // trasy na kartě zůstávají, tohle se jen přidává.
                        approach: me == null ? null : approachEstimate(me, r),
                        onTap: () {
                          // Zapamatuj zvolenou trasu pro řazení „od zvolené trasy".
                          ref.read(lastOpenedRouteProvider.notifier).state = r.id;
                          // Sousedi pro listování swipem = právě vyfiltrovaný
                          // seznam v tom pořadí, v jakém ho uživatel vidí.
                          context.push('/routes/${r.id}',
                              extra: [for (final x in routes) x.id]);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }


  // ── Řazení tras ──
  String _sortLabel(BuildContext context, _RouteSort s) {
    switch (s) {
      case _RouteSort.random:
        return t(context).tr('sortRandom');
      case _RouteSort.length:
        return t(context).tr('sortLength');
      case _RouteSort.duration:
        return t(context).tr('sortDuration');
      case _RouteSort.nearMe:
        return t(context).tr('sortNearMe');
      case _RouteSort.nearRoute:
        return t(context).tr('sortNearRoute');
    }
  }

  double _routeDistFrom(Distance dist, LatLng from, RouteItem r) {
    final a = routeAnchor(r);
    return a == null ? double.infinity : dist.as(LengthUnit.Meter, from, a);
  }

  void _sortRoutes(List<RouteItem> routes, LatLng? me, LatLng? selAnchor) {
    const dist = Distance();
    switch (_sort) {
      case _RouteSort.random:
        break; // už zamícháno stabilním seedem
      case _RouteSort.length:
        routes.sort((a, b) =>
            (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity));
        break;
      case _RouteSort.duration:
        routes.sort((a, b) =>
            (a.durationMin ?? 1 << 30).compareTo(b.durationMin ?? 1 << 30));
        break;
      case _RouteSort.nearMe:
        if (me != null) {
          routes.sort((a, b) =>
              _routeDistFrom(dist, me, a).compareTo(_routeDistFrom(dist, me, b)));
        }
        break;
      case _RouteSort.nearRoute:
        if (selAnchor != null) {
          routes.sort((a, b) => _routeDistFrom(dist, selAnchor, a)
              .compareTo(_routeDistFrom(dist, selAnchor, b)));
        }
        break;
    }
  }

  void _openSortSheet(BuildContext context, bool meAvail, bool routeAvail) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) {
        Widget opt(_RouteSort s, IconData ic, bool enabled) => ListTile(
              enabled: enabled,
              leading: Icon(ic,
                  color: enabled ? MotoGoColors.greenDark : MotoGoColors.g300),
              title: Text(_sortLabel(context, s),
                  style: TextStyle(
                    fontSize: MotoGoTypo.sizeLg,
                    fontWeight: _sort == s ? MotoGoTypo.w900 : MotoGoTypo.w600,
                    color: enabled ? MotoGoColors.black : MotoGoColors.g400,
                    decoration: TextDecoration.none,
                  )),
              trailing: _sort == s
                  ? const Icon(Icons.check, color: MotoGoColors.greenDark)
                  : null,
              onTap: enabled
                  ? () {
                      // Stejná pojistka jako u filtru — sheet může přežít
                      // odpojení obrazovky a setState by pak padl.
                      if (mounted) setState(() => _sort = s);
                      Navigator.of(sc).pop();
                    }
                  : null,
            );
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)),
              ),
              opt(_RouteSort.random, Icons.shuffle, true),
              opt(_RouteSort.length, Icons.straighten, true),
              opt(_RouteSort.duration, Icons.schedule, true),
              opt(_RouteSort.nearMe, Icons.my_location, meAvail),
              opt(_RouteSort.nearRoute, Icons.route, routeAvail),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Lišta rozšířených filtrů (tlačítko + řazení + rychlé zrušení) ──
  // ── Lišta nad seznamem: filtry / řazení / mapa míst / zrušit ──
  //
  // Vodorovně scrollovatelná: tři pilulky + reset se na šířku telefonu
  // nevejdou a pevný Row by přetekl (reset by se ořízl mimo obrazovku
  // a nešel by kliknout), hlavně v němčině s delšími popisky.
  Widget _filterBar(BuildContext context, RoutesData data, LatLng? me, bool routeAvail) {
    final n = _activeFilterCount;
    final active = n > 0;

    Widget pill({
      required IconData icon,
      required String label,
      required bool on,
      required VoidCallback onTap,
      int? badge,
      Color? bg,
      Color? border,
      Color? fg,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: PressableScale(
            pressedScale: 0.96,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: bg ?? (on ? MotoGoColors.greenDark : Colors.white),
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                border: Border.all(
                  color: border ?? (on ? MotoGoColors.greenDark : MotoGoColors.g200),
                  width: 1.5,
                ),
                boxShadow: on ? MotoGoShadows.cardSmall : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 16,
                      color: fg ?? (on ? Colors.white : MotoGoColors.greenDark)),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w800,
                      color: fg ?? (on ? Colors.white : MotoGoColors.black),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeSm,
                          fontWeight: MotoGoTypo.w800,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        children: [
          pill(
            icon: Icons.tune,
            label: t(context).tr('routesFilter'),
            on: active,
            badge: active ? n : null,
            onTap: () => _openFilterSheet(context, data, me),
          ),
          pill(
            icon: Icons.swap_vert,
            label: _sortLabel(context, _sort),
            on: _sort != _RouteSort.random,
            onTap: () => _openSortSheet(context, me != null, routeAvail),
          ),
          // Mapa míst — otevře se s AKTUÁLNÍM filtrem a dá se v ní klikáním
          // poskládat trasa z vybraných míst.
          pill(
            icon: Icons.map_outlined,
            label: t(context).tr('placesMapBtn'),
            on: false,
            bg: MotoGoColors.greenPale,
            border: MotoGoColors.green,
            fg: MotoGoColors.black,
            onTap: () => context.push(Routes.placesMap),
          ),
          if (active)
            GestureDetector(
              onTap: _clearFilters,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close, size: 15, color: MotoGoColors.g500),
                    const SizedBox(width: 3),
                    Text(
                      t(context).tr('routesFilterClear'),
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeBase,
                        fontWeight: MotoGoTypo.w700,
                        color: MotoGoColors.g500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            t(context).tr('routesFilterEmpty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeLg,
              fontWeight: MotoGoTypo.w700,
              color: MotoGoColors.g500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 14),
          PressableScale(
            pressedScale: 0.96,
            onTap: _clearFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
              child: Text(
                t(context).tr('routesFilterClear'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet se všemi filtry ──
  //
  // Přepracováno 2026-09-16: zrušen filtr typu trasy, obtížnosti i samostatný
  // „dojezd od tebe"; délka a čas jsou svázané (posun jednoho dopočítá druhý);
  // státy jsou NAHOŘE (dřív až pod třemi posuvníky, takže vlajky nebyly vidět)
  // s CZ/SK/AT/HU/IT/HR/SI napevno první a zbytkem pod rozbalovačem.
  void _openFilterSheet(BuildContext context, RoutesData data, LatLng? me) {
    final base = data.routes;
    final lang = ref.read(localeProvider).languageCode;
    final q = _query.trim();

    // Meze posuvníků z dat — ve DVOU variantách. Se zapnutým dojezdem od
    // polohy jsou trasy delší, takže rozsah musí sedět na to, co se filtruje;
    // jinak by přepínač buď nic nedělal, nebo by tiše vyhodil vzdálené trasy.
    ({double min, double max, bool ok}) bounds(List<double> xs) {
      xs.sort();
      final ok = xs.length >= 2 && xs.first < xs.last;
      return (
        min: ok ? xs.first.floorToDouble() : 0.0,
        max: ok ? xs.last.ceilToDouble() : 0.0,
        ok: ok,
      );
    }

    final dPlain = bounds(
        base.map((r) => r.distanceKm).whereType<double>().toList());
    final dAppr = bounds(base
        .map((r) => _totalKm(r, me, true))
        .whereType<double>()
        .toList());
    final tPlain = bounds(base
        .map((r) => r.durationMin?.toDouble())
        .whereType<double>()
        .toList());
    final tAppr = bounds(base
        .map((r) => _totalMin(r, me, true)?.toDouble())
        .whereType<double>()
        .toList());

    // Průměrná rychlost pro přepočet km ↔ čas. Bere se MEDIÁN ze skutečných
    // dvojic v datech, ne konstanta — část tras má přepočtených 42 km/h,
    // starší ruční hodnoty vycházejí kolem 33 km/h (včetně zastávek).
    final speeds = <double>[];
    for (final r in base) {
      final km = r.distanceKm;
      final mn = r.durationMin;
      if (km != null && mn != null && km > 0 && mn > 0) speeds.add(km / (mn / 60));
    }
    speeds.sort();
    final kmh = speeds.isEmpty ? 42.0 : speeds[speeds.length ~/ 2];

    // Země přítomné v datech, rozdělené na připnuté a ostatní.
    final split = splitByPriority(<String>{
      for (final r in base) ...r.countries,
      // + státy, které jsou zrovna zaškrtnuté (mohly přijít z Míst, kde je
      // katalog bohatší než trasy) — jinak by nešly odškrtnout.
      ..._fCountry,
    });

    // Pracovní kopie (potvrdí se tlačítkem).
    final tCountry = {..._fCountry};
    var tDist = _fDist;
    var tDur = _fDur;
    var tApproach = _withApproach;
    var moreCountries = tCountry.any(split.rest.contains);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final db = tApproach ? dAppr : dPlain;
            final tb = tApproach ? tAppr : tPlain;
            final hasDist = db.ok, dMin = db.min, dMax = db.max;
            final hasDur = tb.ok, tMin = tb.min, tMax = tb.max;
            final count = base
                .where((r) =>
                    (q.isEmpty || searchMatches(r.searchBlob, q)) &&
                    _routeMatches(r, tCountry, tDist, tDur, me, tApproach))
                .length;

            double clampD(double v) => v.clamp(dMin, dMax);
            double clampT(double v) => v.clamp(tMin, tMax);

            // Posun délky dopočítá čas a naopak — hodnoty spolu korelují,
            // takže dvě nezávislá nastavení si jen protiřečila.
            void setDist(RangeValues v) => setSheet(() {
                  tDist = v;
                  if (hasDur) {
                    tDur = RangeValues(
                      clampT(v.start / kmh * 60),
                      clampT(v.end / kmh * 60),
                    );
                  }
                });
            void setDur(RangeValues v) => setSheet(() {
                  tDur = v;
                  if (hasDist) {
                    tDist = RangeValues(
                      clampD(v.start / 60 * kmh),
                      clampD(v.end / 60 * kmh),
                    );
                  }
                });
            void toggleCountry(String c) => setSheet(
                () => tCountry.contains(c) ? tCountry.remove(c) : tCountry.add(c));

            final dv = tDist ?? RangeValues(dMin, dMax);
            final tv = tDur ?? RangeValues(tMin, tMax);

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
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            t(sheetCtx).tr('routesFilterTitle'),
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeH2,
                              fontWeight: MotoGoTypo.w900,
                              color: MotoGoColors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          // Reset teď filtry i APLIKUJE a sheet zavře. Dřív
                          // vynuloval jen pracovní kopie, takže po zavření
                          // gestem zůstaly filtry beze změny a vypadalo to,
                          // že „zrušit filtry" nefunguje.
                          PressableScale(
                            pressedScale: 0.94,
                            onTap: () {
                              _clearFilters();
                              Navigator.of(sheetCtx).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.close, size: 16, color: MotoGoColors.greenDark),
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
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        children: [
                          // ── Země (nahoře, ať jsou vlajky vidět bez scrollu) ──
                          if (split.top.isNotEmpty || split.rest.isNotEmpty) ...[
                            _sheetSection(t(sheetCtx).tr('routesFilterCountry')),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final c in split.top)
                                _selChip(countryChipLabel(c), tCountry.contains(c),
                                    () => toggleCountry(c)),
                              if (split.rest.isNotEmpty)
                                _selChip(
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
                                          _selChip(countryFullLabel(c, lang), tCountry.contains(c),
                                              () => toggleCountry(c)),
                                      ]),
                                    )
                                  : const SizedBox(width: double.infinity),
                            ),
                            const SizedBox(height: 18),
                          ],
                          // ── Délka trasy (svázaná s časem) ──
                          if (hasDist) ...[
                            _sheetSection(
                                '${t(sheetCtx).tr('routesFilterDistance')}  ·  ${dv.start.round()}–${dv.end.round()} km'),
                            RangeSlider(
                              min: dMin,
                              max: dMax,
                              values: dv,
                              activeColor: MotoGoColors.greenDark,
                              inactiveColor: MotoGoColors.g200,
                              labels: RangeLabels('${dv.start.round()}', '${dv.end.round()}'),
                              onChanged: setDist,
                            ),
                          ],
                          // ── Čas jízdy (svázaný s délkou) ──
                          if (hasDur) ...[
                            const SizedBox(height: 6),
                            _sheetSection(
                                '${t(sheetCtx).tr('routesFilterDuration')}  ·  ${_fmtDur(tv.start.round())}–${_fmtDur(tv.end.round())}'),
                            RangeSlider(
                              min: tMin,
                              max: tMax,
                              values: tv,
                              activeColor: MotoGoColors.greenDark,
                              inactiveColor: MotoGoColors.g200,
                              labels: RangeLabels(
                                  _fmtDur(tv.start.round()), _fmtDur(tv.end.round())),
                              onChanged: setDur,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              child: Text(
                                t(sheetCtx).tr('routesFilterLinkedHint'),
                                style: const TextStyle(
                                  fontSize: MotoGoTypo.sizeSm,
                                  fontWeight: MotoGoTypo.w600,
                                  color: MotoGoColors.g500,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                          // ── Započítat cestu od mojí polohy do délky ──
                          if (hasDist) ...[
                            const SizedBox(height: 14),
                            _selChip(
                              '🏍️ ${t(sheetCtx).tr('routesFilterWithApproach')}',
                              tApproach,
                              () async {
                                if (!tApproach && me == null) {
                                  final ok = await ensureLocation(ref);
                                  if (!ok || !sheetCtx.mounted) return;
                                }
                                setSheet(() {
                                  tApproach = !tApproach;
                                  // Rozsah se přepnutím změní — hodnoty mimo
                                  // nové meze by RangeSlider shodily.
                                  tDist = null;
                                  tDur = null;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Jemný oddělovač — ať je poznat, že obsah nahoře pokračuje.
                    Container(height: 1, color: MotoGoColors.g200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                      child: PressableScale(
                        pressedScale: 0.98,
                        onTap: () {
                          // Sheet přežije odpojení obrazovky (typicky návrat
                          // appky z pozadí), takže tohle `setState` mohlo
                          // běžet nad už uvolněným State → pád
                          // „Null check operator used on a null value"
                          // (hlášeno z 4.0.0+103). Sheet zavřeme vždy,
                          // stav měníme jen když je obrazovka živá.
                          if (!mounted) {
                            Navigator.of(sheetCtx).pop();
                            return;
                          }
                          ref
                              .read(placesFilterProvider.notifier)
                              .update((f) => f.copyWith(countries: {...tCountry}));
                          setState(() {
                            // Plný rozsah = žádný filtr.
                            final td = tDist;
                            final tt = tDur;
                            final fullD =
                                td == null || (td.start <= dMin && td.end >= dMax);
                            final fullT =
                                tt == null || (tt.start <= tMin && tt.end >= tMax);
                            // Osy jsou svázané: když je jedna na plném
                            // rozsahu, dopočítaná druhá nesmí zůstat viset
                            // jako skrytý filtr, o kterém uživatel neví.
                            _fDist = (fullD || fullT) ? null : td;
                            _fDur = (fullD || fullT) ? null : tt;
                            _withApproach = tApproach;
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
                              '${t(sheetCtx).tr('routesFilterApply')} ($count)',
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

  Widget _sheetSection(String label) => Padding(
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

  Widget _selChip(String label, bool active, VoidCallback onTap) {
    return PressableScale(
      pressedScale: 0.94,
      onTap: onTap,
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
            color: active ? Colors.white : MotoGoColors.black,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }


  String _fmtDur(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Widget _emptyState(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Center(child: Text('🗺️', style: TextStyle(fontSize: 52))),
        const SizedBox(height: 14),
        Center(
          child: Text(
            t(context).tr('routesEmptyTitle'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            t(context).tr('routesEmptySub'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeBase,
              color: MotoGoColors.g400,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(BuildContext context, Object e) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Center(child: Icon(Icons.cloud_off, size: 48, color: MotoGoColors.g400)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            t(context).tr('routesError'),
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeXl,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: PressableScale(
            onTap: () => ref.invalidate(routesDataProvider),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              ),
              child: Text(
                t(context).tr('routesRetry'),
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Karta trasy — cover s gradientem, název, badge délka/čas/typ + počet POI.
/// K původní délce/času trasy se navíc ukazuje odhad dojezdu od polohy jezdce.
class _RouteCard extends StatelessWidget {
  final RouteItem route;
  final RouteBranch? branch;
  final String lang;
  final VoidCallback onTap;
  final ({double km, int min})? approach; // dojezd od aktuální polohy (odhad)

  const _RouteCard({
    required this.route,
    required this.branch,
    required this.lang,
    required this.onTap,
    this.approach,
  });

  @override
  Widget build(BuildContext context) {
    final cover = route.cover;
    return PressableScale(
      pressedScale: 0.97,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          boxShadow: MotoGoShadows.motoCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    RouteImage(
                      url: cover,
                      targetWidth: 800,
                      placeholder: (_) => _coverFallback(),
                      error: (_) => _coverFallback(),
                    )
                  else
                    _coverFallback(),
                  // Gradient
                  DecoratedBox(
                    decoration: BoxDecoration(gradient: MotoGoGradients.imageOverlay),
                  ),
                  // Typ trasy badge
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _pill(
                      route.isLoop
                          ? '🔄 ${t(context).tr('routeTypeLoop')}'
                          : '📍 ${t(context).tr('routeTypePoi')}',
                      MotoGoColors.green,
                      MotoGoColors.black,
                    ),
                  ),
                  // Název + pobočka dole
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.nameFor(lang),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeH2,
                            fontWeight: MotoGoTypo.w900,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (branch != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.flag, size: 13, color: MotoGoColors.green),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    branch!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: MotoGoTypo.sizeMd,
                                      fontWeight: MotoGoTypo.w600,
                                      color: Colors.white70,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Meta řádek
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (route.distanceKm != null)
                          _meta(Icons.straighten, '${route.distanceKm!.toStringAsFixed(0)} km'),
                        if (route.durationMin != null)
                          _meta(Icons.schedule, _dur(route.durationMin!)),
                        if (route.pois.isNotEmpty)
                          _meta(Icons.place, '${route.pois.length} ${t(context).tr('routePoiShort')}'),
                        // Dojezd od aktuální polohy — doplněk k údajům trasy výše.
                        if (approach != null)
                          _meta(Icons.near_me,
                              '${t(context).tr('routeFromMe')} ~${approach!.km.round()} km · ~${_dur(approach!.min)}'),
                        _ratingMeta(context),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: MotoGoColors.greenDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dur(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  Widget _coverFallback() => Container(
        color: MotoGoColors.greenPale,
        child: const Center(child: Text('🛣️', style: TextStyle(fontSize: 40))),
      );

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
        child: Text(
          text,
          style: TextStyle(
            fontSize: MotoGoTypo.sizeMd,
            fontWeight: MotoGoTypo.w800,
            color: fg,
            decoration: TextDecoration.none,
          ),
        ),
      );

  /// Hvězdičkové hodnocení trasy od uživatelů — klepnutím se otevřou recenze
  /// (komentáře) v bottom sheetu, bez nutnosti otevírat detail trasy.
  Widget _ratingMeta(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showRouteReviewsSheet(context,
            routeId: route.id, routeName: route.nameFor(lang)),
        child: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(route.reviewCount > 0 ? Icons.star : Icons.star_border,
                  size: 15, color: const Color(0xFFF5B301)),
              const SizedBox(width: 4),
              Text(
                route.reviewCount > 0
                    ? '${(route.reviewAvg ?? 0).toStringAsFixed(1)} (${route.reviewCount})'
                    : '(0)',
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeBase,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _meta(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: MotoGoColors.g400),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w700,
                color: MotoGoColors.g600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
}
