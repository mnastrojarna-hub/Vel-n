import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_ai_fab.dart';
import '../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../route_map.dart';
import '../route_poi_sheet.dart' show openPoiImageViewer;
import '../route_reviews.dart';
import '../routes_model.dart';
import 'route_detail_parts_v2.dart';
import 'rt_v2_text.dart';

/// v2 route detail (board TrasaDetail): the EXISTING route map as the hero
/// (photo-style back, "Zobrazit na mapě", "počítám" chip), the one dark stats
/// card overlapping it, then light sections (description, Místa na trase,
/// Galerie, Recenze) and the dark dock with "ZVOLIT TRASU – NAVIGOVAT"
/// (+ docked AI) and the two existing secondary actions. A dumb view: every
/// value and callback comes from `_RouteDetailScreenState` (seam).
class RouteDetailViewV2 extends StatelessWidget {
  final RouteItem route;
  final RouteBranch? branch;
  final bool startNear;
  final String lang;
  final List<LatLng> geometry;
  final LatLng? start;
  final List<({LatLng point, int index})> poiMarkers;
  final List<RoutePoi> pois;
  final int? activePoi;
  final bool computing;
  final double? realKm;
  final ({double km, int min, bool exact})? approach;
  final (int, int)? sibling;
  final VoidCallback onBack;
  final ValueChanged<int> onPoiTap;
  final VoidCallback onFullMap;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onNavigate;
  final VoidCallback? onCustomize;
  final VoidCallback onExternal;

  const RouteDetailViewV2({
    super.key,
    required this.route,
    required this.branch,
    required this.startNear,
    required this.lang,
    required this.geometry,
    required this.start,
    required this.poiMarkers,
    required this.pois,
    required this.activePoi,
    required this.computing,
    required this.realKm,
    required this.approach,
    required this.sibling,
    required this.onBack,
    required this.onPoiTap,
    required this.onFullMap,
    required this.onPrev,
    required this.onNext,
    required this.onNavigate,
    required this.onCustomize,
    required this.onExternal,
  });

  static const double _mapH = 280;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final top = MediaQuery.paddingOf(context).top;
    final distKm = realKm ?? route.distanceKm;
    final a = approach;
    final fromMe = a == null
        ? null
        : '${tr.tr('routeFromMe')} ${a.exact ? '' : '~'}${a.km.round()} km · ${a.exact ? '' : '~'}${rtDur(a.min)}';
    final desc = route.descFor(lang) ?? '';
    final inShell = MgChromeScope.maybeOf(context)?.navVisible ?? false;

    final dock = MgDock(
      safeArea: !inShell,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: MgFabAvoid(child: MgCta(label: tr.tr('routeNavigate'), loop: true, onTap: onNavigate)),
          ),
          const SizedBox(width: 8),
          const MgAiDisc(size: 56),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          if (onCustomize != null)
            Expanded(child: MgBtnText(label: tr.tr('routeCustomize'), icon: MgIcons.edit, dark: true, onTap: onCustomize)),
          Expanded(child: MgBtnText(label: tr.tr('routeNavExternal'), icon: MgIcons.external, dark: true, onTap: onExternal)),
        ]),
      ]),
    );

    return ColoredBox(
      color: MgColors.canvas,
      child: _DetailBody(
        mapH: _mapH + top,
        map: Stack(children: [
          Positioned.fill(
            child: RouteMapView(
              geometry: geometry,
              start: start,
              pois: poiMarkers,
              activePoi: activePoi,
              onPoiTap: onPoiTap,
            ),
          ),
          Positioned(top: top + 10, left: 12, child: MgV2Back(onTap: onBack, style: MgBackStyle.photo)),
          if (computing)
            Positioned(
              top: top + 14,
              right: 12,
              left: 72,
              child: Align(alignment: Alignment.centerRight, child: _ComputingChip(label: tr.tr('routeNavComputing'))),
            ),
          Positioned(
            right: 12,
            bottom: 36,
            child: _MapPill(label: tr.tr('routeShowOnMap'), onTap: onFullMap),
          ),
        ]),
        dock: dock,
        children: [
          RouteStatsCardV2(
            route: route,
            name: route.nameFor(lang),
            startLine: branch != null && startNear ? '${tr.tr('routeStartsAt')} ${branch!.name}' : null,
            km: distKm == null ? null : '${distKm.toStringAsFixed(0)} km',
            time: route.durationMin == null ? null : rtDur(route.durationMin!),
            fromMe: fromMe,
            sibling: sibling,
            onPrev: onPrev,
            onNext: onNext,
          ),
          if (desc.isNotEmpty) RouteDescV2(desc),
          if (pois.isNotEmpty) ...[
            RtSectionV2(icon: MgIcons.pin, title: tr.tr('routePoisHeader'), count: pois.length),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                clipBehavior: Clip.none,
                itemCount: pois.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => RoutePoiCardV2(
                  poi: pois[i],
                  number: i + 1,
                  lang: lang,
                  active: activePoi == i,
                  onTap: () => onPoiTap(i),
                ),
              ),
            ),
          ],
          if (route.images.isNotEmpty) ...[
            RtSectionV2(icon: MgIcons.image, title: tr.tr('routeGalleryHeader'), count: route.images.length),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: route.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => RouteGalleryThumbV2(
                  url: route.images[i],
                  onTap: () => openPoiImageViewer(context, route.images, i, lang),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: RouteReviewsSection(routeId: route.id),
          ),
        ],
      ),
    );
  }
}

/// Map hero fixed on top, the content scrolling from 24 px over its bottom
/// edge (the dark card overlaps the map), dock at the bottom.
class _DetailBody extends StatefulWidget {
  final double mapH;
  final Widget map;
  final Widget dock;
  final List<Widget> children;
  const _DetailBody({required this.mapH, required this.map, required this.dock, required this.children});

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  double _dockH = 140;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(left: 0, right: 0, top: 0, height: widget.mapH, child: widget.map),
      Positioned.fill(
        top: widget.mapH - 24,
        child: ListView(
          padding: EdgeInsets.only(bottom: _dockH + 16),
          children: widget.children,
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: MgSizeReporter(
          onSize: (s) {
            if (mounted && (s.height - _dockH).abs() > 0.5) setState(() => _dockH = s.height);
          },
          child: widget.dock,
        ),
      ),
    ]);
  }
}

class _ComputingChip extends StatelessWidget {
  final String label;
  const _ComputingChip({required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: label,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MgColors.nightA(0.8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.25)),
            boxShadow: MgShadows.photoControl,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.neon),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: MgType.meta.copyWith(color: MgColors.onDark))),
          ]),
        ),
      );
}

class _MapPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MapPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: MgColors.nightA(0.8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.white(0.25)),
              boxShadow: MgShadows.photoControl,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const MgIcon(MgIcons.full, size: 17, color: MgColors.neon),
              const SizedBox(width: 8),
              Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
            ]),
          ),
        ),
      );
}
