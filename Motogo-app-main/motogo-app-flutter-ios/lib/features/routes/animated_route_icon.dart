import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Jemně animovaná ikona „Trasy" do hlavičky obrazovky. Klikatá silnice
/// s přerušovanou středovou čarou, po které v nekonečné smyčce jede světlá
/// tečka (jezdec na trase) — nenápadné „wow" bez rušivého blikání.
class AnimatedRouteIcon extends StatefulWidget {
  final double size;
  const AnimatedRouteIcon({super.key, this.size = 28});

  @override
  State<AnimatedRouteIcon> createState() => _AnimatedRouteIconState();
}

class _AnimatedRouteIconState extends State<AnimatedRouteIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _RoutePainter(_c.value)),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final double t; // fáze animace 0..1
  _RoutePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Klikatá „silnice" — spojitá S-křivka přes celý rámeček.
    final path = Path()
      ..moveTo(w * 0.16, h * 0.88)
      ..cubicTo(w * 0.02, h * 0.56, w * 0.42, h * 0.54, w * 0.5, h * 0.4)
      ..cubicTo(w * 0.6, h * 0.24, w * 0.94, h * 0.32, w * 0.84, h * 0.08);

    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(path, road);

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round
      ..color = MotoGoColors.greenDark.withValues(alpha: 0.55);

    for (final m in path.computeMetrics()) {
      // Přerušovaná středová čára.
      var d = w * 0.05;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + w * 0.05), dash);
        d += w * 0.12;
      }
      // Jedoucí tečka po trase (jezdec).
      final tan = m.getTangentForOffset(m.length * t);
      if (tan != null) {
        canvas.drawCircle(tan.position, w * 0.14,
            Paint()..color = MotoGoColors.green);
        canvas.drawCircle(
            tan.position,
            w * 0.14,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 0.035
              ..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.t != t;
}
