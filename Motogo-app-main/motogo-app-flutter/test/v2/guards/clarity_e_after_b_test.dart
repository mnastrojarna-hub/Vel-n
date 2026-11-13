// Clarity, part "after-b" (2026-11-13): when the server does not know trips
// yet, the v2 "Sloučit jízdy" screen says so in a heading up front and
// locks the selection and the button, like the old look's amber note
// (G-1084). Before, the customer could pick rides and name the trip and
// only then saw that merging is unavailable.
import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_merge_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/rides_cases.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _t(String key, [String lang = 'cs']) => translations[lang]?[key] ?? key;

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// A second ride on the old server (no trips), on another day than kLegacy.
final _legacy2 = UserRide(
  id: 'l2',
  name: 'Druhá stará jízda',
  track: kLegacy.track,
  segments: kLegacy.segments,
  startedAt: DateTime(2026, 7, 9, 10),
  endedAt: DateTime(2026, 7, 9, 13),
  distanceKm: 80,
  durationMin: 180,
  movingSec: 9000,
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

  group('G-1084 merge screen without trip support', () {
    for (final (lang, w) in [('cs', 360.0), ('de', 320.0)]) {
      testWidgets('heading banner, locked rows and button ($lang $w)', (t) async {
        final shot = GlobalKey();
        await pumpV2(t, const RideMergeScreenV2(preselectRideId: 'l1'),
            lang: lang, size: Size(w, 780), overrides: tripOverrides(rides: [kLegacy, _legacy2]), scaffold: false, boundaryKey: shot);
        await _settle(t);
        await maybeShot(t, shot, 'merge_unavailable__${lang}__${w.toInt()}');
        expect(t.takeException(), isNull);
        final banner = find.byKey(const ValueKey('merge-unavailable'));
        expect(banner, findsOneWidget);
        final b = t.widget<MgStateBanner>(banner);
        expect(b.title, _t('eabMergeOffTitle', lang));
        expect(b.text, _t('v2RpTripUnavailable', lang));
        // The pre-selected ride is not drawn as chosen (old look: same) and
        // the button is locked.
        expect(t.getSemantics(find.bySemanticsLabel(RegExp('Stará jízda \\(starý'))).flagsCollection.isChecked, CheckedState.isFalse);
        final cta = t.widget<MgCta>(find.byType(MgCta));
        expect(cta.enabled, isFalse);
        expect(cta.onTap, isNull);
        // Tapping a row selects nothing (no count, no name dialog).
        await t.tap(find.text('Druhá stará jízda'), warnIfMissed: false);
        await _settle(t);
        expect(t.widget<MgCta>(find.byType(MgCta)).onTap, isNull);
        expect(find.byType(TextField), findsNothing);
      });
    }

    testWidgets('a server with trips: no banner, merging works as before', (t) async {
      await pumpV2(t, const RideMergeScreenV2(preselectRideId: 's1'),
          size: const Size(412, 1600), overrides: tripOverrides(), scaffold: false);
      await _settle(t);
      expect(find.byKey(const ValueKey('merge-unavailable')), findsNothing);
      await t.tap(find.text('Alpy 2026 — Grossglockner a Dolomity'));
      await _settle(t);
      expect(t.widget<MgCta>(find.byType(MgCta)).onTap, isNotNull);
    });
  });

  test('new key exists in all 8 languages', () {
    for (final l in ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk']) {
      expect(translations[l]?['eabMergeOffTitle'], isNotNull, reason: l);
    }
  });
}
