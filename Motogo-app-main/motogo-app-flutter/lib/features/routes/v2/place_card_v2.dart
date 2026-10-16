import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../route_image.dart';
import '../routes_model.dart';
import 'poi_cat_icon_v2.dart';

/// What the second line of a place card names (same rule as the old list).
enum PlaceSubKind { category, route, community }

/// Photo fallback of a place: category icon on a soft tile.
class PlaceThumbFallbackV2 extends StatelessWidget {
  final RoutePoi? poi;
  final double iconSize;
  const PlaceThumbFallbackV2({super.key, this.poi, this.iconSize = 26});

  @override
  Widget build(BuildContext context) => Container(
        color: MgColors.tintFeatureA,
        child: Center(
          child: poi == null
              ? MgIcon(MgIcons.pin, size: iconSize, color: MgColors.link)
              : PoiCatIconV2.of(poi!, size: iconSize, color: MgColors.link),
        ),
      );
}

/// Place card of the Místa list (board TrasyHub): 84 px photo (selection
/// order badge), name, category / route / community line, ★ and distance,
/// add / remove disc. Tap = detail, long-press or disc = toggle — the SAME
/// callbacks as the old card.
class PlaceCardV2 extends StatelessWidget {
  final RoutePoi poi;
  final String name;
  final String subtitle;
  final PlaceSubKind subKind;
  final String? dist;
  final bool selected;
  final int? order;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const PlaceCardV2({
    super.key,
    required this.poi,
    required this.name,
    required this.subtitle,
    required this.subKind,
    required this.dist,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    this.order,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dur = MgMotion.of(context, MgMotion.color);
    final cover = poi.cover;
    final subIcon = switch (subKind) {
      PlaceSubKind.category => PoiCatIconV2.of(poi, size: 14, color: MgColors.link),
      PlaceSubKind.route => const MgIcon(MgIcons.route, size: 14, color: MgColors.link),
      PlaceSubKind.community => const MgIcon(MgIcons.user, size: 14, color: MgColors.link),
    };
    final rated = poi.ratingCount > 0;
    final sem = [
      name,
      subtitle,
      if (rated) '${(poi.avgRating ?? 0).toStringAsFixed(1)} (${poi.ratingCount})',
      if (dist != null) dist!,
      if (selected) tr.tr('v2RtSelected'),
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: dur,
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? MgColors.tintOkBorder : MgColors.line, width: selected ? 1.5 : 1),
          boxShadow: [
            ...MgShadows.card,
            if (selected) BoxShadow(color: MgColors.neonA(0.22), spreadRadius: 3),
          ],
        ),
        child: Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: sem,
              excludeSemantics: true,
              child: MgPress(
                scale: 0.98,
                onTap: onTap,
                onLongPress: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                  child: Row(children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: cover != null
                                ? RouteImage(
                                    url: cover,
                                    targetWidth: 300,
                                    placeholder: (_) => PlaceThumbFallbackV2(poi: poi),
                                    error: (_) => PlaceThumbFallbackV2(poi: poi),
                                  )
                                : PlaceThumbFallbackV2(poi: poi),
                          ),
                        ),
                        if (selected && order != null)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: MgPop(
                              trigger: order,
                              playOnMount: true,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: MgColors.neon,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: MgColors.surface, width: 2),
                                ),
                                child: Center(
                                  child: Text('$order',
                                      style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon))),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                        const SizedBox(height: 4),
                        Row(children: [
                          subIcon,
                          const SizedBox(width: 5),
                          Flexible(
                            // Typ místa celý (zmenší se, smí na 2 řádky), ne „…".
                            child: MgWordFit(
                              minScale: 0.8,
                              child: Text(subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link)),
                            ),
                          ),
                        ]),
                        if (rated || dist != null) ...[
                          const SizedBox(height: 4),
                          Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            if (rated)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                const MgIcon(MgIcons.starFilled, size: 13, color: MgColors.star),
                                const SizedBox(width: 3),
                                Text('${(poi.avgRating ?? 0).toStringAsFixed(1)} (${poi.ratingCount})',
                                    style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                              ]),
                            if (dist != null)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                const MgIcon(MgIcons.navigate, size: 13, color: MgColors.meta),
                                const SizedBox(width: 3),
                                Text(dist!, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
                              ]),
                          ]),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          _ToggleDisc(selected: selected, onTap: onToggle, name: name),
          const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

class _ToggleDisc extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String name;
  const _ToggleDisc({required this.selected, required this.onTap, required this.name});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      toggled: selected,
      label: '${tr.tr(selected ? 'v2RtRemoveFromTrip' : 'v2RtAddToTrip')}: $name',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.9,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: MgMotion.of(context, MgMotion.color),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? MgColors.neon : MgColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? MgColors.neonLo : MgColors.link, width: 1.5),
              ),
              child: Center(
                child: MgBump(
                  trigger: selected,
                  child: MgIcon(selected ? MgIcons.check : MgIcons.plus,
                      size: 22, color: selected ? MgColors.onNeon : MgColors.link),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
