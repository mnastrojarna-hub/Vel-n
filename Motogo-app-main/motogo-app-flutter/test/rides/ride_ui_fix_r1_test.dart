// Opravy starého vzhledu jízd (kolo 1): statistiky a nadpisy celými slovy,
// menu „Přidat" se posouvá, auto-pauza / ruční pauza / bez polohy jasně
// odlišené, štítek cesty podle fáze, mazání nahrávané cesty varuje,
// sloučení na starém serveru nejde ani vybírat.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/community_submit.dart';
import 'package:motogo_app/features/routes/ride_detail_screen.dart';
import 'package:motogo_app/features/routes/ride_merge_screen.dart';
import 'package:motogo_app/features/routes/ride_stats_grid.dart';
import 'package:motogo_app/features/routes/ride_trip.dart';
import 'package:motogo_app/features/routes/ride_trip_card.dart';
import 'package:motogo_app/features/routes/ride_trip_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../v2/render/render_inspect.dart' show midWordBreak;
import 'support/png_http.dart';
import 'support/ui_fixtures.dart';
import 'support/ui_harness.dart';

/// Texty (ne emoji), které se zalomily uprostřed slova nebo usekly „…".
List<String> _badText(WidgetTester t) {
  final out = <String>[];
  void walk(RenderObject o) {
    if (o is RenderParagraph) {
      final s = o.text.toPlainText(includeSemanticsLabels: false);
      final wb = midWordBreak(o);
      if (wb != null) out.add('split $wb');
      if (o.didExceedMaxLines) out.add('cut $s');
    }
    o.visitChildren(walk);
  }

  walk(t.binding.renderViews.first);
  return out;
}

void main() {
  setUpAll(() async {
    await loadRidesFont();
    HttpOverrides.global = RidesPngHttpOverrides();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final rides = ridesFixture();
  final multi = rides.firstWhere((r) => r.id == 'multi');

  for (final lang in ['cs', 'de', 'nl', 'pl', 'fr', 'uk']) {
    for (final (w, scale) in [(320.0, 1.3), (320.0, 1.0), (360.0, 1.3), (412.0, 1.3)]) {
      testWidgets('statistiky a nadpis jízdy celými slovy $lang $w ×$scale', (tester) async {
        await pumpRides(tester, RideStatsGrid(ride: multi), lang: lang, width: w, scale: scale);
        await expectCleanRides(tester);
        expect(_badText(tester), isEmpty);
        await pumpRides(tester, const RideDetailScreen(rideId: 'solo'),
            lang: lang, width: w, scale: scale, overrides: ridesUiOverrides(rides: rides), scroll: false);
        await expectCleanRides(tester);
        // Výchozí název („Záznam jízdy" / „Aufgezeichnete Fahrt") + výpůjčka.
        await pumpRides(tester, const RideDetailScreen(rideId: 'b2'),
            lang: lang, width: w, scale: scale, overrides: ridesUiOverrides(rides: rides), scroll: false);
        await expectCleanRides(tester);
        expect(_badText(tester).where((s) => !s.contains('·')), isEmpty);
      });
    }
  }

  testWidgets('menu Přidat: auto-pauza řekne, co tlačítko udělá; posouvá se, nepřeteče', (tester) async {
    Future<void> open(String k, {String lang = 'cs'}) async {
      await pumpRides(tester, Builder(builder: (c) => TextButton(onPressed: () => showCommunityAddMenu(c), child: const Text('OPEN'))),
          lang: lang, width: 320, height: 690, scale: 1.3, overrides: ridesUiOverrides(rec: recStates()[k]!));
      await tester.tap(find.text('OPEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: k);
    }

    await open('own_auto_stop');
    expect(find.text('Vypnout GPS (ruční pauza)'), findsOneWidget);
    expect(find.textContaining('Nic nemačkej'), findsOneWidget);
    await open('own_manual');
    expect(find.text('Pokračovat v záznamu jízdy'), findsOneWidget);
    // Ukončit během ruční pauzy netvrdí „Nahrávám…".
    await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
    await tester.pump();
    expect(find.textContaining('Záznam je pozastavený — klepnutím cestu ukončíš'), findsOneWidget);
    for (final lang in ['pl', 'de', 'uk']) {
      await open('own_auto_stop', lang: lang);
    }
  });

  testWidgets('karta cesty: štítek podle fáze záznamu (auto-pauza ≠ nahrávám)', (tester) async {
    final trip = [for (final i in groupRides(rides)) if (i is RideListItemTrip) i.trip]
        .firstWhere((t) => t.rides.any((r) => r.id == 't1'));
    final auto = recStates()['own_auto_stop']!.copyWith(rideId: trip.rides.last.id);
    await pumpRides(tester, RideTripCard(trip: trip), overrides: ridesUiOverrides(rec: auto, rides: rides));
    await expectCleanRides(tester);
    expect(find.text('❚❚ Auto-pauza'), findsOneWidget);
    expect(find.textContaining('Nahrávám'), findsNothing);
    final manual = recStates()['own_manual']!.copyWith(rideId: trip.rides.last.id);
    await pumpRides(tester, RideTripCard(trip: trip), overrides: ridesUiOverrides(rec: manual, rides: rides));
    await expectCleanRides(tester);
    expect(find.text('❚❚ Pozastaveno'), findsOneWidget);
  });

  testWidgets('smazání cesty s nahrávanou jízdou varuje; bez rady „Rozdělit"', (tester) async {
    final rec = recStates()['own_auto_stop']!.copyWith(rideId: 't2');
    await pumpRides(tester, const RideTripDetailScreen(rideId: 't1'),
        overrides: ridesUiOverrides(rec: rec, rides: rides), scroll: false, height: 1400);
    await expectCleanRides(tester);
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final tr = t(tester.element(find.byType(RideTripDetailScreen)));
    await tester.tap(find.text(tr.tr('rpTripDeleteAll')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining(tr.tr('rpDeleteRecordingOwnQ')), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Rozdělit')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  int lines(RenderParagraph p) {
    final n = p.text.toPlainText().length;
    return p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n)).map((b) => b.top.round()).toSet().length;
  }

  for (final lang in ['de', 'fr', 'uk', 'pl']) {
    testWidgets('sloučení: tlačítko a dialog na jeden řádek $lang 320 ×1.3', (tester) async {
      await pumpRides(tester, const RideMergeScreen(preselectRideId: 'solo'),
          lang: lang, width: 320, height: 690, scale: 1.3, overrides: ridesUiOverrides(rides: rides), scroll: false);
      await expectCleanRides(tester);
      RenderParagraph para(Finder of) =>
          tester.renderObject<RenderParagraph>(find.descendant(of: of, matching: find.byType(RichText)).first);
      expect(lines(para(find.byType(ElevatedButton))), 1);
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      for (final b in [find.byType(TextButton), find.descendant(of: find.byType(AlertDialog), matching: find.byType(ElevatedButton))]) {
        expect(lines(para(b)), 1, reason: lang);
      }
      expect(_badText(tester), isEmpty);
    });
  }

  testWidgets('sloučení na starém serveru: výběr ani tlačítko nejdou použít', (tester) async {
    await pumpRides(tester, const RideMergeScreen(preselectRideId: 'solo'),
        overrides: ridesUiOverrides(rides: ridesFixture(v2: false)), scroll: false);
    await expectCleanRides(tester);
    expect(find.textContaining('server ještě nemá potřebnou aktualizaci'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsNothing); // předvýběr se neukáže
    await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
    await tester.pump();
    expect(find.byIcon(Icons.check_box), findsNothing);
    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNull);
  });
}
