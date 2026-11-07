// Cases of the Trasy v2 matrix, part 2: route detail, planner, community
// forms, maps and the small v2 pieces (nav skin, place sheet head, menu).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:motogo_app/features/routes/community_submit.dart';
import 'package:motogo_app/features/routes/places_map_screen.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/route_builder_screen.dart';
import 'package:motogo_app/features/routes/route_detail_screen.dart';
import 'package:motogo_app/features/routes/route_submit_screen.dart';
import 'package:motogo_app/features/routes/routes_map_screen.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/routes_provider.dart';
import 'package:motogo_app/features/routes/v2/map_controls_v2.dart';
import 'package:motogo_app/features/routes/v2/poi_sheet_v2.dart';
import 'package:motogo_app/features/routes/v2/route_nav_skin_v2.dart';

import '../support/fakes_routes.dart';
import 'routes_cases.dart' show RtCaseT;

List<Override> _detail({bool fail = false, bool hang = false}) => [
      ...routesOverrides(routesFail: fail, routesHang: hang),
      routeFullProvider.overrideWith((ref, id) async {
        for (final r in kRtRoutes) {
          if (r.id == id) return r;
        }
        return null;
      }),
    ];

Map<String, RtCaseT> detailCases() => {
      'ok': (() => const RouteDetailScreen(routeId: 'r1', siblingIds: ['r1', 'r2', 'r3']), () => _detail()),
      'no-pois': (() => const RouteDetailScreen(routeId: 'r2'), () => _detail()),
      'hard-abroad': (() => const RouteDetailScreen(routeId: 'r3', siblingIds: ['r1', 'r2', 'r3']), () => _detail()),
      'missing': (() => const RouteDetailScreen(routeId: 'zzz'), () => _detail()),
      'loading': (() => const RouteDetailScreen(routeId: 'r1'), () => _detail(hang: true)),
      'error': (() => const RouteDetailScreen(routeId: 'r1'), () => _detail(fail: true)),
    };

Map<String, RtCaseT> builderCases() => {
      'route': (() => RouteBuilderScreen(route: kRtRoutes.first), () => routesOverrides()),
      'empty': (() => const RouteBuilderScreen(route: RouteItem(id: 'custom', name: '')), () => routesOverrides()),
    };

Map<String, RtCaseT> formCases() => {
      'route-submit': (() => const RouteSubmitScreen(), () => routesOverrides()),
      'poi-submit': (() => const PoiSubmitScreen(initialPoint: LatLng(48.99, 16.67)), () => routesOverrides()),
    };

Map<String, RtCaseT> mapCases() => {
      'places-map': (() => const PlacesMapScreen(), () => routesOverrides()),
      'places-map-sel': (() => const PlacesMapScreen(), () => routesOverrides(selected: {'catalog:c1', 'catalog:c2'})),
      'routes-map': (() => const RoutesMapScreen(), () => routesOverrides()),
    };

/// Small v2 pieces on one page (nav skin, place sheet head, map controls).
Map<String, RtCaseT> pieceCases() => {
      'nav-skin-rec': (
        () => const _Pieces(),
        () => routesOverrides(recorder: const RideRecorderState(recording: true, manual: true, rideId: 'x')),
      ),
      'nav-skin-gps': (
        () => const _Pieces(),
        () => routesOverrides(recorder: const RideRecorderState(recording: true, rideId: 'x', gpsLost: true)),
      ),
    };

class _Pieces extends StatelessWidget {
  const _Pieces();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          color: const Color(0xFF0A1F14),
          padding: const EdgeInsets.all(12),
          // Test-only showcase of the pieces (not the real nav bar): a Wrap,
          // so 320 dp / large text never overflows the harness row.
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            NavCircleV2(end: false, onTap: () {}),
            const Text('Rajhrad a Židlochovicko', style: TextStyle(color: Colors.white)),
            const NavRecChipV2(),
            const NavStopsChipV2('2/5'),
            NavCircleV2(end: true, onTap: () {}),
          ]),
        ),
        const SizedBox(height: 16),
        const PoiSheetHeadV2(index: 2, name: 'Zámek Židlochovice', catKey: 'castle', catLabel: 'Hrady a zámky'),
        const SizedBox(height: 16),
        const PoiSheetHeadV2(index: null, name: 'Pouzdřanská step - Kolby', catKey: 'nature', catLabel: 'Příroda'),
        const SizedBox(height: 16),
        const PoiSheetCounterV2('3 / 12'),
        const SizedBox(height: 16),
        PoiTripButtonV2(selected: false, onTap: () {}),
        const SizedBox(height: 12),
        PoiTripButtonV2(selected: true, onTap: () {}),
        const SizedBox(height: 16),
        Row(children: [
          MapRoundV2(icon: Icons.my_location, onTap: () {}),
          const SizedBox(width: 12),
          MapRoundV2(icon: Icons.add_location_alt_outlined, onTap: () {}),
        ]),
      ]);
}
