import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_map.dart';
import 'route_export.dart';

class RouteDetailScreen extends ConsumerStatefulWidget {
  final String routeId;
  const RouteDetailScreen({super.key, required this.routeId});

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  int? _activePoi;

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final dataAsync = ref.watch(routesDataProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.greenDark)),
        error: (e, _) => _missing(context),
        data: (data) {
          final route = data.routes.firstWhere(
            (r) => r.id == widget.routeId,
            orElse: () => const RouteItem(id: '', name: ''),
          );
          if (route.id.isEmpty) return _missing(context);
          final branch = route.branchId != null ? data.branches[route.branchId] : null;
          return _content(context, route, branch, lang);
        },
      ),
    );
  }

  Widget _content(BuildContext context, RouteItem route, RouteBranch? branch, String lang) {
    final geoAsync = ref.watch(routeGeometryProvider(route.id));
    final geometry = geoAsync.valueOrNull ?? route.geometry;
    final poiMarkers = <({LatLng point, int index})>[];
    for (var i = 0; i < route.pois.length; i++) {
      final ll = route.pois[i].latLng;
      if (ll != null) poiMarkers.add((point: ll, index: i));
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ── Mapa (fixní horní část) ──
          SizedBox(
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RouteMapView(
                    geometry: geometry,
                    start: branch?.latLng,
                    pois: poiMarkers,
                    activePoi: _activePoi,
                  ),
                ),
                if (geoAsync.isLoading && route.geometry.isEmpty)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: _MapLoadingChip(),
                  ),
                // Back button
                Positioned(
                  top: 10,
                  left: 12,
                  child: PressableScale(
                    pressedScale: 0.9,
                    onTap: () => context.backOr('/routes'),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(MotoGoRadius.lg),
                        boxShadow: MotoGoShadows.cardSmall,
                      ),
                      child: const Icon(Icons.arrow_back, size: 20, color: MotoGoColors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Obsah (scroll) ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                _titleBlock(context, route, branch, lang),
                if ((route.descFor(lang) ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    route.descFor(lang)!,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      height: 1.5,
                      color: MotoGoColors.g600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
                if (route.pois.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle(t(context).tr('routePoisHeader')),
                  const SizedBox(height: 10),
                  _poiCarousel(context, route, lang),
                ],
                if (route.images.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle(t(context).tr('routeGalleryHeader')),
                  const SizedBox(height: 10),
                  _gallery(route),
                ],
              ],
            ),
          ),
          // ── Spodní lišta „Zvolit → navigace" ──
          _buildExportBar(context, route, branch),
        ],
      ),
    );
  }

  Widget _titleBlock(BuildContext context, RouteItem route, RouteBranch? branch, String lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          route.nameFor(lang),
          style: const TextStyle(
            fontSize: MotoGoTypo.sizeHero,
            fontWeight: MotoGoTypo.w900,
            color: MotoGoColors.black,
            decoration: TextDecoration.none,
          ),
        ),
        if (branch != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.flag, size: 15, color: MotoGoColors.greenDark),
                const SizedBox(width: 4),
                Text(
                  '${t(context).tr('routeStartsAt')} ${branch.name}',
                  style: const TextStyle(
                    fontSize: MotoGoTypo.sizeBase,
                    fontWeight: MotoGoTypo.w600,
                    color: MotoGoColors.g600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(route.isLoop ? '🔄' : '📍',
                route.isLoop ? t(context).tr('routeTypeLoop') : t(context).tr('routeTypePoi')),
            if (route.distanceKm != null)
              _chip('📏', '${route.distanceKm!.toStringAsFixed(0)} km'),
            if (route.durationMin != null) _chip('⏱️', _dur(route.durationMin!)),
            if (route.difficulty != null) _chip('⛰️', _diff(context, route.difficulty!)),
          ],
        ),
      ],
    );
  }

  Widget _poiCarousel(BuildContext context, RouteItem route, String lang) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: route.pois.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = route.pois[i];
          final active = _activePoi == i;
          return PressableScale(
            pressedScale: 0.96,
            onTap: () => setState(() => _activePoi = active ? null : i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(MotoGoRadius.card),
                border: Border.all(
                  color: active ? MotoGoColors.greenDark : MotoGoColors.g200,
                  width: active ? 2 : 1,
                ),
                boxShadow: MotoGoShadows.cardSmall,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 108,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (p.cover != null)
                          Image.network(p.cover!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _poiFallback())
                        else
                          _poiFallback(),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: MotoGoColors.greenDarker,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: MotoGoTypo.w900,
                                      color: Colors.white,
                                      decoration: TextDecoration.none)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nameFor(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeLg,
                            fontWeight: MotoGoTypo.w800,
                            color: MotoGoColors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if ((p.descFor(lang) ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              p.descFor(lang)!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                color: MotoGoColors.g500,
                                height: 1.35,
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
          );
        },
      ),
    );
  }

  Widget _gallery(RouteItem route) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: route.images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
          child: Image.network(
            route.images[i],
            width: 170,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 170,
              color: MotoGoColors.greenPale,
              child: const Center(child: Text('🏞️', style: TextStyle(fontSize: 28))),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom export bar ──
  Widget _buildExportBar(BuildContext context, RouteItem route, RouteBranch? branch) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: MotoGoShadows.stickyBar),
      child: SizedBox(
        height: 52,
        child: PressableScale(
          pressedScale: 0.97,
          onTap: () => _openExportSheet(context, route, branch),
          child: ShimmerSweep(
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            child: Container(
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                boxShadow: [
                  BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.navigation, size: 20, color: MotoGoColors.black),
                    const SizedBox(width: 8),
                    Text(
                      t(context).tr('routeNavigate'),
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeXl,
                        fontWeight: MotoGoTypo.w800,
                        color: MotoGoColors.black,
                        letterSpacing: MotoGoTypo.lsMedium,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openExportSheet(BuildContext context, RouteItem route, RouteBranch? branch) {
    final points = orderedRoutePoints(route, branch);
    if (points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context).tr('routeNoNavData'))),
      );
      return;
    }
    final targets = RouteExport.targets();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(c).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MotoGoColors.g200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              t(context).tr('routeOpenIn'),
              style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800),
            ),
            const SizedBox(height: 14),
            ...targets.map((tg) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: PressableScale(
                      pressedScale: 0.97,
                      onTap: () async {
                        Navigator.pop(c);
                        final ok = await RouteExport.open(tg, points);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t(context).tr('routeOpenFailed'))),
                          );
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: MotoGoColors.greenPale,
                          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                          border: Border.all(color: MotoGoColors.green, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '${tg.emoji}  ${tg.label}',
                            style: const TextStyle(
                              fontSize: MotoGoTypo.sizeLg,
                              fontWeight: MotoGoTypo.w800,
                              color: MotoGoColors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── helpers ──
  static String _dur(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  String _diff(BuildContext context, String d) => switch (d) {
        'easy' => t(context).tr('routeDiffEasy'),
        'medium' => t(context).tr('routeDiffMedium'),
        'hard' => t(context).tr('routeDiffHard'),
        _ => d,
      };

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: MotoGoTypo.sizeH3,
          fontWeight: MotoGoTypo.w900,
          color: MotoGoColors.black,
          decoration: TextDecoration.none,
        ),
      );

  Widget _chip(String emoji, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(MotoGoRadius.pill),
        ),
        child: Text(
          '$emoji  $text',
          style: const TextStyle(
            fontSize: MotoGoTypo.sizeBase,
            fontWeight: MotoGoTypo.w700,
            color: MotoGoColors.greenDarker,
            decoration: TextDecoration.none,
          ),
        ),
      );

  Widget _poiFallback() => Container(
        color: MotoGoColors.greenPale,
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 30))),
      );

  Widget _missing(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wrong_location, size: 48, color: MotoGoColors.g400),
            const SizedBox(height: 12),
            Text(t(context).tr('routeNotFound'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.backOr('/routes'),
              child: Text(t(context).tr('routesRetry')),
            ),
          ],
        ),
      );
}

/// Drobný indikátor „počítám trasu" při živém dopočtu geometrie z Mapy.com.
class _MapLoadingChip extends StatelessWidget {
  const _MapLoadingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.pill),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.greenDark),
          ),
          SizedBox(width: 8),
          Text(
            'Počítám trasu…',
            style: TextStyle(
              fontSize: MotoGoTypo.sizeMd,
              fontWeight: MotoGoTypo.w700,
              color: MotoGoColors.black,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
