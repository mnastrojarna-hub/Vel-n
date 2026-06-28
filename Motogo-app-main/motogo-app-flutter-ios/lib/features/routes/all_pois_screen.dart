import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_poi_sheet.dart';

/// Katalog VŠECH bodů zájmu napříč trasami. Trasa je jen doporučení — tady si
/// zákazník vybere zastávky z různých tras (i ze dvou tras najednou) a sestaví
/// si vlastní vyjížďku, kterou pak naviguje přímo v appce.
class AllPoisScreen extends ConsumerStatefulWidget {
  /// Předvybrané body (klíče `routeId:poiId`) — např. „uprav tuto trasu".
  final Set<String>? initialSelected;
  const AllPoisScreen({super.key, this.initialSelected});

  @override
  ConsumerState<AllPoisScreen> createState() => _AllPoisScreenState();
}

class _AllPoisScreenState extends ConsumerState<AllPoisScreen> {
  final Set<String> _selected = {};
  String _query = '';
  String? _routeFilter; // null = všechny trasy

  @override
  void initState() {
    super.initState();
    if (widget.initialSelected != null) _selected.addAll(widget.initialSelected!);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final all = ref.watch(allPoisProvider);
    final me = ref.watch(currentLocationProvider).valueOrNull;

    // Filtr + řazení (podle vzdálenosti od jezdce, jinak dle názvu trasy).
    final q = _query.trim().toLowerCase();
    final list = all.where((e) {
      if (_routeFilter != null && e.route.id != _routeFilter) return false;
      if (q.isEmpty) return true;
      return e.poi.nameFor(lang).toLowerCase().contains(q) ||
          e.route.nameFor(lang).toLowerCase().contains(q);
    }).toList();
    if (me != null) {
      const d = Distance();
      list.sort((a, b) => d
          .as(LengthUnit.Meter, me, a.latLng!)
          .compareTo(d.as(LengthUnit.Meter, me, b.latLng!)));
    }

    // Trasy, které mají aspoň jeden POI (pro filtr).
    final routesWithPois = <String, RouteItem>{};
    for (final e in all) {
      routesWithPois[e.route.id] = e.route;
    }

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            _filters(context, lang, routesWithPois.values.toList()),
            Expanded(
              child: all.isEmpty
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
                onTap: () => context.backOr('/routes'),
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

  // ── Filtr tras ──
  Widget _filters(BuildContext context, String lang, List<RouteItem> routes) {
    if (routes.length < 2) return const SizedBox(height: 8);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        children: [
          _routeChip(t(context).tr('poiAllRoutes'), null),
          ...routes.map((r) => _routeChip(r.nameFor(lang), r.id)),
        ],
      ),
    );
  }

  Widget _routeChip(String label, String? id) {
    final active = _routeFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: () => setState(() => _routeFilter = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenDark : Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(color: active ? MotoGoColors.greenDark : MotoGoColors.g200, width: 1.5),
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
                    ? Image.network(e.poi.cover!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumbFallback())
                    : _thumbFallback(),
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
                          const Icon(Icons.route, size: 12, color: MotoGoColors.greenDark),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              e.route.nameFor(lang),
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

  Widget _thumbFallback() => Container(
        color: MotoGoColors.greenPale,
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 26))),
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
                      const Icon(Icons.navigation, size: 18, color: MotoGoColors.black),
                      const SizedBox(width: 8),
                      Text(
                        t(context).tr('poiNavigateThrough'),
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
    final route = buildCustomRoute(pois, from: me, name: t(context).tr('poiCustomRouteTitle'));
    context.push('/route-nav-custom', extra: route);
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
