import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_anim_loops.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';

/// Tones of result / error states (DESIGN_V22 §5.2). Meaning colours only —
/// a tone NEVER takes the rank colour.
enum MgTone { ok, pending, warn, err, info, sos }

/// Disc / icon / accent colours of a tone on a light or dark surface.
class MgToneStyle {
  final Color disc;
  final Color icon;
  final Color accent;
  final Color? ring;
  final String iconName;
  const MgToneStyle(this.disc, this.icon, this.accent, this.iconName, [this.ring]);
}

MgToneStyle mgToneStyle(MgTone tone, {bool dark = false}) => switch (tone) {
      MgTone.ok => dark
          ? const MgToneStyle(MgColors.panel, MgColors.neon, MgColors.neon, MgIcons.check, MgColors.neon)
          : const MgToneStyle(MgColors.tintOk, MgColors.link, MgColors.link, MgIcons.check),
      MgTone.pending => dark
          ? const MgToneStyle(MgColors.warnDarkBg, MgColors.warnDark, MgColors.warnDark, MgIcons.clock)
          : const MgToneStyle(MgColors.warnBg, MgColors.warn, MgColors.warn, MgIcons.clock),
      MgTone.warn => dark
          ? const MgToneStyle(MgColors.warnDarkBg, MgColors.warnDark, MgColors.warnDark, MgIcons.warn)
          : const MgToneStyle(MgColors.warnBg, MgColors.warn, MgColors.warn, MgIcons.warn),
      MgTone.err => dark
          ? const MgToneStyle(MgColors.errDarkBg, MgColors.errDark, MgColors.errDark, MgIcons.close)
          : const MgToneStyle(MgColors.errBg, MgColors.err, MgColors.err, MgIcons.close),
      MgTone.info => dark
          ? MgToneStyle(MgColors.white(0.10), MgColors.onDark, MgColors.onDark, MgIcons.info)
          : const MgToneStyle(MgColors.well, MgColors.ink, MgColors.ink, MgIcons.info),
      MgTone.sos => const MgToneStyle(MgColors.sos, MgColors.onDark, MgColors.onDark, MgIcons.alert),
    };

/// Tone disc with its one motion: ✓ pop + one ripple · ⏳ ring sweep (the
/// screen's live loop) · ⚠ pop · ✕ one shake · info / SOS static. Reduced
/// motion → end state. [icon] overrides the tone icon (wifi-off, lock…).
class MgToneDisc extends StatelessWidget {
  final MgTone tone;
  final double size;
  final bool dark;
  final String? icon;
  final bool animate;
  const MgToneDisc({
    super.key,
    required this.tone,
    this.size = 72,
    this.dark = false,
    this.icon,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = mgToneStyle(tone, dark: dark);
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s.disc,
        shape: BoxShape.circle,
        border: s.ring == null ? null : Border.all(color: s.ring!, width: 3),
      ),
      child: Center(child: MgIcon(icon ?? s.iconName, size: size * 0.46, color: s.icon, stroke: 2.2)),
    );
    final semantics = ExcludeSemantics(child: disc);
    if (!animate) return semantics;
    return switch (tone) {
      MgTone.ok => _SuccessDisc(color: s.accent, size: size, child: semantics),
      MgTone.pending => _PendingRing(color: s.icon, size: size, child: semantics),
      MgTone.warn => MgPop(playOnMount: true, child: semantics),
      MgTone.err => MgShake(child: semantics),
      MgTone.info || MgTone.sos => semantics,
    };
  }
}

class _SuccessDisc extends StatelessWidget {
  final Color color;
  final double size;
  final Widget child;
  const _SuccessDisc({required this.color, required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MgMotion.reduced(context)) return child;
    return MgProgressOnce(
      duration: MgMotion.connector,
      curve: Curves.easeOut,
      builder: (_, t) {
        final pop = t < 0.3 ? 0.85 + 0.23 * (t / 0.3) : (t < 0.43 ? 1.08 - 0.08 * ((t - 0.3) / 0.13) : 1.0);
        return SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            if (t < 1)
              Container(
                width: size * (1 + 0.5 * t),
                height: size * (1 + 0.5 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.6 * (1 - t)), width: 2),
                ),
              ),
            Transform.scale(scale: pop, child: child),
          ]),
        );
      },
    );
  }
}

class _PendingRing extends StatelessWidget {
  final Color color;
  final double size;
  final Widget child;
  const _PendingRing({required this.color, required this.size, required this.child});

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
            foregroundPainter: _SweepPainter(color, (s % 1.2) / 1.2),
            child: c,
          ),
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  final Color color;
  final double p;
  _SweepPainter(this.color, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    canvas.drawArc(
      rect,
      -math.pi / 2 + 2 * math.pi * p,
      math.pi * 0.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter o) => o.p != p || o.color != color;
}
