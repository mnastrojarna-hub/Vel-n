import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/router.dart' show MotoGoBackNav, Routes;
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import 'community_submit.dart';
import 'places_map.dart';
import 'route_poi_sheet.dart';
import 'routes_provider.dart';

/// Celoobrazovková mapa VŠECH míst (bodů zájmu) — trasy se sem nekreslí.
///
/// Otevírá se z rozcestníku Míst i Tras („🧭 Mapa"). Tap na místo otevře jeho
/// detail, dlouhý stisk do mapy nabídne přidání nového místa na daném bodě.
class PlacesMapScreen extends ConsumerStatefulWidget {
  const PlacesMapScreen({super.key});

  @override
  ConsumerState<PlacesMapScreen> createState() => _PlacesMapScreenState();
}

class _PlacesMapScreenState extends ConsumerState<PlacesMapScreen> {
  final GlobalKey<PlacesMapViewState> _mapKey = GlobalKey<PlacesMapViewState>();

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

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final places = ref.watch(allPlacesProvider);
    final me = ref.watch(currentLocationProvider).valueOrNull;
    final loading = ref.watch(catalogPoisProvider).isLoading;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: PlacesMapView(
              key: _mapKey,
              places: places,
              lang: lang,
              me: me,
              initialCenter: me,
              initialZoom: me == null ? 7.2 : 11,
              onPlaceTap: (e) => showRoutePoiSheet(context, e.poi, lang),
              onLongPress: _addPlaceAt,
            ),
          ),
          // Hlavička — zpět, název, počet míst.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
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
                                  : t(context)
                                      .tr('placesMapCount')
                                      .replaceFirst('{n}', '${places.length}'),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Tlačítka: vycentrovat na mě + přidat místo.
          Positioned(
            right: 14,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _round(
                  Icons.my_location,
                  () async {
                    if (me == null) {
                      final ok = await ensureLocation(ref);
                      if (!ok || !mounted) return;
                    }
                    _mapKey.currentState?.centerOnMe();
                  },
                ),
                const SizedBox(height: 10),
                _round(
                  Icons.add_location_alt_outlined,
                  () {
                    final center = me;
                    if (center == null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t(context).tr('placesMapAddHint')),
                      ));
                      return;
                    }
                    _addPlaceAt(center);
                  },
                  primary: true,
                ),
              ],
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
