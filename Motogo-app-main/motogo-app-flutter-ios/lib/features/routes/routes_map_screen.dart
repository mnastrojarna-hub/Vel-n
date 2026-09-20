import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart' show MotoGoBackNav, Routes;
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import 'places_filter.dart';
import 'places_map.dart';
import 'route_poi_sheet.dart';
import 'routes_map_provider.dart';
import 'routes_model.dart';
import 'routes_provider.dart';

/// MAPA TRAS — na rozdíl od mapy míst ukazuje jen body, které leží na nějaké
/// trase, a po klepnutí na bod dokreslí JEHO trasu, a to PO SILNICI.
///
/// Zadání uživatele: „Na mapě tras by měly být zobrazeny jenom body, které
/// jsou součástí nějaké trasy… body tras musí mít jinou barvu. Neměla by tam
/// být změť všech tras — trasa se ukáže, až když kliknu na bod. A musí se
/// zobrazovat po silnici, ne přímá vzdálenost."
class RoutesMapScreen extends ConsumerStatefulWidget {
  const RoutesMapScreen({super.key});

  @override
  ConsumerState<RoutesMapScreen> createState() => _RoutesMapScreenState();
}

class _RoutesMapScreenState extends ConsumerState<RoutesMapScreen> {
  final GlobalKey<PlacesMapViewState> _mapKey = GlobalKey<PlacesMapViewState>();

  /// Ukázat i místa mimo trasy (bíle) — ve výchozím stavu ne.
  bool _withOtherPlaces = false;

  /// Která z tras vybraného bodu se kreslí (bod může ležet na více trasách).
  int _routeAt = 0;

  // Memoizace filtrovaného seznamu — klepnutí na marker mění jen výběr.
  List<PoiEntry>? _cache;
  List<PoiEntry>? _cacheBase;
  PlacesFilter? _cacheFilter;
  LatLng? _cacheMe;

