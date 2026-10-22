// TEMP (deleted after review): PNG shots of the v2 pause / trips states.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'rides_cases.dart';
import 'rides_pause_cases.dart';
import 'rides_pause_parts.dart';

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
  final cases = <String, (Widget Function(), dynamic, double, bool)>{
    for (final e in pauseRecorderCases().entries) 'rec-${e.key}': (e.value.$1, e.value.$2, 780, false),
    for (final e in pausePageCases().entries) 'page-${e.key}': (e.value.$1, e.value.$2, 1800, false),
    'part-docks': (docksPart, tripOverrides, 1700, true),
    'part-home': (homeRowsPart, tripOverrides, 1300, true),
    'part-moje': (mojeRowsPart, tripOverrides, 1500, true),
    'part-nav': (navAndSheetPart, tripOverrides, 3200, true),
    'part-cards': (cardsPart, tripOverrides, 2600, true),
  };
  for (final e in cases.entries) {
    for (final lang in ['cs', 'de']) {
      testWidgets('shot ${e.key} $lang', (t) async {
        final key = GlobalKey();
        final (build, ov, h, part) = e.value;
        await pumpV2(t, part ? SingleChildScrollView(child: build()) : build(),
            lang: lang, size: Size(360, h), overrides: (ov as Function)() as dynamic, scaffold: part, boundaryKey: key, reducedMotion: true);
        await t.pump(const Duration(milliseconds: 800));
        await t.pump(const Duration(milliseconds: 800));
        await maybeShot(t, key, '${e.key}__$lang');
        await ridesEnd(t);
      });
    }
  }
}
