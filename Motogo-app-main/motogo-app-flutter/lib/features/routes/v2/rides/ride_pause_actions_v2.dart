import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/widgets/mg_dialog.dart';
import '../../../../core/v2/widgets/mg_toast.dart';
import '../../ride_actions.dart';
import '../../ride_recorder.dart';
import '../../ride_start_feedback.dart' show showRideStartResult;

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
  if (!rec.recording) return;
  final tr = t(context);
  if (rec.isManualPaused) {
    final msg = ScaffoldMessenger.maybeOf(context);
    final r = await n.resume();
    if (!context.mounted) return;
    if (r == RideStartResult.ok) {
      // Armed = GPS back on, the ride continues at the first move-off.
      final armed = ref.read(rideRecorderProvider).isPaused;
      showMgToast(context, tr.tr(armed ? 'v2RpToastResumed' : 'v2RpToastResumedNow'),
          icon: MgIcons.playFilled, lift: rideToastLiftV2(context));
    } else if (msg != null) {
      showRideStartResult(msg, tr, r);
    }
    return;
  }
  await n.pause();
  if (context.mounted) showMgToast(context, tr.tr('v2RpToastPaused'), icon: MgIcons.pause, lift: rideToastLiftV2(context));
}

/// Height of the visible page dock this [context] sits in (0 outside the
/// v2 chrome — e.g. the recorder screen, whose dock is the bottom bar).
double rideToastLiftV2(BuildContext context) => MgChromeScope.chromeOf(context)?.dockHeight ?? 0;

/// "Ukončit záznam?" (presentation only) → true = end and save. While the
/// trip is paused the body adds where it will be saved (`v2RpStopBody2`).
Future<bool> trasyConfirmStop(BuildContext context, {bool paused = false}) async {
  final tr = t(context);
  final body = tr.tr('v2RtRecStopBody');
  final ok = await showMgConfirm(
    context,
    title: tr.tr('v2RtRecStopQ'),
    body: paused ? '$body\n\n${tr.tr('v2RpStopBody2')}' : body,
    safeLabel: tr.tr('v2RtRecContinue'),
    actionLabel: tr.tr('v2RtRecStopSave'),
  );
  return ok == true;
}

/// The existing stop (`toggleManualRide(running: true)`, PM-4 — the same
/// "Uloženo / Příliš krátká / Nepodařilo se" results). Ask first.
Future<void> trasyStopNowV2(BuildContext context, WidgetRef ref) => toggleManualRide(context, ref, running: true);

/// Asks first, then the existing stop. Nothing is busy while the question
/// is open.
Future<void> trasyConfirmStopRide(BuildContext context, WidgetRef ref) async {
  final paused = ref.read(rideRecorderProvider).isPaused;
  if (await trasyConfirmStop(context, paused: paused) && context.mounted) {
    await trasyStopNowV2(context, ref);
  }
}
