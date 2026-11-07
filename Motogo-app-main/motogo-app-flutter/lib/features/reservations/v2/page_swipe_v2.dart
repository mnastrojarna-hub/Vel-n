import 'package:flutter/widgets.dart';

import '../../../core/v2/gestures/mg_swipe.dart';
import '../../../core/v2/motion/mg_haptic.dart';

/// Page-level twin of `MgSwipeSegments` (gesture only, no visuals): a
/// horizontal swipe ANYWHERE on a segmented page — the header, the
/// segmented control, empty space under a short list, the lazily built
/// rest of a long list — switches to the neighbour segment, as the page-wide
/// swipe did before the follow-the-finger body. Same thresholds (MgSwipe
/// 72 px / 450 px/s) and the same callback as the tabs; nothing new. The
/// body's own `MgSwipeSegments` (deeper in the tree) wins inside its area,
/// a deeper horizontal scrollable (chip rail, carousel) keeps its drags,
/// and vertical scroll wins when it passes the slop first.
class V2PageSwipe extends StatefulWidget {
  /// +1 = next segment, −1 = previous; returns whether it switched (the
  /// haptic tick only then).
  final bool Function(int dir) onStep;
  final bool enabled;
  final Widget child;

  const V2PageSwipe({super.key, required this.onStep, required this.child, this.enabled = true});

  @override
  State<V2PageSwipe> createState() => _V2PageSwipeState();
}

class _V2PageSwipeState extends State<V2PageSwipe> {
  double _dx = 0;

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final fling = v.abs() >= MgSwipe.commitVelocity;
    final far = _dx.abs() >= MgSwipe.commitDistance;
    final dir = fling ? (v < 0 ? 1 : -1) : (_dx < 0 ? 1 : -1);
    _dx = 0;
    if ((fling || far) && widget.onStep(dir)) MgHaptic.select();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (d) => _dx += d.primaryDelta ?? 0,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => _dx = 0,
      child: widget.child,
    );
  }
}
