// Fixtures + provider overrides for the Trasy v2 tests (PLAN §5.2): live
// sample places / routes near Velké Němčice and Mezná (research
// trasy_inventory §4), every Supabase / GPS backed provider faked.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_56_v2_routes_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_56_v2_routes_b.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart';
import 'package:motogo_app/features/routes/places_filter.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/routes_map_provider.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/routes_provider.dart';

/// Registers the Trasy v2 strings (idempotent) — the integration step
/// registers them in translations.dart for the app.
void registerRoutesStrings() {
  for (final part in [translationsExt56V2RoutesA, translationsExt56V2RoutesB]) {
    part.forEach((lang, map) => translations.putIfAbsent(lang, () => {}).addAll(map));
  }
}

const kMe = LatLng(48.9918, 16.6705);

const _rajhradPois = [
  RoutePoi(id: 'p1', name: 'Klášter Rajhrad', lat: 49.0906, lng: 16.6100, category: 'sights',
      description: 'Benediktinský klášter s památníkem písemnictví na Moravě.', avgRating: 4.7, ratingCount: 3),
  RoutePoi(id: 'p2', name: 'Blučina', lat: 49.0550, lng: 16.6440, category: 'sights'),
  RoutePoi(id: 'p3', name: 'Výhon u Židlochovic', lat: 49.0420, lng: 16.6380, category: 'lookout'),
  RoutePoi(id: 'p4', name: 'Nosislav – vinné sklepy', lat: 49.0140, lng: 16.6570, category: 'food',
      description: 'Vinařská obec s tradičními sklepy uprostřed vinic.'),
  RoutePoi(id: 'p5', name: 'Zámek Židlochovice', lat: 49.0390, lng: 16.6180, category: 'castle',
      description: 'Barokní lovecký zámek s rozlehlým parkem.'),
];

const kBranchVn = RouteBranch(id: 'b1', name: 'MotoGo24 Velké Němčice', lat: 48.9918, lng: 16.6705);
const kBranchMezna = RouteBranch(id: 'b2', name: 'MotoGo24 Mezná', lat: 49.3290, lng: 15.2590);

final kRtRoutes = <RouteItem>[
  const RouteItem(
    id: 'r1',
    branchId: 'b1',
    name: 'Rajhrad a Židlochovicko',
    description: 'Okruh úrodnou krajinou jižně od Brna mezi klášterem a zámky. Benediktinský klášter Rajhrad, '
        'lovecký zámek Židlochovice a vinařské Nosislav — pohodová jízda po okresních silnicích.',
    distanceKm: 40,
    durationMin: 55,
    difficulty: 'easy',
    waypoints: [LatLng(49.09, 16.61), LatLng(49.05, 16.64), LatLng(49.01, 16.66), LatLng(49.04, 16.62)],
    pois: _rajhradPois,
    reviewAvg: 4.7,
    reviewCount: 3,
    countries: ['CZ'],
  ),
  const RouteItem(
    id: 'r2',
    branchId: 'b1',
    name: 'Vodní krásy: Věstonická nádrž a okolí',
    distanceKm: 170,
    durationMin: 290,
    difficulty: 'medium',
    waypoints: [LatLng(48.95, 16.60), LatLng(48.87, 16.63), LatLng(48.85, 16.72), LatLng(48.93, 16.70)],
    countries: ['CZ'],
  ),
  const RouteItem(
    id: 'r3',
    branchId: 'b2',
    routeType: 'poi',
    name: 'Vyhlídková jízda: Stará radnice v Brně a okolí',
    distanceKm: 249,
    durationMin: 355,
    difficulty: 'hard',
    waypoints: [LatLng(49.19, 16.60), LatLng(49.22, 16.66), LatLng(49.17, 16.70)],
    countries: ['CZ', 'AT'],
  ),
];

