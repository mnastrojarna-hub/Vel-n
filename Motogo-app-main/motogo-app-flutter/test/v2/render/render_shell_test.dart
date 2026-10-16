// verify:render — v2 shell with real tab screens (nav, AI button, strips,
// banner) (large text + reduced motion, 8 languages × 320/360/412).
import 'dart:io';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes_http.dart';
import 'cases_shell.dart';
import 'render_harness.dart';

void main() => renderMatrix(shellRenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      HttpOverrides.global = RtFakeHttpOverrides();
    });
