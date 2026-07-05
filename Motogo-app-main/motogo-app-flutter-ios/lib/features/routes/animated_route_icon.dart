import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Jemně animovaná ikona „Trasy" do hlavičky obrazovky. Místo uzavřeného kruhu
/// je to natažená vlnitá čára (profil silnice) s tečkami (zastávky na trase).
/// Světlá tečka (jezdec) po čáře jede zleva doprava — u KAŽDÉ tečky se na 0,5 s
/// zastaví, pak pokračuje doprava, na konci zmizí vpravo a znovu se objeví vlevo.
class AnimatedRouteIcon extends StatefulWidget {
  final double size;
  const AnimatedRouteIcon({super.key, this.size = 28});

  @override
  State<AnimatedRouteIcon> createState() => _AnimatedRouteIconState();
}

/// Jedna fáze časové osy jezdce — buď posun po trase, nebo zastávka na tečce.
class _Phase {
  final double from; // frakce délky trasy 0..1
  final double to;
  final bool pause;
  final double durMs;
  const _Phase(this.from, this.to, this.pause, this.durMs);
}

class _AnimatedRouteIconState extends State<AnimatedRouteIcon>
    with SingleTickerProviderStateMixin {
  // Tečky (zastávky) rozmístěné po délce trasy.
  static const List<double> _stops = [0.2, 0.5, 0.8];
  static const double _moveMs = 620; // posun mezi zastávkami
  static const double _pauseMs = 500; // zastavení u každé tečky (0,5 s)

  late final List<_Phase> _phases;
  late final double _totalMs;
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // Sestav časovou osu: 0 → tečka1 (pauza) → tečka2 (pauza) → … → 1.
    final targets = [0.0, ..._stops, 1.0];
    final phases = <_Phase>[];
    for (var i = 0; i < targets.length - 1; i++) {
      phases.add(_Phase(targets[i], targets[i + 1], false, _moveMs));
      // Pauza na každé viditelné tečce (ne na krajních koncích čáry).
      if (i + 1 < targets.length - 1) {
        phases.add(_Phase(targets[i + 1], targets[i + 1], true, _pauseMs));
      }
    }
    _phases = phases;
    _totalMs = phases.fold(0.0, (a, p) => a + p.durMs);

    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _totalMs.round()),
    )..repeat();
  }

  /// Mapuje globální fázi 0..1 na frakci délky trasy s pauzami u teček.
  double _riderFraction(double t) {
    var target = t * _totalMs;
    var acc = 0.0;
    for (final p in _phases) {
      if (target <= acc + p.durMs) {
        if (p.pause) return p.from;
        final local = ((target - acc) / p.durMs).clamp(0.0, 1.0);
        return p.from + (p.to - p.from) * Curves.easeInOut.transform(local);
      }
      acc += p.durMs;
    }
    return 1.0;
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
          builder: (_, __) => CustomPaint(
            painter: _RoutePainter(_riderFraction(_c.value)),
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final double riderT; // frakce délky trasy 0..1, kde je jezdec
  _RoutePainter(this.riderT);

  Path _buildPath(double w, double h) {
    // Natažená vlnitá čára — profil horské silnice (vlny + závěrečný „vrchol").
    final midY = h * 0.52;
    final amp = h * 0.24;
    return Path()
      ..moveTo(w * 0.04, midY + amp * 0.35)
      ..cubicTo(w * 0.18, midY - amp, w * 0.26, midY - amp,
          w * 0.40, midY + amp * 0.15)
      ..cubicTo(w * 0.50, midY + amp * 0.95, w * 0.58, midY + amp * 0.95,
          w * 0.68, midY - amp * 0.25)
      ..cubicTo(w * 0.80, midY - amp * 1.15, w * 0.88, midY - amp * 0.55,
          w * 0.96, midY - amp * 0.1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = _buildPath(w, h);

    // Silnice — bílý tah.
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(path, road);

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.028
      ..strokeCap = StrokeCap.round
      ..color = MotoGoColors.greenDark.withValues(alpha: 0.55);

    final metric = path.computeMetrics().first;
    final len = metric.length;

    // Přerušovaná středová čára.
    var d = w * 0.05;
    while (d < len) {
      canvas.drawPath(metric.extractPath(d, d + w * 0.05), dash);
      d += w * 0.12;
    }

    // Tečky (zastávky) na trase.
    final dotFill = Paint()..color = MotoGoColors.green;
    final dotRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..color = Colors.white.withValues(alpha: 0.9);
    for (final s in _AnimatedRouteIconState._stops) {
      final tan = metric.getTangentForOffset(len * s);
      if (tan == null) continue;
      canvas.drawCircle(tan.position, w * 0.075, dotFill);
      canvas.drawCircle(tan.position, w * 0.075, dotRing);
    }

    // Jezdec — mizí vpravo, znovu se objeví vlevo (fade na obou koncích trasy).
    final tan = metric.getTangentForOffset(len * riderT.clamp(0.0, 1.0));
    if (tan != null) {
      final fadeIn = (riderT / 0.08).clamp(0.0, 1.0);
      final fadeOut = ((1 - riderT) / 0.08).clamp(0.0, 1.0);
      final op = math.min(fadeIn, fadeOut);
      canvas.drawCircle(tan.position, w * 0.15,
          Paint()..color = MotoGoColors.green.withValues(alpha: op));
      canvas.drawCircle(
          tan.position,
          w * 0.15,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.035
            ..color = Colors.white.withValues(alpha: op));
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.riderT != riderT;
}
