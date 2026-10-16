import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart' show MotoGoBackNav, Routes;
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../community_submit.dart';
import 'places_parts_v2.dart';
import 'record_dock_v2.dart';
import 'rides/recorder_screen_v2.dart' show openRideRecorderV2;
import 'trasy_hub_header_v2.dart';

/// Hub header on the Trasy segment: map = Mapa tras (the old "Mapa tras"
/// pill / quick link), "+" = the existing add menu. The list is a pushed
/// screen, so it keeps the old visible back (`backOr(Routes.routes)`).
class RoutesHubHeaderV2 extends StatelessWidget {
  final Widget search;
  const RoutesHubHeaderV2({super.key, required this.search});

  @override
  Widget build(BuildContext context) => TrasyHubHeaderV2(
        onBack: () => context.backOr(Routes.routes),
        seg: TrasySeg.routes,
        onSegment: (s) => trasyGoSegment(context, TrasySeg.routes, s),
        search: search,
        onMap: () => context.push(Routes.routesMap),
        mapLabel: t(context).tr('routesMapTitle'),
        onAdd: () => showCommunityAddMenu(context),
      );
}

/// Trasy page for the states without a list (loading / error / no routes):
/// same header, the state below, the record dock.
class RoutesStatePageV2 extends StatelessWidget {
  final Widget header;
  final Widget? child;
  final bool loading;
  const RoutesStatePageV2({super.key, required this.header, this.child, this.loading = false});

  @override
  Widget build(BuildContext context) => MgPage(
        overlapHero: false,
        header: header,
        slivers: [
          SliverToBoxAdapter(child: loading ? const PlacesLoadingV2() : child),
        ],
        dock: TrasyRecordDockV2(onOpenRecorder: () => openRideRecorderV2(context)),
      );
}

/// The ONE white band of the Trasy list: the old header numbers as stat
/// tiles ("1 370+ tras s navigací", "37 000+ zajímavých míst" — the same
/// floored counts) and the toolbar of the screen.
class RoutesBandV2 extends StatelessWidget {
  final String routes;
  final String pois;
  final Widget toolbar;
  const RoutesBandV2({super.key, required this.routes, required this.pois, required this.toolbar});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget stat(String v, String label) => Expanded(
          child: Semantics(
            label: '$v $label',
            excludeSemantics: true,
            child: Column(children: [
              Text('$v+', style: MgType.tab(MgType.h3.copyWith(color: MgColors.ink))),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: MgType.meta.copyWith(color: MgColors.meta)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.only(top: 16, bottom: 14),
      decoration: BoxDecoration(color: MgColors.surface, boxShadow: MgShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              stat(routes, tr.tr('v2RtStatRoutes')),
              const VerticalDivider(width: 1, color: MgColors.line),
              stat(pois, tr.tr('v2RtStatPois')),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        toolbar,
      ]),
    );
  }
}

/// Toolbar of the Trasy list: Filtry (n) · Řadit: … · Mapa tras · Zrušit.
class RoutesToolbarV2 extends StatelessWidget {
  final int activeCount;
  final String sortLabel;
  final bool sortOn;
  final VoidCallback onFilter;
  final VoidCallback onSort;
  final VoidCallback onMap;
  final VoidCallback onClear;

  const RoutesToolbarV2({
    super.key,
    required this.activeCount,
    required this.sortLabel,
    required this.sortOn,
    required this.onFilter,
    required this.onSort,
    required this.onMap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return TrasyChipRailV2(children: [
      TrasyToolChipV2(
        label: tr.tr('routesFilter'),
        icon: MgIcons.filter,
        on: activeCount > 0,
        count: activeCount > 0 ? activeCount : null,
        onTap: onFilter,
      ),
      TrasyToolChipV2(label: sortLabel, icon: MgIcons.sort, on: sortOn, caret: true, onTap: onSort),
      TrasyToolChipV2(label: tr.tr('routesMapBtn'), icon: MgIcons.map, onTap: onMap),
      if (activeCount > 0)
        TrasyToolChipV2(label: tr.tr('routesFilterClear'), icon: MgIcons.close, danger: true, onTap: onClear),
    ]);
  }
}
