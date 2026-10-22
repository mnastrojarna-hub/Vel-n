import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import 'ride_phase_v2.dart';

/// State glyph of a recording surface: red ping only while really riding
/// (static under reduced motion), a static ❚❚ when paused, a neon ring
/// when armed ("čeká na rozjezd"), an amber dot when GPS is lost.
class RecGlyphV2 extends StatelessWidget {
  final RecToneV2 tone;
  final double size;
  final bool dark;
  const RecGlyphV2({super.key, required this.tone, this.size = 18, this.dark = true});

  @override
  Widget build(BuildContext context) {
    final Widget g = switch (tone) {
      RecToneV2.rec => MgPing(size: size * 0.55, color: MgColors.sosDot, active: !MgMotion.reduced(context)),
      RecToneV2.paused => MgIcon(MgIcons.pause, size: size, color: dark ? MgColors.onDark : MgColors.ink, stroke: 2.6),
      RecToneV2.armed => Container(
          width: size * 0.7,
          height: size * 0.7,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: dark ? MgColors.neon : MgColors.neonLo, width: 2.4)),
        ),
      RecToneV2.warn => Container(
          width: size * 0.55,
          height: size * 0.55,
          decoration: const BoxDecoration(color: MgColors.warnDark, shape: BoxShape.circle),
        ),
    };
    return SizedBox(width: size, height: size, child: Center(child: g));
  }
}

/// 44 px pause / resume disc (every recording — own AND rental). [paused] =
/// manually paused → ▶ resume; otherwise ❚❚ pause (also while auto-paused
/// or armed: it then turns GPS off).
class RecPauseDiscV2 extends StatelessWidget {
  final bool paused;
  final VoidCallback onTap;
  final bool dark;
  const RecPauseDiscV2({super.key, required this.paused, required this.onTap, this.dark = true});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final label = tr.tr(paused ? 'v2RpA11yResume' : 'v2RpA11yPause');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: paused ? MgColors.neon : (dark ? MgColors.white(0.10) : MgColors.surface),
              shape: BoxShape.circle,
              border: Border.all(color: paused ? MgColors.neon : (dark ? MgColors.white(0.30) : MgColors.lineInput)),
            ),
            child: Center(
              child: MgIcon(paused ? MgIcons.playFilled : MgIcons.pause,
                  size: 20, color: paused ? MgColors.onNeon : (dark ? MgColors.onDark : MgColors.ink), stroke: 2.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// White "■ Ukončit" (manual ride only). [iconOnly] = just the 44 × 44 ■
/// (the label stays in semantics / tooltip) on narrow bars.
class RecStopButtonV2 extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  final bool iconOnly;
  final bool outlined;
  const RecStopButtonV2({super.key, required this.onTap, this.compact = false, this.iconOnly = false, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final label = tr.tr('rideManualStop');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 36 : 44, minWidth: 44),
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 12),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: outlined ? Border.all(color: MgColors.err, width: 1.5) : null,
              boxShadow: outlined
                  ? null
                  : [BoxShadow(color: MgColors.black(0.4), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -8)],
            ),
            child: iconOnly
                ? const SizedBox(width: 44, height: 44, child: Center(child: MgIcon(MgIcons.stopFilled, size: 16, color: MgColors.err)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const MgIcon(MgIcons.stopFilled, size: 14, color: MgColors.err),
                    const SizedBox(width: 6),
                    Text(tr.tr('v2RtRecStop'), style: MgType.ctaCompact.copyWith(color: MgColors.err, letterSpacing: 0)),
                  ]),
          ),
        ),
      ),
    );
  }
}
