// Trasy v2 screen matrix (PLAN §5.3): hub header × segments, Místa
// (location prompt, list, selection, loading, error, empty, picker), Trasy
// list (list, empty, filter-empty, error, loading), record dock (idle,
// selection, recording manual / automatic, weak GPS) × 8 languages × 2
// phone sizes — no overflow / exception. Reduced-motion passes settle.
// Review shots go to MG_SHOTS_DIR.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/v2_harness.dart';
import 'routes_cases.dart';

typedef RtCase = (Widget Function(), List<Override> Function());

Future<void> _settleClean(WidgetTester tester) async {
  await expectCleanFrames(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

void _matrix(String screen, Map<String, RtCase> cases, {List<String> langs = kV2Langs}) {
  for (final entry in cases.entries) {
    for (final lang in langs) {
      for (final size in kV2Sizes) {
        final w = size.width.toInt(), h = size.height.toInt();
        testWidgets('$screen ${entry.key} $lang ${w}x$h', (tester) async {
          final key = GlobalKey();
          await pumpV2(tester, entry.value.$1(), lang: lang, size: size, overrides: entry.value.$2(), boundaryKey: key);
          await _settleClean(tester);
          await maybeShot(tester, key, 'routes__${screen}__${entry.key}__${lang}__${w}x$h');
        });
      }
    }
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRoutesStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  _matrix('places', placesCases());
  _matrix('routes', routesListCases());

  // Reduced motion: every loop off → the frame settles.
  for (final e in {...placesCases(), ...routesListCases()}.entries) {
    testWidgets('reduced motion ${e.key}', (tester) async {
      await pumpV2(tester, e.value.$1(), overrides: e.value.$2(), reducedMotion: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }

  // Whole pages in one tall frame (review shots).
  for (final e in {
    'places': placesCases()['list']!,
    'places-sel': placesCases()['selection']!,
    'routes': routesListCases()['list']!,
  }.entries) {
    for (final lang in ['cs', 'de', 'fr']) {
      testWidgets('full ${e.key} $lang', (tester) async {
        final key = GlobalKey();
        await pumpV2(tester, e.value.$1(), lang: lang, size: const Size(390, 2400), overrides: e.value.$2(), boundaryKey: key);
        await _settleClean(tester);
        await maybeShot(tester, key, 'routes__full__${e.key}__${lang}__390x2400');
      });
    }
  }

  testWidgets('dock: recording state keeps a stop button (manual) and none (automatic)', (tester) async {
    await pumpV2(tester, placesCases()['list']!.$1(),
        overrides: routesOverrides(recorder: const RideRecorderState(recording: true, manual: true, rideId: 'x')));
    await _settleClean(tester);
    expect(find.text('Ukončit'), findsOneWidget);
    await pumpV2(tester, placesCases()['list']!.$1(),
        overrides: routesOverrides(recorder: const RideRecorderState(recording: true, rideId: 'x', bookingId: 'b')));
    await _settleClean(tester);
    expect(find.text('Ukončit'), findsNothing);
  });
}
