// v2 ride pause / auto-pause (SPEC §9.2, §16.2): phase mapping, pause /
// resume / stop from every surface (r1: the stop asks first, no spinner
// while the question is open), guards, rental rules, reduced motion and
// the i18n plurals / keys. Trips: rides_trips_test.dart. ui-v2 r1 (toast
// above the dock, auto-pause / no-GPS words, nav chip):
// rides_pause_r1_test.dart. Layout of every state × 8 languages × 3
// widths × 2 text scales: rides_pause_fit_test.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
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
import 'rides_cases.dart';

const _cs = AppTranslations('cs');

FakePauseRecorder _rec(WidgetTester t) {
  final el = t.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(el).read(rideRecorderProvider.notifier) as FakePauseRecorder;
}

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

  group('phase mapping', () {
    test('every phase has its status, chip and tone', () {
      expect(RecPhaseV2.of(_cs, kRecRiding).tone, RecToneV2.rec);
      expect(RecPhaseV2.of(_cs, kRecRiding).status, 'NAHRÁVÁM');
      expect(RecPhaseV2.of(_cs, kRecArmed).tone, RecToneV2.armed);
      expect(RecPhaseV2.of(_cs, kRecArmed).chip, 'Čeká na rozjezd');
      final auto = RecPhaseV2.of(_cs, kRecAutoPaused);
      expect(auto.tone, RecToneV2.paused);
      expect(auto.since, startsWith('od '));
      expect(auto.title, contains('sám pozastavil'));
      expect(RecPhaseV2.of(_cs, kRecManualPaused).title, contains('GPS je vypnuté'));
      expect(RecPhaseV2.of(_cs, kRecHome).status, 'ZPĚT NA STARTU');
      expect(RecPhaseV2.of(_cs, kRecLong).status, 'GPS VYPNUTÉ');
      expect(RecPhaseV2.of(_cs, kRecGpsLost).tone, RecToneV2.warn);
      expect(recHintV2(_cs, kRecHome), contains('kvůli baterii'));
    });

    test('since: time today, date + time on another day', () {
      final now = DateTime(2026, 10, 22, 21, 0);
      expect(recSinceV2(DateTime(2026, 10, 22, 20, 14), now: now), '20:14');
      expect(recSinceV2(DateTime(2026, 10, 21, 20, 14), now: now), '21. 10. 20:14');
    });

    test('live bits: Ø only after 5 min riding, day chip from the 2nd day', () {
      expect(recLiveBitsV2(_cs, const RideRecorderState(recording: true, liveKm: 3, liveMovingSec: 200)), hasLength(2));
      final bits = recLiveBitsV2(_cs, kRecRiding);
      expect(bits.first, '128 km');
      expect(bits, contains('2 h 3 min v sedle'));
      expect(bits, contains('Ø 63 km/h'));
      expect(bits, contains('2. den'));
      const short = RideRecorderState(recording: true, liveKm: 12.34, liveMovingSec: 900);
      expect(recLiveBitsV2(_cs, short).first, '12,3 km');
      expect(recLiveBitsV2(const AppTranslations('en'), short).first, '12.3 km');
    });

    test('plurals (cs / pl / uk)', () {
      expect([1, 2, 5, 21].map((n) => recDaysV2(_cs, n)), ['1 den', '2 dny', '5 dní', '21 dní']);
      expect([1, 3, 5].map((n) => recRidesV2(_cs, n)), ['1 jízda', '3 jízdy', '5 jízd']);
      const pl = AppTranslations('pl');
      expect([2, 5, 12, 22].map((n) => recDaysV2(pl, n)), ['2 dni', '5 dni', '12 dni', '22 dni']);
      expect([2, 5, 12, 22].map((n) => recRidesV2(pl, n)), ['2 przejazdy', '5 przejazdów', '12 przejazdów', '22 przejazdy']);
      const uk = AppTranslations('uk');
      expect([1, 3, 11, 21].map((n) => recDaysV2(uk, n)), ['1 день', '3 дні', '11 днів', '21 день']);
    });

    test('every v2Rp key used in the code exists in all 8 languages', () {
      final used = <String>{};
      for (final f in Directory('lib/features').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final m in RegExp(r"'(v2Rp[A-Za-z0-9]+)'").allMatches(f.readAsStringSync())) {
          used.add(m.group(1)!);
        }
      }
      used.addAll([for (final p in ['v2RpDays', 'v2RpRides']) for (final f in ['One', 'Few', 'Many']) '$p$f']);
      expect(used.length, greaterThan(80));
      for (final l in kV2Langs) {
        for (final k in used) {
          expect(translations[l]![k], isNotNull, reason: '$l $k');
        }
      }
    });
  });

  group('recorder screen', () {
    testWidgets('riding: ❚❚ POZASTAVIT pauses (toast, no stop)', (t) async {
      await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecRiding), scaffold: false);
      await _settle(t);
      await t.tap(find.byType(RecorderPauseButtonV2));
      await _settle(t);
      expect(_rec(t).calls, ['pause']);
      expect(find.textContaining('Záznam je pozastavený a GPS vypnuté'), findsOneWidget);
      expect(find.text('POKRAČOVAT'), findsOneWidget);
    });

    testWidgets('manual pause: ▶ POKRAČOVAT resumes; the stop question adds where it is saved', (t) async {
      await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecManualPaused), scaffold: false);
      await _settle(t);
      await t.tap(find.byType(RecorderStopButtonV2));
      await _settle(t);
      expect(find.text('Ukončit záznam?'), findsOneWidget);
      expect(find.textContaining('Pozastavená cesta se uloží'), findsOneWidget);
      await t.tap(find.text('Pokračovat v jízdě'));
      await _settle(t);
      await t.tap(find.byType(RecorderPauseButtonV2));
      await _settle(t);
      expect(_rec(t).calls, ['resume']);
    });

    testWidgets('r1: stop asks FIRST — no spinner while the question is open', (t) async {
      await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecRiding), scaffold: false, reducedMotion: true);
      await _settle(t);
      await t.tap(find.byType(RecorderStopButtonV2));
      await _settle(t);
      expect(find.text('Ukončit záznam?'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_rec(t).calls, isEmpty);
      await t.tap(find.text('Ukončit a uložit'));
      await _settle(t);
      expect(_rec(t).calls, ['stop']);
      expect(find.text('Jízda uložena mezi projeté jízdy'), findsOneWidget);
    });

    testWidgets('resume failure shows what to fix (no permission)', (t) async {
      await pumpV2(t, const RecorderScreenV2(),
          overrides: tripOverrides(recorder: kRecManualPaused, resumeResult: RideStartResult.noPermission), scaffold: false);
      await _settle(t);
      await t.tap(find.byType(RecorderPauseButtonV2));
      await _settle(t);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(_cs.tr('eoOpenSettings')), findsOneWidget);
    });

    testWidgets('guard (home): POKRAČOVAT V CESTĚ + Ukončit a uložit', (t) async {
      await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecHome), scaffold: false);
      await _settle(t);
      expect(find.text('ZPĚT NA STARTU'), findsOneWidget);
      expect(find.text('Ukončit a uložit'), findsOneWidget);
      await t.tap(find.text('POKRAČOVAT V CESTĚ'));
      await _settle(t);
      expect(_rec(t).calls, ['resume']);
    });

    testWidgets('rental: pause yes, stop no, ends with the return', (t) async {
      await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: kRecRentalWalk), scaffold: false);
      await _settle(t);
      expect(find.byType(RecorderPauseButtonV2), findsOneWidget);
      expect(find.byType(RecorderStopButtonV2), findsNothing);
      expect(find.textContaining('skončí sám, až motorku vrátíš'), findsOneWidget);
    });

    testWidgets('reduced motion: riding and paused settle (no loop)', (t) async {
      for (final s in [kRecRiding, kRecAutoPaused, kRecArmed]) {
        await pumpV2(t, const RecorderScreenV2(), overrides: tripOverrides(recorder: s), scaffold: false, reducedMotion: true);
        await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  group('dock, Domů row, nav chip', () {
    testWidgets('dock bar: ❚❚ disc pauses, ■ only for a manual ride', (t) async {
      await pumpV2(t, TrasyRecordDockV2(onOpenRecorder: () {}), overrides: tripOverrides(recorder: kRecAutoPaused));
      await _settle(t);
      // ui-v2 r1: auto-pauza má vlastní slovo (ne „POZASTAVENO" jako ruční).
      expect(find.text('AUTO-PAUZA'), findsOneWidget);
      expect(find.byType(RecStopButtonV2), findsOneWidget);
      await t.tap(find.byType(RecPauseDiscV2));
      await _settle(t);
      expect(_rec(t).calls, ['pause']);
      await t.pumpWidget(const SizedBox());
      await pumpV2(t, TrasyRecordDockV2(onOpenRecorder: () {}), overrides: tripOverrides(recorder: kRecRentalWalk));
      await _settle(t);
      expect(find.byType(RecStopButtonV2), findsNothing);
      expect(find.byType(RecPauseDiscV2), findsOneWidget);
    });

    testWidgets('Domů row: pause disc + stop asks first', (t) async {
      await pumpV2(t, const HomeRecordRowV2(), overrides: tripOverrides(recorder: kRecRiding), size: const Size(412, 915));
      await _settle(t);
      await t.tap(find.byType(RecPauseDiscV2));
      await _settle(t);
      expect(_rec(t).calls, ['pause']);
      await t.tap(find.bySemanticsLabel('Ukončit záznam jízdy'));
      await _settle(t);
      expect(find.text('Ukončit záznam?'), findsOneWidget);
      await t.tap(find.text('Ukončit a uložit'));
      await _settle(t);
      expect(_rec(t).calls, ['pause', 'stop']);
    });

    testWidgets('nav chip: hidden idle, REC / AUTO-PAUZA, tap → sheet → pause', (t) async {
      await pumpV2(t, const NavRecChipV2(), overrides: tripOverrides());
      await _settle(t);
      expect(find.text('REC'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await pumpV2(t, const NavRecChipV2(), overrides: tripOverrides(recorder: kRecAutoPaused));
      await _settle(t);
      expect(find.text('AUTO-PAUZA'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await pumpV2(t, const NavRecChipV2(), overrides: tripOverrides(recorder: kRecRiding));
      await _settle(t);
      await t.tap(find.text('REC'));
      await _settle(t);
      expect(find.text('NAHRÁVÁM'), findsOneWidget);
      await t.tap(find.text('Pozastavit'));
      await _settle(t);
      expect(_rec(t).calls, ['pause']);
      expect(find.text('Pokračovat'), findsOneWidget);
    });
  });
}
