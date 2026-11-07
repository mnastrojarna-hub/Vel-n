// Starý vzhled ovládání záznamu (SPEC §9.1, §16.2): karta v „Mých
// zážitcích", štítek, štítek v navigaci a jeho sheet — každá fáze × 8 jazyků
// × šířka 320 / 412 × písmo 1.0 / 1.3 bez přetečení; tlačítka volají
// pause / resume / stop; Ukončit jen u vlastní jízdy; popisky pro čtečku;
// reduced motion = nic se neanimuje.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/ride_pause_sheet.dart';
import 'package:motogo_app/features/routes/ride_rec_controls.dart';
import 'package:motogo_app/features/routes/ride_rec_phase.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_fixtures.dart';
import 'support/ui_harness.dart';

/// Hlavička navigace jako ve starém vzhledu (tmavý pruh, název trasy roztažený).
Widget _navHeader() => Container(
      color: const Color(0xFF1A2E22),
      padding: const EdgeInsets.all(8),
      child: const Row(children: [
        SizedBox(width: 40, height: 40),
        SizedBox(width: 10),
        Expanded(child: Text('Okruh Pálavou s výhledem na vinice', maxLines: 1, overflow: TextOverflow.ellipsis)),
        RideNavRecChip(),
      ]),
    );

Widget _all(Future<void> Function(bool) onStartStop) => Column(children: [
      const Align(alignment: Alignment.centerLeft, child: RideRecChip()),
      const SizedBox(height: 8),
      RideRecControlsCard(onStartStop: onStartStop),
      _navHeader(),
    ]);

RideRecorderState _s(String k) => recStates()[k]!;

FakeRec _fake(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(RideRecControlsCard).first), listen: false)
        .read(rideRecorderProvider.notifier) as FakeRec;

