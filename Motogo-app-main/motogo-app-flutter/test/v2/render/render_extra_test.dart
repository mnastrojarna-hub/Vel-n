// verify:render — coverage gaps of the area matrices (route error page,
// POI sheet, Místa / Trasy sheets, detail toggles, rank ramp 0–20).
import 'dart:io';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes_http.dart';
import '../support/supabase_stub.dart';
import 'cases_extra.dart';
import 'render_harness.dart';

void main() => renderMatrix(extraRenderCases(), setUpAllExtra: () async {
      mockPathProvider();
      HttpOverrides.global = RtFakeHttpOverrides();
      await stubSupabase();
    });
