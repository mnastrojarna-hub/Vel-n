// Safeguards of ride recording and trips in the NEW look (soupis pojistek
// 2026-11-12, part "after"): the real cause when a start fails (G-1040 /
// G-1041), the decision after a safety pause and the "rental ends by
// itself" note (G-1046 / G-1045), the double-tap lock of the record
// controls (G-1043), the trip detail busy lock and failure toast (G-1076 /
// G-1078), the live badge of the ride this phone records (G-1038), the
// "remove from trip" lock (G-1065) and the merge name pre-fill (G-1087).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:motogo_app/features/routes/v2/record_dock_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_tabs_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/rec_widgets_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_card_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_merge_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_results_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_trip_card_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_trip_row_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_actions_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_detail_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/rides_cases.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _t(String key) => translations['cs']?[key] ?? key;

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Recorder whose pause waits until the test releases it.
class _SlowPauseRecorder extends FakePauseRecorder {
  final Completer<void> gate = Completer<void>();
  _SlowPauseRecorder(super.ref, super.initial);

  @override
  Future<void> pause() async {
    calls.add('pause');
    await gate.future;
  }
}

Widget _rec(RideRecorderState s, Widget child, {FakePauseRecorder Function(Ref ref)? make}) => ProviderScope(
    overrides: [rideRecorderProvider.overrideWith((ref) => make?.call(ref) ?? FakePauseRecorder(ref, s))], child: child);

