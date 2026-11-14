import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/motion/mg_once_progress.dart';

/// Route line that draws itself ONCE per route per session (V21 §2.5:
/// 1 600 ms in the detail map; static under reduced motion / on return).
/// [build] receives the visible prefix of [points] (cut by length, the
/// last point interpolated) and returns the layer — the old polylines.
class RouteLineDrawV2 extends StatefulWidget {
  final List<LatLng> points;
  final String sessionKey;
  final Widget Function(List<LatLng> visible) build;
  const RouteLineDrawV2({super.key, required this.points, required this.sessionKey, required this.build});

  @override
  State<RouteLineDrawV2> createState() => _RouteLineDrawV2State();
}

class _RouteLineDrawV2State extends State<RouteLineDrawV2> {
  static const _d = Distance();
  List<double> _cum = const [];
  List<LatLng>? _for;

  /// Cumulative length (m) — computed once per geometry, not per frame.
  List<double> _lengths() {
    if (!identical(_for, widget.points)) {
      _for = widget.points;
      final out = <double>[0];
      for (var i = 1; i < widget.points.length; i++) {
        out.add(out.last + _d.as(LengthUnit.Meter, widget.points[i - 1], widget.points[i]));
      }
      _cum = out;
    }
    return _cum;
  }

  List<LatLng> _prefix(double t) {
    final pts = widget.points;
    if (t >= 1 || pts.length < 2) return pts;
    final cum = _lengths();
    final target = cum.last * t;
    var i = 1;
    while (i < cum.length && cum[i] < target) {
      i++;
    }
    if (i >= cum.length) return pts;
    final seg = cum[i] - cum[i - 1];
    final f = seg <= 0 ? 0.0 : (target - cum[i - 1]) / seg;
    final a = pts[i - 1], b = pts[i];
    return [...pts.sublist(0, i), LatLng(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f)];
  }

  @override
  Widget build(BuildContext context) => MgOnceProgress(
        duration: const Duration(milliseconds: 1600),
        curve: MgMotion.ease,
        sessionKey: widget.sessionKey,
        builder: (_, t) => widget.build(_prefix(t)),
      );
}

/// Map pin that pops in once (scale 0 → 1.08 → 1 over `MgMotion.pop`)
/// [index] × 70 ms after the line starts (V21 §2.5); static when reduced.
class RoutePinPopV2 extends StatelessWidget {
  final int index;
  final String sessionKey;
  final Widget child;
  const RoutePinPopV2({super.key, required this.index, required this.sessionKey, required this.child});

  @override
  Widget build(BuildContext context) => MgOnceProgress(
        duration: MgMotion.pop,
        curve: Curves.linear,
        delay: Duration(milliseconds: 70 * index.clamp(0, 12)),
        sessionKey: '$sessionKey-pin-$index',
        builder: (_, t) {
          final s = t < 0.4 ? 1.08 * (t / 0.4) : 1.08 - 0.08 * ((t - 0.4) / 0.6);
          return Transform.scale(scale: s, child: child);
        },
      );
}
