// v2 trips (SPEC §8 / §9.2): grouping in the list (explicit trip, rental
// group, merge row only on the new server), merge with name + Zpět, the
// old-server message, trip detail actions (split, sharing, delete choice,
// gone trip), the trip row of a ride, multi-day stats / stages and the
// old-server labels. Pause / recorder: rides_pause_test.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:motogo_app/features/routes/v2/rides/moje_lists_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_card_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_merge_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_track_sketch_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_trip_card_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_detail_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'rides_cases.dart';

const _cs = AppTranslations('cs');

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

  group('trips in the list', () {
    testWidgets('grouped: 2 trips + 3 rides, merge row, counts by item', (t) async {
      await pumpV2(t, mojeView(rides: AsyncValue.data(kTripRides())),
          size: const Size(412, 3000), overrides: tripOverrides(), scaffold: false);
      await _settle(t);
      expect(find.byType(RideTripCardV2), findsNWidgets(2));
      expect(find.byType(RideCardV2), findsNWidgets(3));
      expect(find.byType(MojeMergeRowV2), findsOneWidget);
      expect(find.text('5'), findsWidgets); // Vše 5 · summary 5
      expect(find.text('Alpy 2026 — Grossglockner a Dolomity'), findsOneWidget);
      expect(find.text('Výpůjčka Honda Africa Twin'), findsOneWidget);
    });

    testWidgets('old server rides only: no merge row', (t) async {
      await pumpV2(t, mojeView(rides: AsyncValue.data([kLegacy, kRidePrivate])),
          size: const Size(412, 2400), overrides: tripOverrides(rides: [kLegacy, kRidePrivate]), scaffold: false);
      await _settle(t);
      expect(find.byType(MojeMergeRowV2), findsNothing);
    });

    testWidgets('ride card: range, days chip, time in the saddle', (t) async {
      await pumpV2(t, RideCardV2(ride: kRideMultiDay, onTap: () {}), overrides: tripOverrides());
      await _settle(t);
      expect(find.text('28.–30. 9. 2026'), findsOneWidget);
      expect(find.text('3 dny'), findsOneWidget);
      expect(find.text('21 h 10 min v sedle'), findsOneWidget);
    });

    test('sketch: a pause in place draws nothing, a moved pause is dashed', () {
      final s = RideTrackSketch(ride: kRideMultiDay);
      expect(s.gaps, hasLength(1));
      expect(s.gaps.single.$3, isTrue);
    });
  });

  group('merge', () {
    testWidgets('below two: hint + disabled; merge → name → server items → Zpět', (t) async {
      final log = TripSeamLog();
      await pumpV2(t, const RideMergeScreenV2(preselectRideId: 's1'),
          size: const Size(412, 1600), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      expect(find.text('Vyber aspoň dvě jízdy.'), findsOneWidget);
      await t.tap(find.text('SLOUČIT (1)'));
      await _settle(t);
      expect(log.sets, isEmpty);
      await t.tap(find.text('Alpy 2026 — Grossglockner a Dolomity'));
      await _settle(t);
      await t.tap(find.text('SLOUČIT (2)'));
      await _settle(t);
      expect(find.text('Pojmenuj cestu'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Léto 2026');
      await t.tap(find.text('Uložit'));
      await _settle(t);
      expect(log.sets, hasLength(1));
      final items = log.sets.single;
      expect(items.map((i) => i.id).toSet(), {'t1', 't2', 't3', 's1'});
      expect(items.every((i) => i.tripId == 't1' && i.tripName == 'Léto 2026'), isTrue);
      expect(find.text('Jízdy jsou sloučené do jedné cesty.'), findsOneWidget);
      await t.tap(find.text('Zpět'));
      await _settle(t);
      expect(log.sets, hasLength(2));
      final undo = {for (final i in log.sets.last) i.id: (i.tripId, i.tripName)};
      expect(undo['s1'], (null, null));
      expect(undo['t2'], ('t1', 'Alpy 2026 — Grossglockner a Dolomity'));
    });

    testWidgets('old server: what / why / fix stays on the screen', (t) async {
      final log = TripSeamLog()..kind = RideTripSetKind.missing;
      await pumpV2(t, const RideMergeScreenV2(preselectRideId: 's1'),
          size: const Size(412, 1600), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      await t.tap(find.text('Tři dny Šumavou a Bavorskem s přejezdem trajektem'));
      await _settle(t);
      await t.tap(find.text('SLOUČIT (2)'));
      await _settle(t);
      await t.tap(find.text('Uložit'));
      await _settle(t);
      expect(find.text('Jízdy se nesloučily'), findsOneWidget);
      expect(find.textContaining('server ještě nemá potřebnou aktualizaci'), findsOneWidget);
    });
  });

  group('trip detail', () {
    testWidgets('sums, rides, split with confirm, sharing switch', (t) async {
      final log = TripSeamLog();
      await pumpV2(t, const TripDetailScreenV2(leaderId: 't1'),
          size: const Size(412, 3000), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      expect(find.text('Alpy 2026 — Grossglockner a Dolomity'), findsOneWidget);
      expect(find.text('Jízdy v cestě'), findsOneWidget);
      expect(find.byType(RideCardV2), findsNWidgets(3));
      expect(find.text('941 km'), findsWidgets);
      await t.tap(find.byType(Switch));
      await _settle(t);
      expect(log.other, ['visibility:true:3']);
      await t.ensureVisible(find.text('Rozdělit cestu').first);
      await t.tap(find.text('Rozdělit cestu').first);
      await _settle(t);
      expect(find.text('Rozdělit cestu na jednotlivé jízdy?'), findsOneWidget);
      await t.tap(find.text('Rozdělit cestu').last);
      await _settle(t);
      expect(log.sets.single.every((i) => i.tripId == i.id && i.tripName == null), isTrue);
    });

    testWidgets('delete: choice sheet → delete all asks again', (t) async {
      final log = TripSeamLog();
      await pumpV2(t, const TripDetailScreenV2(leaderId: 'b91'),
          size: const Size(412, 3000), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      expect(find.text('Výpůjčka Honda Africa Twin'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Smazat cestu'));
      await _settle(t);
      expect(find.text('Co chceš smazat?'), findsOneWidget);
      await t.tap(find.text('Smazat i všechny jízdy'));
      await _settle(t);
      expect(find.text('Smazat celou cestu?'), findsOneWidget);
      await t.tap(find.text('Smazat i všechny jízdy').last);
      await _settle(t);
      expect(log.other, ['delete:2']);
    });

    testWidgets('gone trip: what happened + way back', (t) async {
      await pumpV2(t, const TripDetailScreenV2(leaderId: 'zz'), overrides: tripOverrides(), scaffold: false);
      await _settle(t);
      expect(find.text('Tahle cesta už neexistuje'), findsOneWidget);
    });
  });

  group('ride detail', () {
    testWidgets('trip member: part of the trip + remove with Zpět', (t) async {
      final log = TripSeamLog();
      await pumpV2(t, rideDetail(kTrip2), size: const Size(412, 2600), overrides: tripOverrides(log: log), scaffold: false);
      await _settle(t);
      expect(find.text('Součást cesty'), findsOneWidget);
      await t.tap(find.text('Vyjmout z cesty'));
      await _settle(t);
      expect(log.sets.single.single.tripId, 't2');
      expect(find.text('Jízda je vyjmutá z cesty.'), findsOneWidget);
    });

    testWidgets('multi-day ride: stages, pauses, days, add to a trip', (t) async {
      await pumpV2(t, rideDetail(kRideMultiDay), size: const Size(412, 3400), overrides: tripOverrides(), scaffold: false);
      await _settle(t);
      expect(find.text('Přidat do cesty…'), findsOneWidget);
      expect(find.text('Etapy'), findsOneWidget);
      expect(find.textContaining('Den 3 · '), findsOneWidget);
      expect(find.text('2× · 37 h'), findsOneWidget);
      expect(find.text('na cestě (bez pauz)'), findsOneWidget);
      expect(find.text('krátké zastávky'), findsOneWidget);
      expect(find.text('dny na cestě'), findsOneWidget);
      expect(find.textContaining('přesun během pauzy'), findsOneWidget);
    });

    testWidgets('old-server ride: old labels, no trip row', (t) async {
      await pumpV2(t, rideDetail(kLegacy), size: const Size(412, 2600), overrides: tripOverrides(), scaffold: false);
      await _settle(t);
      expect(find.text('celkový čas'), findsOneWidget);
      expect(find.text('na cestě (bez pauz)'), findsNothing);
      expect(find.text('Přidat do cesty…'), findsNothing);
      expect(find.text('Součást cesty'), findsNothing);
    });
  });

  group('trip names', () {
    test('rider name > rental > dates', () {
      final rides = kTripRides();
      expect(tripNameV2(_cs, tripOf(rides, 't1')), 'Alpy 2026 — Grossglockner a Dolomity');
      expect(tripNameV2(_cs, tripOf(rides, 'b91')), 'Výpůjčka Honda Africa Twin');
    });
  });
}
