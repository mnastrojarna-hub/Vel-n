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
  String? _routeFilter; // null = vše, _kCommunity = komunitní body, jinak id trasy
  final Set<String> _cats = {}; // aktivní kategorie (prázdné = všechny)

  /// Sentinel filtru pro komunitní (uživatelské) body zájmu.
  static const _kCommunity = '__community__';

  /// Sentinel filtru pro katalogová „zajímavá místa" (samostatné body zájmu
  /// nezávislé na trasách — přehrady, hrady, rozhledny, památky, rezervace…).
  static const _kCatalog = '__catalog__';

  // Filtr „v okolí výběru" — nabídne další body do X km od už vybraných.
  bool _nearbyOn = false;
  double _nearbyKm = 10;
  static const List<double> _nearbyKmOptions = [5, 10, 25, 50];

  // Náhodné pořadí bodů — losuje se jen JEDNOU za běh appky (static), takže se
  // nemění při návratu na obrazovku; nové promíchání až po restartu appky.
  // Použije se, když není známá poloha; se známou polohou vyhrává vzdálenost.
  static final int _shuffleSeed = Random().nextInt(0x7fffffff);

  @override
  void initState() {
    super.initState();
    if (widget.initialSelected != null) _selected.addAll(widget.initialSelected!);
  }

  /// Stabilní pseudonáhodné pořadí bodu (nezávislé na tom, kdy dorazí který
  /// zdroj) — seznam se pak při postupném načítání zdrojů nepřeskládává.
  int _stableOrder(PoiEntry e) => (e.key.hashCode ^ _shuffleSeed) & 0x7fffffff;

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
    final all = <PoiEntry>[
      ...routePois,
      ...catalogPois.map((p) => PoiEntry(p, null, null, catalog: true)),
      ...userPois.map((p) => PoiEntry(p, null, null)),
    ]..sort((a, b) => _stableOrder(a).compareTo(_stableOrder(b)));
    final me = ref.watch(currentLocationProvider).valueOrNull;

    // Filtr + řazení (podle vzdálenosti od jezdce, jinak dle názvu trasy).
    final q = _query.trim();
    // 1) Zdroj (vše / komunitní / trasa) + hledání — základ pro počty kategorií.
    final sourceFiltered = all.where((e) {
      if (_routeFilter == _kCommunity) {
        if (!e.isCommunity) return false; // jen komunitní (uživatelské) body
      } else if (_routeFilter == _kCatalog) {
        if (!e.catalog) return false; // jen katalogová zajímavá místa
      } else if (_routeFilter != null && e.route?.id != _routeFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      // Hloubkové hledání: název, popis i překlady bodu (bez diakritiky),
      // případně název trasy, ke které bod patří.
      return searchMatches(e.poi.searchBlob, q) ||
          (e.route != null && searchMatches(e.route!.nameBlob, q));
    }).toList();
    // 2) „V okolí výběru" — po výběru bodu nabídne další body do X km od něj
    //    (vybrané zůstávají vidět vždy). Kategorie se filtrují až nad tím.
    const dist = Distance();
    final selPts = _nearbyOn && _selected.isNotEmpty
        ? all
            .where((e) => _selected.contains(e.key) && e.latLng != null)
            .map((e) => e.latLng!)
            .toList()
        : const <LatLng>[];
    double nearestSel(PoiEntry e) {
      var best = double.infinity;
      for (final p in selPts) {
        final d = dist.as(LengthUnit.Meter, p, e.latLng!);
        if (d < best) best = d;
      }
      return best;
    }
    final nearFiltered = selPts.isEmpty
        ? sourceFiltered
        : sourceFiltered
            .where((e) =>
                _selected.contains(e.key) ||
                (e.latLng != null && nearestSel(e) <= _nearbyKm * 1000))
            .toList();
    // 3) Kategorie.
    final list = _cats.isEmpty
        ? nearFiltered
        : nearFiltered.where((e) => _cats.contains(poiCategoryOf(e.poi))).toList();
    if (selPts.isNotEmpty) {
      // Řazení od vybraných bodů — nejbližší návrhy nahoře.
      list.sort((a, b) => nearestSel(a).compareTo(nearestSel(b)));
    } else if (me != null) {
      list.sort((a, b) => dist
          .as(LengthUnit.Meter, me, a.latLng!)
          .compareTo(dist.as(LengthUnit.Meter, me, b.latLng!)));
    }

    // Trasy, které mají aspoň jeden POI (pro filtr).
    final routesWithPois = <String, RouteItem>{};
    for (final e in routePois) {
      if (e.route != null) routesWithPois[e.route!.id] = e.route!;
    }

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            _filters(context, lang, routesWithPois.values.toList(), all, nearFiltered),
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
                    onChanged: (v) => setState(() => _query = v),
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

  // ── Filtry: řádek zdroje (vše / komunitní / trasa) + řádek kategorií ──
  Widget _filters(BuildContext context, String lang, List<RouteItem> routes,
      List<PoiEntry> all, List<PoiEntry> sourceFiltered) {
    final communityCount = all.where((e) => e.isCommunity).length;
    final catalogCount = all.where((e) => e.catalog).length;
    if (routes.length < 2 && communityCount == 0 && catalogCount == 0 &&
        _selected.isEmpty) {
      return const SizedBox(height: 8);
    }

    // Počty kategorií z aktuálního zdroje (bez zapnutých kategorií).
    final catCounts = <String, int>{};
    for (final e in sourceFiltered) {
      final c = poiCategoryOf(e.poi);
      catCounts[c] = (catCounts[c] ?? 0) + 1;
    }

    RouteItem? selRoute;
    if (_routeFilter != null && _routeFilter != _kCommunity) {
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
              _srcChip(t(context).tr('poiAllPoints'), Icons.apps, _routeFilter == null,
                  all.length, () => setState(() => _routeFilter = null)),
              if (catalogCount > 0)
                _srcChip(t(context).tr('poiCatalog'), Icons.place, _routeFilter == _kCatalog,
                    catalogCount, () => setState(() => _routeFilter = _kCatalog)),
              if (communityCount > 0)
                _srcChip(t(context).tr('poiCommunity'), Icons.groups, _routeFilter == _kCommunity,
                    communityCount, () => setState(() => _routeFilter = _kCommunity)),
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
