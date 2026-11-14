import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'mg_motion.dart';

/// Elapsed-time clock for loop painters (CTA glow + tier fx share ONE
/// ticker, so a CTA is one loop). Paused by `TickerMode` (off-screen, covered
/// route, closed sheet); never ticks under reduced motion or when [active]
/// is false — the builder then gets `null` (draw the static end state).
/// [pauseOffscreen] (default): the clock also stops while its box is
/// scrolled out of the viewport of its scrollables (design M6) and resumes
/// when it comes back (the builder keeps getting the listenable).
class MgLoopClock extends StatefulWidget {
  final bool active;
  final bool pauseOffscreen;
  final Widget Function(BuildContext context, ValueListenable<double>? seconds) builder;
  const MgLoopClock({super.key, required this.active, required this.builder, this.pauseOffscreen = true});

  @override
  State<MgLoopClock> createState() => _MgLoopClockState();
}

class _MgLoopClockState extends State<MgLoopClock> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _t = ValueNotifier(0);
  Ticker? _ticker;
  bool _run = false;
  bool _visible = true;
  bool _checkQueued = false;
  final List<ScrollableState> _scrollables = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchScrollables();
    _sync();
  }

  @override
  void didUpdateWidget(covariant MgLoopClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pauseOffscreen != widget.pauseOffscreen) _watchScrollables();
    _sync();
  }

  /// Listens to up to 3 enclosing scrollables (a carousel inside a list).
  void _watchScrollables() {
    for (final s in _scrollables) {
      s.position.removeListener(_queueCheck);
    }
    _scrollables.clear();
    if (!widget.pauseOffscreen) {
      _visible = true;
      return;
    }
    var s = Scrollable.maybeOf(context);
    while (s != null && _scrollables.length < 3) {
      _scrollables.add(s);
      s.position.addListener(_queueCheck);
      s = Scrollable.maybeOf(s.context);
    }
    _queueCheck();
  }

  void _queueCheck() {
    if (_checkQueued || _scrollables.isEmpty) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (!mounted) return;
      final v = _isVisible();
      if (v != _visible) {
        _visible = v;
        _sync();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool _isVisible() {
    final me = context.findRenderObject();
    if (me is! RenderBox || !me.attached || !me.hasSize) return true;
    final rect = me.localToGlobal(Offset.zero) & me.size;
    for (final s in _scrollables) {
      final vp = s.context.findRenderObject();
      if (vp is! RenderBox || !vp.attached || !vp.hasSize) continue;
      final r = vp.localToGlobal(Offset.zero) & vp.size;
      if (!r.overlaps(rect)) return false;
    }
    return true;
  }

  void _sync() {
    final run = widget.active && _visible && !MgMotion.reduced(context);
    if (run == _run) return;
    _run = run;
    if (run) {
      _ticker ??= createTicker((e) => _t.value = e.inMicroseconds / 1e6);
      _ticker!.start();
    } else {
      _ticker?.stop();
      if (_visible) _t.value = 0;
    }
  }

  @override
  void dispose() {
    for (final s in _scrollables) {
      s.position.removeListener(_queueCheck);
    }
    _ticker?.dispose();
    _t.dispose();
    super.dispose();
  }

  /// While paused off-screen the builder keeps the listenable (frozen),
  /// so the subtree does not swap to the static look and back.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
      child: widget.builder(context, _run || (widget.active && !_visible && !MgMotion.reduced(context)) ? _t : null));
}

/// Live indicator ping: a ring grows 0 → [spread] while fading .7 → 0
/// (1.8 s loop). Reduced motion / [active] false → static dot only.
class MgPing extends StatelessWidget {
  final double size;
  final Color color;
  final double spread;
  final bool active;
  final Widget? child;
  const MgPing({
    super.key,
    this.size = 10,
    required this.color,
    this.spread = 7,
    this.active = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dot = child ??
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: SizedBox(width: size, height: size),
        );
    return MgLoopClock(
      active: active,
      builder: (context, t) {
        if (t == null) return dot;
        return ValueListenableBuilder<double>(
          valueListenable: t,
          child: dot,
          builder: (_, s, child) {
            final p = (s % 1.8) / 1.8;
            return CustomPaint(
              painter: _PingPainter(p, color, spread),
              child: child,
            );
          },
        );
      },
    );
  }
}

class _PingPainter extends CustomPainter {
  final double p;
  final Color color;
  final double spread;
  _PingPainter(this.p, this.color, this.spread);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 + spread * p;
    canvas.drawCircle(
      size.center(Offset.zero),
      r,
      Paint()..color = color.withValues(alpha: 0.7 * (1 - p)),
    );
  }

  @override
  bool shouldRepaint(_PingPainter o) => o.p != p || o.color != color;
}

/// Loading shimmer: one 1.2 s sweep, repeated only while [active]
/// (loading). Reduced motion → static at 55 % opacity.
class MgShimmer extends StatelessWidget {
  final Widget child;
  final bool active;
  final Color highlight;
  const MgShimmer({
    super.key,
    required this.child,
    this.active = true,
    this.highlight = const Color(0x66FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    if (MgMotion.reduced(context)) {
      return Opacity(opacity: active ? 0.55 : 1, child: child);
    }
    return MgLoopClock(
      active: active,
      builder: (context, t) {
        if (t == null) return child;
        return ValueListenableBuilder<double>(
          valueListenable: t,
          child: child,
          builder: (_, s, child) {
            final p = (s % 1.2) / 1.2;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment(-1 + 3 * p - 1, 0),
                end: Alignment(-1 + 3 * p, 0),
                colors: [const Color(0x00FFFFFF), highlight, const Color(0x00FFFFFF)],
              ).createShader(r),
              child: child,
            );
          },
        );
      },
    );
  }
}
