import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_anim_loops.dart';
import '../rank/rank_fx.dart';
import '../rank/rank_marks.dart';
import '../rank/rank_provider.dart';
import '../rank/rank_tokens.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

/// Size of the primary CTA: 60 (sticky Detail / Booking), 56 (hero),
/// 48 (card action), 44 (compact).
enum MgCtaSize { lg60, md56, sm48, xs44 }

/// THE rank-themed primary action (`shared/cta.html`). Rank material + glow;
/// the loop fx run only when [loop] (one looping primary per screen). Label
/// is caps 14.5/800; [price] is appended as "· 10 189 Kč" (900, tabular,
/// never uppercased). [busy] shows a spinner inside without a layout jump.
/// ALWAYS on a dark carrier (hero, dock, dark block) — on light put it into
/// `MgDock` / a dark block (DESIGN_V22 §1.4).
class MgCta extends ConsumerWidget {
  final String label;
  final VoidCallback? onTap;
  final String? price;
  final bool loop;
  final MgCtaSize size;
  final bool enabled;
  final bool busy;
  final RankTokens? rank;

  /// Trailing → arrow (hero / card CTAs).
  final bool arrow;

  /// Full width (default) or hug the label.
  final bool expand;
  final bool showMarks;
  final String? semanticLabel;

  const MgCta({
    super.key,
    required this.label,
    required this.onTap,
    this.price,
    this.loop = false,
    this.size = MgCtaSize.md56,
    this.enabled = true,
    this.busy = false,
    this.rank,
    this.arrow = false,
    this.expand = true,
    this.showMarks = true,
    this.semanticLabel,
  });

  double get _height => switch (size) {
        MgCtaSize.lg60 => 60,
        MgCtaSize.md56 => 56,
        MgCtaSize.sm48 => 48,
        MgCtaSize.xs44 => 44,
      };

  double get _radius => switch (size) {
        MgCtaSize.lg60 => 16,
        MgCtaSize.md56 => 14,
        _ => 12,
      };

  TextStyle get _textStyle => switch (size) {
        MgCtaSize.lg60 || MgCtaSize.md56 => MgType.cta,
        MgCtaSize.sm48 => MgType.ctaCompact,
        MgCtaSize.xs44 => MgType.ctaCompact.copyWith(fontSize: 12.5),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankTokens r = rank ?? ref.watch(rankTokensProvider);
    final active = enabled && onTap != null;
    final radius = BorderRadius.circular(_radius);
    final labelColor = active ? r.ctaLabel : MgColors.onDarkFloor;
    final base = _textStyle.copyWith(color: labelColor);
    final sem = semanticLabel ?? (price == null ? label : '$label, $price');

    Widget text = Text.rich(
      TextSpan(children: [
        TextSpan(text: label.toUpperCase()),
        if (price != null) ...[
          TextSpan(
            text: '  ·  ',
            style: TextStyle(color: labelColor.withValues(alpha: 0.55), fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: price,
            style: MgType.tab(const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0)),
          ),
        ],
      ]),
      textAlign: TextAlign.center,
      style: base,
      softWrap: true,
    );
    final glyph = !active || !showMarks
        ? null
        : switch (r.glyph) {
            RankGlyph.crown => MgIcons.crown,
            RankGlyph.laurel => MgIcons.laurel,
            RankGlyph.none => null,
          };
    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (glyph != null) ...[MgIcon(glyph, size: 18, color: labelColor), const SizedBox(width: 8)],
        Flexible(child: text),
        if (arrow) ...[const SizedBox(width: 8), MgIcon(MgIcons.arrowRight, size: 18, color: labelColor)],
      ],
    );
    if (busy) {
      content = Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0, child: content),
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: labelColor),
        ),
      ]);
    }
    final marksSize = RankMarks.sizeFor(r, 0.8);
    final showMk = active && showMarks && !busy && !marksSize.isEmpty;

    Widget button(ValueListenable<double>? clock) {
      Widget body(double? s) {
        final pulse = s == null ? 0.0 : (math.sin(2 * math.pi * (s % 2.2) / 2.2 - math.pi / 2) + 1) / 2;
        return Container(
          constraints: BoxConstraints(minHeight: _height),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: active ? r.edgeGradient : null,
            color: active ? null : MgColors.white(0.12),
            boxShadow: active ? r.ctaGlow(pulse) : null,
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            constraints: BoxConstraints(minHeight: _height - 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius - 1.5),
              gradient: active ? r.ctaGradient : null,
              color: active ? null : MgColors.white(0.10),
            ),
            child: CustomPaint(
              painter: active ? RankFxPainter(r, (loop && !busy) ? s : null, _radius - 1.5) : null,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    size == MgCtaSize.sm48 || size == MgCtaSize.xs44 ? 12 : 18,
                    8,
                    size == MgCtaSize.sm48 || size == MgCtaSize.xs44 ? 12 : 18,
                    showMk ? 8 + marksSize.height + 2 : 8),
                child: Center(widthFactor: expand ? null : 1, child: content),
              ),
            ),
          ),
        );
      }

      if (clock == null) return body(null);
      return ValueListenableBuilder<double>(valueListenable: clock, builder: (_, s, __) => body(s));
    }

    Widget cta = MgLoopClock(
      active: active && loop && !busy,
      builder: (_, clock) => button(clock),
    );
    if (showMk) {
      cta = Stack(children: [
        cta,
        Positioned(
          left: 0,
          right: 0,
          bottom: size == MgCtaSize.lg60 || size == MgCtaSize.md56 ? 6 : 4,
          child: Center(
            child: RankMarks(
              rank: r,
              scale: 0.8,
              litColor: r.ctaLabel.withValues(alpha: 0.62),
              dimColor: r.ctaLabel.withValues(alpha: 0.2),
            ),
          ),
        ),
      ]);
    }
    return Semantics(
      button: true,
      enabled: active && !busy,
      label: sem,
      excludeSemantics: true,
      onTap: active && !busy ? onTap : null,
      child: MgPress(
        onTap: active && !busy ? onTap : null,
        child: SizedBox(width: expand ? double.infinity : null, child: cta),
      ),
    );
  }
}
