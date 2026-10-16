import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../rank/rank_provider.dart';
import '../rank/rank_tokens.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_word_fit.dart';

/// One option of [MgSegmented].
class MgSegment<T> {
  final T value;
  final String label;
  final String? icon;
  final String? sub;
  const MgSegment({required this.value, required this.label, this.icon, this.sub});
}

/// Sliding-thumb segmented control. Light: well track + white thumb; dark:
/// night pill with a neon thumb and a 30 % rank glow. All segments share
/// one height (the tallest wins); labels wrap to 2 lines, never ellipsis.
/// [iconAbove] = 52 px tall variant with the icon over a 12.5/800 label
/// (required for the Trasy segments, V21 §0.4).
class MgSegmented<T> extends ConsumerWidget {
  final List<MgSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool dark;
  final bool iconAbove;
  final RankTokens? rank;

  const MgSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.dark = false,
    this.iconAbove = false,
    this.rank,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankTokens? r = dark ? (rank ?? ref.watch(rankTokensProvider)) : null;
    final index = segments.indexWhere((s) => s.value == value).clamp(0, segments.length - 1);
    final dur = MgMotion.of(context, MgMotion.thumb);
    const pad = 4.0;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: dark ? MgColors.white(0.06) : MgColors.well,
          borderRadius: BorderRadius.circular(dark ? 999 : MgRadius.button),
          border: Border.all(color: dark ? MgColors.white(0.10) : MgColors.line),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final segW = c.maxWidth / segments.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: dur,
              curve: MgMotion.spring,
              left: segW * index,
              top: 0,
              bottom: 0,
              width: segW,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? MgColors.neon : MgColors.surface,
                  borderRadius: BorderRadius.circular(dark ? 999 : 11),
                  boxShadow: dark
                      ? [
                          BoxShadow(
                            color: r!.glowColor.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : MgShadows.icon,
                ),
              ),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < segments.length; i++)
                    Expanded(child: _segment(context, segments[i], i == index)),
                ],
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _segment(BuildContext context, MgSegment<T> s, bool selected) {
    final fg = dark
        ? (selected ? MgColors.onNeon : MgColors.onDarkSecondary)
        : (selected ? MgColors.ink : MgColors.lead);
    // Jednoslovný popisek se nikdy nerozdělí („Doporuč|ené"): nejdřív se
    // zmenší (do 75 %), až potom zalomí v mezeře — opraví všechny segmenty.
    final label = MgWordFit(
      minScale: 0.75,
      alignment: Alignment.center,
      child: Text(
        s.label,
        textAlign: TextAlign.center,
        maxLines: 2,
        softWrap: true,
        style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg, height: 1.2),
      ),
    );
    final child = iconAbove
        ? Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (s.icon != null) MgIcon(s.icon!, size: 20, color: fg),
            const SizedBox(height: 4),
            label,
          ])
        : Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (s.icon != null) ...[MgIcon(s.icon!, size: 18, color: fg), const SizedBox(width: 6)],
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                label,
                if (s.sub != null)
                  Text(s.sub!,
                      textAlign: TextAlign.center,
                      style: MgType.meta.copyWith(
                          color: dark
                              ? (selected ? MgColors.priceOnNeon : MgColors.onDarkMeta)
                              : MgColors.meta)),
              ]),
            ),
          ]);
    return Semantics(
      button: true,
      selected: selected,
      label: s.sub == null ? s.label : '${s.label}, ${s.sub}',
      excludeSemantics: true,
      onTap: onChanged == null ? null : () => onChanged!(s.value),
      child: MgPress(
        onTap: onChanged == null || selected ? null : () => onChanged!(s.value),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: iconAbove ? 52 : MgSize.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.s6, vertical: MgSpace.s6),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
