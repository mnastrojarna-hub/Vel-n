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
import '../record_dock_v2.dart' show trasyConfirmStopRide;
import 'recorder_parts_v2.dart';

/// Opens the full-screen recorder on the root navigator (no router change;
/// system back = pop, leaving keeps the recording running).
Future<void> openRideRecorderV2(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const RecorderScreenV2()));

/// "Záznam jízdy" (DESIGN_V22 §4.2 D; dark, outdoor). Reads
/// `rideRecorderProvider`; start / stop go through the shared
/// `toggleManualRide` (PM-4 — same permission handling and result messages
/// as everywhere), the switch is the existing auto-record `setEnabled`.
/// A rental (automatic) recording has no stop — it ends with the rental.
class RecorderScreenV2 extends ConsumerStatefulWidget {
  const RecorderScreenV2({super.key});

  @override
  ConsumerState<RecorderScreenV2> createState() => _RecorderScreenV2State();
}

class _RecorderScreenV2State extends ConsumerState<RecorderScreenV2> {
  bool _hint = false;
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

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    final live = rec.recording;

    final Widget action;
    if (!live) {
      action = MgCta(
        label: tr.tr('v2RideRecStart'),
        loop: !_busy,
        busy: _busy,
        semanticLabel: tr.tr('v2RtRecA11y'),
        onTap: () => _run(() => toggleManualRide(context, ref, running: false)),
      );
    } else if (rec.manual) {
      action = RecorderStopButtonV2(
        busy: _busy,
        onTap: () => _run(() => trasyConfirmStopRide(context, ref)),
      );
    } else {
      action = MgBtnGhostDark(label: tr.back, icon: MgIcons.chevronLeft, onTap: () => Navigator.of(context).maybePop());
    }

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
                  const SizedBox(height: 16),
                  if (live && !rec.manual) ...[
                    RecorderNoteV2(icon: MgIcons.key, text: tr.tr('v2RideRecAutoNote')),
                    const SizedBox(height: 10),
                  ],
                  RecorderNoteV2(icon: MgIcons.info, text: tr.tr('v2RideRecAfter')),
                  const SizedBox(height: 16),
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
            MgDock(child: action),
          ]),
        ),
      ),
    );
  }
}
