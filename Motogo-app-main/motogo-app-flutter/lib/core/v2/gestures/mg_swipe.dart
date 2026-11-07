import 'package:flutter/widgets.dart';

import '../motion/mg_haptic.dart';
import '../motion/mg_motion.dart';

/// Swipe thresholds of the v2 look (design G3 / G4 / G6 / G2) — the only
/// values gestures may use.
abstract final class MgSwipe {
  /// Segment / month / pager switch: distance OR velocity.
  static const commitDistance = 72.0;
  static const commitVelocity = 450.0;

  /// Content follows the finger ×.35, ×.15 where there is no neighbour.
  static const follow = .35;
  static const endRubber = .15;

  /// Photo viewer swipe-down close (today's app values).
  static const dismissDistance = 100.0;
  static const dismissVelocity = 800.0;

  /// Sheet pulled from its body: 25 % of its height or 700 px/s.
  static const sheetDismissFraction = .25;
  static const sheetDismissVelocity = 700.0;

  /// iOS edge back on guarded pages: 20 px strip, 30 % width or 700 px/s.
  static const edgeWidth = 20.0;
  static const edgeCommitFraction = .3;
  static const edgeCommitVelocity = 700.0;
}

/// Horizontal swipe between in-place segments (design G4 b: Rezervace
/// filters, Zprávy notes / threads, Moje sub-tabs). Every swipe has its tap
/// twin (the segmented control above it) — this only calls [onChanged] with
/// the neighbour value, never anything new.
///
/// The body follows the finger ×.35 (×.15 at the ends) and dims to .85;
/// release past 72 px or faster than 450 px/s → `selectionClick` +
/// `onChanged(neighbour)`, else it springs back (300, `MgMotion.spring`).
/// [progress] = signed fraction of the width toward the target, POSITIVE
/// toward the NEXT value (finger moving left) — pass it straight to
/// `MgSegmented.dragProgress` so the thumb tracks the drag. Vertical scroll
/// wins when it passes the slop first; a deeper horizontal scrollable (chip
/// rail, carousel, photo pager) keeps its own drags. Reduced motion: no
/// follow, the switch happens on release.
class MgSwipeSegments<T> extends StatefulWidget {
  final List<T> values;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget child;
  final bool enabled;
  final ValueNotifier<double>? progress;

  const MgSwipeSegments({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
    required this.child,
    this.enabled = true,
    this.progress,
  });

  @override
  State<MgSwipeSegments<T>> createState() => _MgSwipeSegmentsState<T>();
}

class _MgSwipeSegmentsState<T> extends State<MgSwipeSegments<T>> with SingleTickerProviderStateMixin {
  double _dx = 0;
  double _from = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: MgMotion.thumb)
    ..addListener(() => _set(_from * (1 - MgMotion.spring.transform(_back.value))));

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  /// Neighbour in direction [dir] (+1 next, −1 previous) or null.
  T? _neighbour(int dir) {
    final i = widget.values.indexOf(widget.value);
    final j = i + dir;
    if (i < 0 || dir == 0 || j < 0 || j >= widget.values.length) return null;
    return widget.values[j];
  }

  double get _width => (context.size?.width ?? 0) > 0 ? context.size!.width : 360;

  void _set(double dx) {
    if (!mounted) return;
    setState(() => _dx = dx);
    final p = widget.progress;
    if (p != null) {
      final dir = dx < 0 ? 1 : -1;
      final f = _neighbour(dir) == null ? MgSwipe.endRubber : 1.0;
      p.value = (-dx / _width * f).clamp(-1.0, 1.0);
    }
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final fling = v.abs() >= MgSwipe.commitVelocity;
    final dir = fling ? (v < 0 ? 1 : -1) : (_dx < 0 ? 1 : -1);
    final n = _neighbour(dir);
    final far = _dx.abs() >= MgSwipe.commitDistance && (_dx < 0 ? 1 : -1) == dir;
    if (n != null && (fling || far)) {
      MgHaptic.select();
      _back.stop();
      _set(0);
      widget.onChanged(n);
      return;
    }
    _springBack();
  }

  void _springBack() {
    if (!mounted) return;
    if (MgMotion.reduced(context) || _dx == 0) {
      _set(0);
      return;
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final reduced = MgMotion.reduced(context);
    final dir = _dx < 0 ? 1 : -1;
    final f = _neighbour(dir) == null ? MgSwipe.endRubber : MgSwipe.follow;
    final shift = reduced ? 0.0 : _dx * f;
    final fade = reduced ? 1.0 : 1 - 0.15 * (_dx.abs() / (_width / 2)).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _back.stop(),
      onHorizontalDragUpdate: (d) => _set(_dx + (d.primaryDelta ?? 0)),
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _springBack,
      child: Opacity(
        opacity: fade,
        child: Transform.translate(offset: Offset(shift, 0), child: widget.child),
      ),
    );
  }
}
