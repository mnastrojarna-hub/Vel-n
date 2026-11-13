import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/states/mg_state_sheet.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';
import '../../../../core/v2/widgets/mg_toast.dart';
import '../../ride_actions.dart';
import '../../ride_recorder.dart';
import 'ride_results_v2.dart';
import 'ride_phase_v2.dart' show recLiveLineV2;

/// Manual pause / resume from any v2 surface (dock, recorder, Domů row,
/// nav chip, pause sheet) — SPEC §5.2 / §9.2. Pause is local and cannot
/// fail (GPS off at once, survives a restart); resume runs the SAME checks
/// as a manual start, so a failure gets the existing what / why / fix
/// message (`showRideStartResult`, with "Otevřít nastavení"). The toast
/// floats above a page dock (Trasy / Moje record dock) — it must never
/// cover the ▶ / ❚❚ the rider may want to tap right away; the recorder
/// screen keeps its dock in `bottomNavigationBar` for the same reason.
Future<void> rideTogglePauseV2(BuildContext context, WidgetRef ref) async {
  final n = ref.read(rideRecorderProvider.notifier);
  final rec = ref.read(rideRecorderProvider);
  if (!rec.recording || _rideOpBusyV2) return;
  final tr = t(context);
  if (rec.isManualPaused) {
    final msg = ScaffoldMessenger.maybeOf(context);
    final RideStartResult r;
    _rideOpBusyV2 = true;
    try {
      r = await n.resume();
    } finally {
      _rideOpBusyV2 = false;
    }
    if (!context.mounted) return;
    if (r == RideStartResult.ok) {
      // Armed = GPS back on, the ride continues at the first move-off.
      final armed = ref.read(rideRecorderProvider).isPaused;
      showMgToast(context, tr.tr(armed ? 'v2RpToastResumed' : 'v2RpToastResumedNow'),
          icon: MgIcons.playFilled, lift: rideToastLiftV2(context));
    } else if (msg != null) {
      // v2 (F-06): what · why · fix as a T2 sheet; retry = resume again.
      await showRideStartResultV2(context, r, onRetry: () => rideTogglePauseV2(context, ref));
    }
    return;
  }
  _rideOpBusyV2 = true;
  try {
    await n.pause();
  } finally {
    _rideOpBusyV2 = false;
  }
  if (context.mounted) showMgToast(context, tr.tr('v2RpToastPaused'), icon: MgIcons.pause, lift: rideToastLiftV2(context));
}

/// Height of the visible page dock this [context] sits in (0 outside the
/// v2 chrome — e.g. the recorder screen, whose dock is the bottom bar).
double rideToastLiftV2(BuildContext context) => MgChromeScope.chromeOf(context)?.dockHeight ?? 0;

/// "Ukončit záznam?" (presentation only) → true = end and save. Light T2
/// sheet (DESIGN_V22 §4.4 #13, board Zazitky stav 13 — thumb reach with
/// gloves): stop disc, what is being saved ("38,2 km · 1 h 12 min v
/// sedle"), the existing body (+ `v2RpStopBody2` while paused); primary
/// UKONČIT A ULOŽIT (ink) over POKRAČOVAT V JÍZDĚ (ghost). ✕ / scrim /
/// swipe-down = continue (false), as the old dialog's barrier.
Future<bool> trasyConfirmStop(BuildContext context, {bool paused = false}) async {
  final tr = t(context);
  final body = tr.tr('v2RtRecStopBody');
  final rec = ProviderScope.containerOf(context, listen: false).read(rideRecorderProvider);
  final ok = await showMgSheet<bool>(
    context,
    builder: (_) => MgStateSheetBody(
      tone: MgTone.info,
      icon: MgIcons.stop,
      title: tr.tr('v2RtRecStopQ'),
      why: rec.recording ? recLiveLineV2(tr, rec) : null,
      support: false,
      children: [
        Text(paused ? '$body\n\n${tr.tr('v2RpStopBody2')}' : body, style: MgType.small.copyWith(color: MgColors.meta)),
      ],
    ),
    footer: Builder(
      builder: (c) => MgSheetButtons(
        primary: MgBtnInk(label: tr.tr('v2RtRecStopSave'), onTap: () => Navigator.of(c).pop(true)),
        secondary: MgBtnGhostLight(label: tr.tr('v2RtRecContinue'), onTap: () => Navigator.of(c).pop(false)),
      ),
    ),
  );
  return ok == true;
}

/// The existing stop (`toggleManualRide(running: true)`, PM-4 — the same
/// "Uloženo / Příliš krátká / Nepodařilo se" results). Ask first.
Future<void> trasyStopNowV2(BuildContext context, WidgetRef ref) => toggleManualRide(context, ref, running: true);

/// Asks first, then the existing stop. Nothing is busy while the question
/// is open.
Future<void> trasyConfirmStopRide(BuildContext context, WidgetRef ref) => _rideOnceV2(() async {
      final paused = ref.read(rideRecorderProvider).isPaused;
      if (await trasyConfirmStop(context, paused: paused) && context.mounted) {
        await trasyStopNowV2(context, ref);
      }
    });

/// Manual start from the v2 dock / Domů row — the existing
/// `toggleManualRide(running: false)` under the double-tap lock.
Future<void> rideStartManualV2(BuildContext context, WidgetRef ref) =>
    _rideOnceV2(() => toggleManualRide(context, ref, running: false));

/// G-1043: double-tap lock of the v2 record controls (the old card had a
/// `_busy` flag): while a start / stop / pause / resume runs, a second tap
/// on ANY v2 control is ignored (a second tap undid the pause, or showed a
/// spurious "Záznam se nespustil").
bool _rideOpBusyV2 = false;

/// True while a v2 record action runs.
bool get rideOpBusyV2 => _rideOpBusyV2;

/// Public form of the lock for v2 sheets (RGA-02: the pause sheet's
/// stop keeps the sheet open, so resume / a second stop must wait).
Future<void> rideOnceV2(Future<void> Function() op) => _rideOnceV2(op);

Future<void> _rideOnceV2(Future<void> Function() op) async {
  if (_rideOpBusyV2) return;
  _rideOpBusyV2 = true;
  try {
    await op();
  } finally {
    _rideOpBusyV2 = false;
  }
}
