import 'package:flutter/material.dart';

import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import 'mg_swipe.dart';

/// iOS left-edge swipe back for GUARDED pages with in-screen steps
/// (`PopScope(canPop: false)`: register, reset password, reservation-edit
/// intents — design G2). The system Cupertino gesture is off there, so this
/// 20 px strip forwards the swipe to the SAME [onBack] the ‹ control runs:
/// the page follows the finger 1:1 (≤ 40 % width) with a 12 px ink edge
/// shadow left of it over the canvas; release past 30 % of the width or faster than 700 px/s →
/// [onBack], else it slides back over `MgMotion.sheet`. Android / other
/// platforms: [child] only (predictive back + the existing confirm).
/// Reduced motion: no follow, same release rule. Use ONLY where the route's
/// own back gesture is disabled.
class MgEdgeBack extends StatefulWidget {
  final VoidCallback onBack;
  final Widget child;
  final bool enabled;
  const MgEdgeBack({super.key, required this.onBack, required this.child, this.enabled = true});

  @override
  State<MgEdgeBack> createState() => _MgEdgeBackState();
}

class _MgEdgeBackState extends State<MgEdgeBack> with SingleTickerProviderStateMixin {
  double _dx = 0;
  double _from = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: MgMotion.sheet)
    ..addListener(() => setState(() => _dx = _from * (1 - MgMotion.emphasized.transform(_back.value))));

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  /// Width of the box, read when a drag starts (never during build).
  double _width = 360;

  void _measure() {
    final w = context.size?.width ?? 0;
    if (w > 0) _width = w;
  }

  void _end(double v) {
    final commit = _dx >= _width * MgSwipe.edgeCommitFraction || v >= MgSwipe.edgeCommitVelocity;
    if (commit) {
      setState(() => _dx = 0);
      widget.onBack();
      return;
    }
    if (_dx == 0 || MgMotion.reduced(context)) {
      setState(() => _dx = 0);
      return;
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Theme.of(context).platform != TargetPlatform.iOS) return widget.child;
    final shift = MgMotion.reduced(context) ? 0.0 : _dx.clamp(0.0, _width * 0.4);
    // Fixed child list (no `if` before the page): the page element and its
    // state are never re-created when a drag starts.
    return Stack(children: [
      // The uncovered strip shows the canvas, never the black under an
      // opaque route.
      Positioned.fill(child: ColoredBox(color: shift > 0 ? MgColors.canvas : const Color(0x00000000))),
      Transform.translate(
        offset: Offset(shift, 0),
        child: Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
          widget.child,
          // 12 px ink edge shadow OUTSIDE the page's left edge (no veil
          // over the page itself).
          if (shift > 0)
            Positioned(
              left: -12,
              top: 0,
              bottom: 0,
              width: 12,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [MgColors.inkA(0), MgColors.inkA(0.18)]),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: MgSwipe.edgeWidth,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _measure();
            _back.stop();
          },
          onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + (d.primaryDelta ?? 0)).clamp(0.0, _width)),
          onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
          onHorizontalDragCancel: () => _end(0),
        ),
      ),
    ]);
  }
}
