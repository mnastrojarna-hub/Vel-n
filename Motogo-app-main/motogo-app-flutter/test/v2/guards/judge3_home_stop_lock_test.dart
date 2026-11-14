// RGA-01 (G-1043 on Domů): while the Home row's Stop runs (confirmed,
// recorder still stopping) the pause disc and a second Stop are ignored —
// the same v2 lock as the Trasy dock, as the old card's _busy did.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/v2/home_record_row_v2.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/v2/rides/rec_widgets_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/rides_cases.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/fakes_rides.dart';
import '../support/v2_harness.dart';

class _SlowStop extends FakePauseRecorder {
  final Completer<void> gate = Completer<void>();
  _SlowStop(super.ref, super.initial);
  @override
  Future<bool?> stop() async {
    calls.add('stop');
    await gate.future;
    state = state.copyWith(recording: false, clearRide: true);
    return true;
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRidesStrings();
    ridesMockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });
  testWidgets('RGA-01: Home stop in flight — pause disc and a 2nd Stop are ignored', (t) async {
    late _SlowStop rec;
    final ov = tripOverrides(recorder: kRecRiding);
    ov[0] = rideRecorderProvider.overrideWith((ref) => rec = _SlowStop(ref, kRecRiding));
    await pumpV2(t, const HomeRecordRowV2(), overrides: ov, size: const Size(412, 915));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.bySemanticsLabel('Ukončit záznam jízdy'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text('Ukončit a uložit'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // stop is now in flight
    expect(find.byType(RecPauseDiscV2), findsOneWidget);
    await t.tap(find.byType(RecPauseDiscV2));
    await t.pump();
    // second stop tap
    await t.tap(find.bySemanticsLabel('Ukončit záznam jízdy'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Ukončit a uložit'), findsNothing, reason: 'no second stop confirm');
    expect(rec.calls, ['stop'], reason: 'no pause while the stop runs');
    rec.gate.complete();
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(rec.calls, ['stop']);
    // Close the stop result sheet: the lock is released when it closes.
    Navigator.of(t.element(find.byType(HomeRecordRowV2)), rootNavigator: true).maybePop();
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  });
}
