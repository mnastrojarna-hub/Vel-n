import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import 'places_parts_v2.dart';
import 'rt_v2_text.dart';

/// The ONE white band of Místa (DESIGN_V22 R5.6): toolbar (Filtry a
/// řazení → the existing tools sheet, V okolí + km, Trasa → the existing
/// route picker, Zrušit) and the category row, now always visible with
/// live counts. Every tap calls the screen's existing filter writes.
class PlacesFiltersV2 extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTools;
  final bool nearbyOn;
  final double nearbyKm;
  final List<double> kmOptions;
  final VoidCallback onNearby;
  final ValueChanged<double> onKm;
  final String routeLabel;
  final bool routeActive;
  final int? routeCount;
  final VoidCallback onRoute;
  final VoidCallback onClear;
  final List<PlacesCatV2> cats;
  final ValueChanged<String> onCat;
  final int sourceCount;

  const PlacesFiltersV2({
    super.key,
    required this.activeCount,
    required this.onTools,
    required this.nearbyOn,
    required this.nearbyKm,
    required this.kmOptions,
    required this.onNearby,
    required this.onKm,
    required this.routeLabel,
    required this.routeActive,
    required this.routeCount,
    required this.onRoute,
    required this.onClear,
    required this.cats,
    required this.onCat,
    required this.sourceCount,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: MgColors.surface, boxShadow: MgShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TrasyChipRailV2(children: [
          TrasyToolChipV2(
            label: tr.tr('poiFiltersOpen'),
            icon: MgIcons.filter,
            on: activeCount > 0,
            count: activeCount > 0 ? activeCount : null,
            onTap: onTools,
          ),
          TrasyToolChipV2(
            label: '${tr.tr('poiNearby')} ${nearbyKm.round()} km',
            icon: MgIcons.target,
            on: nearbyOn,
            onTap: onNearby,
          ),
          if (nearbyOn)
            for (final km in kmOptions)
              TrasyToolChipV2(label: '${km.round()} km', on: nearbyKm == km, onTap: () => onKm(km)),
          TrasyToolChipV2(
            label: routeLabel,
            icon: MgIcons.route,
            on: routeActive,
            count: routeCount,
            caret: true,
            onTap: onRoute,
          ),
          if (activeCount > 0)
            TrasyToolChipV2(label: tr.tr('routesFilterClear'), icon: MgIcons.close, danger: true, onTap: onClear),
        ]),
        if (cats.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(children: [
              MgEyebrowDark(tr.tr('v2RtCategories'), icon: MgIcons.pin),
              const SizedBox(width: 10),
              Flexible(
                child: Text(rtPlural(tr, 'v2RtPlaces', sourceCount),
                    style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
              ),
            ]),
          ),
          TrasyChipRailV2(children: [
            for (final c in cats)
              TrasyToolChipV2(
                label: c.label,
                iconWidget: c.icon,
                on: c.selected,
                count: c.count,
                onTap: () => onCat(c.key),
              ),
          ]),
        ],
      ]),
    );
  }
}
