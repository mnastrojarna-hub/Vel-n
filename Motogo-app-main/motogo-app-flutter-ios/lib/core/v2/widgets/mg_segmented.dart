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
import 'mg_text_fit.dart';
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

  /// Smallest label scale (r2: was 0.65 — large text must stay large).
  static const _minScale = 0.8;

  static const _labelStyle = TextStyle(fontWeight: FontWeight.w800, height: 1.2);

  /// True when every label's longest word fits its equal-width segment at
  /// [_minScale] at most — otherwise the options stack (never "Recommen|ded").
  bool _fitsSideBySide(BuildContext context, double segW) {
    final style = MgType.small.merge(_labelStyle);
    for (final s in segments) {
      var room = segW - 2 * MgSpace.s6;
      if (!iconAbove && s.icon != null) room -= 24;
      if (!mgWordsFit(context, s.label, style, room + 0.5, minScale: _minScale)) return false;
    }
    return true;
  }

  BoxDecoration _thumb(RankTokens? r) => BoxDecoration(
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
      );

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
          if (c.maxWidth.isFinite && !_fitsSideBySide(context, segW)) {
            // Úzký telefon / velké písmo / dlouhý jazyk: volby pod sebou,
            // vybraná má stejný „palec“ (přechod barvou místo posunu).
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < segments.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                  child: AnimatedContainer(
                    duration: dur,
                    curve: Curves.easeOut,
                    decoration: i == index
                        ? _thumb(r)
                        : BoxDecoration(borderRadius: BorderRadius.circular(dark ? 999 : 11)),
                    child: _segment(context, segments[i], i == index, stacked: true),
                  ),
                ),
            ]);
          }
          return Stack(children: [
            AnimatedPositioned(
              duration: dur,
              curve: MgMotion.spring,
              left: segW * index,
              top: 0,
              bottom: 0,
              width: segW,
              child: Container(decoration: _thumb(r)),
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

  Widget _segment(BuildContext context, MgSegment<T> s, bool selected, {bool stacked = false}) {
    final fg = dark
        ? (selected ? MgColors.onNeon : MgColors.onDarkSecondary)
        : (selected ? MgColors.ink : MgColors.lead);
    // Jednoslovný popisek se nikdy nerozdělí („Doporuč|ené"): nejdřív se
    // zmenší (nejvýš na 80 %), zalomí jen v mezeře; když ani to nestačí,
    // volby se složí pod sebe (build).
    final label = MgWordFit(
      minScale: _minScale,
      alignment: Alignment.center,
      child: Text(
        s.label,
        textAlign: TextAlign.center,
        maxLines: 2,
        softWrap: true,
        style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg, height: 1.2),
      ),
    );
    final child = iconAbove && !stacked
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
          constraints: BoxConstraints(minHeight: iconAbove && !stacked ? 52 : MgSize.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.s6, vertical: MgSpace.s6),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
