import 'package:flutter/widgets.dart';

import 'mg_motion.dart';

/// Height / width change animated in the v2 tempo ([duration], [curve]).
/// Under reduced motion the child is placed directly: a zero-length
/// `AnimatedSize` re-dirties itself inside its own layout when the child
/// changes ("RenderAnimatedSize was mutated in its own performLayout").
/// At rest both paths lay the child out with the same constraints.
class MgAnimatedSize extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  const MgAnimatedSize({
    super.key,
    required this.child,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) => MgMotion.reduced(context)
      ? child
      : AnimatedSize(duration: duration, curve: curve, alignment: alignment, child: child);
}
