import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim_loops.dart';
import '../motion/mg_motion.dart';
import '../motion/mg_once_progress.dart';
import 'mg_tone.dart' show MgToneStyle;

/// The tone disc itself; [progress] < 1 draws only that part of the icon.
class MgToneFace extends StatelessWidget {
  final MgToneStyle style;
  final double size;
  final String icon;
  final double progress;
  final Color? disc;
  final Color? iconColor;
  final Color? ring;
  const MgToneFace({
    super.key,
    required this.style,
    required this.size,
    required this.icon,
    this.progress = 1,
    this.disc,
    this.iconColor,
    this.ring,
  });

  @override
  Widget build(BuildContext context) {
    final r = ring ?? style.ring;
    final i = size * 0.46;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: disc ?? style.disc,
        shape: BoxShape.circle,
        border: r == null ? null : Border.all(color: r, width: 3),
      ),
      child: Center(
        child: SizedBox(
          width: i,
          height: i,
          child: CustomPaint(painter: MgIconPainter(icon, iconColor ?? style.icon, 2.2, progress)),
        ),
      ),
    );
  }
}

/// ✓ success: the icon draws in over `MgMotion.checkDraw` (300) → the disc
/// pops (300) → one ripple in the accent colour (700). Reduced: final face.
class MgToneSuccess extends StatelessWidget {
  final MgToneStyle style;
  final double size;
  final String icon;
  const MgToneSuccess({super.key, required this.style, required this.size, required this.icon});

  static final int _drawMs = MgMotion.checkDraw.inMilliseconds;
  static final int _totalMs = _drawMs + MgMotion.ripple.inMilliseconds;

  @override
  Widget build(BuildContext context) {
    return MgOnceProgress(
      duration: Duration(milliseconds: _totalMs),
      curve: Curves.linear,
      builder: (_, t) {
        final ms = t * _totalMs;
        final draw = Curves.easeOut.transform((ms / _drawMs).clamp(0.0, 1.0));
        final popT = ((ms - _drawMs) / MgMotion.pop.inMilliseconds).clamp(0.0, 1.0);
        final pop = popT <= 0 || popT >= 1
            ? 1.0
            : (popT < 0.4 ? 1 + 0.08 * (popT / 0.4) : 1.08 - 0.08 * ((popT - 0.4) / 0.6));
        final rip = ((ms - _drawMs) / MgMotion.ripple.inMilliseconds).clamp(0.0, 1.0);
        return SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            if (rip > 0 && rip < 1)
              Container(
                key: const ValueKey('mg-tone-ripple'),
                width: size * (1 + 0.5 * rip),
                height: size * (1 + 0.5 * rip),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: style.accent.withValues(alpha: 0.6 * (1 - rip)), width: 2),
                ),
              ),
            Transform.scale(scale: pop, child: MgToneFace(style: style, size: size, icon: icon, progress: draw)),
          ]),
        );
      },
    );
  }
}

/// ⏳ pending: a 1.2 s ring sweep (the screen's live loop, paused off-screen).
class MgTonePendingRing extends StatelessWidget {
  final Color color;
  final double size;
  final Widget child;
  const MgTonePendingRing({super.key, required this.color, required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    return MgLoopClock(
      active: true,
      builder: (_, clock) {
        if (clock == null) return child;
        return ValueListenableBuilder<double>(
          valueListenable: clock,
          child: child,
          builder: (_, s, c) => CustomPaint(
            foregroundPainter: MgSweepPainter(color, (s % 1.2) / 1.2),
            child: c,
          ),
        );
      },
    );
  }
}

/// The pending disc turning ok IN PLACE over `MgMotion.morph` (450): the
/// sweep closes into a full ring (first 55 %), then the colours cross-fade
/// and the ✓ draws in. Reduced: the ok face at once.
class MgToneMorph extends StatelessWidget {
  final MgToneStyle from;
  final MgToneStyle to;
  final double size;
  final String icon;
  const MgToneMorph({super.key, required this.from, required this.to, required this.size, required this.icon});

  @override
  Widget build(BuildContext context) {
    return MgOnceProgress(
      duration: MgMotion.morph,
      curve: Curves.linear,
      builder: (_, t) {
        if (t >= 1) return MgToneFace(style: to, size: size, icon: icon);
        final close = MgMotion.emphasized.transform((t / 0.55).clamp(0.0, 1.0));
        final turn = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
        final face = MgToneFace(
          style: to,
          size: size,
          icon: icon,
          progress: Curves.easeOut.transform(turn),
          disc: Color.lerp(from.disc, to.disc, turn),
          iconColor: to.icon,
          ring: to.ring == null ? null : Color.lerp(to.ring!.withValues(alpha: 0), to.ring, turn),
        );
        return CustomPaint(
          foregroundPainter: MgSweepPainter(Color.lerp(from.icon, to.accent, turn)!, 0, sweep: 0.3 + 0.7 * close, fade: 1 - turn),
          child: face,
        );
      },
    );
  }
}

/// Ring arc from 12 o'clock + [p] turns, [sweep] of the full circle.
class MgSweepPainter extends CustomPainter {
  final Color color;
  final double p;
  final double sweep;
  final double fade;
  MgSweepPainter(this.color, this.p, {this.sweep = 0.3, this.fade = 1});

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0) return;
    final rect = (Offset.zero & size).deflate(1.5);
    canvas.drawArc(
      rect,
      -math.pi / 2 + 2 * math.pi * p,
      2 * math.pi * sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: color.a * fade),
    );
  }

  @override
  bool shouldRepaint(MgSweepPainter o) => o.p != p || o.color != color || o.sweep != sweep || o.fade != fade;
}
