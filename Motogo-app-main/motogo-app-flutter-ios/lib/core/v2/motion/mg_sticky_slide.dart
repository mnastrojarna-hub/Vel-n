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
      out = ClipRect(
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
