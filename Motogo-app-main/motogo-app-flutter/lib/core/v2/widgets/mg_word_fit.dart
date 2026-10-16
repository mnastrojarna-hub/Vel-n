import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shared v2 typography rule (verify:render): a label NEVER breaks inside a
/// word. When the longest word of [child] (usually a `Text`) is wider than
/// the space, the whole label scales down (to [minScale] at most) before it
/// wraps — and a label over its `maxLines` shrinks a little more. Wrapping
/// at spaces still works; only the "Bearbeit|en" kind of split is gone.
///
/// Unlike `FittedBox` the child keeps a bounded width (it still wraps), and
/// unlike `LayoutBuilder` it answers intrinsic sizes, so it is safe inside
/// `IntrinsicHeight` rows. The child stays a normal `Text` (semantics,
/// `find.text`, hit tests and the render inspector see it as before).
class MgWordFit extends SingleChildRenderObjectWidget {
  /// Smallest scale (1 = never scale).
  final double minScale;

  /// Where the (scaled) child sits when it is smaller than this box.
  final AlignmentGeometry alignment;

  const MgWordFit({
    super.key,
    this.minScale = 0.8,
    this.alignment = AlignmentDirectional.centerStart,
    required Widget super.child,
  });

  @override
  RenderMgWordFit createRenderObject(BuildContext context) => RenderMgWordFit(
        minScale: minScale,
        alignment: alignment.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr),
      );

  @override
  void updateRenderObject(BuildContext context, RenderMgWordFit renderObject) {
    renderObject
      ..minScale = minScale
      ..alignment = alignment.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr);
  }
}

/// Render object of [MgWordFit].
class RenderMgWordFit extends RenderProxyBox {
  RenderMgWordFit({required double minScale, required Alignment alignment})
      : _minScale = minScale,
        _alignment = alignment;

  double _minScale;
  double get minScale => _minScale;
  set minScale(double v) {
    if (v == _minScale) return;
    _minScale = v;
    markNeedsLayout();
  }

  Alignment _alignment;
  Alignment get alignment => _alignment;
  set alignment(Alignment v) {
    if (v == _alignment) return;
    _alignment = v;
    markNeedsPaint();
  }

  double _scale = 1;
  Offset _offset = Offset.zero;

  /// Scale for a box of width [w]: the longest word (single-line text: the
  /// whole line) must fit.
  double _initialScale(RenderBox child, double w) {
    if (!w.isFinite || w <= 0) return 1;
    final p = child;
    final need = p is RenderParagraph && p.maxLines == 1
        ? p.getMaxIntrinsicWidth(double.infinity)
        : child.getMinIntrinsicWidth(double.infinity);
    if (need <= w || need <= 0) return 1;
    return math.max(_minScale, w / need);
  }

  BoxConstraints _childConstraints(BoxConstraints c, double s) => BoxConstraints(
        minWidth: c.minWidth / s,
        maxWidth: c.maxWidth.isFinite ? c.maxWidth / s : double.infinity,
      );

  @override
  void performLayout() {
    final child = this.child;
    final c = constraints;
    if (child == null) {
      size = c.smallest;
      return;
    }
    var s = _initialScale(child, c.maxWidth);
    while (true) {
      child.layout(_childConstraints(c, s), parentUsesSize: true);
      final p = child;
      // Over maxLines (ellipsis) → a little smaller, never below minScale.
      if (p is RenderParagraph && p.didExceedMaxLines && s > _minScale + 0.001 && c.maxWidth.isFinite) {
        s = math.max(_minScale, s - 0.05);
        continue;
      }
      break;
    }
    _scale = s;
    final scaled = Size(child.size.width * s, child.size.height * s);
    size = c.constrain(scaled);
    _offset = _alignment.alongOffset(Offset(size.width - scaled.width, size.height - scaled.height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final s = _initialScale(child, constraints.maxWidth);
    final d = child.getDryLayout(_childConstraints(constraints, s));
    return constraints.constrain(Size(d.width * s, d.height * s));
  }

  @override
  double computeMinIntrinsicWidth(double height) => (child?.getMinIntrinsicWidth(height) ?? 0) * _minScale;

  double _heightFor(double width, double Function(RenderBox, double) of) {
    final child = this.child;
    if (child == null) return 0;
    final s = _initialScale(child, width);
    return of(child, width.isFinite ? width / s : width) * s;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width, (c, w) => c.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width, (c, w) => c.getMaxIntrinsicHeight(w));

  Matrix4 get _transform => Matrix4.translationValues(_offset.dx, _offset.dy, 0)..scaleByDouble(_scale, _scale, 1, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      layer = null;
      context.paintChild(child, offset + _offset);
      return;
    }
    layer = context.pushTransform(needsCompositing, offset, _transform, (ctx, o) => ctx.paintChild(child, o),
        oldLayer: layer is TransformLayer ? layer as TransformLayer? : null);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (r, p) => child.hitTest(r, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_transform);
}
