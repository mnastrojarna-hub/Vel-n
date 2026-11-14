import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';

/// Brand-neon gradient of the active menu pill (the original look's
/// `MotoGoColors.green → greenDark`, owner v5.0.1 "víc svítivě zelené").
const LinearGradient kV2NavPillGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF74FB71), Color(0xFF3DBA3A)],
);

/// Halo under the active pill at breath [b] (0 = rest = the original look's
/// `green @ .5, blur 14, dy 4`; 1 = the brightest breath).
List<BoxShadow> v2NavPillHalo(double b) => [
      BoxShadow(color: MgColors.neonA(0.5 + 0.22 * b), blurRadius: 14 + 8 * b, offset: const Offset(0, 4)),
      BoxShadow(color: MgColors.neonA(0.16 * b), blurRadius: 26, spreadRadius: 1),
    ];

/// The active tab's filled neon pill (icon + label sit on it). Liquid
/// stretch while it travels to a new tab ([trigger] = the tab index); the
/// halo breathes slowly a few times after it lands ([breaths] × 2.6 s,
/// then it rests on the static original halo — no endless ticker on the
/// bar). Reduced motion: no stretch, no breathing. Only this box repaints.
class V2NavPill extends StatefulWidget {
  final int trigger;
  final bool reduced;
  final int breaths;
  const V2NavPill({super.key, required this.trigger, required this.reduced, this.breaths = 3});

  /// One breath (in + out).
  static const Duration breath = Duration(milliseconds: 2600);

  @override
  State<V2NavPill> createState() => _V2NavPillState();
}

class _V2NavPillState extends State<V2NavPill> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: MgMotion.thumb, value: 1);
  late final AnimationController _halo =
      AnimationController(vsync: this, duration: V2NavPill.breath * math.max(1, widget.breaths));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _breathe());
  }

  @override
  void didUpdateWidget(covariant V2NavPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      if (!widget.reduced) _move.forward(from: 0);
      _breathe();
    }
    if (widget.reduced) {
      _move.value = 1;
      _halo.value = 0;
      _halo.stop();
    }
  }

  void _breathe() {
    if (!mounted || widget.reduced || widget.breaths <= 0) return;
    _halo.forward(from: 0);
  }

  @override
  void dispose() {
    _move.dispose();
    _halo.dispose();
    super.dispose();
  }

  /// 0 → 1 → 0 per breath, eased (sin²).
  double get _b {
    if (!_halo.isAnimating) return 0;
    final s = math.sin(math.pi * _halo.value * math.max(1, widget.breaths));
    return s * s;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_move, _halo]),
        builder: (_, __) {
          final t = _move.isAnimating ? math.sin(math.pi * _move.value) : 0.0;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1 + 0.18 * t, 1 - 0.08 * t, 1),
            child: DecoratedBox(
              key: const ValueKey('v2-nav-pill'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: kV2NavPillGradient,
                boxShadow: v2NavPillHalo(_b),
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      );
}

/// The original menu's elastic pop (`NavBounceIcon`: 0.6 → 1.0,
/// `Curves.elasticOut`, 520 ms) when a tab becomes active; none under
/// reduced motion.
class V2NavBounce extends StatefulWidget {
  final bool active;
  final Widget child;
  const V2NavBounce({super.key, required this.active, required this.child});

  static const Duration duration = Duration(milliseconds: 520);

  @override
  State<V2NavBounce> createState() => _V2NavBounceState();
}

class _V2NavBounceState extends State<V2NavBounce> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: V2NavBounce.duration, value: 1);

  @override
  void didUpdateWidget(covariant V2NavBounce oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !MgMotion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => _c.isAnimating
            ? Transform.scale(scale: 0.6 + 0.4 * Curves.elasticOut.transform(_c.value), child: child)
            : child!,
      );
}

/// Re-tap of the active tab: the icon nudges 3 px up and back (`pop`).
class V2NavNudge extends StatefulWidget {
  final int trigger;
  final Widget child;
  const V2NavNudge({super.key, required this.trigger, required this.child});

  @override
  State<V2NavNudge> createState() => _V2NavNudgeState();
}

class _V2NavNudgeState extends State<V2NavNudge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: MgMotion.pop, value: 1);

  @override
  void didUpdateWidget(covariant V2NavNudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != 0 && widget.trigger != oldWidget.trigger && !MgMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _c.isAnimating ? -3 * math.sin(math.pi * _c.value) : 0),
          child: child,
        ),
      );
}
