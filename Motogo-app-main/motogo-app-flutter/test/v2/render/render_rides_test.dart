// verify:render — Jízdy v2 (large text + reduced motion, 8 languages ×
// 320/360/412). Map tiles answer with a tiny PNG (fake HTTP).
import 'dart:io';

import '../screens/rides_cases.dart' show ridesMockPathProvider;
import '../support/fakes_routes_http.dart';
import 'cases_rides.dart';
import 'render_harness.dart';

void main() => renderMatrix(ridesRenderCases(), setUpAllExtra: () async {
      ridesMockPathProvider();
      HttpOverrides.global = RtFakeHttpOverrides();
    });
