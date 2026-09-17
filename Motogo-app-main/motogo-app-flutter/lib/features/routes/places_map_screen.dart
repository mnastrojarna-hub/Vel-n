import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart' show MotoGoBackNav, Routes;
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import 'community_submit.dart';
import 'places_filter.dart';
import 'routes_model.dart';
import 'places_map.dart';
import 'route_poi_sheet.dart';
import 'routes_provider.dart';

/// Celoobrazovková mapa MÍST — trasy se sem nekreslí.
///
/// Otevírá se z rozcestníku Míst i z Tras („🧭 Mapa"). Ukazuje přesně ta místa,
/// která projdou AKTUÁLNÍM filtrem (sdílený `placesFilterProvider`), takže
/// odpovídá tomu, co má uživatel zrovna nastavené v seznamu. Klepnutím se
/// místo přidá do výběru a ze spodní lišty se z výběru poskládá trasa.
class PlacesMapScreen extends ConsumerStatefulWidget {
  const PlacesMapScreen({super.key});

  @override
  ConsumerState<PlacesMapScreen> createState() => _PlacesMapScreenState();
}

class _PlacesMapScreenState extends ConsumerState<PlacesMapScreen> {
  final GlobalKey<PlacesMapViewState> _mapKey = GlobalKey<PlacesMapViewState>();

  // Memoizace filtrovaného seznamu: klepnutí na marker mění jen VÝBĚR,
  // a ten na výsledek filtru nemá vliv, dokud není zapnuté „v okolí".
  // Bez toho se při každém tapu procházel celý katalog znovu.
  List<PoiEntry>? _cache;
  List<PoiEntry>? _cacheBase;
  PlacesFilter? _cacheFilter;
  LatLng? _cacheMe;
  Set<String>? _cacheSel;

  List<PoiEntry> _filtered(List<PoiEntry> base, List<PoiEntry> all,
      PlacesFilter f, Set<String> selected, LatLng? me) {
    final selKey = f.nearbyOn ? selected : null;
    if (_cache != null &&
        identical(_cacheBase, base) &&
        _cacheFilter == f &&
        _cacheMe == me &&
        _sameSel(_cacheSel, selKey)) {
      return _cache!;
    }
    final out = applyPlacesFilter(base, f,
        all: all, selected: selected, me: me);
    _cache = out;
    _cacheBase = base;
    _cacheFilter = f;
    _cacheMe = me;
    _cacheSel = selKey == null ? null : {...selKey};
    return out;
  }

  static bool _sameSel(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.length == b.length && a.containsAll(b);
  }

