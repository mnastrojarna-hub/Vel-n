import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import 'mg_tone_motion.dart';

export 'mg_tone_motion.dart';

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

/// Tone disc with its one motion (V22 §5.2, design M4): ✓ draws itself in
/// (300) → pop → one neon ripple (700) · ⏳ ring sweep (the screen's live
/// loop) — when the SAME disc turns pending → ok, the ring completes and
/// closes into the ✓ (450) · ⚠ pop · ✕ one shake · info / SOS static.
/// Reduced motion → end state. [icon] overrides the tone icon (wifi-off,
/// lock…).
class MgToneDisc extends StatefulWidget {
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
  State<MgToneDisc> createState() => _MgToneDiscState();
}

class _MgToneDiscState extends State<MgToneDisc> {
  int _morph = 0;

  @override
  void didUpdateWidget(covariant MgToneDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tone == MgTone.pending && widget.tone == MgTone.ok) {
      _morph++;
    } else if (oldWidget.tone != widget.tone) {
      _morph = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final s = mgToneStyle(w.tone, dark: w.dark);
    final icon = w.icon ?? s.iconName;
    final face = ExcludeSemantics(child: MgToneFace(style: s, size: w.size, icon: icon));
    if (!w.animate) return face;
    if (_morph > 0 && w.tone == MgTone.ok) {
      return ExcludeSemantics(
        child: MgToneMorph(
          key: ValueKey(_morph),
          from: mgToneStyle(MgTone.pending, dark: w.dark),
          to: s,
          size: w.size,
          icon: icon,
        ),
      );
    }
    return switch (w.tone) {
      MgTone.ok => ExcludeSemantics(child: MgToneSuccess(style: s, size: w.size, icon: icon)),
      MgTone.pending => MgTonePendingRing(color: s.icon, size: w.size, child: face),
      MgTone.warn => MgPop(playOnMount: true, child: face),
      MgTone.err => MgShake(child: face),
      MgTone.info || MgTone.sos => face,
    };
  }
}