  List<PoiEntry> _filtered(
      List<PoiEntry> base, List<PoiEntry> all, PlacesFilter f, LatLng? me) {
    if (_cache != null &&
        identical(_cacheBase, base) &&
        _cacheFilter == f &&
        _cacheMe == me) {
      return _cache!;
    }
    final out = applyPlacesFilter(base, f,
        all: all, selected: const {}, me: me, ordered: false);
    _cache = out;
    _cacheBase = base;
    _cacheFilter = f;
    _cacheMe = me;
    return out;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureLocation(ref);
    });
  }

  void _openDetail(BuildContext context, PoiEntry e, List<PoiEntry> places,
      String lang) {
    final window = siblingWindow(places, places.indexOf(e));
    final keyOf = <String, String>{for (final x in window) x.poi.id: x.key};
    showRoutePoiSheet(
      context,
      e.poi,
      lang,
      siblings: [for (final x in window) x.poi],
      isSelected: (p) {
        final k = keyOf[p.id];
        return k != null && ref.read(placesSelectionProvider).contains(k);
      },
      onToggleSelect: (p) {
        final k = keyOf[p.id];
        if (k != null) ref.read(placesSelectionProvider.notifier).toggle(k);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final filter = ref.watch(placesFilterProvider);
    final selected = ref.watch(placesSelectionProvider);
    final me = ref.watch(currentLocationProvider).valueOrNull;
    final draft = ref.watch(draftRouteProvider);

    final all = ref.watch(allPlacesProvider);
    // Výchozí zdroj = JEN body tras; ostatní místa se přidají přepínačem.
    final base = _withOtherPlaces
        ? ref.watch(dedupedPlacesProvider)
        : ref.watch(dedupedRoutePlacesProvider);
    final places = _filtered(base, all, filter, me);

    // Trasy vybraných bodů — kreslí se VŽDY JEN JEDNA (žádná změť).
    final allRoutes =
        ref.watch(routesDataProvider).valueOrNull?.routes ?? const <RouteItem>[];
    final matched = routesForSelection(allRoutes, places, selected);
    final at = matched.isEmpty ? 0 : _routeAt % matched.length;
    final shown = matched.isEmpty ? null : matched[at];
    // Čára po silnici (cache v provideru; při chybě routingu se nekreslí nic).
    final lineAsync = shown == null
        ? null
        : ref.watch(routeRoadLineProvider(shown.id));
    final line = lineAsync?.valueOrNull ?? const <LatLng>[];

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: PlacesMapView(
              attributionOnLeft: true,
              key: _mapKey,
              places: places,
              lang: lang,
              selected: selected,
              markRouteStops: true,
              routeLines: line.length >= 2 ? [line] : const [],
              draftLine: draft?.geometry ?? const [],
              me: me,
              initialCenter: me,
              initialZoom: me == null ? 7.2 : 11,
              onPlaceTap: (e) {
                setState(() => _routeAt = 0);
                ref.read(placesSelectionProvider.notifier).toggle(e.key);
              },
              onPlaceLongPress: (e) => _openDetail(context, e, places, lang),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _header(context, places.length, matched, at,
                  lineAsync?.isLoading ?? false),
            ),
          ),
          // Čip „Tvoje trasa" — zůstane i po návratu z editoru.
          if (draft != null && draft.geometry.length >= 2)
            Positioned(
              left: 14,
              bottom: selected.isEmpty ? 24 : 104,
              child: _draftChip(context, draft),
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
              ],
            ),
          ),
        ],
      ),
      bottomSheet: selected.isEmpty ? null : _selectionBar(context, me),
    );
  }

  Widget _header(BuildContext context, int count, List<RouteItem> matched,
      int at, bool computing) {
    final lang = ref.watch(localeProvider).languageCode;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.backOr(Routes.routesList),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('🗺️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t(context).tr('routesMapTitle'),
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w900,
                          color: Colors.white,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        computing
                            ? t(context).tr('routesMapComputing')
                            : (matched.isEmpty
                                ? '${t(context).tr('routesMapCount')} · $count'
                                : '${matched[at].nameFor(lang)}'
                                    '${matched.length > 1 ? '  (${at + 1}/${matched.length})' : ''}'),
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
                // Přepnutí na mapu míst.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pushReplacement(Routes.placesMap),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.explore_outlined,
                            size: 16, color: MotoGoColors.green),
                        const SizedBox(width: 4),
                        Text(
                          t(context).tr('placesMapBtn'),
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeSm,
                            fontWeight: MotoGoTypo.w800,
                            color: MotoGoColors.green,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Další trasa vybraného bodu (bod může ležet na více trasách).
                if (matched.length > 1)
                  _miniBtn(
                    Icons.alt_route,
                    t(context).tr('routesMapNextRoute'),
                    () => setState(() => _routeAt = at + 1),
                  ),
                if (matched.length > 1) const SizedBox(width: 8),
                _miniBtn(
                  _withOtherPlaces ? Icons.layers_clear : Icons.layers,
                  t(context).tr(_withOtherPlaces
                      ? 'routesMapOnlyRoutes'
                      : 'routesMapShowOther'),
                  () => setState(() {
                    _withOtherPlaces = !_withOtherPlaces;
                    _cache = null;
                  }),
                ),
                const Spacer(),
                Text(
                  t(context).tr('routesMapTapHint'),
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
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(IconData icon, String label, VoidCallback onTap) {
    return PressableScale(
      pressedScale: 0.95,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: MotoGoColors.green),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeSm,
                fontWeight: MotoGoTypo.w800,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draftChip(BuildContext context, DraftRoute draft) {
    final km = draft.lengthM == null
        ? null
        : (draft.lengthM! / 1000).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.pill),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.navigation, size: 15, color: MotoGoColors.greenDarker),
          const SizedBox(width: 6),
          Text(
            km == null
                ? t(context).tr('routesMapDraft')
                : '${t(context).tr('routesMapDraft')} · $km km',
            style: const TextStyle(
              fontSize: MotoGoTypo.sizeMd,
              fontWeight: MotoGoTypo.w800,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(draftRouteProvider.notifier).clear(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Icon(Icons.close, size: 15, color: MotoGoColors.g400),
            ),
          ),
        ],
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
              onTap: () {
                final pois = resolveSelected(
                  ref.read(dedupedPlacesProvider),
                  ref.read(allPlacesProvider),
                  ref.read(placesSelectionProvider),
                );
                if (pois.isEmpty) return;
                ref.read(placesSelectionProvider.notifier).clear();
                final route = buildCustomRoute(pois,
                    from: me, name: t(context).tr('poiCustomRouteTitle'));
                context.push('/route-build', extra: route);
              },
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                ),
                child: Center(
                  child: Text(
                    t(context).tr('poiContinue'),
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
    );
  }

  Widget _round(IconData icon, VoidCallback onTap) {
    return PressableScale(
      pressedScale: 0.92,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: MotoGoColors.greenDark),
      ),
    );
  }
}
