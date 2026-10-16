import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../icons/mg_icon.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'rank_marks.dart';
import 'rank_provider.dart';
import 'rank_tokens.dart';

/// Logo / avatar in the tier ring (`.rk-frame`): solid 3 px (Silnice) ·
/// conic metal (Kovy) · 12-facet conic (Drahokamy) · double ring + crown
/// (VIP) · legend conic + laurel (Legenda), progress arc, level badge and
/// step marks on the ring. The child (logo tile / avatar) is never
/// recoloured. Used by the Home logo row, Profil avatar, nav PROFIL tab,
/// AI FAB ring and the ladder. [rank] / [arcPct] default to the providers.
class RankFrame extends ConsumerWidget {
  final Widget child;

  /// Outer size of the frame (ring included; arc / badge / glyph overflow).
  final double size;
  final bool circle;

  /// Ring thickness (default: 5 for the rounded logo frame, tier width for
  /// circles).
  final double? ringWidth;
  final RankTokens? rank;

  /// Progress inside the level (0–100); null = provider value.
  final double? arcPct;
  final bool showArc;
  final bool showLevel;
  final bool showGlyph;
  final bool showMarks;
  final bool glow;

  /// Distance of the progress arc from the frame edge.
  final double arcGap;
  final String? semanticLabel;

  const RankFrame({
    super.key,
    required this.child,
    this.size = 62,
    this.circle = false,
    this.ringWidth,
    this.rank,
    this.arcPct,
    this.showArc = true,
    this.showLevel = true,
    this.showGlyph = true,
    this.showMarks = true,
    this.glow = true,
    this.arcGap = 5.75,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankTokens r = rank ?? ref.watch(rankTokensProvider);
    final double? pct = arcPct ?? (showArc ? ref.watch(rankArcPctProvider) : null);
    final pad = ringWidth ?? (circle ? r.ringWidth : 5.0);
    final radius = circle ? size / 2 : 18 * size / 62;
    final innerR = math.max(0.0, radius - pad);
    final arc = showArc && !r.isBrand && r.arc != null && pct != null;
    final double marksScale = circle ? 0 : _ringMarkScale(r);

    Widget frame = CustomPaint(
      painter: _RingPainter(r, circle, radius, glow),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(innerR),
          child: SizedBox.expand(child: child),
        ),
      ),
    );
    frame = SizedBox(width: size, height: size, child: frame);

    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        if (arc)
          Positioned(
            left: -arcGap,
            top: -arcGap,
            right: -arcGap,
            bottom: -arcGap,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ArcPainter(r.arc!, pct.clamp(0.0, 100.0) / 100, circle, radius + arcGap),
              ),
            ),
          ),
        frame,
        if (showMarks && marksScale > 0 && !r.isBrand && r.tier != RankTier.legend)
          Positioned(
            left: 0,
            right: 0,
            bottom: pad / 2 - RankMarks.sizeFor(r, marksScale).height / 2,
            child: Center(
              child: RankMarks(
                rank: r,
                scale: marksScale,
                litColor: r.ctaLabel.withValues(alpha: 0.85),
                dimColor: r.ctaLabel.withValues(alpha: 0.24),
              ),
            ),
          ),
        if (showGlyph && r.glyph == RankGlyph.crown)
          Positioned(
            top: -15 * size / 62,
            left: 0,
            right: 0,
            child: Center(
              child: MgIcon(MgIcons.crown, size: 22 * size / 62, color: const Color(0xFFD4AF37)),
            ),
          ),
        if (showGlyph && r.glyph == RankGlyph.laurel)
          Positioned(
            left: -12 * size / 62,
            right: -12 * size / 62,
            bottom: -10 * size / 62,
            height: 30 * size / 62,
            child: Center(
              child: MgIcon(MgIcons.laurel, size: 30 * size / 62, color: const Color(0xFFFFD34D)),
            ),
          ),
        if (showLevel && !r.isBrand)
          Positioned(
            right: -7 * size / 62,
            bottom: -7 * size / 62,
            child: _LevelBadge(r),
          ),
      ],
    );
    if (semanticLabel == null) return ExcludeSemantics(child: stack);
    return Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: stack));
  }

  /// Marks on the logo ring: pitch 5 / 6 / 3.6 / 6 px (row ≤ 26 px).
  double _ringMarkScale(RankTokens r) => switch (r.tier) {
        RankTier.road => 0.5,
        RankTier.metal => 0.75,
        RankTier.jewel => 0.45,
        RankTier.vip => 0.6,
        RankTier.legend => 0,
      };
}

