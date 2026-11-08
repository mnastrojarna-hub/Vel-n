import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../motion/mg_motion.dart';
import 'mg_chrome_metrics.dart';
import 'mg_hide_on_scroll.dart';

/// The bottom block (caption: name, price, CTA) of a full-screen card in the
/// v2 shell (owner 2026-11-08 "fotka plus nějaký ten základní popisek"):
/// the card is as tall as the body with the bars FOLDED, so while the nav
/// is unfolded (64) its foot is under / below the nav. [child] rides up by
/// the bottom chrome that covers the card's foot — the unfolded nav, the
/// status strips and [extra] (a button slot shown only with the bars, e.g.
/// Domů's scroll-to-top) — in step with the nav (`MgMotion.sticky` +
/// emphasized, instant under reduced motion), and only as far as the card
/// has [room] ([room] = the card's height): a card grown by a very large
/// text size keeps its layout. [child] = the Stack's non-positioned bottom
/// block; the lift adds empty space under it (taps there reach the photo)
/// and never changes the card's height. Outside the shell: no lift.
class MgChromeLift extends StatelessWidget {
  final double room;
  final double extra;
  final Widget child;
  const MgChromeLift({super.key, required this.room, this.extra = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = MgChromeScope.maybeOf(context);
    var lift = 0.0;
    if (s != null) {
      final open = s.navVisible && !MgBarsScope.hiddenOf(context);
      lift = s.notifier!.stripsHeight + (open ? MgChrome.nav + extra : 0);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: lift),
      duration: MgMotion.of(context, MgMotion.sticky),
      curve: MgMotion.emphasized,
      child: child,
      builder: (_, v, child) => _Lift(lift: v, room: room, child: child),
    );
  }
}

class _Lift extends SingleChildRenderObjectWidget {
  final double lift;
  final double room;
  const _Lift({required this.lift, required this.room, super.child});

  @override
  RenderMgChromeLift createRenderObject(BuildContext context) => RenderMgChromeLift(lift: lift, room: room);

  @override
  void updateRenderObject(BuildContext context, RenderMgChromeLift renderObject) {
    renderObject
      ..lift = lift
      ..room = room;
  }
}

/// Lays the child out at its natural height h and takes h + min([lift],
/// [room] − h) (≥ 0), the child at the top: bottom-aligned by the parent,
/// the child sits that much higher.
class RenderMgChromeLift extends RenderShiftedBox {
  RenderMgChromeLift({required double lift, required double room})
      : _lift = lift,
        _room = room,
        super(null);

  double _lift;
  set lift(double v) {
    if (v == _lift) return;
    _lift = v;
    markNeedsLayout();
  }

  double _room;
  set room(double v) {
    if (v == _room) return;
    _room = v;
    markNeedsLayout();
  }

  /// The applied lift (≤ [lift]).
  double shift = 0;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      shift = 0;
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    shift = math.min(math.max(0.0, _lift), math.max(0.0, _room - c.size.height));
    (c.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(Size(c.size.width, c.size.height + shift));
  }

  @override
  double computeMinIntrinsicHeight(double width) => child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final s = c.getDryLayout(constraints);
    final lift = math.min(math.max(0.0, _lift), math.max(0.0, _room - s.height));
    return constraints.constrain(Size(s.width, s.height + lift));
  }
}