void main() {
  setUpAll(loadRidesFont);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Matice: každá fáze × jazyk × šířka × písmo → žádné přetečení ani výjimka.
  for (final lang in kRpLangs) {
    for (final w in kRpWidths) {
      for (final scale in kRpScales) {
        testWidgets('ovládání záznamu $lang ${w.toInt()} ×$scale', (tester) async {
          for (final e in recStates().entries) {
            await pumpRides(tester, _all((_) async {}),
                lang: lang, width: w, scale: scale, overrides: ridesUiOverrides(rec: e.value));
            await tester.pump(const Duration(milliseconds: 60));
            expect(tester.takeException(), isNull, reason: e.key);
            // Sheet z navigace (když se nahrává) — taky bez přetečení.
            if (e.value.recording) {
              await tester.tap(find.byType(RideNavRecChip));
              await tester.pump(const Duration(milliseconds: 400));
              expect(tester.takeException(), isNull, reason: 'sheet ${e.key}');
              expect(find.byType(RideRecButtons), findsNWidgets(2), reason: 'sheet ${e.key} otevřený');
            }
          }
        });
      }
    }
  }

  testWidgets('vlastní jízda: Pozastavit → pause(), Ukončit → onStartStop(true)', (tester) async {
    final calls = <bool>[];
    await pumpRides(tester, _all((r) async => calls.add(r)), overrides: ridesUiOverrides(rec: _s('own_riding')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Pozastavit'), findsOneWidget);
    expect(find.text('Ukončit záznam jízdy'), findsOneWidget);
    expect(find.text(t(tester.element(find.byType(RideRecControlsCard))).tr('rpRentalEndsHint')), findsNothing);
    await tester.tap(find.text('Pozastavit'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_fake(tester).calls, ['pause']);
    expect(find.text('Pokračovat'), findsOneWidget); // ruční pauza → Pokračovat
    await tester.tap(find.text('Ukončit záznam jízdy'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, [true]);
  });

  testWidgets('ruční pauza: Pokračovat → resume() a hláška „čeká na rozjezd"', (tester) async {
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('own_manual')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Pokračovat'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_fake(tester).calls, ['resume']);
    expect(find.text('Pokračuju — nahrávat začnu, jakmile se rozjedeš.'), findsOneWidget);
    expect(find.text('Připraveno — nahrávat začnu, jakmile se rozjedeš'), findsOneWidget);
  });

  testWidgets('Pokračovat bez polohy → hláška co a jak opravit', (tester) async {
    await pumpRides(tester, _all((_) async {}),
        overrides: ridesUiOverrides(rec: _s('own_manual'), resumeResult: RideStartResult.locationOff));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Pokračovat'));
    await tester.pump(const Duration(milliseconds: 100));
    final tr = t(tester.element(find.byType(RideRecControlsCard)));
    expect(find.text(tr.tr('eoRideLocOff')), findsOneWidget);
    expect(find.text(tr.tr('eoOpenSettings')), findsOneWidget);
  });

  testWidgets('výpůjčka: pauza ano, Ukončit ne, vysvětlení konce vrácením', (tester) async {
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('rent_auto')));
    await tester.pump(const Duration(milliseconds: 60));
    // Auto-pauza: tlačítko říká, co udělá (vypne GPS), a že se nic mačkat nemusí.
    expect(find.text('Vypnout GPS'), findsOneWidget);
    expect(find.text('Pozastavit'), findsNothing);
    expect(find.text('Nic nemačkej — jakmile se rozjedeš, nahrávám dál sám.'), findsOneWidget);
    expect(find.text('❚❚ Auto-pauza'), findsOneWidget);
    expect(find.text('Ukončit záznam jízdy'), findsNothing);
    expect(find.text('Záznam výpůjčky skončí sám, až motorku vrátíš.'), findsOneWidget);
    expect(find.text('Stojíš — záznam je pozastavený'), findsOneWidget);
    expect(find.textContaining('od '), findsWidgets);
  });

  testWidgets('pojistka (doma): Pokračovat v cestě / Ukončit a uložit + otázka', (tester) async {
    final calls = <bool>[];
    await pumpRides(tester, _all((r) async => calls.add(r)), overrides: ridesUiOverrides(rec: _s('own_home')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Jsi zpátky tam, kde cesta začala'), findsOneWidget);
    expect(find.textContaining('přes 4 h'), findsOneWidget);
    await tester.tap(find.text('Ukončit a uložit'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, [true]);
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('own_long')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Pokračovat v cestě'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_fake(tester).calls, ['resume']);
  });

  testWidgets('vysvětlení auto-pauzy jde rozbalit', (tester) async {
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('own_auto_stop')));
    await tester.pump(const Duration(milliseconds: 60));
    final hint = t(tester.element(find.byType(RideRecControlsCard))).tr('rpHintAuto');
    expect(find.text(hint), findsNothing);
    await tester.tap(find.text('Jak funguje automatická pauza?'));
    await tester.pump();
    expect(find.text(hint), findsOneWidget);
  });

  testWidgets('bez záznamu: karta „Zaznamenat vlastní jízdu", štítky skryté', (tester) async {
    final calls = <bool>[];
    await pumpRides(tester, _all((r) async => calls.add(r)), overrides: ridesUiOverrides());
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Zaznamenat vlastní jízdu'), findsOneWidget);
    expect(find.text('REC'), findsNothing);
    await tester.tap(find.text('Zaznamenat vlastní jízdu'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, [false]);
  });

  testWidgets('navigace: štítek → sheet → Pozastavit', (tester) async {
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('rent_riding')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('REC 86,4'), findsOneWidget);
    await tester.tap(find.byType(RideNavRecChip));
    await tester.pumpAndSettle();
    expect(find.text('Ukončit záznam jízdy'), findsNothing);
    await tester.tap(find.text('Pozastavit').last);
    await tester.pumpAndSettle();
    expect(_fake(tester).calls, ['pause']);
    expect(find.text('Pauza'), findsOneWidget);
  });

  testWidgets('popisky pro čtečku a cíle ≥ 44 px', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('own_riding')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.bySemanticsLabel('Pozastavit záznam jízdy'), findsOneWidget);
    expect(find.bySemanticsLabel('Nahrávám jízdu'), findsWidgets);
    for (final b in tester.widgetList<RideRecButton>(find.byType(RideRecButton))) {
      final size = tester.getSize(find.byWidget(b));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    expect(tester.getSize(find.byType(RideNavRecChip)).height, greaterThanOrEqualTo(44));
    final node = tester.getSemantics(find.text('Nahrávám jízdu'));
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  testWidgets('reduced motion: všechny fáze se ustálí (žádná smyčka)', (tester) async {
    for (final e in recStates().entries) {
      await pumpRides(tester, _all((_) async {}), reducedMotion: true, overrides: ridesUiOverrides(rec: e.value));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5));
      expect(tester.takeException(), isNull, reason: e.key);
    }
  });

  test('texty fází (LOGIC_API §1.3)', () {
    const tr = AppTranslations('cs');
    final st = recStates();
    expect(ridePhaseText(st['idle']!, tr), isNull);
    expect(ridePhaseText(st['own_riding']!, tr), 'Nahrávám jízdu');
    expect(ridePhaseText(st['own_armed']!, tr), 'Připraveno — nahrávat začnu, jakmile se rozjedeš');
    expect(ridePhaseText(st['own_auto_walk']!, tr), 'Stojíš — záznam je pozastavený');
    expect(ridePhaseText(st['own_manual']!, tr), 'Záznam je pozastavený');
    expect(ridePhaseText(st['own_long']!, tr), startsWith('Cesta stojí od '));
    expect(rideChipKey(st['own_armed']!), 'rpChipArmed');
    // Auto-pauza má vlastní štítek (ne „Pozastaveno" jako ruční pauza).
    expect(rideChipKey(st['rent_auto']!), 'rpChipAuto');
    expect(rideChipKey(st['own_manual']!), 'rpChipPaused');
    // Bez polohy se nenahrává — štítek ani věta nesmí tvrdit „Nahrávám".
    expect(rideChipKey(st['own_gpslost']!), 'rpChipNoGps');
    expect(ridePhaseText(st['own_gpslost']!, tr), 'Záznam stojí — poloha není dostupná');
    expect(rideNavChipText(st['own_gpslost']!, tr), 'Bez GPS');
    expect(rideIsAutoPaused(st['own_auto_stop']!), isTrue);
    expect(rideIsAutoPaused(st['own_armed']!), isFalse);
    expect(rideIsAutoPaused(st['own_manual']!), isFalse);
    expect(rideIsAutoPaused(st['own_gpslost']!), isFalse);
    expect(rideSinceText(st['own_armed']!, tr), isNull);
    expect(rideSinceText(st['own_auto_stop']!, tr), startsWith('od '));
    expect(rideSinceText(st['own_long']!, tr), isNull);
    // Číslo + jednotka se nezalomí (pevná mezera, „km⁠/⁠h" se spojovníky slov).
    expect(rideLiveText(st['own_riding']!, tr),
        '1235\u00A0km · 26\u00A0h 21\u00A0min v sedle · 7.\u00A0den · Ø\u00A047\u00A0km\u2060/\u2060h');
    expect(rideLiveText(st['rent_armed']!, tr), isNull);
    // Ø až po 5 min v sedle.
    expect(rideLiveText(const RideRecorderState(recording: true, liveKm: 3, liveMovingSec: 200), tr),
        '3,0\u00A0km · 3\u00A0min v sedle');
    expect(rideNavChipText(st['own_manual']!, tr), 'Pauza');
    // „REC" jen při skutečném nahrávání.
    expect(rideNavChipText(st['own_armed']!, tr), 'Připraveno');
    expect(rideNavChipText(st['own_auto_stop']!, tr), 'Auto-pauza');
    expect(rideNavChipText(st['own_riding']!, tr), 'REC 1235');
  });

  testWidgets('obnovení stavu po restartu předka nepřepíše pevný stav', (tester) async {
    await pumpRides(tester, _all((_) async {}), overrides: ridesUiOverrides(rec: _s('own_auto_stop')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Stojíš — záznam je pozastavený'), findsOneWidget);
    expect(tester.renderObject<RenderBox>(find.byType(RideRecControlsCard)).size.width, greaterThan(200));
  });
}
