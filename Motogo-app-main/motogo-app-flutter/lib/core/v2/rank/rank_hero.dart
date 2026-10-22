import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_shadows.dart';
import 'rank_provider.dart';
import 'rank_tokens.dart';

/// Dark rank header band (`.rk-hero`): `gDark` with the rank aura as the
/// first stop, a static tier texture (4–7 % white, zero motion), a 2 px
/// minted bottom edge and ONE ambient sweep per session (headlight / sheen /
/// prism / aurora / aurora + embers; none under reduced motion). White text
/// on it stays ≥ 4.5 : 1 for every level.
class MgRankHero extends ConsumerWidget {
  final Widget child;
  final RankTokens? rank;
  final EdgeInsetsGeometry padding;
  final double bottomRadius;

  /// Adds the status-bar height above [padding].
  final bool includeStatusBar;
  final bool ambient;

  /// Session key of the one-shot ambient (one play per key and level).
  final String ambientKey;

  const MgRankHero({
    super.key,
    required this.child,
    this.rank,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 20),
    this.bottomRadius = 24,
    this.includeStatusBar = true,
    this.ambient = true,
    this.ambientKey = 'hero',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankTokens r = rank ?? ref.watch(rankTokensProvider);
    final top = includeStatusBar ? MediaQuery.paddingOf(context).top : 0.0;
    final radius = BorderRadius.vertical(bottom: Radius.circular(bottomRadius));
    final playAmbient = ambient &&
        !MgMotion.reduced(context) &&
        MgMotion.firstTime('ambient:$ambientKey:${r.level}');
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: MgGradients.hero(r.aura)),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _TexturePainter(r.tier))),
            ),
            if (playAmbient)
              Positioned.fill(
                child: IgnorePointer(
                  child: MgProgressOnce(
                    duration: Duration(milliseconds: r.tier.index >= 3 ? 2400 : 900),
                    delay: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    builder: (_, t) => CustomPaint(painter: _AmbientPainter(r, t)),
                  ),
                ),
              ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 0,
              height: 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.85,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(colors: [
                        const Color(0x00FFFFFF),
                        r.ctaEdge.first,
                        r.uiDark,
                        r.ctaEdge[2],
                        const Color(0x00FFFFFF),
                      ], stops: const [0, 0.25, 0.5, 0.75, 1]),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: top).add(padding),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _TexturePainter extends CustomPainter {
  final RankTier tier;
  _TexturePainter(this.tier);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x0FFFFFFF);
    switch (tier) {
      case RankTier.road:
        for (var row = 0; row < size.height / 30 + 1; row++) {
          final y0 = 28.0 + row * 30;
          final p = Path()..moveTo(-10, y0);
          for (double x = -10; x < size.width + 40; x += 82) {
            p.relativeCubicTo(30, -14, 52, 10, 82, 2);
          }
          canvas.drawPath(p, line);
        }
      case RankTier.metal:
        final hi = Paint()..color = const Color(0x0BFFFFFF);
        final lo = Paint()..color = const Color(0x12000000);
        for (double y = 0; y < size.height; y += 3) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), hi);
        }
        for (double y = 0; y < size.height; y += 9) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), lo);
        }
      case RankTier.jewel:
        for (double x = -size.height; x < size.width + size.height; x += 60) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height * 0.58, size.height), line);
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height * 0.58, 0), line);
        }
        for (double y = 52; y < size.height; y += 104) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case RankTier.vip:
      case RankTier.legend:
        final p = line..color = const Color(0x0EFFFFFF);
        for (double y = 0; y < size.height + 64; y += 64) {
          for (double x = 0; x < size.width + 64; x += 64) {
            canvas.drawCircle(Offset(x, y), 30, p);
          }
        }
        if (tier == RankTier.legend) {
          final g = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0x14FFE27A);
          final c = Offset(size.width - 70, size.height / 2);
          canvas.drawArc(Rect.fromCircle(center: c, radius: 76), math.pi * 0.55, math.pi * 0.9, false, g);
        }
    }
  }

  @override
  bool shouldRepaint(_TexturePainter o) => o.tier != tier;
}

class _AmbientPainter extends CustomPainter {
  final RankTokens r;
  final double t;
  _AmbientPainter(this.r, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final op = t < 0.15 ? t / 0.15 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
    if (op <= 0) return;
    final rect = Offset.zero & size;
    if (r.tier.index >= 3) {
      // aurora: two soft glows drifting across
      final a = Offset(size.width * (0.3 + 0.2 * t), size.height * 0.35);
      final b = Offset(size.width * (0.7 - 0.2 * t), size.height * 0.7);
      final warm = r.tier == RankTier.legend ? const Color(0xFFFF8C00) : r.glowColor;
      canvas.drawCircle(a, size.width * 0.3,
          Paint()..shader = RadialGradient(colors: [warm.withValues(alpha: 0.4 * op), warm.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: a, radius: size.width * 0.3)));
      const gold = Color(0xFFD4AF37);
      canvas.drawCircle(b, size.width * 0.26,
          Paint()..shader = RadialGradient(colors: [gold.withValues(alpha: 0.35 * op), gold.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: b, radius: size.width * 0.26)));
      return;
    }
    // headlight / sheen / prism: a diagonal light band sweeping right → left
    final strength = 0.10 + 0.16 * r.stepFraction;
    final cx = size.width * (1.5 - 2.1 * t);
    final band = Rect.fromLTWH(cx - size.width * 0.4, 0, size.width * 0.8, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0x00FFFFFF),
            r.glowColor.withValues(alpha: strength * op),
            Color.fromRGBO(255, 255, 255, 0.2 * op),
            r.glowColor.withValues(alpha: strength * op),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.t != t || o.r != r;
}