final kCatalog = <RoutePoi>[
  const RoutePoi(id: 'c1', name: 'Zámek Velké Němčice', lat: 48.9930, lng: 16.6720, category: 'castle', isCatalogPoi: true,
      description: 'Kulturní památka České republiky v obci Velké Němčice.'),
  const RoutePoi(id: 'c2', name: 'vodní mlýn Velké Němčice', lat: 48.9950, lng: 16.6640, category: 'tech', isCatalogPoi: true),
  const RoutePoi(id: 'c3', name: 'Knížecí les', lat: 49.0040, lng: 16.6790, category: 'nature', isCatalogPoi: true),
  const RoutePoi(id: 'c4', name: 'Pouzdřanská step - Kolby', lat: 48.9420, lng: 16.6330, category: 'nature', isCatalogPoi: true,
      avgRating: 4.5, ratingCount: 12),
  const RoutePoi(id: 'c5', name: 'Hustopeče (rozhledna)', lat: 48.9420, lng: 16.7330, category: 'lookout', isCatalogPoi: true),
  const RoutePoi(id: 'c6', name: 'Vodní dílo Nové Mlýny', lat: 48.8900, lng: 16.6200, category: 'water', isCatalogPoi: true),
];

final kUserPois = <RoutePoi>[
  const RoutePoi(id: 'u1', name: 'Vyhlídka nad Pouzdřany', lat: 48.9440, lng: 16.6400, isUserPoi: true),
];

class FakeRtRoutes extends RoutesDataNotifier {
  final List<RouteItem> routes;
  final bool fail;
  final bool hang;
  FakeRtRoutes(this.routes, {this.fail = false, this.hang = false});

  @override
  Future<RoutesData> build() async {
    if (hang) await Completer<void>().future;
    if (fail) throw Exception('SocketException: offline');
    return RoutesData(routes: routes, branches: const {'b1': kBranchVn, 'b2': kBranchMezna});
  }
}

class FakeRtCatalog extends CatalogPoisNotifier {
  final List<RoutePoi> pois;
  final bool fail;
  final bool hang;
  FakeRtCatalog(this.pois, {this.fail = false, this.hang = false});

  @override
  Future<List<RoutePoi>> build() async {
    if (hang) await Completer<void>().future;
    if (fail) throw Exception('SocketException: offline');
    return pois;
  }
}

class FakeRtRecorder extends RideRecorderNotifier {
  final RideRecorderState initial;
  FakeRtRecorder(super.ref, this.initial) {
    state = initial;
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) state = initial;
    });
  }
}

class FakeSelection extends PlacesSelectionNotifier {
  final Set<String> initial;
  FakeSelection(this.initial);
  @override
  Set<String> build() => initial;
}

/// Everything the Trasy v2 screens read, faked.
List<Override> routesOverrides({
  List<RouteItem>? routes,
  List<RoutePoi>? catalog,
  bool routesFail = false,
  bool routesHang = false,
  bool catalogFail = false,
  bool catalogHang = false,
  LatLng? me = kMe,
  RideRecorderState recorder = const RideRecorderState(),
  Set<String> selected = const {},
}) =>
    [
      routesDataProvider.overrideWith(() => FakeRtRoutes(routes ?? kRtRoutes, fail: routesFail, hang: routesHang)),
      catalogPoisProvider.overrideWith(() => FakeRtCatalog(catalog ?? kCatalog, fail: catalogFail, hang: catalogHang)),
      userPoisProvider.overrideWith((ref) async => kUserPois),
      currentLocationProvider.overrideWith((ref) async => me),
      rideRecorderProvider.overrideWith((ref) => FakeRtRecorder(ref, recorder)),
      placesSelectionProvider.overrideWith(() => FakeSelection(selected)),
      selectionRoadRouteProvider.overrideWith((ref, key) async => null),
      routeDisplayProvider.overrideWith((ref, id) async {
        final r = (routes ?? kRtRoutes).firstWhere((x) => x.id == id, orElse: () => kRtRoutes.first);
        return RouteDisplay(geometry: r.waypoints, start: const LatLng(48.9918, 16.6705));
      }),
      routeRealLengthKmProvider.overrideWith((ref, id) async => 41.6),
      routeApproachProvider.overrideWith((ref, id) async => (km: 14.0, min: 14, exact: false)),
      myRidesProvider.overrideWith((ref) async => const []),
      mySavedRoutesProvider.overrideWith((ref) async => const []),
      myPlacesProvider.overrideWith((ref) async => const []),
    ];
