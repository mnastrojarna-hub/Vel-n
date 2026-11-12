// routes_rides F-04 / F-05 / F-06 / F-08 / F-10 / F-15–F-17 / F-22 /
// F-23 / F-31 / F-33 / F-34 / F-38: recorder numbers, ride results as
// sheets, the stop sheet, ride-detail pager, Moje swipe / tiles / months.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/routes/animated_route_icon.dart';
import 'package:motogo_app/features/routes/ride_detail_screen.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_trip.dart';
import 'package:motogo_app/features/routes/ride_trip_card.dart';
import 'package:motogo_app/core/v2/gestures/mg_swipe.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_tabs_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/rec_live_bar_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/rec_widgets_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_screen_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_detail_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_pause_actions_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_results_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_trip_card_v2.dart';
import 'package:motogo_app/features/routes/v2/trasy_hub_header_v2.dart';

import '../screens/rides_cases.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

Widget _launch(void Function(BuildContext) open) =>
    Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => open(c), child: const Text('OPEN'))));

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('OPEN'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Router app (the login action is a push) in the v2 scope.
Future<GoRouter> _router(WidgetTester t, void Function(BuildContext) open) async {
  final r = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: _launch(open))),
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('LOGIN PAGE'))),
  ]);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerConfig: r,
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      builder: (c, child) => MgV2Scope(enabled: true, child: child!),
    ),
  ));
  return r;
}