/// [child] whose trip-server seam waits for [gate] and counts calls.
Widget _slowSet(Completer<void> gate, List<int> calls, Widget child) => ProviderScope(
      overrides: [
        tripSetSeamV2.overrideWithValue((items) async {
          calls.add(items.length);
          await gate.future;
          return RideTripSetResult(RideTripSetKind.ok, updated: items.length);
        }),
      ],
      child: child,
    );

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

  testWidgets('G-1040/G-1041 failed start names the missing signal, not "restart the app"', (t) async {
    await pumpV2(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showRideStartResultV2(c, RideStartResult.failed, onRetry: () {}),
            child: const Text('go'),
          ),
        ));
    await t.tap(find.text('go'));
    await _settle(t);
    expect(find.text(_t('eoRideStartFailed')), findsOneWidget);
    expect(find.text(_t('v2UxRrFailW')), findsNothing);
  });

  group('G-1046 / G-1045 recording notes', () {
    testWidgets('safety pause: the decision question in the dock bar and on the Moje row', (t) async {
      await pumpV2(t, _rec(kRecHome, TrasyRecordDockV2(onOpenRecorder: () {})), size: const Size(412, 400));
      await _settle(t);
      expect(find.text(_t('gdaRecDecide')), findsOneWidget);
      await pumpV2(
          t,
          _rec(kRecHome, MojeRecordRowV2(rec: kRecHome, hintOpen: false, onHint: () {}, onEnabled: (_) {}, onOpen: () {})),
          size: const Size(412, 600));
      await _settle(t);
      expect(find.byKey(const ValueKey('moje-rec-decision')), findsOneWidget);
    });

    testWidgets('voluntary pause: no decision question', (t) async {
      await pumpV2(
          t,
          _rec(kRecManualPaused,
              MojeRecordRowV2(rec: kRecManualPaused, hintOpen: false, onHint: () {}, onEnabled: (_) {}, onOpen: () {})),
          size: const Size(412, 600));
      await _settle(t);
      expect(find.byKey(const ValueKey('moje-rec-decision')), findsNothing);
      expect(find.byKey(const ValueKey('moje-rec-rental-ends')), findsNothing);
    });

    testWidgets('rental recording: "ends by itself when you return the bike"', (t) async {
      await pumpV2(
          t,
          _rec(kRecRidingRental,
              MojeRecordRowV2(rec: kRecRidingRental, hintOpen: false, onHint: () {}, onEnabled: (_) {}, onOpen: () {})),
          size: const Size(412, 600));
      await _settle(t);
      expect(find.byKey(const ValueKey('moje-rec-rental-ends')), findsOneWidget);
      expect(find.text(_t('v2RpRentalEnds')), findsOneWidget);
    });
  });

  testWidgets('G-1043 double tap on the dock pause disc pauses once', (t) async {
    late _SlowPauseRecorder rec;
    await pumpV2(
        t,
        _rec(kRecRiding, TrasyRecordDockV2(onOpenRecorder: () {}),
            make: (ref) => rec = _SlowPauseRecorder(ref, kRecRiding)),
        size: const Size(412, 400));
    await _settle(t);
    await t.tap(find.byType(RecPauseDiscV2));
    await t.pump();
    await t.tap(find.byType(RecPauseDiscV2));
    await t.pump();
    expect(rec.calls.where((c) => c == 'pause' || c == 'resume'), ['pause']);
    rec.gate.complete();
    await _settle(t);
  });

  group('G-1076 / G-1078 trip detail', () {
    testWidgets('while a split runs, delete is locked', (t) async {
      final gate = Completer<void>();
      final calls = <int>[];
      final log = TripSeamLog();
      await pumpV2(t, _slowSet(gate, calls, const TripDetailScreenV2(leaderId: 't1')),
          size: const Size(412, 3000), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      await t.ensureVisible(find.text('Rozdělit cestu').first);
      await t.tap(find.text('Rozdělit cestu').first);
      await _settle(t);
      await t.tap(find.text('Rozdělit cestu').last);
      await t.pump();
      expect(calls, hasLength(1));
      await t.tap(find.bySemanticsLabel('Smazat cestu'), warnIfMissed: false);
      await _settle(t);
      expect(find.text('Co chceš smazat?'), findsNothing);
      expect(log.other, isEmpty);
      gate.complete();
      await _settle(t);
    });

    testWidgets('a failed split also shows a toast (the banner may be off screen)', (t) async {
      final log = TripSeamLog()..kind = RideTripSetKind.missing;
      await pumpV2(t, const TripDetailScreenV2(leaderId: 't1'),
          size: const Size(412, 3000), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      await t.ensureVisible(find.text('Rozdělit cestu').first);
      await t.tap(find.text('Rozdělit cestu').first);
      await _settle(t);
      await t.tap(find.text('Rozdělit cestu').last);
      await _settle(t);
      expect(find.descendant(of: find.byType(SnackBar), matching: find.text(_t('v2RpTripUnavailable'))), findsOneWidget);
    });
  });

  group('G-1038 live badge from the local recorder', () {
    const rec = RideRecorderState(recording: true, manual: true, rideId: 's1');
    testWidgets('ride card', (t) async {
      await pumpV2(t, RideCardV2(ride: kSolo, onTap: () {}), overrides: tripOverrides(recorder: rec));
      await _settle(t);
      expect(find.byType(RideLiveBadgeV2), findsOneWidget);
    });

    testWidgets('trip card', (t) async {
      final trip = tripOf(kTripRides(), 't1');
      await pumpV2(t, RideTripCardV2(trip: trip, onTap: () {}),
          overrides: tripOverrides(recorder: const RideRecorderState(recording: true, manual: true, rideId: 't2')));
      await _settle(t);
      expect(find.byType(RideLiveBadgeV2), findsOneWidget);
    });

    testWidgets('no recording: no badge', (t) async {
      await pumpV2(t, RideCardV2(ride: kSolo, onTap: () {}), overrides: tripOverrides());
      await _settle(t);
      expect(find.byType(RideLiveBadgeV2), findsNothing);
    });
  });

  testWidgets('G-1065 "remove from trip": one call for a double tap', (t) async {
    final gate = Completer<void>();
    final calls = <int>[];
    await pumpV2(t, _slowSet(gate, calls, SingleChildScrollView(child: RideTripRowV2(ride: kTrip1))),
        size: const Size(412, 800), overrides: tripOverrides());
    await _settle(t);
    await t.tap(find.text(_t('v2RpTripRemove')));
    await t.pump();
    await t.tap(find.text(_t('v2RpTripRemove')), warnIfMissed: false);
    await t.pump();
    expect(calls, hasLength(1));
    gate.complete();
    await _settle(t);
  });

  testWidgets('G-1087 merge into a named trip pre-fills its name', (t) async {
    await pumpV2(t, const RideMergeScreenV2(preselectRideId: 's1'),
        size: const Size(412, 1600), overrides: tripOverrides(), scaffold: false);
    await _settle(t);
    await t.tap(find.text('Alpy 2026 — Grossglockner a Dolomity'));
    await _settle(t);
    await t.tap(find.text('SLOUČIT (2)'));
    await _settle(t);
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Alpy 2026 — Grossglockner a Dolomity');
  });
}
