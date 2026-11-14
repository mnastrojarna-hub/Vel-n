import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import 'rank_tokens.dart';

/// Tier material + loop fx of the rank CTA (DESIGN_V22 §1.3), painted INSIDE
/// the button (clipped to [radius]). [seconds] = loop clock; null = static
/// (reduced motion, `loop: false`, disabled) → only the static material.
/// T0 shine (extra streaks at steps 3 / 5) · T1 brushed metal + sheen 4.8 s ·
/// T2 prism band + glints 3.6 s · T3 light orbiting the frame 4 s ·
/// T4 molten shine + embers 4.4 s. Never violet / pink (white / warm only).
class RankFxPainter extends CustomPainter {
  final RankTokens rank;
  final double? seconds;
  final double radius;
  RankFxPainter(this.rank, this.seconds, this.radius);

  static const _white = Color(0xFFFFFFFF);
  Color _w(double a) => _white.withValues(alpha: a.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rr);
    _material(canvas, size);
    final s = seconds;
    if (s != null) {
      switch (rank.tier) {
        case RankTier.road:
          final period = 3.2 - 0.15 * (rank.step - 1).clamp(0, 4);
          _streak(canvas, size, _phase(s, period), 0.5, 0.75, -22, 0.6);
          if (rank.step >= 3) _streak(canvas, size, _phase(s - 0.14, period), 0.24, 0.6, -22, 0.6);
          if (rank.step >= 5) _streak(canvas, size, _phase(s - 0.26, period), 0.14, 0.6, -22, 0.6);
        case RankTier.metal:
          _streak(canvas, size, _phase(s, 4.8), 0.42, 0.9, -12, 0.65, from: -1.7, to: 3.3);
        case RankTier.jewel:
          _glint(canvas, size, _phase(s, 3.6), 0.12, 0.20, 10);
          _glint(canvas, size, _phase(s - 0.3, 3.6), 0.57, 0.14, 8);
          _glint(canvas, size, _phase(s - 0.6, 3.6), 0.86, 0.56, 7);
        case RankTier.vip:
          _orbit(canvas, rr, _phase(s, 4.0));
        case RankTier.legend:
          _streak(canvas, size, _phase(s, 4.4), 0.55, 0.85, -22, 0.6,
              warm: true);
          _ember(canvas, size, _phase(s - 2.1, 4.4), 0.22);
          _ember(canvas, size, _phase(s - 3.0, 4.4), 0.73);
      }
    }
    canvas.restore();
  }

  double _phase(double s, double period) {
    final v = (s % period) / period;
    return v < 0 ? v + 1 : v;
  }

  void _material(Canvas canvas, Size size) {
    if (rank.tier == RankTier.metal) {
      final top = Rect.fromLTWH(0, 0, size.width, size.height * 0.46);
      canvas.drawRect(
        top,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_w(0.30), _w(0)],
          ).createShader(top),
      );
      final line = Paint()..color = _w(0.07);
      for (double y = 0; y < size.height; y += 3) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
    } else if (rank.tier == RankTier.jewel) {
      final k = rank.whiteLabel ? 0.5 : 1.0;
      final r = Offset.zero & size;
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: const Alignment(-1, -0.47),
            end: const Alignment(1, 0.47),
            colors: [_w(0), _w(0), _w(0.20 * k), _w(0), _w(0.12 * k), _w(0)],
            stops: const [0, 0.28, 0.29, 0.46, 0.62, 0.63],
          ).createShader(r),
      );
    }
  }

  /// Diagonal light streak sweeping left → right in the last part of the
  /// cycle ([hold] = share of the cycle it waits off-screen).
  void _streak(Canvas canvas, Size size, double p, double widthK, double peak,
      double skewDeg, double hold,
      {double from = -1.6, double to = 3.2, bool warm = false}) {
    if (p < hold) return;
    final q = Curves.easeInOut.transform(((p - hold) / (1 - hold)).clamp(0.0, 1.0));
    final w = size.width * widthK;
    final x = w * (from + (to - from) * q);
    final rect = Rect.fromLTWH(x, -size.height * 0.2, w, size.height * 1.4);
    final colors = warm
        ? [const Color(0x00FFF4D6), const Color(0xD9FFF4D6), const Color(0x4DFFB000), const Color(0x00FFB000)]
        : [_w(0), _w(peak), _w(0)];
    canvas.save();
    canvas.translate(0, size.height / 2);
    canvas.skew(math.tan(skewDeg * math.pi / 180), 0);
    canvas.translate(0, -size.height / 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: colors).createShader(rect),
    );
    canvas.restore();
  }

  /// 4-point star glint: hidden 0–58 %, full at 66 %, gone from 76 %.
  void _glint(Canvas canvas, Size size, double p, double fx, double fy, double d) {
    double scale, op;
    if (p < 0.58 || p >= 0.76) return;
    if (p < 0.66) {
      final k = (p - 0.58) / 0.08;
      scale = k;
      op = k;
    } else {
      final k = (p - 0.66) / 0.10;
      scale = 1 - k;
      op = 1 - k;
    }
    final c = Offset(size.width * fx + d / 2, size.height * fy + d / 2);
    final h = d / 2 * scale;
    final path = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + h * 0.22, c.dy - h * 0.22)
      ..lineTo(c.dx + h, c.dy)
      ..lineTo(c.dx + h * 0.22, c.dy + h * 0.22)
      ..lineTo(c.dx, c.dy + h)
      ..lineTo(c.dx - h * 0.22, c.dy + h * 0.22)
      ..lineTo(c.dx - h, c.dy)
      ..lineTo(c.dx - h * 0.22, c.dy - h * 0.22)
      ..close();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(math.pi / 4 * (p < 0.66 ? (p - 0.58) / 0.08 : 1 + (p - 0.66) / 0.10));
    canvas.translate(-c.dx, -c.dy);
    canvas.drawPath(path, Paint()..color = _w(op));
    canvas.restore();
  }

  /// VIP: a bright arc of light travelling around the 1.5 px frame.
  void _orbit(Canvas canvas, RRect rr, double p) {
    final rect = rr.outerRect;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = SweepGradient(
        colors: [_w(0), _w(0), _w(0.95), _w(0)],
        stops: const [0, 0.68, 0.80, 0.92],
        transform: GradientRotation(2 * math.pi * p),
      ).createShader(rect);
    canvas.drawRRect(rr.deflate(0.75), paint);
  }

  /// Legenda ember: rises 16 px and fades (hidden 0–55 %).
  void _ember(Canvas canvas, Size size, double p, double fx) {
    if (p < 0.55) return;
    final k = (p - 0.55) / 0.45;
    final op = k < 0.155 ? k / 0.155 : 1 - (k - 0.155) / 0.845;
    final y = size.height - 5 - 16 * k;
    final c = Offset(size.width * fx, y);
    canvas.drawCircle(
      c,
      4 + 2,
      Paint()
        ..color = const Color(0xFFFF8C00).withValues(alpha: 0.8 * op)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(c, 2 * (0.6 + 0.4 * k), Paint()..color = const Color(0xFFFFF4D6).withValues(alpha: op));
  }

  @override
  bool shouldRepaint(RankFxPainter o) =>
      o.seconds != seconds || o.rank != rank || o.radius != radius;
}
