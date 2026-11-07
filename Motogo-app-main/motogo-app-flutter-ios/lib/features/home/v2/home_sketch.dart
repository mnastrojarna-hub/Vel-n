import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';

/// Ride detail with swipe siblings (same push + extra as `RideCard`).
void homePushRide(BuildContext context, String id, List<String> siblings) =>
    GoRouter.maybeOf(context)?.push('/ride/$id', extra: siblings);

/// Route detail with swipe siblings (same push + extra as the routes list).
void homePushRoute(BuildContext context, String id, List<String> siblings) =>
    GoRouter.maybeOf(context)?.push('/routes/$id', extra: siblings);

/// Little route sketch from track / waypoint coordinates on a dark tile,
/// drawn once (900 ms; instant under reduced motion). No points → glyph.
class HomeSketch extends StatelessWidget {
  final List<LatLng> points;
  final double width;
  final double height;
  final bool private;
  final bool tile;
  final double stroke;
  const HomeSketch({
    super.key,
    required this.points,
    required this.width,
    required this.height,
    this.private = false,
    this.tile = true,
    this.stroke = 2.2,
  });

  @override
  Widget build(BuildContext context) {
    final color = private ? MgColors.onDarkLead : MgColors.neon;
    final body = points.length < 2
        ? Center(child: MgIcon(MgIcons.route, size: math.min(width, height) * 0.45, color: color))
        : MgProgressOnce(
            duration: const Duration(milliseconds: 900),
            delay: const Duration(milliseconds: 300),
            builder: (_, t) => CustomPaint(painter: _SketchPainter(points, color, t, stroke, !tile)),
          );
    if (!tile) return SizedBox(width: width, height: height, child: body);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [MgColors.glow, MgColors.panel, MgColors.night],
            stops: [0, 0.6, 1],
          ),
        ),
        child: body,
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  final List<LatLng> pts;
  final Color color;
  final double t;
  final double stroke;
  final bool halo;
  _SketchPainter(this.pts, this.color, this.t, this.stroke, this.halo);

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.longitude);
      maxX = math.max(maxX, p.longitude);
      minY = math.min(minY, p.latitude);
      maxY = math.max(maxY, p.latitude);
    }
    final pad = size.shortestSide * 0.16;
    final w = size.width - 2 * pad, h = size.height - 2 * pad;
    final kx = math.cos((minY + maxY) / 2 * math.pi / 180);
    final spanX = math.max((maxX - minX) * kx, 1e-9), spanY = math.max(maxY - minY, 1e-9);
    final s = math.min(w / spanX, h / spanY);
    final ox = pad + (w - spanX * s) / 2, oy = pad + (h - spanY * s) / 2;
    Offset map(LatLng p) => Offset(ox + (p.longitude - minX) * kx * s, oy + (maxY - p.latitude) * s);
    final step = math.max(1, pts.length ~/ 160);
    final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (var i = step; i < pts.length; i += step) {
      final o = map(pts[i]);
      path.lineTo(o.dx, o.dy);
    }
    final last = map(pts.last);
    path.lineTo(last.dx, last.dy);
    Path drawn = path;
    if (t < 1) {
      drawn = Path();
      for (final PathMetric m in path.computeMetrics()) {
        drawn.addPath(m.extractPath(0, m.length * t), Offset.zero);
      }
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (halo) {
      canvas.drawPath(drawn, paint..color = MgColors.nightA(0.7)..strokeWidth = stroke + 4);
    }
    canvas.drawPath(drawn, paint..color = color..strokeWidth = stroke);
    if (t >= 1) {
      final dot = Paint()..color = MgColors.onDark;
      canvas.drawCircle(map(pts.first), stroke + 1, dot);
    }
  }

  @override
  bool shouldRepaint(_SketchPainter o) => o.t != t || o.pts != pts || o.color != color;
}
