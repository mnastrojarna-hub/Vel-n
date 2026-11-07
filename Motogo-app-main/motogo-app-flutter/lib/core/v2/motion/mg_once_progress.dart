import 'package:flutter/widgets.dart';

import 'mg_anim.dart';
import 'mg_motion.dart';

/// One-shot progress t 0 → 1 over [duration] after [delay] ([curve]); with
/// [sessionKey] only the first time that key is shown in this app session
/// (later: t = 1 at once). Reduced motion: t = 1. For drawn ✓ paths, bars
/// filling once, etc. — never a loop.
class MgOnceProgress extends StatefulWidget {
  final Duration duration;
  final Curve curve;
  final String? sessionKey;
  final Duration delay;
  final Widget Function(BuildContext, double t) builder;

  const MgOnceProgress({
    super.key,
    required this.duration,
    this.curve = MgMotion.out,
    this.sessionKey,
    this.delay = Duration.zero,
    required this.builder,
  });

  @override
  State<MgOnceProgress> createState() => _MgOnceProgressState();
}

class _MgOnceProgressState extends State<MgOnceProgress> {
  late final bool _play = widget.sessionKey == null || MgMotion.firstTime('once:${widget.sessionKey}');

  @override
  Widget build(BuildContext context) {
    if (!_play || MgMotion.reduced(context)) return widget.builder(context, 1);
    return MgProgressOnce(
      duration: widget.duration,
      delay: widget.delay,
      curve: widget.curve,
      builder: widget.builder,
    );
  }
}
