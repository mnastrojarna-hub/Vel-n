import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import 'ride_recorder.dart';
import 'ride_start_feedback.dart';
import '../../core/v2/flag/v2_scope.dart';
import 'v2/rides/ride_results_v2.dart';

/// Ruční záznam jízdy — zapnout / vypnout (PLAN PM-4). Tělo PŘESNĚ podle
/// `_MyExperiencesScreenState._toggleManualRide` (jediná změna: `mounted`
/// → `context.mounted`, funkce už nežije ve State). Jízda kratší než 1 km
/// se zahodí; výsledek startu hlásí `showRideStartResult` (co je špatně a
/// jak to opravit). Volá ji v2 Domů (řádek „Zaznamenat jízdu") a má ji
/// převzít i Moje zážitky / docky (oblast jízd).
Future<void> toggleManualRide(BuildContext context, WidgetRef ref, {required bool running}) async {
  final n = ref.read(rideRecorderProvider.notifier);
  final msg = ScaffoldMessenger.of(context);
  if (running) {
    final kept = await n.stop();
    if (!context.mounted) return;
    // v2 (F-06): the result as a sheet (saved = success), same outcome.
    if (MgV2.on(context)) {
      await showRideStopResultV2(context, kept);
      return;
    }
    // null = server jízdu nevzal (offline) → zkusí se to znovu, NENÍ
    // to „příliš krátká".
    msg.showSnackBar(SnackBar(
      content: Text(t(context).tr(kept == null
          ? 'rideManualStopFailed'
          : (kept ? 'rideManualSaved' : 'rideManualTooShort'))),
    ));
    return;
  }
  final tr = t(context);
  final r = await n.startManualResult();
  if (!context.mounted) return;
  // Záznam čeká na rozjezd (auto-pauza) → řekne to hláška.
  if (MgV2.on(context)) {
    await showRideStartResultV2(context, r,
        armed: ref.read(rideRecorderProvider).isArmed,
        onRetry: () => toggleManualRide(context, ref, running: false));
    return;
  }
  showRideStartResult(msg, tr, r, armed: ref.read(rideRecorderProvider).isArmed);
}
