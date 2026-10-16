import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../ride_recorder.dart' show RideRecorderState;

/// The recorder's live card (DESIGN_V22 §4.2 D, dark): what the recorder
/// really knows — recording or ready, manual / rental mode, GPS lost, the
/// number of track points. No km / time / trace (the recorder does not
/// expose them; they appear on the saved ride).
class RecorderLiveCardV2 extends StatelessWidget {
  final RideRecorderState rec;
  const RecorderLiveCardV2({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final live = rec.recording;
    final reduced = MgMotion.reduced(context);
    final status = live ? tr.tr('rideRecording') : tr.tr('v2RideRecReady');
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
        decoration: BoxDecoration(
          gradient: const RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [MgColors.glow, MgColors.panel, MgColors.night],
            stops: [0, 0.55, 1],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: live ? MgColors.sosDot.withValues(alpha: 0.55) : MgColors.neonA(0.16), width: live ? 1.5 : 1),
          boxShadow: MgShadows.dark,
        ),
        child: Column(children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? MgColors.errDarkBg : MgColors.neonA(0.10),
              border: Border.all(color: live ? MgColors.sosDot.withValues(alpha: 0.6) : MgColors.neonA(0.35), width: 2),
            ),
            child: Center(
              child: live
                  ? MgPing(size: 22, spread: 14, color: MgColors.sosDot, active: !reduced)
                  : MgPop(playOnMount: true, child: const MgIcon(MgIcons.recordDot, size: 40, color: MgColors.neon)),
            ),
          ),
          const SizedBox(height: 14),
          Text(live ? status.toUpperCase() : status,
              textAlign: TextAlign.center,
              style: MgType.h2.copyWith(color: MgColors.onDark, letterSpacing: live ? 1 : 0)),
          const SizedBox(height: 10),
          if (live)
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              _Chip(icon: rec.manual ? MgIcons.bike : MgIcons.key, label: tr.tr(rec.manual ? 'v2RtRecManual' : 'v2RtRecAuto')),
              _Chip(icon: MgIcons.route, label: tr.trArgs('v2RideRecPoints', {'n': rec.points})),
              _Chip(
                icon: rec.gpsLost ? MgIcons.signalOff : MgIcons.gps,
                label: tr.tr(rec.gpsLost ? 'v2RtRecGps' : 'v2RideRecGpsOk'),
                warn: rec.gpsLost,
              ),
            ])
          else
            Text(tr.tr('rideManualHint'),
                textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.onDarkLead)),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String icon;
  final String label;
  final bool warn;
  const _Chip({required this.icon, required this.label, this.warn = false});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: warn ? MgColors.warnDarkBg : MgColors.white(0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: warn ? MgColors.warnDark.withValues(alpha: 0.6) : MgColors.white(0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 15, color: warn ? MgColors.warnDark : MgColors.neon),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: MgType.tab(MgType.small.copyWith(
                    fontWeight: FontWeight.w800, color: warn ? MgColors.warnDark : MgColors.onDarkBody))),
          ),
        ]),
      );
}

/// "■ UKONČIT ZÁZNAM" — white 56 button with a red label (ending is not a
/// money action, so it is never the rank CTA; V22 §4.2 D).
class RecorderStopButtonV2 extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  const RecorderStopButtonV2({super.key, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final label = t(context).tr('rideManualStop');
    return Semantics(
      button: true,
      enabled: onTap != null && !busy,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: busy ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: MgColors.black(0.4), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -8)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: MgColors.err))
            else
              const MgIcon(MgIcons.stopFilled, size: 18, color: MgColors.err),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label.toUpperCase(),
                  textAlign: TextAlign.center, style: MgType.cta.copyWith(color: MgColors.err, letterSpacing: 0.4)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Note row on dark (icon + text).
class RecorderNoteV2 extends StatelessWidget {
  final String icon;
  final String text;
  const RecorderNoteV2({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: MgIcon(icon, size: 18, color: MgColors.neon)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.onDarkLead))),
      ]);
}
