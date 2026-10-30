import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_anim_loops.dart';
import '../../../../core/v2/motion/mg_animated_size.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_live_stats.dart' show rideLiveDuration, rideLiveKm;
import '../../ride_recorder.dart' show RideRecorderState;
import 'ride_phase_v2.dart';

/// The recorder's live card (DESIGN_V22 §4.2 D, dark) by phase (SPEC §9.2):
/// NAHRÁVÁM (red ping) / ČEKÁM NA ROZJEZD (neon ring) / STOJÍŠ · AUTO-PAUZA
/// or POZASTAVENO (static ❚❚, "od HH:MM") / ZPĚT NA STARTU · GPS VYPNUTÉ
/// (guards) / POLOHA NEDOSTUPNÁ (warn); one sentence of
/// what is happening; chips km · v sedle · Ø (≥ 5 min) · N. den (≥ 2) ·
/// mode · GPS. Idle: "Připraveno" + the manual-start hint.
class RecorderLiveCardV2 extends StatelessWidget {
  final RideRecorderState rec;
  const RecorderLiveCardV2({super.key, required this.rec});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final live = rec.recording;
    final ph = RecPhaseV2.of(tr, rec);
    final tone = live ? ph.tone : null;
    final edge = switch (tone) {
      RecToneV2.rec => MgColors.sosDot.withValues(alpha: 0.55),
      RecToneV2.warn => MgColors.warnDark.withValues(alpha: 0.6),
      RecToneV2.paused => MgColors.white(0.30),
      _ => MgColors.neonA(live ? 0.45 : 0.16),
    };
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
          border: Border.all(color: edge, width: live ? 1.5 : 1),
          boxShadow: MgShadows.dark,
        ),
        child: Column(children: [
          _Disc(tone: tone),
          const SizedBox(height: 14),
          // Stav celý, nikdy „ENREGISTREME|NT": nejdřív zmenšit.
          MgWordFit(
            minScale: 0.6,
            alignment: Alignment.center,
            child: Text(live ? ph.status : tr.tr('v2RideRecReady'),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: MgType.h2.copyWith(color: MgColors.onDark, letterSpacing: live ? 1 : 0)),
          ),
          const SizedBox(height: 6),
          if (live) ...[
            MgWordFit(
              minScale: 0.85,
              alignment: Alignment.center,
              child: Text(ph.title,
                  textAlign: TextAlign.center,
                  style: MgType.body.copyWith(color: tone == RecToneV2.warn ? MgColors.warnDark : MgColors.onDarkLead)),
            ),
            if (ph.since != null) ...[
              const SizedBox(height: 2),
              Text(ph.since!,
                  textAlign: TextAlign.center,
                  style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDarkBody))),
            ],
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              _Chip(icon: MgIcons.ruler, label: '${rideLiveKm(rec.liveKm, tr.lang)} km', strong: true),
              _Chip(icon: MgIcons.ride, label: tr.trArgs('v2RpChipRiding', {'time': rideLiveDuration(rec.liveMovingSec)})),
              if (recAvgV2(rec) case final a?) _Chip(icon: MgIcons.speed, label: tr.trArgs('v2RpChipAvg', {'v': a})),
              if (rec.liveStages >= 2) _Chip(icon: MgIcons.moon, label: tr.trArgs('v2RpChipDay', {'n': rec.liveStages})),
              _Chip(icon: rec.manual ? MgIcons.bike : MgIcons.key, label: tr.tr(rec.manual ? 'v2RtRecManual' : 'v2RtRecAuto')),
              _Chip(
                icon: rec.gpsLost ? MgIcons.signalOff : MgIcons.gps,
                label: tr.tr(recGpsChipKeyV2(rec)),
                warn: rec.gpsLost,
              ),
            ]),
          ] else
            Text(tr.tr('rideManualHint'),
                textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.onDarkLead)),
        ]),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final RecToneV2? tone;
  const _Disc({required this.tone});

  @override
  Widget build(BuildContext context) {
    final reduced = MgMotion.reduced(context);
    final (bg, border) = switch (tone) {
      RecToneV2.rec => (MgColors.errDarkBg, MgColors.sosDot.withValues(alpha: 0.6)),
      RecToneV2.warn => (MgColors.warnDarkBg, MgColors.warnDark.withValues(alpha: 0.6)),
      RecToneV2.paused => (MgColors.white(0.08), MgColors.white(0.35)),
      _ => (MgColors.neonA(0.10), MgColors.neonA(0.35)),
    };
    final Widget inner = switch (tone) {
      RecToneV2.rec => MgPing(size: 22, spread: 14, color: MgColors.sosDot, active: !reduced),
      RecToneV2.warn => const MgIcon(MgIcons.signalOff, size: 34, color: MgColors.warnDark),
      RecToneV2.paused => const MgIcon(MgIcons.pause, size: 36, color: MgColors.onDark, stroke: 2.6),
      RecToneV2.armed => const MgIcon(MgIcons.recordDot, size: 40, color: MgColors.neon),
      null => MgPop(playOnMount: true, child: const MgIcon(MgIcons.recordDot, size: 40, color: MgColors.neon)),
    };
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: border, width: 2)),
      child: Center(child: inner),
    );
  }
}

