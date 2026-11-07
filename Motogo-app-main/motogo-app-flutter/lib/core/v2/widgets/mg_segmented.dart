import 'package:flutter/foundation.dart' show ValueListenable;
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
///
/// [dragProgress] (from `MgSwipeSegments.progress`): the thumb tracks a body
/// swipe — x = (index + progress) × segment width, clamped. [counts] show a
/// number per segment: [inlineCount] = after the label on the same line
/// (neon 11/800 on dark, `#0D6E0D` on light, never wraps), else on the sub
/// line. [inkThumb] = light track with an ink `#1A2E22` thumb and a white
/// selected label (Zážitky filter).
class MgSegmented<T> extends ConsumerWidget {
  final List<MgSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool dark;
  final bool iconAbove;
  final RankTokens? rank;
  final ValueListenable<double>? dragProgress;
  final Map<T, int>? counts;
  final bool inlineCount;
  final bool inkThumb;

  const MgSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.dark = false,
    this.iconAbove = false,
    this.rank,
    this.dragProgress,
    this.counts,
    this.inlineCount = false,
    this.inkThumb = false,
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
      if (inlineCount && counts?[s.value] != null) room -= _countWidth(context, counts![s.value]!);
      if (!mgWordsFit(context, s.label, style, room + 0.5, minScale: _minScale)) return false;
    }
    return true;
  }

  static const _countStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 1.2);

  /// Room an inline count takes (gap + tabular number).
  double _countWidth(BuildContext context, int n) {
    final tp = TextPainter(
      text: TextSpan(text: '$n', style: MgType.small.merge(_countStyle).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width + 4;
    tp.dispose();
    return w;
  }

  BoxDecoration _thumb(RankTokens? r) => BoxDecoration(
        color: dark ? MgColors.neon : (inkThumb ? MgColors.ink : MgColors.surface),
        borderRadius: BorderRadius.circular(dark ? 999 : 11),
        boxShadow: dark
            ? [
                BoxShadow(
                  color: r!.glowColor.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : (inkThumb ? null : MgShadows.icon),
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
          Widget thumbAt(double p) => AnimatedPositioned(
                // Během tažení palec jde přesně s prstem, po puštění pruží.
                duration: p == 0 ? dur : Duration.zero,
                curve: MgMotion.spring,
                left: segW * (index + p).clamp(0.0, segments.length - 1.0),
                top: 0,
                bottom: 0,
                width: segW,
                child: Container(decoration: _thumb(r)),
              );
          return Stack(children: [
            if (dragProgress == null)
              thumbAt(0)
            else
              ValueListenableBuilder<double>(
                valueListenable: dragProgress!,
                builder: (_, p, __) => Positioned.fill(child: Stack(children: [thumbAt(p)])),
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
        : (selected ? (inkThumb ? MgColors.onDark : MgColors.ink) : MgColors.lead);
    final count = counts?[s.value];
    final countText = count == null
        ? null
        : Text('$count',
            maxLines: 1,
            softWrap: false,
            style: MgType.small.merge(_countStyle).copyWith(
                  color: dark ? (selected ? MgColors.priceOnNeon : MgColors.neon) : (selected && inkThumb ? MgColors.neon : MgColors.link),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ));
    // Jednoslovný popisek se nikdy nerozdělí („Doporuč|ené"): nejdřív se
    // zmenší (nejvýš na 80 %), zalomí jen v mezeře; když ani to nestačí,
    // volby se složí pod sebe (build).
    Widget label = MgWordFit(
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
    if (countText != null && inlineCount) {
      label = Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: label),
        const SizedBox(width: 4),
        countText,
      ]);
    }
    final subText = s.sub ?? (countText != null && !inlineCount ? '$count' : null);
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
                if (subText != null)
                  Text(subText,
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
      label: [s.label, if (s.sub != null) s.sub!, if (count != null) '$count'].join(', '),
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
