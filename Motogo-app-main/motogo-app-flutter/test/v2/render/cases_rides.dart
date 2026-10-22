// verify:render cases — Jízdy v2 (rides_cases.dart): Moje zážitky (each
// sub-screen, logged out, recording, loading / error / empty), ride detail
// (S MotoGo / soukromá / výpadek / chybí), recorder (idle / manual / rental
// / weak GPS / off) + its stop confirm, stop editor (new / error), the
// delete + edit dialogs and the share sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_dialogs_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_share_v2.dart';

import '../screens/rides_cases.dart';
import '../screens/rides_pause_cases.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

Future<void> _tapStop(WidgetTester t) async {
  final f = find.byType(RecorderStopButtonV2);
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

List<RenderCase> ridesRenderCases() {
  final out = <RenderCase>[];
  void add(String screen, Map<String, RideCase> m, {bool scaffold = false}) {
    for (final e in m.entries) {
      out.add(RenderCase('rides', screen, e.key, e.value.$1, e.value.$2,
          scaffold: scaffold, loading: e.key.contains('loading'), end: ridesEnd));
    }
  }

  add('moje', mojeCases());
  add('detail', detailCases());
  add('recorder', recorderCases());
  add('point', pointCases(), scaffold: true);
  // Pauza / auto-pauza / cesty (SPEC §9.2): recorder in every phase, trips.
  add('recorder-pause', pauseRecorderCases());
  add('trips', pausePageCases());
  out.addAll([
    RenderCase('rides', 'recorder', 'manual-stop-confirm', () => const RecorderScreenV2(), () => ridesOverrides(recorder: kRecManual),
        scaffold: false, after: _tapStop, end: ridesEnd),
    RenderCase('rides', 'recorder', 'paused-stop-confirm', () => const RecorderScreenV2(), () => tripOverrides(recorder: kRecManualPaused),
        scaffold: false, after: _tapStop, end: ridesEnd),
    RenderCase(
        'rides',
        'dialog',
        'delete',
        () => launcher((c) => showDialog<bool>(
            context: c, builder: (dc) => rideConfirmDeleteV2(dc, title: t(dc).tr('rideDeleteConfirm'), body: 'Pálava za soumraku'))),
        () => ridesOverrides(),
        after: tapOpen),
    RenderCase(
        'rides',
        'dialog',
        'edit',
        () => launcher((c) => showDialog<bool>(
            context: c,
            builder: (dc) => rideEditDialogV2(dc, TextEditingController(text: 'Pálava za soumraku'), TextEditingController()))),
        () => ridesOverrides(),
        after: tapOpen),
    RenderCase('rides', 'sheet', 'share',
        () => launcher((c) => showRideShareSheetV2(c, text: 'Pálava za soumraku', link: 'https://mapy.com/x')), () => ridesOverrides(),
        after: tapOpen),
  ]);
  return out;
}