class _Chip extends StatelessWidget {
  final String icon;
  final String label;
  final bool warn;
  final bool strong;
  const _Chip({required this.icon, required this.label, this.warn = false, this.strong = false});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: warn ? MgColors.warnDarkBg : MgColors.white(strong ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: warn ? MgColors.warnDark.withValues(alpha: 0.6) : MgColors.white(0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 15, color: warn ? MgColors.warnDark : MgColors.neon),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: MgType.tab(MgType.small.copyWith(
                    fontWeight: FontWeight.w800, color: warn ? MgColors.warnDark : (strong ? MgColors.onDark : MgColors.onDarkBody)))),
          ),
        ]),
      );
}

/// White 56 button of the recorder's dock: "❚❚ POZASTAVIT" (every recording
/// — own AND rental), "▶ POKRAČOVAT" when manually paused, "❚❚ VYPNOUT
/// GPS" while auto-paused ([auto]: it already stands by itself, the same
/// pause only turns GPS off — nothing the rider has to do).
class RecorderPauseButtonV2 extends StatelessWidget {
  final bool paused;
  final bool auto;
  final VoidCallback? onTap;
  final bool busy;
  const RecorderPauseButtonV2({super.key, required this.paused, required this.onTap, this.busy = false, this.auto = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final gpsOff = auto && !paused;
    final label = gpsOff ? tr.tr('v2RpGpsOffBtn').toUpperCase() : tr.tr(paused ? 'v2RpResumeCta' : 'v2RpPauseCta');
    return Semantics(
      button: true,
      enabled: onTap != null && !busy,
      label: tr.tr(gpsOff ? 'v2RpA11yGpsOff' : (paused ? 'v2RpA11yResume' : 'v2RpA11yPause')),
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
              const RecBusyV2(color: MgColors.ink)
            else
              MgIcon(paused ? MgIcons.playFilled : MgIcons.pause, size: 20, color: MgColors.ink, stroke: 2.6),
            const SizedBox(width: 10),
            Flexible(
              child: MgWordFit(
                minScale: 0.7,
                child: Text(label, maxLines: 1, softWrap: false, style: MgType.cta.copyWith(color: MgColors.ink, letterSpacing: 0.4)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Busy mark of a dock button: a spinner, a static arc under reduced motion.
class RecBusyV2 extends StatelessWidget {
  final Color color;
  const RecBusyV2({super.key, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: color, value: MgMotion.reduced(context) ? 0.7 : null),
      );
}

/// "■ UKONČIT ZÁZNAM" — white 56 button with a red label (ending is not a
/// money action, so it is never the rank CTA; V22 §4.2 D). Busy only while
/// the stop itself runs (the confirm comes first).
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
            if (busy) const RecBusyV2(color: MgColors.err) else const MgIcon(MgIcons.stopFilled, size: 18, color: MgColors.err),
            const SizedBox(width: 10),
            Flexible(
              child: MgWordFit(
                minScale: 0.7,
                child: Text(label.toUpperCase(),
                    textAlign: TextAlign.center, maxLines: 2, style: MgType.cta.copyWith(color: MgColors.err, letterSpacing: 0.4)),
              ),
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

/// "Jak funguje automatická pauza?" — a 44 px row that opens the
/// explanation of the current state (auto-pause, manual pause, guard).
class RecorderHowV2 extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  final String text;
  const RecorderHowV2({super.key, required this.open, required this.onTap, required this.text});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      decoration: BoxDecoration(
        color: MgColors.white(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.white(0.10)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: open,
          label: tr.tr('v2RpHowTitle'),
          excludeSemantics: true,
          child: MgPress(
            scale: 0.98,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const MgIcon(MgIcons.pause, size: 18, color: MgColors.neon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MgWordFit(
                      minScale: 0.8,
                      child: Text(tr.tr('v2RpHowTitle'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
                    ),
                  ),
                  MgIcon(open ? MgIcons.chevronUp : MgIcons.chevronDown, size: 18, color: MgColors.onDarkLead),
                ]),
              ),
            ),
          ),
        ),
        MgAnimatedSize(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(40, 0, 12, 12),
                  child: Text(text, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}
