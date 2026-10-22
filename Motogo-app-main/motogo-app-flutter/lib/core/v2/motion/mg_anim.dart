import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mg_motion.dart';

/// Press feedback for every v2 tappable: scale .97 (.92 for icon buttons)
/// in 150 ms + `selectionClick` haptic. Reduced motion → no scaling.
class MgPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior behavior;

  const MgPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<MgPress> createState() => _MgPressState();
}

class _MgPressState extends State<MgPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduced = MgMotion.reduced(context);
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: (_down && !reduced) ? widget.scale : 1,
        duration: MgMotion.press,
        curve: MgMotion.ease,
        child: widget.child,
      ),
    );
  }
}

/// Base for one-shot animations that replay when [trigger] changes and
/// snap to the end state under reduced motion.
abstract class _OneShot extends StatefulWidget {
  final Widget child;
  final Object? trigger;
  final bool playOnMount;
  final Duration delay;
  const _OneShot({
    super.key,
    required this.child,
    this.trigger,
    this.playOnMount = true,
    this.delay = Duration.zero,
  });

  Duration get duration;
  Widget transform(double t, Widget child);

  @override
  State<_OneShot> createState() => _OneShotState();
}

class _OneShotState extends State<_OneShot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: widget.duration, value: widget.playOnMount ? 0 : 1);
  bool _reduced = false;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MgMotion.reduced(context);
    if (_reduced) _c.value = 1;
  }

  @override
  void initState() {
    super.initState();
    if (widget.playOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  void _play() {
    if (!mounted) return;
    if (_reduced) {
      _c.value = 1;
      return;
    }
    _delay?.cancel();
    if (widget.delay == Duration.zero) {
      _c.forward(from: 0);
      return;
    }
    _c.value = 0;
    // Cancellable (a replay or dispose drops the pending start).
    _delay = Timer(widget.delay, () {
      if (mounted && !_reduced) _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant _OneShot old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _play();
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => widget.transform(_c.value, child!),
    );
  }
}

/// Selection / badge / ✓ pop: .85 → 1.08 (40 %) → 1 in 300 ms.
class MgPop extends _OneShot {
  const MgPop({super.key, required super.child, super.trigger, super.playOnMount = false});

  @override
  Duration get duration => MgMotion.pop;


  @override
  Widget transform(double t, Widget child) {
    final s = t < 0.4 ? 0.85 + (1.08 - 0.85) * (t / 0.4) : 1.08 - 0.08 * ((t - 0.4) / 0.6);
    return Transform.scale(scale: s, child: child);
  }
}

/// Content entering: opacity 0 → 1 + Y 12 → 0 in 450 ms (once on mount).
class MgEnter extends _OneShot {
  const MgEnter({super.key, required super.child, super.delay, super.trigger});

  @override
  Duration get duration => MgMotion.enter;


  @override
  Widget transform(double t, Widget child) {
    final e = MgMotion.ease.transform(t);
    return Opacity(
      opacity: e,
      child: Transform.translate(offset: Offset(0, 12 * (1 - e)), child: child),
    );
  }
}

/// List reveal: Y 16 → 0 + fade, 550 ms, stagger 70 ms (capped at index 5).
/// With [sessionKey] it plays only on the first build in this app session.
/// "First time" is decided once per mounted element, and the widget keeps
/// the same shape afterwards (rebuilds never remount [child]).
class MgReveal extends StatefulWidget {
  final Widget child;
  final int index;
  final String? sessionKey;
  const MgReveal({super.key, required this.child, this.index = 0, this.sessionKey});

  @override
  State<MgReveal> createState() => _MgRevealState();
}

class _MgRevealState extends State<MgReveal> {
  late final bool _play =
      widget.sessionKey == null || MgMotion.firstTime('reveal:${widget.sessionKey}:${widget.index}');

  @override
  Widget build(BuildContext context) => _Reveal(
        delay: MgMotion.revealStagger * math.min(widget.index, 5),
        playOnMount: _play,
        child: widget.child,
      );
}

class _Reveal extends _OneShot {
  const _Reveal({required super.child, super.delay, super.playOnMount});

  @override
  Duration get duration => MgMotion.reveal;


  @override
  Widget transform(double t, Widget child) {
    final e = MgMotion.ease.transform(t);
    return Opacity(
      opacity: e,
      child: Transform.translate(offset: Offset(0, 16 * (1 - e)), child: child),
    );
  }
}

/// Totals: 1 → 1.12 → 1 in 450 ms whenever [trigger] changes.
class MgBump extends _OneShot {
  const MgBump({super.key, required super.child, required super.trigger})
      : super(playOnMount: false);

  @override
  Duration get duration => MgMotion.bump;


  @override
  Widget transform(double t, Widget child) =>
      Transform.scale(scale: 1 + 0.12 * math.sin(math.pi * t), child: child);
}

/// Error tone: one 4 px shake in 300 ms (on mount and when [trigger] changes).
class MgShake extends _OneShot {
  const MgShake({super.key, required super.child, super.trigger});

  @override
  Duration get duration => MgMotion.shake;


  @override
  Widget transform(double t, Widget child) => Transform.translate(
        offset: Offset(4 * math.sin(t * math.pi * 4) * (1 - t), 0),
        child: child,
      );
}

/// One-shot 0 → 1 progress (path draw, connectors, marks draw-in). Builder
/// gets 1 immediately under reduced motion.
class MgProgressOnce extends StatelessWidget {
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final Widget Function(BuildContext context, double t) builder;
  const MgProgressOnce({
    super.key,
    required this.duration,
    required this.builder,
    this.delay = Duration.zero,
    this.curve = Curves.easeInOut,
  });

  @override
  Widget build(BuildContext context) {
    if (MgMotion.reduced(context)) return builder(context, 1);
    final total = duration + delay;
    final lead = total.inMicroseconds == 0 ? 0.0 : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (c, v, _) {
        final t = lead >= 1 ? 1.0 : ((v - lead) / (1 - lead)).clamp(0.0, 1.0);
        return builder(c, curve.transform(t));
      },
    );
  }
}