class _LevelBadge extends StatelessWidget {
  final RankTokens r;
  const _LevelBadge(this.r);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MgColors.night,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: r.uiDark, width: 1.5),
      ),
      child: Text(
        '${r.level}',
        style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w900, height: 1, color: r.accentOnDark)),
      ),
    );
  }
}

/// Ring paint per tier (CSS conic angles start at 12 o'clock; Flutter sweeps
/// start at 3 o'clock → rotation − 90°).
Shader? ringShader(RankTokens r, Rect rect) {
  final c = r.ring;
  double rad(double deg) => (deg - 90) * math.pi / 180;
  switch (r.ringKind) {
    case RankRingKind.solid:
      return null;
    case RankRingKind.metal:
    case RankRingKind.legend:
      return SweepGradient(colors: c, transform: GradientRotation(rad(210))).createShader(rect);
    case RankRingKind.jewel:
      return SweepGradient(colors: c, transform: GradientRotation(rad(20))).createShader(rect);
    case RankRingKind.vip:
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: c,
        stops: const [0, 0.5, 1],
      ).createShader(rect);
  }
}

class _RingPainter extends CustomPainter {
  final RankTokens r;
  final bool circle, glow;
  final double radius;
  _RingPainter(this.r, this.circle, this.radius, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    if (glow) {
      final blur = 16 + (12 * r.stepFraction).roundToDouble();
      canvas.drawRRect(
        rr.inflate(1),
        Paint()
          ..color = r.glowColor.withValues(alpha: r.row.glowAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, blur / 2),
      );
    }
    final ring2 = r.ring2;
    if (ring2 != null) {
      canvas.drawRRect(rr.inflate(1.5), Paint()..color = ring2);
    }
    final shader = ringShader(r, rect);
    final p = Paint();
    if (shader != null) {
      p.shader = shader;
    } else {
      p.color = r.ring.first;
    }
    canvas.drawRRect(rr, p);
    if (r.ringKind == RankRingKind.jewel) {
      // 12 facets: white .26 for 15° every 30° (from 8°).
      final colors = <Color>[];
      final stops = <double>[];
      for (var i = 0; i < 12; i++) {
        final a = i / 12, b = (i + 0.5) / 12, e = (i + 1) / 12;
        colors.addAll(const [Color(0x42FFFFFF), Color(0x42FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF)]);
        stops.addAll([a, b, b, e]);
      }
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = SweepGradient(
            colors: colors,
            stops: stops,
            transform: GradientRotation((8 - 90) * math.pi / 180),
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.r != r || o.radius != radius || o.glow != glow;
}

class _ArcPainter extends CustomPainter {
  final Color color;
  final double pct;
  final bool circle;
  final double radius;
  _ArcPainter(this.color, this.pct, this.circle, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.25);
    final path = Path();
    if (circle) {
      path.addArc(rect, -math.pi / 2, 2 * math.pi - 0.0001);
    } else {
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - 1.25)));
      // start at top centre, clockwise
      path
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rr.right - rr.trRadiusX, rect.top)
        ..arcToPoint(Offset(rect.right, rect.top + rr.trRadiusY), radius: rr.trRadius)
        ..lineTo(rect.right, rect.bottom - rr.brRadiusY)
        ..arcToPoint(Offset(rect.right - rr.brRadiusX, rect.bottom), radius: rr.brRadius)
        ..lineTo(rect.left + rr.blRadiusX, rect.bottom)
        ..arcToPoint(Offset(rect.left, rect.bottom - rr.blRadiusY), radius: rr.blRadius)
        ..lineTo(rect.left, rect.top + rr.tlRadiusY)
        ..arcToPoint(Offset(rect.left + rr.tlRadiusX, rect.top), radius: rr.tlRadius)
        ..lineTo(rect.center.dx, rect.top);
    }
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = MgColors.white(0.18);
    canvas.drawPath(path, track);
    if (pct <= 0) return;
    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * pct), prog);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.pct != pct || o.color != color || o.radius != radius;
}
