import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/friendly_error.dart';
import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_dock.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_animated_size.dart';
import '../../../../core/v2/states/mg_state_banner.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/widgets/error_feedback.dart' show openFixSettings;
import '../../ride_actions.dart';
import '../../ride_recorder.dart';
import 'recorder_parts_v2.dart';
import 'ride_pause_actions_v2.dart';
import 'ride_phase_v2.dart';

/// Opens the full-screen recorder on the root navigator (no router change;
/// system back = pop, leaving keeps the recording running).
Future<void> openRideRecorderV2(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const RecorderScreenV2()));

/// "Záznam jízdy" (DESIGN_V22 §4.2 D; dark, outdoor) + SPEC §9.2. Reads
/// `rideRecorderProvider`. Dock: idle → ZAZNAMENAT JÍZDU (`toggleManualRide`,
/// PM-4); recording → ❚❚ POZASTAVIT / ▶ POKRAČOVAT (own AND rental) +
/// "Ukončit záznam" for a manual ride (confirm FIRST, busy only while the
/// stop runs — r1); a guard pause (home / long) → POKRAČOVAT V CESTĚ +
/// "Ukončit a uložit". A rental ends with the return (note under the card).
/// The dock is the Scaffold's bottom bar, so a toast (Pozastaveno /
/// Pokračuju) floats ABOVE it and never covers POKRAČOVAT / UKONČIT.
class RecorderScreenV2 extends ConsumerStatefulWidget {
  const RecorderScreenV2({super.key});

  @override
  ConsumerState<RecorderScreenV2> createState() => _RecorderScreenV2State();
}

class _RecorderScreenV2State extends ConsumerState<RecorderScreenV2> {
  bool _hint = false;
  bool _how = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// r1: the question first (nothing busy while it is open), then the stop.
  Future<void> _stop() async {
    if (_busy) return;
    final paused = ref.read(rideRecorderProvider).isPaused;
    if (!await trasyConfirmStop(context, paused: paused) || !mounted) return;
    await _run(() => toggleManualRide(context, ref, running: true));
  }

  Widget _action(AppTranslations tr, RideRecorderState rec) {
    if (!rec.recording) {
      return MgCta(
        label: tr.tr('v2RideRecStart'),
        loop: !_busy,
        busy: _busy,
        semanticLabel: tr.tr('v2RtRecA11y'),
        onTap: () => _run(() => toggleManualRide(context, ref, running: false)),
      );
    }
    final Widget primary;
    Widget? secondary;
    if (rec.needsDecision) {
      primary = MgCta(
        label: tr.tr('v2RpResumeTripCta'),
        busy: _busy,
        semanticLabel: tr.tr('v2RpA11yResume'),
        onTap: () => _run(() => rideTogglePauseV2(context, ref)),
      );
      secondary = MgBtnGhostDark(label: tr.tr('v2RpEndSave'), icon: MgIcons.stopFilled, onTap: _busy ? null : _stop);
    } else {
      primary = RecorderPauseButtonV2(
        paused: rec.isManualPaused,
        auto: RecPhaseV2.of(tr, rec).auto,
        busy: _busy,
        onTap: () => _run(() => rideTogglePauseV2(context, ref)),
      );
      if (rec.canStop) secondary = RecorderStopButtonV2(onTap: _busy ? null : _stop);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      primary,
      if (secondary != null) ...[const SizedBox(height: 10), secondary],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    final live = rec.recording;

    return Scaffold(
      backgroundColor: MgColors.night,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.2),
            radius: 1.3,
            colors: [MgColors.glow, MgColors.night],
            stops: [0, 0.62],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(children: [
                MgV2Back(onTap: () => Navigator.of(context).maybePop(), style: MgBackStyle.dark),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: MgWordFit(
                      minScale: 0.75,
                      child: Text(tr.tr('rideRecordTitle'),
                          maxLines: 2, style: MgType.section.copyWith(color: MgColors.onDark)),
                    ),
                  ),
                ),
                MgIconButton(
                  icon: MgIcons.info,
                  semanticLabel: tr.tr('v2RideRecInfoA11y'),
                  onTap: () => setState(() => _hint = !_hint),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  MgAnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topCenter,
                    child: _hint
                        ? Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: MgColors.white(0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: MgColors.white(0.12)),
                            ),
                            child: Text(tr.tr('rideRecordHint'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  if (live && rec.gpsLost) ...[
                    MgStateBanner(
                      dark: true,
                      tone: MgTone.warn,
                      icon: MgIcons.gps,
                      title: tr.tr('v2RtRecGps'),
                      text: tr.tr('eoRideGpsLost'),
                      actions: [
                        MgBtnText(
                          label: tr.tr('eoOpenSettings'),
                          dark: true,
                          onTap: () => openFixSettings(const FriendlyError(FriendlyKind.locationOff)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  RecorderLiveCardV2(rec: rec),
                  if (live && rec.needsDecision) ...[
                    const SizedBox(height: 12),
                    MgStateBanner(
                      dark: true,
                      tone: MgTone.info,
                      icon: MgIcons.gps,
                      title: RecPhaseV2.of(tr, rec).title,
                      text: recHintV2(tr, rec),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Jak funguje automatická pauza (vysvětlení stavu).
                  RecorderHowV2(
                    open: _how,
                    onTap: () => setState(() => _how = !_how),
                    text: live ? recHintV2(tr, rec) : tr.tr('v2RpHintAuto'),
                  ),
                  const SizedBox(height: 16),
                  if (live && !rec.manual) ...[
                    RecorderNoteV2(icon: MgIcons.key, text: tr.tr('v2RideRecAutoNote')),
                    const SizedBox(height: 10),
                    RecorderNoteV2(icon: MgIcons.flag, text: tr.tr('v2RpRentalEnds')),
                    const SizedBox(height: 10),
                  ],
                  // Během záznamu jsou km a čas vidět živě výš — poznámka „uvidíš po
                  // uložení" platí jen před startem.
                  if (!live) ...[
                    RecorderNoteV2(icon: MgIcons.info, text: tr.tr('v2RideRecAfter')),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: MgColors.white(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: MgColors.white(0.10)),
                    ),
                    child: MgSwitchRow(
                      dark: true,
                      title: tr.tr('v2RideAutoTitle'),
                      sub: tr.tr('v2RideAutoSub'),
                      value: rec.enabled,
                      onChanged: (v) => ref.read(rideRecorderProvider.notifier).setEnabled(v),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
      bottomNavigationBar: MgDock(child: _action(tr, rec)),
    );
  }
}
