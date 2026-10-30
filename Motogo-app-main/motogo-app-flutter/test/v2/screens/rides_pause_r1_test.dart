// v2 ride recording — fix:ui-v2:r1: the toast after ❚❚ / ▶ floats above
// the dock (recorder screen and the Trasy record dock), auto-pause has its
// own words and CTA (STOJÍŠ · AUTO-PAUZA, VYPNOUT GPS), the GPS chip says
// "zaznamenává" only while riding, GPS lost never says "Nahrávám", the nav
// chip tells REC / PŘIPRAVENO / AUTO-PAUZA / PAUZA / BEZ GPS apart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_chrome_metrics.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/v2/home_record_row_v2.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/v2/record_dock_v2.dart';
import 'package:motogo_app/features/routes/v2/route_nav_skin_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/rec_widgets_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_phase_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'rides_cases.dart' show ridesMockPathProvider;

const _cs = AppTranslations('cs');

FakePauseRecorder _rec(WidgetTester t) {
  final el = t.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(el).read(rideRecorderProvider.notifier) as FakePauseRecorder;
}

/// The visible toast (its Material, without the floating margin).
Rect _toastRect(WidgetTester t) =>
    t.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
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

  test('auto-pause ≠ manual pause, GPS lost never says Nahrávám', () {
    final auto = RecPhaseV2.of(_cs, kRecAutoPaused);
    expect([auto.status, auto.chip, auto.auto], ['STOJÍŠ · AUTO-PAUZA', 'Auto-pauza', isTrue]);
    expect(RecPhaseV2.of(_cs, kRecRentalWalk).auto, isTrue);
    final manual = RecPhaseV2.of(_cs, kRecManualPaused);
    expect([manual.status, manual.chip, manual.auto], ['POZASTAVENO', 'Pozastaveno', isFalse]);
    expect(RecPhaseV2.of(_cs, kRecArmed).auto, isFalse);
    expect(RecPhaseV2.of(_cs, kRecHome).auto, isFalse);
    final lost = RecPhaseV2.of(_cs, kRecGpsLost);
    expect([lost.status, lost.chip], ['POLOHA NEDOSTUPNÁ', 'Bez GPS']);
    expect(lost.title, contains('Záznam stojí'));
    String nav(RideRecorderState s) => recNavLabelV2(_cs, RecPhaseV2.of(_cs, s));
    expect([kRecRiding, kRecArmed, kRecAutoPaused, kRecManualPaused, kRecHome, kRecGpsLost].map(nav),
        ['REC', 'PŘIPRAVENO', 'AUTO-PAUZA', 'PAUZA', 'PAUZA', 'BEZ GPS']);
    expect(recGpsChipKeyV2(kRecRiding), 'v2RideRecGpsOk');
    expect(recGpsChipKeyV2(kRecArmed), 'v2RpGpsWaiting');
    expect(recGpsChipKeyV2(kRecAutoPaused), 'v2RpGpsWaiting');
    expect(recGpsChipKeyV2(kRecManualPaused), 'v2RpGpsOff');
    expect(recGpsChipKeyV2(kRecGpsLost), 'v2RpChipNoGps');
    expect(recHintV2(_cs, kRecAutoPaused), allOf(contains('nemusíš nic mačkat'), contains('Vypnout GPS')));
    expect(recHintV2(_cs, kRecRiding), _cs.tr('v2RpHintAuto'));
    for (final l in kV2Langs) {
      final tr = AppTranslations(l);
      expect(RecPhaseV2.of(tr, kRecGpsLost).status, isNot(tr.tr('rideRecording').toUpperCase()), reason: l);
      expect(RecPhaseV2.of(tr, kRecAutoPaused).status, isNot(RecPhaseV2.of(tr, kRecManualPaused).status), reason: l);
      expect(tr.tr('v2RpHintAutoNow'), contains(tr.tr('v2RpGpsOffBtn')), reason: l);
    }
  });

  testWidgets('recorder: the toast floats ABOVE the dock (never over POKRAČOVAT / UKONČIT)', (t) async {
    for (final (lang, w) in [('cs', 320.0), ('de', 360.0), ('uk', 412.0)]) {
      await pumpV2(t, const RecorderScreenV2(),
          lang: lang, size: Size(w, 780), overrides: tripOverrides(recorder: kRecRiding), scaffold: false);
      await _settle(t);
      await t.tap(find.byType(RecorderPauseButtonV2));
      await _settle(t);
      expect(find.byType(SnackBar), findsOneWidget, reason: lang);
      final toast = _toastRect(t);
      final dock = t.getRect(find.byType(MgDock));
      expect(toast.bottom, lessThanOrEqualTo(dock.top + 0.5), reason: '$lang $w: $toast vs $dock');
      // ▶ POKRAČOVAT is tappable at once (the toast does not cover it).
      await t.tap(find.byType(RecorderPauseButtonV2));
      await _settle(t);
      expect(_rec(t).calls, ['pause', 'resume'], reason: lang);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('recorder: auto-pause says so, CTA VYPNOUT GPS, GPS chip waits', (t) async {
    await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecAutoPaused), scaffold: false);
    await _settle(t);
    expect(find.text('STOJÍŠ · AUTO-PAUZA'), findsOneWidget);
    expect(find.text('POZASTAVENO'), findsNothing);
    expect(find.text('VYPNOUT GPS'), findsOneWidget);
    expect(find.text('POZASTAVIT'), findsNothing);
    expect(find.text('GPS zapnuté — čeká na rozjezd'), findsOneWidget);
    expect(find.text('Poloha se zaznamenává'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Vypnout GPS a šetřit baterii')), findsOneWidget);
    await t.tap(find.byType(RecorderPauseButtonV2));
    await _settle(t);
    expect(_rec(t).calls, ['pause']);
    await t.pumpWidget(const SizedBox());
    await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecArmed), scaffold: false);
    await _settle(t);
    expect(find.text('POZASTAVIT'), findsOneWidget);
    expect(find.text('GPS zapnuté — čeká na rozjezd'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecRiding), scaffold: false);
    await _settle(t);
    expect(find.text('Poloha se zaznamenává'), findsOneWidget);
  });

  testWidgets('recorder: GPS lost — POLOHA NEDOSTUPNÁ, never NAHRÁVÁM', (t) async {
    await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecGpsLost), scaffold: false);
    await _settle(t);
    expect(find.text('POLOHA NEDOSTUPNÁ'), findsOneWidget);
    expect(find.text('NAHRÁVÁM'), findsNothing);
    expect(find.text('Bez GPS'), findsOneWidget);
    expect(find.textContaining('Záznam jízdy stojí'), findsOneWidget);
  });

  testWidgets('Trasy dock in the page body: the toast floats above it', (t) async {
    final chrome = MgShellChrome();
    await pumpV2(
      t,
      MgChromeScope(
        chrome: chrome,
        navVisible: false,
        fabVisible: false,
        child: Column(children: [const Expanded(child: SizedBox.expand()), TrasyRecordDockV2(onOpenRecorder: () {})]),
      ),
      overrides: tripOverrides(recorder: kRecRiding),
    );
    await _settle(t);
    expect(chrome.dockHeight, greaterThan(40));
    await t.tap(find.byType(RecPauseDiscV2));
    await _settle(t);
    expect(_rec(t).calls, ['pause']);
    expect(_toastRect(t).bottom, lessThanOrEqualTo(t.getRect(find.byType(MgDock)).top + 0.5));
    await t.pumpWidget(const SizedBox());
    chrome.dispose();
  });

  testWidgets('Domů row without GPS says Bez GPS, never Nahrávám', (t) async {
    await pumpV2(t, const HomeRecordRowV2(), overrides: tripOverrides(recorder: kRecGpsLost), size: const Size(412, 915));
    await _settle(t);
    expect(find.text('Bez GPS'), findsOneWidget);
    expect(find.text('Nahrávám'), findsNothing);
  });

  testWidgets('nav chip: PAUZA / PŘIPRAVENO / BEZ GPS, REC only while riding', (t) async {
    for (final (s, label) in [(kRecManualPaused, 'PAUZA'), (kRecArmed, 'PŘIPRAVENO'), (kRecGpsLost, 'BEZ GPS')]) {
      await pumpV2(t, const NavRecChipV2(), overrides: tripOverrides(recorder: s));
      await _settle(t);
      expect(find.text(label), findsOneWidget, reason: label);
      expect(find.text('REC'), findsNothing, reason: label);
      await t.pumpWidget(const SizedBox());
    }
  });
}
