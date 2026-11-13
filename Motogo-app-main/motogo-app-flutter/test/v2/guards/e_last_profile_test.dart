// Last fixes "e_last" (2026-11-13), K4-02, new look only: opening the
// personal form on Profil keeps the page where the customer is (the
// pull-to-refresh wrapper that switches off while the form is open no longer
// remounts the scroll view), and the booking-fix path from the booking form
// still lands on the group with the missing field when the form is built
// late (reduced motion / slow first frame).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_catalog.dart' show kBmw;
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/profile_harness.dart';
import '../support/v2_harness.dart';

String _cs(String k) => translations['cs']![k]!;

Future<void> _frames(WidgetTester t, [int n = 40]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerProfileStrings();
    mockPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  for (final reduced in [false, true]) {
    testWidgets('K4-02 "Upravit" further down keeps the card in view (reduced=$reduced)', (t) async {
      await pumpV2(t, const PfHubHarness(), overrides: profileOverrides(), size: const Size(360, 780), reducedMotion: reduced);
      await _frames(t);
      final edit = find.text(_cs('edit'));
      final y0 = t.getTopLeft(find.text(_cs('personalInfo'))).dy;
      expect(y0, greaterThan(420), reason: 'the card starts further down the page');
      await t.drag(find.byType(Scrollable).first, Offset(0, -(y0 - 300)));
      await _frames(t, 10);
      final before = t.getTopLeft(find.text(_cs('personalInfo'))).dy;
      expect(before, lessThan(420), reason: 'scrolled down to the card');
      await t.tap(edit);
      await _frames(t);
      expect(find.text(_cs('saveChanges')), findsOneWidget, reason: 'form opened');
      final after = t.getTopLeft(find.text(_cs('personalInfo'))).dy;
      expect((after - before).abs(), lessThan(2), reason: 'the page did not jump back to the top');
      // Closing it (pull-to-refresh comes back) keeps the place too.
      await t.tap(find.text(_cs('close')));
      await _frames(t);
      expect((t.getTopLeft(find.text(_cs('personalInfo'))).dy - before).abs(), lessThan(2));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('K4-02 booking fix with reduced motion lands on Adresa, not the top', (t) async {
    final profile = {...kProfileFull, 'street': '', 'zip': null};
    await pumpV2(t, PfHubHarness(onBack: () {}, bookingFix: true),
        overrides: <Override>[...profileOverrides(profile: profile), bookingMotoProvider.overrideWith((ref) => kBmw)],
        size: const Size(360, 780), reducedMotion: true);
    await _frames(t);
    expect(find.text(_cs('saveChanges')), findsOneWidget, reason: 'form opened');
    final y = t.getTopLeft(find.text(_cs('v2PfGroupAddress').toUpperCase())).dy;
    expect(y, inInclusiveRange(60, 400), reason: 'Adresa brought under the pinned back');
    expect(t.takeException(), isNull);
  });
}