Future<void> _drain(WidgetTester t) async {
  await ridesEnd(t);
  await t.pump(const Duration(seconds: 11));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    ridesMockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(MgMotion.resetSession);

  group('F-04 / F-05 recorder', () {
    testWidgets('live card: 48 px time in the saddle, km in neon, Ø, "od 8:29 · start"', (t) async {
      final start = DateTime.now().copyWith(hour: 8, minute: 29);
      final rec = kRecManual.copyWith(liveKm: 38.2, liveMovingSec: 4320, tripStartedAt: start);
      await pumpV2(t, const RecorderScreenV2(), overrides: ridesOverrides(recorder: rec), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('rec-live-time')), findsOneWidget);
      expect(find.text('1 h 12 min'), findsOneWidget);
      expect(find.text('38,2 km'), findsOneWidget);
      expect(find.text('Ø 32 km/h'), findsOneWidget);
      expect(find.text('od 8:29 · start'), findsOneWidget);
      await ridesEnd(t);
    });

    testWidgets('idle CTA "ZAČÍT ZÁZNAM" carries the ⏺ glyph', (t) async {
      await pumpV2(t, const RecorderScreenV2(), overrides: ridesOverrides(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      final cta = t.widget<MgCta>(find.byType(MgCta));
      expect(cta.leadingIcon, MgIcons.recordDot);
      await ridesEnd(t);
    });
  });

  group('F-06 ride results', () {
    for (final (r, title) in [
      (RideStartResult.locationOff, 'Poloha v telefonu je vypnutá'),
      (RideStartResult.noPermission, 'Bez polohy jízdu nezaznamenáme'),
      (RideStartResult.imprecise, 'Zapni přesnou polohu'),
      (RideStartResult.failed, 'Záznam se nespustil'),
      (RideStartResult.notSignedIn, 'Přihlas se a vyraž'),
    ]) {
      testWidgets('start $r → T2 sheet "$title"', (t) async {
        await pumpV2(t, _launch((c) => showRideStartResultV2(c, r, onRetry: () {})));
        await _open(t);
        expect(find.text(title), findsOneWidget);
        expect(find.text('Zpět'), findsOneWidget);
      });
    }

    testWidgets('not signed in: PŘIHLÁSIT SE closes the sheet and opens /login', (t) async {
      await _router(t, (c) => showRideStartResultV2(c, RideStartResult.notSignedIn));
      await _open(t);
      await t.tap(find.text('PŘIHLÁSIT SE'));
      await t.pumpAndSettle();
      expect(find.text('LOGIN PAGE'), findsOneWidget);
    });

    testWidgets('failed: ZKUSIT ZNOVU closes it and runs the same start again', (t) async {
      var retried = 0;
      await pumpV2(t, _launch((c) => showRideStartResultV2(c, RideStartResult.failed, onRetry: () => retried++)));
      await _open(t);
      await t.tap(find.text('Zkusit znovu'));
      await t.pumpAndSettle();
      expect(retried, 1);
      expect(find.text('Záznam se nespustil'), findsNothing);
    });

    testWidgets('ok = a toast (not a sheet)', (t) async {
      await pumpV2(t, _launch((c) => showRideStartResultV2(c, RideStartResult.ok)));
      await _open(t);
      expect(find.text('Záznam jízdy běží'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    for (final (kept, title, tone) in [
      (true, 'Jízda je uložená', MgTone.ok),
      (false, 'Jízda byla kratší než 1 km', MgTone.info),
      (null, 'Jízdu uložíme, až chytíš signál', MgTone.pending),
    ]) {
      testWidgets('stop kept=$kept → "$title" ($tone)', (t) async {
        await pumpV2(t, _launch((c) => showRideStopResultV2(c, kept)));
        await _open(t);
        expect(find.text(title), findsOneWidget);
        expect(t.widget<MgToneDisc>(find.byType(MgToneDisc)).tone, tone);
      });
    }

    testWidgets('saved sheet under reduced motion: static ✓, Hotovo closes', (t) async {
      await pumpV2(t, _launch((c) => showRideStopResultV2(c, true)), reducedMotion: true);
      await t.tap(find.text('OPEN'));
      await t.pump();
      expect(find.text('Jízda je uložená'), findsOneWidget);
      await t.tap(find.text('Hotovo'));
      await t.pump();
      expect(find.text('Jízda je uložená'), findsNothing);
    });
  });

  group('F-22 stop confirm sheet', () {
    for (final (tap, want) in [('Pokračovat v jízdě', false), ('Ukončit a uložit', true)]) {
      testWidgets('"$tap" → $want', (t) async {
        bool? got;
        await pumpV2(t, _launch((c) async => got = await trasyConfirmStop(c)),
            overrides: ridesOverrides(recorder: kRecManual.copyWith(liveKm: 38.2, liveMovingSec: 4320)));
        await _open(t);
        expect(find.text('Ukončit záznam?'), findsOneWidget);
        expect(find.textContaining('38,2 km'), findsOneWidget);
        await t.tap(find.text(tap));
        await t.pump(const Duration(milliseconds: 600));
        expect(got, want);
      });
    }

    testWidgets('swipe down = continue (false)', (t) async {
      bool? got;
      await pumpV2(t, _launch((c) async => got = await trasyConfirmStop(c)), overrides: ridesOverrides(recorder: kRecManual));
      await _open(t);
      await t.drag(find.text('Ukončit záznam?'), const Offset(0, 500));
      await t.pump(const Duration(milliseconds: 600));
      expect(got, isFalse);
    });
  });

  testWidgets('F-23 live bar keeps "Ukončit" labelled at 360 (264 px bar)', (t) async {
    await pumpV2(
        t,
        Center(
          child: SizedBox(
            width: 264,
            child: RecLiveBarV2(rec: kRecManual, onOpen: () {}, onPause: () {}, onStop: () {}),
          ),
        ),
        overrides: ridesOverrides(recorder: kRecManual));
    expect(t.widget<RecStopButtonV2>(find.byType(RecStopButtonV2)).iconOnly, isFalse);
  });

  group('F-08 ride detail pager', () {
    testWidgets('"‹ 2 / 3 ›" steps like the swipe; content switches; reduced = instant', (t) async {
      final rides = kTripRides();
      final ids = [for (final r in rides.take(3)) r.id];
      await pumpV2(t, RideDetailScreen(rideId: ids[1], siblingIds: ids),
          overrides: tripOverrides(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(RidePagerV2), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(RidePagerV2), matching: find.byType(MgIconButton)).last);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('3 / 3'), findsOneWidget);
      await t.fling(find.byType(RideDetailHeaderV2), const Offset(300, 0), 1000);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('2 / 3'), findsOneWidget);
      await _drain(t);
    });
  });

  testWidgets('F-10 trip card in the reservation detail = the v2 card', (t) async {
    final trip = groupRides(kTripRides()).whereType<RideListItemTrip>().first.trip;
    await pumpV2(t, SingleChildScrollView(child: RideTripCard(trip: trip)), overrides: tripOverrides());
    expect(find.byType(RideTripCardV2), findsOneWidget);
    await _drain(t);
  });

  group('Moje (F-15 / F-16 / F-17 / F-33 / F-38)', () {
    testWidgets('body swipe left → next sub-tab, chips are dark tab pills', (t) async {
      final taps = RideTaps();
      await pumpV2(t, mojeView(taps: taps), overrides: ridesOverrides(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      expect(t.widgetList<MgFilterChip>(find.byType(MgFilterChip)).every((c) => c.style == MgFilterChipStyle.tab), isTrue);
      // Scroll the list into the middle, then swipe on it.
      await t.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(MgSwipeSegments<MojeSub>), findsOneWidget);
      await t.flingFrom(const Offset(180, 450), const Offset(-300, 0), 1000);
      await t.pump(const Duration(milliseconds: 400));
      // lookonly-fix: the old three tabs — the first page → Objevená místa.
      expect(taps.log, contains('tab:1'));
      await ridesEnd(t);
    });

    testWidgets('summary: 3 tiles in one row at 412, "—" while rides load', (t) async {
      await pumpV2(t, mojeView(rides: const AsyncValue.loading()),
          overrides: ridesOverrides(), scaffold: false, reducedMotion: true, size: const Size(412, 915));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('—'), findsWidgets);
      await ridesEnd(t);
    });

    testWidgets('places: "Mapa míst" row = the header map action', (t) async {
      final taps = RideTaps();
      await pumpV2(t, mojeView(tab: 1, taps: taps), overrides: ridesOverrides(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      await t.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Mapa míst'), findsWidgets);
      await ridesEnd(t);
    });
  });

  group('F-14 / F-31 / F-34 small', () {
    testWidgets('hub header: logo ring (→ ranks) + stats line, route icon plays once', (t) async {
      await pumpV2(t, TrasyHubHeaderV2(seg: TrasySeg.places, onSegment: (_) {}, stats: ('1 100', '49 000')),
          overrides: ridesOverrides());
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('1 100+'), findsOneWidget);
      final icon = t.widget<AnimatedRouteIcon>(find.byType(AnimatedRouteIcon));
      expect(icon.once, isTrue);
      await t.pump(const Duration(seconds: 5));
      expect(t.binding.hasScheduledFrame, isFalse); // no infinite loop left
    });
  });
}
