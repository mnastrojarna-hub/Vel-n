import 'package:flutter/widgets.dart';

import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import 'rank_tokens.dart';

/// Step marks inside a tier (owner 2026-10-15: ranks 3/4/5 must not look
/// alike): Silnice lane dashes 1–5 · Kovy rivets 1–4 · Drahokamy facets 1–7 ·
/// VIP crowns 1–3 · Legenda none. Dim = all steps of the tier, lit = steps
/// reached. Lit marks draw in once (700 ms; instant under reduced motion).
class RankMarks extends StatelessWidget {
  final RankTokens rank;
  final Color litColor;
  final Color dimColor;

  /// 1 = element size (pitch 8–10 px); the CTA uses .8.
  final double scale;
  final bool animate;

  const RankMarks({
    super.key,
    required this.rank,
    required this.litColor,
    required this.dimColor,
    this.scale = 1,
    this.animate = true,
  });

  /// Size the marks occupy for [rank] at [scale] (zero for Legenda / brand).
  static Size sizeFor(RankTokens rank, [double scale = 1]) {
    final g = _geom(rank.tier);
    if (g == null || rank.isBrand) return Size.zero;
    return Size((rank.steps * g.pitch - g.gap) * scale, g.height * scale);
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(rank, scale);
    if (size.isEmpty) return const SizedBox.shrink();
    Widget paint(double t) => CustomPaint(
          size: size,
          painter: _MarksPainter(rank, litColor, dimColor, scale, t),
        );
    if (!animate) return ExcludeSemantics(child: paint(1));
    return ExcludeSemantics(
      child: MgProgressOnce(
        duration: MgMotion.marks,
        delay: const Duration(milliseconds: 400),
        curve: const Cubic(0.2, 0.8, 0.2, 1),
        builder: (_, t) => paint(t),
      ),
    );
  }
}

class _Geom {
  final double pitch, gap, height;
  const _Geom(this.pitch, this.gap, this.height);
}

_Geom? _geom(RankTier t) => switch (t) {
      RankTier.road => const _Geom(10, 3, 4),
      RankTier.metal => const _Geom(8, 3, 5),
      RankTier.jewel => const _Geom(8, 2, 6),
      RankTier.vip => const _Geom(10, 2, 6),
      RankTier.legend => null,
    };

class _MarksPainter extends CustomPainter {
  final RankTokens rank;
  final Color lit, dim;
  final double scale, t;
  _MarksPainter(this.rank, this.lit, this.dim, this.scale, this.t);

  Path _shape(RankTier tier, double x, double h) {
    final p = Path();
    switch (tier) {
      case RankTier.road:
        p.addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 0, 7 * scale, h), Radius.circular(1.3 * scale)));
      case RankTier.metal:
        p.addOval(Rect.fromLTWH(x, 0, 5 * scale, 5 * scale));
      case RankTier.jewel:
        final s = scale;
        p
          ..moveTo(x + 3 * s, 0)
          ..lineTo(x + 6 * s, 3 * s)
          ..lineTo(x + 3 * s, 6 * s)
          ..lineTo(x, 3 * s)
          ..close();
      case RankTier.vip:
        final s = scale;
        p
          ..moveTo(x, 6 * s)
          ..lineTo(x, 1.6 * s)
          ..lineTo(x + 2.1 * s, 3.5 * s)
          ..lineTo(x + 4 * s, 0)
          ..lineTo(x + 5.9 * s, 3.5 * s)
          ..lineTo(x + 8 * s, 1.6 * s)
          ..lineTo(x + 8 * s, 6 * s)
          ..close();
      case RankTier.legend:
        break;
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _geom(rank.tier);
    if (g == null) return;
    final dimP = Paint()..color = dim;
    final litP = Paint()..color = lit;
    final litW = (rank.step * g.pitch - g.gap) * scale * t;
    for (var i = 0; i < rank.steps; i++) {
      final x = i * g.pitch * scale;
      final shape = _shape(rank.tier, x, size.height);
      canvas.drawPath(shape, dimP);
      if (i < rank.step) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, litW, size.height));
        canvas.drawPath(shape, litP);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_MarksPainter o) =>
      o.t != t || o.lit != lit || o.dim != dim || o.rank != rank || o.scale != scale;
}
