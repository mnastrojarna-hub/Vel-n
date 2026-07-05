import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Jemně animovaná ikona „Trasy" do hlavičky obrazovky. Uzavřený okruh (smyčka)
/// s přerušovanou středovou čarou, po které v nekonečné smyčce jede světlá
/// tečka (jezdec na okruhu) — nenápadné „wow" bez rušivého blikání.
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

    // Uzavřený okruh (smyčka) — spojitá vlnitá klička, konec navazuje na začátek.
    // Čtyři kubiky kolem středu dají „okruh", který působí jako trasa, ne jen
    // kruh; `close()` spojí konec se začátkem.
    final cx = w * 0.5, cy = h * 0.5;
    final rx = w * 0.34, ry = h * 0.32;
    final k = 0.5522847; // aproximace kruhu Bézierem, mírně rozladěná = živější okruh
    final path = Path()
      ..moveTo(cx, cy - ry)
      ..cubicTo(cx + rx * k, cy - ry, cx + rx, cy - ry * k * 0.8, cx + rx, cy)
      ..cubicTo(cx + rx, cy + ry * k, cx + rx * k * 0.8, cy + ry, cx, cy + ry)
      ..cubicTo(cx - rx * k, cy + ry, cx - rx, cy + ry * k * 0.8, cx - rx, cy)
      ..cubicTo(cx - rx, cy - ry * k, cx - rx * k * 0.8, cy - ry, cx, cy - ry)
      ..close();

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
