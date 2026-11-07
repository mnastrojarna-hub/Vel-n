import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import 'ride_recorder.dart';
import 'ride_start_feedback.dart';

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
  showRideStartResult(msg, tr, r, armed: ref.read(rideRecorderProvider).isArmed);
}
