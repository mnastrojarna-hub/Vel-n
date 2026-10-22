// verify:render — Trasy v2 (large text + reduced motion, 8 languages ×
// 320/360/412). Map tiles answer with a tiny PNG (fake HTTP).
import 'dart:io';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes_http.dart';
import 'cases_routes.dart';
import 'render_harness.dart';

void main() => renderMatrix(routesRenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      HttpOverrides.global = RtFakeHttpOverrides();
    });
