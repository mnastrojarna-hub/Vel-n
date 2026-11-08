import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../motion/mg_motion.dart';

/// Hide-on-scroll fold of the bottom nav (owner 2026-11-08): the tab row
/// sinks into the bottom edge and only the nav's own bottom safe-area part
/// ([band] px of its night surface, behind the home indicator / gesture
/// bar) stays. The body above grows by the tab row's height and NOTHING in
/// it changes its insets: docks, status strips, the AI button and the
/// scroll padding sit on the band exactly as they sat on the nav, so the
/// bottom safe area stays right in both states and nothing jumps. Folded =
/// no taps, no semantics. `MgMotion.sticky` + emphasized, instant under
/// reduced motion. (The keyboard still removes the whole nav — the shell's
/// `MgStickySlide` around this.)
class MgNavBand extends StatelessWidget {
  final bool folded;
  final double band;
  final Widget child;
  const MgNavBand({super.key, required this.folded, required this.band, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: folded ? 0 : 1),
        duration: MgMotion.of(context, MgMotion.sticky),
        curve: MgMotion.emphasized,
        child: child,
        builder: (_, v, child) => IgnorePointer(
          ignoring: folded,
          child: ExcludeSemantics(
            excluding: folded,
            child: _NavBandBox(progress: v, band: band, child: child),
          ),
        ),
      );
}

class _NavBandBox extends SingleChildRenderObjectWidget {
  final double progress;
  final double band;
  const _NavBandBox({required this.progress, required this.band, super.child});

  @override
  RenderMgNavBand createRenderObject(BuildContext context) => RenderMgNavBand(progress: progress, band: band);

  @override
  void updateRenderObject(BuildContext context, RenderMgNavBand renderObject) {
    renderObject
      ..progress = progress
      ..band = band;
  }
}

/// Lays the child out at its natural height H and takes
/// `band + (H − band) × progress`; the child is bottom-aligned (its top
/// part leaves through the top edge, clipped) — fully open it paints
/// unclipped, so the nav's shadow above its top edge stays.
class RenderMgNavBand extends RenderProxyBox {
  RenderMgNavBand({required double progress, required double band})
      : _progress = progress,
        _band = band;

  double _progress;
  double get progress => _progress;
  set progress(double v) {
    if (v == _progress) return;
    _progress = v;
    markNeedsLayout();
  }

  double _band;
  set band(double v) {
    if (v == _band) return;
    _band = v;
    markNeedsLayout();
  }

  double _childH = 0;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  bool get _open => _progress >= 1;

  double get _shift => _childH - size.height;

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(BoxConstraints.tightFor(width: constraints.maxWidth), parentUsesSize: true);
    _childH = c.size.height;
    final rest = math.min(_band, _childH);
    final h = rest + (_childH - rest) * _progress.clamp(0.0, 1.0);
    size = constraints.constrain(Size(constraints.maxWidth, h));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, -_shift, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null || !size.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, -_shift),
      position: position,
      hitTest: (r, p) => c.hitTest(r, position: p),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    if (_open) {
      _clip.layer = null;
      context.paintChild(c, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (ctx, o) => ctx.paintChild(c, o + Offset(0, -_shift)),
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