  @override
  void initState() {
    super.initState();
    // Mapa je celá o poloze — vyžádat si ji hned po otevření je očekávané.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureLocation(ref);
    });
  }

  Future<void> _addPlaceAt(LatLng p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PoiSubmitScreen(initialPoint: p),
    ));
    if (mounted) ref.invalidate(userPoisProvider);
  }

  /// Sestaví z vybraných míst trasu a otevře editor — stejná akce jako spodní
  /// lišta v seznamu Míst, aby šlo trasu poskládat i čistě z mapy.
  void _buildRoute(LatLng? me) {
    // Body se dohledávají ve VŠECH místech, ne jen v právě zobrazených —
    // jinak by se vybrané místo, které mezitím vypadlo z filtru, tiše
    // zahodilo a tlačítko by nedělalo nic.
    final selected = ref.read(placesSelectionProvider);
    final pois = resolveSelected(
      ref.read(dedupedPlacesProvider),
      ref.read(allPlacesProvider),
      selected,
    );
    if (pois.isEmpty) return;
    // Po předání do editoru výběr uklidíme, ať se nevrací na jiné obrazovce.
    ref.read(placesSelectionProvider.notifier).clear();
    final route = buildCustomRoute(pois,
        from: me, name: t(context).tr('poiCustomRouteTitle'));
    context.push('/route-build', extra: route);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final filter = ref.watch(placesFilterProvider);
    final selected = ref.watch(placesSelectionProvider);
    final me = ref.watch(currentLocationProvider).valueOrNull;
    final loading = ref.watch(catalogPoisProvider).isLoading;

    // Stejný zdroj i stejný filtr jako seznam Míst — mapa tak nikdy neukáže
    // jiný počet ani jiné klíče. Při filtru na konkrétní trasu se (stejně
    // jako v seznamu) NEdeduplikuje, jinak by z mapy zmizela místa, jejichž
    // reprezentantem se stal bod z jiné trasy nebo z katalogu.
    final all = ref.watch(allPlacesProvider);
    final base = filter.routeId == null
        ? ref.watch(dedupedPlacesProvider)
        : all;
    final places = _filtered(base, all, filter, selected, me);
    final chips = filter.summary();

    // Trasy se na mapě míst NEKRESLÍ, dokud uživatel nějaké místo neoznačí.
    // Pak se objeví jen ty, které vybraná místa obsahují.
    final allRoutes =
        ref.watch(routesDataProvider).valueOrNull?.routes ?? const <RouteItem>[];
    final matched = routesContaining(allRoutes, places, selected);
    final lines = [for (final r in matched) routeLine(r)];

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: PlacesMapView(
              key: _mapKey,
              places: places,
              lang: lang,
              selected: selected,
              routeLines: lines,
              me: me,
              initialCenter: me,
              initialZoom: me == null ? 7.2 : 11,
              onPlaceTap: (e) =>
                  ref.read(placesSelectionProvider.notifier).toggle(e.key),
              onPlaceLongPress: (e) => showRoutePoiSheet(context, e.poi, lang,
                  siblings: [
                    for (final x in siblingWindow(places, places.indexOf(e)))
                      x.poi
                  ]),
              onLongPress: _addPlaceAt,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
                bottom: false,
                child: _header(context, places, loading, chips, matched.length)),
          ),
          Positioned(
            right: 14,
            bottom: selected.isEmpty ? 24 : 104,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _round(Icons.my_location, () async {
                  if (me == null) {
                    final ok = await ensureLocation(ref);
                    if (!ok || !mounted) return;
                  }
                  _mapKey.currentState?.centerOnMe();
                }),
                const SizedBox(height: 10),
                _round(Icons.add_location_alt_outlined, () {
                  final center = me;
                  if (center == null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(t(context).tr('placesMapAddHint')),
                    ));
                    return;
                  }
                  _addPlaceAt(center);
                }, primary: true),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: selected.isEmpty ? null : _selectionBar(context, me),
    );
  }

  Widget _header(BuildContext context, List<PoiEntry> places, bool loading,
      List<String> chips, int matchedRoutes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: MotoGoColors.dark,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.backOr(Routes.routes),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 6),
            const Text('🧭', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t(context).tr('placesMapTitle'),
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w900,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    loading
                        ? t(context).tr('placesMapLoading')
                        : [
                            '${t(context).tr('placesMapCount')} · ${places.length}',
                            ...chips,
                            if (matchedRoutes > 0)
                              '${t(context).tr('placesMapRoutes')} · $matchedRoutes',
                          ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeSm,
                      fontWeight: MotoGoTypo.w600,
                      color: Color(0xFF8AAB99),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            // Zrušit filtr přímo z mapy — jinak by se uživatel musel vracet
            // do seznamu, aby zase viděl všechna místa.
            if (chips.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  ref.read(placesFilterProvider.notifier).clear();
                  ref.read(placesSearchProvider.notifier).state = '';
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Icon(Icons.filter_alt_off,
                      color: MotoGoColors.green, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context, LatLng? me) {
    final n = ref.watch(placesSelectionProvider).length;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration:
          BoxDecoration(color: Colors.white, boxShadow: MotoGoShadows.stickyBar),
      child: Row(
        children: [
          GestureDetector(
            onTap: ref.read(placesSelectionProvider.notifier).clear,
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
              onTap: () => _buildRoute(me),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  boxShadow: [
                    BoxShadow(
                        color: MotoGoColors.green.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.navigation,
                          size: 18, color: MotoGoColors.black),
                      const SizedBox(width: 8),
                      Text(
                        t(context).tr('poiContinue'),
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

  Widget _round(IconData icon, VoidCallback onTap, {bool primary = false}) {
    return PressableScale(
      pressedScale: 0.92,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: primary ? MotoGoColors.green : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon,
            size: 22,
            color: primary ? MotoGoColors.black : MotoGoColors.greenDark),
      ),
    );
  }
}
