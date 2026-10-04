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
import 'routes_map_picker.dart';
import 'routes_map_provider.dart';
import 'routes_model.dart';
import 'routes_provider.dart';

/// MAPA TRAS — na rozdíl od mapy míst ukazuje jen body, které leží na nějaké
/// trase, a po klepnutí na bod dokreslí JEHO trasy, a to PO SILNICI.
///
/// Zadání uživatele: „Na mapě tras by měly být zobrazeny jenom body, které
/// jsou součástí nějaké trasy… body tras musí mít jinou barvu. Neměla by tam
/// být změť všech tras — trasa se ukáže, až když kliknu na bod. A musí se
/// zobrazovat po silnici, ne přímá vzdálenost."
///
/// Doplnění 2026-10-04: bod může ležet na VÍCE trasách — dřív se kreslila jen
/// jedna a přepínala se čipem v hlavičce, takže „když vyberu místo, přes které
/// vedou dvě trasy, ukáže mi to jen jednu a nemůžu si vybrat, kterou pojedu".
/// Teď se kreslí všechny trasy vybraného bodu (každá jinou barvou, se
/// štítkem názvu přímo na čáře) a dole je panel s kartou pro každou —
/// klepnutí (na kartu i na štítek) trasu zvýrazní a přiblíží, „Detail" otevře
/// její stránku; čip „Další trasa" nahoře zůstává jako rychlé přepínání.
class RoutesMapScreen extends ConsumerStatefulWidget {
  const RoutesMapScreen({super.key});

  @override
  ConsumerState<RoutesMapScreen> createState() => _RoutesMapScreenState();
}

class _RoutesMapScreenState extends ConsumerState<RoutesMapScreen> {
  final GlobalKey<PlacesMapViewState> _mapKey = GlobalKey<PlacesMapViewState>();

  /// Ukázat i místa mimo trasy (bíle) — ve výchozím stavu ne.
  bool _withOtherPlaces = false;

  /// Zvýrazněná trasa z panelu dole / štítku na mapě / čipu „Další trasa"
  /// (null = první z nalezených).
  String? _activeId;

  /// Zvýrazní trasu a přiblíží mapu na její čáru (když už je spočtená).
  void _pickRoute(String id, List<LatLng>? pts) {
    setState(() => _activeId = id);
    if (pts != null && pts.length >= 2) {
      // Tělo Scaffoldu sahá i pod spodní panel (proto mají tlačítka offset
      // 104) — dole se nechá místo na panel s kartami i lištu výběru, nahoře
      // na hlavičku.
      _mapKey.currentState?.fitTo(pts,
          padding: const EdgeInsets.fromLTRB(
              36, 130, 36, kRoutesMapPickerHeight + 110));
    }
  }

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

    // Trasy vybraných bodů — VŠECHNY (bod může ležet na více trasách), každá
    // svou barvou; zvýrazněná se kreslí navrch. Čáry po silnici počítá
    // provider s cache; když routing selže, čára se nekreslí (žádné rovné
    // spojnice). Bez vybraného bodu se nekreslí nic — žádná změť všech tras.
    final data = ref.watch(routesDataProvider).valueOrNull;
    final allRoutes = data?.routes ?? const <RouteItem>[];
    final matched = routesForSelection(allRoutes, places, selected);
    final active = matched.isEmpty
        ? null
        : matched.firstWhere((r) => r.id == _activeId,
            orElse: () => matched.first);
    final lineOf = <String, List<LatLng>>{};
    final computingIds = <String>{};
    final lines = <MapRouteLine>[];
    for (var i = 0; i < matched.length; i++) {
      final r = matched[i];
      final lineAsync = ref.watch(routeRoadLineProvider(r.id));
      if (lineAsync.isLoading && !lineAsync.hasValue) {
        computingIds.add(r.id);
        continue;
      }
      final pts = lineAsync.valueOrNull ?? const <LatLng>[];
      lineOf[r.id] = pts;
      if (pts.length >= 2) {
        final isActive = r.id == active?.id;
        lines.add(MapRouteLine(
          pts,
          color: routesMapColor(i),
          width: isActive ? 5 : 4,
          emphasized: isActive,
          // Štítek s názvem přímo na čáře — výběr trasy je vidět na mapě.
          label: r.nameFor(lang),
          onTap: () => _pickRoute(r.id, pts),
        ));
      }
    }
    // Čip „Další trasa" v hlavičce: cyklicky další z tras vybraného bodu.
    final activeAt =
        active == null ? -1 : matched.indexWhere((r) => r.id == active.id);
    final VoidCallback? onNext = matched.length > 1
        ? () {
            final next = matched[(activeAt + 1) % matched.length];
            _pickRoute(next.id, lineOf[next.id]);
          }
        : null;
    final activeLabel = active == null
        ? null
        : '${active.nameFor(lang)}'
            '${matched.length > 1 ? '  (${activeAt + 1}/${matched.length})' : ''}';
    // Panel s kartami tras zabírá dole místo — tlačítka a čip nad něj.
    final bottomPad = selected.isEmpty
        ? 24.0
        : (matched.isEmpty ? 104.0 : 104.0 + kRoutesMapPickerHeight);

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
              routeLines: lines,
              draftLine: draft?.geometry ?? const [],
              me: me,
              initialCenter: me,
              initialZoom: me == null ? 7.2 : 11,
              onPlaceTap: (e) {
                setState(() => _activeId = null);
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
              child: _header(context, places.length, activeLabel,
                  computingIds.isNotEmpty, onNext),
            ),
          ),
          // Čip „Tvoje trasa" — zůstane i po návratu z editoru.
          if (draft != null && draft.geometry.length >= 2)
            Positioned(
              left: 14,
              bottom: bottomPad,
              child: _draftChip(context, draft),
            ),
          Positioned(
            right: 14,
            bottom: bottomPad,
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
      bottomSheet: selected.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (matched.isNotEmpty)
                  RoutesMapPicker(
                    routes: matched,
                    branches: data?.branches ?? const {},
                    lang: lang,
                    activeId: active?.id,
                    lines: lineOf,
                    computing: computingIds,
                    onPick: (r) => _pickRoute(r.id, lineOf[r.id]),
                    onOpen: (r) {
                      // Stejně jako karta v seznamu tras: zapamatovat zvolenou
                      // trasu a předat sousedy pro listování swipem.
                      ref.read(lastOpenedRouteProvider.notifier).state = r.id;
                      context.push('/routes/${r.id}',
                          extra: [for (final x in matched) x.id]);
                    },
                  ),
                _selectionBar(context, me),
              ],
            ),
    );
  }

  Widget _header(BuildContext context, int count, String? activeLabel,
      bool computing, VoidCallback? onNext) {
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
                            : (activeLabel ??
                                '${t(context).tr('routesMapCount')} · $count'),
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
                // Další trasa vybraného bodu — rychlé přepínání nahoře
                // (uživatel: „nahoře to může zůstat, ale musí to přibýt dole").
                if (onNext != null)
                  _miniBtn(Icons.alt_route, t(context).tr('routesMapNextRoute'),
                      onNext),
                if (onNext != null) const SizedBox(width: 8),
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
