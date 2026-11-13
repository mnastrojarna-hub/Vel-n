// RGA-02 (G-1043, v2 pause sheet): while "Ukončit a uložit" runs, the sheet
// stays open — "Pokračovat v cestě" and a second stop must do nothing (the
// old sheet closed itself before stopping, so no second action was
// possible).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_pause_actions_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_pause_sheet_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/rides_cases.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _t(String k) => translations['cs']?[k] ?? k;

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

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
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

  testWidgets('RGA-02: end&save in flight -> resume and a second stop are ignored', (t) async {
    late _SlowStop rec;
    final ov = tripOverrides(recorder: kRecHome);
    ov[0] = rideRecorderProvider.overrideWith((ref) => rec = _SlowStop(ref, kRecHome));
    await pumpV2(t, const SingleChildScrollView(child: RidePauseSheetBodyV2()), overrides: ov, size: const Size(412, 915));
    await _settle(t);
    expect(kRecHome.needsDecision, isTrue);
    await t.tap(find.text(_t('v2RpEndSave')));
    await _settle(t);
    await t.tap(find.text(_t('v2RtRecStopSave')).last);
    await _settle(t);
    expect(rideOpBusyV2, isTrue);
    final resume = find.text(_t('v2RpResumeTripCta'));
    expect(resume, findsOneWidget);
    await t.tap(resume, warnIfMissed: false);
    await _settle(t);
    final again = find.text(_t('v2RpEndSave'));
    if (again.evaluate().isNotEmpty) {
      await t.tap(again.first, warnIfMissed: false);
      await _settle(t);
    }
    expect(rec.calls, ['stop']);
    // The stop finishes; the lock stays until its result sheet is closed
    // (same as trasyConfirmStopRide), so nothing more is asserted here.
    rec.gate.complete();
    await _settle(t);
  });
}
