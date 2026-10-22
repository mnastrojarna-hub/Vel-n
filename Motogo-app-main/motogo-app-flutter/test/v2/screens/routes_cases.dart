// Cases of the Trasy v2 matrix (split from routes_test.dart for size).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/features/routes/all_pois_screen.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/routes_screen.dart';

import '../support/fakes_routes.dart';

typedef RtCaseT = (Widget Function(), List<Override> Function());

Map<String, RtCaseT> placesCases() => {
      'list': (() => const AllPoisScreen(asTab: true), () => routesOverrides()),
      'no-location': (() => const AllPoisScreen(asTab: true), () => routesOverrides(me: null)),
      'selection': (
        () => const AllPoisScreen(asTab: true),
        () => routesOverrides(selected: {'catalog:c4', 'catalog:c5', 'r1:p1'}),
      ),
      'recording-manual': (
        () => const AllPoisScreen(asTab: true),
        () => routesOverrides(recorder: const RideRecorderState(recording: true, manual: true, rideId: 'x')),
      ),
      'recording-auto-gps': (
        () => const AllPoisScreen(asTab: true),
        () => routesOverrides(recorder: const RideRecorderState(recording: true, rideId: 'x', bookingId: 'b', gpsLost: true)),
      ),
      'recording-selection': (
        () => const AllPoisScreen(asTab: true),
        () => routesOverrides(
            selected: {'catalog:c1'}, recorder: const RideRecorderState(recording: true, manual: true, rideId: 'x')),
      ),
      'loading': (() => const AllPoisScreen(asTab: true), () => routesOverrides(catalogHang: true)),
      'error': (() => const AllPoisScreen(asTab: true), () => routesOverrides(catalogFail: true, routes: const [])),
      'empty': (() => const AllPoisScreen(asTab: true), () => routesOverrides(catalog: const [], routes: const [])),
      'picker': (
        () => const AllPoisScreen(pickMode: true, initialSelected: {'catalog:c2'}),
        () => routesOverrides(),
      ),
      'from-route': (
        () => const AllPoisScreen(initialSelected: {'r1:p1', 'r1:p2'}),
        () => routesOverrides(),
      ),
    };

Map<String, RtCaseT> routesListCases() => {
      'list': (() => const RoutesScreen(), () => routesOverrides()),
      'no-location': (() => const RoutesScreen(), () => routesOverrides(me: null)),
      'empty': (() => const RoutesScreen(), () => routesOverrides(routes: const [])),
      'error': (() => const RoutesScreen(), () => routesOverrides(routesFail: true)),
      'loading': (() => const RoutesScreen(), () => routesOverrides(routesHang: true)),
    };
