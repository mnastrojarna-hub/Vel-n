import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';

/// Hide-on-scroll fold of the bottom nav (owner 2026-11-08): the tab row
/// is covered from the top and fades out, and only a [band] px strip of the
/// nav's night surface (behind the home indicator / gesture bar = the
/// nav's own bottom safe-area part) stays. The body above grows by the tab row's height and NOTHING in
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

  /// The fold / unfold finished (the shell re-places the AI button).
  final VoidCallback? onEnd;
  const MgNavBand({super.key, required this.folded, required this.band, required this.child, this.onEnd});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: folded ? 0 : 1),
        duration: MgMotion.of(context, MgMotion.sticky),
        curve: MgMotion.emphasized,
        onEnd: onEnd,
        child: child,
        builder: (_, v, child) => IgnorePointer(
          ignoring: folded,
          child: ExcludeSemantics(
            excluding: folded,
            child: _NavBandBox(progress: v, band: band, color: MgColors.night.withValues(alpha: 0.96), child: child),
          ),
        ),
      );
}

class _NavBandBox extends SingleChildRenderObjectWidget {
  final double progress;
  final double band;
  final Color color;
  const _NavBandBox({required this.progress, required this.band, required this.color, super.child});

  @override
  RenderMgNavBand createRenderObject(BuildContext context) =>
      RenderMgNavBand(progress: progress, band: band, color: color);

  @override
  void updateRenderObject(BuildContext context, RenderMgNavBand renderObject) {
    renderObject
      ..progress = progress
      ..band = band
      ..color = color;
  }
}

/// Lays the child out at its natural height H and takes
/// `band + (H − band) × progress`; the child is bottom-aligned (its top
/// part leaves through the top edge, clipped) and fades with [progress]
/// over a [color] fill of the box (the band) — fully open it paints
/// unclipped, so the nav's shadow above its top edge stays.
class RenderMgNavBand extends RenderProxyBox {
  RenderMgNavBand({required double progress, required double band, required Color color})
      : _progress = progress,
        _band = band,
        _color = color;

  Color _color;
  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

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
  final LayerHandle<OpacityLayer> _fade = LayerHandle<OpacityLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null && !_open;

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
      _fade.layer = null;
      context.paintChild(c, offset);
      return;
    }
    final alpha = (255 * _progress.clamp(0.0, 1.0)).round();
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (ctx, o) {
        ctx.canvas.drawRect(o & size, Paint()..color = _color);
        if (alpha == 0) {
          _fade.layer = null;
          return;
        }
        _fade.layer = ctx.pushOpacity(o, alpha, (ctx2, o2) => ctx2.paintChild(c, o2 + Offset(0, -_shift)),
            oldLayer: _fade.layer);
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _fade.layer = null;
    super.dispose();
  }
}
