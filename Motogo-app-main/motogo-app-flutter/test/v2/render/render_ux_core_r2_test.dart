// verify:render — fix:r2:core: map tiles failing on every v2 map (large
// text + reduced motion, 8 languages × 320/360/412). Tiles answer with a
// tiny PNG (fake HTTP); the failure is preset.
import 'dart:io';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes_http.dart';
import 'cases_ux_core_r2.dart';
import 'render_harness.dart';

void main() => renderMatrix(coreR2RenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      HttpOverrides.global = RtFakeHttpOverrides();
    });
