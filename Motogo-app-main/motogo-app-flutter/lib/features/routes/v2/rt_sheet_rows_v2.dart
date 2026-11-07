import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'poi_cat_icon_v2.dart';
import 'rt_sheet_v2.dart';

/// One choice of a tool sheet: label, state and the screen's existing
/// callback (null = not available now, e.g. "U vybrané trasy" without a
/// selected route). [icon] = MgIcons name, [cat] = place category key.
class RtOpt {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final String? icon;
  final String? cat;
  final String? sub;
  const RtOpt(this.label, this.on, this.onTap, {this.icon, this.cat, this.sub});
}

/// Choice chip of the tool sheets (44): well + line → selected = ink with
/// neon text and icon (✓ when there is no icon, so the state is never
/// colour-only); unavailable = 45 %.
class RtChipV2 extends StatelessWidget {
  final RtOpt opt;
  const RtChipV2(this.opt, {super.key});

  @override
  Widget build(BuildContext context) {
    final on = opt.on;
    final fg = on ? MgColors.neon : MgColors.ink;
    final ic = on ? MgColors.neon : MgColors.link;
    Widget? lead;
    if (opt.cat != null) {
      lead = PoiCatIconV2(opt.cat!, size: 16, color: ic);
    } else if (opt.icon != null) {
      lead = MgIcon(opt.icon!, size: 16, color: opt.icon == MgIcons.starFilled && !on ? MgColors.star : ic);
    } else if (on) {
      lead = MgPop(trigger: on, child: MgIcon(MgIcons.check, size: 16, color: ic));
    }
    return Semantics(
      button: true,
      selected: on,
      enabled: opt.onTap != null,
      label: opt.label,
      excludeSemantics: true,
      onTap: opt.onTap,
      child: MgPress(
        onTap: opt.onTap,
        child: Opacity(
          opacity: opt.onTap == null ? 0.45 : 1,
          child: AnimatedContainer(
            duration: MgMotion.of(context, MgMotion.color),
            constraints: const BoxConstraints(minHeight: MgSize.choiceChip),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? MgColors.ink : MgColors.well,
              borderRadius: BorderRadius.circular(MgRadius.pill),
              border: Border.all(color: on ? MgColors.ink : MgColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (lead != null) ...[lead, const SizedBox(width: 6)],
              Flexible(
                child: MgWordFit(
                  minScale: 0.8,
                  child: Text(opt.label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The chips of one section, wrapped.
class RtChipsV2 extends StatelessWidget {
  final List<RtOpt> opts;
  const RtChipsV2(this.opts, {super.key});

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: [for (final o in opts) RtChipV2(o)]);
}

/// Radio row of the sort sheet (`.so`): icon tile + label, selected =
/// tint + ✓, unavailable = 45 %.
class RtSortRowV2 extends StatelessWidget {
  final RtOpt opt;
  const RtSortRowV2(this.opt, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: opt.on,
        enabled: opt.onTap != null,
        label: opt.label,
        excludeSemantics: true,
        onTap: opt.onTap,
        child: MgPress(
          onTap: opt.onTap,
          child: Opacity(
            opacity: opt.onTap == null ? 0.45 : 1,
            child: AnimatedContainer(
              duration: MgMotion.of(context, MgMotion.color),
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: opt.on ? MgColors.tintOk : MgColors.surface,
                borderRadius: BorderRadius.circular(MgRadius.action),
              ),
              child: Row(children: [
                MgIconTileLight(opt.icon ?? MgIcons.sort, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: MgWordFit(
                    child: Text(opt.label, style: MgType.title.copyWith(color: MgColors.ink)),
                  ),
                ),
                if (opt.on) ...[
                  const SizedBox(width: 8),
                  MgPop(trigger: opt.on, child: const MgIcon(MgIcons.check, size: 20, color: MgColors.link)),
                ],
              ]),
            ),
          ),
        ),
      );
}

/// Row of the route picker (`.rpr`): route icon, name (2 lines), count of
/// places, ✓ when chosen.
class RtPickRowV2 extends StatelessWidget {
  final RtOpt opt;
  final int count;
  const RtPickRowV2(this.opt, this.count, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: opt.on,
        label: '${opt.label}, $count',
        excludeSemantics: true,
        onTap: opt.onTap,
        child: MgPress(
          onTap: opt.onTap,
          child: AnimatedContainer(
            duration: MgMotion.of(context, MgMotion.color),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: opt.on ? MgColors.tintOk : MgColors.surface,
              borderRadius: BorderRadius.circular(MgRadius.action),
            ),
            child: Row(children: [
              MgIcon(opt.icon ?? MgIcons.route, size: 20, color: MgColors.link),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  opt.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MgType.body.copyWith(color: MgColors.ink, fontWeight: opt.on ? FontWeight.w800 : FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 26),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: opt.on ? MgColors.neon : MgColors.well,
                  borderRadius: BorderRadius.circular(MgRadius.pill),
                  border: opt.on ? null : Border.all(color: MgColors.line),
                ),
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: MgType.tab(MgType.meta.copyWith(color: opt.on ? MgColors.onNeon : MgColors.body2))),
              ),
              if (opt.on) ...[
                const SizedBox(width: 8),
                const MgIcon(MgIcons.check, size: 20, color: MgColors.link),
              ],
            ]),
          ),
        ),
      );
}

/// "Země" block: the pinned states, "Další státy (n)" and the rest below it
/// (opens / closes in place).
class RtCountriesV2 extends StatelessWidget {
  final List<RtOpt> top;
  final List<RtOpt> rest;
  final bool open;
  final VoidCallback onMore;
  const RtCountriesV2({super.key, required this.top, required this.rest, required this.open, required this.onMore});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RtChipsV2(top),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 4),
          RtExpandLinkV2(
            label: '${t(context).tr('routesFilterMoreCountries')} (${rest.length})',
            open: open,
            onTap: onMore,
          ),
          MgAnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open ? RtChipsV2(rest) : const SizedBox(width: double.infinity),
          ),
        ],
      ]);
}
