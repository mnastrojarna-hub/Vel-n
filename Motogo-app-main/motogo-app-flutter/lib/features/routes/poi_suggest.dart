import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'poi_categories.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_image.dart';
import 'route_poi_sheet.dart';

/// Návrhy bodů zájmu v okolí právě skládané trasy (editor trasy).
/// Jakmile má trasa aspoň jednu zastávku, nabídne další body do X km
/// (nastavitelný okruh) od kterékoliv zastávky; navíc filtr dle kategorií.
/// Klepnutím na kartu se bod přidá jako další zastávka.
class NearbyPoiPanel extends ConsumerStatefulWidget {
  /// Aktuální zastávky trasy (od nich se měří okruh).
  final List<LatLng> stops;

  /// Id bodů zájmu, které už v trase jsou (nenabízet znovu).
  final Set<String> excludedPoiIds;

  final void Function(RoutePoi poi) onAdd;

  const NearbyPoiPanel({
    super.key,
    required this.stops,
    required this.excludedPoiIds,
    required this.onAdd,
  });

  @override
  ConsumerState<NearbyPoiPanel> createState() => _NearbyPoiPanelState();
}

class _NearbyPoiPanelState extends ConsumerState<NearbyPoiPanel> {
  static const List<double> _kmOptions = [5, 10, 25, 50];
  static const int _maxCards = 40;

  bool _expanded = true;
  double _radiusKm = 10;
  final Set<String> _cats = {};

  @override
  Widget build(BuildContext context) {
    if (widget.stops.isEmpty) return const SizedBox.shrink();
    final lang = ref.watch(localeProvider).languageCode;

    // Stejné zdroje jako katalog bodů: body z tras + katalog + komunitní.
    final routePois = ref.watch(allPoisProvider);
    final userPois = ref.watch(userPoisProvider).valueOrNull ?? const [];
    final catalogPois = ref.watch(catalogPoisProvider).valueOrNull ?? const [];
    final all = <PoiEntry>[
      ...routePois,
      ...catalogPois.map((p) => PoiEntry(p, null, null, catalog: true)),
      ...userPois.map((p) => PoiEntry(p, null, null)),
    ];

    // Kandidáti v okruhu: min. vzdálenost k libovolné zastávce ≤ X km.
    const dist = Distance();
    double nearest(LatLng ll) {
      var best = double.infinity;
      for (final s in widget.stops) {
        final d = dist.as(LengthUnit.Meter, s, ll);
        if (d < best) best = d;
      }
      return best;
    }

    final seen = <String>{};
    final inRadius = <({PoiEntry e, double m})>[];
    for (final e in all) {
      final ll = e.latLng;
      if (ll == null) continue;
      if (widget.excludedPoiIds.contains(e.poi.id)) continue;
      if (!seen.add(e.poi.id)) continue; // stejný bod ve víc trasách jen 1×
      final m = nearest(ll);
      if (m <= _radiusKm * 1000) inRadius.add((e: e, m: m));
    }
    inRadius.sort((a, b) => a.m.compareTo(b.m));

    // Počty kategorií z okruhu; filtr kategorií nad tím.
    final catCounts = <String, int>{};
    for (final c in inRadius) {
      final k = poiCategoryOf(c.e.poi);
      catCounts[k] = (catCounts[k] ?? 0) + 1;
    }
    final filtered = _cats.isEmpty
        ? inRadius
        : inRadius.where((c) => _cats.contains(poiCategoryOf(c.e.poi))).toList();
    final cards =
        filtered.length > _maxCards ? filtered.sublist(0, _maxCards) : filtered;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerRow(context, filtered.length),
          if (_expanded) ...[
            _chipsRow(context, catCounts),
            if (cards.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  t(context).tr('builderNearbyEmpty'),
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeMd,
                    fontWeight: MotoGoTypo.w600,
                    color: MotoGoColors.g500,
                    decoration: TextDecoration.none,
                  ),
                ),
              )
            else
              SizedBox(
                height: 76,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  itemCount: cards.length,
                  itemBuilder: (context, i) =>
                      _card(context, cards[i].e, cards[i].m, lang),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context, int count) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 4),
        child: Row(
          children: [
            const Icon(Icons.radar, size: 16, color: MotoGoColors.greenDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t(context).tr('builderNearbyTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
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
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 22,
              color: MotoGoColors.g500,
            ),
          ],
        ),
      ),
    );
  }

  // Jeden řádek chipů: okruh (5/10/25/50 km) + kategorie s počty.
  Widget _chipsRow(BuildContext context, Map<String, int> catCounts) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        children: [
          for (final km in _kmOptions)
            _chip(
              label: '${km.round()} km',
              active: _radiusKm == km,
              filled: true,
              onTap: () => setState(() => _radiusKm = km),
            ),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            color: MotoGoColors.g200,
          ),
          for (final c in kPoiCats)
            if ((catCounts[c.key] ?? 0) > 0 || _cats.contains(c.key))
              _chip(
                label:
                    '${c.emoji} ${t(context).tr(c.i18nKey)} ${catCounts[c.key] ?? 0}',
                active: _cats.contains(c.key),
                filled: false,
                onTap: () => setState(() =>
                    _cats.contains(c.key) ? _cats.remove(c.key) : _cats.add(c.key)),
              ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final bg = active
        ? (filled ? MotoGoColors.greenDark : MotoGoColors.greenPale)
        : Colors.white;
    final fg = active
        ? (filled ? Colors.white : MotoGoColors.greenDarker)
        : MotoGoColors.black;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressableScale(
        pressedScale: 0.94,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(
              color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w600,
                color: fg,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Karta návrhu: náhled + název + vzdálenost; klepnutí = přidat do trasy.
  Widget _card(BuildContext context, PoiEntry e, double meters, String lang) {
    final distTxt = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.round()} m';
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PressableScale(
        pressedScale: 0.96,
        onTap: () => widget.onAdd(e.poi),
        child: Container(
          width: 210,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.xl),
            border: Border.all(color: MotoGoColors.g200),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: double.infinity,
                child: e.poi.cover != null
                    ? RouteImage(
                        url: e.poi.cover!,
                        targetWidth: 200,
                        placeholder: (_) => _thumbFallback(),
                        error: (_) => _thumbFallback(),
                      )
                    : _thumbFallback(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        e.poi.nameFor(lang),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MotoGoTypo.sizeMd,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.black,
                          height: 1.15,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.near_me,
                              size: 11, color: MotoGoColors.g400),
                          const SizedBox(width: 3),
                          Text(
                            distTxt,
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeSm,
                              fontWeight: MotoGoTypo.w700,
                              color: MotoGoColors.g500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () =>
                                showRoutePoiSheet(context, e.poi, lang),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.info_outline,
                                  size: 15, color: MotoGoColors.g400),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: MotoGoColors.greenDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
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
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 20))),
      );
}
