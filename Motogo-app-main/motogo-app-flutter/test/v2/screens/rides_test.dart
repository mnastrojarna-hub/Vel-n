// Jízdy v2 screen matrix (PLAN §5.3): Moje zážitky (sub-screens, states),
// ride detail, recorder, stop editor × 8 languages × 2 phone sizes — no
// overflow / exception; reduced-motion passes settle; the views call the
// callbacks they were given (the old State's actions). Review shots go to
// MG_SHOTS_DIR.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_cards_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_card_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_detail_view_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_dialogs_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_share_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_rides.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'rides_cases.dart';

Future<void> _settleClean(WidgetTester tester) async {
  await expectCleanFrames(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

void _matrix(String screen, Map<String, RideCase> cases, {bool scaffold = false}) {
  for (final entry in cases.entries) {
    for (final lang in kV2Langs) {
      for (final size in kV2Sizes) {
        final w = size.width.toInt(), h = size.height.toInt();
        testWidgets('$screen ${entry.key} $lang ${w}x$h', (tester) async {
          final key = GlobalKey();
          await pumpV2(tester, entry.value.$1(),
              lang: lang, size: size, overrides: entry.value.$2(), scaffold: scaffold, boundaryKey: key);
          await _settleClean(tester);
          await maybeShot(tester, key, 'rides__${screen}__${entry.key}__${lang}__${w}x$h');
          await ridesEnd(tester);
        });
      }
    }
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRidesStrings();
    ridesMockPathProvider();
    // Map tiles / photos answer 200 with a tiny PNG (the default test client
    // answers 400 and flutter_map would report every tile).
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  _matrix('moje', mojeCases());
  _matrix('detail', detailCases());
  _matrix('recorder', recorderCases());
  _matrix('point', pointCases(), scaffold: true);

  // Reduced motion: every loop off → the frame settles.
  for (final e in {
    ...mojeCases().map((k, v) => MapEntry('moje-$k', v)),
    ...detailCases().map((k, v) => MapEntry('detail-$k', v)),
    ...recorderCases().map((k, v) => MapEntry('recorder-$k', v)),
  }.entries) {
    testWidgets('reduced motion ${e.key}', (tester) async {
      await pumpV2(tester, e.value.$1(), overrides: e.value.$2(), reducedMotion: true, scaffold: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
      await ridesEnd(tester);
    });
  }

  // Whole pages in one tall frame (review shots).
  for (final e in {
    'moje-rides': mojeCases()['rides']!,
    'moje-history': mojeCases()['history']!,
    'detail-motogo': detailCases()['motogo']!,
    'detail-gap': detailCases()['gap']!,
  }.entries) {
    for (final lang in ['cs', 'de', 'fr', 'uk']) {
      testWidgets('full ${e.key} $lang', (tester) async {
        final key = GlobalKey();
        await pumpV2(tester, e.value.$1(),
            lang: lang, size: const Size(390, 2200), overrides: e.value.$2(), scaffold: false, boundaryKey: key);
        await _settleClean(tester);
        await maybeShot(tester, key, 'rides__full__${e.key}__${lang}__390x2200');
        await ridesEnd(tester);
      });
    }
  }

  group('Moje actions', () {
    testWidgets('sub-chips switch Jízdy ↔ Uložené trasy and keep the old tab index', (tester) async {
      final taps = RideTaps();
      await pumpV2(tester, mojeView(taps: taps), size: const Size(412, 2000), overrides: ridesOverrides(), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(RideCardV2), findsNWidgets(kRides.length));
      await tester.tap(find.byType(MgFilterChip).at(1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SavedRouteCardV2), findsNWidgets(kSavedRoutes.length));
      expect(taps.log, contains('tab:0'));
      await tester.ensureVisible(find.byType(MgFilterChip).at(3));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(MgFilterChip).at(3));
      expect(taps.log.last, 'tab:2');
      await tester.pump(const Duration(seconds: 1));
      await ridesEnd(tester);
    });

    testWidgets('saved route card: open / navigate / delete', (tester) async {
      final taps = RideTaps();
      await pumpV2(tester, mojeView(taps: taps), size: const Size(412, 2000), overrides: ridesOverrides(), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(MgFilterChip).at(1));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Navigovat').first);
      await tester.tap(find.byType(MojeDeleteButton).first);
      await tester.tap(find.text('Upravit').first);
      expect(taps.log, containsAll(['navSaved:s1', 'delSaved:s1', 'openSaved:s1']));
      await tester.pump(const Duration(seconds: 1));
      await ridesEnd(tester);
    });

    testWidgets('history: continue / delete pass the active flag', (tester) async {
      final taps = RideTaps();
      await pumpV2(tester, mojeView(tab: 2, active: kHistoryActive, taps: taps),
          size: const Size(412, 2000), overrides: ridesOverrides(), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(HistoryCardV2).first);
      await tester.tap(find.text('Pokračovat v trase'));
      await tester.tap(find.byType(MojeDeleteButton).last);
      expect(taps.log, containsAll(['openHist:1', 'go:1:true', 'delHist:2:false']));
      await tester.pump(const Duration(seconds: 1));
      await ridesEnd(tester);
    });

    testWidgets('logged out: login + history from the lock card', (tester) async {
      final taps = RideTaps();
      await pumpV2(tester, mojeView(loggedIn: false, taps: taps),
          size: const Size(412, 2000), overrides: ridesOverrides(loyalty: null), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('PŘIHLÁSIT SE').first);
      await tester.tap(find.text('Otevřít historii navigace'));
      expect(taps.log, containsAll(['login', 'tab:2']));
      await tester.pump(const Duration(seconds: 1));
      await ridesEnd(tester);
    });

    testWidgets('auto-record switch calls the old setter', (tester) async {
      final taps = RideTaps();
      await pumpV2(tester, mojeView(taps: taps), size: const Size(412, 2000), overrides: ridesOverrides(), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(Switch).first);
      expect(taps.log, contains('auto:false'));
      await tester.pump(const Duration(seconds: 1));
      await ridesEnd(tester);
    });
  });

  group('Ride detail actions', () {
    testWidgets('header + sharing + stops call the State callbacks', (tester) async {
      final taps = RideTaps();
      await pumpV2(tester, rideDetail(kRideMg, taps: taps),
          size: const Size(412, 2400), overrides: ridesOverrides(), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.bySemanticsLabel('Sdílet jízdu'));
      await tester.tap(find.bySemanticsLabel('Smazat jízdu'));
      await tester.tap(find.text('Pálava za soumraku'));
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Rozhledna Děvičky'));
      expect(taps.log, containsAll(['share', 'delete', 'edit', 'visibility:false', 'editPoint:p1']));
      await tester.pump(const Duration(seconds: 1));
      await ridesEnd(tester);
    });

    testWidgets('missing ride: the action goes back', (tester) async {
      var back = 0;
      await pumpV2(tester, RideMissingV2(onBack: () => back++), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Zpět na Moje zážitky'));
      expect(back, 1);
    });

    testWidgets('delete dialog returns the old pop values', (tester) async {
      bool? result;
      await pumpV2(tester, Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await showDialog<bool>(
              context: c, builder: (dc) => rideConfirmDeleteV2(dc, title: 'Smazat jízdu?', body: 'Pálava')),
          child: const Text('open'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smazat'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('edit dialog keeps the controllers and pops true on save', (tester) async {
      bool? result;
      final name = TextEditingController(text: 'Pálava');
      final desc = TextEditingController();
      await pumpV2(tester, Builder(
        builder: (c) => TextButton(
          onPressed: () async =>
              result = await showDialog<bool>(context: c, builder: (dc) => rideEditDialogV2(dc, name, desc)),
          child: const Text('open'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Nový název');
      await tester.tap(find.text('Uložit'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(name.text, 'Nový název');
    });

    testWidgets('share sheet lists every target', (tester) async {
      await pumpV2(tester, Builder(
        builder: (c) => TextButton(
          onPressed: () => showRideShareSheetV2(c, text: 'Pálava', link: 'https://mapy.com/x'),
          child: const Text('open'),
        ),
      ), overrides: ridesOverrides());
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 800));
      for (final l in ['WhatsApp', 'Facebook', 'X', 'Telegram', 'E-mail', 'Kopírovat']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Recorder', () {
    testWidgets('auto-record switch → setEnabled (existing action)', (tester) async {
      late FakeRidesRecorder rec;
      await pumpV2(tester, const RecorderScreenV2(),
          overrides: [
            rideRecorderProvider.overrideWith((ref) => rec = FakeRidesRecorder(ref, kRecIdle)),
            ...ridesOverrides().skip(1),
          ],
          scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(rec.calls, ['setEnabled:false']);
    });

    testWidgets('manual recording: stop asks first (no stop without confirm)', (tester) async {
      await pumpV2(tester, const RecorderScreenV2(), overrides: ridesOverrides(recorder: kRecManual), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(RecorderStopButtonV2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ukončit záznam?'), findsOneWidget);
      await tester.tap(find.text('Pokračovat v jízdě'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ukončit záznam?'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('rental recording has no stop button', (tester) async {
      await pumpV2(tester, const RecorderScreenV2(), overrides: ridesOverrides(recorder: kRecAuto), scaffold: false);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(RecorderStopButtonV2), findsNothing);
    });

    testWidgets('openRideRecorderV2 pushes the screen and back pops it', (tester) async {
      await pumpV2(tester, Builder(
        builder: (c) => TextButton(onPressed: () => openRideRecorderV2(c), child: const Text('open')),
      ), overrides: ridesOverrides());
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(RecorderScreenV2), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Zpět'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(RecorderScreenV2), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
