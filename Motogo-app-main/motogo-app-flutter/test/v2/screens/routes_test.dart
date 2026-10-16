// Trasy v2 screen matrix (PLAN §5.3): hub header × segments, Místa
// (location prompt, list, selection, loading, error, empty, picker), Trasy
// list (list, empty, filter-empty, error, loading), record dock (idle,
// selection, recording manual / automatic, weak GPS) × 8 languages × 2
// phone sizes — no overflow / exception. Reduced-motion passes settle.
// Review shots go to MG_SHOTS_DIR.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'routes_cases.dart';
import 'routes_cases2.dart';

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
          await rtEnd(tester);
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
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  _matrix('places', placesCases());
  _matrix('routes', routesListCases());
  _matrix('detail', detailCases());
  _matrix('builder', builderCases());
  _matrix('form', formCases());
  _matrix('map', mapCases());
  _matrix('pieces', pieceCases());

  // Reduced motion: every loop off → the frame settles (loading states
  // keep their progress indicator spinning by design → only clean frames).
  final all = <String, RtCase>{
    for (final e in placesCases().entries) 'places-${e.key}': e.value,
    for (final e in routesListCases().entries) 'routes-${e.key}': e.value,
    for (final e in detailCases().entries) 'detail-${e.key}': e.value,
    for (final e in builderCases().entries) 'builder-${e.key}': e.value,
    for (final e in formCases().entries) 'form-${e.key}': e.value,
    for (final e in pieceCases().entries) 'pieces-${e.key}': e.value,
  };
  for (final e in all.entries) {
    testWidgets('reduced motion ${e.key}', (tester) async {
      await pumpV2(tester, e.value.$1(), overrides: e.value.$2(), reducedMotion: true);
      if (e.key.endsWith('loading')) {
        await expectCleanFrames(tester);
      } else {
        await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      }
      expect(tester.takeException(), isNull);
      await rtEnd(tester);
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
        await rtEnd(tester);
      });
    }
  }

  testWidgets('dock: manual recording shows "Ukončit"', (tester) async {
    await pumpV2(tester, placesCases()['list']!.$1(),
        overrides: routesOverrides(recorder: const RideRecorderState(recording: true, manual: true, rideId: 'x')));
    await _settleClean(tester);
    expect(find.text('Ukončit'), findsOneWidget);
    expect(find.text('ZAZNAMENAT JÍZDU'), findsNothing);
    await rtEnd(tester);
  });
  testWidgets('dock: automatic (rental) recording has no stop', (tester) async {
    await pumpV2(tester, placesCases()['list']!.$1(),
        overrides: routesOverrides(recorder: const RideRecorderState(recording: true, rideId: 'x', bookingId: 'b')));
    await _settleClean(tester);
    expect(find.text('Ukončit'), findsNothing);
    expect(find.text('Jízda z výpůjčky'), findsOneWidget);
    await rtEnd(tester);
  });

  // Behaviour kept: the card disc toggles the SAME shared selection, the
  // dock switches to "Vlastní vyjížďka (n)" and ✕ clears it again.
  testWidgets('places: toggle disc → selection dock → clear', (tester) async {
    final sem = tester.ensureSemantics();
    await pumpV2(tester, placesCases()['list']!.$1(), size: const Size(390, 1400), overrides: routesOverrides());
    await _settleClean(tester);
    final add = find.bySemanticsLabel(RegExp('^Přidat do vyjížďky: '));
    expect(add, findsWidgets);
    await tester.tap(add.first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('VLASTNÍ VYJÍŽĎKA (1)'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Zrušit výběr'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('ZAZNAMENAT JÍZDU'), findsOneWidget);
    sem.dispose();
    await rtEnd(tester);
  });

  // The "+" opens the existing add menu (v2 rows, + "Vytvořit novou trasu").
  for (final lang in kV2Langs) {
    testWidgets('add menu $lang', (tester) async {
      final sem = tester.ensureSemantics();
      final key = GlobalKey();
      await pumpV2(tester, placesCases()['list']!.$1(), lang: lang, overrides: routesOverrides(), boundaryKey: key);
      await _settleClean(tester);
      await tester.tap(find.bySemanticsLabel(translations[lang]!['v2RtAddA11y']!));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
      expect(find.text(translations[lang]!['v2RtCreateRoute']!), findsOneWidget);
      expect(find.text(translations[lang]!['rideManualStart']!), findsOneWidget);
      sem.dispose();
      await rtEnd(tester);
    });
  }

  // Flag OFF → the old screens render exactly as before (no v2 widgets).
  for (final e in {
    'places': placesCases()['list']!,
    'routes': routesListCases()['list']!,
    'detail': detailCases()['ok']!,
    'builder': builderCases()['route']!,
  }.entries) {
    testWidgets('flag off ${e.key}', (tester) async {
      await pumpV2(tester, e.value.$1(), overrides: e.value.$2(), v2: false);
      await _settleClean(tester);
      expect(find.text('ZAZNAMENAT JÍZDU'), findsNothing);
      expect(find.text('ZVOLIT TRASU – NAVIGOVAT'.toUpperCase()), e.key == 'detail' ? findsOneWidget : findsNothing);
      await rtEnd(tester);
    });
  }
}
