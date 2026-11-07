import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
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

/// Place card of the Místa list (board TrasyHub): 84 px photo (64 px on
/// phones under 360 dp — the text column needs the room), name, category /
/// route / community line, ★ and distance, add / remove disc. Tap = detail,
/// long-press or disc = toggle — the SAME callbacks as the old card.
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
    // Under 360 dp a smaller photo leaves the name / type column ~20 px more
    // (a long type like „Bezienswaardigheden“ stays whole, no ellipsis).
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final thumb = narrow ? 64.0 : 84.0;
    final sem = [
      name,
      subtitle,
      if (rated) '${(poi.avgRating ?? 0).toStringAsFixed(1)} (${poi.ratingCount})',
      if (dist != null) dist!,
      if (selected) tr.tr('v2RtSelected'),
    ].join(', ');
    final subStyle = MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.link);
    // Typ místa celý (smí na 2 řádky v mezeře; jedno dlouhé slovo jako
    // „Bezienswaardigheden“ se zmenší nejvýš na 80 %), ne „…“.
    final subLine = Row(children: [
      subIcon,
      const SizedBox(width: 5),
      Flexible(
        child: MgWordFit(
          minScale: _minScale,
          child: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: subStyle),
        ),
      ),
    ]);
    return LayoutBuilder(builder: (context, c) {
    // Když se nejdelší slovo typu nevejde do sloupce ani na 80 % (úzký
    // telefon + velké písmo), řádek typu jde pod fotku přes celou kartu.
    final colW = c.maxWidth - 3 - 10 - 4 - thumb - (narrow ? 10 : 12) - 48 - 10;
    final subInline = !c.maxWidth.isFinite || _wordFits(context, subtitle, subStyle, colW - 19);
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
                  child: _withSubBelow(subInline ? null : subLine, Row(children: [
                    SizedBox(
                      width: thumb,
                      height: thumb,
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
                                // Pořadí 10+ při velkém písmu se do kolečka vejde (číslo, ne text).
                                child: Padding(
                                  padding: const EdgeInsets.all(1),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('$order',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon))),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    SizedBox(width: narrow ? 10 : 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                        if (subInline) ...[const SizedBox(height: 4), subLine],
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
                                // „128.5 km · 2h 47m“ wraps at a space in a narrow column.
                                Flexible(child: Text(dist!, style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta)))),
                              ]),
                          ]),
                        ],
                      ]),
                    ),
                  ])),
                ),
              ),
            ),
          ),
          _ToggleDisc(selected: selected, onTap: onToggle, name: name),
          const SizedBox(width: 10),
        ]),
      ),
    );
    });
  }

  static const _minScale = 0.8;

  static bool _wordFits(BuildContext context, String text, TextStyle style, double width) =>
      mgWordsFit(context, text, style, width + 0.5, minScale: _minScale);

  static Widget _withSubBelow(Widget? sub, Widget row) => sub == null
      ? row
      : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          row,
          const SizedBox(height: 8),
          sub,
        ]);
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
