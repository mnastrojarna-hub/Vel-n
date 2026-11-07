import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import 'ride_recorder.dart';
import 'ride_start_feedback.dart';

/// Akce záznamu jízdy sdílené všemi ovladači (Moje zážitky, navigace,
/// menu „Přidat", v2 dok / Domů / nahrávač) — SPEC §9.1.

/// Pozastavit / pokračovat (vlastní jízda i výpůjčka). Pozastavení nejde
/// zkazit (GPS se vypne hned); pokračování má stejné kontroly jako ruční
/// start a každý neúspěch řekne co a jak opravit. Volat z klepnutí.
Future<void> rideTogglePause(BuildContext context, WidgetRef ref) async {
  // Kontejner místo `ref` po `await` — ovladač (sheet, menu) se mezitím
  // může zavřít a jeho `ref` by už neplatil.
  final container = ProviderScope.containerOf(context, listen: false);
  final n = ref.read(rideRecorderProvider.notifier);
  final st = ref.read(rideRecorderProvider);
  final msg = ScaffoldMessenger.of(context);
  final tr = t(context);
  if (!st.recording) return;
  if (!st.isManualPaused) {
    await n.pause();
    showRidePauseFeedback(msg, tr, paused: true);
    return;
  }
  final r = await n.resume();
  if (r != RideStartResult.ok) {
    showRideStartResult(msg, tr, r);
    return;
  }
  showRidePauseFeedback(msg, tr,
      paused: false, armed: container.read(rideRecorderProvider).isArmed);
}

/// Ukončit (a uložit) vlastní záznam s hláškou výsledku — jako tlačítko
/// „Ukončit záznam jízdy". Kratší než 1 km se zahodí; offline se ukončení
/// zkusí znovu samo (NENÍ to „krátká jízda").
Future<bool?> rideStopWithFeedback(BuildContext context, WidgetRef ref) async {
  final n = ref.read(rideRecorderProvider.notifier);
  final msg = ScaffoldMessenger.of(context);
  final tr = t(context);
  final kept = await n.stop();
  msg
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(tr.tr(kept == null
          ? 'rideManualStopFailed'
          : (kept ? 'rideManualSaved' : 'rideManualTooShort'))),
    ));
  return kept;
}
