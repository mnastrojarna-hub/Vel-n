import 'package:flutter/widgets.dart';

import '../motion/mg_motion.dart';

/// In-place content switch (design M1: segment, month, sibling, edit
/// intent): the new content slides in 24 px from the side of [direction]
/// (+1 = from the right / next, −1 = from the left / previous, 0 = fade only)
/// and fades in over `MgMotion.tab` emphasized; the old one only fades out.
/// Keyed by [switchKey] — a new key = new content (state of the old one is
/// dropped). Reduced motion: the new content at once.
class MgSwipeSwitcher extends StatelessWidget {
  final Object switchKey;
  final int direction;
  final Widget child;
  final AlignmentGeometry alignment;

  const MgSwipeSwitcher({
    super.key,
    required this.switchKey,
    this.direction = 0,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final keyed = KeyedSubtree(key: ValueKey<Object>(switchKey), child: child);
    if (MgMotion.reduced(context)) return keyed;
    final incomingKey = ValueKey<Object>(switchKey);
    return AnimatedSwitcher(
      duration: MgMotion.tab,
      switchInCurve: MgMotion.emphasized,
      switchOutCurve: Curves.linear,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (c, a) => c.key == incomingKey
          ? _MgSlideFade(animation: a, dx: 24.0 * direction.sign, child: c)
          : FadeTransition(opacity: a, child: c),
      child: keyed,
    );
  }
}

/// Same look as [MgSwipeSwitcher] on the SAME element: when [trigger]
/// changes, the child fades / slides in again but keeps its state (form
/// fields, scroll positions — reservation-edit intents, register steps).
/// Reduced motion: nothing moves.
class MgStepFade extends StatefulWidget {
  final Object trigger;
  final Widget child;
  final int direction;
  const MgStepFade({super.key, required this.trigger, required this.child, this.direction = 0});

  @override
  State<MgStepFade> createState() => _MgStepFadeState();
}

class _MgStepFadeState extends State<MgStepFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: MgMotion.tab, value: 1);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: MgMotion.emphasized);

  @override
  void didUpdateWidget(covariant MgStepFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !MgMotion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _MgSlideFade(animation: _a, dx: 24.0 * widget.direction.sign, child: widget.child);
}

class _MgSlideFade extends AnimatedWidget {
  final double dx;
  final Widget child;
  const _MgSlideFade({required Animation<double> animation, required this.dx, required this.child})
      : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(dx * (1 - t), 0), child: child),
    );
  }
}
