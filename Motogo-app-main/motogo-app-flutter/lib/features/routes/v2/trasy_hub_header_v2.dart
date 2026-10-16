import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart' show MotoGoBackNav, Routes;
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_segmented.dart';
import '../animated_route_icon.dart';

/// The three faces of the Trasy tab (one hub, routing unchanged).
enum TrasySeg { places, routes, mine }

/// Segment taps = the destinations of the old quick links (no new routes):
/// Místa = back to the tab root, Trasy = the pushed list, Moje = Moje zážitky.
void trasyGoSegment(BuildContext context, TrasySeg from, TrasySeg to) {
  if (from == to) return;
  switch (to) {
    case TrasySeg.places:
      context.backOr(Routes.routes);
    case TrasySeg.routes:
      context.pushOrGo(Routes.routesList);
    case TrasySeg.mine:
      context.pushOrGo('/my-experiences');
  }
}

/// Dark rank header of the Trasy hub (board TrasyHub `.hd`): title with the
/// riding-dot route icon, 44 glass map button, 44 "+" (the existing add
/// menu), the search pill of the screen and the Místa · Trasy · Moje
/// segments (icon above, labels never ellipsized). [onBack] = focused
/// variant (place picker) with a back disc and no segments.
class TrasyHubHeaderV2 extends StatelessWidget {
  final TrasySeg seg;
  final ValueChanged<TrasySeg>? onSegment;
  final Widget? search;
  final VoidCallback? onMap;
  final String? mapLabel;
  final VoidCallback? onAdd;
  final VoidCallback? onBack;
  final String? title;
  final String? subtitle;

  const TrasyHubHeaderV2({
    super.key,
    required this.seg,
    this.onSegment,
    this.search,
    this.onMap,
    this.mapLabel,
    this.onAdd,
    this.onBack,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final reduced = MgMotion.reduced(context);
    return MgRankHero(
      ambientKey: 'trasy',
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (onBack != null) ...[
            MgV2Back(onTap: onBack, style: MgBackStyle.dark),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Row(children: [
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(title ?? tr.tr('routesTitle'),
                      style: MgType.h2.copyWith(color: MgColors.onDark, height: 1.1)),
                ),
              ),
              const SizedBox(width: 10),
              ExcludeSemantics(
                child: reduced
                    ? const MgIcon(MgIcons.route, size: 24, color: MgColors.neon)
                    : const RepaintBoundary(child: AnimatedRouteIcon(size: 28)),
              ),
            ]),
          ),
          if (onMap != null)
            MgIconButton(
              icon: MgIcons.map,
              onTap: onMap,
              semanticLabel: mapLabel ?? tr.tr('placesMapTitle'),
            ),
          if (onAdd != null) ...[
            const SizedBox(width: 4),
            MgIconButton(
              icon: MgIcons.plus,
              onTap: onAdd,
              iconColor: MgColors.neon,
              semanticLabel: tr.tr('v2RtAddA11y'),
            ),
          ],
        ]),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
        ],
        if (search != null) ...[
          const SizedBox(height: 12),
          search!,
        ],
        if (onSegment != null) ...[
          const SizedBox(height: 12),
          MgSegmented<TrasySeg>(
            dark: true,
            iconAbove: true,
            value: seg,
            onChanged: onSegment,
            segments: [
              MgSegment(value: TrasySeg.places, label: tr.tr('poiBrowseAll'), icon: MgIcons.pin),
              MgSegment(value: TrasySeg.routes, label: tr.tr('routesTitle'), icon: MgIcons.route),
              MgSegment(value: TrasySeg.mine, label: tr.tr('v2RtSegMine'), icon: MgIcons.bike),
            ],
          ),
        ],
      ]),
    );
  }
}

/// Search pill on the dark header, bound to the screen's EXISTING search
/// controller / debounce (the screen passes its own callbacks).
class TrasySearchV2 extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool showClear;

  const TrasySearchV2({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    required this.showClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: MgColors.white(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.white(0.18)),
      ),
      child: Row(children: [
        const MgIcon(MgIcons.search, size: 20, color: MgColors.onDarkSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            cursorColor: MgColors.neon,
            style: MgType.body.copyWith(color: MgColors.onDark),
            decoration: InputDecoration.collapsed(
              hintText: hint,
              hintStyle: MgType.body.copyWith(color: MgColors.onDarkMeta),
            ),
          ),
        ),
        if (showClear)
          Semantics(
            button: true,
            label: t(context).tr('v2RtSearchClear'),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.onDarkSecondary)),
              ),
            ),
          )
        else
          const SizedBox(width: 12),
      ]),
    );
  }
}
