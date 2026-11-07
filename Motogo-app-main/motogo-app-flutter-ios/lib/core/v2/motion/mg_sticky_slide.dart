import 'package:flutter/widgets.dart';

import 'mg_motion.dart';

/// Chrome sliding in / out (design M3: nav, docks, strips, pinned bars):
/// slides 110 % of its height toward the edge [from] (down = the bottom
/// edge, up = the top edge) and fades over `MgMotion.sticky` (300,
/// emphasized). [collapse] also animates its height to 0, so the layout
/// gives the space back (the bottom nav on /sos). Hidden = no taps, no
/// semantics. Reduced motion: instant.
class MgStickySlide extends StatelessWidget {
  final bool visible;
  final Widget child;
  final AxisDirection from;
  final bool collapse;

  const MgStickySlide({
    super.key,
    required this.visible,
    required this.child,
    this.from = AxisDirection.down,
    this.collapse = false,
  });

  Offset get _hidden => switch (from) {
        AxisDirection.down => const Offset(0, 1.1),
        AxisDirection.up => const Offset(0, -1.1),
        AxisDirection.left => const Offset(-1.1, 0),
        AxisDirection.right => const Offset(1.1, 0),
      };

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.sticky);
    Widget out = AnimatedSlide(
      offset: visible ? Offset.zero : _hidden,
      duration: d,
      curve: MgMotion.emphasized,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: d,
        curve: MgMotion.emphasized,
        child: child,
      ),
    );
    if (collapse) {
      // Clip only on the collapsing side: the nav's shadow above its top edge
      // (or a top bar's below its bottom) stays visible.
      out = ClipRect(
        clipper: _OpenEdgeClip(from),
        child: AnimatedAlign(
          alignment: from == AxisDirection.up ? Alignment.bottomCenter : Alignment.topCenter,
          heightFactor: visible ? 1 : 0,
          duration: d,
          curve: MgMotion.emphasized,
          child: out,
        ),
      );
    }
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(excluding: !visible, child: out),
    );
  }
}

/// Clips the side the child slides out to; the opposite edge and the sides
/// stay open (shadows).
class _OpenEdgeClip extends CustomClipper<Rect> {
  final AxisDirection from;
  const _OpenEdgeClip(this.from);

  static const double _open = 1000;

  @override
  Rect getClip(Size size) => switch (from) {
        AxisDirection.down => Rect.fromLTRB(-_open, -_open, size.width + _open, size.height),
        AxisDirection.up => Rect.fromLTRB(-_open, 0, size.width + _open, size.height + _open),
        AxisDirection.left => Rect.fromLTRB(0, -_open, size.width + _open, size.height + _open),
        AxisDirection.right => Rect.fromLTRB(-_open, -_open, size.width, size.height + _open),
      };

  @override
  bool shouldReclip(_OpenEdgeClip oldClipper) => oldClipper.from != from;
}
