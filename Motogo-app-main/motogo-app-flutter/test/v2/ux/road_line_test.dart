// Pokyn majitele 2026-11-08: „všechny trasy se všude zobrazovaly přepočítané
// po silnici a ne jen přímky mezi body“ — uložená geometrie ze samotných
// zastávek se nebere, náhledy karet kreslí jen čáru po silnici a bez ní nic.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_map/flutter_map.dart' show Polyline, PolylineLayer;
import 'package:motogo_app/features/routes/my_experiences_provider.dart';
import 'package:motogo_app/features/routes/ride_map.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/road_line.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/routes_provider.dart' show RouteProfile;
import 'package:motogo_app/features/routes/v2/rides/ride_track_sketch_v2.dart';
import 'package:motogo_app/features/routes/v2/route_road_sketch_v2.dart';

import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

const _a = LatLng(49.20, 16.60), _b = LatLng(49.25, 16.70), _c = LatLng(49.30, 16.65);

Map<String, dynamic> _json(List<LatLng> geo) => {
      'id': 'r1',
      'name': 'Okruh',
      'route_type': 'loop',
      'waypoints': [for (final p in [_a, _b, _c]) {'lat': p.latitude, 'lng': p.longitude}],
      'geometry': {'coordinates': [for (final p in geo) [p.longitude, p.latitude]]},
    };

void main() {
  setUpAll(() {
    registerRoutesStrings();
    HttpOverrides.global = RtFakeHttpOverrides();
  });

  group('isRoadGeometry', () {
    test('bare stops (+ branch start and loop back) are straight legs', () {
      expect(isRoadGeometry(const [], 3), isFalse);
      expect(isRoadGeometry(const [_a, _b, _c], 3), isFalse);
      expect(isRoadGeometry(const [_a, _b, _c, _a, _b], 3), isFalse);
    });
    test('a routed line has more points than the stops', () {
      expect(isRoadGeometry(fakeRoadLine(const [_a, _b, _c]), 3), isTrue);
    });
  });

  group('RouteItem.fromJson', () {
    test('drops stored geometry made only of the stops', () {
      expect(RouteItem.fromJson(_json(const [_a, _b, _c, _a])).geometry, isEmpty);
    });
    test('keeps a stored road line', () {
      final road = fakeRoadLine(const [_a, _b, _c]);
      expect(RouteItem.fromJson(_json(road)).geometry, hasLength(road.length));
    });
  });

  test('RoadLineKey compares by stops and profile', () {
    expect(RoadLineKey(const [_a, _b]), RoadLineKey(const [_a, _b]));
    expect(RoadLineKey(const [_a, _b]).hashCode, RoadLineKey(const [_a, _b]).hashCode);
    expect(RoadLineKey(const [_a, _b]) == RoadLineKey(const [_b, _a]), isFalse);
    expect(RoadLineKey(const [_a, _b]) == RoadLineKey(const [_a, _b], profile: RouteProfile.fastest), isFalse);
  });

  group('sketches', () {
    testWidgets('saved route sketch routes its stops in the chosen profile', (t) async {
      RoadLineKey? asked;
      final road = fakeRoadLine(const [_a, _b, _c]);
      const saved = SavedRoute(id: 's1', name: 'Moje', waypoints: [_a, _b, _c], profile: RouteProfile.shortest);
      await pumpV2(t, const SavedRouteRoadSketchV2(route: saved), overrides: [
        roadLineProvider.overrideWith((ref, key) async {
          asked = key;
          return road;
        }),
      ]);
      await t.pumpAndSettle();
      expect(asked, RoadLineKey(const [_a, _b, _c], profile: RouteProfile.shortest));
      expect(t.widget<RideTrackSketch>(find.byType(RideTrackSketch)).lines.single, road);
    });
  });

  group('ride gaps (owner: „odhad šedá trasa s popisem“)', () {
    const gap = RideGap(from: _b, to: _c, sec: 900, km: 6);
    final segs = [
      const RideSegment([_a, _b]),
      const RideSegment([_c, LatLng(49.31, 16.66)], gapBefore: gap),
    ];
    final road = fakeRoadLine(const [_b, _c]);

    testWidgets('big map: gap = grey dotted ROAD estimate + label, no straight connector', (t) async {
      await pumpV2(t, SizedBox(width: 360, height: 400, child: RideTrackMap(track: const [_a, _b, _c], segments: segs, interactive: true)),
          overrides: [roadLineProvider.overrideWith((ref, key) async => key.stops.length == 2 ? road : const <LatLng>[])]);
      await t.pump(const Duration(milliseconds: 50));
      final lines = [for (final l in t.widgetList<PolylineLayer>(find.byType(PolylineLayer))) ...l.polylines];
      expect(lines.any((Polyline l) => l.points.length == road.length), isTrue);
      expect(lines.any((Polyline l) => l.points.length == 2 && l.points.first == _b && l.points.last == _c), isFalse);
      expect(find.text('Odhad trasy · bez GPS'), findsOneWidget);
      await rtEnd(t);
    });

    testWidgets('routing failed → no gap line at all', (t) async {
      await pumpV2(t, SizedBox(width: 360, height: 400, child: RideTrackMap(track: const [_a, _b, _c], segments: segs, interactive: true)),
          overrides: [roadLineProvider.overrideWith((ref, key) async => const <LatLng>[])]);
      await t.pump(const Duration(milliseconds: 50));
      final lines = [for (final l in t.widgetList<PolylineLayer>(find.byType(PolylineLayer))) ...l.polylines];
      expect(lines.any((Polyline l) => l.points.length == 2 && l.points.first == _b), isFalse);
      expect(find.text('Odhad trasy · bez GPS'), findsNothing);
      await rtEnd(t);
    });
  });
}
