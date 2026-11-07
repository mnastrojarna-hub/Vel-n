// verify:render cases — fix:r2:core: map tiles failing (MapTileErrors
// preset) on every v2 map: the strip under the header / HUD / back /
// expand disc, never under them — places map, routes map, planner, route
// detail hero, full route map, ride / trip detail, Místa map card, POI
// submit form, map picker.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/widgets/map_tile_errors.dart';
import 'package:motogo_app/features/booking/widgets/map_picker.dart';
import 'package:motogo_app/features/routes/v2/route_map_full_v2.dart';

import '../screens/rides_cases.dart' as rides;
import '../screens/rides_pause_cases.dart' as pause;
import '../screens/routes_cases.dart' as a;
import '../screens/routes_cases2.dart' as b;
import '../support/fakes_rides.dart';
import '../support/fakes_routes.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

Widget Function() _failing(Widget Function() build) => () {
      MapTileErrors.failingSince.value = DateTime(2026, 11, 7);
      return build();
    };

Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  // Map picker geocoding timeouts (4 s / 5 s) run out.
  await t.pump(const Duration(seconds: 6));
  MapTileErrors.retry();
}

List<RenderCase> coreR2RenderCases() {
  RenderCase c(String state, (Widget Function(), List<Override> Function()) x, {bool scaffold = true}) =>
      RenderCase('core_r2', 'tiles', state, _failing(x.$1), x.$2, scaffold: scaffold, end: _end);
  return [
    c('places_map', b.mapCases()['places-map']!),
    c('routes_map', b.mapCases()['routes-map']!),
    c('builder', b.builderCases()['route']!),
    c('route_detail', b.detailCases()['ok']!),
    c('places_card', a.placesCases()['list']!),
    c('ride_detail', rides.detailCases()['motogo']!, scaffold: false),
    c('trip_detail', pause.pausePageCases()['trip-explicit']!, scaffold: false),
    c('poi_submit', b.formCases()['poi-submit']!),
    c(
        'full_map',
        (
          () => RouteFullMapV2(
              map: const Stack(children: [ColoredBox(color: Color(0xFFE8EFE9), child: SizedBox.expand()), MapTileErrorChip()]),
              title: 'Rajhrad a Židlochovicko',
              sub: '5 míst · Okruh · 40 km',
              onClose: () {}),
          () => ridesOverrides(),
        ),
        scaffold: false),
    RenderCase('core_r2', 'tiles', 'map_picker',
        _failing(() => launcher((ctx) => MapPickerScreen.show(ctx, lat: 49.4, lng: 15.2))), () => routesOverrides(),
        after: tapOpen, end: _end),
  ];
}
